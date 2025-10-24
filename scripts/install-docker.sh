#!/bin/bash
# Install Docker on Ubuntu/Linux Mint
set -e

echo "🐳 Installing Docker..."
echo ""

# Update package index
echo "📦 Updating package index..."
sudo apt-get update

# Install prerequisites
echo "📦 Installing prerequisites..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
echo "🔑 Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Determine Ubuntu version (Linux Mint is based on Ubuntu)
UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
echo "📋 Detected Ubuntu base: $UBUNTU_CODENAME"

# Set up Docker repository
echo "📦 Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $UBUNTU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again
echo "📦 Updating package index with Docker repo..."
sudo apt-get update

# Install Docker Engine
echo "🐳 Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
echo "👤 Adding $USER to docker group..."
sudo usermod -aG docker $USER

# Start and enable Docker
echo "🚀 Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Test Docker installation (with sudo for now)
echo ""
echo "✅ Docker installed successfully!"
echo ""
echo "📋 Docker version:"
sudo docker --version

echo ""
echo "⚠️  IMPORTANT: You need to log out and log back in for group changes to take effect."
echo "    Or run: newgrp docker"
echo ""
echo "After logging back in, test with: docker run hello-world"
