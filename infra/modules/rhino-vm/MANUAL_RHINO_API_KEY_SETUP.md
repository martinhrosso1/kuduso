az vm run-command invoke --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm --command-id RunPowerShellScript --scripts "[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', (az keyvault secret show --vault-name kuduso-dev-kv --name RHINO-COMPUTE-KEY --query value -o tsv), 'Machine'); iisreset /restart; Write-Host 'API key set and IIS restarted'"



## 🔧 **Final Step: Set API Key**

Now I'll set the API key and restart IIS:

The API key setup was skipped. You can set it manually or via Azure Run Command later. Let me verify the VM is using the custom image:


## 📝 **Post-Deployment Steps**

### **Option 1: Via Azure Portal**
1. Go to Azure Portal → Virtual Machines → `kuduso-dev-rhino-vm`
2. Click **Run command** → **RunPowerShellScript**
3. Paste:
```powershell
$apiKey = (Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' -Method GET -Headers @{Metadata="true"} | ConvertFrom-Json).access_token
$secret = (Invoke-RestMethod -Uri 'https://kuduso-dev-kv-93d2ab.vault.azure.net/secrets/RHINO-COMPUTE-KEY?api-version=7.0' -Method GET -Headers @{Authorization="Bearer $apiKey"} | ConvertFrom-Json).value
[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $secret, 'Machine')
iisreset /restart
Write-Host "API key set and IIS restarted"
```

### **Option 2: Via RDP**
1. RDP to VM: `mstsc /v:52.148.197.239`
2. Open PowerShell as Administrator:
```powershell
# Get secret from Key Vault (VM has access via Managed Identity)
$apiKey = "YOUR_KEY_FROM_KEYVAULT"
[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $apiKey, 'Machine')
iisreset /restart
```

### **Option 3: Azure CLI (from terminal)**
```bash
# Get the API key
API_KEY=$(az keyvault secret show \
  --vault-name kuduso-dev-kv \
  --name RHINO-COMPUTE-KEY \
  --query value -o tsv)

# Set on VM via Run Command
az vm run-command invoke \
  --resource-group kuduso-dev-rg \
  --name kuduso-dev-rhino-vm \
  --command-id RunPowerShellScript \
  --scripts "[System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', '$API_KEY', 'Machine'); iisreset /restart"
```