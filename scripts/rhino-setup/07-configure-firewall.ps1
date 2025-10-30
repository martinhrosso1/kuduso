#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 7: Configure Windows Firewall to allow inbound traffic on Rhino.Compute port
#>

param(
    [int]$Port = 8081
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 7: Configure Firewall" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Port: $Port" -ForegroundColor Yellow
Write-Host ""

try {
    # Check if rule already exists
    $existingRule = Get-NetFirewallRule -DisplayName "Rhino.Compute HTTP" -ErrorAction SilentlyContinue
    
    if ($existingRule) {
        Write-Host "Firewall rule exists, removing old rule..." -ForegroundColor Yellow
        Remove-NetFirewallRule -DisplayName "Rhino.Compute HTTP"
    }
    
    # Create new firewall rule
    Write-Host "Creating firewall rule for port $Port..." -ForegroundColor Yellow
    
    New-NetFirewallRule -DisplayName "Rhino.Compute HTTP" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Any `
        -Description "Allow inbound traffic to Rhino.Compute server on port $Port"
    
    Write-Host "✓ Firewall rule created" -ForegroundColor Green
    
    # Verify
    Write-Host ""
    Write-Host "Firewall rule details:" -ForegroundColor Cyan
    Get-NetFirewallRule -DisplayName "Rhino.Compute HTTP" | Format-List DisplayName, Enabled, Direction, Action
    
    Write-Host ""
    Write-Host "Step 7: COMPLETE - Continue to 08-create-gh-directories.ps1" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to configure firewall: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual configuration:" -ForegroundColor Yellow
    Write-Host "1. Open Windows Firewall with Advanced Security"
    Write-Host "2. Create new Inbound Rule"
    Write-Host "3. Port: TCP $Port"
    Write-Host "4. Action: Allow"
    exit 1
}
