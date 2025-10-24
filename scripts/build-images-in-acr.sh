#!/bin/bash
# Build images in ACR (no local Docker needed)
set -e

echo "🐳 Building Docker Images in Azure Container Registry"
echo ""

# Get git SHA for tagging
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
ACR_NAME=kudusodevacr93d2ab

echo "ACR: $ACR_NAME"
echo "Image Tag: $GIT_SHA"
echo ""
echo "Note: This will build images in Azure (no local Docker needed)"
echo "Each build uploads source code and may take 2-5 minutes per image"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Build AppServer
echo ""
echo "📦 1/3 Building appserver-node..."
echo "─────────────────────────────────────"
az acr build \
  --registry $ACR_NAME \
  --image appserver-node:$GIT_SHA \
  --image appserver-node:latest \
  --file shared/appserver-node/Dockerfile \
  --platform linux \
  shared/appserver-node

echo "✓ AppServer built"

# Build API
echo ""
echo "📦 2/3 Building api-fastapi..."
echo "─────────────────────────────────────"
az acr build \
  --registry $ACR_NAME \
  --image api-fastapi:$GIT_SHA \
  --image api-fastapi:latest \
  --file apps/sitefit/api-fastapi/Dockerfile \
  --platform linux \
  apps/sitefit/api-fastapi

echo "✓ API built"

# Build Worker
echo ""
echo "📦 3/3 Building worker-fastapi..."
echo "─────────────────────────────────────"
az acr build \
  --registry $ACR_NAME \
  --image worker-fastapi:$GIT_SHA \
  --image worker-fastapi:latest \
  --file apps/sitefit/worker-fastapi/Dockerfile \
  --platform linux \
  apps/sitefit/worker-fastapi

echo "✓ Worker built"

echo ""
echo "✅ All images built successfully in ACR!"
echo ""
echo "Images created:"
echo "  - $ACR_NAME.azurecr.io/appserver-node:$GIT_SHA"
echo "  - $ACR_NAME.azurecr.io/api-fastapi:$GIT_SHA"
echo "  - $ACR_NAME.azurecr.io/worker-fastapi:$GIT_SHA"
echo ""
echo "💾 Save this tag for deployment:"
echo "  export IMG_SHA=$GIT_SHA"
echo ""

# Verify images
echo "📋 Verifying images in ACR..."
az acr repository list --name $ACR_NAME --output table

echo ""
echo "🎉 Build complete! Ready for Phase 3: Infrastructure Modules"
