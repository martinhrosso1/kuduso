#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 3: Install .NET Runtimes via Chocolatey
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 3: Install .NET Runtimes" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Verify Chocolatey is installed
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "✗ Chocolatey not found. Run 01-install-chocolatey.ps1 first" -ForegroundColor Red
    throw "Chocolatey not found - run script 01 first"
}

Write-Host "Installing .NET 8.0 SDK and runtimes..." -ForegroundColor Yellow
Write-Host "This may take 10-15 minutes..." -ForegroundColor Yellow
Write-Host ""

try {
    # Install .NET components
    Write-Host "[1/5] Installing .NET 8.0 SDK..." -ForegroundColor Yellow
    choco install dotnet-8.0-sdk -y --no-progress
    
    Write-Host "[2/5] Installing .NET 8.0 Runtime..." -ForegroundColor Yellow
    choco install dotnet-8.0-runtime -y --no-progress
    
    Write-Host "[3/5] Installing .NET 8.0 Desktop Runtime (required for Rhino)..." -ForegroundColor Yellow
    choco install dotnet-8.0-desktopruntime -y --no-progress
    
    Write-Host "[4/5] Installing ASP.NET Core 8.0 Hosting Bundle (IIS Module)..." -ForegroundColor Yellow
    choco install dotnet-8.0-aspnetcoremodule-v2 -y --no-progress
    
    Write-Host "[5/5] Restarting IIS to register ASP.NET Core Module..." -ForegroundColor Yellow
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 3
    
    Write-Host ""
    Write-Host "✓ .NET runtimes installed successfully" -ForegroundColor Green
    
    # Verify installation
    Write-Host ""
    Write-Host "Verifying .NET installation:" -ForegroundColor Cyan
    dotnet --version
    dotnet --list-runtimes
    
    Write-Host ""
    Write-Host "Step 3: COMPLETE - Continue to 04-setup-keyvault.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to install .NET: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Check internet connectivity"
    Write-Host "2. Try manual install: https://dotnet.microsoft.com/download"
    Write-Host "3. Continue anyway - Rhino.Compute might work with existing .NET"
    Write-Host ""
    Write-Host "You can skip this error and continue to step 4" -ForegroundColor Yellow
    throw "Script failed - see error above"
}
