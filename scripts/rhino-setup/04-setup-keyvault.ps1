#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 4: Fetch RHINO_COMPUTE_KEY from Azure Key Vault and set as environment variable
#>

param(
    [string]$KeyVaultName = "kuduso-dev-kv-93d2ab",
    [string]$SecretName = "RHINO-COMPUTE-KEY"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 4: Setup API Key from Key Vault" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Key Vault: $KeyVaultName" -ForegroundColor Yellow
Write-Host "Secret: $SecretName" -ForegroundColor Yellow
Write-Host ""

# Check if already set
$existing = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
if ($existing) {
    Write-Host "✓ RHINO_COMPUTE_KEY already set" -ForegroundColor Green
    Write-Host "  Value length: $($existing.Length) characters" -ForegroundColor Gray
    Write-Host "  Preview: $($existing.Substring(0, [Math]::Min(10, $existing.Length)))..." -ForegroundColor Gray
    Write-Host ""
    Write-Host "To re-fetch from Key Vault, delete the environment variable first:" -ForegroundColor Yellow
    Write-Host '  [System.Environment]::SetEnvironmentVariable("RHINO_COMPUTE_KEY", $null, "Machine")' -ForegroundColor Gray
    Write-Host ""
    Write-Host "Step 4: COMPLETE - Continue to 05-download-compute.ps1" -ForegroundColor Green
    exit 0
}

Write-Host "Fetching API key from Azure Key Vault..." -ForegroundColor Yellow

try {
    Write-Host "[1/3] Getting Managed Identity access token..." -ForegroundColor Yellow
    
    $tokenUri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net'
    
    $tokenResponse = Invoke-RestMethod -Uri $tokenUri `
        -Method GET `
        -Headers @{Metadata = "true" } `
        -UseBasicParsing `
        -TimeoutSec 10
    
    if (!$tokenResponse.access_token) {
        throw "Failed to get access token from Managed Identity"
    }
    
    Write-Host "✓ Access token obtained" -ForegroundColor Green
    
    Write-Host "[2/3] Fetching secret from Key Vault..." -ForegroundColor Yellow
    
    $secretUri = "https://$KeyVaultName.vault.azure.net/secrets/$SecretName?api-version=7.4"
    $headers = @{
        'Authorization' = "Bearer $($tokenResponse.access_token)"
    }
    
    $secretResponse = Invoke-RestMethod -Uri $secretUri `
        -Headers $headers `
        -Method GET `
        -UseBasicParsing
    
    if (!$secretResponse.value) {
        throw "Secret value is empty"
    }
    
    $computeKey = $secretResponse.value
    Write-Host "✓ Secret retrieved successfully" -ForegroundColor Green
    Write-Host "  Value length: $($computeKey.Length) characters" -ForegroundColor Gray
    
    Write-Host "[3/3] Setting as system environment variable..." -ForegroundColor Yellow
    
    # Set as machine-level environment variable
    [System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $computeKey, 'Machine')
    
    # Also set for current session
    $env:RHINO_COMPUTE_KEY = $computeKey
    
    # Verify
    $verified = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
    if ($verified -eq $computeKey) {
        Write-Host "✓ Environment variable set successfully" -ForegroundColor Green
    }
    else {
        throw "Environment variable verification failed"
    }
    
    Write-Host ""
    Write-Host "✓ RHINO_COMPUTE_KEY configured" -ForegroundColor Green
    Write-Host ""
    Write-Host "Step 4: COMPLETE - Continue to 05-download-compute.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to fetch API key: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify VM has Managed Identity enabled:"
    Write-Host "   az vm identity show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm"
    Write-Host ""
    Write-Host "2. Verify Key Vault access policy:"
    Write-Host "   az keyvault set-policy --name $KeyVaultName --object-id <VM_IDENTITY_ID> --secret-permissions get"
    Write-Host ""
    Write-Host "3. Verify secret exists:"
    Write-Host "   az keyvault secret show --vault-name $KeyVaultName --name $SecretName"
    Write-Host ""
    Write-Host "Manual workaround:" -ForegroundColor Yellow
    Write-Host "Get the key from your local machine and set manually:" -ForegroundColor Yellow
    Write-Host '  $key = "paste-key-here"' -ForegroundColor Gray
    Write-Host '  [System.Environment]::SetEnvironmentVariable("RHINO_COMPUTE_KEY", $key, "Machine")' -ForegroundColor Gray
    exit 1
}
