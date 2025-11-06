# ✅ Rhino Setup Scripts Ready

**Date:** October 30, 2025  
**Status:** Scripts created - Ready for manual execution

---

## What Was Created

I've split the monolithic bootstrap script into **10 incremental, testable scripts** located in:

```
scripts/rhino-setup/
├── README.md                      # Complete guide
├── 01-install-chocolatey.ps1      # Package manager (2 min)
├── 02-install-iis.ps1             # Web server (5-10 min)
├── 03-install-dotnet.ps1          # .NET runtimes (10-15 min)
├── 04-setup-keyvault.ps1          # API key from Azure (1 min)
├── 05-download-compute.ps1        # Rhino.Compute binaries (2-3 min)
├── 06-configure-iis.ps1           # IIS site setup (1 min)
├── 07-configure-firewall.ps1      # Open port 8081 (30 sec)
├── 08-create-gh-directories.ps1   # GH folder structure (30 sec)
├── 09-install-rhino.md            # Rhino 8 install guide (10 min - manual)
└── 10-test-compute.ps1            # Comprehensive tests (1 min)
```

**Total time:** ~30-45 minutes + Rhino install

---

## Why This Approach is Better

✅ **Incremental:** Run one step at a time, verify, continue  
✅ **Debuggable:** If a step fails, fix it before moving forward  
✅ **Idempotent:** Scripts check if work is already done  
✅ **Clear Feedback:** Each script shows pass/fail with troubleshooting  
✅ **Manual Control:** You observe each step's execution  

---

## How to Use

### 1. Connect to Rhino VM

```bash
# VM is already running
# IP: 20.73.173.209
# Username: rhinoadmin
# Password: GZHPSDwer6c60qHr (or from Key Vault)

# RDP command:
mstsc /v:20.73.173.209
```

### 2. Copy Scripts to VM

**Option A: Via RDP shared drive**
1. When connecting via RDP, enable "Local Resources" → "Drives"
2. Your local drive appears in VM as `\\tsclient\C`
3. Copy `scripts/rhino-setup` to `C:\rhino-setup` on VM

**Option B: Download directly on VM**
- If scripts are in a Git repository, clone on VM
- Or download individual files via browser

### 3. Execute Scripts in Order

On VM, open **PowerShell as Administrator**:

```powershell
cd C:\rhino-setup

# Run each script in sequence
.\01-install-chocolatey.ps1     # Close and reopen PowerShell after this
.\02-install-iis.ps1
.\03-install-dotnet.ps1
.\04-setup-keyvault.ps1
.\05-download-compute.ps1
.\06-configure-iis.ps1
.\07-configure-firewall.ps1
.\08-create-gh-directories.ps1

# Manual step: Install Rhino 8 (see 09-install-rhino.md)
# Download from: https://www.rhino3d.com/download/
# Launch → Cloud Zoo → Sign in

# Final test
.\10-test-compute.ps1
```

Each script will:
- ✅ Show what it's doing
- ✅ Check if already completed (skip if done)
- ✅ Display clear success/failure messages
- ✅ Provide troubleshooting tips if failed

---

## What Happens at Each Step

| Step | Action | Output | Duration |
|------|--------|--------|----------|
| 1 | Install Chocolatey | Package manager ready | 2 min |
| 2 | Install IIS | Web server running | 5-10 min |
| 3 | Install .NET 8.0 | Runtimes available | 10-15 min |
| 4 | Fetch API key from Key Vault | `RHINO_COMPUTE_KEY` set | 1 min |
| 5 | Download Rhino.Compute | Files in `C:\inetpub\compute\` | 2-3 min |
| 6 | Configure IIS | Site "RhinoCompute" on :8081 | 1 min |
| 7 | Open firewall | Port 8081 accessible | 30 sec |
| 8 | Create GH directories | `C:\compute\sitefit\1.0.0\` | 30 sec |
| 9 | Install Rhino 8 (manual) | Rhino licensed & ready | 10 min |
| 10 | Run tests | All systems verified | 1 min |

---

## Expected Final State

After all scripts complete:

✅ **IIS** running with Rhino.Compute on port 8081  
✅ **API Key** set as system environment variable  
✅ **Firewall** allows inbound on 8081  
✅ **Rhino 8** installed and licensed (Cloud Zoo)  
✅ **Health endpoint** responds: `http://localhost:8081/version`  
✅ **Authenticated endpoints** work with API key  
✅ **GH directory** ready for definitions  

---

## Test from Your Local Machine

After Step 10 passes on VM:

```bash
# Health check
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

**Expected:** 200 OK with geometry data 🎉

---

## Next Steps After Setup

1. **Create Grasshopper definition** (`sitefit.ghx`)
2. **Place in:** `C:\compute\sitefit\1.0.0\sitefit.ghx`
3. **Update AppServer** configuration to use Compute
4. **Test end-to-end** job execution

---

## Quick Start Command

If you want to copy-paste all at once (after RDP to VM):

```powershell
# Open PowerShell as Administrator on VM
cd C:\rhino-setup

# Execute all automated steps (Rhino install is manual)
.\01-install-chocolatey.ps1; if ($LASTEXITCODE -eq 0) {
  Write-Host "Step 1 complete. Close this window and open new PowerShell as Admin"
  Write-Host "Then run: cd C:\rhino-setup; .\02-install-iis.ps1" -ForegroundColor Yellow
}
```

**Note:** After Step 1 (Chocolatey), you **must** close and reopen PowerShell.

---

## Support Files

- **Detailed README:** `scripts/rhino-setup/README.md`
- **VM Connection Info:** `STAGE4_RHINO_SETUP_INFO.md`
- **Stage 4 Guide:** `context/dev_roadmap_sitefit/stage4_rhino_installation.md`

---

## What to Do if Something Fails

Each script has built-in troubleshooting. If a step fails:

1. **Read the error message** - scripts provide specific guidance
2. **Check the troubleshooting section** in the script output
3. **Fix the issue** using suggested commands
4. **Re-run the script** - it will skip completed steps
5. **Continue to next script** once current one passes

Common issues and fixes are documented in each script.

---

**Status:** ✅ Ready to execute on VM

**Next Action:** RDP to 20.73.173.209 and run scripts! 🚀
