#!/bin/bash
# Register Azure Resource Providers needed for shared-core resources
set -e

echo "🔧 Registering Azure Resource Providers..."
echo ""

# List of providers needed for shared-core
PROVIDERS=(
    "Microsoft.Storage"              # Already registered, but included for completeness
    "Microsoft.ContainerRegistry"    # ACR
    "Microsoft.OperationalInsights"  # Log Analytics
    "Microsoft.KeyVault"             # Key Vault
    "Microsoft.ServiceBus"           # Service Bus
    "Microsoft.App"                  # Container Apps
)

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription: $SUBSCRIPTION_ID"
echo ""

# Register each provider
for PROVIDER in "${PROVIDERS[@]}"; do
    echo "Checking $PROVIDER..."
    
    STATE=$(az provider show --namespace "$PROVIDER" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    
    if [ "$STATE" = "Registered" ]; then
        echo "  ✓ Already registered"
    else
        echo "  ⚙ Registering..."
        az provider register --namespace "$PROVIDER" --subscription "$SUBSCRIPTION_ID"
        echo "  ✓ Registration initiated"
    fi
done

echo ""
echo "✅ Provider registration complete"
echo ""
echo "Note: Some providers may still be registering in the background."
echo "You can check status with: az provider list --query \"[?registrationState=='Registering']\" --output table"
