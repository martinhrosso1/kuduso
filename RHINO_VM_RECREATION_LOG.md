# Rhino VM Recreation Log

**Date:** November 25, 2024
**Status:** ✅ Successfully Completed

## Summary

The corrupted Rhino VM was successfully destroyed and recreated from the compute gallery image (`rhino-compute-image-v1` version `1.0.0`).

---

## What Was Done

### 1. Infrastructure State Verification
- Verified current Terragrunt/Terraform state
- Confirmed all dependencies (compute gallery image) were available

### 2. VM Destruction
- Destroyed all VM resources:
  - Windows Virtual Machine (`kuduso-dev-rhino-vm`)
  - Network Interface
  - Public IP
  - Virtual Network & Subnet
  - Network Security Group
  - Auto-shutdown schedule
  - Key Vault role assignments

**Duration:** ~1 minute

### 3. VM Recreation
- Recreated all resources from scratch using the compute gallery image
- Image source: `kuduso_images/rhino-compute/1.0.0`
- The custom image includes:
  - Windows Server 2022 Datacenter
  - Rhino 8 (licensed)
  - Rhino.Compute built and configured
  - IIS with proper app pool settings
  - All dependencies (.NET, ASP.NET Core Module, etc.)

**Duration:** ~4 minutes

---

## New VM Details

| Property | Value |
|----------|-------|
| **VM Name** | `kuduso-dev-rhino-vm` |
| **Public IP** | `51.137.35.150` |
| **Private IP** | `10.0.1.4` |
| **Rhino.Compute URL** | `http://51.137.35.150:8081/` |
| **RDP Connection** | `mstsc /v:51.137.35.150` |
| **Admin Username** | `rhinoadmin` |
| **VM Size** | `Standard_B2s` (2 vCPUs, 4GB RAM) |
| **Auto-shutdown** | Enabled (7 PM CET) |

---

## 🚨 Required Post-Deployment Steps

The VM is running but **Rhino.Compute requires the API key to be set** before it can accept requests.

### Option 1: Azure CLI (Recommended - Quick)

From your terminal:

```bash
# Get the API key from Key Vault
API_KEY=$(az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name RHINO-COMPUTE-KEY \
  --query value -o tsv)

# Set the environment variable on the VM and restart IIS
az vm run-command invoke \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-rhino-vm \
  --command-id RunPowerShellScript \
  --scripts "[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', '$API_KEY', 'Machine'); iisreset /restart; Write-Host 'API key set and IIS restarted'"
```

### Option 2: Azure Portal

1. Go to Azure Portal → Virtual Machines → `kuduso-dev-rhino-vm`
2. Click **Run command** → **RunPowerShellScript**
3. Paste and run:

```powershell
# Retrieve API key from Key Vault using VM's Managed Identity
$token = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' -Method GET -Headers @{Metadata="true"} | ConvertFrom-Json).access_token
$secret = (Invoke-RestMethod -Uri 'https://kuduso-dev-kv-93d2ab.vault.azure.net/secrets/RHINO-COMPUTE-KEY?api-version=7.0' -Method GET -Headers @{Authorization="Bearer $token"} | ConvertFrom-Json).value
[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $secret, 'Machine')
iisreset /restart
Write-Host "API key set and IIS restarted successfully"
```

### Option 3: Via RDP

1. Connect via RDP: `mstsc /v:51.137.35.150`
   - Username: `rhinoadmin`
   - Password: (from `RHINO_VM_PASSWORD` env var or default)

2. Open PowerShell as Administrator and run:

```powershell
# Retrieve from Key Vault (VM has Managed Identity access)
Install-Module -Name Az.KeyVault -Force -Scope CurrentUser
Connect-AzAccount -Identity
$apiKey = (Get-AzKeyVaultSecret -VaultName "kuduso-dev-kv-93d2ab" -Name "RHINO-COMPUTE-KEY").SecretValueText

# Set environment variable
[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $apiKey, 'Machine')

# Restart IIS
iisreset /restart
```

---

## Verification Steps

After setting the API key, verify Rhino.Compute is working:

### 1. Check Rhino.Compute Endpoint

```bash
curl http://51.137.35.150:8081/version
```

Expected response: Rhino.Compute version information

### 2. Test from AppServer

Update AppServer environment variables with new IP if needed:
```bash
COMPUTE_URL=http://51.137.35.150:8081/
```

### 3. End-to-End Test

Run a complete workflow test from your API → Worker → AppServer → Rhino.Compute:

```bash
# Navigate to your API test directory
cd /home/martin/Desktop/kuduso/apps/sitefit/api-fastapi

# Run test (adjust based on your test setup)
# Example:
# pytest tests/test_integration.py
```

---

## Infrastructure Configuration

All infrastructure is defined in:
- **Rhino VM Config:** `/home/martin/Desktop/kuduso/infra/live/dev/shared/rhino/terragrunt.hcl`
- **Compute Gallery:** `/home/martin/Desktop/kuduso/infra/live/dev/shared/compute-gallery/terragrunt.hcl`
- **VM Module:** `/home/martin/Desktop/kuduso/infra/modules/rhino-vm/`

---

## Network Security

The VM has the following access rules (NSG):
- **RDP (3389):** Your IP only (`178.40.216.159/32`)
- **HTTP (80):** Your IP only
- **Rhino.Compute (8081):** 
  - Your IP
  - Azure Container Apps outbound IPs (for AppServer access)
- **Windows Admin Center (6516):** Your IP only

---

## Next Steps for Stage 4 Testing

1. ✅ **Set the API key** (choose one of the options above)
2. ✅ **Verify Rhino.Compute is responding** at `http://51.137.35.150:8081/`
3. ✅ **Update any hardcoded IPs** in your AppServer config (if applicable)
4. ✅ **Run end-to-end workflow test** from API → Worker → AppServer → Rhino
5. ✅ **Monitor logs** in Azure Log Analytics for any errors

---

## Troubleshooting

### If Rhino.Compute is not responding:

1. **Check IIS is running:**
   ```bash
   az vm run-command invoke \
     --resource-group kuduso-dev-rg \
     --name kuduso-dev-rhino-vm \
     --command-id RunPowerShellScript \
     --scripts "Get-Service -Name W3SVC | Select-Object Name, Status"
   ```

2. **Restart IIS:**
   ```bash
   az vm run-command invoke \
     --resource-group kuduso-dev-rg \
     --name kuduso-dev-rhino-vm \
     --command-id RunPowerShellScript \
     --scripts "iisreset /restart"
   ```

3. **Check Windows Event Logs via RDP** for any Rhino.Compute errors

4. **Verify API key is set:**
   ```bash
   az vm run-command invoke \
     --resource-group kuduso-dev-rg \
     --name kuduso-dev-rhino-vm \
     --command-id RunPowerShellScript \
     --scripts "[System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')"
   ```

---

## Cost Optimization

- Auto-shutdown enabled at **7 PM CET daily**
- VM will automatically stop to save costs
- Start manually when needed:
  ```bash
  az vm start --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm
  ```

---

## Notes

- The VM was recreated cleanly from a tested compute gallery image
- All previous VM state/corruption is eliminated
- Public IP address has changed: `52.148.197.239` → `51.137.35.150`
- Update any external configurations that referenced the old IP

---

**Created by:** Windsurf Cascade AI Assistant  
**Last Updated:** November 25, 2024
