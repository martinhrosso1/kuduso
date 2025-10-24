# Kuduso Infrastructure

Infrastructure as Code (IaC) using OpenTofu/Terraform + Terragrunt for Azure deployment.

## Structure

```
infra/
├── modules/              # Reusable Terraform modules
│   ├── shared-core/      # Platform resources (RG, ACR, KV, Storage, SB, ACA env)
│   ├── shared-appserver/ # AppServer (internal ACA app)
│   ├── app-stack/        # Per-app stack (API, Worker, Queue)
│   └── rhino-vm/         # Rhino Compute VM (dev only)
├── live/                 # Environment-specific configurations
│   └── dev/
│       ├── shared/       # Shared platform resources
│       │   ├── core/
│       │   ├── rhino/
│       │   └── appserver/
│       └── apps/         # Application-specific resources
│           └── sitefit/
└── terragrunt.hcl        # Root configuration
```

## Prerequisites

1. **Azure CLI**: Logged in with appropriate permissions
   ```bash
   az login
   az account show
   ```

2. **OpenTofu or Terraform**: Version >= 1.6
   ```bash
   tofu version  # or: terraform version
   ```

3. **Terragrunt**: Latest version
   ```bash
   terragrunt --version
   ```

## Quick Start

### 1. Setup State Backend

Create Azure Storage for Terraform state:

```bash
./scripts/setup-state-backend.sh
```

This creates:
- Resource Group: `kuduso-tfstate-rg`
- Storage Account: `kudusotfstate`
- Container: `tfstate`

Export the storage account name:
```bash
export TF_STATE_STORAGE_ACCOUNT=kudusotfstate
```

### 2. Deploy Platform Core (Stage 2, Phase 1)

Deploy shared platform resources:

```bash
cd infra/live/dev/shared/core
terragrunt init
terragrunt plan
terragrunt apply
```

This creates:
- ✅ Resource Group
- ✅ Azure Container Registry
- ✅ Log Analytics Workspace
- ✅ Key Vault
- ✅ Storage Account + artifacts container
- ✅ Service Bus Namespace
- ✅ Container Apps Environment

### 3. Verify Deployment

Check created resources:

```bash
# Get outputs
terragrunt output

# List resources in resource group
az resource list --resource-group kuduso-dev-rg --output table
```

## Module Details

### shared-core

**Inputs:**
- `name_prefix`: Prefix for resource names (e.g., "kuduso-dev")
- `location`: Azure region (default: "westeurope")
- `environment`: Environment name (default: "dev")
- `log_retention_days`: Log Analytics retention (default: 30)
- `servicebus_sku`: Service Bus SKU (default: "Standard")

**Outputs:**
- Resource Group: name, id, location
- ACR: name, server, id
- Log Analytics: workspace id, name
- Key Vault: id, name, uri
- Storage: account name, id, artifacts container
- Service Bus: namespace name, id, connection string
- ACA Environment: id, name, default domain

## Next Steps

After deploying shared-core:

1. **Build & Push Images** to ACR
2. **Deploy Rhino VM** (shared/rhino)
3. **Deploy AppServer** (shared/appserver)
4. **Deploy App Stack** (apps/sitefit)

## Commands

```bash
# Initialize Terragrunt
terragrunt init

# Plan changes
terragrunt plan

# Apply changes
terragrunt apply

# Destroy resources (careful!)
terragrunt destroy

# Run for all modules in directory
terragrunt run-all init
terragrunt run-all plan
terragrunt run-all apply
```

## Security Notes

- State is stored in Azure Storage with encryption at rest
- Key Vault uses RBAC authorization
- Storage accounts have public access disabled
- Secrets are managed via Key Vault, never in code
- Managed identities used for service authentication

## Cost Management

- Worker apps default to `min_replicas=0` (scale to zero)
- Log Analytics retention set to 30 days
- Storage uses LRS (locally redundant)
- Service Bus uses Standard tier
- ACR uses Basic tier (upgrade to Standard for production)

## Troubleshooting

### State Backend Issues

If you get state backend errors:
```bash
export TF_STATE_STORAGE_ACCOUNT=kudusotfstate
cd infra/live/dev/shared/core
terragrunt init -reconfigure
```

### Authentication Issues

Ensure Azure CLI is logged in:
```bash
az account show
az account set --subscription <subscription-id>
```

### Resource Naming Conflicts

If resource names conflict:
- Check `name_prefix` in inputs
- Verify no existing resources with same names
- Module adds random suffix to some names (ACR, KV, Storage)
