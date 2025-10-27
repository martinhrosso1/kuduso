#!/bin/bash
# Script to configure KEDA scaling for Worker Container App
# This is needed because Terraform azurerm provider doesn't fully support KEDA scale rules yet

set -e

# Arguments
RESOURCE_GROUP=$1
WORKER_APP_NAME=$2
QUEUE_NAME=$3
SERVICEBUS_NAMESPACE=$4
QUEUE_LENGTH=${5:-5}

if [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKER_APP_NAME" ] || [ -z "$QUEUE_NAME" ] || [ -z "$SERVICEBUS_NAMESPACE" ]; then
  echo "Usage: $0 <resource_group> <worker_app_name> <queue_name> <servicebus_namespace> [queue_length]"
  echo "Example: $0 kuduso-dev-rg kuduso-dev-sitefit-worker sitefit-queue kuduso-dev-servicebus 5"
  exit 1
fi

echo "🔧 Configuring KEDA scaling for $WORKER_APP_NAME..."
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Queue: $QUEUE_NAME"
echo "  Namespace: $SERVICEBUS_NAMESPACE"
echo "  Queue Length Threshold: $QUEUE_LENGTH"

# Get the worker's managed identity client ID
IDENTITY_CLIENT_ID=$(az containerapp show \
  --name "$WORKER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "identity.userAssignedIdentities[].clientId" \
  --output tsv)

if [ -z "$IDENTITY_CLIENT_ID" ]; then
  echo "❌ Failed to get identity client ID"
  exit 1
fi

echo "  Identity Client ID: $IDENTITY_CLIENT_ID"

# Update the Container App with KEDA scale rule using Azure CLI
# Note: This uses the --scale-rule-* parameters
az containerapp update \
  --name "$WORKER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --scale-rule-name "queue-based-scaling" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata \
    queueName="$QUEUE_NAME" \
    namespace="$SERVICEBUS_NAMESPACE" \
    messageCount="$QUEUE_LENGTH" \
  --scale-rule-auth \
    triggerParameter=connection \
    secretRef=servicebus-connection \
  --min-replicas 0 \
  --max-replicas 10 \
  --output none

echo "✅ KEDA scaling configured successfully!"
echo ""
echo "Scale rule details:"
echo "  - Trigger: Azure Service Bus Queue"
echo "  - Queue: $QUEUE_NAME"
echo "  - Message count threshold: $QUEUE_LENGTH"
echo "  - Min replicas: 0 (scale to zero when queue is empty)"
echo "  - Max replicas: 10"
echo ""
echo "The worker will now:"
echo "  • Scale to 0 when queue is empty"
echo "  • Scale up when messages > $QUEUE_LENGTH per replica"
echo "  • Scale up to maximum 10 replicas"
