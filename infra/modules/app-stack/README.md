# App Stack Module

Terraform module for deploying a complete application stack with API and Worker Container Apps. This module creates:

- **Service Bus Queue**: Message queue for async processing
- **API Container App**: External HTTPS endpoint
- **Worker Container App**: Internal worker with KEDA autoscaling

## Features

- **External API**: HTTPS endpoint with auto-scaling (1-5 replicas)
- **Internal Worker**: Queue-triggered processing with scale-to-zero (0-10 replicas)
- **KEDA Autoscaling**: Scales based on Service Bus queue length
- **Managed Identities**: Secure access to Key Vault, ACR, and Service Bus
- **Health Probes**: Liveness and readiness checks
- **Secrets Management**: Key Vault integration

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Internet (HTTPS)                            │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
           ┌─────────────────────┐
           │   API Container     │
           │   (External)        │
           │   • HTTPS Ingress   │
           │   • 1-5 replicas    │
           └──────┬──────┬───────┘
                  │      │
    ──────────────┘      └────────────────┐
    │                                     │
    ▼                                     ▼
┌─────────────────────┐     ┌──────────────────────────┐
│   AppServer         │     │   Service Bus Queue      │
│   (Shared)          │     │   • Message storage      │
│   • Validation      │     │   • Dead letter queue    │
│   • Compute routing │     └──────────┬───────────────┘
└─────────────────────┘                │
                                       │ (KEDA triggers)
                                       ▼
                         ┌──────────────────────────┐
                         │   Worker Container       │
                         │   (Internal)             │
                         │   • Queue processing     │
                         │   • 0-10 replicas        │
                         │   • Scale to zero        │
                         └──────────┬───────────────┘
                                    │
                                    ▼
                         ┌──────────────────────────┐
                         │   AppServer              │
                         │   (Shared)               │
                         │   • Compute requests     │
                         └──────────────────────────┘
```

## Cost Estimate

- **Service Bus Queue**: ~$0 (included in namespace)
- **API Container App**: ~$8-10/month (0.5 vCPU, 1GB RAM, 1-5 replicas)
- **Worker Container App**: ~$7-10/month (0.5 vCPU, 1GB RAM, scales 0-10)

**Total**: ~$15-20/month per application

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for resources | string | - | yes |
| app_name | Application name | string | - | yes |
| resource_group_name | Resource group | string | - | yes |
| location | Azure region | string | - | yes |
| container_apps_environment_id | CAE ID | string | - | yes |
| container_registry_server | ACR server | string | - | yes |
| servicebus_namespace_id | Service Bus namespace ID | string | - | yes |
| key_vault_id | Key Vault ID | string | - | yes |
| key_vault_uri | Key Vault URI | string | - | yes |
| appserver_url | AppServer URL | string | http://kuduso-dev-appserver:8080 | no |
| api_image | API container image | string | api-node:latest | no |
| api_cpu | API CPU allocation | string | 0.5 | no |
| api_memory | API memory allocation | string | 1Gi | no |
| api_min_replicas | API min replicas | number | 1 | no |
| api_max_replicas | API max replicas | number | 5 | no |
| worker_image | Worker container image | string | worker-node:latest | no |
| worker_cpu | Worker CPU allocation | string | 0.5 | no |
| worker_memory | Worker memory allocation | string | 1Gi | no |
| worker_min_replicas | Worker min replicas | number | 0 | no |
| worker_max_replicas | Worker max replicas | number | 10 | no |
| keda_queue_length | Queue length threshold | number | 5 | no |

## Outputs

| Name | Description |
|------|-------------|
| queue_name | Service Bus queue name |
| api_url | API HTTPS URL |
| api_name | API Container App name |
| worker_name | Worker Container App name |
| deployment_summary | Summary of deployed resources |

## Usage

### 1. Deploy with Terragrunt

```bash
cd infra/live/dev/apps/sitefit
terragrunt init
terragrunt plan
terragrunt apply
```

### 2. Configure KEDA Scaling

After Terraform deployment, configure KEDA (required):

```bash
cd infra/modules/app-stack

chmod +x configure-keda.sh

./configure-keda.sh \
  kuduso-dev-rg \
  kuduso-dev-sitefit-worker \
  sitefit-queue \
  kuduso-dev-servicebus \
  5
```

### 3. Verify Deployment

```bash
# Get outputs
terragrunt output

# Check API status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --query "{name:name, url:properties.configuration.ingress.fqdn, status:properties.runningStatus}"

# Check Worker status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "{name:name, replicas:properties.template.scale, status:properties.runningStatus}"

# Check queue
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "{name:name, messageCount:messageCount}"
```

---

## API Container App

### Configuration

- **Ingress**: External HTTPS
- **Port**: 3000
- **Scaling**: 1-5 replicas based on HTTP load
- **Resources**: 0.5 vCPU, 1GB RAM

### Environment Variables

```bash
NODE_ENV=production
PORT=3000
APP_NAME=sitefit
APPSERVER_URL=http://kuduso-dev-appserver:8080
QUEUE_NAME=sitefit-queue
DATABASE_URL=<from Key Vault>
SERVICEBUS_CONNECTION_STRING=<from Key Vault>
AZURE_CLIENT_ID=<managed identity>
```

### Health Endpoints

- **Liveness**: `GET /health` (every 30s)
- **Readiness**: `GET /ready` (every 10s)

### Example API Request

```bash
# Get API URL
API_URL=$(terragrunt output -raw api_url)

# Test health
curl $API_URL/health

# Example API call
curl -X POST $API_URL/api/v1/contracts \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Contract",
    "geometry": {...}
  }'
```

---

## Worker Container App

### Configuration

- **Ingress**: None (internal only)
- **Port**: 8080
- **Scaling**: 0-10 replicas via KEDA
- **Resources**: 0.5 vCPU, 1GB RAM

### Environment Variables

```bash
NODE_ENV=production
APP_NAME=sitefit
APPSERVER_URL=http://kuduso-dev-appserver:8080
QUEUE_NAME=sitefit-queue
DATABASE_URL=<from Key Vault>
SERVICEBUS_CONNECTION_STRING=<from Key Vault>
AZURE_CLIENT_ID=<managed identity>
```

### KEDA Scaling Behavior

- **Scale to Zero**: When queue is empty
- **Scale Up**: When messages > 5 per replica
- **Max Replicas**: 10
- **Polling Interval**: 30 seconds
- **Cooldown**: 5 minutes before scaling down

### Scaling Example

```
Queue Messages | Workers
---------------|--------
0              | 0
1-5            | 1
6-10           | 2
11-15          | 3
...            | ...
50+            | 10 (max)
```

---

## Service Bus Queue

### Configuration

- **Name**: `{app_name}-queue` (e.g., `sitefit-queue`)
- **Partitioning**: Enabled
- **Max Delivery Count**: 10
- **Message TTL**: 14 days
- **Lock Duration**: 5 minutes
- **Dead Letter**: Enabled on expiration

### Sending Messages

```javascript
// From API app
const { ServiceBusClient } = require('@azure/service-bus');

const client = new ServiceBusClient(process.env.SERVICEBUS_CONNECTION_STRING);
const sender = client.createSender(process.env.QUEUE_NAME);

await sender.sendMessages({
  body: {
    contractId: '123',
    operation: 'process',
    data: {...}
  }
});
```

### Processing Messages

```javascript
// From Worker app
const receiver = client.createReceiver(process.env.QUEUE_NAME);

receiver.subscribe({
  processMessage: async (message) => {
    console.log('Processing:', message.body);
    // Process message
    await message.complete();
  },
  processError: async (error) => {
    console.error('Error:', error);
  }
});
```

---

## Managed Identities

### API Identity Permissions

- ✅ Key Vault Secrets User
- ✅ ACR Pull

### Worker Identity Permissions

- ✅ Key Vault Secrets User
- ✅ ACR Pull
- ✅ Azure Service Bus Data Receiver

---

## Monitoring

### View API Logs

```bash
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --follow
```

### View Worker Logs

```bash
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --follow
```

### Check Queue Metrics

```bash
# Active messages
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.activeMessageCount"

# Dead letter messages
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.deadLetterMessageCount"
```

### Check Worker Scaling

```bash
# Current replicas
az containerapp revision list \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "[0].{revision:name, replicas:properties.replicas, active:properties.active}"
```

---

## Troubleshooting

### API Not Responding

```bash
# Check status
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --query "properties.runningStatus"

# Check logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-api \
  --tail 50
```

### Worker Not Scaling

```bash
# Check KEDA scale rules
az containerapp show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --query "properties.template.scale"

# Reconfigure KEDA
cd infra/modules/app-stack
./configure-keda.sh kuduso-dev-rg kuduso-dev-sitefit-worker sitefit-queue kuduso-dev-servicebus 5
```

### Messages Not Processing

```bash
# Check queue
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue

# Check worker logs
az containerapp logs show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-sitefit-worker \
  --tail 100
```

### Check Dead Letter Queue

```bash
# View dead letter messages
az servicebus queue show \
  --resource-group kuduso-dev-rg \
  --namespace-name kuduso-dev-servicebus \
  --name sitefit-queue \
  --query "countDetails.deadLetterMessageCount"
```

---

## Updates

### Update API Image

```bash
# Build and push new image
docker build -t kudusodevacr93d2ab.azurecr.io/api-node:new-tag apps/sitefit/api
docker push kudusodevacr93d2ab.azurecr.io/api-node:new-tag

# Update terragrunt config
# Edit api_image in terragrunt.hcl

# Redeploy
terragrunt apply
```

### Update Worker Image

```bash
# Build and push new image
docker build -t kudusodevacr93d2ab.azurecr.io/worker-node:new-tag apps/sitefit/worker
docker push kudusodevacr93d2ab.azurecr.io/worker-node:new-tag

# Update terragrunt config
# Edit worker_image in terragrunt.hcl

# Redeploy
terragrunt apply

# Reconfigure KEDA
./configure-keda.sh ...
```

---

## Security

✅ **Managed Identities**: No credentials in code  
✅ **Key Vault Integration**: Secrets managed centrally  
✅ **RBAC**: Minimal required permissions  
✅ **External API Only**: Worker is internal  
✅ **HTTPS**: API uses HTTPS only  

---

## Cleanup

```bash
cd infra/live/dev/apps/sitefit
terragrunt destroy
```

This removes:
- API Container App
- Worker Container App
- Service Bus Queue
- Managed Identities
- Role Assignments

**Note**: Shared resources (CAE, Service Bus namespace, Key Vault) are not removed.
