# Building the SiteFit Grasshopper Definition

## Overview

This guide shows you how to create `sitefit.ghx` that implements the SiteFit v1.0.0 contract for Rhino.Compute.

---

## Quick Start (Recommended)

### Use the Python Script Component

1. **Open Rhino 8**
2. **Type `Grasshopper`** to launch GH editor
3. **Add components to canvas:**

   a. **5 Input Parameters** (from Params > Input panel):
   - `parcel_polygon` (Curve parameter)
   - `house_polygon` (Curve parameter)
   - `rotation_spec` (Text parameter)
   - `grid_step` (Number parameter)
   - `seed` (Integer parameter)

   b. **1 Python Script component** (Maths > Script > Python Script):
   - Double-click to open the editor
   - Delete the default `RunScript` function stub
   - Copy the entire contents of `SiteFitSolver.py`
   - Set input parameter names (right-click input > Rename): 
     - `parcel_polygon` (Curve)
     - `house_polygon` (Curve)
     - `rotation_spec` (string)
     - `grid_step` (double)
     - `seed` (int)
   - Set output parameter names:
     - `placed_transforms` (object)
     - `placement_scores` (object)
     - `kpis` (object)

   c. **3 Output Panels** (from Params > Output panel):
   - `placed_transforms` (connect to script output `placed_transforms`)
   - `placement_scores` (connect to script output `placement_scores`)
   - `kpis` (connect to script output `kpis`)

4. **Wire inputs to the Python component inputs**
5. **Wire Python component outputs to output panels**
6. **Right-click each parameter** → **Set as input/output** (for RhinoCompute)
7. **Save as `sitefit.ghx`** (File > Save As > XML format)

---

## Canvas Layout

```
┌─────────────────────┐
│  parcel_polygon     │────┐
│  (Curve Input)      │    │
└─────────────────────┘    │
                           │
┌─────────────────────┐    │
│  house_polygon      │────┤
│  (Curve Input)      │    │
└─────────────────────┘    │      ┌──────────────────┐      ┌──────────────────┐
                           │      │                  │      │ placed_transforms│
┌─────────────────────┐    ├─────▶│   C# Script     │─────▶│  (Panel Output)  │
│  rotation_spec      │    │      │  SiteFitSolver   │      └──────────────────┘
│  (Text Input)       │────┤      │                  │
└─────────────────────┘    │      │                  │      ┌──────────────────┐
                           │      │                  │─────▶│ placement_scores │
┌─────────────────────┐    │      │                  │      │  (Panel Output)  │
│  grid_step          │────┤      └──────────────────┘      └──────────────────┘
│  (Number Input)     │    │
└─────────────────────┘    │                                ┌──────────────────┐
                           │                                │      kpis        │
┌─────────────────────┐    │                                │  (Panel Output)  │
│  seed               │────┘                                └──────────────────┘
│  (Integer Input)    │
└─────────────────────┘
```

---

## Parameter Configuration

### Inputs (must be marked as "Principal Parameter"):

1. **parcel_polygon**
   - Type: Curve
   - Hint: "Item access" (not list)
   - Set Principal: Yes
   - Name MUST match exactly

2. **house_polygon**
   - Type: Curve
   - Hint: "Item access"
   - Set Principal: Yes
   - Name MUST match exactly

3. **rotation_spec**
   - Type: Text (String)
   - Default: `{"min":0,"max":180,"step":5}`
   - Set Principal: Yes
   - Name MUST match exactly

4. **grid_step**
   - Type: Number (Double)
   - Default: 0.5
   - Set Principal: Yes
   - Name MUST match exactly

5. **seed**
   - Type: Integer
   - Default: 1
   - Set Principal: Yes
   - Name MUST match exactly

### Outputs (must be marked as "Principal Parameter"):

1. **placed_transforms**
   - Type: Text (list)
   - Set Principal: Yes
   - Name MUST match exactly

2. **placement_scores**
   - Type: Number (list)
   - Set Principal: Yes
   - Name MUST match exactly

3. **kpis**
   - Type: Text (list)
   - Set Principal: Yes
   - Name MUST match exactly

---

## Testing Locally in Rhino

Before uploading to Rhino.Compute, test locally:

### 1. Create Test Geometry

```
# In Rhino command line:

# Create parcel (10m x 15m rectangle)
_Rectangle 0,0,0 10,15

# Create house (6m x 8m rectangle)
_Rectangle 0,0,0 6,8

# Select parcel curve and right-click parcel_polygon param → "Set one curve"
# Select house curve and right-click house_polygon param → "Set one curve"
```

### 2. Set Test Parameters

- **rotation_spec**: `{"min":0,"max":90,"step":15}`
- **grid_step**: `1.0`
- **seed**: `42`

### 3. Run and Verify

You should see:
- **placed_transforms**: Array of JSON transform objects
- **placement_scores**: Array of numbers (scores)
- **kpis**: Array of JSON metrics objects

Example output:
```json
// placed_transforms[0]:
{"rotation":{"axis":"z","value":15,"units":"deg"},"translation":{"x":2.5,"y":3.0,"z":0,"units":"m"},"scale":{"uniform":1.0}}

// placement_scores[0]:
0.825

// kpis[0]:
{"yard_area_m2":102,"min_setback_m":2.5,"house_area_m2":48,"orientation_deg":15,"parcel_utilization":0.32}
```

---

## Uploading to Rhino VM

### 1. Save the Definition

```
File > Save As > sitefit.ghx
Location: /home/martin/Desktop/kuduso/contracts/sitefit/1.0.0/
Format: XML (*.ghx)
```

### 2. Upload to Rhino VM via RDP

```bash
# From local machine, copy file to VM
# Option 1: RDP to VM and copy-paste
mstsc /v:52.148.197.239

# Option 2: Use Azure File Share
az storage file upload \
  --account-name kudusodevst93d2ab \
  --share-name rhino-definitions \
  --source ./sitefit.ghx \
  --path sitefit/1.0.0/sitefit.ghx
```

### 3. Place on VM

Place the file in:
```
C:\RhinoDefinitions\sitefit\1.0.0\sitefit.ghx
```

---

## Rhino.Compute API Call

Once deployed, test via API:

```bash
# Get API key
API_KEY=$(az keyvault secret show \
  --vault-name kuduso-dev-kv-93d2ab \
  --name RHINO-COMPUTE-KEY \
  --query value -o tsv)

# Call Rhino.Compute
curl -X POST http://52.148.197.239:8081/grasshopper \
  -H "Content-Type: application/json" \
  -H "RhinoComputeKey: $API_KEY" \
  -d '{
    "algo": "C:/RhinoDefinitions/sitefit/1.0.0/sitefit.ghx",
    "pointer": null,
    "values": [
      {
        "ParamName": "parcel_polygon",
        "InnerTree": {
          "{0}": [
            {
              "type": "Rhino.Geometry.PolylineCurve",
              "data": "..." 
            }
          ]
        }
      },
      {
        "ParamName": "house_polygon",
        "InnerTree": {
          "{0}": [
            {
              "type": "Rhino.Geometry.PolylineCurve",
              "data": "..."
            }
          ]
        }
      },
      {
        "ParamName": "rotation_spec",
        "InnerTree": {
          "{0}": [
            {
              "type": "System.String",
              "data": "{\"min\":0,\"max\":180,\"step\":5}"
            }
          ]
        }
      },
      {
        "ParamName": "grid_step",
        "InnerTree": {
          "{0}": [
            {
              "type": "System.Double",
              "data": "0.5"
            }
          ]
        }
      },
      {
        "ParamName": "seed",
        "InnerTree": {
          "{0}": [
            {
              "type": "System.Int32",
              "data": "1"
            }
          ]
        }
      }
    ]
  }'
```

---

## Troubleshooting

### "Parameter not found"
- Ensure parameter names match **exactly** (case-sensitive)
- Check spelling: `parcel_polygon`, `house_polygon`, etc.
- Right-click param → Properties → check "Principal parameter" is checked

### "Script error" in C# component
- Check you have `using Newtonsoft.Json;` at top
- Verify Rhino.Compute has Newtonsoft.Json.dll available
- Check for syntax errors in C# code

### "Curve is not closed"
- Ensure test curves are closed (use `_CloseCrv` in Rhino)
- Check curve direction and validity

### No results returned
- Reduce `grid_step` (try 0.5 or 1.0)
- Increase rotation step (try 15 or 30 degrees)
- Check house fits in parcel at all

### Slow performance
- Increase `grid_step` (try 2.0 or 5.0)
- Reduce rotation range (try 0-90 instead of 0-180)
- Reduce rotation step count (try step:30 instead of step:5)

---

## Performance Guidelines

For MVP (Stage 4):
- **Grid step**: 0.5 - 2.0 meters
- **Rotation step**: 5 - 15 degrees
- **Rotation range**: 0-180 degrees max
- **Expected samples**: ~100-500 placements tested
- **Target time**: < 5 seconds per call

---

## Next Steps

After verifying this works:
1. ✅ Test with real parcel/house geometries
2. ✅ Tune scoring function weights
3. ✅ Add more KPIs (solar access, views, etc.)
4. ✅ Optimize for performance
5. ✅ Add constraint checks (setback rules, etc.)
6. ✅ Deploy to production Rhino.Compute

---

## Files Created

- ✅ `SiteFitSolver.cs` - C# script implementation
- ✅ `sitefit.ghx` - Grasshopper definition (you'll build this)
- ✅ `GRASSHOPPER_BUILD_INSTRUCTIONS.md` - This file

**Ready to build!** 🚀
