# Kuduso API (FastAPI)

External-facing API for job submission and result retrieval.

## Features

- **Job submission**: `POST /jobs/run` with contract-based validation
- **Status polling**: `GET /jobs/status/{job_id}`
- **Result retrieval**: `GET /jobs/result/{job_id}`
- **Correlation tracking**: Propagates `x-correlation-id` headers
- **CORS enabled**: For local frontend development

## Stage 1 vs Future

**Stage 1 (current)**: 
- In-memory job storage
- Synchronous AppServer calls
- Simple dictionary-based state

**Stage 2+**:
- Service Bus producer (enqueue jobs)
- Database persistence (Supabase)
- Asynchronous processing via workers

## API Endpoints

### `POST /jobs/run`

Submit a computational job.

**Request:**
```json
{
  "app_id": "sitefit",
  "definition": "sitefit",
  "version": "1.0.0",
  "inputs": {
    "crs": "EPSG:5514",
    "parcel": { "coordinates": [[0,0], [20,0], [20,30], [0,30], [0,0]] },
    "house": { "coordinates": [[0,0], [10,0], [10,8], [0,8], [0,0]] }
  }
}
```

**Response:**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "succeeded",
  "correlation_id": "abc-123"
}
```

### `GET /jobs/status/{job_id}`

Get job status.

**Response:**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "succeeded",
  "has_result": true,
  "created_at": "2025-10-23T14:30:00Z",
  "correlation_id": "abc-123"
}
```

### `GET /jobs/result/{job_id}`

Get job result (only when status is `succeeded`).

**Response:** Matches `contracts/{definition}/{version}/outputs.schema.json`

### `GET /health`

Health check.

### `GET /jobs`

List all jobs (debug endpoint for Stage 1 only).

## Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run development server
uvicorn main:app --reload --port 8081

# Or use make
make dev-api
```

## Usage

```bash
# Submit a job
curl -X POST http://localhost:8081/jobs/run \
  -H "Content-Type: application/json" \
  -d @job_payload.json

# Check status
curl http://localhost:8081/jobs/status/{job_id}

# Get result
curl http://localhost:8081/jobs/result/{job_id}
```

## Error Responses

- `400` - Invalid request envelope or input validation failed
- `404` - Job not found
- `409` - Job not ready (still running or failed)
- `504` - AppServer unreachable
