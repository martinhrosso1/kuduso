# Rhino.Compute Setup Scripts - Step-by-Step Guide

**For:** Kuduso Rhino VM (`kuduso-dev-rhino-vm`)  
**VM IP:** 20.73.173.209  
**Date:** October 30, 2025

---

## Overview

This directory contains **10 incremental scripts** to set up Rhino.Compute on the Azure Windows VM. Each script handles one specific task and can be run independently.

**Total estimated time:** 30-45 minutes (+ Rhino install ~10 min)

---

## Prerequisites

✅ RDP access to the VM  
✅ Admin credentials: `rhinoadmin` / (see STAGE4_RHINO_SETUP_INFO.md)  
✅ McNeel account with Rhino Cloud Zoo license  
✅ Internet connectivity on VM

---

## Quick Start

### 1. Connect to VM

```bash
# From your local machine
mstsc /v:20.73.173.209

# Or on Mac/Linux
open rdp://20.73.173.209
```

### 2. Run script directly in powershell of VM, one by one

<!-- ### 2. Copy Scripts to VM

**Option A: Download from GitHub (if you push there)**
```powershell
# On VM PowerShell
cd C:\
git clone https://github.com/your-org/kuduso.git
cd kuduso\scripts\rhino-setup
```

**Option B: Copy via RDP**
1. Open RDP connection
2. Enable "Local Resources" → "More" → "Drives" (share your local drive)
3. Copy `scripts/rhino-setup` folder from your local machine to `C:\rhino-setup` on VM

Disconnect and reconnect with folder sharing enabled:
```bash
xfreerdp /u:rhinoadmin /p:'ChangeMe123!_?' /v:20.73.173.209:3389 \
  /dynamic-resolution /cert:ignore \
  /drive:local,/home/martin/Desktop/kuduso/scripts/rhino-setup
```
Then on the Windows VM, open PowerShell and run (this will copy the scripts):
```powershell
# The shared folder will appear as a network drive (usually \\tsclient\local)
Copy-Item -Path "\\tsclient\local\*" -Destination "C:\scripts\rhino-setup\" -Recurse -Force
```

**Option C: Download individual scripts**
1. On VM, open browser
2. Navigate to your repository
3. Download each `.ps1` file to `C:\rhino-setup` -->

---

## Installation Steps

Open **PowerShell as Administrator** on the VM and run scripts in order:

### Step 1: Install Chocolatey (2 min)

```powershell
cd C:\rhino-setup
.\01-install-chocolatey.ps1
```

**What it does:** Installs Chocolatey package manager  
**On success:** Close PowerShell and open new window as Administrator

---

### Step 2: Install IIS (5-10 min)

```powershell
cd C:\rhino-setup
.\02-install-iis.ps1
```

**What it does:** Installs IIS web server + required features  
**On success:** IIS is running and accessible

---

### Step 3: Install .NET Runtimes (10-15 min)

```powershell
.\03-install-dotnet.ps1
```

**What it does:** Installs .NET 8.0 SDK, Desktop Runtime, ASP.NET Core Hosting Bundle  
**On success:** `dotnet --version` shows installed version

---

### Step 4: Setup API Key from Key Vault (1 min)

```powershell
.\04-setup-keyvault.ps1
```

**What it does:** Fetches `RHINO_COMPUTE_KEY` from Azure Key Vault using Managed Identity  
**On success:** Environment variable `RHINO_COMPUTE_KEY` is set

**If this fails:** Check troubleshooting section in script output

---

### Step 5: Download Rhino.Compute (2-3 min)

```powershell
.\05-download-compute.ps1
```

**What it does:** Downloads latest Rhino.Compute from GitHub  
**On success:** Files extracted to `C:\inetpub\compute\`

---

### Step 6: Configure IIS (1 min)

```powershell
.\06-configure-iis.ps1
```

**What it does:** Creates IIS site, app pool, and web.config  
**On success:** IIS site "RhinoCompute" is running on port 8081

---

### Step 7: Configure Firewall (30 sec)

```powershell
.\07-configure-firewall.ps1
```

**What it does:** Opens port 8081 in Windows Firewall  
**On success:** Firewall rule "Rhino.Compute HTTP" created

---

### Step 8: Create GH Directories (30 sec)

```powershell
.\08-create-gh-directories.ps1
```

**What it does:** Creates directory structure for Grasshopper definitions  
**On success:** `C:\compute\sitefit\1.0.0\` exists with README

---

### Step 9: Install Rhino 8 (MANUAL - 10 min)

**See:** `09-install-rhino.md` for detailed instructions

**Quick version:**
1. Download from: https://www.rhino3d.com/download/
2. Run installer
3. Launch Rhino → Choose Cloud Zoo → Sign in
4. Close Rhino

---

### Step 10: Test Everything (1 min)

```powershell
.\10-test-compute.ps1
```

**What it does:** Runs comprehensive tests  
**On success:** All tests pass, Compute is ready!

---

## Verification Checklist

After completing all steps, verify:

- [ ] Chocolatey installed: `choco --version`
- [ ] IIS running: `Get-Service W3SVC`
- [ ] .NET installed: `dotnet --version`
- [ ] API key set: `[Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')`
- [ ] Compute downloaded: `Test-Path C:\inetpub\compute\compute.geometry.exe`
- [ ] IIS site running: `Get-Website -Name RhinoCompute`
- [ ] Firewall open: `Get-NetFirewallRule -DisplayName "Rhino.Compute*"`
- [ ] GH directory exists: `Test-Path C:\compute\sitefit\1.0.0`
- [ ] Rhino 8 installed: `Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe"`
- [ ] Health check works: `curl http://localhost:8081/version`

---

## Testing from Local Machine

Once Step 10 passes, test from your local machine:

```bash
# Health check (no auth)
curl http://20.73.173.209:8081/version

# Get API key
API_KEY=$(az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name RHINO-COMPUTE-KEY \
  --query value -o tsv)

# Authenticated test
curl -X POST http://20.73.173.209:8081/rhino/geometry/point \
  -H "RhinoComputeKey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"x":10,"y":20,"z":30}'
```

**Expected:** 200 OK with point geometry data

---

## Troubleshooting

### Script fails with "not running as Administrator"

```powershell
# Right-click PowerShell → Run as Administrator
```

### Chocolatey install fails

- Check internet connectivity
- Disable antivirus temporarily
- Try manual install: https://chocolatey.org/install

### IIS install hangs

- Check Windows Update isn't running
- Restart VM and try again

### Key Vault access fails

**Verify Managed Identity:**
```bash
# On local machine
az vm identity show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm
```

**Grant Key Vault access:**
```bash
IDENTITY_ID="<principal-id-from-above>"
az keyvault set-policy \
  --name kuduso-dev-kv-93d2ab \
  --object-id $IDENTITY_ID \
  --secret-permissions get
```

### Compute /version returns 503

- Wait 30 seconds (cold start)
- Check Rhino is installed and licensed
- Review IIS logs: `C:\inetpub\compute\logs\stdout*.log`
- Restart IIS: `iisreset`

### Firewall blocks external access

Check NSG allows your IP:
```bash
# On local machine
curl ifconfig.me  # Get your IP
# Update NSG to allow your IP on port 8081
```

---

## Next Steps After Setup

1. **Create Grasshopper Definition**
   - Design .ghx file matching contract
   - Save to: `C:\compute\sitefit\1.0.0\sitefit.ghx`

2. **Update AppServer**
   ```bash
   # In infra/live/dev/shared/appserver/terragrunt.hcl
   rhino_compute_url = "http://20.73.173.209:8081"
   use_compute       = true
   ```

3. **Deploy AppServer**
   ```bash
   cd infra/live/dev/shared/appserver
   terragrunt apply
   ```

4. **Test End-to-End**
   - Submit job via API
   - Worker processes via Service Bus
   - AppServer calls Rhino.Compute
   - Real GH execution returns results

---

## Support

- **Rhino.Compute Docs:** https://developer.rhino3d.com/guides/compute/
- **McNeel Forum:** https://discourse.mcneel.com
- **Project Context:** `/kuduso/context/dev_roadmap_sitefit/stage4_rhino_installation.md`

---

## File Reference

| Script | Purpose | Duration | Can Skip? |
|--------|---------|----------|-----------|
| `01-install-chocolatey.ps1` | Package manager | 2 min | No |
| `02-install-iis.ps1` | Web server | 5-10 min | No |
| `03-install-dotnet.ps1` | .NET runtimes | 10-15 min | No |
| `04-setup-keyvault.ps1` | API key from Azure | 1 min | If manual |
| `05-download-compute.ps1` | Compute binaries | 2-3 min | No |
| `06-configure-iis.ps1` | IIS site setup | 1 min | No |
| `07-configure-firewall.ps1` | Open port 8081 | 30 sec | If manual |
| `08-create-gh-directories.ps1` | GH folder structure | 30 sec | Yes |
| `09-install-rhino.md` | Rhino 8 install guide | 10 min | No |
| `10-test-compute.ps1` | Comprehensive tests | 1 min | No |

---

**Setup Status:** Ready to execute! 🚀
