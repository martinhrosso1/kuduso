# Shared AppServer Module

Terraform module for deploying the shared AppServer to Azure Container Apps. This service handles:
- Contract validation
- Rhino.Compute routing
- Shared business logic

## Features

- **Internal Access Only**: No external ingress (accessed by API/Worker apps)
- **Managed Identity**: Secure access to Key Vault and ACR
- **Auto-scaling**: 1-3 replicas based on load
- **Health Probes**: Liveness, readiness, and startup probes
- **Secrets Management**: Key Vault integration
- **Container Registry**: Pulls images from ACR

## Architecture

```
┌─────────────────────────────────────────────────┐
│         Container Apps Environment              │
│                                                 │
│  ┌────────────┐      ┌─────────────────────┐   │
│  │ API App    │─────▶│   AppServer App     │   │
│  │ (external) │      │   (internal only)   │   │
│  └────────────┘      │                     │   │
│                      │  ┌────────────────┐ │   │
│  ┌────────────┐      │  │ Contract Val.  │ │   │
│  │ Worker App │─────▶│  │ Compute Route  │ │   │
│  │ (internal) │      │  └────────────────┘ │   │
│  └────────────┘      └─────────────────────┘   │
│                               │                 │
└───────────────────────────────┼─────────────────┘
                                │
                                ▼
                      ┌──────────────────┐
                      │ Rhino.Compute VM │
                      │  (or mock)       │
                      └──────────────────┘
```

## Cost Estimate

- **Container App**: ~$10-15/month (0.5 vCPU, 1GB RAM, 1-3 replicas)
- Always-on with min 1 replica

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for resources | string | - | yes |
| resource_group_name | Resource group | string | - | yes |
| location | Azure region | string | - | yes |
| container_apps_environment_id | CAE ID | string | - | yes |
| container_registry_server | ACR server | string | - | yes |
| container_registry_identity_id | ACR identity | string | - | yes |
| app_image | Container image | string | appserver-node:latest | no |
| key_vault_id | Key Vault ID | string | - | yes |
| cpu | CPU allocation | string | 0.5 | no |
| memory | Memory allocation | string | 1Gi | no |
| min_replicas | Min replicas | number | 1 | no |
| max_replicas | Max replicas | number | 3 | no |
| target_port | Container port | number | 8080 | no |
| rhino_compute_url | Rhino URL | string | http://mock-compute:8081 | no |
| enable_ingress | External ingress | bool | false | no |

## Outputs

| Name | Description |
|------|-------------|
| app_id | Container App ID |
| app_name | Container App name |
| app_fqdn | FQDN (if external) |
| app_url | Full URL |
| identity_principal_id | Managed identity principal ID |
| identity_client_id | Managed identity client ID |
| latest_revision_name | Latest revision |

## Usage

### 1. Deploy with Terragrunt

```bash
cd infra/live/dev/shared/appserver
terragrunt init
terragrunt plan
terragrunt apply
```

### 2. Verify Deployment

```bash
# Get app details
terragrunt output

# Check app status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "{name:name, provisioningState:properties.provisioningState, runningStatus:properties.runningStatus}"

# View logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --follow
```

### 3. Test the App (Internal)

Since AppServer has no external ingress, test from another Container App:

```bash
# From API or Worker app
curl http://kuduso-dev-appserver/health
curl http://kuduso-dev-appserver/ready
```

## Environment Variables

The app receives these environment variables:

| Variable | Source | Description |
|----------|--------|-------------|
| NODE_ENV | Static | `production` |
| PORT | Static | `8080` |
| COMPUTE_URL | Config | Rhino.Compute endpoint |
| DATABASE_URL | Key Vault | PostgreSQL connection string |
| COMPUTE_API_KEY | Key Vault | Rhino.Compute API key |
| AZURE_CLIENT_ID | Identity | For Key Vault auth |

## Health Probes

### Liveness Probe
- **Path**: `/health`
- **Initial Delay**: 10s
- **Interval**: 30s
- **Timeout**: 5s
- **Failure Threshold**: 3

### Readiness Probe
- **Path**: `/ready`
- **Interval**: 10s
- **Timeout**: 3s
- **Failure Threshold**: 3
- **Success Threshold**: 1

### Startup Probe
- **Path**: `/health`
- **Interval**: 5s
- **Timeout**: 3s
- **Failure Threshold**: 10

## Scaling

- **Min Replicas**: 1 (always-on)
- **Max Replicas**: 3
- **Auto-scale**: Based on HTTP traffic and CPU

Can be adjusted in `terragrunt.hcl`:
```hcl
inputs = {
  min_replicas = 2
  max_replicas = 5
}
```

## Secrets Management

Secrets are fetched from Key Vault at runtime:

1. **DB-CONNECTION-STRING**: PostgreSQL connection
2. **COMPUTE-API-KEY**: Rhino.Compute authentication

The app's managed identity has `Key Vault Secrets User` role.

## Connecting to Rhino.Compute

### Option 1: Real Rhino VM
```hcl
rhino_compute_url = "http://20.73.173.209:8081"
```

### Option 2: Mock (for testing)
```hcl
rhino_compute_url = "http://mock-compute:8081"
```

Switch between them by updating `terragrunt.hcl` and running `terragrunt apply`.

## Internal Networking

AppServer is **internal only** (`enable_ingress = false`):
- No public endpoint
- Accessible only within Container Apps Environment
- Other apps connect via: `http://kuduso-dev-appserver:8080`

To enable external access (not recommended):
```hcl
enable_ingress = true
```

## Monitoring

### View Logs
```bash
# Real-time logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --follow

# Container logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --container appserver \
  --tail 100
```

### View Metrics
```bash
# Get revision status
az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas}" \
  --output table
```

### Application Insights
If configured in the CAE, logs and metrics flow to Application Insights automatically.

## Troubleshooting

### App Not Starting

1. **Check image exists:**
   ```bash
   az acr repository show-tags \
     --name kudusodevacr93d2ab \
     --repository appserver-node
   ```

2. **Check logs:**
   ```bash
   az containerapp logs show \
     --resource-group kuduso-dev-rg \
     --name kuduso-dev-appserver \
     --tail 50
   ```

3. **Check secrets access:**
   ```bash
   # Verify identity has Key Vault access
   az role assignment list \
     --assignee <identity-principal-id> \
     --query "[?roleDefinitionName=='Key Vault Secrets User']"
   ```

### Can't Access from Other Apps

AppServer is internal only. Verify:
1. Both apps in same Container Apps Environment
2. Use internal FQDN: `http://kuduso-dev-appserver:8080`
3. Check firewall rules (if any)

### High Memory Usage

Increase memory allocation:
```hcl
memory = "2Gi"
```

Or scale out:
```hcl
min_replicas = 2
max_replicas = 5
```

### Rhino.Compute Connection Failed

1. **Check Rhino VM is running:**
   ```bash
   az vm show \
     --resource-group kuduso-dev-rg \
     --name kuduso-dev-rhino-vm \
     --query powerState
   ```

2. **Test connectivity:**
   ```bash
   curl http://20.73.173.209:8081/version
   ```

3. **Use mock for testing:**
   ```hcl
   rhino_compute_url = "http://mock-compute:8081"
   ```

## Updates and Deployments

### Update Image

```bash
# Build and push new image
cd shared/appserver-node
docker build -t kudusodevacr93d2ab.azurecr.io/appserver-node:new-tag .
docker push kudusodevacr93d2ab.azurecr.io/appserver-node:new-tag

# Update terragrunt config
# Edit infra/live/dev/shared/appserver/terragrunt.hcl
app_image = "appserver-node:new-tag"

# Apply
cd infra/live/dev/shared/appserver
terragrunt apply
```

### Update Configuration

Edit `terragrunt.hcl` and run:
```bash
terragrunt apply
```

### Rollback

```bash
# List revisions
az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --query "[].{name:name, active:properties.active, createdTime:properties.createdTime}"

# Activate previous revision
az containerapp revision activate \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-appserver \
  --revision <revision-name>
```

## Security

✅ **Managed Identity**: No credentials in code  
✅ **Key Vault**: Secrets managed centrally  
✅ **Internal Only**: No public exposure  
✅ **ACR Pull**: Secure image pulling  
✅ **RBAC**: Minimal required permissions  

## Production Considerations

For production:
- Increase replicas: `min_replicas = 2`
- Add Application Insights
- Configure custom domains
- Set up CI/CD pipeline
- Enable monitoring alerts
- Review resource allocations

## Cleanup

```bash
cd infra/live/dev/shared/appserver
terragrunt destroy
```

**Note**: This removes the Container App but not dependencies (CAE, ACR, Key Vault).
