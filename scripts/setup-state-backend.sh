#!/bin/bash
# Setup Azure Storage for Terraform/OpenTofu state backend
set -e

echo "🔧 Setting up Terraform/OpenTofu State Backend..."
echo ""

# Configuration
LOCATION="westeurope"
RESOURCE_GROUP="kuduso-tfstate-rg"
STORAGE_ACCOUNT="kudusotfstate"
CONTAINER_NAME="tfstate"

echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Container: $CONTAINER_NAME"
echo "  Location: $LOCATION"
echo ""

# Verify Azure login
if ! az account show &>/dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo "✓ Logged in to Azure"
echo "  Subscription: $SUBSCRIPTION_NAME"
echo "  ID: $SUBSCRIPTION_ID"
echo ""

# Explicitly set the subscription (in case it's not default)
echo "Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "✓ Subscription set"
echo ""

# Check if Microsoft.Storage provider is registered
echo "Checking Microsoft.Storage provider..."
STORAGE_PROVIDER_STATE=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")

if [ "$STORAGE_PROVIDER_STATE" != "Registered" ]; then
    echo "⚠ Microsoft.Storage provider not registered. Registering..."
    az provider register --namespace Microsoft.Storage
    echo "✓ Provider registration initiated (may take a few minutes)"
    echo "  Waiting for registration to complete..."
    
    # Wait for registration
    for i in {1..30}; do
        STORAGE_PROVIDER_STATE=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv)
        if [ "$STORAGE_PROVIDER_STATE" = "Registered" ]; then
            echo "✓ Provider registered"
            break
        fi
        echo "  Still registering... ($i/30)"
        sleep 10
    done
    
    if [ "$STORAGE_PROVIDER_STATE" != "Registered" ]; then
        echo "❌ Provider registration timed out. Please wait and try again."
        exit 1
    fi
else
    echo "✓ Microsoft.Storage provider already registered"
fi
echo ""

# Create resource group if it doesn't exist
echo "📦 Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags purpose=terraform-state environment=shared \
  --output none

echo "✓ Resource group created/verified"

# Create storage account if it doesn't exist
echo "💾 Creating storage account..."
if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo "✓ Storage account already exists"
else
    echo "  Creating storage account (this may take 1-2 minutes)..."
    if az storage account create \
      --name "$STORAGE_ACCOUNT" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --min-tls-version TLS1_2 \
      --allow-blob-public-access false \
      --tags purpose=terraform-state \
      --subscription "$SUBSCRIPTION_ID" \
      --output none 2>&1; then
        echo "✓ Storage account created"
    else
        echo "❌ Failed to create storage account"
        echo "  Please check:"
        echo "  1. The subscription is active and has quota"
        echo "  2. The storage account name is globally unique"
        echo "  3. You have Contributor permissions"
        exit 1
    fi
fi

# Get storage account key
echo "🔑 Retrieving storage account key..."
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --subscription "$SUBSCRIPTION_ID" \
  --query '[0].value' -o tsv)

if [ -z "$ACCOUNT_KEY" ]; then
    echo "❌ Failed to retrieve storage account key"
    exit 1
fi
echo "✓ Key retrieved"

# Create container if it doesn't exist
echo "📁 Creating storage container..."
if az storage container show \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" &>/dev/null; then
    echo "✓ Container already exists"
else
    az storage container create \
      --name "$CONTAINER_NAME" \
      --account-name "$STORAGE_ACCOUNT" \
      --account-key "$ACCOUNT_KEY" \
      --output none
    
    echo "✓ Container created"
fi

echo ""
echo "✅ State backend setup complete!"
echo ""
echo "Export this environment variable before running Terragrunt:"
echo ""
echo "  export TF_STATE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT"
echo ""
echo "Or add it to your shell profile (.bashrc, .zshrc, etc.)"
