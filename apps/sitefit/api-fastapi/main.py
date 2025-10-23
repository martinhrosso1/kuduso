"""
Kuduso API - External FastAPI service
Handles job submission, status, and result retrieval

Stage 1: In-memory storage with synchronous AppServer calls
Stage 2+: Service Bus producer with database persistence
"""

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import httpx
import hashlib
import json
import uuid
import logging
from datetime import datetime

from models import RunEnvelope, JobStatusResponse, HealthResponse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s", "logger": "%(name)s"}'
)
logger = logging.getLogger(__name__)

# Configuration
APP_SERVER_URL = "http://localhost:8080/gh/{def}:{ver}/solve"
TIMEOUT_SECONDS = 10.0

# In-memory job storage (Stage 1 only)
jobs: dict[str, dict] = {}

# FastAPI app
app = FastAPI(
    title="Kuduso API",
    description="External API for job submission and result retrieval",
    version="0.1.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # Frontend origin
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
    return {
        "status": "ok",
        "service": "api-fastapi",
        "storage": "in-memory",
        "jobs_count": len(jobs)
    }


@app.post("/jobs/run")
async def run_job(
    envelope: RunEnvelope,
    x_correlation_id: Optional[str] = Header(default=None)
):
    """
    Submit a job for execution
    
    Stage 1: Synchronously calls AppServer
    Stage 2+: Will enqueue to Service Bus
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

    # Compute inputs hash for idempotency
    inputs_hash = compute_inputs_hash(envelope.inputs, envelope.definition, envelope.version)
    
    # Initialize job
    jobs[job_id] = {
        "status": "running",
        "app_id": envelope.app_id,
        "definition": envelope.definition,
        "version": envelope.version,
        "inputs_hash": inputs_hash,
        "correlation_id": cid,
        "created_at": datetime.utcnow().isoformat(),
        "started_at": datetime.utcnow().isoformat()
    }

    # Synchronous call to AppServer (Stage 1 only)
    url = APP_SERVER_URL.format(def=envelope.definition, ver=envelope.version)
    headers = {"x-correlation-id": cid}

    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            logger.debug(json.dumps({
                "event": "appserver.call",
                "job_id": job_id,
                "correlation_id": cid,
                "url": url
            }))
            
            resp = await client.post(url, json=envelope.inputs, headers=headers)
            
        if resp.status_code != 200:
            error_detail = resp.json() if resp.headers.get("content-type") == "application/json" else resp.text
            jobs[job_id].update({
                "status": "failed",
                "error": error_detail,
                "ended_at": datetime.utcnow().isoformat()
            })
            
            logger.error(json.dumps({
                "event": "job.failed",
                "job_id": job_id,
                "correlation_id": cid,
                "status_code": resp.status_code,
                "error": str(error_detail)
            }))
            
            raise HTTPException(status_code=resp.status_code, detail=error_detail)
        
        result = resp.json()
        jobs[job_id].update({
            "status": "succeeded",
            "result": result,
            "ended_at": datetime.utcnow().isoformat()
        })
        
        logger.info(json.dumps({
            "event": "job.succeeded",
            "job_id": job_id,
            "correlation_id": cid,
            "results_count": len(result.get("results", []))
        }))
        
        return {
            "job_id": job_id,
            "status": "succeeded",
            "correlation_id": cid
        }
        
    except httpx.RequestError as e:
        jobs[job_id].update({
            "status": "failed",
            "error": f"AppServer unreachable: {str(e)}",
            "ended_at": datetime.utcnow().isoformat()
        })
        
        logger.error(json.dumps({
            "event": "job.failed",
            "job_id": job_id,
            "correlation_id": cid,
            "error": "AppServer unreachable",
            "details": str(e)
        }))
        
        raise HTTPException(status_code=504, detail="AppServer unreachable")


@app.get("/jobs/status/{job_id}", response_model=JobStatusResponse)
async def get_job_status(job_id: str):
    """Get job status"""
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    return {
        "job_id": job_id,
        "status": job["status"],
        "has_result": "result" in job,
        "created_at": job.get("created_at"),
        "correlation_id": job.get("correlation_id")
    }


@app.get("/jobs/result/{job_id}")
async def get_job_result(job_id: str):
    """Get job result"""
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    if job["status"] != "succeeded":
        raise HTTPException(
            status_code=409,
            detail=f"Job not ready. Status: {job['status']}"
        )
    
    if "result" not in job:
        raise HTTPException(status_code=404, detail="Result not found")
    
    return job["result"]


@app.get("/jobs")
async def list_jobs():
    """List all jobs (debug endpoint for Stage 1)"""
    return {
        "jobs": [
            {
                "job_id": job_id,
                "status": job["status"],
                "definition": job.get("definition"),
                "created_at": job.get("created_at")
            }
            for job_id, job in jobs.items()
        ],
        "total": len(jobs)
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081)
