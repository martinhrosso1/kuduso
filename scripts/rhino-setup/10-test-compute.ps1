#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 10: Test Rhino.Compute server is working correctly
#>

param(
    [string]$ComputeUrl = "http://localhost:8081",
    [switch]$SkipRhinoCheck = $false
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 10: Test Rhino.Compute" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Compute URL: $ComputeUrl" -ForegroundColor Yellow
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Check Rhino is installed (unless skipped)
if (!$SkipRhinoCheck) {
    Write-Host "[TEST 1] Checking Rhino 8 installation..." -ForegroundColor Cyan
    
    if (Test-Path "C:\Program Files\Rhino 8\System\Rhino.exe") {
        Write-Host "  ✓ PASS: Rhino 8 installed" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  ✗ FAIL: Rhino 8 not found" -ForegroundColor Red
        Write-Host "    Install Rhino 8 before proceeding (see 09-install-rhino.md)" -ForegroundColor Yellow
        $testsFailed++
    }
}

# Test 2: Check API key is set
Write-Host "[TEST 2] Checking RHINO_COMPUTE_KEY..." -ForegroundColor Cyan

$apiKey = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
if ($apiKey) {
    Write-Host "  ✓ PASS: API key is set ($($apiKey.Length) characters)" -ForegroundColor Green
    $testsPassed++
}
else {
    Write-Host "  ✗ FAIL: RHINO_COMPUTE_KEY not set" -ForegroundColor Red
    Write-Host "    Run: 04-setup-keyvault.ps1" -ForegroundColor Yellow
    $testsFailed++
    $apiKey = Read-Host "  Enter API key manually for testing (or press Enter to skip auth tests)"
}

# Test 3: Check IIS site is running
Write-Host "[TEST 3] Checking IIS site status..." -ForegroundColor Cyan

try {
    Import-Module WebAdministration
    $site = Get-Website -Name "RhinoCompute" -ErrorAction Stop
    
    if ($site.State -eq "Started") {
        Write-Host "  ✓ PASS: IIS site is running" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "  ✗ FAIL: IIS site exists but not started (State: $($site.State))" -ForegroundColor Red
        Write-Host "    Starting site..." -ForegroundColor Yellow
        Start-Website -Name "RhinoCompute"
        Start-Sleep -Seconds 3
        $testsFailed++
    }
}
catch {
    Write-Host "  ✗ FAIL: IIS site not found" -ForegroundColor Red
    Write-Host "    Run: 06-configure-iis.ps1" -ForegroundColor Yellow
    $testsFailed++
}

# Test 4: Health endpoint (no auth required)
Write-Host "[TEST 4] Testing /version endpoint (no auth)..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "$ComputeUrl/version" -Method GET -UseBasicParsing -TimeoutSec 10
    
    if ($response) {
        Write-Host "  ✓ PASS: Health endpoint responding" -ForegroundColor Green
        Write-Host "    Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
        $testsPassed++
    }
}
catch {
    Write-Host "  ✗ FAIL: Health endpoint not responding" -ForegroundColor Red
    Write-Host "    Error: $_" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Troubleshooting:" -ForegroundColor Yellow
    Write-Host "    1. Check IIS site is running: Get-Website -Name RhinoCompute"
    Write-Host "    2. Check port 8081: netstat -ano | findstr :8081"
    Write-Host "    3. Review IIS logs: C:\inetpub\compute\logs\"
    Write-Host "    4. Restart IIS: iisreset"
    $testsFailed++
}

# Test 5: Authenticated endpoint
if ($apiKey) {
    Write-Host "[TEST 5] Testing authenticated endpoint..." -ForegroundColor Cyan
    
    try {
        $headers = @{
            "RhinoComputeKey" = $apiKey
            "Content-Type"    = "application/json"
        }
        
        $body = @{
            x = 10
            y = 20
            z = 30
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$ComputeUrl/rhino/geometry/point" `
            -Method POST `
            -Headers $headers `
            -Body $body `
            -UseBasicParsing `
            -TimeoutSec 10
        
        if ($response) {
            Write-Host "  ✓ PASS: Authenticated request successful" -ForegroundColor Green
            Write-Host "    Response: $($response | ConvertTo-Json -Compress -Depth 2)" -ForegroundColor Gray
            $testsPassed++
        }
    }
    catch {
        Write-Host "  ✗ FAIL: Authenticated request failed" -ForegroundColor Red
        
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            Write-Host "    Error: 401 Unauthorized - API key mismatch" -ForegroundColor Gray
            Write-Host "    Verify RHINO_COMPUTE_KEY matches the key in Key Vault" -ForegroundColor Yellow
        }
        else {
            Write-Host "    Error: $_" -ForegroundColor Gray
        }
        
        $testsFailed++
    }
}
else {
    Write-Host "[TEST 5] Skipping authenticated test (no API key)" -ForegroundColor Yellow
}

# Test 6: External accessibility (from public IP)
Write-Host "[TEST 6] Testing external accessibility..." -ForegroundColor Cyan

try {
    $publicIp = (Invoke-RestMethod -Uri "http://ifconfig.me/ip" -TimeoutSec 5).Trim()
    $externalUrl = "http://${publicIp}:8081/version"
    
    Write-Host "  Testing: $externalUrl" -ForegroundColor Gray
    
    $response = Invoke-RestMethod -Uri $externalUrl -Method GET -UseBasicParsing -TimeoutSec 10
    
    if ($response) {
        Write-Host "  ✓ PASS: Accessible from external IP" -ForegroundColor Green
        $testsPassed++
    }
}
catch {
    Write-Host "  ⚠ WARNING: Not accessible from public IP" -ForegroundColor Yellow
    Write-Host "    This is expected if NSG restricts access to specific IPs" -ForegroundColor Gray
    Write-Host "    Test from your local machine instead" -ForegroundColor Gray
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor Red
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "✓ All tests passed! Rhino.Compute is working correctly." -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "1. Place your Grasshopper definition in: C:\compute\sitefit\1.0.0\sitefit.ghx" -ForegroundColor Yellow
    Write-Host "2. Test from your local machine (see STAGE4_RHINO_SETUP_INFO.md)" -ForegroundColor Yellow
    Write-Host "3. Update AppServer to use Compute URL" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Step 10: COMPLETE - Setup finished!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "✗ Some tests failed. Fix issues before proceeding." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor Yellow
    Write-Host "- Restart IIS: iisreset" -ForegroundColor Gray
    Write-Host "- Check IIS logs: C:\inetpub\compute\logs\stdout*.log" -ForegroundColor Gray
    Write-Host "- Verify Rhino is installed and licensed" -ForegroundColor Gray
    Write-Host "- Check firewall: Get-NetFirewallRule -DisplayName 'Rhino.Compute*'" -ForegroundColor Gray
    exit 1
}
