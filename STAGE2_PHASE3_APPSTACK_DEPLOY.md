# Stage 2 - Phase 3: Deploy App Stack Module

## 🎯 Goal

Deploy the complete sitefit application stack with API, Worker, and Service Bus queue.

## 📋 What We Created

### Terraform Module
```
infra/modules/app-stack/
├── variables.tf           ✅ 30+ input variables
├── main.tf                ✅ Queue + API + Worker + Identities
├── outputs.tf             ✅ 15 outputs
├── configure-keda.sh      ✅ KEDA configuration script
└── README.md              ✅ Complete documentation
```

### Configuration
```
infra/live/dev/apps/sitefit/
└── terragrunt.hcl         ✅ Sitefit app configuration
```

## 🏗️ What Will Be Deployed

### 1. Service Bus Queue
- **Name**: `sitefit-queue`
- **Partitioning**: Enabled
- **Dead Letter**: Enabled
- **Message TTL**: 14 days

### 2. API Container App
- **Name**: `kuduso-dev-sitefit-api`
- **Image**: `api-node:f75482e`
- **Resources**: 0.5 vCPU, 1GB RAM
- **Scaling**: 1-5 replicas
- **Access**: External HTTPS
- **Port**: 3000

### 3. Worker Container App
- **Name**: `kuduso-dev-sitefit-worker`
- **Image**: `worker-node:f75482e`
- **Resources**: 0.5 vCPU, 1GB RAM
- **Scaling**: 0-10 replicas (KEDA)
- **Access**: Internal only
- **Trigger**: Service Bus queue

### 4. Managed Identities
- API identity (Key Vault + ACR access)
- Worker identity (Key Vault + ACR + Service Bus access)

## 💰 Cost Estimate

- **Service Bus Queue**: ~$0 (included in namespace)
- **API Container App**: ~$8-10/month
- **Worker Container App**: ~$7-10/month

**Total**: ~$15-20/month

**Updated Platform Total**: ~$73-83/month

---

## 🚀 Deployment Steps

### Step 1: Review Configuration

Check `infra/live/dev/apps/sitefit/terragrunt.hcl`:

```hcl
# Application name
app_name = "sitefit"

# Images
api_image    = "api-node:f75482e"
worker_image = "worker-node:f75482e"

# AppServer URL
appserver_url = "http://kuduso-dev-appserver:8080"

# API Scaling
api_min_replicas = 1
api_max_replicas = 5

# Worker Scaling
worker_min_replicas = 0  # Scale to zero!
worker_max_replicas = 10

# KEDA Settings
keda_queue_length = 5  # Scale when > 5 messages per replica
```

### Step 2: Initialize Terraform

```bash
cd infra/live/dev/apps/sitefit

terragrunt init
```

### Step 3: Review Plan

```bash
terragrunt plan
```

**Expected resources**: 8 to add
- 1 Service Bus queue
- 2 Managed identities
- 2 Container Apps
- 5 Role assignments

### Step 4: Deploy

```bash
terragrunt apply
```

**Deployment time**: ~3-5 minutes

### Step 5: Configure KEDA Scaling

After Terraform completes, configure KEDA:

```bash
cd ../../../modules/app-stack

./configure-keda.sh \
  kuduso-dev-rg \
  kuduso-dev-sitefit-worker \
  sitefit-queue \
  kuduso-dev-servicebus \
  5
```

This configures the Worker to:
- Scale to **0** when queue is empty
- Scale up when messages > **5** per replica
- Scale to max **10** replicas

### Step 6: Get Deployment Outputs

```bash
cd ../../../live/dev/apps/sitefit

# Get all outputs
terragrunt output

# Get API URL
API_URL=$(terragrunt output -raw api_url)
echo "API URL: $API_URL"
```

---

## ✅ Verification

### Check API Status

```bash
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --query "{name:name, url:properties.configuration.ingress.fqdn, status:properties.runningStatus}"
```

### Check Worker Status

```bash
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "{name:name, status:properties.runningStatus}"
```

### Check Queue

```bash
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "{name:name, activeMessages:countDetails.activeMessageCount}"
```

### Test API Health

```bash
# Get API URL
cd infra/live/dev/apps/sitefit
API_URL=$(terragrunt output -raw api_url)

# Test health endpoint
curl $API_URL/health

# Test readiness endpoint
curl $API_URL/ready
```

### View Logs

```bash
# API logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --tail 30

# Worker logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --tail 30
```

---

## 🔧 Testing the Stack

### Test 1: API Health Check

```bash
curl https://<api-url>/health
```

Expected: `{"status":"healthy"}`

### Test 2: Send Message to Queue

```bash
# This would be done by the API in production
# For testing, use Azure Portal or Azure CLI
az servicebus queue message send \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --queue-name sitefit-queue \
  --body '{"test":"message"}'
```

### Test 3: Watch Worker Scale

```bash
# Send 10 messages
for i in {1..10}; do
  az servicebus queue message send \
    --resource-group kuduso-dev-rg \
    --namespace-name kuduso-dev-servicebus \
    --queue-name sitefit-queue \
    --body "{\"message\":$i}"
done

# Watch worker scale (should go from 0 to 2 replicas)
watch -n 5 'az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "[0].properties.replicas"'
```

### Test 4: Verify AppServer Communication

Check logs for AppServer calls:

```bash
# API should call AppServer for validation
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --tail 20 | grep -i appserver

# Worker should call AppServer for compute
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --tail 20 | grep -i appserver
```

---

## 🐛 Troubleshooting

### API Not Responding

**Check deployment:**
```bash
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --query "properties.provisioningState"
```

**Check logs:**
```bash
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --tail 50
```

**Common issues:**
- Missing health endpoints (`/health`, `/ready`)
- Image pull failed
- Key Vault secrets not accessible
- AppServer not reachable

### Worker Not Scaling

**Check KEDA configuration:**
```bash
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "properties.template.scale"
```

**Reconfigure KEDA:**
```bash
cd infra/modules/app-stack
./configure-keda.sh kuduso-dev-rg kuduso-dev-sitefit-worker sitefit-queue kuduso-dev-servicebus 5
```

**Check Service Bus permissions:**
```bash
# Get worker identity
WORKER_IDENTITY=$(az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "identity.userAssignedIdentities[].principalId" \
  --output tsv)

# Check role assignments
az role assignment list \
  --assignee $WORKER_IDENTITY \
  --query "[?roleDefinitionName=='Azure Service Bus Data Receiver']"
```

### Messages Not Processing

**Check queue messages:**
```bash
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "{active:countDetails.activeMessageCount, deadLetter:countDetails.deadLetterMessageCount}"
```

**Check worker logs:**
```bash
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --follow
```

**Check dead letter queue:**
```bash
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.deadLetterMessageCount"
```

### Can't Access AppServer

The API and Worker need to call AppServer internally:

```bash
# Check AppServer is running
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "properties.runningStatus"

# Verify apps are in same environment
az containerapp list \
  --resource-group kuduso-dev-rg \
  --query "[].{name:name, environment:properties.environmentId}" \
  --output table
```

AppServer URL should be: `http://kuduso-dev-appserver:8080`

---

## 🔄 Updates and Redeployment

### Update API Image

```bash
# Build and push
cd apps/sitefit/api
docker build -t kudusodevacr93d2ab.azurecr.io/api-node:new-tag .
docker push kudusodevacr93d2ab.azurecr.io/api-node:new-tag

# Update config
cd infra/live/dev/apps/sitefit
# Edit terragrunt.hcl: api_image = "api-node:new-tag"

# Redeploy
terragrunt apply
```

### Update Worker Image

```bash
# Build and push
cd apps/sitefit/worker
docker build -t kudusodevacr93d2ab.azurecr.io/worker-node:new-tag .
docker push kudusodevacr93d2ab.azurecr.io/worker-node:new-tag

# Update config
cd infra/live/dev/apps/sitefit
# Edit terragrunt.hcl: worker_image = "worker-node:new-tag"

# Redeploy
terragrunt apply

# Reconfigure KEDA
cd ../../modules/app-stack
./configure-keda.sh kuduso-dev-rg kuduso-dev-sitefit-worker sitefit-queue kuduso-dev-servicebus 5
```

### Adjust Scaling

```hcl
# Edit infra/live/dev/apps/sitefit/terragrunt.hcl

# API scaling
api_min_replicas = 2  # Always 2 replicas
api_max_replicas = 10 # Scale up to 10

# Worker scaling
worker_max_replicas = 20  # Scale up to 20

# KEDA threshold
keda_queue_length = 10  # Scale when > 10 messages
```

Then apply:
```bash
terragrunt apply

# Reconfigure KEDA with new threshold
cd ../../modules/app-stack
./configure-keda.sh kuduso-dev-rg kuduso-dev-sitefit-worker sitefit-queue kuduso-dev-servicebus 10
```

---

## 🎯 Success Criteria

✅ API Container App is running  
✅ API has external HTTPS endpoint  
✅ Worker Container App is deployed  
✅ Worker scales to 0 when idle  
✅ Service Bus queue exists  
✅ KEDA scaling configured  
✅ Managed identities have correct permissions  
✅ Both apps can access AppServer  
✅ Both apps can access Key Vault secrets  

---

## 📊 What's Next

After successful deployment:

1. **Test the Complete Flow**
   - Send API request
   - Verify queue message
   - Watch worker scale up
   - Check processing logs

2. **Move to Stage 3: Code Changes**
   - Update application code
   - Implement API endpoints
   - Implement worker logic
   - Add proper error handling

3. **Production Readiness**
   - Add monitoring & alerts
   - Configure custom domains
   - Set up CI/CD pipelines
   - Review security settings

---

## 🎊 Summary

This completes the infrastructure deployment for Stage 2!

**Deployed Resources:**
- ✅ Platform Core (CAE, ACR, Key Vault, Service Bus, Storage, Logs)
- ✅ Rhino VM (Windows Server 2022, Rhino.Compute)
- ✅ AppServer (Shared validation & compute routing)
- ✅ Sitefit App Stack (API + Worker + Queue)

**Total Monthly Cost**: ~$73-83

**Ready for deployment?**
