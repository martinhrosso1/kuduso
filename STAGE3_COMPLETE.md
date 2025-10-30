# 🎉 Stage 3 COMPLETE - Messaging & Persistence

**Completion Date**: October 30, 2025  
**Duration**: ~6 hours (with networking debugging)  
**Status**: ✅ **100% WORKING - Full E2E Job Processing**

---

## 🎯 Stage 3 Goal

Replace in-memory/local components with **Service Bus + Supabase**, while keeping AppServer in **mock mode**. Enable full asynchronous job processing with proper database persistence and message queuing.

---

## ✅ What We Built

### 1. **Database Layer** (Supabase PostgreSQL + Alembic)

**Tables Created:**
- `job` - Job metadata, status tracking, attempts, errors
- `result` - Computation results (placements, KPIs, scores)
- `artifact` - Artifact metadata (links to blob storage)
- `job_with_result` - View joining jobs and results

**Features:**
- ✅ UUID primary keys with proper indexes
- ✅ JSONB columns for flexible payloads
- ✅ Status tracking: `queued` → `running` → `succeeded`/`failed`
- ✅ Alembic migrations for version control
- ✅ Proper foreign key relationships

**Files:**
```
apps/sitefit/migrations/
├── alembic.ini
├── env.py
└── versions/
    └── 001_initial_schema.py
```

### 2. **API (FastAPI)** - External HTTP + Service Bus Producer

**Endpoints Implemented:**
- `POST /jobs/run` - Submit job with idempotency (inputs_hash)
- `GET /jobs/status/{id}` - Real-time status tracking
- `GET /jobs/result/{id}` - Fetch computation results
- `GET /health` - Database connectivity check

**Key Features:**
- ✅ Service Bus message enqueueing
- ✅ Database persistence on all operations
- ✅ Proper error handling and logging
- ✅ JSON structured logging

**Technology:**
- FastAPI + SQLAlchemy + azure-servicebus
- Deployed to Azure Container Apps (external ingress)

### 3. **Worker (FastAPI)** - Service Bus Consumer

**Core Logic:**
- ✅ Service Bus queue consumer (peek-lock pattern)
- ✅ Message processing with retry logic
- ✅ Lock renewal during long-running jobs (45s intervals)
- ✅ Database status updates throughout lifecycle
- ✅ Dead-letter handling for poison messages
- ✅ Max attempts enforcement (5 attempts)
- ✅ AppServer HTTP client integration

**Worker Flow:**
1. Poll queue with 5s wait time
2. Claim job → Update status to `running`
3. Call AppServer `/gh/{definition}:{version}/solve`
4. Persist results to database
5. Complete message (or abandon on error)

**Technology:**
- FastAPI + httpx + azure-servicebus
- Deployed to Azure Container Apps (internal only)
- KEDA scaling (0-10 replicas based on queue depth)

### 4. **AppServer Updates**

**Enhancements:**
- ✅ Added `/ready` endpoint for Container Apps readiness probe
- ✅ Contracts directory properly included in Docker image
- ✅ `CONTRACTS_DIR=/app/contracts` environment variable
- ✅ Schema validation working with real contracts

---

## 🐛 Major Issues Encountered & Solutions

### Issue #1: Service Bus Queue Didn't Exist

**Symptom:**
```bash
az servicebus queue show --name sitefit-queue
ERROR: (EntityNotFound) Queue does not exist
```

**Root Cause:**
- Terraform state showed queue existed
- Azure API said it didn't exist
- State drift between Terraform and actual infrastructure

**Solution:**
1. Removed queue from Terraform state
2. Re-ran `terragrunt apply` to recreate queue
3. Queue created successfully with proper configuration

**Learning:** Always verify cloud resources exist beyond Terraform state

---

### Issue #2: Worker Receiving 0 Messages from Queue

**Symptom:**
```python
{"event": "worker.received", "message_count": 0, "iteration": 42}
```
Queue showed 1 active message, but worker couldn't receive it.

**Root Cause:**
Service Bus queue didn't exist (see Issue #1). Worker was polling a non-existent queue without errors.

**Solution:**
After recreating queue, worker immediately started receiving messages.

**Learning:** Azure SDK silently handles missing resources; verify resource existence independently

---

### Issue #3: AppServer Internal Networking - The Big One! 🔥

**Symptom:**
```python
{"event": "job.failed", "error": "Request timeout after 240s"}
```
Worker could not connect to AppServer's internal FQDN:
```
http://kuduso-dev-appserver.internal.blackwave-77d88b66.westeurope.azurecontainerapps.io
```

**Investigation Steps:**

1. ✅ **Verified all apps in same Container Apps Environment**
   ```bash
   API, Worker, AppServer all in: kuduso-dev-aca-env
   ```

2. ✅ **Confirmed AppServer was running**
   ```bash
   provisioningState: "Succeeded"
   runningStatus: "Running"
   replicas: 2
   ```

3. ❌ **Found AppServer was unhealthy**
   ```bash
   healthState: "Unhealthy"
   ```

**Sub-Issue 3.1: Missing Readiness Endpoint**

**Root Cause:**
AppServer had `/health` but readiness probe expected `/ready`

**Solution:**
Added `/ready` endpoint to `shared/appserver-node/src/index.ts`:
```typescript
app.get('/ready', (req: Request, res: Response) => {
  res.json({ status: 'ready', service: 'appserver-node' });
});
```

**Sub-Issue 3.2: Terraform Attribute Name**

**Symptom:**
```
Error: Unsupported argument "allow_insecure" is not expected here
```

**Root Cause:**
Used wrong attribute name. Correct one is `allow_insecure_connections`

**Solution:**
Updated `infra/modules/shared-appserver/main.tf`:
```hcl
ingress {
  external_enabled           = false
  target_port                = 8080
  allow_insecure_connections = true  # Allow HTTP for internal communication
}
```

**Sub-Issue 3.3: HTTP Connection Still Timing Out**

**After fixes above, still got:**
```
HTTP Request: POST http://...appserver.../gh/sitefit:1.0.0/solve "HTTP/1.1 404 Not Found"
```

🎉 **BREAKTHROUGH:** Connection worked! Got 404 instead of timeout.

**Sub-Issue 3.4: AppServer "Contract not found: sitefit@1.0.0"**

**Root Cause #1:** Contracts not in Docker image

**Solution:**
Fixed `shared/appserver-node/Dockerfile`:
```dockerfile
# Build from repo root to access contracts
COPY contracts ./contracts
```

Built from repo root:
```bash
docker build -f shared/appserver-node/Dockerfile -t appserver-node:6282cdd .
```

**Root Cause #2:** Wrong contracts path in container

**Solution:**
Added environment variable in Terraform:
```hcl
env {
  name  = "CONTRACTS_DIR"
  value = "/app/contracts"
}
```

**Final Result:**
```json
🎉 {"event": "solve.success", "duration_ms": 15}
```

**Total Time to Debug:** ~4 hours  
**Key Learning:** Internal networking in Container Apps requires:
- Proper health probes (`/health` and `/ready`)
- `allow_insecure_connections: true` for HTTP
- Correct image includes all runtime dependencies
- Environment variables pointing to correct paths

---

### Issue #4: Docker Build Context Path Issues

**Symptom:**
```
ERROR: COPY package*.json ./ - file not found
```

**Root Cause:**
Dockerfile paths assumed building from `shared/appserver-node/`, but we needed to build from repo root to access `contracts/` directory.

**Solution:**
Updated all COPY paths in Dockerfile:
```dockerfile
# Before
COPY package*.json ./
COPY . .

# After
COPY shared/appserver-node/package*.json ./
COPY shared/appserver-node/ ./
COPY contracts ./contracts
```

Build command:
```bash
docker build -f shared/appserver-node/Dockerfile -t appserver-node:TAG .
```

---

## 🎯 End-to-End Flow (Working!)

### Request Flow

```
1. Client → POST /jobs/run
   ├─ Validate inputs
   ├─ Compute inputs_hash
   ├─ Insert job record (status: queued)
   ├─ Enqueue Service Bus message
   └─ Return 202 {job_id}

2. Service Bus Queue
   └─ Message stored with peek-lock

3. Worker polls queue
   ├─ Receive message (5s wait)
   ├─ Claim job → Update status: running
   ├─ POST to AppServer /gh/sitefit:1.0.0/solve
   │  ├─ Load contracts from /app/contracts/sitefit/1.0.0/
   │  ├─ Validate inputs against schema
   │  ├─ Execute mock solver
   │  ├─ Validate outputs against schema
   │  └─ Return 200 {results, metadata}
   ├─ Insert result record
   ├─ Update job status: succeeded
   └─ Complete Service Bus message

4. Client → GET /jobs/result/{id}
   └─ Return result from database
```

### Actual Working Test

**Request:**
```bash
curl -X POST .../jobs/run \
  -d '{
    "app_id": "sitefit",
    "definition": "sitefit",
    "version": "1.0.0",
    "inputs": {
      "crs": "EPSG:5514",
      "parcel": {"coordinates": [[0, 0], [20, 0], [20, 30], [0, 30], [0, 0]]},
      "house": {"coordinates": [[0, 0], [10, 0], [10, 8], [0, 8], [0, 0]]},
      "seed": 999
    }
  }'
```

**Response (1 second later):**
```json
{
  "results": [{
    "id": "result-999",
    "score": 94.5,
    "transform": {
      "rotation": {"axis": "z", "value": 225},
      "translation": {"x": 9, "y": 9, "z": 0}
    }
  }],
  "metadata": {
    "definition": "sitefit",
    "version": "1.0.0",
    "engine": {"mode": "deterministic", "name": "mock"}
  }
}
```

---

## 📊 Infrastructure Deployed

### Azure Resources

```
Resource Group: kuduso-dev-rg
├── Container Apps Environment: kuduso-dev-aca-env
├── Container Apps:
│   ├── kuduso-dev-sitefit-api (external, 1-5 replicas)
│   ├── kuduso-dev-sitefit-worker (internal, 0-10 replicas, KEDA)
│   └── kuduso-dev-appserver (internal, 1-3 replicas)
├── Service Bus:
│   ├── Namespace: kuduso-dev-servicebus
│   └── Queue: sitefit-queue
├── Container Registry: kudusodevacr93d2ab
├── Key Vault: kuduso-dev-kv-93d2ab
└── Storage Account: kudusodevsto93d2ab
```

### Database (Supabase)

```
Project: kuduso-dev
Region: Europe West (AWS eu-west-1)
Database: PostgreSQL 15
Tables: job, result, artifact, job_with_result (view)
```

---

## 🔑 Key Learnings

### 1. **Container Apps Internal Networking**
- Apps in same environment can communicate via `{app-name}.internal.{env-domain}`
- Must use `allow_insecure_connections: true` for HTTP
- Health and readiness probes are critical for routing
- DNS resolution happens automatically within environment

### 2. **Service Bus Peek-Lock Pattern**
- Lock duration: 5 minutes (PT5M)
- Renew lock every 45 seconds during long jobs
- Complete message only after successful DB write
- Abandon for transient errors (auto-retry)
- Dead-letter after 5 failed attempts

### 3. **Docker Multi-Stage Builds**
- Build context matters when copying from parent directories
- Use repo root as context when accessing sibling folders
- Explicit paths prevent confusion: `COPY shared/appserver-node/ ./`

### 4. **Schema Validation**
- Contracts must be runtime-available, not build-time only
- Environment variables > hardcoded paths
- Validate inputs AND outputs for contract adherence

### 5. **Debugging Distributed Systems**
- Check each component independently before integration
- Logs with correlation IDs are essential
- Health endpoints reveal infrastructure issues
- State drift between IaC and reality is real

---

## 📁 Files Created/Modified

### New Files
```
apps/sitefit/
├── api-fastapi/
│   ├── main.py           (250 lines - API implementation)
│   ├── requirements.txt
│   └── Dockerfile
├── worker-fastapi/
│   ├── main.py           (330 lines - Worker implementation)
│   ├── requirements.txt
│   └── Dockerfile
└── migrations/
    ├── alembic.ini
    ├── env.py
    └── versions/
        └── 001_initial_schema.py
```

### Modified Files
```
shared/appserver-node/
├── src/index.ts          (+ /ready endpoint)
└── Dockerfile            (+ contracts copy, fixed paths)

infra/modules/shared-appserver/
└── main.tf               (+ allow_insecure_connections, CONTRACTS_DIR env)

infra/live/dev/shared/appserver/
└── terragrunt.hcl        (image: appserver-node:6282cdd)
```

---

## 🚀 What's Next - Stage 4

**Goal:** Replace mock solver with **real Rhino.Compute**

**Tasks:**
1. ✅ Rhino VM already running (from Stage 2)
2. Create real Grasshopper definition (`sitefit.gh`)
3. Update AppServer to call Rhino.Compute API
4. Test with real geometry processing
5. Add artifact generation (glTF/GeoJSON)
6. Upload artifacts to Azure Blob Storage

**Current Mode:**
```typescript
USE_COMPUTE=false  // Mock solver
```

**Stage 4 Mode:**
```typescript
USE_COMPUTE=true   // Real Rhino.Compute
COMPUTE_URL=http://20.73.173.209:8081
```

---

## ✅ Stage 3 Success Criteria (All Met!)

- [x] Service Bus queue created and accessible
- [x] Database schema deployed via Alembic
- [x] API persists jobs to database
- [x] API enqueues messages to Service Bus
- [x] Worker consumes from Service Bus
- [x] Worker calls AppServer successfully
- [x] AppServer validates contracts
- [x] AppServer returns mock results
- [x] Worker persists results to database
- [x] API returns results from database
- [x] Full E2E test passes: POST → poll → GET result
- [x] Internal networking working (HTTP)
- [x] KEDA scaling configured
- [x] Correlation IDs in logs
- [x] Service Bus retry/DLQ working

---

## 📸 Evidence of Success

**Job Status:**
```json
{
  "job_id": "ccc06e87-8f8c-45d2-9b58-c4e40f9eab76",
  "status": "succeeded",
  "has_result": true,
  "created_at": "2025-10-30T08:19:39.685426+00:00"
}
```

**Worker Logs:**
```json
{"event": "worker.poll", "queue": "sitefit-queue"}
{"event": "worker.received", "message_count": 1}
{"event": "job.claim", "job_id": "ccc..."}
{"event": "job.before_appserver"}
{"event": "job.after_appserver", "duration_ms": 125}
{"event": "job.succeeded"}
```

**AppServer Logs:**
```json
{"event": "solve.start", "def": "sitefit", "ver": "1.0.0"}
{"event": "inputs.validated"}
{"event": "solve.complete", "duration_ms": 15}
{"event": "solve.success", "results_count": 1}
```

---

## 🎓 Conclusion

Stage 3 transformed our architecture from a basic deployment to a **production-ready async job processing system**. The biggest challenge was debugging Container Apps internal networking, which taught us the critical importance of proper health probes, correct Terraform attributes, and ensuring runtime dependencies are properly packaged.

The system now handles:
- ✅ Async job processing with message queuing
- ✅ Database persistence with proper migrations
- ✅ Contract-driven validation
- ✅ Scalable worker pool (KEDA)
- ✅ Proper error handling and retries
- ✅ Internal service-to-service communication

**Next stop: Real Grasshopper + Rhino.Compute!** 🦏

---

**Stage 3 Status: 🎉 COMPLETE - 100% WORKING**
