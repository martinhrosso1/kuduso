#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 4b: Verify Rhino 8 installation
.DESCRIPTION
    Checks if Rhino 8 is installed and provides guidance for installation and licensing
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 4b: Verify Rhino 8" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Rhino 8 is required to build Rhino.Compute" -ForegroundColor Yellow
Write-Host ""

# Check if Rhino 8 is installed
$rhinoPath = "C:\Program Files\Rhino 8"
$rhinoExe = "$rhinoPath\System\Rhino.exe"

if (!(Test-Path $rhinoPath)) {
    Write-Host "✗ Rhino 8 is NOT installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "REQUIRED: Install Rhino 8" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Steps to install:" -ForegroundColor Cyan
    Write-Host "1. Download Rhino 8 from:" -ForegroundColor Gray
    Write-Host "   https://www.rhino3d.com/download/rhino-for-windows/8/latest" -ForegroundColor White
    Write-Host ""
    Write-Host "2. Run the installer" -ForegroundColor Gray
    Write-Host "3. Launch Rhino and complete the licensing process" -ForegroundColor Gray
    Write-Host "   (You'll need a valid Rhino 8 license)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. After installation, run this script again to verify" -ForegroundColor Gray
    Write-Host ""
    
    $response = Read-Host "Do you want to open the Rhino download page now? (Y/N)"
    if ($response -eq "Y" -or $response -eq "y") {
        Start-Process "https://www.rhino3d.com/download/rhino-for-windows/8/latest"
        Write-Host "✓ Browser opened. Install Rhino and run this script again." -ForegroundColor Yellow
    }
    
    throw "Rhino 8 not installed"
}

Write-Host "✓ Rhino 8 is installed" -ForegroundColor Green
Write-Host "  Location: $rhinoPath" -ForegroundColor Gray

# Check if Rhino executable exists
if (Test-Path $rhinoExe) {
    $version = (Get-Item $rhinoExe).VersionInfo.FileVersion
    Write-Host "  Version: $version" -ForegroundColor Gray
}

Write-Host ""
Write-Host "IMPORTANT: Rhino 8 must be licensed!" -ForegroundColor Yellow
Write-Host ""
Write-Host "Verify licensing:" -ForegroundColor Cyan
Write-Host "1. Launch Rhino: Start > Rhino 8" -ForegroundColor Gray
Write-Host "2. If prompted, complete the licensing process" -ForegroundColor Gray
Write-Host "3. Verify Rhino starts without license warnings" -ForegroundColor Gray
Write-Host ""

$response = Read-Host "Has Rhino 8 been licensed successfully? (Y/N)"
if ($response -ne "Y" -and $response -ne "y") {
    Write-Host ""
    Write-Host "⚠ Please license Rhino 8 before continuing" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Licensing options:" -ForegroundColor Cyan
    Write-Host "- Stand-alone license (enter license key)" -ForegroundColor Gray
    Write-Host "- Cloud Zoo (login with Rhino account)" -ForegroundColor Gray
    Write-Host "- LAN Zoo (connect to license server)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "After licensing, run this script again." -ForegroundColor Yellow
    
    throw "Rhino 8 not licensed"
}

Write-Host ""
Write-Host "✓ Rhino 8 verified and licensed!" -ForegroundColor Green
Write-Host ""
Write-Host "Step 4b: COMPLETE - Continue to 05-download-compute.ps1" -ForegroundColor Green
