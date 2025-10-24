#!/bin/bash
# Build and push Docker images to ACR
set -e

echo "🐳 Building and Pushing Docker Images to ACR"
echo ""

# Save current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Get ACR details
cd "$PROJECT_ROOT/infra/live/dev/shared/core"
ACR_SERVER=$(terragrunt output -raw acr_server)
ACR_NAME=$(terragrunt output -raw acr_name)
cd "$PROJECT_ROOT"

echo "ACR Server: $ACR_SERVER"
echo "ACR Name: $ACR_NAME"
echo ""

# Get git SHA for tagging
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
echo "Image Tag: $GIT_SHA"
echo ""

# Login to ACR
echo "🔑 Logging into ACR..."
az acr login --name $ACR_NAME
echo "✓ Logged in"
echo ""

# Build and push AppServer
echo "📦 Building AppServer (Node.js)..."
docker build -t $ACR_SERVER/appserver-node:$GIT_SHA \
  -t $ACR_SERVER/appserver-node:latest \
  -f "$PROJECT_ROOT/shared/appserver-node/Dockerfile" \
  "$PROJECT_ROOT/shared/appserver-node"

echo "⬆️  Pushing AppServer..."
docker push $ACR_SERVER/appserver-node:$GIT_SHA
docker push $ACR_SERVER/appserver-node:latest
echo "✓ AppServer pushed"
echo ""

# Build and push API
echo "📦 Building API (FastAPI)..."
docker build -t $ACR_SERVER/api-fastapi:$GIT_SHA \
  -t $ACR_SERVER/api-fastapi:latest \
  -f "$PROJECT_ROOT/apps/sitefit/api-fastapi/Dockerfile" \
  "$PROJECT_ROOT/apps/sitefit/api-fastapi"

echo "⬆️  Pushing API..."
docker push $ACR_SERVER/api-fastapi:$GIT_SHA
docker push $ACR_SERVER/api-fastapi:latest
echo "✓ API pushed"
echo ""

# Build and push Worker
echo "📦 Building Worker (FastAPI)..."
docker build -t $ACR_SERVER/worker-fastapi:$GIT_SHA \
  -t $ACR_SERVER/worker-fastapi:latest \
  -f "$PROJECT_ROOT/apps/sitefit/worker-fastapi/Dockerfile" \
  "$PROJECT_ROOT/apps/sitefit/worker-fastapi"

echo "⬆️  Pushing Worker..."
docker push $ACR_SERVER/worker-fastapi:$GIT_SHA
docker push $ACR_SERVER/worker-fastapi:latest
echo "✓ Worker pushed"
echo ""

echo "✅ All images built and pushed successfully!"
echo ""
echo "Images:"
echo "  - $ACR_SERVER/appserver-node:$GIT_SHA"
echo "  - $ACR_SERVER/api-fastapi:$GIT_SHA"
echo "  - $ACR_SERVER/worker-fastapi:$GIT_SHA"
echo ""
echo "💾 Save this tag for deployment:"
echo "  export IMG_SHA=$GIT_SHA"
