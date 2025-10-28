"""Service Bus queue producer"""
import json
import logging
from datetime import datetime
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from typing import Dict, Any, Optional

from config import SERVICEBUS_CONN, SERVICEBUS_QUEUE

logger = logging.getLogger(__name__)


class QueueProducer:
    """Service Bus queue producer for job messages"""
    
    def __init__(self):
        self.conn_string = SERVICEBUS_CONN
        self.queue_name = SERVICEBUS_QUEUE
        
    def enqueue_job(
        self,
        job_id: str,
        tenant_id: Optional[str],
        app_id: str,
        definition: str,
        version: str,
        inputs_hash: str,
        payload: Dict[str, Any],
        correlation_id: str,
        priority: int = 100
    ) -> None:
        """Enqueue a job message to Service Bus"""
        
        message_body = {
            "job_id": job_id,
            "tenant_id": tenant_id,
            "app_id": app_id,
            "definition": definition,
            "version": version,
            "inputs_hash": inputs_hash,
            "requested_at": datetime.utcnow().isoformat(),
            "payload": payload,
            "priority": priority
        }
        
        try:
            with ServiceBusClient.from_connection_string(self.conn_string) as client:
                with client.get_queue_sender(self.queue_name) as sender:
                    # Create message with application properties
                    message = ServiceBusMessage(
                        body=json.dumps(message_body),
                        application_properties={
                            "x-correlation-id": correlation_id,
                            "job_id": job_id,
                            "app_id": app_id,
                            "definition": definition,
                            "version": version
                        }
                    )
                    
                    sender.send_messages(message)
                    
            logger.info(json.dumps({
                "event": "queue.enqueued",
                "job_id": job_id,
                "correlation_id": correlation_id,
                "queue": self.queue_name
            }))
            
        except Exception as e:
            logger.error(json.dumps({
                "event": "queue.enqueue_failed",
                "job_id": job_id,
                "correlation_id": correlation_id,
                "error": str(e)
            }))
            raise


# Global queue producer instance
queue_producer = QueueProducer()
