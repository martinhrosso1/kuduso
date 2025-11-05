#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 1: Install Chocolatey Package Manager
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 1: Install Chocolatey" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if already installed
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "✓ Chocolatey already installed" -ForegroundColor Green
    choco --version
    Write-Host ""
    Write-Host "Step 1: COMPLETE" -ForegroundColor Green
    return
}

Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow

try {
    # Set execution policy
    Set-ExecutionPolicy Bypass -Scope Process -Force
    
    # Enable TLS 1.2
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    
    # Download and install
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    
    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    Write-Host ""
    Write-Host "✓ Chocolatey installed successfully" -ForegroundColor Green
    choco --version
    
    Write-Host ""
    Write-Host "IMPORTANT: Close this PowerShell window and open a new one as Administrator" -ForegroundColor Yellow
    Write-Host "Then run: 02-install-iis.ps1" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Step 1: COMPLETE" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to install Chocolatey: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're running PowerShell as Administrator"
    Write-Host "2. Check internet connectivity"
    Write-Host "3. Try manual install: https://chocolatey.org/install"
    throw "Script failed - see error above"
}
