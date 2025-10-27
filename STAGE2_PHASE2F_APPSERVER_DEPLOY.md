# Stage 2 - Phase 2E: Deploy AppServer Module

## 🎯 Goal

Deploy the shared AppServer container app for contract validation and Rhino.Compute routing.

## 📋 What We Created

### Terraform Module
```
infra/modules/shared-appserver/
├── variables.tf      ✅ Input variables
├── main.tf           ✅ Container App + Identity + Roles
├── outputs.tf        ✅ Outputs (URL, identity, etc.)
└── README.md         ✅ Documentation
```

### Configuration
```
infra/live/dev/shared/appserver/
└── terragrunt.hcl    ✅ Dev environment config
```

## 🏗️ What Will Be Deployed

### Container App
- **Name**: `kuduso-dev-appserver`
- **Image**: `appserver-node:f75482e`
- **Resources**: 0.5 vCPU, 1GB RAM
- **Scaling**: 1-3 replicas
- **Network**: Internal only (no external ingress)
- **Port**: 8080

### Managed Identity
- Access to Key Vault (secrets)
- Access to ACR (image pull)

### Secrets (from Key Vault)
- `DB-CONNECTION-STRING` → Database connection
- `COMPUTE-API-KEY` → Rhino.Compute authentication

### Environment Variables
- `NODE_ENV=production`
- `PORT=8080`
- `COMPUTE_URL=http://20.73.173.209:8081`
- `DATABASE_URL` (from Key Vault)
- `COMPUTE_API_KEY` (from Key Vault)

## 💰 Cost Estimate

- **Container App**: ~$10-15/month
  - 0.5 vCPU, 1GB RAM
  - 1-3 replicas (1 always-on)

## 🚀 Deployment Steps

### Step 1: Verify Prerequisites

```bash
# Check ACR image exists
az acr repository show-tags \
  --name kudusodevacr93d2ab \
  --repository appserver-node \
  --output table

# Should show: f75482e, latest
```

### Step 2: Review Configuration

Check `infra/live/dev/shared/appserver/terragrunt.hcl`:

```hcl
# Image
app_image = "appserver-node:f75482e"

# Rhino.Compute URL (update if needed)
rhino_compute_url = "http://20.73.173.209:8081" # Real VM
# rhino_compute_url = "http://mock-compute:8081" # Mock for testing

# Network
enable_ingress = false # Internal only
```

### Step 3: Deploy

```bash
cd infra/live/dev/shared/appserver

# Initialize
terragrunt init

# Review plan
terragrunt plan

# Deploy (takes ~2-3 minutes)
terragrunt apply
```

### Step 4: Verify Deployment

```bash
# Get outputs
terragrunt output

# Check app status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "{name:name, provisioningState:properties.provisioningState, runningStatus:properties.runningStatus}"
```

### Step 5: View Logs

```bash
# Real-time logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --follow

# Or specific container
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --container appserver \
  --tail 50
```

---

## ✅ Verification

### Check Container is Running

```bash
az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas, createdTime:properties.createdTime}" \
  --output table
```

### Check Health (Internal Only)

Since AppServer has no external ingress, you can't curl it directly. You'll test it once API/Worker apps are deployed.

For now, check logs for startup messages:
```bash
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --tail 20
```

### Verify Managed Identity

```bash
# Get identity ID
cd infra/live/dev/shared/appserver
IDENTITY_ID=$(terragrunt output -raw identity_principal_id)

# Check Key Vault access
az role assignment list \
  --assignee $IDENTITY_ID \
  --query "[?roleDefinitionName=='Key Vault Secrets User']"

# Check ACR access
az role assignment list \
  --assignee $IDENTITY_ID \
  --query "[?roleDefinitionName=='AcrPull']"
```

---

## 🔧 Configuration Options

### Use Mock Rhino.Compute

If Rhino VM isn't ready, use mock:

```hcl
# Edit infra/live/dev/shared/appserver/terragrunt.hcl
rhino_compute_url = "http://mock-compute:8081"
```

Then apply:
```bash
terragrunt apply
```

### Enable External Access (Testing Only)

Not recommended, but if needed:

```hcl
enable_ingress = true
```

Then access via:
```bash
APPSERVER_URL=$(terragrunt output -raw app_url)
curl $APPSERVER_URL/health
```

### Adjust Resources

```hcl
cpu    = "1"    # 1 vCPU
memory = "2Gi"  # 2 GB RAM

min_replicas = 2  # Always 2 replicas
max_replicas = 5  # Scale up to 5
```

---

## 🐛 Troubleshooting

### Deployment Fails - ACR Image Not Found

Check image exists:
```bash
az acr repository show-tags \
  --name kudusodevacr93d2ab \
  --repository appserver-node
```

If missing, rebuild and push:
```bash
cd shared/appserver-node
docker build -t kudusodevacr93d2ab.azurecr.io/appserver-node:f75482e .
docker push kudusodevacr93d2ab.azurecr.io/appserver-node:f75482e
```

### Deployment Fails - Key Vault Access

Verify secrets exist:
```bash
cd infra/live/dev/shared/core
KV_NAME=$(terragrunt output -raw key_vault_name)

az keyvault secret list --vault-name $KV_NAME --query "[].name"
```

Should have:
- `DB-CONNECTION-STRING`
- `COMPUTE-API-KEY`

### Container Keeps Restarting

Check logs:
```bash
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --tail 100
```

Common issues:
1. **Missing health endpoints**: App must respond to `/health` and `/ready`
2. **Database connection failed**: Check `DATABASE_URL` secret
3. **Port mismatch**: App must listen on port 8080

### Can't See Logs

Wait a few seconds after deployment, then try:
```bash
# Give it time to start
sleep 30

# Try again
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --follow
```

---

## 📝 Next Steps

After AppServer is deployed:

### Option A: Test with Rhino.Compute ⭐
**Time**: 5 minutes

If Rhino VM is ready:
1. Verify Rhino.Compute is running
2. Check AppServer can connect
3. View logs for compute requests

### Option B: Create App Stack Module
**Time**: 30 minutes

Deploy the complete app stack:
- Service Bus queue
- API app (external, calls AppServer)
- Worker app (internal, calls AppServer)
- KEDA autoscaling

**Recommended**: Do this next to complete Stage 2!

### Option C: Update AppServer Code
**Time**: Variable

If you need to modify the AppServer code:
1. Make changes in `shared/appserver-node/`
2. Rebuild image
3. Push to ACR
4. Update `app_image` in terragrunt.hcl
5. `terragrunt apply`

---

## 🎯 Summary

### Resources Created
- ✅ Managed Identity
- ✅ Role Assignment (Key Vault)
- ✅ Role Assignment (ACR)
- ✅ Container App (internal)

### What You Get
- Internal-only AppServer
- Auto-scaling (1-3 replicas)
- Health probes configured
- Secrets from Key Vault
- Connected to Rhino.Compute
- Ready to be called by API/Worker

**Ready to deploy? Run the commands above!**
