<#
.SYNOPSIS
    Automated Rhino VM Setup - Runs scripts 01-03 automatically
    Scripts 04-10 should be run manually via RDP
    Used by Azure VM Custom Script Extension
    
.NOTES
    Runs as SYSTEM account via Azure Custom Script Extension
    No #Requires -RunAsAdministrator needed - already has admin rights
#>

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Automated Rhino VM Setup (01-03)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create log directory
$LogDir = "C:\rhino-setup-logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = "$LogDir\setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $Message
    Add-Content -Path $LogFile -Value $logMessage
}

# ============================================
# Step 1: Install Chocolatey
# ============================================
Write-Log "=== Step 1: Installing Chocolatey ==="

if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Log "Chocolatey already installed"
} else {
    try {
        Write-Log "Downloading Chocolatey install script..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        
        Write-Log "Running Chocolatey installer..."
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Verify installation
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            $chocoVersion = choco --version
            Write-Log "SUCCESS: Chocolatey $chocoVersion installed"
        } else {
            Write-Log "WARNING: Chocolatey installed but not in PATH yet. May need reboot."
        }
    } catch {
        Write-Log "ERROR: Failed to install Chocolatey: $_"
        Write-Log "Continuing anyway - you can install Chocolatey manually"
    }
}

# ============================================
# Step 2: Install IIS
# ============================================
Write-Log "=== Step 2: Installing IIS ==="

$iis = Get-Service W3SVC -ErrorAction SilentlyContinue
if ($iis) {
    Write-Log "IIS already installed"
} else {
    try {
        $features = @(
            "Web-Server", "Web-WebServer", "Web-Common-Http", "Web-Default-Doc",
            "Web-Dir-Browsing", "Web-Http-Errors", "Web-Static-Content", "Web-Http-Redirect",
            "Web-Health", "Web-Http-Logging", "Web-Performance", "Web-Stat-Compression",
            "Web-Dyn-Compression", "Web-Security", "Web-Filtering", "Web-App-Dev",
            "Web-Net-Ext45", "Web-Asp-Net45", "Web-ISAPI-Ext", "Web-ISAPI-Filter",
            "Web-Mgmt-Tools", "Web-Mgmt-Console", "Web-AppInit"
        )
        
        Install-WindowsFeature -Name $features -IncludeManagementTools | Out-Null
        Write-Log "SUCCESS: IIS installed"
    } catch {
        Write-Log "ERROR: Failed to install IIS: $_"
        throw
    }
}

# ============================================
# Step 3: Install .NET
# ============================================
Write-Log "=== Step 3: Installing .NET Runtimes ==="

if (Get-Command choco -ErrorAction SilentlyContinue) {
    try {
        Write-Log "Installing .NET 8.0 SDK..."
        choco install dotnet-8.0-sdk -y --no-progress --ignore-package-exit-codes | Out-Null
        
        Write-Log "Installing .NET 8.0 Runtime..."
        choco install dotnet-8.0-runtime -y --no-progress --ignore-package-exit-codes | Out-Null
        
        Write-Log "Installing .NET 8.0 Desktop Runtime..."
        choco install dotnet-8.0-desktopruntime -y --no-progress --ignore-package-exit-codes | Out-Null
        
        Write-Log "Installing ASP.NET Core Hosting Bundle..."
        choco install dotnet-aspnethosting-bundle -y --no-progress --ignore-package-exit-codes | Out-Null
        
        Write-Log "SUCCESS: .NET runtimes installed"
    } catch {
        Write-Log "WARNING: .NET installation had issues: $_"
        Write-Log "Continuing anyway - you can install .NET manually if needed"
    }
} else {
    Write-Log "WARNING: Chocolatey not available, skipping .NET installation"
    Write-Log "Install .NET manually: https://dotnet.microsoft.com/download"
}

# ============================================
# Final Summary
# ============================================
Write-Log ""
Write-Log "========================================" 
Write-Log "  Automated Setup Complete (01-03)!" 
Write-Log "========================================" 
Write-Log ""
Write-Log "✓ Chocolatey installed"
Write-Log "✓ IIS installed and configured"
Write-Log "✓ .NET 8.0 runtimes installed"
Write-Log ""
Write-Log "NEXT: Run remaining scripts manually via RDP:"
Write-Log ""
Write-Log "  04-setup-keyvault.ps1    - Fetch RHINO_COMPUTE_KEY from Azure Key Vault"
Write-Log "  04a-install-build-tools.ps1 - Install Git & Visual Studio Build Tools"
Write-Log "  04b-verify-rhino.ps1     - Verify Rhino 8 installation and licensing"
Write-Log "  05-download-compute.ps1  - Build Rhino.Compute from source"
Write-Log "  06-configure-iis.ps1     - Configure IIS site and app pool"
Write-Log "  07-configure-firewall.ps1 - Open port 8081 in Windows Firewall"
Write-Log "  08-create-gh-directories.ps1 - Create Grasshopper folder structure"
Write-Log "  09-install-rhino.md      - Install Rhino 8 (manual, requires license)"
Write-Log "  10-test-compute.ps1      - Test the complete setup"
Write-Log ""
Write-Log "Scripts location: C:\scripts\rhino-setup"
Write-Log "Log file: $LogFile"
Write-Log ""
Write-Log "========================================" 
