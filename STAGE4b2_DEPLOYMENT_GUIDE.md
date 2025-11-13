# Stage 4 Deployment Guide — Real Rhino.Compute Integration

## Overview

This guide walks through deploying the AppServer with real Rhino.Compute integration. Stage 4 replaces the mock solver with actual Grasshopper execution via Rhino.Compute.

**What's been implemented:**
- ✅ Rhino.Compute HTTP client (`rhinoComputeClient.ts`)
- ✅ Bindings module (JSON → Grasshopper DataTrees) using `rhino3dm` 
- ✅ Manifest enforcement (timeouts, limits, vertex caps)
- ✅ Compute solver orchestration (`computeSolver.ts`)
- ✅ Dynamic routing (mock vs compute modes via `USE_COMPUTE` flag)
- ✅ Proper error handling and HTTP status codes (400/422/429/504)
- ✅ Infrastructure variables for Rhino.Compute configuration

---

## Prerequisites

Before deploying, ensure you have completed:

1. **Rhino VM deployed and configured** (from Stage 2)
   - Rhino 8 installed and licensed
   - Rhino.Compute installed and running as Windows service
   - Firewall rules allow port 8081
   - API key generated and stored in Key Vault

2. **Grasshopper definition uploaded to VM**
   - File: `sitefit_ready.ghx` (or `ghlogic.ghx`)
   - Location: `C:\compute\sitefit\1.0.0\ghlogic.ghx`
   - Verify inputs/outputs match `contracts/sitefit/1.0.0/bindings.json`

3. **Key Vault secrets configured**
   - `COMPUTE-API-KEY` — Rhino.Compute API key
   - `DATABASE-URL` — Supabase connection string

---

## Step 1: Verify Rhino.Compute is Running

### From Your Local Machine

```bash
# Get Rhino VM IP (if not already known)
cd infra/live/dev/shared/rhino
RHINO_IP=$(terragrunt output -raw public_ip 2>/dev/null || echo "20.73.173.209")
echo "Rhino VM IP: $RHINO_IP"

# Get API key from Key Vault
KV_NAME=$(cd ../core && terragrunt output -raw key_vault_name)
API_KEY=$(az keyvault secret show --vault-name $KV_NAME --name COMPUTE-API-KEY --query value -o tsv)

# Test health endpoint (no auth required)
curl http://$RHINO_IP:8081/version

# Test with auth
curl -X POST http://$RHINO_IP:8081/rhino/geometry/point \
  -H "RhinoComputeKey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"x":10,"y":20,"z":30}'
```

**Expected:** `200 OK` responses ✅

If health checks fail, see [Troubleshooting](#troubleshooting) section.

---

## Step 2: Upload Grasshopper Definition to VM

### Option A: Via RDP

1. Connect to VM via Remote Desktop
2. Navigate to: `C:\compute\sitefit\1.0.0\`
3. Copy `sitefit_ready.ghx` → rename to `ghlogic.ghx`
4. Verify file exists: `Test-Path "C:\compute\sitefit\1.0.0\ghlogic.ghx"`

### Option B: Via PowerShell Remote (if enabled)

```bash
# From your local machine (replace with actual VM IP and credentials)
scp contracts/sitefit/1.0.0/sitefit_ready.ghx azureuser@$RHINO_IP:C:/compute/sitefit/1.0.0/ghlogic.ghx
```

### Verify GH Definition Structure

On the VM, check that the definition has the expected parameters:

```powershell
# List files in definition directory
Get-ChildItem "C:\compute\sitefit\1.0.0"
```

**Expected files:**
- `ghlogic.ghx` (or `sitefit.ghx`)
- Optional: `README.md`, `inputs.json` (test payloads)

---

## Step 3: Build and Push New AppServer Image

The AppServer now includes:
- `rhino3dm` package for geometry encoding
- `jsonpath-plus` for bindings evaluation
- New solver modules

```bash
cd /home/martin/Desktop/kuduso

# Build AppServer image with new dependencies
docker build -t appserver-node:stage4 -f shared/appserver-node/Dockerfile .

# Get ACR login server
cd infra/live/dev/shared/core
ACR_SERVER=$(terragrunt output -raw acr_server)

# Login to ACR
az acr login --name $(echo $ACR_SERVER | cut -d. -f1)

# Tag and push
docker tag appserver-node:stage4 $ACR_SERVER/appserver-node:stage4
docker push $ACR_SERVER/appserver-node:stage4

# Get image digest for immutable reference
IMAGE_DIGEST=$(az acr repository show -n $(echo $ACR_SERVER | cut -d. -f1) \
  --image appserver-node:stage4 --query digest -o tsv)

echo "Image pushed: $ACR_SERVER/appserver-node:stage4"
echo "Digest: $IMAGE_DIGEST"
```

---

## Step 4: Update Terragrunt Configuration

Edit `infra/live/dev/shared/appserver/terragrunt.hcl`:

```hcl
inputs = {
  # ... existing config ...
  
  # Update image to new version
  app_image = "appserver-node:stage4"
  
  # Rhino.Compute Configuration
  rhino_compute_url = "http://20.73.173.209:8081" # Your Rhino VM IP
  use_compute       = false  # Start with mock=true for testing
  timeout_ms        = 240000  # 4 minutes
  compute_definitions_path = "C:\\\\compute"
  log_level         = "info"  # Use "debug" for verbose logging
  
  # ... rest of config ...
}
```

**Important:** Start with `use_compute = false` to test deployment first!

---

## Step 5: Deploy Updated AppServer

```bash
cd infra/live/dev/shared/appserver

# Initialize if needed
terragrunt init

# Review changes
terragrunt plan

# Apply changes
terragrunt apply
```

**Expected changes:**
- Container image updated
- Environment variables added (USE_COMPUTE, TIMEOUT_MS, etc.)
- Container restarted with new configuration

---

## Step 6: Test Mock Mode First

Before enabling compute, verify the new AppServer works in mock mode:

```bash
# Get AppServer internal FQDN
APPSERVER_FQDN=$(terragrunt output -raw appserver_fqdn 2>/dev/null || echo "kuduso-dev-appserver.internal")

# Test from within ACA environment (via API container)
# Or use the test script locally with port-forward

cd ../../../shared/appserver-node

# Test health
curl http://$APPSERVER_FQDN:8080/health

# Test readiness
curl http://$APPSERVER_FQDN:8080/ready

# Test mock solve
./test-appserver.sh mock
```

**Expected:** All tests pass in mock mode ✅

---

## Step 7: Enable Real Compute Mode

Once mock mode works, flip the switch to use real Rhino.Compute:

### Update Terragrunt

Edit `infra/live/dev/shared/appserver/terragrunt.hcl`:

```hcl
inputs = {
  # ... existing config ...
  
  use_compute = true  # 🚀 Enable real compute!
  log_level   = "debug"  # Verbose logging for first run
}
```

### Deploy

```bash
cd infra/live/dev/shared/appserver
terragrunt apply
```

### Test with Real Compute

```bash
# Wait for container to restart (~30 seconds)
sleep 30

# Test readiness (should check Compute health now)
curl http://$APPSERVER_FQDN:8080/ready

# Run golden test with real Compute
./test-appserver.sh compute
```

**Expected:** AppServer calls Rhino.Compute, returns real placement results ✅

---

## Step 8: Verify End-to-End Flow

Test the complete flow: API → Worker → AppServer → Rhino.Compute

### Via API Container

```bash
# Get API URL
cd infra/live/dev/apps/sitefit
API_URL=$(terragrunt output -raw api_url)

# Submit a job
JOB_RESPONSE=$(curl -s -X POST "$API_URL/jobs/run" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SUPABASE_JWT" \
  -d @contracts/sitefit/1.0.0/examples/valid/minimal.json)

JOB_ID=$(echo "$JOB_RESPONSE" | jq -r .job_id)
echo "Job ID: $JOB_ID"

# Poll for result
while true; do
  STATUS=$(curl -s "$API_URL/jobs/status/$JOB_ID" | jq -r .status)
  echo "Status: $STATUS"
  
  if [ "$STATUS" = "succeeded" ]; then
    curl -s "$API_URL/jobs/result/$JOB_ID" | jq .
    break
  elif [ "$STATUS" = "failed" ]; then
    echo "Job failed!"
    break
  fi
  
  sleep 2
done
```

---

## Step 9: Golden Test Validation

Run the contract validation test to ensure outputs match schema:

```bash
cd contracts/sitefit/1.0.0

# Validate example inputs
npm run validate

# Test a specific example through the API
curl -X POST "$APPSERVER_FQDN:8080/gh/sitefit:1.0.0/solve" \
  -H "Content-Type: application/json" \
  -d @examples/valid/typical.json \
  | jq . > /tmp/output.json

# Validate output against schema
npx ajv-cli validate -s outputs.schema.json -d /tmp/output.json
```

**Expected:** Validation passes, outputs conform to contract ✅

---

## Monitoring & Observability

### View Logs

```bash
# AppServer logs
az containerapp logs show \
  --name kuduso-dev-appserver \
  --resource-group kuduso-dev-rg \
  --follow

# Filter for compute events
az monitor log-analytics query \
  --workspace $(cd infra/live/dev/shared/core && terragrunt output -raw log_analytics_workspace_id) \
  --analytics-query "
    ContainerAppConsoleLogs_CL
    | where ContainerName_s == 'appserver'
    | where Log_s contains 'compute'
    | project TimeGenerated, Log_s
    | order by TimeGenerated desc
    | take 50
  "
```

### Key Metrics to Watch

- **Compute call latency:** p50, p95, p99
- **Success rate:** 2xx vs 4xx/5xx
- **Timeout rate:** 504 responses
- **Errors by type:** 400 (validation), 422 (domain), 429 (busy), 503 (unavailable)

---

## Troubleshooting

### Issue: AppServer can't reach Rhino.Compute

**Symptoms:**
- `/ready` endpoint returns 503
- Logs show "Failed to connect to Compute"

**Fix:**
1. Verify Rhino VM is running: `az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm`
2. Check NSG allows traffic from ACA subnet
3. Test from your machine: `curl http://$RHINO_IP:8081/version`

---

### Issue: 401 Unauthorized from Compute

**Cause:** API key mismatch

**Fix:**
```bash
# Verify key in Key Vault
az keyvault secret show --vault-name $KV_NAME --name COMPUTE-API-KEY --query value

# Compare with key on VM (via RDP)
# PowerShell on VM:
[Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')

# If different, update Key Vault
az keyvault secret set --vault-name $KV_NAME --name COMPUTE-API-KEY --value "VM_KEY_HERE"

# Restart AppServer
cd infra/live/dev/shared/appserver
terragrunt apply -auto-approve
```

---

### Issue: 422 Domain Error from Grasshopper

**Symptoms:**
- Request succeeds but returns 422
- Logs show "Grasshopper execution failed"

**Possible causes:**
1. GH definition expects different parameter names → check `bindings.json`
2. Geometry encoding issue → verify rhino3dm is working
3. Infeasible inputs (e.g., house larger than parcel)

**Debug:**
```bash
# Enable debug logging
# Edit terragrunt.hcl: log_level = "debug"
terragrunt apply

# Review detailed logs
az containerapp logs show --name kuduso-dev-appserver --resource-group kuduso-dev-rg --follow
```

---

### Issue: 504 Timeout

**Cause:** Compute call exceeds manifest timeout

**Fix:**
1. Check `manifest.json`: `timeout_sec: 240`
2. Reduce problem complexity (smaller grid_step, fewer rotation samples)
3. Increase timeout in `terragrunt.hcl`: `timeout_ms = 300000` (5 min)

---

### Issue: Bindings Error (missing output)

**Symptoms:**
- 500 error with "Output validation failed"
- Logs show "bindings.missing_input" or "bindings.parse_error"

**Fix:**
1. Verify GH definition outputs match `bindings.json` exactly (case-sensitive!)
2. Check GH file on VM: `placed_transforms`, `placement_scores`, `kpis`
3. Test GH definition manually in Grasshopper GUI on VM

---

## Performance Tuning

### Concurrency Control

Currently, AppServer has no semaphore. To add concurrency limits:

Edit `shared/appserver-node/src/computeSolver.ts`:

```typescript
// At top of file
const MAX_CONCURRENT_JOBS = 1; // Match Rhino license seats
let activeJobs = 0;

// In computeSolve function, add:
if (activeJobs >= MAX_CONCURRENT_JOBS) {
  throw { code: 429, message: 'Compute busy', details: [] };
}

activeJobs++;
try {
  // ... existing code ...
} finally {
  activeJobs--;
}
```

### Timeout Tuning

Adjust per definition in `manifest.json`:
- **Preview mode:** 30-60 seconds
- **Batch mode:** 120-240 seconds

---

## Rollback Plan

If issues arise, revert to mock mode:

```bash
cd infra/live/dev/shared/appserver

# Edit terragrunt.hcl: use_compute = false
terragrunt apply -auto-approve
```

Or roll back to previous image:

```hcl
app_image = "appserver-node:6282cdd" # Previous working version
```

---

## Next Steps (Stage 5)

Once Stage 4 is stable:
- ✅ Move Rhino to VMSS + Internal Load Balancer (no public IP)
- ✅ Add plugin attestation checks
- ✅ Implement idempotency (inputs_hash caching)
- ✅ Add DLQ peek/replay tools
- ✅ Load testing and concurrency validation

---

## Summary Checklist

- [ ] Rhino.Compute VM healthy and accessible
- [ ] Grasshopper definition uploaded to `C:\compute\sitefit\1.0.0\ghlogic.ghx`
- [ ] API key stored in Key Vault as `COMPUTE-API-KEY`
- [ ] AppServer image rebuilt with new dependencies
- [ ] Terraform module updated with new environment variables
- [ ] AppServer deployed and tested in mock mode
- [ ] `USE_COMPUTE=true` enabled and tested with real Rhino
- [ ] Golden tests pass with deterministic results
- [ ] End-to-end flow verified (API → Worker → AppServer → Compute)
- [ ] Logs and metrics monitored for errors

---

**Status:** Ready to deploy Stage 4! 🚀

**Estimated Time:**
- Manual steps: ~30 minutes
- Build + deploy: ~15 minutes
- Testing + validation: ~20 minutes
- **Total:** ~1 hour

---

## Quick Reference

### Environment Variables (AppServer)

| Variable | Purpose | Example |
|----------|---------|---------|
| `USE_COMPUTE` | Enable real Rhino.Compute | `true` |
| `COMPUTE_URL` | Rhino.Compute endpoint | `http://20.73.173.209:8081` |
| `COMPUTE_API_KEY` | API key (from Key Vault) | `abc123...` |
| `TIMEOUT_MS` | Request timeout | `240000` (4 min) |
| `COMPUTE_DEFINITIONS_PATH` | GH definitions root | `C:\\compute` |
| `LOG_LEVEL` | Logging verbosity | `info` or `debug` |

### Important Paths

| Component | Path |
|-----------|------|
| GH Definition (VM) | `C:\compute\sitefit\1.0.0\ghlogic.ghx` |
| Contracts (AppServer) | `/app/contracts/sitefit/1.0.0/` |
| AppServer Code | `/home/martin/Desktop/kuduso/shared/appserver-node/` |
| Infra Config | `/home/martin/Desktop/kuduso/infra/live/dev/shared/appserver/` |


