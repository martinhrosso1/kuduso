# SiteFit v1.1.0 - Debug Version Created ✅

## What Was Created

A **minimal debug version** of the SiteFit contract for infrastructure testing.

### Location
```
contracts/sitefit/1.1.0/
├── inputs.schema.json         # Single number input
├── outputs.schema.json        # Single number output  
├── bindings.json              # Simple JSONPath mapping
├── manifest.json              # Minimal limits
├── plugins.json               # No plugins required
├── ghlogic.ghx               # ⭐ Minimal GHX file
├── README.md                  # Documentation
├── CHANGELOG.md               # Version history
├── DEPLOY_TO_VM.md           # Deployment instructions
├── test-v1.1.0.sh            # ⭐ Test script
└── examples/
    ├── valid-minimal.json
    └── invalid-missing-value.json
```

## Contract Comparison

| Aspect | v1.0.0 (Production) | v1.1.0 (Debug) |
|--------|---------------------|----------------|
| **Purpose** | Production placement solver | Infrastructure testing |
| **Inputs** | 5 parameters | 1 number |
| **Outputs** | 3 arrays | 1 number |
| **GH Components** | 10+ | 3 |
| **Python Scripts** | Yes | No |
| **Geometry** | Yes (rhino3dm) | No |
| **Complexity** | High | Minimal |
| **Exec Time** | 1-4 minutes | <1 second |
| **Test Complexity** | Hard to verify | Easy (42 + 10 = 52) |

## v1.1.0 Contract

### Input
```json
{
  "value": 42
}
```

- Single number (0-1000)
- Required field
- Default: 42

### Output
```json
{
  "result": 52
}
```

- Single number
- Always equals `input + 10`

### Grasshopper Logic

```
[input_value] → [Addition: A+10] → [output_value]
```

1. **Input Parameter** - Receives number from API
2. **Addition Component** - Adds 10 to the input
3. **Output Parameter** - Returns result to API

**No Python. No Geometry. No Complex Logic.**

## Why This Version?

### Problem
v1.0.0 is too complex to debug infrastructure issues:
- Multiple input parameters (polygons, grids, seeds)
- Complex geometry processing (rhino3dm)
- Python script with arrays
- GeoJSON transformations
- 10+ Grasshopper components

**When it fails, we can't tell if it's:**
- Infrastructure (network, permissions, file paths)
- Business logic (Python script, geometry)
- Contract mismatch (bindings, schemas)

### Solution
v1.1.0 eliminates ALL business logic complexity:
- ✅ Single number in/out - trivial to verify
- ✅ No Python - eliminates script errors
- ✅ No geometry - eliminates rhino3dm issues
- ✅ Fast - completes in <1 second
- ✅ Predictable - always 42 + 10 = 52

## Testing Strategy

### Phase 1: Test v1.1.0 (Debug)

```bash
cd /home/martin/Desktop/kuduso/contracts/sitefit/1.1.0
./test-v1.1.0.sh
```

**If successful:**
- ✅ API is working
- ✅ Service Bus is working
- ✅ Worker is working
- ✅ AppServer is working
- ✅ Rhino.Compute is working
- ✅ GHX file loading is working
- ✅ Parameter passing is working
- ✅ Output mapping is working

**Infrastructure is good!** → Move to Phase 2

**If fails:**
- Check specific error in logs
- Fix infrastructure issue
- Retry Phase 1

### Phase 2: Debug v1.0.0 (Production)

Once v1.1.0 works, we know the infrastructure is solid. Then we can focus on v1.0.0 business logic:
- Open 1.0.0 GHX in Grasshopper on VM
- Test Python script manually
- Check geometry components
- Verify output structure
- Fix specific business logic issues

## Deployment Instructions

### 1. Deploy to Rhino VM

Follow instructions in `contracts/sitefit/1.1.0/DEPLOY_TO_VM.md`:

```bash
# Connect to VM with folder sharing
VM_IP=$(az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm --show-details --query "publicIps" -o tsv)
xfreerdp /v:$VM_IP /u:rhinoadmin \
  /dynamic-resolution /cert:ignore \
  /drive:local,/home/martin/Desktop/kuduso/contracts/sitefit/1.1.0 &
```

**In VM PowerShell:**
```powershell
New-Item -ItemType Directory -Path 'C:\compute\sitefit\1.1.0' -Force
Copy-Item '\\tsclient\local\ghlogic.ghx' -Destination 'C:\compute\sitefit\1.1.0\ghlogic.ghx'
Get-Item 'C:\compute\sitefit\1.1.0\ghlogic.ghx' | Format-List Length, LastWriteTime
iisreset
```

### 2. Run Test

```bash
cd /home/martin/Desktop/kuduso/contracts/sitefit/1.1.0
./test-v1.1.0.sh
```

Expected output:
```json
{
  "result": 52
}
```

### 3. Interpret Results

**✅ If result = 52:**
- Infrastructure is perfect
- Rhino.Compute is working
- GHX file loading works
- Move to debugging v1.0.0

**❌ If fails:**
- Check AppServer logs for error
- Check Rhino.Compute logs
- Verify GHX file on VM
- Fix infrastructure issue

## Manual Test

```bash
# Submit job
curl -X POST "https://kuduso-dev-sitefit-api.blackwave-77d88b66.westeurope.azurecontainerapps.io/jobs/run" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "sitefit",
    "definition": "sitefit",
    "version": "1.1.0",
    "inputs": {"value": 42}
  }'

# Get job ID from response
# Wait 10 seconds

# Check status
curl "https://kuduso-dev-sitefit-api.../jobs/status/{job_id}"

# Get result (should be 52)
curl "https://kuduso-dev-sitefit-api.../jobs/result/{job_id}"
```

## Architecture Verification

v1.1.0 tests the ENTIRE pipeline:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Browser   │────▶│     API     │────▶│ Service Bus │
│  (curl)     │     │  (FastAPI)  │     │  (Azure)    │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │   Worker    │
                                        │ (FastAPI)   │
                                        └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  AppServer  │
                                        │  (Node.js)  │
                                        └─────────────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │   Rhino     │
                                        │  Compute    │
                                        │  + GHX      │
                                        └─────────────┘
```

Every component is exercised with v1.1.0!

## Next Steps

1. ✅ **Created** - v1.1.0 debug version
2. 🔄 **Deploy** - Upload GHX to Rhino VM
3. 🔄 **Test** - Run test-v1.1.0.sh
4. 🔄 **Verify** - Result should be 52
5. 🔄 **Debug v1.0.0** - Once infrastructure works

## Files Summary

- **Total files created:** 13
- **Contract files:** 6 (schemas, bindings, manifest, plugins)
- **GHX file:** 1 (minimal Grasshopper definition)
- **Documentation:** 3 (README, CHANGELOG, DEPLOY)
- **Examples:** 2 (valid, invalid)
- **Test script:** 1 (automated test)

**Ready to test!** 🚀

