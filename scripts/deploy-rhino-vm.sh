#!/bin/bash
# Quick deploy script for Rhino VM
set -e

echo "🖥️  Deploying Rhino VM..."
echo ""

# Get your public IP
echo "📍 Getting your public IP..."
export MY_PUBLIC_IP="$(curl -s ifconfig.me)/32"
echo "   Your IP: $MY_PUBLIC_IP"
echo ""

# Check for password
if [ -z "$RHINO_VM_PASSWORD" ]; then
    echo "⚠️  RHINO_VM_PASSWORD not set!"
    echo ""
    echo "Please set a strong password:"
    echo "  export RHINO_VM_PASSWORD='YourStrongPassword123!'"
    echo ""
    echo "Requirements:"
    echo "  - At least 12 characters"
    echo "  - Mix of uppercase, lowercase, numbers, symbols"
    exit 1
fi

echo "✓ Password configured"
echo ""

# Navigate to rhino module
cd "$(dirname "$0")/../infra/live/dev/shared/rhino"

# Deploy
echo "🚀 Deploying VM..."
terragrunt apply

echo ""
echo "✅ Rhino VM deployed!"
echo ""

# Display connection info
echo "📋 Connection Information:"
echo "=========================="
PUBLIC_IP=$(terragrunt output -raw public_ip_address)
echo "Public IP: $PUBLIC_IP"
echo "Username:  rhinoadmin"
echo "Password:  (set via RHINO_VM_PASSWORD)"
echo ""
echo "RDP Command:"
echo "  xfreerdp /v:$PUBLIC_IP /u:rhinoadmin"
echo ""
echo "Rhino.Compute URL:"
terragrunt output rhino_compute_url
echo ""
echo "📝 Next Steps:"
echo "1. Connect via RDP"
echo "2. Run setup-rhino.ps1 script"
echo "3. Install Rhino.Compute"
echo "4. Save API key to Key Vault"
echo ""
