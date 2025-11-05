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
    return
}

Write-Host "IMPORTANT: Rhino.Compute is no longer distributed as pre-built binaries!" -ForegroundColor Yellow
Write-Host "You must build it from source. This script will clone and build it." -ForegroundColor Yellow
Write-Host ""

# Check for required tools
$missingTools = @()
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    $missingTools += "Git"
}

# Check for Visual Studio 2022 in both possible locations
$vs2022Found = (Test-Path "C:\Program Files\Microsoft Visual Studio\2022") -or 
               (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022")
if (!$vs2022Found) {
    $missingTools += "Visual Studio 2022"
}

if (!(Test-Path "C:\Program Files\Rhino 8")) {
    $missingTools += "Rhino 8"
}

if ($missingTools.Count -gt 0) {
    Write-Host "✗ Missing required tools:" -ForegroundColor Red
    $missingTools | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Install required tools:" -ForegroundColor Yellow
    Write-Host "1. Rhino 8: https://www.rhino3d.com/download/rhino-for-windows/8/latest" -ForegroundColor Gray
    Write-Host "2. Visual Studio 2022: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Gray
    Write-Host "3. Git: choco install git -y" -ForegroundColor Gray
    Write-Host ""
    Write-Host "ALTERNATIVE: For quick testing, use pre-built community version:" -ForegroundColor Cyan
    Write-Host "  https://files.mcneel.com/rhino.compute/" -ForegroundColor Gray
    throw "Missing required tools"
}

try {
    # Create install directory
    Write-Host "[1/5] Creating directory: $InstallPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
    
    # Clone repository
    Write-Host "[2/5] Cloning compute.rhino3d repository..." -ForegroundColor Yellow
    $repoPath = "$env:TEMP\compute.rhino3d"
    if (Test-Path $repoPath) {
        Remove-Item -Path $repoPath -Recurse -Force
    }
    
    git clone --branch 8.x --depth 1 https://github.com/mcneel/compute.rhino3d.git $repoPath
    if ($LASTEXITCODE -ne 0) {
        throw "Git clone failed"
    }
    Write-Host "✓ Repository cloned" -ForegroundColor Green
    
    # Restore NuGet packages
    Write-Host "[3/6] Restoring NuGet packages..." -ForegroundColor Yellow
    $slnPath = "$repoPath\src\compute.sln"
    
    # Use dotnet restore (comes with .NET SDK)
    & dotnet restore $slnPath
    
    if ($LASTEXITCODE -ne 0) {
        throw "NuGet restore failed. Check internet connectivity"
    }
    Write-Host "✓ NuGet packages restored" -ForegroundColor Green
    
    # Build with MSBuild
    Write-Host "[4/6] Building compute.geometry.exe (this may take 5-10 minutes)..." -ForegroundColor Yellow
    
    # Check for MSBuild in both 64-bit and x86 locations
    $msbuildPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe"
    )
    
    $msbuild = $null
    foreach ($path in $msbuildPaths) {
        if (Test-Path $path) {
            $msbuild = $path
            Write-Host "  Found MSBuild: $path" -ForegroundColor Gray
            break
        }
    }
    
    if (!$msbuild) {
        throw "MSBuild not found. Install Visual Studio 2022 Build Tools"
    }
    
    & $msbuild $slnPath /p:Configuration=Release /p:Platform="Any CPU" /v:m
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed. Check Visual Studio installation and Rhino SDK"
    }
    Write-Host "✓ Build complete" -ForegroundColor Green
    
    # Copy binaries
    Write-Host "[5/6] Copying binaries..." -ForegroundColor Yellow
    
    # Copy from the two project output directories
    $computeGeometryOutput = "$repoPath\src\bin\Release\compute.geometry"
    $rhinoComputeOutput = "$repoPath\src\bin\Release\rhino.compute"
    
    if (Test-Path $computeGeometryOutput) {
        Write-Host "  Copying from compute.geometry..." -ForegroundColor Gray
        Copy-Item -Path "$computeGeometryOutput\*" -Destination $InstallPath -Recurse -Force
    }
    
    if (Test-Path $rhinoComputeOutput) {
        Write-Host "  Copying from rhino.compute..." -ForegroundColor Gray
        Copy-Item -Path "$rhinoComputeOutput\*" -Destination $InstallPath -Recurse -Force
    }
    
    # Remove .NET runtime DLLs (use system installation instead)
    Write-Host "  Cleaning up .NET runtime DLLs..." -ForegroundColor Gray
    $runtimeDlls = @(
        "clretwrc.dll", "clrgc.dll", "clrjit.dll", "coreclr.dll", "createdump.exe",
        "hostfxr.dll", "hostpolicy.dll", "mscordaccore*.dll", "mscordbi.dll",
        "mscorlib.dll", "mscorrc.dll", "System.Private.CoreLib.dll"
    )
    foreach ($dll in $runtimeDlls) {
        Get-ChildItem "$InstallPath\$dll" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    Write-Host "✓ Binaries copied" -ForegroundColor Green
    
    # Verify
    Write-Host "[6/6] Verifying installation..." -ForegroundColor Yellow
    
    # Check for key executables and DLLs
    $requiredFiles = @(
        "compute.geometry.dll",
        "rhino.compute.exe"
    )
    
    $allFound = $true
    foreach ($file in $requiredFiles) {
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
    Write-Host "Cleaning up temporary files..." -ForegroundColor Gray
    Remove-Item -Path $repoPath -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Host "✓ Rhino.Compute built successfully!" -ForegroundColor Green
    Write-Host "  Location: $InstallPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Step 5: COMPLETE - Continue to 06-configure-iis.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to build Rhino.Compute: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure Rhino 8 is installed and licensed"
    Write-Host "2. Install Visual Studio 2022 with .NET desktop development workload"
    Write-Host "3. Install Git: choco install git -y"
    Write-Host "4. Check internet connectivity for GitHub access"
    Write-Host ""
    Write-Host "Manual build:" -ForegroundColor Yellow
    Write-Host "1. Clone: git clone --branch 8.x https://github.com/mcneel/compute.rhino3d.git"
    Write-Host "2. Open src\compute.sln in Visual Studio 2022"
    Write-Host "3. Build in Release mode"
    Write-Host "4. Copy binaries from src\bin\Release to $InstallPath"
    throw "Script failed - see error above"
}
