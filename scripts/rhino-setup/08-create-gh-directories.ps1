#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Step 8: Create directory structure for Grasshopper definitions
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Step 8: Create GH Directories" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

try {
    # Create directory structure
    $ghDir = "C:\compute\sitefit\1.0.0"
    
    Write-Host "Creating directory: $ghDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ghDir -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
    
    # Create README
    $readme = @"
# Grasshopper Definitions for Rhino.Compute

## Directory Structure
C:\compute\
└── sitefit\
    └── 1.0.0\
        ├── sitefit.ghx        (main Grasshopper definition)
        ├── inputs.json        (sample test inputs)
        └── README.md          (this file)

## Usage

Place your Grasshopper definition file here: C:\compute\sitefit\1.0.0\sitefit.ghx

The definition will be referenced in API calls:
```json
{
  "algo": "C:\\compute\\sitefit\\1.0.0\\sitefit.ghx",
  "pointer": true,
  "values": [...]
}
```

## Contract

Your Grasshopper definition must match the contract defined in:
- inputs.schema.json
- outputs.schema.json  
- bindings.json

Contract location: /kuduso/contracts/sitefit/1.0.0/

## Testing

Test the definition locally:
```powershell
`$apiKey = [System.Environment]::GetEnvironmentVariable('RHINO_COMPUTE_KEY', 'Machine')
curl -Method POST http://localhost:8081/grasshopper \
  -Headers @{"RhinoComputeKey"=`$apiKey; "Content-Type"="application/json"} \
  -Body (Get-Content inputs.json -Raw)
```

## Notes

- Grasshopper must run headless (no UI components)
- Use deterministic logic (avoid randomness unless seeded)
- Keep parameter names exactly as specified in bindings.json
- Test locally before deploying
"@
    
    $readme | Out-File -FilePath "$ghDir\README.md" -Encoding UTF8
    Write-Host "✓ README.md created" -ForegroundColor Green
    
    # Create sample inputs.json
    $sampleInputs = @"
{
  "algo": "C:\\compute\\sitefit\\1.0.0\\sitefit.ghx",
  "pointer": true,
  "values": [
    {
      "ParamName": "parcel_polygon",
      "InnerTree": {
        "0": [
          {
            "type": "Curve",
            "data": "... curve data ..."
          }
        ]
      }
    }
  ]
}
"@
    
    $sampleInputs | Out-File -FilePath "$ghDir\inputs.json" -Encoding UTF8
    Write-Host "✓ inputs.json template created" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "✓ Grasshopper directory structure created" -ForegroundColor Green
    Write-Host ""
    Write-Host "Directory contents:" -ForegroundColor Cyan
    Get-ChildItem $ghDir | Format-Table Name, Length, LastWriteTime -AutoSize
    
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Install Rhino 8 (manual step - see 09-install-rhino.md)" -ForegroundColor Yellow
    Write-Host "2. Place your .ghx file in: $ghDir" -ForegroundColor Yellow
    Write-Host "3. Test Compute server (run 10-test-compute.ps1)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Step 8: COMPLETE" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Failed to create directories: $_" -ForegroundColor Red
    exit 1
}
