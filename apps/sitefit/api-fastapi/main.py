"""
Kuduso API - External FastAPI service
Handles job submission, status, and result retrieval

Stage 3: Service Bus producer with Supabase database persistence
"""

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import hashlib
import json
import uuid
import logging
from datetime import datetime

from models import RunEnvelope, JobStatusResponse, HealthResponse
from database import db
from job_queue import queue_producer
from config import DATABASE_URL, SERVICEBUS_CONN, SERVICEBUS_QUEUE

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s", "logger": "%(name)s"}'
)
logger = logging.getLogger(__name__)

# FastAPI app
app = FastAPI(
    title="Kuduso API",
    description="External API for job submission and result retrieval",
    version="0.3.0-stage3"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:3001", 
        "http://localhost:3002",
        "http://localhost:3003",
        "https://*.vercel.app"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def compute_inputs_hash(payload: dict, definition: str, version: str) -> str:
    """Compute deterministic hash of inputs for idempotency"""
    normalized = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    combined = f"{normalized}{definition}{version}"
    return hashlib.sha256(combined.encode()).hexdigest()


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    # Test database connection
    try:
        conn = db.get_connection()
        conn.close()
        db_status = "connected"
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        db_status = "disconnected"
    
    return {
        "status": "ok" if db_status == "connected" else "degraded",
        "service": "api-fastapi-stage3",
        "storage": f"supabase-{db_status}",
        "jobs_count": 0  # Could query actual count if needed
    }


@app.post("/jobs/run")
async def run_job(
    envelope: RunEnvelope,
    x_correlation_id: Optional[str] = Header(default=None)
):
    """
    Submit a job for execution
    
    Stage 3: Enqueues to Service Bus, writes to database
    """
    cid = x_correlation_id or str(uuid.uuid4())
    job_id = str(uuid.uuid4())
    
    logger.info(json.dumps({
        "event": "job.submit",
        "job_id": job_id,
        "correlation_id": cid,
        "app_id": envelope.app_id,
        "definition": envelope.definition,
        "version": envelope.version
    }))

    # TODO: Validate inputs against contract schema
    # TODO: Materialize defaults from schema
    
    # Compute inputs hash for idempotency
    inputs_hash = compute_inputs_hash(envelope.inputs, envelope.definition, envelope.version)
    
    # Check for duplicate (optional idempotency)
    existing = db.check_duplicate_by_hash(inputs_hash)
    if existing and existing['status'] == 'succeeded':
        logger.info(json.dumps({
            "event": "job.duplicate",
            "job_id": job_id,
            "existing_job_id": existing['job_id'],
            "correlation_id": cid
        }))
        return {
            "job_id": existing['job_id'],
            "status": "succeeded",
            "correlation_id": cid,
            "cached": True
        }
    
    try:
        # Insert job into database
        db.insert_job(
            job_id=job_id,
            tenant_id=None,  # TODO: Extract from JWT when auth is implemented
            app_id=envelope.app_id,
            definition=envelope.definition,
            version=envelope.version,
            inputs_hash=inputs_hash,
            payload_json=envelope.inputs
        )
        
        # Enqueue to Service Bus
        queue_producer.enqueue_job(
            job_id=job_id,
            tenant_id=None,
            app_id=envelope.app_id,
            definition=envelope.definition,
            version=envelope.version,
            inputs_hash=inputs_hash,
            payload=envelope.inputs,
            correlation_id=cid,
            priority=100
        )
        
        logger.info(json.dumps({
            "event": "job.enqueued",
            "job_id": job_id,
            "correlation_id": cid
        }))
        
        return {
            "job_id": job_id,
            "status": "queued",
            "correlation_id": cid
        }
        
    except Exception as e:
        logger.error(json.dumps({
            "event": "job.submit_failed",
            "job_id": job_id,
            "correlation_id": cid,
            "error": str(e)
        }))
        raise HTTPException(status_code=500, detail=f"Failed to submit job: {str(e)}")


@app.get("/jobs/status/{job_id}", response_model=JobStatusResponse)
async def get_job_status(job_id: str):
    """Get job status from database"""
    try:
        job = db.get_job_status(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        
        return {
            "job_id": job['job_id'],
            "status": job['status'],
            "has_result": job['status'] == 'succeeded',
            "created_at": job.get('created_at').isoformat() if job.get('created_at') else None,
            "correlation_id": None  # TODO: Store correlation_id in job table
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get job status: {e}")
        raise HTTPException(status_code=500, detail="Failed to get job status")


@app.get("/jobs/result/{job_id}")
async def get_job_result(job_id: str):
    """Get job result from database"""
    try:
        job = db.get_job_result(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        
        if job['status'] != 'succeeded':
            raise HTTPException(
                status_code=409,
                detail=f"Job not ready. Status: {job['status']}"
            )
        
        if not job.get('outputs_json'):
            raise HTTPException(status_code=404, detail="Result not found")
        
        return job['outputs_json']
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get job result: {e}")
        raise HTTPException(status_code=500, detail="Failed to get job result")


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "kuduso-api",
        "stage": "3-messaging-persistence",
        "version": "0.3.0",
        "database": "supabase" if DATABASE_URL else "not_configured",
        "queue": SERVICEBUS_QUEUE if SERVICEBUS_CONN else "not_configured"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
