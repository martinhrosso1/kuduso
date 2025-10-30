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
    exit 1
}

Write-Host "Installing .NET 8.0 SDK and runtimes..." -ForegroundColor Yellow
Write-Host "This may take 10-15 minutes..." -ForegroundColor Yellow
Write-Host ""

try {
    # Install .NET components
    Write-Host "[1/4] Installing .NET 8.0 SDK..." -ForegroundColor Yellow
    choco install dotnet-8.0-sdk -y --no-progress
    
    Write-Host "[2/4] Installing .NET 8.0 Runtime..." -ForegroundColor Yellow
    choco install dotnet-8.0-runtime -y --no-progress
    
    Write-Host "[3/4] Installing .NET 8.0 Desktop Runtime (required for Rhino)..." -ForegroundColor Yellow
    choco install dotnet-8.0-desktopruntime -y --no-progress
    
    Write-Host "[4/4] Installing ASP.NET Core Hosting Bundle..." -ForegroundColor Yellow
    choco install dotnet-aspnethosting-bundle -y --no-progress
    
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
    exit 1
}
