#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 5: Download and extract Rhino.Compute binaries
#>

param(
    [string]$InstallPath = "C:\inetpub\compute"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 5: Download Rhino.Compute" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Install Path: $InstallPath" -ForegroundColor Yellow
Write-Host ""

# Check if already downloaded
if (Test-Path "$InstallPath\compute.geometry.exe") {
    Write-Host "✓ Rhino.Compute already downloaded" -ForegroundColor Green
    Write-Host "  Location: $InstallPath\compute.geometry.exe" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To re-download, delete the folder first:" -ForegroundColor Yellow
    Write-Host "  Remove-Item -Path $InstallPath -Recurse -Force" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Step 5: COMPLETE - Continue to 06-configure-iis.ps1" -ForegroundColor Green
    exit 0
}

Write-Host "Downloading Rhino.Compute binaries..." -ForegroundColor Yellow

try {
    # Create install directory
    Write-Host "[1/4] Creating directory: $InstallPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
    
    # Download
    Write-Host "[2/4] Downloading from GitHub (latest release)..." -ForegroundColor Yellow
    $computeZipUrl = "https://github.com/mcneel/compute.rhino3d/releases/latest/download/rhino.compute.zip"
    $computeZip = "$env:TEMP\rhino.compute.zip"
    
    # Enable TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    Invoke-WebRequest -Uri $computeZipUrl -OutFile $computeZip -UseBasicParsing
    
    $zipSize = (Get-Item $computeZip).Length / 1MB
    Write-Host "✓ Downloaded $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
    
    # Extract
    Write-Host "[3/4] Extracting archive..." -ForegroundColor Yellow
    Expand-Archive -Path $computeZip -DestinationPath $InstallPath -Force
    Write-Host "✓ Extraction complete" -ForegroundColor Green
    
    # Verify
    Write-Host "[4/4] Verifying installation..." -ForegroundColor Yellow
    
    $files = @(
        "compute.geometry.exe",
        "compute.geometry.dll"
    )
    
    $allFound = $true
    foreach ($file in $files) {
        if (Test-Path "$InstallPath\$file") {
            Write-Host "  ✓ Found: $file" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Missing: $file" -ForegroundColor Red
            $allFound = $false
        }
    }
    
    if (!$allFound) {
        throw "Some required files are missing"
    }
    
    # Create logs directory
    New-Item -ItemType Directory -Path "$InstallPath\logs" -Force | Out-Null
    
    # Clean up
    Remove-Item $computeZip -Force
    
    Write-Host ""
    Write-Host "✓ Rhino.Compute downloaded successfully" -ForegroundColor Green
    Write-Host "  Location: $InstallPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Step 5: COMPLETE - Continue to 06-configure-iis.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to download Rhino.Compute: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Check internet connectivity"
    Write-Host "2. Verify GitHub is accessible"
    Write-Host "3. Try manual download: https://github.com/mcneel/compute.rhino3d/releases"
    Write-Host ""
    Write-Host "Manual installation:" -ForegroundColor Yellow
    Write-Host "1. Download rhino.compute.zip from GitHub"
    Write-Host "2. Extract to: $InstallPath"
    exit 1
}
