#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap script for Rhino.Compute on Azure Windows VM
    
.DESCRIPTION
    Automates installation and configuration of Rhino.Compute including:
    - IIS + required features
    - .NET Desktop Runtime & ASP.NET Core Hosting Bundle
    - Rhino.Compute server under IIS
    - Key Vault integration for API key (via Managed Identity)
    - Windows Firewall rules
    - Application warm-up configuration
    - GH definition directory structure
    
.NOTES
    This script does NOT install Rhino 8 - that requires manual installation and licensing.
    After this script completes, you must:
    1. RDP to VM
    2. Install Rhino 8
    3. Activate Cloud Zoo license
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName = "kuduso-dev-kv-93d2ab",
    
    [Parameter(Mandatory = $false)]
    [string]$ComputeKeySecretName = "RHINO-COMPUTE-KEY",
    
    [Parameter(Mandatory = $false)]
    [int]$IISPort = 8081,
    
    [Parameter(Mandatory = $false)]
    [string]$ComputeVersion = "8.0",
    
    [Parameter(Mandatory = $false)]
    [string]$LogFile = "C:\rhino-bootstrap.log"
)

# ===========================================
# Logging Function
# ===========================================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# ===========================================
# Error Handler
# ===========================================
$ErrorActionPreference = "Stop"
trap {
    Write-Log "ERROR: $_" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}

# ===========================================
# Start Bootstrap
# ===========================================
Write-Log "========================================" "INFO"
Write-Log "Rhino.Compute Bootstrap Script Starting" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Key Vault: $KeyVaultName"
Write-Log "IIS Port: $IISPort"
Write-Log "Compute Version: $ComputeVersion"

# ===========================================
# 1. Install Chocolatey (Package Manager)
# ===========================================
Write-Log "[1/12] Installing Chocolatey..." "INFO"

if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Chocolatey package manager..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    
    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Log "Chocolatey installed successfully"
    }
    catch {
        Write-Log "Failed to install Chocolatey: $_" "ERROR"
        throw
    }
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}
else {
    Write-Log "Chocolatey already installed"
}

# ===========================================
# 2. Install IIS + Required Features
# ===========================================
Write-Log "[2/12] Installing IIS and required features..." "INFO"

try {
    $features = @(
        "Web-Server",
        "Web-WebServer",
        "Web-Common-Http",
        "Web-Default-Doc",
        "Web-Dir-Browsing",
        "Web-Http-Errors",
        "Web-Static-Content",
        "Web-Http-Redirect",
        "Web-Health",
        "Web-Http-Logging",
        "Web-Performance",
        "Web-Stat-Compression",
        "Web-Dyn-Compression",
        "Web-Security",
        "Web-Filtering",
        "Web-App-Dev",
        "Web-Net-Ext45",
        "Web-Asp-Net45",
        "Web-ISAPI-Ext",
        "Web-ISAPI-Filter",
        "Web-Mgmt-Tools",
        "Web-Mgmt-Console",
        "Web-AppInit"  # Application Initialization for warm-up
    )
    
    Install-WindowsFeature -Name $features -IncludeManagementTools
    Write-Log "IIS features installed successfully"
}
catch {
    Write-Log "Failed to install IIS: $_" "ERROR"
    throw
}

# ===========================================
# 3. Install .NET Runtimes
# ===========================================
Write-Log "[3/12] Installing .NET runtimes..." "INFO"

try {
    # Install .NET 8.0 SDK, Desktop Runtime, and ASP.NET Core Runtime
    choco install dotnet-8.0-sdk -y --no-progress
    choco install dotnet-8.0-runtime -y --no-progress
    choco install dotnet-8.0-desktopruntime -y --no-progress
    choco install dotnet-aspnethosting-bundle -y --no-progress
    
    Write-Log ".NET runtimes installed successfully"
}
catch {
    Write-Log "Failed to install .NET runtimes: $_" "WARNING"
    # Continue anyway - might already be installed
}

# ===========================================
# 4. Get RHINO_COMPUTE_KEY from Key Vault
# ===========================================
Write-Log "[4/12] Fetching RHINO_COMPUTE_KEY from Key Vault..." "INFO"

try {
    Write-Log "Getting Managed Identity access token..."
    
    $tokenResponse = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' `
        -Method GET `
        -Headers @{Metadata = "true" } `
        -UseBasicParsing
    
    $token = $tokenResponse.access_token
    Write-Log "Access token obtained"
    
    # Get secret from Key Vault
    $secretUri = "https://$KeyVaultName.vault.azure.net/secrets/$ComputeKeySecretName?api-version=7.4"
    Write-Log "Fetching secret from: $secretUri"
    
    $headers = @{
        'Authorization' = "Bearer $token"
    }
    
    $secretResponse = Invoke-RestMethod -Uri $secretUri -Headers $headers -Method GET -UseBasicParsing
    $computeKey = $secretResponse.value
    
    Write-Log "RHINO_COMPUTE_KEY retrieved successfully"
    
    # Set as system environment variable
    [System.Environment]::SetEnvironmentVariable('RHINO_COMPUTE_KEY', $computeKey, 'Machine')
    $env:RHINO_COMPUTE_KEY = $computeKey
    
    Write-Log "RHINO_COMPUTE_KEY set as system environment variable"
}
catch {
    Write-Log "Failed to get API key from Key Vault: $_" "ERROR"
    Write-Log "You will need to set RHINO_COMPUTE_KEY manually" "WARNING"
    # Don't fail - continue with setup
}

# ===========================================
# 5. Download Rhino.Compute Binaries
# ===========================================
Write-Log "[5/12] Downloading Rhino.Compute..." "INFO"

$computePath = "C:\inetpub\compute"
New-Item -ItemType Directory -Path $computePath -Force | Out-Null

try {
    # Download latest Rhino.Compute release
    $computeZipUrl = "https://github.com/mcneel/compute.rhino3d/releases/latest/download/rhino.compute.zip"
    $computeZip = "$env:TEMP\rhino.compute.zip"
    
    Write-Log "Downloading from: $computeZipUrl"
    
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    Invoke-WebRequest -Uri $computeZipUrl -OutFile $computeZip -UseBasicParsing
    Write-Log "Download complete"
    
    # Extract
    Write-Log "Extracting to: $computePath"
    Expand-Archive -Path $computeZip -DestinationPath $computePath -Force
    
    Write-Log "Rhino.Compute extracted successfully"
    
    # Verify
    if (Test-Path "$computePath\compute.geometry.exe") {
        Write-Log "Verified: compute.geometry.exe found"
    }
    else {
        Write-Log "WARNING: compute.geometry.exe not found at expected location" "WARNING"
    }
}
catch {
    Write-Log "Failed to download Rhino.Compute: $_" "ERROR"
    throw
}

# Create logs directory
New-Item -ItemType Directory -Path "$computePath\logs" -Force | Out-Null

# ===========================================
# 6. Create IIS Application Pool
# ===========================================
Write-Log "[6/12] Creating IIS Application Pool..." "INFO"

try {
    Import-Module WebAdministration
    
    $appPoolName = "RhinoComputePool"
    
    # Remove if exists
    if (Test-Path "IIS:\AppPools\$appPoolName") {
        Write-Log "Removing existing app pool..."
        Remove-WebAppPool -Name $appPoolName
    }
    
    # Create new app pool
    Write-Log "Creating app pool: $appPoolName"
    New-WebAppPool -Name $appPoolName
    
    # Configure app pool
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "managedRuntimeVersion" -Value ""
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "startMode" -Value "AlwaysRunning"
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "autoStart" -Value $true
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "processModel.idleTimeout" -Value ([TimeSpan]::FromMinutes(0))
    
    Write-Log "App pool configured successfully"
}
catch {
    Write-Log "Failed to create app pool: $_" "ERROR"
    throw
}

# ===========================================
# 7. Create IIS Website
# ===========================================
Write-Log "[7/12] Creating IIS Website..." "INFO"

try {
    $siteName = "RhinoCompute"
    
    # Remove if exists
    if (Test-Path "IIS:\Sites\$siteName") {
        Write-Log "Removing existing website..."
        Remove-Website -Name $siteName
    }
    
    # Create website
    Write-Log "Creating website: $siteName on port $IISPort"
    New-WebSite -Name $siteName `
        -Port $IISPort `
        -PhysicalPath $computePath `
        -ApplicationPool $appPoolName `
        -Force
    
    # Configure binding
    New-WebBinding -Name $siteName -Protocol http -Port $IISPort -IPAddress "*" -ErrorAction SilentlyContinue
    
    Write-Log "Website created successfully"
}
catch {
    Write-Log "Failed to create website: $_" "ERROR"
    throw
}

# ===========================================
# 8. Generate web.config
# ===========================================
Write-Log "[8/12] Generating web.config..." "INFO"

$webConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath=".\compute.geometry.exe" 
                  arguments="" 
                  stdoutLogEnabled="true" 
                  stdoutLogFile=".\logs\stdout" 
                  hostingModel="OutOfProcess"
                  requestTimeout="00:20:00">
        <environmentVariables>
          <environmentVariable name="RHINO_COMPUTE_KEY" value="%RHINO_COMPUTE_KEY%" />
          <environmentVariable name="ASPNETCORE_ENVIRONMENT" value="Production" />
          <environmentVariable name="ASPNETCORE_URLS" value="http://localhost:$IISPort" />
        </environmentVariables>
      </aspNetCore>
      <httpProtocol>
        <customHeaders>
          <add name="X-Powered-By" value="Rhino.Compute" />
        </customHeaders>
      </httpProtocol>
    </system.webServer>
  </location>
</configuration>
"@

try {
    $webConfig | Out-File -FilePath "$computePath\web.config" -Encoding UTF8 -Force
    Write-Log "web.config created successfully"
}
catch {
    Write-Log "Failed to create web.config: $_" "ERROR"
    throw
}

# ===========================================
# 9. Enable Application Initialization (Warm-up)
# ===========================================
Write-Log "[9/12] Enabling Application Initialization..." "INFO"

try {
    $siteName = "RhinoCompute"
    
    # Enable preload on app pool
    Set-ItemProperty "IIS:\AppPools\RhinoComputePool" -Name "autoStart" -Value $true
    
    # Enable preload on site
    Set-ItemProperty "IIS:\Sites\$siteName" -Name "applicationDefaults.preloadEnabled" -Value $true
    
    # Configure application initialization
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config "$siteName" `
        /section:applicationInitialization `
        /remapManagedRequestsTo:"" `
        /skipManagedModules:true `
        /doAppInitAfterRestart:true `
        /commit:apphost
    
    # Add warm-up page
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config "$siteName" `
        /section:applicationInitialization `
        /+"[hostName='',initPage='/version']" `
        /commit:apphost
    
    Write-Log "Application warm-up configured"
}
catch {
    Write-Log "Failed to configure warm-up: $_" "WARNING"
    # Continue anyway
}

# ===========================================
# 10. Configure Windows Firewall
# ===========================================
Write-Log "[10/12] Configuring Windows Firewall..." "INFO"

try {
    # Remove existing rule if present
    Remove-NetFirewallRule -DisplayName "Rhino.Compute HTTP" -ErrorAction SilentlyContinue
    
    # Create new rule
    New-NetFirewallRule -DisplayName "Rhino.Compute HTTP" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $IISPort `
        -Action Allow `
        -Profile Any `
        -Description "Allow inbound traffic to Rhino.Compute server"
    
    Write-Log "Firewall rule created for port $IISPort"
}
catch {
    Write-Log "Failed to configure firewall: $_" "WARNING"
    # Continue anyway
}

# ===========================================
# 11. Create Grasshopper Definition Directories
# ===========================================
Write-Log "[11/12] Creating Grasshopper definition directories..." "INFO"

try {
    $ghDirs = @(
        "C:\compute\sitefit\1.0.0"
    )
    
    foreach ($dir in $ghDirs) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Log "Created: $dir"
    }
    
    # Create README
    $readme = @"
# Grasshopper Definitions Directory

This directory contains versioned Grasshopper definitions for Rhino.Compute.

## Structure
C:\compute\
└── sitefit\
    └── 1.0.0\
        ├── sitefit.ghx        (main definition)
        ├── inputs.json        (sample test inputs)
        └── README.md          (this file)

## Usage
Place your .ghx files here and reference them in AppServer:
  algo: "C:\\compute\\sitefit\\1.0.0\\sitefit.ghx"

## Contract
Definitions must match the contract in:
  /kuduso/contracts/sitefit/1.0.0/
  - inputs.schema.json
  - outputs.schema.json
  - bindings.json

## Testing
Test locally:
  curl -X POST http://localhost:$IISPort/grasshopper \
    -H "RhinoComputeKey: <KEY>" \
    -H "Content-Type: application/json" \
    -d @inputs.json
"@
    
    $readme | Out-File -FilePath "C:\compute\sitefit\1.0.0\README.md" -Encoding UTF8
    Write-Log "Created README in GH directory"
}
catch {
    Write-Log "Failed to create GH directories: $_" "WARNING"
}

# ===========================================
# 12. Restart IIS
# ===========================================
Write-Log "[12/12] Restarting IIS..." "INFO"

try {
    iisreset
    Start-Sleep -Seconds 5
    Write-Log "IIS restarted successfully"
}
catch {
    Write-Log "Failed to restart IIS: $_" "WARNING"
}

# ===========================================
# Verification
# ===========================================
Write-Log "========================================" "INFO"
Write-Log "Bootstrap Complete - Verifying Setup" "INFO"
Write-Log "========================================" "INFO"

$checks = @{
    "Chocolatey Installed"                = (Get-Command choco -ErrorAction SilentlyContinue) -ne $null
    "IIS Installed"                       = (Get-Service W3SVC -ErrorAction SilentlyContinue) -ne $null
    "Compute Files Exist"                 = Test-Path "$computePath\compute.geometry.exe"
    "web.config Exists"                   = Test-Path "$computePath\web.config"
    "App Pool Exists"                     = Test-Path "IIS:\AppPools\RhinoComputePool"
    "Website Exists"                      = Test-Path "IIS:\Sites\RhinoCompute"
    "RHINO_COMPUTE_KEY Set"               = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine') -ne $null
    "Firewall Rule Exists"                = (Get-NetFirewallRule -DisplayName "Rhino.Compute HTTP" -ErrorAction SilentlyContinue) -ne $null
    "GH Directory Exists"                 = Test-Path "C:\compute\sitefit\1.0.0"
}

$allPassed = $true
foreach ($check in $checks.GetEnumerator()) {
    $status = if ($check.Value) { "✓ PASS" } else { "✗ FAIL"; $allPassed = $false }
    Write-Log "$($check.Key): $status"
}

# ===========================================
# Summary & Next Steps
# ===========================================
Write-Log ""
Write-Log "========================================" "INFO"
Write-Log "  BOOTSTRAP SUMMARY" "INFO"
Write-Log "========================================" "INFO"

if ($allPassed) {
    Write-Log "✓ All automated steps completed successfully!" "INFO"
}
else {
    Write-Log "⚠ Some checks failed - review log above" "WARNING"
}

Write-Log ""
Write-Log "IMPORTANT: Manual steps still required:" "INFO"
Write-Log "1. Install Rhino 8 for Windows" "INFO"
Write-Log "   Download: https://www.rhino3d.com/download/" "INFO"
Write-Log ""
Write-Log "2. Activate Rhino License (Cloud Zoo)" "INFO"
Write-Log "   - Launch Rhino 8" "INFO"
Write-Log "   - Choose Cloud Zoo when prompted" "INFO"
Write-Log "   - Sign in with McNeel account" "INFO"
Write-Log ""
Write-Log "3. Place Grasshopper definitions" "INFO"
Write-Log "   Location: C:\compute\sitefit\1.0.0\sitefit.ghx" "INFO"
Write-Log ""
Write-Log "4. Test Compute server" "INFO"
Write-Log "   Health: curl http://localhost:$IISPort/version" "INFO"
Write-Log ""
Write-Log "Compute URL: http://localhost:$IISPort/" "INFO"
Write-Log "Logs: $LogFile" "INFO"
Write-Log "IIS Logs: $computePath\logs\" "INFO"
Write-Log ""
Write-Log "========================================" "INFO"
Write-Log "Bootstrap script completed!" "INFO"
Write-Log "========================================" "INFO"

exit 0
