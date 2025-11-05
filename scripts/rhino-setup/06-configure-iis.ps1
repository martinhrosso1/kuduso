#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 6: Configure IIS site and app pool for Rhino.Compute
#>

param(
    [string]$SiteName = "RhinoCompute",
    [string]$AppPoolName = "RhinoComputePool",
    [int]$Port = 8081,
    [string]$PhysicalPath = "C:\inetpub\compute"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 6: Configure IIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Site Name: $SiteName" -ForegroundColor Yellow
Write-Host "Port: $Port" -ForegroundColor Yellow
Write-Host ""

# Verify prerequisites
if (!(Get-Service W3SVC -ErrorAction SilentlyContinue)) {
    Write-Host "✗ IIS not installed. Run 02-install-iis.ps1 first" -ForegroundColor Red
    throw "IIS not installed - run script 02 first"
}

if (!(Test-Path "$PhysicalPath\compute.geometry.exe")) {
    Write-Host "✗ Rhino.Compute not found. Run 05-download-compute.ps1 first" -ForegroundColor Red
    throw "Rhino.Compute not found - run script 05 first"
}

Import-Module WebAdministration

try {
    # Create App Pool
    Write-Host "[1/5] Creating application pool: $AppPoolName" -ForegroundColor Yellow
    
    if (Test-Path "IIS:\AppPools\$AppPoolName") {
        Write-Host "  App pool exists, removing..." -ForegroundColor Gray
        Remove-WebAppPool -Name $AppPoolName
    }
    
    New-WebAppPool -Name $AppPoolName
    
    # Configure app pool for .NET Core (no managed runtime)
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value ""
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "startMode" -Value "AlwaysRunning"
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "autoStart" -Value $true
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "processModel.idleTimeout" -Value ([TimeSpan]::FromMinutes(0))
    
    Write-Host "✓ App pool created and configured" -ForegroundColor Green
    
    # Create Website
    Write-Host "[2/5] Creating website: $SiteName" -ForegroundColor Yellow
    
    if (Test-Path "IIS:\Sites\$SiteName") {
        Write-Host "  Website exists, removing..." -ForegroundColor Gray
        Remove-Website -Name $SiteName
    }
    
    New-WebSite -Name $SiteName `
        -Port $Port `
        -PhysicalPath $PhysicalPath `
        -ApplicationPool $AppPoolName `
        -Force
    
    Write-Host "✓ Website created" -ForegroundColor Green
    
    # Create web.config
    Write-Host "[3/5] Generating web.config..." -ForegroundColor Yellow
    
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
        </environmentVariables>
      </aspNetCore>
    </system.webServer>
  </location>
</configuration>
"@
    
    $webConfig | Out-File -FilePath "$PhysicalPath\web.config" -Encoding UTF8 -Force
    Write-Host "✓ web.config created" -ForegroundColor Green
    
    # Enable warm-up
    Write-Host "[4/5] Enabling application warm-up..." -ForegroundColor Yellow
    
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name "applicationDefaults.preloadEnabled" -Value $true
    
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config "$SiteName" `
        /section:applicationInitialization `
        /remapManagedRequestsTo:"" `
        /skipManagedModules:true `
        /doAppInitAfterRestart:true `
        /commit:apphost | Out-Null
    
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config "$SiteName" `
        /section:applicationInitialization `
        /+"[hostName='',initPage='/version']" `
        /commit:apphost | Out-Null
    
    Write-Host "✓ Warm-up configured (/version will be called on startup)" -ForegroundColor Green
    
    # Restart IIS
    Write-Host "[5/5] Restarting IIS..." -ForegroundColor Yellow
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 5
    Write-Host "✓ IIS restarted" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "✓ IIS configuration complete" -ForegroundColor Green
    Write-Host ""
    Write-Host "Website details:" -ForegroundColor Cyan
    Get-Website -Name $SiteName | Format-List Name, State, PhysicalPath, Bindings
    
    Write-Host ""
    Write-Host "Step 6: COMPLETE - Continue to 07-configure-firewall.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to configure IIS: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure IIS is running: Get-Service W3SVC"
    Write-Host "2. Check if port $Port is already in use: netstat -ano | findstr :$Port"
    Write-Host "3. Review IIS logs in: C:\inetpub\logs\"
    throw "Script failed - see error above"
}
