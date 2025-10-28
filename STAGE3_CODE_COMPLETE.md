# ✅ Stage 3 - Application Code Complete!

## 🎉 What Was Done

### Database Setup ✅
- ✅ Alembic migrations created
- ✅ Database schema deployed to Supabase
- ✅ Tables: `job`, `result`, `artifact`
- ✅ Indexes and RLS policies configured

### Secrets in Key Vault ✅
- ✅ `DATABASE-URL` - Supabase connection string
- ✅ `SERVICEBUS-CONN` - Service Bus connection string  
- ✅ `BLOB-SAS-SIGNING` - Storage account key
- ✅ `COMPUTE-API-KEY` - Rhino compute key (Stage 2)

### API Code Updated ✅

**New Files Created:**
- `config.py` - Environment configuration
- `database.py` - Supabase database operations
- `queue.py` - Service Bus producer

**Updated Files:**
- `main.py` - Stage 3 version (async job submission)
- `requirements.txt` - Added psycopg2, azure-servicebus

**Backup:**
- `main_stage1_backup.py` - Original sync version

**New Functionality:**
- ✅ Validates inputs and computes hash
- ✅ Inserts job into database (status='queued')
- ✅ Enqueues message to Service Bus
- ✅ Returns 202 with job_id
- ✅ `/jobs/status/{id}` reads from database
- ✅ `/jobs/result/{id}` reads from database
- ✅ Idempotency check (optional)

### Worker Code Updated ✅

**New Files Created:**
- `config.py` - Environment configuration
- `database.py` - Database operations for results

**Updated Files:**
- `main.py` - Stage 3 version (queue consumer)
- `requirements.txt` - Added psycopg2

**Backup:**
- `main_stage1_backup.py` - Original placeholder

**New Functionality:**
- ✅ Service Bus consumer (peek-lock)
- ✅ Lock renewal during processing
- ✅ Calls AppServer (mock mode)
- ✅ Writes results to database
- ✅ Completes/abandons/dead-letters messages
- ✅ Retry logic for transient errors
- ✅ Max attempts enforcement

---

## 📦 Updated File Structure

```
apps/sitefit/
├── api-fastapi/
│   ├── main.py                    ✅ Stage 3 (Service Bus + DB)
│   ├── main_stage1_backup.py      📦 Backup
│   ├── models.py                  (unchanged)
│   ├── config.py                  ✅ NEW
│   ├── database.py                ✅ NEW
│   ├── queue.py                   ✅ NEW
│   ├── requirements.txt           ✅ Updated
│   └── Dockerfile                 (unchanged)
│
├── worker-fastapi/
│   ├── main.py                    ✅ Stage 3 (queue consumer)
│   ├── main_stage1_backup.py      📦 Backup
│   ├── config.py                  ✅ NEW
│   ├── database.py                ✅ NEW
│   ├── requirements.txt           ✅ Updated
│   └── Dockerfile                 (unchanged)
│
└── migrations/
    ├── alembic.ini                ✅ NEW
    ├── env.py                     ✅ NEW
    ├── README.md                  ✅ NEW
    ├── requirements.txt           ✅ NEW
    └── versions/
        └── 001_initial_schema.py  ✅ NEW
```

---

## 🚀 Next Steps: Build & Deploy

### Step 1: Build New Docker Images

```bash
cd /home/martin/Desktop/kuduso

# Get git commit SHA for tagging
GIT_SHA=$(git rev-parse --short HEAD)
echo "Building images with tag: $GIT_SHA"

# Build API image
docker build -t api-fastapi:$GIT_SHA apps/sitefit/api-fastapi

# Build Worker image
docker build -t worker-fastapi:$GIT_SHA apps/sitefit/worker-fastapi
```

### Step 2: Push to Azure Container Registry

```bash
# Login to ACR
az acr login --name kudusodevacr93d2ab

# Tag images
ACR="kudusodevacr93d2ab.azurecr.io"
docker tag api-fastapi:$GIT_SHA $ACR/api-fastapi:$GIT_SHA
docker tag worker-fastapi:$GIT_SHA $ACR/worker-fastapi:$GIT_SHA

# Push images
docker push $ACR/api-fastapi:$GIT_SHA
docker push $ACR/worker-fastapi:$GIT_SHA

echo "✅ Images pushed with tag: $GIT_SHA"
```

### Step 3: Update Terragrunt Configuration

Edit `infra/live/dev/apps/sitefit/terragrunt.hcl`:

```hcl
inputs = {
  # Update image tags to new SHA
  api_image    = "api-fastapi:abc123"  # Your actual $GIT_SHA
  worker_image = "worker-fastapi:abc123"
  
  # Environment variables for API
  api_env_vars = [
    { name = "DATABASE_URL", secret_ref = "DATABASE-URL" },
    { name = "SERVICEBUS_CONN", secret_ref = "SERVICEBUS-CONN" },
    { name = "SERVICEBUS_QUEUE", value = "sitefit-queue" },
    { name = "APP_SERVER_URL", value = "http://kuduso-dev-appserver:8080/gh/{definition}:{version}/solve" },
    { name = "BLOB_SAS_SIGNING", secret_ref = "BLOB-SAS-SIGNING" },
    { name = "RESULT_CACHE_TTL", value = "300" }
  ]
  
  # Environment variables for Worker
  worker_env_vars = [
    { name = "DATABASE_URL", secret_ref = "DATABASE-URL" },
    { name = "SERVICEBUS_CONN", secret_ref = "SERVICEBUS-CONN" },
    { name = "SERVICEBUS_QUEUE", value = "sitefit-queue" },
    { name = "APP_SERVER_URL", value = "http://kuduso-dev-appserver:8080/gh/{definition}:{version}/solve" },
    { name = "LOCK_RENEW_SEC", value = "45" },
    { name = "JOB_TIMEOUT_SEC", value = "240" },
    { name = "MAX_ATTEMPTS", value = "5" }
  ]
  
  # Rest of config stays the same
  api_cpu          = "0.5"
  api_memory       = "1Gi"
  api_min_replicas = 1
  api_max_replicas = 5
  api_port         = 8000
  
  worker_cpu          = "0.5"
  worker_memory       = "1Gi"
  worker_min_replicas = 0
  worker_max_replicas = 10
  worker_port         = 8080
}
```

### Step 4: Deploy with Terragrunt

```bash
cd infra/live/dev/apps/sitefit

# Check what will change
terragrunt plan

# Deploy
terragrunt apply
```

Expected changes:
- API container updated with new image + env vars
- Worker container updated with new image + env vars
- New revision created for both apps

---

## 🧪 Testing the Deployment

### Check Deployment Status

```bash
# API status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --query "{name:name, status:properties.runningStatus, revision:properties.latestRevisionName}"

# Worker status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "{name:name, status:properties.runningStatus, replicas:properties.template.scale.minReplicas}"
```

### Test API

```bash
API_URL="https://kuduso-dev-sitefit-api.blackwave-77d88b66.westeurope.azurecontainerapps.io"

# 1. Health check
curl $API_URL/health

# Should return: {"status":"ok","service":"api-fastapi-stage3","storage":"supabase-connected"}

# 2. Submit a job
curl -X POST $API_URL/jobs/run \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "sitefit",
    "definition": "sitefit",
    "version": "1.0.0",
    "inputs": {
      "crs": "EPSG:5514",
      "parcel": {"coordinates": [[0,0],[20,0],[20,30],[0,30],[0,0]]},
      "house": {"coordinates": [[0,0],[10,0],[10,8],[0,8],[0,0]]},
      "seed": 42
    }
  }'

# Should return: {"job_id":"uuid","status":"queued","correlation_id":"uuid"}
```

### Watch Worker Process Job

```bash
# Get the job_id from previous response
JOB_ID="<uuid-from-response>"

# Watch logs (in separate terminal)
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --follow

# Check job status
curl $API_URL/jobs/status/$JOB_ID

# When status is "succeeded", get result
curl $API_URL/jobs/result/$JOB_ID
```

### Verify in Supabase

Go to Supabase → SQL Editor:

```sql
-- Check recent jobs
SELECT 
  id::text as job_id, 
  status, 
  definition, 
  version, 
  attempts,
  created_at,
  started_at,
  ended_at
FROM job 
ORDER BY created_at DESC 
LIMIT 10;

-- Check results
SELECT 
  job_id::text,
  outputs_json,
  score,
  created_at
FROM result
ORDER BY created_at DESC
LIMIT 10;
```

### Check Queue

```bash
# Check queue message count
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.{active:activeMessageCount,deadLetter:deadLetterMessageCount}"
```

---

## 🔍 Monitoring & Troubleshooting

### View Logs

```bash
# API logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --follow \
  --tail 50

# Worker logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --follow \
  --tail 50

# AppServer logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --follow \
  --tail 50
```

### Common Issues

**API can't connect to database:**
```bash
# Check DATABASE-URL secret
az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name DATABASE-URL \
  --query value -o tsv

# Check API logs for connection errors
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --tail 100 | grep -i "database\|error"
```

**Worker not processing messages:**
```bash
# Check if worker is running
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "properties.runningStatus"

# Check worker logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --tail 100

# Check KEDA scaling
az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "[0].properties.{replicas:replicas,active:active}"
```

**AppServer unreachable:**
```bash
# Check AppServer status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "{name:name,status:properties.runningStatus}"

# Test internal connectivity (from worker logs, should see AppServer calls)
```

---

## ✅ Success Criteria

Stage 3 is complete when:

- ✅ API accepts `/jobs/run` and returns `202` with `job_id`
- ✅ Job appears in Supabase `job` table with `status='queued'`
- ✅ Message appears in Service Bus `sitefit-queue`
- ✅ Worker scales from 0 to 1 (KEDA triggered)
- ✅ Worker processes job and calls AppServer (mock)
- ✅ Result appears in Supabase `result` table
- ✅ Job status updates to `'succeeded'`
- ✅ `/jobs/result/{id}` returns the output
- ✅ Worker scales back to 0 when queue empty
- ✅ Logs show correlation IDs end-to-end

---

## 🎯 What's Next: Stage 4

Once Stage 3 is working:

1. **Install Rhino.Compute** on Windows VM
2. **Update AppServer**: Set `USE_COMPUTE=true`
3. **Test with real Grasshopper** computation
4. **No API/Worker changes needed!** ✨

---

## 📝 Summary

### What Changed

| Component | Stage 1 | Stage 3 |
|-----------|---------|---------|
| **API** | In-memory, sync | Database + queue, async |
| **Worker** | Placeholder | Full queue consumer |
| **Storage** | RAM | Supabase PostgreSQL |
| **Queue** | None | Azure Service Bus |
| **Scaling** | N/A | KEDA (0-10 replicas) |

### Code Stats

- **API**: +3 files, ~400 lines
- **Worker**: +2 files, ~300 lines
- **Migrations**: +5 files, ~200 lines
- **Total**: ~900 lines of production code

### Architecture

```
Client → API (external HTTPS)
         ↓ (insert job, enqueue message)
         ├→ Supabase (job status)
         └→ Service Bus (sitefit-queue)
                ↓ (KEDA scales)
              Worker (0-10 replicas)
                ↓ (process job)
              AppServer (mock mode)
                ↓ (write result)
              Supabase (result table)
```

---

**🎉 Ready to build and deploy!**
