"""
Pydantic models for API request/response envelopes
"""

from pydantic import BaseModel, Field
from typing import Optional, Dict, Any


class RunEnvelope(BaseModel):
    """Job submission envelope"""
    app_id: str = Field(..., description="Application identifier")
    definition: str = Field(..., description="Contract definition name")
    version: str = Field(..., description="Contract version (semver)")
    inputs: Dict[str, Any] = Field(..., description="Input payload matching contract schema")

    model_config = {
        "json_schema_extra": {
            "example": {
                "app_id": "sitefit",
                "definition": "sitefit",
                "version": "1.0.0",
                "inputs": {
                    "crs": "EPSG:5514",
                    "parcel": {
                        "coordinates": [[0, 0], [20, 0], [20, 30], [0, 30], [0, 0]]
                    },
                    "house": {
                        "coordinates": [[0, 0], [10, 0], [10, 8], [0, 8], [0, 0]]
                    },
                    "seed": 42
                }
            }
        }
    }


class JobStatusResponse(BaseModel):
    """Job status response"""
    job_id: str
    status: str = Field(..., description="Job status: running, succeeded, failed")
    has_result: bool = Field(..., description="Whether result is available")
    created_at: Optional[str] = None
    correlation_id: Optional[str] = None


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    service: str
    storage: str
    jobs_count: int
