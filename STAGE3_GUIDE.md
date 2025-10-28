# 🚀 Stage 3 Implementation Guide

## Overview

Stage 3 connects your deployed infrastructure to **real database** (Supabase) and **message queue** (Service Bus), while keeping compute **mocked**.

**Time estimate**: 3-4 hours  
**Status**: Infrastructure ready ✅, now adding application logic

---

## Prerequisites ✅

From Stage 2, you have:
- ✅ Service Bus namespace + queue (`sitefit-queue`)
- ✅ Storage Account (for blob artifacts)
- ✅ Key Vault (for secrets)
- ✅ API Container App (placeholder FastAPI)
- ✅ Worker Container App (placeholder FastAPI)
- ✅ AppServer Container App (mock mode)

---

## Step 1: Set Up Supabase (20 minutes)

### 1.1 Create Supabase Project

1. Go to https://supabase.com and sign in
2. Click **New Project**
3. Configure:
   - **Organization**: Create or select
   - **Name**: `kuduso-dev`
   - **Database Password**: Generate strong password (SAVE THIS!)
   - **Region**: `Europe West (eu-west-1)` or closest to Azure West Europe
   - **Pricing**: Free tier is fine for dev
4. Click **Create new project**
5. Wait ~2 minutes for provisioning

### 1.2 Get Connection String

1. Go to **Project Settings** → **Database**
2. Under **Connection string**, select **URI**
3. Copy the connection string (it looks like):
   ```
   postgresql://postgres.xxxxxx:[YOUR-PASSWORD]@aws-0-eu-west-1.pooler.supabase.com:6543/postgres
   ```
4. Replace `[YOUR-PASSWORD]` with the actual password you set

### 1.3 Create Database Schema with Alembic

We'll use Alembic for proper database migrations:

```bash
cd /home/martin/Desktop/kuduso

# Install Alembic
pip install alembic psycopg2-binary

# Run migrations
cd apps/sitefit/migrations
export DATABASE_URL="postgresql://..."  # Your Supabase connection string
alembic upgrade head
```

Verify tables created: Go to Supabase **Table Editor**, you should see:
- `job`
- `result`
- `artifact`
- `alembic_version` (tracks migrations)

### 1.4 Store Secrets in Key Vault

Run the setup script:

```bash
cd /home/martin/Desktop/kuduso
chmod +x STAGE3_SETUP.sh
./STAGE3_SETUP.sh
```

This will:
- ✅ Store `DATABASE-URL` in Key Vault
- ✅ Store `SERVICEBUS-CONN` in Key Vault (if not exists)
- ✅ Store `BLOB-SAS-SIGNING` (Storage Account key) in Key Vault

---

## Step 2: Update Environment Variables (15 minutes)

### 2.1 Update API Configuration

Edit `infra/live/dev/apps/sitefit/terragrunt.hcl` and verify/add environment variables:

The API needs to know:
- Service Bus queue name
- AppServer internal URL
- Storage account name
- Supabase auth URL (for JWT validation)

### 2.2 Update Worker Configuration

The Worker needs:
- Service Bus queue name
- AppServer internal URL
- Lock renewal settings
- Job timeout settings

### 2.3 Update AppServer Configuration

Edit `infra/live/dev/shared/appserver/terragrunt.hcl`:
- Ensure `USE_COMPUTE=false` (keep mocked)
- Verify contracts directory path

---

## Step 3: Update Application Code

### 3.1 API Changes (apps/sitefit/api-fastapi/)

**Files to update**:

#### `app/main.py` - Main FastAPI app
- Add Service Bus client
- Add Supabase client
- Add endpoints:
  - `POST /jobs/run` - Enqueue job
  - `GET /jobs/status/{job_id}` - Get job status
  - `GET /jobs/result/{job_id}` - Get job result

#### `app/services/job_service.py` - NEW
- Input validation + default materialization
- Compute `inputs_hash` (SHA-256)
- Insert job into Supabase
- Enqueue message to Service Bus
- Generate Blob SAS URLs for artifacts

#### `app/services/db.py` - NEW
- Supabase client wrapper
- Job CRUD operations
- Result storage

#### `app/services/queue.py` - NEW
- Service Bus sender
- Message formatting
- Correlation ID handling

#### `requirements.txt`
```txt
fastapi
uvicorn[standard]
pydantic
azure-servicebus
supabase
python-jose[cryptography]
jsonschema
httpx
```

### 3.2 Worker Changes (apps/sitefit/worker-fastapi/)

**Files to update**:

#### `app/main.py` - Main worker loop
- Service Bus receiver (peek-lock mode)
- Lock renewal task
- Message processing loop
- Error handling (abandon vs DLQ)

#### `app/services/job_processor.py` - NEW
- Receive and process messages
- Update job status in DB
- Call AppServer
- Store results
- Complete/abandon/deadletter logic

#### `app/services/db.py` - NEW
- Same Supabase operations as API
- Job status updates
- Result insertion

#### `requirements.txt`
```txt
fastapi
uvicorn[standard]
azure-servicebus
supabase
httpx
```

### 3.3 AppServer Updates (shared/appserver-node/)

**Minimal changes needed** - AppServer already has mock mode!

Just verify:
- `USE_COMPUTE=false` in environment
- Health endpoints work
- Mock solver returns proper format

---

## Step 4: Build and Deploy Updated Images (20 minutes)

### 4.1 Build New Images

```bash
cd /home/martin/Desktop/kuduso

# Get git commit SHA for tagging
GIT_SHA=$(git rev-parse --short HEAD)

# Build images
docker build -t api-fastapi:$GIT_SHA apps/sitefit/api-fastapi
docker build -t worker-fastapi:$GIT_SHA apps/sitefit/worker-fastapi

# If AppServer changed:
# docker build -t appserver-node:$GIT_SHA shared/appserver-node
```

### 4.2 Push to ACR

```bash
ACR="kudusodevacr93d2ab.azurecr.io"

# Login to ACR
az acr login --name kudusodevacr93d2ab

# Tag and push
docker tag api-fastapi:$GIT_SHA $ACR/api-fastapi:$GIT_SHA
docker tag worker-fastapi:$GIT_SHA $ACR/worker-fastapi:$GIT_SHA

docker push $ACR/api-fastapi:$GIT_SHA
docker push $ACR/worker-fastapi:$GIT_SHA
```

### 4.3 Update Terragrunt Config

Edit `infra/live/dev/apps/sitefit/terragrunt.hcl`:

```hcl
inputs = {
  # Update image tags
  api_image    = "api-fastapi:abc123"  # Your actual GIT_SHA
  worker_image = "worker-fastapi:abc123"
  
  # ... rest stays the same
}
```

### 4.4 Redeploy

```bash
cd infra/live/dev/apps/sitefit

terragrunt apply
```

---

## Step 5: Test End-to-End (30 minutes)

### 5.1 Check Deployments

```bash
# Check API
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --query "{name:name, status:properties.runningStatus}"

# Check Worker
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "{name:name, status:properties.runningStatus, replicas:properties.template.scale.minReplicas}"
```

### 5.2 Test Happy Path

```bash
API_URL="https://kuduso-dev-sitefit-api.blackwave-77d88b66.westeurope.azurecontainerapps.io"

# 1. Submit a job
curl -X POST $API_URL/jobs/run \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "sitefit",
    "definition": "sitefit",
    "version": "1.0.0",
    "inputs": {
      "site_boundary": [...],
      "constraints": {...}
    }
  }'

# Response: {"job_id": "uuid"}

# 2. Check status
curl $API_URL/jobs/status/{job_id}

# 3. Get result (once succeeded)
curl $API_URL/jobs/result/{job_id}
```

### 5.3 Verify Database

In Supabase SQL Editor:

```sql
-- Check recent jobs
select id, status, definition, version, attempts, created_at, ended_at 
from job 
order by created_at desc 
limit 10;

-- Check results
select job_id, score, created_at 
from result 
order by created_at desc 
limit 10;
```

### 5.4 Watch Worker Scale

```bash
# Send 10 jobs to trigger scaling
for i in {1..10}; do
  curl -X POST $API_URL/jobs/run \
    -H "Content-Type: application/json" \
    -d '{"app_id":"sitefit","definition":"sitefit","version":"1.0.0","inputs":{...}}'
done

# Watch worker replicas increase
watch -n 2 'az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "[0].properties.replicas"'
```

### 5.5 Check Logs

```bash
# API logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --follow

# Worker logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --follow
```

---

## Step 6: Test Error Scenarios

### 6.1 Retry Path

**Simulate transient error**:
- Temporarily make AppServer return 429 or 503
- Worker should abandon message
- Service Bus redelivers
- Worker retries successfully

### 6.2 Poison Message

**Send invalid payload**:
- Worker should dead-letter after max attempts
- Check DLQ in Azure Portal

```bash
# Check DLQ
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.deadLetterMessageCount"
```

---

## Troubleshooting

### API not connecting to Supabase

**Check**:
```bash
# Verify secret in Key Vault
az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name DATABASE-URL \
  --query value -o tsv

# Check API logs for connection errors
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --tail 50
```

### Worker not processing messages

**Check**:
```bash
# Check queue has messages
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.activeMessageCount"

# Check worker logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --tail 100

# Check KEDA scaling
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "properties.template.scale"
```

### AppServer not reachable

**Check internal DNS**:
- Worker should use `http://kuduso-dev-appserver:8080`
- Both must be in same Container Apps Environment
- Verify AppServer is running:

```bash
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "properties.runningStatus"
```

---

## Success Criteria ✅

Stage 3 is complete when:

- ✅ Supabase database created with schema
- ✅ All secrets stored in Key Vault
- ✅ API accepts jobs and returns 202 with job_id
- ✅ Jobs appear in Supabase `job` table
- ✅ Messages appear in Service Bus queue
- ✅ Worker scales from 0 to N based on queue depth
- ✅ Worker processes jobs and calls AppServer (mock)
- ✅ Results stored in Supabase `result` table
- ✅ Worker scales back to 0 when queue empty
- ✅ Retry logic works (abandon → redeliver)
- ✅ Poison messages go to DLQ
- ✅ Logs show correlation IDs end-to-end

---

## What's Next: Stage 4

Once Stage 3 is working:

1. **Install Rhino.Compute** on the Rhino VM
2. **Update AppServer**: Set `USE_COMPUTE=true`
3. **Test** with real Grasshopper computation
4. **No API/Worker changes needed!** (that's the beauty of this architecture)

---

## Quick Reference

**API URL**: `https://kuduso-dev-sitefit-api.blackwave-77d88b66.westeurope.azurecontainerapps.io`

**Supabase**: https://supabase.com/dashboard/project/[your-project]

**Azure Portal Resources**:
- Resource Group: `kuduso-dev-rg`
- Container Apps: API, Worker, AppServer
- Service Bus: `kuduso-dev-servicebus` → `sitefit-queue`
- Storage: For artifacts
- Key Vault: `kuduso-dev-kv-93d2ab`

**Useful Commands**:
```bash
# Tail all logs
az containerapp logs show --resource-group kuduso-dev-rg --name kuduso-dev-sitefit-api --follow
az containerapp logs show --resource-group kuduso-dev-rg --name kuduso-dev-sitefit-worker --follow

# Check queue depth
az servicebus queue show --resource-group kuduso-dev-rg --namespace-name kuduso-dev-servicebus --name sitefit-queue --query "countDetails"

# Check worker replicas
az containerapp revision list --resource-group kuduso-dev-rg --name kuduso-dev-sitefit-worker --query "[0].properties.replicas"
```

---

**Ready to start coding? Let me know which component you want to tackle first!**
