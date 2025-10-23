"""
End-to-end tests for Stage 1 mock compute loop

Tests the complete flow:
1. Submit job via API
2. API calls AppServer
3. AppServer validates and returns mock result
4. API stores and returns result
"""

import pytest
import httpx
import json
import os
from pathlib import Path

API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8081")
APPSERVER_URL = os.getenv("APPSERVER_URL", "http://localhost:8080")
CONTRACTS_DIR = Path(__file__).parent.parent.parent / "contracts"


def load_example(definition: str, version: str, example_type: str, filename: str):
    """Load example payload from contracts"""
    path = CONTRACTS_DIR / definition / version / "examples" / example_type / filename
    with open(path) as f:
        return json.load(f)


@pytest.mark.asyncio
async def test_happy_path_valid_input():
    """Test successful job submission with valid input"""
    
    # Load valid example from contracts
    inputs = load_example("sitefit", "1.0.0", "valid", "minimal.json")
    
    async with httpx.AsyncClient() as client:
        # Submit job
        response = await client.post(
            f"{API_BASE_URL}/jobs/run",
            json={
                "app_id": "sitefit",
                "definition": "sitefit",
                "version": "1.0.0",
                "inputs": inputs
            },
            timeout=10.0
        )
        
        assert response.status_code == 200
        data = response.json()
        
        assert "job_id" in data
        assert "status" in data
        assert data["status"] == "succeeded"  # Stage 1: synchronous
        
        job_id = data["job_id"]
        
        # Get status
        status_response = await client.get(f"{API_BASE_URL}/jobs/status/{job_id}")
        assert status_response.status_code == 200
        status_data = status_response.json()
        
        assert status_data["status"] == "succeeded"
        assert status_data["has_result"] is True
        
        # Get result
        result_response = await client.get(f"{API_BASE_URL}/jobs/result/{job_id}")
        assert result_response.status_code == 200
        result_data = result_response.json()
        
        # Validate result structure
        assert "results" in result_data
        assert len(result_data["results"]) > 0
        assert "artifacts" in result_data
        assert "metadata" in result_data
        
        # Check first result has required fields
        first_result = result_data["results"][0]
        assert "transform" in first_result
        assert "score" in first_result
        assert "metrics" in first_result


@pytest.mark.asyncio
async def test_invalid_input_missing_required():
    """Test job submission with missing required field"""
    
    # Load invalid example
    inputs = load_example("sitefit", "1.0.0", "invalid", "missing-required.json")
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{API_BASE_URL}/jobs/run",
            json={
                "app_id": "sitefit",
                "definition": "sitefit",
                "version": "1.0.0",
                "inputs": inputs
            },
            timeout=10.0
        )
        
        # Should fail validation
        assert response.status_code == 400
        error_data = response.json()
        assert "detail" in error_data or "message" in error_data


@pytest.mark.asyncio
async def test_invalid_input_bad_crs():
    """Test job submission with invalid CRS format"""
    
    inputs = load_example("sitefit", "1.0.0", "invalid", "bad-crs.json")
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{API_BASE_URL}/jobs/run",
            json={
                "app_id": "sitefit",
                "definition": "sitefit",
                "version": "1.0.0",
                "inputs": inputs
            },
            timeout=10.0
        )
        
        # Should fail validation
        assert response.status_code == 400


@pytest.mark.asyncio
async def test_appserver_direct_call():
    """Test calling AppServer directly (bypassing API)"""
    
    inputs = load_example("sitefit", "1.0.0", "valid", "minimal.json")
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{APPSERVER_URL}/gh/sitefit:1.0.0/solve",
            json=inputs,
            headers={"x-correlation-id": "test-direct-call"},
            timeout=10.0
        )
        
        assert response.status_code == 200
        result = response.json()
        
        # Check correlation ID is echoed
        assert response.headers.get("x-correlation-id") == "test-direct-call"
        
        # Validate structure
        assert "results" in result
        assert "metadata" in result
        assert result["metadata"]["definition"] == "sitefit"
        assert result["metadata"]["version"] == "1.0.0"


@pytest.mark.asyncio
async def test_correlation_id_propagation():
    """Test that correlation IDs flow through the system"""
    
    inputs = load_example("sitefit", "1.0.0", "valid", "minimal.json")
    test_cid = "test-correlation-123"
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{API_BASE_URL}/jobs/run",
            json={
                "app_id": "sitefit",
                "definition": "sitefit",
                "version": "1.0.0",
                "inputs": inputs
            },
            headers={"x-correlation-id": test_cid},
            timeout=10.0
        )
        
        assert response.status_code == 200
        data = response.json()
        
        # API should return the correlation ID
        assert data.get("correlation_id") == test_cid


@pytest.mark.asyncio
async def test_health_endpoints():
    """Test health check endpoints"""
    
    async with httpx.AsyncClient() as client:
        # API health
        api_health = await client.get(f"{API_BASE_URL}/health")
        assert api_health.status_code == 200
        api_data = api_health.json()
        assert api_data["status"] == "ok"
        assert api_data["service"] == "api-fastapi"
        
        # AppServer health
        appserver_health = await client.get(f"{APPSERVER_URL}/health")
        assert appserver_health.status_code == 200
        appserver_data = appserver_health.json()
        assert appserver_data["status"] == "ok"
        assert appserver_data["service"] == "appserver-node"


@pytest.mark.asyncio
async def test_deterministic_results():
    """Test that same seed produces same results"""
    
    inputs = load_example("sitefit", "1.0.0", "valid", "typical.json")
    
    async with httpx.AsyncClient() as client:
        # Run twice with same seed
        results = []
        for _ in range(2):
            response = await client.post(
                f"{API_BASE_URL}/jobs/run",
                json={
                    "app_id": "sitefit",
                    "definition": "sitefit",
                    "version": "1.0.0",
                    "inputs": inputs
                },
                timeout=10.0
            )
            
            assert response.status_code == 200
            job_id = response.json()["job_id"]
            
            result_response = await client.get(f"{API_BASE_URL}/jobs/result/{job_id}")
            result = result_response.json()
            results.append(result)
        
        # Compare results (should be identical for same seed)
        assert results[0]["results"][0]["transform"] == results[1]["results"][0]["transform"]
        assert results[0]["metadata"]["seed"] == results[1]["metadata"]["seed"]
