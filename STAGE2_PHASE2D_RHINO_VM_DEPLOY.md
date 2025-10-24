# Stage 2 - Phase 2D: Deploy Rhino VM

## 🎯 Goal

Deploy a Windows VM with Rhino.Compute for development environment.

## 📋 What We Created

### Terraform Module
```
infra/modules/rhino-vm/
├── variables.tf      ✅ Input variables
├── main.tf           ✅ VM + Network resources
├── outputs.tf        ✅ Outputs (IP, URL, etc.)
├── setup-rhino.ps1   ✅ PowerShell setup script
└── README.md         ✅ Documentation
```

### Configuration
```
infra/live/dev/shared/rhino/
└── terragrunt.hcl    ✅ Dev environment config
```

## 💰 Cost Estimate

- **VM (Standard_B2s)**: 2 vCPUs, 4GB RAM
  - Running 24/7: ~$30/month
  - With auto-shutdown (7 PM): ~$20/month
- **Public IP**: ~$3/month
- **Disk (Standard LRS)**: ~$5/month

**Total**: ~$28/month with auto-shutdown

## 🚀 Deployment Steps

### Step 1: Set Environment Variables

```bash
# Get your public IP address (for NSG lockdown)
export MY_PUBLIC_IP="$(curl -s ifconfig.me)/32"
echo "Your IP: $MY_PUBLIC_IP"

# Set a strong admin password
export RHINO_VM_PASSWORD="YourStrongPassword123!"
```

**⚠️ Important:**
- Password must meet Windows complexity requirements:
  - At least 12 characters
  - Mix of uppercase, lowercase, numbers, symbols
- Your IP will be the ONLY IP allowed to connect

### Step 2: Deploy the VM

```bash
cd infra/live/dev/shared/rhino

# Initialize
terragrunt init

# Review what will be created
terragrunt plan

# Deploy (takes ~5 minutes)
terragrunt apply
```

### Step 3: Get Connection Info

```bash
# Get public IP
PUBLIC_IP=$(terragrunt output -raw public_ip_address)
echo "VM Public IP: $PUBLIC_IP"

# Get Rhino.Compute URL
terragrunt output rhino_compute_url

# Get RDP connection command
terragrunt output rdp_connection
```

### Step 4: Connect via RDP

**On Linux:**
```bash
# Install RDP client if needed
sudo apt-get install remmina  # or xfreerdp

# Connect
xfreerdp /v:$PUBLIC_IP /u:rhinoadmin
# Enter password when prompted
```

**On Windows:**
```bash
mstsc /v:<public_ip>
```

### Step 5: Setup Rhino.Compute on the VM

Once connected to the VM:

#### 5.1 Download Setup Script

In PowerShell on the VM:
```powershell
# Create working directory
New-Item -Path C:\RhinoSetup -ItemType Directory -Force
cd C:\RhinoSetup

# Download setup script from your repo (or copy manually)
# For now, create it manually with the content from:
# infra/modules/rhino-vm/setup-rhino.ps1
```

#### 5.2 Run Setup Script

```powershell
cd C:\RhinoSetup
.\setup-rhino.ps1
```

This will:
- Create installation directory
- Configure Windows Firewall
- Generate API key
- Save configuration
- Display next steps

#### 5.3 Install Rhino.Compute

**Manual Step Required**:
1. Download Rhino.Compute from McNeel (requires Rhino license)
2. Copy installer to the VM
3. Extract to `C:\RhinoCompute`
4. Run `compute.geometry.exe`

**Test it works**:
```powershell
# On VM
Invoke-WebRequest -Uri "http://localhost:8081/version"

# From your machine
curl http://$PUBLIC_IP:8081/version
```

#### 5.4 Save API Key to Key Vault

```bash
# Back on your local machine
# Get the API key from C:\rhino-api-key.txt in the VM

# Get Key Vault name
cd infra/live/dev/shared/core
KV_NAME=$(terragrunt output -raw key_vault_name)

# Update the secret (replace <KEY> with actual key from VM)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name COMPUTE-API-KEY \
  --value "<KEY-FROM-VM>"
```

---

## ✅ Verification

### Check VM is Running

```bash
az vm show \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-rhino-vm \
  --show-details \
  --query "{name:name, powerState:powerState, publicIp:publicIps}"
```

### Test Rhino.Compute

```bash
# Get VM IP
cd infra/live/dev/shared/rhino
PUBLIC_IP=$(terragrunt output -raw public_ip_address)

# Test version endpoint
curl http://$PUBLIC_IP:8081/version

# Should return Rhino.Compute version info
```

### Check Auto-Shutdown

```bash
# View shutdown schedule
az vm list \
  --resource-group kuduso-dev-rg \
  --show-details \
  --query "[?name=='kuduso-dev-rhino-vm'].{name:name, autoShutdown:tags.autoShutdown}"
```

---

## 🔧 Management

### Start VM (if auto-shut down)

```bash
az vm start \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-rhino-vm
```

### Stop VM (to save costs)

```bash
# Stop and deallocate (no compute charges)
az vm deallocate \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-rhino-vm
```

### Change Allowed IP

```bash
# Update environment variable
export MY_PUBLIC_IP="$(curl -s ifconfig.me)/32"

# Reapply
cd infra/live/dev/shared/rhino
terragrunt apply
```

### Connect to VM

```bash
# Get connection info
cd infra/live/dev/shared/rhino
PUBLIC_IP=$(terragrunt output -raw public_ip_address)

# RDP
xfreerdp /v:$PUBLIC_IP /u:rhinoadmin
```

---

## 🐛 Troubleshooting

### Can't Deploy - "SkuNotAvailable"

Standard_B2s might not be available in your region. Try:
- Change region in `infra/live/dev/shared/core/terragrunt.hcl`
- Or use a different VM size:

```hcl
# In infra/live/dev/shared/rhino/terragrunt.hcl
inputs = {
  vm_size = "Standard_D2s_v3"  # 2 vCPUs, 8GB RAM, ~$70/month
}
```

### Can't Connect via RDP

1. Check VM is running
2. Verify your IP hasn't changed: `curl ifconfig.me`
3. Update NSG if needed: `terragrunt apply`
4. Check NSG rules in Azure Portal

### Rhino.Compute Not Working

1. Check service is running on VM
2. Test locally on VM first: `http://localhost:8081/version`
3. Check Windows Firewall
4. Verify NSG allows your IP on port 8081

### High Costs

Enable auto-shutdown (enabled by default) or:
```bash
# Stop VM when not in use
az vm deallocate --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm
```

---

## 📝 Next Steps

After VM is deployed and Rhino.Compute is running:

1. **✅ Verify API Key is in Key Vault**
2. **Next: Create AppServer Module** 
   - Will use Rhino.Compute URL
   - Will authenticate with API key from Key Vault
   - Can switch between mock and real compute

3. **Then: Create App Stack Module**
   - API + Worker apps
   - Service Bus queue
   - All wired together

---

## 🧹 Cleanup

To remove the VM and all resources:

```bash
cd infra/live/dev/shared/rhino
terragrunt destroy
```

**Note**: This is permanent. VM and disk will be deleted.

---

## 🎯 Summary

### Resources Created
- ✅ Virtual Network (10.0.0.0/16)
- ✅ Subnet (10.0.1.0/24)
- ✅ Public IP (Static)
- ✅ Network Security Group (locked to your IP)
- ✅ Network Interface
- ✅ Windows Server 2022 VM (Standard_B2s)
- ✅ Auto-shutdown schedule (7 PM)

### What You Get
- Windows VM accessible only from your IP
- Ready for Rhino.Compute installation
- Auto-shutdown to save costs
- API key for secure access
- PowerShell setup script included

**Ready to deploy? Run the commands above!**
