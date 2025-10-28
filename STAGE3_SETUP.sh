#!/bin/bash
# Stage 3 Setup Script - Run after creating Supabase project

set -e

echo "🚀 Stage 3 Setup"
echo ""

# Get Key Vault name
KV_NAME=$(az keyvault list --resource-group kuduso-dev-rg --query "[0].name" -o tsv)
echo "📦 Using Key Vault: $KV_NAME"
echo ""

# 1. Store Supabase DATABASE_URL
echo "📝 Step 1: Store Supabase DATABASE_URL"
echo "Enter your Supabase connection string (postgresql://...):"
read -r DATABASE_URL

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name DATABASE-URL \
  --value "$DATABASE_URL"

echo "✅ DATABASE-URL stored in Key Vault"
echo ""

# 1.5 Run database migrations
echo "📝 Step 1.5: Run database migrations with Alembic"
echo "Installing Alembic dependencies..."
pip install -q alembic psycopg2-binary sqlalchemy

echo "Running migrations..."
cd apps/sitefit/migrations
export DATABASE_URL="$DATABASE_URL"
alembic upgrade head

if [ $? -eq 0 ]; then
  echo "✅ Database schema created successfully"
else
  echo "❌ Migration failed - check errors above"
  exit 1
fi

cd ../../..
echo ""

# 2. Verify Service Bus connection string exists
echo "📝 Step 2: Verify Service Bus connection"
SB_CONN=$(az keyvault secret show --vault-name "$KV_NAME" --name SERVICEBUS-CONN --query value -o tsv 2>/dev/null || echo "")

if [ -z "$SB_CONN" ]; then
  echo "⚠️  SERVICEBUS-CONN not found in Key Vault"
  echo "Getting Service Bus connection string..."
  
  SB_CONN=$(az servicebus namespace authorization-rule keys list \
    --resource-group kuduso-dev-rg \
    --namespace-name kuduso-dev-servicebus \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString -o tsv)
  
  az keyvault secret set \
    --vault-name "$KV_NAME" \
    --name SERVICEBUS-CONN \
    --value "$SB_CONN"
  
  echo "✅ SERVICEBUS-CONN stored in Key Vault"
else
  echo "✅ SERVICEBUS-CONN already exists in Key Vault"
fi
echo ""

# 3. Get/Create Blob SAS signing key
echo "📝 Step 3: Storage Account Key for Blob SAS"
STORAGE_ACCOUNT=$(az storage account list --resource-group kuduso-dev-rg --query "[0].name" -o tsv)
echo "Using Storage Account: $STORAGE_ACCOUNT"

STORAGE_KEY=$(az storage account keys list \
  --resource-group kuduso-dev-rg \
  --account-name "$STORAGE_ACCOUNT" \
  --query "[0].value" -o tsv)

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name BLOB-SAS-SIGNING \
  --value "$STORAGE_KEY"

echo "✅ BLOB-SAS-SIGNING stored in Key Vault"
echo ""

# 4. Summary
echo "📊 Summary of Secrets in Key Vault:"
az keyvault secret list --vault-name "$KV_NAME" --query "[].name" -o table

echo ""
echo "✅ Stage 3 setup complete!"
echo ""
echo "✨ What was done:"
echo "  ✅ DATABASE-URL stored in Key Vault"
echo "  ✅ Database schema created with Alembic"
echo "  ✅ SERVICEBUS-CONN stored in Key Vault"
echo "  ✅ BLOB-SAS-SIGNING stored in Key Vault"
echo ""
echo "📊 Verify in Supabase:"
echo "  Go to Table Editor → should see: job, result, artifact tables"
echo ""
echo "🚀 Next steps:"
echo "  1. Update API/Worker code (see STAGE3_GUIDE.md)"
echo "  2. Build and push new images"
echo "  3. Redeploy Container Apps"
echo "  4. Test end-to-end flow"
