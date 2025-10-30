# Stage 4 — Rhino.Compute Setup (Infrastructure Already Exists)

## Objectives

* Install & license **Rhino 8** on Windows VM
* Configure **Rhino.Compute** server
* Connect **AppServer** to real Compute
* Test Grasshopper execution

**Success criteria:** AppServer executes real GH definitions via Rhino.Compute

---

**Note:** The `infra/modules/rhino-vm/` module was created in Stage 2. This guide focuses on:
1. Deploying the VM
2. Software installation (Rhino + Compute)
3. Configuration & testing

---

# 4.1 Deploy Rhino VM (Quick Step)


## Step 3: Get VM Public IP

```bash
VM_IP=$(terragrunt output -raw public_ip)
echo "Rhino VM IP: $VM_IP"
```

---

# 4.2 Install Rhino 8 (Manual - RDP Required)

## Step 1: RDP to VM

**Windows:**
```cmd
mstsc /v:%VM_IP%
```

**Mac:**
```bash
open rdp://$VM_IP
```

**Linux:**
```bash
rdesktop $VM_IP
# or
xfreerdp /u:azureuser /v:$VM_IP
```

**Credentials:**
- Username: `azureuser`
- Password: (from terragrunt.hcl)

---

## Step 2: Download & Install Rhino 8

**On the VM (via RDP):**

### Option A: Interactive Install

1. Open browser and go to: https://www.rhino3d.com/download/
2. Download **Rhino 8 for Windows**
3. Run installer
4. Choose **Cloud Zoo** licensing
5. Sign in with McNeel account
6. Complete installation (~10 minutes)

### Option B: Silent Install (PowerShell)

```powershell
# Download Rhino 8 installer
$installerUrl = "https://www.rhino3d.com/download/rhino-for-windows/8/latest/direct"
$installerPath = "$env:TEMP\rhino_8_setup.exe"

Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

# Silent install with Cloud Zoo
Start-Process $installerPath -ArgumentList @(
  '/quiet',
  '/norestart',
  'LICENSE_METHOD=CLOUD_ZOO'
) -Wait

# Verify installation
Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe"
```

### Step 3: Activate License

If using **Cloud Zoo** (recommended):
1. Launch Rhino 8
2. When prompted, choose **Cloud Zoo**
3. Sign in to your McNeel account
4. Select your license from the list

If using **LAN Zoo**:
```powershell
# Point to LAN Zoo server
reg add "HKLM\SOFTWARE\McNeel\Rhinoceros\8.0\License Manager" `
  /v "Server" /t REG_SZ /d "zoo.yourcompany.com" /f
```

### Step 4: Verify License

```powershell
# Check license status
& "C:\Program Files\Rhino 8\System\Rhino.exe" /runscript="_-Exit"
```

---

# 4.3 Install & Configure Rhino.Compute

## Step 1: Install Prerequisites

**On the VM:**

```powershell
# Install Chocolatey (package manager)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install .NET SDK and runtimes
choco install dotnet-8.0-sdk dotnet-8.0-runtime dotnet-8.0-desktopruntime -y
choco install dotnet-aspnethosting-bundle -y

# Restart PowerShell to update PATH
```

---

## Step 2: Download Rhino.Compute

```powershell
# Create directory
New-Item -Path "C:\rhino-compute" -ItemType Directory -Force

# Download latest release
$computeUrl = "https://github.com/mcneel/compute.rhino3d/releases/latest/download/rhino.compute.zip"
$computeZip = "C:\rhino-compute\rhino.compute.zip"

Invoke-WebRequest -Uri $computeUrl -OutFile $computeZip

# Extract
Expand-Archive -Path $computeZip -DestinationPath "C:\rhino-compute" -Force

# Verify
Test-Path "C:\rhino-compute\compute.geometry.exe"
```

---

## Step 3: Generate & Set API Key

```powershell
# Generate secure API key
$apiKey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
Write-Host "Generated API Key: $apiKey"
Write-Host "SAVE THIS KEY - You'll need it for Azure Key Vault"

# Set as system environment variable
[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $apiKey, 'Machine')

# Verify
[System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
```

**Important:** Copy this API key and store it in Azure Key Vault:

```bash
# On your local machine
az keyvault secret set \
  --vault-name kuduso-dev-kv-93d2ab \
  --name RHINO-COMPUTE-KEY \
  --value "YOUR_GENERATED_KEY"
```

---

## Step 4: Test Self-Hosted Compute (Quick Test)

**On VM:**

```powershell
cd C:\rhino-compute

# Start Compute server
.\compute.geometry.exe

# Server should start on http://localhost:8081
# Press Ctrl+C to stop when done testing
```

**From another PowerShell window on VM:**

```powershell
# Test health endpoint (no auth required)
curl http://localhost:8081/version

# Test with auth
$apiKey = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
curl -Method POST http://localhost:8081/rhino/geometry/point `
  -Headers @{"RhinoComputeKey"=$apiKey; "Content-Type"="application/json"} `
  -Body '{"x":0,"y":0,"z":0}'
```

If both tests pass, Compute is working! ✅

---

## Step 5: Configure as Windows Service (Production Setup)

**Install NSSM (Non-Sucking Service Manager):**

```powershell
choco install nssm -y

# Create Windows Service
nssm install RhinoCompute "C:\rhino-compute\compute.geometry.exe"
nssm set RhinoCompute AppDirectory "C:\rhino-compute"
nssm set RhinoCompute DisplayName "Rhino.Compute Server"
nssm set RhinoCompute Description "Rhino geometry computation service"
nssm set RhinoCompute Start SERVICE_AUTO_START

# Set environment variable for service
nssm set RhinoCompute AppEnvironmentExtra "RHINO_COMPUTE_KEY=$([System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine'))"

# Start service
nssm start RhinoCompute

# Verify service is running
nssm status RhinoCompute
```

---

## Step 6: Configure Windows Firewall

```powershell
# Allow inbound on port 8081
New-NetFirewallRule -DisplayName "Rhino.Compute" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8081 `
  -Action Allow `
  -Profile Any
```

---

## Step 7: Test from Your Local Machine

```bash
# Get VM IP
VM_IP=$(cd infra/live/dev/shared/rhino && terragrunt output -raw public_ip)

# Get API key from Key Vault
API_KEY=$(az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name RHINO-COMPUTE-KEY \
  --query value -o tsv)

# Test health
curl http://$VM_IP:8081/version

# Test auth
curl -X POST http://$VM_IP:8081/rhino/geometry/point \
  -H "RhinoComputeKey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"x":10,"y":20,"z":30}'
```

**Expected:** `200 OK` with point geometry data ✅

---

# 4.4 Create Grasshopper Definition Directory

**On VM:**

```powershell
# Create versioned directories for GH definitions
New-Item -Path "C:\compute\sitefit\1.0.0" -ItemType Directory -Force

# This is where you'll place sitefit.ghx
```

**File structure:**
```
C:\compute\
└── sitefit\
    └── 1.0.0\
        ├── sitefit.ghx        (main definition)
        ├── inputs.json        (sample inputs for testing)
        └── README.md          (definition docs)
```

**Note:** You'll create the actual Grasshopper definition in the next stage. For now, create a placeholder:

```powershell
@"
This directory will contain the Grasshopper definition for sitefit v1.0.0

Required files:
- sitefit.ghx: Main Grasshopper definition
- inputs.json: Sample test inputs

The definition should match the contract in:
/home/martin/Desktop/kuduso/contracts/sitefit/1.0.0/
"@ | Out-File "C:\compute\sitefit\1.0.0\README.md"
```

---

# 4.5 Wire AppServer to Rhino.Compute

Now that Compute is running, update AppServer to use it:

## Step 1: Update AppServer Terragrunt Config

**File:** `infra/live/dev/shared/appserver/terragrunt.hcl`

```hcl
dependency "rhino" {
  config_path = "../rhino"
  mock_outputs = {
    public_ip = "0.0.0.0"
  }
}

inputs = {
  # ...existing config...
  
  # Rhino.Compute Configuration
  rhino_compute_url = "http://${dependency.rhino.outputs.public_ip}:8081"
  use_compute       = false  # Keep as false until we have a real GH definition
}
```

## Step 2: Update AppServer Module (if needed)

The `shared-appserver` module should already have these environment variables. Verify in `infra/modules/shared-appserver/main.tf`:

```hcl
env {
  name  = "USE_COMPUTE"
  value = tostring(var.use_compute)
}

env {
  name  = "COMPUTE_URL"
  value = var.rhino_compute_url
}

env {
  name        = "COMPUTE_API_KEY"
  secret_name = var.rhino_api_key_secret_name
}
```

## Step 3: Redeploy AppServer (Optional - only if config changed)

```bash
cd infra/live/dev/shared/appserver
terragrunt apply
```

---

# 4.6 Quick Validation Checklist

Run through this checklist to verify everything is working:

- [ ] **VM deployed:** `az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm`
- [ ] **Can RDP:** Connect via Remote Desktop
- [ ] **Rhino 8 installed:** `Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe"`
- [ ] **License active:** Launch Rhino, check Tools → Options → Licenses
- [ ] **Compute running:** Service status `nssm status RhinoCompute` = `SERVICE_RUNNING`
- [ ] **API key set:** `[Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')`
- [ ] **Firewall open:** `Get-NetFirewallRule -DisplayName "Rhino.Compute"`
- [ ] **Health check works:** `curl http://$VM_IP:8081/version`
- [ ] **Auth works:** POST with `RhinoComputeKey` header returns 200
- [ ] **API key in Key Vault:** `az keyvault secret show --vault-name kuduso-dev-kv-93d2ab --name RHINO-COMPUTE-KEY`
- [ ] **GH directory exists:** `Test-Path "C:\compute\sitefit\1.0.0"`

---

# 4.7 Common Issues & Fixes

## Issue: Can't RDP to VM

**Check NSG allows your IP:**
```bash
curl ifconfig.me  # Get your current IP
# Update terragrunt.hcl with: allowed_source_ip = "YOUR_IP/32"
# Redeploy: terragrunt apply
```

---

## Issue: 401 Unauthorized from Compute

**Cause:** API key mismatch

**Fix:**
```powershell
# On VM - check environment variable
[Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')

# Compare with Key Vault
az keyvault secret show --vault-name kuduso-dev-kv-93d2ab --name RHINO-COMPUTE-KEY --query value

# If different, update Key Vault with VM's value
```

---

## Issue: Service won't start

**Check logs:**
```powershell
# View service logs
Get-EventLog -LogName Application -Source "RhinoCompute" -Newest 20

# Check if port 8081 is already in use
netstat -ano | findstr :8081

# Restart service
nssm restart RhinoCompute
```

---

## Issue: Rhino license not found

**Fix:**
```powershell
# Launch Rhino GUI and complete sign-in
& "C:\Program Files\Rhino 8\System\Rhino.exe"

# Verify license is active
# Tools → Options → Licenses → Cloud Zoo
```

---

# 4.8 Next Steps

✅ **Stage 4 Complete** when:
- Rhino VM is running
- Rhino 8 installed & licensed
- Rhino.Compute responding to health checks
- API key stored in Key Vault

🚀 **Stage 5:** Create real Grasshopper definition (`sitefit.ghx`) that matches your contracts

---

# 4.9 Cost Management

**VM Running Costs:** ~$120/month for D4as_v5

**Save money:**
```bash
# Stop VM when not in use
az vm deallocate --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm

# Start when needed
az vm start --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm

# Auto-shutdown is already configured (7 PM UTC)
```

---

# 4.10 References

- **Rhino.Compute GitHub:** https://github.com/mcneel/compute.rhino3d
- **Compute Guides:** https://developer.rhino3d.com/guides/compute/
- **McNeel Forum:** https://discourse.mcneel.com
- **Silent Install:** https://wiki.mcneel.com/rhino/installingrhino
- **NSSM Documentation:** https://nssm.cc/usage

---

**Status:** Ready to deploy! 🎯
