# rhino3dm and Path Fixes Complete ✅

**Date:** November 13, 2025  
**Status:** Path escaping fixed, GHX file investigation required

---

## 🎉 Issues Resolved

### 1. rhino3dm Initialization ✅
**Problem:** `rhino3dm is not a function` error  
**Root Cause:** Incorrect API usage - tried to call `rhino.PolylineCurve.createFromPolyline()` (doesn't exist)  
**Solution:** Use constructor instead: `new rhino.PolylineCurve(polyline)`

**Files Changed:**
- `shared/appserver-node/src/bindings.ts` - Fixed `coordinatesToCurve()` function

### 2. Windows Path Escaping ✅
**Problem:** Path sent to Rhino.Compute had 4x backslashes: `C:\\\\\\\\compute\\\\\\\\sitefit...`  
**Root Cause:** Double escaping in both:
- Terragrunt config: `"C:\\\\compute"` (4 backslashes)
- TypeScript code: `${PATH}\\\\${def}` (adding 2 more)

**Solution:**
- Terragrunt: Changed to `"C:\\compute"` (2 backslashes in HCL string)
- TypeScript: Changed to `${PATH}\\${def}` (adding 1 backslash per segment)
- Result: Correct JSON path `"C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx"` (2x throughout)

**Files Changed:**
- `infra/live/dev/shared/appserver/terragrunt.hcl` - Line 62
- `shared/appserver-node/src/computeSolver.ts` - Line 20

### 3. Docker Build ✅
**Added:** WASM file validation in Dockerfile to ensure `rhino3dm.wasm` exists at build time

---

## 📊 Current Status

### ✅ Working Components
- rhino3dm WASM module initialization
- Polyline and PolylineCurve creation
- Network connectivity (ACA → Rhino VM)
- NSG rules (port 8081 accessible)
- Rhino.Compute service (responds to /version)
- Path construction (correct format)
- AppServer Revision: `kuduso-dev-appserver--0000008`

### ❌ Remaining Issue: GHX File

**Symptom:** Rhino.Compute returns 500 error when processing GHX file

**Log Evidence:**
```json
{
  "event": "compute.request",
  "url": "http://52.148.197.239:8081/grasshopper",
  "algo": "C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx",
  "input_params": ["parcel_polygon", "house_polygon", "rotation_spec", "grid_step", "seed"]
}
{
  "event": "compute.error",
  "status": 500,
  "error": ""
}
```

**Expected Input Parameters (from bindings.json):**
- `parcel_polygon` - Parcel boundary as closed polygon
- `house_polygon` - House footprint as closed polygon  
- `rotation_spec` - Rotation range specification (min, max, step)
- `grid_step` - Grid spacing for placement sampling
- `seed` - Random seed

**Expected Output Parameters:**
- `placed_transforms` - Array of placement transforms
- `placement_scores` - Quality scores for each placement
- `kpis` - Key performance indicators per placement

---

## 🔍 GHX File Investigation Needed

### Possible Causes

1. **File Doesn't Exist**
   - Path: `C:\compute\sitefit\1.0.0\ghlogic.ghx`
   - The file might not have been uploaded correctly to the VM
   - Or it might be named differently (e.g., `sitefit_ready.ghx` instead of `ghlogic.ghx`)

2. **Parameter Name Mismatch**
   - GHX file might have different parameter names than expected
   - Example: GHX has `parcel` but bindings expects `parcel_polygon`

3. **Missing Components/Plugins**
   - GHX file might use components not available in Rhino 8
   - Or requires plugins not listed in `plugins.json`

4. **File Corruption or Errors**
   - GHX file itself might have errors
   - Could be an invalid/broken Grasshopper definition

### Verification Steps

#### Step 1: Verify File Exists on VM
```powershell
# Via RDP or Azure Run Command
Test-Path 'C:\compute\sitefit\1.0.0\ghlogic.ghx'
Get-ChildItem 'C:\compute\sitefit\1.0.0\'
Get-Content 'C:\compute\sitefit\1.0.0\ghlogic.ghx' | Select-String -Pattern 'name=' | Select-First 10
```

#### Step 2: Check Parameter Names
Open `sitefit_ready.ghx` in a text editor or Grasshopper and verify:
- Input parameters match: `parcel_polygon`, `house_polygon`, `rotation_spec`, `grid_step`, `seed`
- Output parameters match: `placed_transforms`, `placement_scores`, `kpis`

#### Step 3: Test GHX Locally (if possible)
- Open in Grasshopper
- Check for errors or missing components
- Verify it runs with sample inputs

#### Step 4: Test Minimal GHX
Create a minimal test GHX file to verify Rhino.Compute works:
```grasshopper
Inputs: test_number (Number)
Logic: Multiply by 2
Outputs: result (Number)
```

---

## 📝 Files Modified

### Code Changes
```
✏️  shared/appserver-node/src/bindings.ts
    - Fixed coordinatesToCurve() to use constructor
    - Removed excessive debugging

✏️  shared/appserver-node/src/computeSolver.ts
    - Fixed buildDefinitionPath() to use single backslashes

✏️  shared/appserver-node/Dockerfile
    - Added WASM file validation
```

### Infrastructure Changes
```
✏️  infra/live/dev/shared/appserver/terragrunt.hcl
    - Fixed compute_definitions_path from "C:\\\\compute" to "C:\\compute"
    - Image: appserver-node:stage4-final
    - Revision: kuduso-dev-appserver--0000008
```

---

## 🧪 Testing Results

### Test 1: rhino3dm Initialization
```json
{"event": "rhino3dm.init_start", "type": "function", "is_function": true}
{"event": "rhino3dm.init_success"}
```
✅ **Result:** SUCCESS

### Test 2: Path Construction
```json
{"algo": "C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx"}
```
✅ **Result:** CORRECT (2x backslashes throughout)

### Test 3: Rhino.Compute Communication
```json
{"event": "compute.request", "url": "http://52.148.197.239:8081/grasshopper"}
{"event": "compute.error", "status": 500, "error": ""}
```
❌ **Result:** FAILED - GHX file issue

---

## 🎯 Next Actions

1. **Verify GHX File Location**
   - Confirm file exists at `C:\compute\sitefit\1.0.0\ghlogic.ghx`
   - If not, check if it was uploaded to a different location

2. **Check Parameter Names**
   - Open `sitefit_ready.ghx` and verify parameter names match bindings.json
   - Update either GHX or bindings.json to align

3. **Test GHX File**
   - Open in Grasshopper manually
   - Check for errors or warnings
   - Verify all components are available

4. **Create Minimal Test**
   - If issues persist, create a simple test GHX to verify Rhino.Compute works
   - Once confirmed working, debug the actual Sitefit GHX

---

## 💡 Key Learnings

### HCL String Escaping
In Terragrunt/Terraform HCL files, strings already handle one level of escaping:
- ❌ Wrong: `"C:\\\\compute"` (results in 4 backslashes in env var)
- ✅ Right: `"C:\\compute"` (results in 2 backslashes in env var)

### rhino3dm API
The library uses constructors, not static factory methods:
- ❌ Wrong: `rhino.PolylineCurve.createFromPolyline(polyline)`
- ✅ Right: `new rhino.PolylineCurve(polyline)`

### JSON Path Encoding
When sending Windows paths in JSON:
- Source string: `C:\compute\sitefit\1.0.0\ghlogic.ghx`
- JSON encoding: `"C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx"` (2x backslashes)
- In logs: `C:\\\\compute\\\\sitefit\\\\1.0.0\\\\ghlogic.ghx` (4x due to JSON stringification)

---

## 📚 Related Files

- **Source Code:** `shared/appserver-node/src/`
- **Contracts:** `contracts/sitefit/1.0.0/`
- **GHX File:** `contracts/sitefit/1.0.0/sitefit_ready.ghx` (source)
- **VM Location:** `C:\compute\sitefit\1.0.0\ghlogic.ghx` (deployed)
- **Infrastructure:** `infra/live/dev/shared/appserver/`

---

**Fixed by:** AI Assistant  
**Date:** November 13, 2025  
**Duration:** ~2 hours (diagnosis + fixes + deployment)

---

🎯 **Status:** Ready for GHX file investigation and resolution

