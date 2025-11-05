#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 4a: Install build tools required for Rhino.Compute
.DESCRIPTION
    Installs Git and Visual Studio 2022 Build Tools needed to build Rhino.Compute from source
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 4a: Install Build Tools" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Required for building Rhino.Compute from source" -ForegroundColor Yellow
Write-Host ""

# Check if already installed
$allInstalled = $true
$tools = @()

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    $allInstalled = $false
    $tools += "Git"
}

# Check for Visual Studio 2022 in both possible locations
$vs2022Found = (Test-Path "C:\Program Files\Microsoft Visual Studio\2022") -or 
               (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022")
if (!$vs2022Found) {
    $allInstalled = $false
    $tools += "Visual Studio 2022"
}

if ($allInstalled) {
    Write-Host "✓ All build tools already installed" -ForegroundColor Green
    Write-Host "  Git: $(git --version)" -ForegroundColor Gray
    Write-Host "  Visual Studio: Installed" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Step 4a: COMPLETE - Continue to 4b-verify-rhino.ps1" -ForegroundColor Green
    return
}

Write-Host "Installing build tools..." -ForegroundColor Yellow
Write-Host "Missing: $($tools -join ', ')" -ForegroundColor Gray
Write-Host "This will take 15-20 minutes" -ForegroundColor Gray
Write-Host ""

try {
    # Install Git
    if ($tools -contains "Git") {
        Write-Host "[1/2] Installing Git..." -ForegroundColor Yellow
        
        # Verify Chocolatey
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            throw "Chocolatey not found. Run 01-install-chocolatey.ps1 first"
        }
        
        choco install git -y --force --no-progress
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Write-Host "✓ Git installed: $(git --version)" -ForegroundColor Green
        }
        else {
            throw "Git installation failed"
        }
    }
    else {
        Write-Host "[1/2] Git already installed" -ForegroundColor Green
    }
    
    # Install Visual Studio Build Tools
    if ($tools -contains "Visual Studio 2022") {
        Write-Host "[2/2] Installing Visual Studio 2022 Build Tools..." -ForegroundColor Yellow
        Write-Host "  This will download ~2GB and take 15-20 minutes" -ForegroundColor Gray
        Write-Host ""
        
        $vsUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
        $vsInstaller = "$env:TEMP\vs_buildtools.exe"
        
        Write-Host "  Downloading installer..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $vsUrl -OutFile $vsInstaller -UseBasicParsing
        
        Write-Host "  Installing (please wait, this is silent)..." -ForegroundColor Gray
        
        # Install with required workloads for building .NET projects
        $vsArgs = @(
            "--quiet",
            "--wait",
            "--norestart",
            "--nocache",
            "--add", "Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools",
            "--add", "Microsoft.Net.Component.4.8.SDK",
            "--add", "Microsoft.NetCore.Component.Runtime.8.0",
            "--add", "Microsoft.NetCore.Component.SDK"
        )
        
        $process = Start-Process -FilePath $vsInstaller -ArgumentList $vsArgs -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Host "✓ Visual Studio Build Tools installed" -ForegroundColor Green
        }
        else {
            throw "Visual Studio installation failed with exit code: $($process.ExitCode)"
        }
        
        # Clean up
        Remove-Item $vsInstaller -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "[2/2] Visual Studio already installed" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "✓ All build tools installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Step 4a: COMPLETE - Continue to 4b-verify-rhino.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to install build tools: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're running PowerShell as Administrator" -ForegroundColor Gray
    Write-Host "2. Check internet connectivity" -ForegroundColor Gray
    Write-Host "3. Verify Windows Update is not blocking installations" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Manual installation:" -ForegroundColor Yellow
    Write-Host "Git: choco install git -y" -ForegroundColor Gray
    Write-Host "VS Build Tools: https://aka.ms/vs/17/release/vs_BuildTools.exe" -ForegroundColor Gray
    throw "Script failed - see error above"
}
