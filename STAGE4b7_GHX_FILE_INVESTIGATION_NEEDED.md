# GHX File Investigation Required

**Date:** November 13, 2025  
**Status:** Clear evidence of GHX file issue - needs manual verification

---

## 🔍 Evidence Collected

### From Enhanced Logging

**HTTP Response from Rhino.Compute:**
```json
{
  "status": 500,
  "statusText": "Server Error",
  "contentType": null,
  "errorBody": "",
  "errorLength": 0,
  "hasContent": false
}
```

**Request Details:**
```json
{
  "algo": "C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx",
  "input_count": 5,
  "input_params": [
    {"param": "parcel_polygon", "path_count": 1},
    {"param": "house_polygon", "path_count": 1},
    {"param": "rotation_spec", "path_count": 1},
    {"param": "grid_step", "path_count": 1},
    {"param": "seed", "path_count": 1}
  ]
}
```

**Response Time:** 8-42ms (instant failure)

---

## 🎯 Key Observations

### ✅ What's Working
1. **Network connectivity** - Request reaches Rhino.Compute
2. **Path format** - Correct: `C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx`
3. **Input binding** - 5 parameters correctly formatted
4. **Rhino.Compute service** - Responds (but with error)
5. **rhino3dm** - Successfully initializes and creates geometry

### ❌ What's Failing
1. **Empty error response** - Rhino.Compute returns HTTP 500 with no body
2. **Instant failure** - Fails in 8-42ms, suggesting file load issue, not execution
3. **No Grasshopper logs** - Not reaching Grasshopper execution

---

## 🔬 Diagnostic Conclusion

The **empty response body** and **instant failure time** indicate that Rhino.Compute is crashing during file load, **before** it can construct a proper error response or execute the Grasshopper definition.

### Most Likely Causes (in order):

#### 1. File Doesn't Exist ⚠️ (Most Likely)
- Path: `C:\compute\sitefit\1.0.0\ghlogic.ghx`
- May not have been uploaded
- May be in different location or with different name

#### 2. File Corruption 🔥
- GHX file is corrupted or incomplete
- Invalid XML structure
- Binary corruption during transfer

#### 3. Parameter Mismatch 📝
- GHX expects different parameter names
- Missing required inputs
- Wrong parameter types

#### 4. Missing Components/Plugins ⚙️
- GHX uses components not available in Rhino 8
- Required plugins not installed
- Custom components missing

---

## 🛠️ Required Actions

### Step 1: Verify File Exists (MANUAL - VIA RDP)

**Connect to VM:**
```bash
# Get VM IP
az vm show --resource-group kuduso-dev-rg --name kuduso-dev-rhino-vm \
  --show-details --query "publicIps" -o tsv

# Connect via RDP
# IP: 52.148.197.239
# User: rhinoadmin
```

**Check File:**
```powershell
# In PowerShell on the VM:
Test-Path 'C:\compute\sitefit\1.0.0\ghlogic.ghx'
Get-ChildItem 'C:\compute' -Recurse
```

**Expected Location:**
```
C:\compute\
  └── sitefit\
      └── 1.0.0\
          └── ghlogic.ghx  ← Should be here
```

---

### Step 2: Upload GHX File (If Missing)

The GHX file is in the repo at:
```
contracts/sitefit/1.0.0/sitefit_ready.ghx
```

**Upload using RDP:**
```bash
# From local machine
cd /home/martin/Desktop/kuduso
xfreerdp /v:52.148.197.239 /u:rhinoadmin \
  /dynamic-resolution /cert:ignore \
  /drive:local,$(pwd)/contracts/sitefit/1.0.0
```

**Then on VM in PowerShell:**
```powershell
# Create directory
New-Item -ItemType Directory -Path 'C:\compute\sitefit\1.0.0' -Force

# Copy file and RENAME to ghlogic.ghx
Copy-Item '\\tsclient\local\sitefit_ready.ghx' `
  -Destination 'C:\compute\sitefit\1.0.0\ghlogic.ghx'

# Verify
Get-Item 'C:\compute\sitefit\1.0.0\ghlogic.ghx' | Format-List
```

---

### Step 3: Verify GHX Parameter Names

**Open the GHX file** (either locally or on VM in Grasshopper):
```
contracts/sitefit/1.0.0/sitefit_ready.ghx
```

**Verify Input Parameters Match:**
```
Expected (from bindings.json):
✓ parcel_polygon
✓ house_polygon
✓ rotation_spec
✓ grid_step
✓ seed
```

**Verify Output Parameters Match:**
```
Expected (from bindings.json):
✓ placed_transforms
✓ placement_scores
✓ kpis
```

---

### Step 4: Test GHX in Grasshopper (Manual)

**On the Rhino VM:**
1. Open Rhino 8
2. Start Grasshopper
3. Open `C:\compute\sitefit\1.0.0\ghlogic.ghx`
4. Check for:
   - ❌ Error messages
   - ⚠️ Warning messages
   - 🔴 Missing components (red)
   - ⚪ Disabled components (grey)

---

### Step 5: Test via Rhino.Compute (After Fix)

**Simple test request:**
```bash
RHINO_IP="52.148.197.239"
API_KEY=$(az keyvault secret show --vault-name kuduso-dev-kv-93d2ab \
  --name COMPUTE-API-KEY --query value -o tsv)

# Test if file loads (even with wrong inputs)
curl -X POST http://$RHINO_IP:8081/grasshopper \
  -H "RhinoComputeKey: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "algo": "C:\\compute\\sitefit\\1.0.0\\ghlogic.ghx",
    "pointer": true,
    "values": []
  }' -v
```

**Expected responses:**
- ✅ **File exists & loads:** HTTP 200 or 422 with Grasshopper errors about missing inputs
- ❌ **File missing:** HTTP 500 with empty body (current behavior)
- ❌ **File corrupt:** HTTP 500 with error message

---

## 📊 Current Stack Status

```
✅ API Gateway         - Receiving jobs
✅ Service Bus         - Queuing messages  
✅ Worker              - Processing jobs
✅ AppServer           - Calling Rhino.Compute
✅ Network (NSG)       - Port 8081 accessible
✅ Rhino.Compute       - Responding to requests
✅ rhino3dm            - Geometry creation working
✅ Path Format         - Correct Windows path
❌ GHX File            - Missing or corrupted ← BLOCKER
```

---

## 🎓 What We Learned

### Enhanced Logging Shows:
1. **Empty responses indicate crashes** - When Rhino.Compute crashes during file load, it returns 500 with no body
2. **Response time reveals stage** - <50ms = file load issue, >1s = execution issue
3. **Content-type header is key** - `null` means crash before response construction

### Rhino.Compute Behavior:
- Returns **proper error JSON** when GHX executes with errors
- Returns **empty 500** when it crashes before execution
- Instant failure = file system or parse error
- Slow failure = execution or computation error

---

## 🚀 Next Steps

1. **RDP to VM** and verify file exists at `C:\compute\sitefit\1.0.0\ghlogic.ghx`
2. If missing: **Upload `sitefit_ready.ghx` as `ghlogic.ghx`**
3. **Test file in Grasshopper** manually to verify it works
4. **Re-test via API** to confirm end-to-end flow

Once the GHX file issue is resolved, the full stack should work end-to-end.

---

## 📝 Files Modified for Enhanced Logging

```
✏️  shared/appserver-node/src/rhinoComputeClient.ts
    - Enhanced error logging with full response details
    - Added status, statusText, contentType, errorBody
    - Logs both HTTP errors and Grasshopper errors separately

✏️  shared/appserver-node/src/computeSolver.ts
    - Added input parameter details to request logging
    - Shows parameter names and path counts
```

---

**Investigation Status:** Complete - waiting for manual VM access to verify/fix GHX file  
**Recommendation:** Use RDP to check file existence and upload if missing  
**Expected Resolution Time:** 5-10 minutes once VM is accessed

---

