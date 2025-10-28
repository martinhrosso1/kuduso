"""
Kuduso Worker - Job Consumer
Stage 3: Service Bus consumer with database persistence
"""

import os
import asyncio
import logging
import json
import httpx
from datetime import datetime
from typing import Dict, Any, Optional
from azure.servicebus import ServiceBusClient, ServiceBusReceiver
from azure.servicebus import ServiceBusMessage
from fastapi import FastAPI
import threading

from config import (
    SERVICEBUS_CONN,
    SERVICEBUS_QUEUE,
    APP_SERVER_URL,
    LOCK_RENEW_SEC,
    JOB_TIMEOUT_SEC,
    MAX_ATTEMPTS
)
from database import db

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}'
)
logger = logging.getLogger(__name__)

# FastAPI app (for health checks)
app = FastAPI(title="Kuduso Worker", version="0.3.0-stage3")

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "worker-stage3"}


class JobProcessor:
    """Process jobs from Service Bus queue"""
    
    def __init__(self):
        self.client = ServiceBusClient.from_connection_string(SERVICEBUS_CONN)
        self.receiver: ServiceBusReceiver = self.client.get_queue_receiver(SERVICEBUS_QUEUE)
        self.running = False
        
    def process_message(self, message: ServiceBusMessage) -> None:
        """Process a single message"""
        try:
            # Parse message
            body = json.loads(str(message))
            job_id = body.get("job_id")
            correlation_id = body.get("correlation_id") or message.application_properties.get("x-correlation-id", "unknown")
            
            logger.info(json.dumps({
                "event": "job.claim",
                "job_id": job_id,
                "correlation_id": correlation_id
            }))
            
            # Check if we should process this job
            attempts = db.get_job_attempts(job_id)
            if attempts >= MAX_ATTEMPTS:
                logger.error(json.dumps({
                    "event": "job.max_attempts",
                    "job_id": job_id,
                    "attempts": attempts
                }))
                # Dead letter the message
                self.receiver.dead_letter_message(
                    message,
                    reason="MaxAttemptsReached",
                    error_description=f"Job exceeded maximum attempts ({MAX_ATTEMPTS})"
                )
                return
            
            # Update job status to running
            db.update_job_status(
                job_id=job_id,
                status="running",
                started_at=datetime.utcnow(),
                increment_attempts=True
            )
            
            # Start lock renewal in background
            lock_renewal_task = threading.Thread(
                target=self._renew_lock,
                args=(message, job_id),
                daemon=True
            )
            lock_renewal_task.start()
            
            try:
                # Call AppServer
                result = self._call_appserver(
                    job_id=job_id,
                    definition=body.get("definition"),
                    version=body.get("version"),
                    payload=body.get("payload"),
                    correlation_id=correlation_id
                )
                
                # Insert result
                db.insert_result(
                    job_id=job_id,
                    outputs_json=result,
                    score=result.get("score")  # If AppServer returns a score
                )
                
                # Update job status
                db.update_job_status(
                    job_id=job_id,
                    status="succeeded",
                    ended_at=datetime.utcnow()
                )
                
                # Complete the message
                self.receiver.complete_message(message)
                
                logger.info(json.dumps({
                    "event": "job.succeeded",
                    "job_id": job_id,
                    "correlation_id": correlation_id
                }))
                
            except httpx.HTTPStatusError as e:
                # HTTP error from AppServer
                if e.response.status_code in [429, 503]:
                    # Transient error - abandon for retry
                    logger.warning(json.dumps({
                        "event": "job.transient_error",
                        "job_id": job_id,
                        "status_code": e.response.status_code,
                        "correlation_id": correlation_id
                    }))
                    
                    db.update_job_status(job_id=job_id, status="queued")
                    self.receiver.abandon_message(message)
                    
                else:
                    # Permanent error - dead letter
                    error_detail = {
                        "type": "appserver_error",
                        "status_code": e.response.status_code,
                        "message": str(e),
                        "timestamp": datetime.utcnow().isoformat()
                    }
                    
                    db.update_job_error(job_id=job_id, error=error_detail)
                    
                    self.receiver.dead_letter_message(
                        message,
                        reason="AppServerError",
                        error_description=str(e)
                    )
                    
                    logger.error(json.dumps({
                        "event": "job.failed",
                        "job_id": job_id,
                        "error": error_detail,
                        "correlation_id": correlation_id
                    }))
                    
            except Exception as e:
                # Unexpected error
                logger.error(json.dumps({
                    "event": "job.error",
                    "job_id": job_id,
                    "error": str(e),
                    "correlation_id": correlation_id
                }))
                
                error_detail = {
                    "type": "processing_error",
                    "message": str(e),
                    "timestamp": datetime.utcnow().isoformat()
                }
                
                db.update_job_error(job_id=job_id, error=error_detail)
                
                # Abandon for retry
                db.update_job_status(job_id=job_id, status="queued")
                self.receiver.abandon_message(message)
            
        except Exception as e:
            logger.error(f"Failed to process message: {e}")
            # Abandon message so it can be retried
            try:
                self.receiver.abandon_message(message)
            except:
                pass
    
    def _call_appserver(
        self,
        job_id: str,
        definition: str,
        version: str,
        payload: Dict[str, Any],
        correlation_id: str
    ) -> Dict[str, Any]:
        """Call AppServer to process job"""
        url = APP_SERVER_URL.format(definition=definition, version=version)
        headers = {"x-correlation-id": correlation_id}
        
        logger.debug(json.dumps({
            "event": "appserver.call",
            "job_id": job_id,
            "url": url,
            "correlation_id": correlation_id
        }))
        
        with httpx.Client(timeout=JOB_TIMEOUT_SEC) as client:
            response = client.post(url, json=payload, headers=headers)
            response.raise_for_status()
            return response.json()
    
    def _renew_lock(self, message: ServiceBusMessage, job_id: str) -> None:
        """Renew message lock periodically"""
        try:
            import time
            while True:
                time.sleep(LOCK_RENEW_SEC)
                try:
                    self.receiver.renew_message_lock(message)
                    logger.debug(f"Lock renewed for job {job_id}")
                except Exception as e:
                    logger.warning(f"Failed to renew lock for job {job_id}: {e}")
                    break
        except Exception as e:
            logger.error(f"Lock renewal error for job {job_id}: {e}")
    
    def run(self) -> None:
        """Main worker loop"""
        self.running = True
        logger.info("Worker started - waiting for messages...")
        
        try:
            while self.running:
                # Receive one message at a time
                messages = self.receiver.receive_messages(max_message_count=1, max_wait_time=5)
                
                for message in messages:
                    self.process_message(message)
                
        except KeyboardInterrupt:
            logger.info("Worker interrupted")
        except Exception as e:
            logger.error(f"Worker error: {e}")
        finally:
            self.close()
    
    def close(self) -> None:
        """Close connections"""
        self.running = False
        self.receiver.close()
        self.client.close()
        logger.info("Worker connections closed")


# Global processor instance
processor = None


def run_worker_sync():
    """Run worker in synchronous mode"""
    global processor
    processor = JobProcessor()
    processor.run()


if __name__ == "__main__":
    import uvicorn
    
    # Start health check server in background thread
    def start_health_server():
        config = uvicorn.Config(
            app,
            host="0.0.0.0",
            port=8080,
            log_config=None
        )
        server = uvicorn.Server(config)
        asyncio.run(server.serve())
    
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    
    # Run worker in main thread
    logger.info("Starting worker process...")
    run_worker_sync()
