# Stage 4 - Rhino VM Setup Information

**Date:** October 30, 2025  
**Status:** ✅ VM Running - Ready for Rhino Installation

---

## 🖥️ VM Connection Details

| Property | Value |
|----------|-------|
| **VM Name** | kuduso-dev-rhino-vm |
| **Public IP** | 20.73.173.209 |
| **Private IP** | 10.0.1.4 |
| **Username** | rhinoadmin |
| **Password** | GZHPSDwer6c60qHr |
| **Size** | Standard_B2s (2 vCPU, 4 GB RAM) |
| **OS** | Windows Server 2022 Datacenter |

---

## 🔐 Stored Secrets (Key Vault)

| Secret Name | Purpose |
|-------------|---------|
| `RHINO-VM-ADMIN-PASSWORD` | VM admin password |
| `RHINO-COMPUTE-KEY` | API key for Rhino.Compute authentication |

**Retrieve secrets:**
```bash
# VM Password
az keyvault secret show --vault-name kuduso-dev-kv-93d2ab --name RHINO-VM-ADMIN-PASSWORD --query value -o tsv

# Compute API Key
az keyvault secret show --vault-name kuduso-dev-kv-93d2ab --name RHINO-COMPUTE-KEY --query value -o tsv
```

---

## 🌐 Network Configuration

**NSG Rules (kuduso-dev-rhino-nsg):**
- ✅ RDP (3389) from 92.180.224.113/32
- ✅ HTTP (80) from 92.180.224.113/32  
- ✅ Rhino.Compute (8081) from 92.180.224.113/32

**Compute URL:** `http://20.73.173.209:8081/`

---

## 📋 Next Steps - RDP to VM

### Connect via RDP

**Windows:**
```cmd
mstsc /v:20.73.173.209
```

**Mac:**
1. Install Microsoft Remote Desktop from App Store
2. Add PC with IP: 20.73.173.209
3. Use credentials above

**Linux:**
```bash
rdesktop 20.73.173.209
# or
xfreerdp /u:rhinoadmin /p:GZHPSDwer6c60qHr /v:20.73.173.209
```

---

## 🔧 Installation Checklist (On VM)

Follow these steps **after connecting via RDP**:

### 1. Install Prerequisites
```powershell
# Open PowerShell as Administrator

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Close and reopen PowerShell as Administrator

# Install .NET runtimes
choco install dotnet-8.0-sdk dotnet-8.0-runtime dotnet-8.0-desktopruntime -y
choco install dotnet-aspnethosting-bundle -y
```

### 2. Download Rhino 8
```powershell
# Option A: Download via browser
# Go to: https://www.rhino3d.com/download/

# Option B: PowerShell download
$installerUrl = "https://www.rhino3d.com/download/rhino-for-windows/8/latest/direct"
$installerPath = "$env:TEMP\rhino_8_setup.exe"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
```

### 3. Install Rhino 8
```powershell
# Silent install with Cloud Zoo
Start-Process "$env:TEMP\rhino_8_setup.exe" -ArgumentList @(
  '/quiet',
  '/norestart',
  'LICENSE_METHOD=CLOUD_ZOO'
) -Wait

# Verify installation
Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe"
```

### 4. Activate License
1. Launch Rhino 8 from Start Menu
2. Choose **Cloud Zoo** when prompted
3. Sign in with your McNeel account
4. Select license from list
5. Verify in Tools → Options → Licenses

### 5. Download Rhino.Compute
```powershell
# Create directory
New-Item -Path "C:\rhino-compute" -ItemType Directory -Force

# Download
$computeUrl = "https://github.com/mcneel/compute.rhino3d/releases/latest/download/rhino.compute.zip"
Invoke-WebRequest -Uri $computeUrl -OutFile "C:\rhino-compute\rhino.compute.zip"

# Extract
Expand-Archive -Path "C:\rhino-compute\rhino.compute.zip" -DestinationPath "C:\rhino-compute" -Force

# Verify
Test-Path "C:\rhino-compute\compute.geometry.exe"
```

### 6. Set API Key
```powershell
# The key is stored in Azure Key Vault
# Retrieve it from your local machine:
# az keyvault secret show --vault-name kuduso-dev-kv-93d2ab --name RHINO-COMPUTE-KEY --query value -o tsv

# On VM, set as environment variable:
$apiKey = "1XCDSdVDFL00zuahxpacrm1vh7dPDPa8l33ks7xL/Xo="  # Replace with actual key
[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $apiKey, 'Machine')

# Verify
[System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
```

### 7. Test Compute (Self-Hosted)
```powershell
cd C:\rhino-compute
.\compute.geometry.exe

# Server starts on http://localhost:8081
# Keep this window open for testing
```

**In another PowerShell window:**
```powershell
# Test health endpoint
curl http://localhost:8081/version

# Test with auth
$apiKey = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
curl -Method POST http://localhost:8081/rhino/geometry/point `
  -Headers @{"RhinoComputeKey"=$apiKey; "Content-Type"="application/json"} `
  -Body '{"x":10,"y":20,"z":30}'
```

### 8. Install as Windows Service
```powershell
# Install NSSM (Service Manager)
choco install nssm -y

# Create service
nssm install RhinoCompute "C:\rhino-compute\compute.geometry.exe"
nssm set RhinoCompute AppDirectory "C:\rhino-compute"
nssm set RhinoCompute DisplayName "Rhino.Compute Server"
nssm set RhinoCompute Start SERVICE_AUTO_START

# Set environment variable for service
$apiKey = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
nssm set RhinoCompute AppEnvironmentExtra "RHINO_COMPUTE_KEY=$apiKey"

# Start service
nssm start RhinoCompute

# Verify
nssm status RhinoCompute
```

### 9. Configure Firewall
```powershell
# Allow inbound on port 8081
New-NetFirewallRule -DisplayName "Rhino.Compute" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8081 `
  -Action Allow `
  -Profile Any
```

### 10. Create GH Definition Directory
```powershell
# Create versioned directory structure
New-Item -Path "C:\compute\sitefit\1.0.0" -ItemType Directory -Force

# Verify
Test-Path "C:\compute\sitefit\1.0.0"
```

---

## 🧪 Testing from Local Machine

After completing setup on VM, test from your local machine:

```bash
# Health check
curl http://20.73.173.209:8081/version

# Auth test
API_KEY=$(az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name RHINO-COMPUTE-KEY \
  --query value -o tsv)

curl -X POST http://20.73.173.209:8081/rhino/geometry/point \
  -H "RhinoComputeKey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"x":10,"y":20,"z":30}'
```

**Expected:** `200 OK` with point geometry data ✅

---

## 🔄 Update AppServer Configuration

Once Compute is working, update AppServer:

**File:** `infra/live/dev/shared/appserver/terragrunt.hcl`

```hcl
inputs = {
  # ...existing config...
  
  rhino_compute_url = "http://20.73.173.209:8081"
  use_compute       = false  # Keep false until we have real GH definition
  
  # Key Vault secret name for API key
  rhino_api_key_secret_name = "RHINO-COMPUTE-KEY"
}
```

**Redeploy AppServer:**
```bash
cd infra/live/dev/shared/appserver
terragrunt apply
```

---

## 💾 VM Management

### Stop VM (save costs)
```bash
az vm deallocate --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm
```

### Start VM
```bash
az vm start --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm
```

### Auto-shutdown
VM is configured to auto-shutdown at **7 PM UTC** daily.

---

## 📚 Reference Documents

- Installation guide: `/home/martin/Desktop/kuduso/context/dev_roadmap_sitefit/stage4_rhino_installation.md`
- Rhino.Compute docs: https://developer.rhino3d.com/guides/compute/
- McNeel Forum: https://discourse.mcneel.com

---

## ✅ Completion Checklist

- [ ] RDP connection successful
- [ ] Chocolatey installed
- [ ] .NET runtimes installed
- [ ] Rhino 8 installed
- [ ] Rhino license activated (Cloud Zoo)
- [ ] Rhino.Compute downloaded
- [ ] RHINO_COMPUTE_KEY set as environment variable
- [ ] Compute service installed and running
- [ ] Firewall rule configured
- [ ] GH definition directory created
- [ ] Health check works from local machine
- [ ] Auth test passes from local machine
- [ ] AppServer updated with Compute URL

---

**Status:** Ready to proceed with manual installation on VM! 🚀
