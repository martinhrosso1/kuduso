# Stage 2 Deployment Guide

Step-by-step guide to deploy Stage 2 infrastructure.

## Overview

Stage 2 sets up the Azure cloud infrastructure using OpenTofu + Terragrunt:

**Phase 1 (Current)**: Platform Core
- Resource Group, ACR, Log Analytics, Key Vault, Storage, Service Bus, ACA Environment

**Phase 2 (Next)**: Images + Rhino VM + AppServer

**Phase 3 (Final)**: App Stack (API + Worker + Queue)

---

## Phase 1: Deploy Platform Core

### Step 1: Setup State Backend

```bash
# Run the setup script
./scripts/setup-state-backend.sh

# Export the storage account name
export TF_STATE_STORAGE_ACCOUNT=kudusotfstate

# Add to your shell profile to persist
echo 'export TF_STATE_STORAGE_ACCOUNT=kudusotfstate' >> ~/.bashrc
```

### Step 2: Verify Azure Login

```bash
# Check current subscription
az account show

# If needed, switch subscription
az account set --subscription <subscription-id>

# List available subscriptions
az account list --output table
```

### Step 3: Deploy shared-core

```bash
# Navigate to the module
cd infra/live/dev/shared/core

# Initialize Terragrunt (downloads providers, sets up backend)
terragrunt init

# Review the plan
terragrunt plan

# Apply (creates resources)
terragrunt apply
```

**Expected resources created:**
- `kuduso-dev-rg` - Resource Group
- `kudusodevacrXXXXXX` - Azure Container Registry
- `kuduso-dev-law` - Log Analytics Workspace
- `kuduso-dev-kv-XXXXXX` - Key Vault
- `kudusdevstXXXXXX` - Storage Account
- `artifacts` - Blob container
- `kuduso-dev-sb` - Service Bus Namespace
- `kuduso-dev-aca-env` - Container Apps Environment

### Step 4: Verify Deployment

```bash
# Get outputs
terragrunt output

# Save important outputs
ACR_SERVER=$(terragrunt output -raw acr_server)
KV_NAME=$(terragrunt output -raw key_vault_name)
SB_NAMESPACE=$(terragrunt output -raw servicebus_namespace_name)

echo "ACR Server: $ACR_SERVER"
echo "Key Vault: $KV_NAME"
echo "Service Bus: $SB_NAMESPACE"

# List all resources
az resource list --resource-group kuduso-dev-rg --output table
```

### Step 5: Setup Secrets in Key Vault

Now manually create secrets that will be used by services:

```bash
# Get Key Vault name
KV_NAME=$(cd infra/live/dev/shared/core && terragrunt output -raw key_vault_name)

# Grant yourself Key Vault Secrets Officer role (needed to create secrets)
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv)
KV_ID=$(cd infra/live/dev/shared/core && terragrunt output -raw key_vault_id)

az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee $CURRENT_USER_ID \
  --scope $KV_ID

# Wait a few seconds for RBAC to propagate
sleep 10

# Create placeholder secrets (we'll update these later)
az keyvault secret set --vault-name $KV_NAME --name DATABASE-URL --value "placeholder-will-update-after-supabase"
az keyvault secret set --vault-name $KV_NAME --name SERVICEBUS-CONN --value "placeholder-will-update-later"
az keyvault secret set --vault-name $KV_NAME --name BLOB-SAS-SIGNING --value "placeholder-will-update-later"
az keyvault secret set --vault-name $KV_NAME --name COMPUTE-API-KEY --value "placeholder-will-update-later"

echo "✅ Placeholder secrets created in Key Vault"
```

---

## Phase 1 Complete! ✅

You now have:
- ✅ State backend configured
- ✅ Platform core infrastructure deployed
- ✅ Key Vault with placeholder secrets
- ✅ ACR ready for container images
- ✅ Service Bus namespace ready
- ✅ ACA environment ready
- ✅ Storage account with artifacts container

## Next Steps

### Immediate (Optional - Verify)

Test that everything works:

```bash
# Test ACR login
ACR_NAME=$(cd infra/live/dev/shared/core && terragrunt output -raw acr_name)
az acr login --name $ACR_NAME

# Test Key Vault access
KV_NAME=$(cd infra/live/dev/shared/core && terragrunt output -raw key_vault_name)
az keyvault secret list --vault-name $KV_NAME --output table

# Test Storage access
ST_NAME=$(cd infra/live/dev/shared/core && terragrunt output -raw storage_account_name)
az storage container list --account-name $ST_NAME --auth-mode login --output table
```

### Phase 2: Build & Push Images

Before deploying AppServer and apps, we need to build and push Docker images to ACR.

```bash
# Get ACR server
cd infra/live/dev/shared/core
ACR_SERVER=$(terragrunt output -raw acr_server)
ACR_NAME=$(terragrunt output -raw acr_name)

# Login to ACR
az acr login --name $ACR_NAME

# Build and tag images
GIT_SHA=$(git rev-parse --short HEAD)

docker build -t $ACR_SERVER/appserver-node:$GIT_SHA ./shared/appserver-node
docker build -t $ACR_SERVER/api-fastapi:$GIT_SHA ./apps/sitefit/api-fastapi
docker build -t $ACR_SERVER/worker-fastapi:$GIT_SHA ./apps/sitefit/worker-fastapi

# Push images
docker push $ACR_SERVER/appserver-node:$GIT_SHA
docker push $ACR_SERVER/api-fastapi:$GIT_SHA
docker push $ACR_SERVER/worker-fastapi:$GIT_SHA

# Save the image tag for later use
export IMG_SHA=$GIT_SHA
echo "export IMG_SHA=$GIT_SHA" >> ~/.bashrc
```

### Phase 3: Deploy remaining infrastructure

After images are pushed and Supabase is configured:

1. **Create Supabase project** (manual via UI)
2. **Update Key Vault secrets** with real values
3. **Deploy Rhino VM** (shared/rhino module - to be created)
4. **Deploy AppServer** (shared/appserver module - to be created)
5. **Deploy App Stack** (apps/sitefit module - to be created)

---

## Troubleshooting

### Error: "resource group already exists"

If deployment partially succeeded, you can continue:
```bash
terragrunt init -reconfigure
terragrunt apply
```

### Error: "name already in use"

Some resources (ACR, Storage, Key Vault) need globally unique names. The module adds a random suffix, but if there's still a conflict:

1. Destroy and recreate:
   ```bash
   terragrunt destroy
   terragrunt apply
   ```

2. Or manually delete the conflicting resource in Azure Portal

### Key Vault RBAC Issues

If you can't create secrets:
```bash
# Grant yourself Secrets Officer role
KV_ID=$(terragrunt output -raw key_vault_id)
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee $CURRENT_USER_ID \
  --scope $KV_ID

# Wait for propagation
sleep 15
```

### State Lock Issues

If Terragrunt gets stuck with a state lock:
```bash
terragrunt force-unlock <lock-id>
```

---

## Cleanup (Destructive!)

To tear down all infrastructure:

```bash
cd infra/live/dev/shared/core
terragrunt destroy

# Optionally remove state backend
az group delete --name kuduso-tfstate-rg --yes --no-wait
```

---

**🎉 Phase 1 Complete! Ready for Phase 2: Images + Rhino VM + AppServer**
