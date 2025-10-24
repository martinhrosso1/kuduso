# Stage 2 - Phase 2: Docker Images Setup

## 🐳 Docker Installation Required

Docker is not currently installed on your system. You need to install it to build and push images.

### Option A: Install Docker Desktop (Recommended for Dev)

**Ubuntu/Debian:**
```bash
# Remove old versions
sudo apt-get remove docker docker-engine docker.io containerd runc

# Install prerequisites
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add your user to docker group (to run without sudo)
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
# Or run: newgrp docker
```

### Option B: Use Azure Container Registry Build Tasks (No Local Docker Needed)

You can build images directly in Azure using ACR tasks:

```bash
# Build AppServer
az acr build \
  --registry kudusodevacr93d2ab \
  --image appserver-node:$(git rev-parse --short HEAD) \
  --file shared/appserver-node/Dockerfile \
  shared/appserver-node

# Build API
az acr build \
  --registry kudusodevacr93d2ab \
  --image api-fastapi:$(git rev-parse --short HEAD) \
  --file apps/sitefit/api-fastapi/Dockerfile \
  apps/sitefit/api-fastapi

# Build Worker
az acr build \
  --registry kudusodevacr93d2ab \
  --image worker-fastapi:$(git rev-parse --short HEAD) \
  --file apps/sitefit/worker-fastapi/Dockerfile \
  apps/sitefit/worker-fastapi
```

---

## 📦 What We Created

### Dockerfiles ✅
1. **shared/appserver-node/Dockerfile**
   - Multi-stage build
   - Node.js 18 Alpine
   - TypeScript compilation
   - Health check on port 8080

2. **apps/sitefit/api-fastapi/Dockerfile**
   - Multi-stage build
   - Python 3.11 slim
   - FastAPI + Uvicorn
   - Health check on port 8081
   - Non-root user

3. **apps/sitefit/worker-fastapi/Dockerfile**
   - Multi-stage build
   - Python 3.11 slim
   - Worker process + health check server
   - Health check on port 8082
   - Non-root user

### Worker Code ✅
Created minimal worker structure:
- `apps/sitefit/worker-fastapi/main.py` - Placeholder worker
- `apps/sitefit/worker-fastapi/requirements.txt` - Dependencies
- Ready for Stage 3 implementation

### .dockerignore Files ✅
Optimized builds by excluding:
- node_modules, __pycache__
- .git, logs, test files
- Development configs

### Build Script ✅
- `scripts/build-and-push-images.sh`
- Automates build and push for all 3 images
- Tags with git SHA + latest
- Saves tag for deployment

---

## 🚀 Next Steps

### If You Choose Option A (Local Docker):

1. **Install Docker** (see commands above)
2. **Log out and log back in** (for group permissions)
3. **Run build script**:
   ```bash
   ./scripts/build-and-push-images.sh
   ```

### If You Choose Option B (ACR Build):

Create a script to build all images in Azure:

```bash
#!/bin/bash
# Build images in ACR (no local Docker needed)
set -e

GIT_SHA=$(git rev-parse --short HEAD)
ACR_NAME=kudusodevacr93d2ab

echo "Building images in ACR with tag: $GIT_SHA"
echo ""

# AppServer
echo "📦 Building appserver-node..."
az acr build \
  --registry $ACR_NAME \
  --image appserver-node:$GIT_SHA \
  --image appserver-node:latest \
  --file shared/appserver-node/Dockerfile \
  shared/appserver-node

# API
echo "📦 Building api-fastapi..."
az acr build \
  --registry $ACR_NAME \
  --image api-fastapi:$GIT_SHA \
  --image api-fastapi:latest \
  --file apps/sitefit/api-fastapi/Dockerfile \
  apps/sitefit/api-fastapi

# Worker
echo "📦 Building worker-fastapi..."
az acr build \
  --registry $ACR_NAME \
  --image worker-fastapi:$GIT_SHA \
  --image worker-fastapi:latest \
  --file apps/sitefit/worker-fastapi/Dockerfile \
  apps/sitefit/worker-fastapi

echo ""
echo "✅ All images built in ACR!"
echo "Image tag: $GIT_SHA"
echo ""
echo "Save this for deployment:"
echo "export IMG_SHA=$GIT_SHA"
```

Save this as `scripts/build-images-in-acr.sh` and run it!

---

## 🎯 Summary

### Created Files ✅
```
shared/appserver-node/
├── Dockerfile              ✅
└── .dockerignore          ✅

apps/sitefit/api-fastapi/
├── Dockerfile              ✅
└── .dockerignore          ✅

apps/sitefit/worker-fastapi/
├── main.py                 ✅ (minimal placeholder)
├── requirements.txt        ✅
├── Dockerfile              ✅
└── .dockerignore          ✅

scripts/
└── build-and-push-images.sh  ✅
```

### Image Specs
| Image | Base | Port | Size (est) | Purpose |
|-------|------|------|------------|---------|
| appserver-node | node:18-alpine | 8080 | ~50MB | Contract validation & compute routing |
| api-fastapi | python:3.11-slim | 8081 | ~150MB | Job submission API |
| worker-fastapi | python:3.11-slim | 8082 | ~180MB | Message consumer & processor |

---

## ❓ Which Option Do You Prefer?

**Option A: Install Docker locally**
- Pros: Faster builds, works offline, full Docker features
- Cons: Requires installation, ~5 min setup time

**Option B: Use ACR Build**
- Pros: No local Docker needed, builds in cloud
- Cons: Requires internet, slower (uploads code each time)

**My recommendation:** If you plan to develop locally, install Docker (Option A). If this is one-time or you have slow local resources, use ACR Build (Option B).

**Let me know which option you'd like and I'll help you proceed!**
