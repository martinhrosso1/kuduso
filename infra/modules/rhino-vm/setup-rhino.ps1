# PowerShell script to setup Rhino.Compute on Windows Server
# Run this script manually on the VM after it's provisioned

# Configuration
$RhinoComputeVersion = "8.0.0" # Update to desired version
$InstallDir = "C:\RhinoCompute"
$Port = 8081

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Rhino.Compute Setup Script" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Create installation directory
Write-Host "Creating installation directory..." -ForegroundColor Yellow
New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

# Download Rhino.Compute
# Note: Replace this URL with the actual Rhino.Compute download link
# You may need to download from McNeel website and upload to Azure Blob
Write-Host "Downloading Rhino.Compute..." -ForegroundColor Yellow
Write-Host "  Version: $RhinoComputeVersion" -ForegroundColor Gray
Write-Host ""
Write-Host "  ⚠️  MANUAL STEP REQUIRED:" -ForegroundColor Red
Write-Host "  1. Download Rhino.Compute from McNeel" -ForegroundColor White
Write-Host "  2. Upload to Azure Blob or copy to VM" -ForegroundColor White
Write-Host "  3. Extract to $InstallDir" -ForegroundColor White
Write-Host ""

# Install .NET prerequisites
Write-Host "Installing .NET Framework prerequisites..." -ForegroundColor Yellow
# Rhino.Compute requires .NET Framework 4.8 or later (usually pre-installed on Windows Server 2022)

# Configure Windows Firewall
Write-Host "Configuring Windows Firewall..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "Rhino.Compute HTTP" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Rhino.Compute $Port" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $Port `
    -Action Allow `
    -ErrorAction SilentlyContinue

Write-Host "✓ Firewall rules created" -ForegroundColor Green

# Generate API Key
Write-Host "Generating API Key..." -ForegroundColor Yellow
$ApiKey = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([System.Guid]::NewGuid().ToString()))
Write-Host "✓ API Key generated" -ForegroundColor Green
Write-Host ""
Write-Host "  🔑 API Key: $ApiKey" -ForegroundColor Cyan
Write-Host "  📝 Save this key in Azure Key Vault!" -ForegroundColor Yellow
Write-Host ""

# Save configuration
$ConfigContent = @"
{
  "Port": $Port,
  "ApiKey": "$ApiKey",
  "ChildCount": 4,
  "IdleSpan": 3600
}
"@

$ConfigPath = Join-Path $InstallDir "appsettings.Production.json"
$ConfigContent | Out-File -FilePath $ConfigPath -Encoding UTF8
Write-Host "✓ Configuration saved to $ConfigPath" -ForegroundColor Green

# Create service (manual step - Rhino.Compute needs to be installed first)
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Next Steps:" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Download Rhino.Compute binary" -ForegroundColor White
Write-Host "2. Extract to $InstallDir" -ForegroundColor White
Write-Host "3. Run: .\compute.geometry.exe" -ForegroundColor White
Write-Host "4. Test: http://localhost:$Port/version" -ForegroundColor White
Write-Host "5. Add API Key to Azure Key Vault:" -ForegroundColor White
Write-Host "   az keyvault secret set --vault-name <KV_NAME> \\" -ForegroundColor Gray
Write-Host "     --name COMPUTE-API-KEY --value '$ApiKey'" -ForegroundColor Gray
Write-Host ""
Write-Host "6. To run as Windows Service:" -ForegroundColor White
Write-Host "   sc.exe create RhinoCompute binPath= '$InstallDir\compute.geometry.exe'" -ForegroundColor Gray
Write-Host "   sc.exe start RhinoCompute" -ForegroundColor Gray
Write-Host ""

# Save API key to file for easy access
$ApiKey | Out-File -FilePath "C:\rhino-api-key.txt" -Encoding UTF8
Write-Host "✓ API Key also saved to C:\rhino-api-key.txt" -ForegroundColor Green
Write-Host ""
