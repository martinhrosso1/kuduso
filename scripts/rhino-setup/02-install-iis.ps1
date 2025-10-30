#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 2: Install IIS and required features
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 2: Install IIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if already installed
$iis = Get-Service W3SVC -ErrorAction SilentlyContinue
if ($iis) {
    Write-Host "✓ IIS already installed - Status: $($iis.Status)" -ForegroundColor Green
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "✓ WebAdministration module loaded" -ForegroundColor Green
    Write-Host ""
    Write-Host "Step 2: COMPLETE - Continue to 03-install-dotnet.ps1" -ForegroundColor Green
    exit 0
}

Write-Host "Installing IIS and required features..." -ForegroundColor Yellow
Write-Host "This may take 5-10 minutes..." -ForegroundColor Yellow
Write-Host ""

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
    
    Write-Host ""
    Write-Host "✓ IIS features installed successfully" -ForegroundColor Green
    
    # Verify
    Import-Module WebAdministration
    Write-Host "✓ WebAdministration module loaded" -ForegroundColor Green
    
    # Show current websites
    Write-Host ""
    Write-Host "Current IIS Sites:" -ForegroundColor Cyan
    Get-Website | Format-Table Name, State, PhysicalPath -AutoSize
    
    Write-Host ""
    Write-Host "Step 2: COMPLETE - Continue to 03-install-dotnet.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to install IIS: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're running PowerShell as Administrator"
    Write-Host "2. Check Windows Update is not blocking installations"
    Write-Host "3. Restart VM and try again"
    exit 1
}
