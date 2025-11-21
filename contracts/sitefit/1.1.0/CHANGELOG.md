# Changelog - SiteFit v1.1.0

## [1.1.0] - 2025-11-21

### Purpose
Minimal debug version for infrastructure testing.

### Changed
- **Simplified to single number input/output** - Removed all geometry, polygons, transforms
- **Removed Python script** - No scripting components, just native GH math
- **Reduced complexity** - Only 3 components: input parameter, addition, output parameter

### Why?
The production version (1.0.0) is too complex for debugging infrastructure issues:
- Complex geometry processing with rhino3dm
- Python script with multiple outputs
- Multiple input parameters
- GeoJSON transformations

This debug version (1.1.0) isolates infrastructure testing from business logic.

### Usage
Replace 1.0.0 with 1.1.0 in API requests for testing:
```json
{
  "version": "1.1.0",
  "inputs": {"value": 42}
}
```

Expected output:
```json
{
  "result": 52
}
```

### Migration Path
- This is NOT a replacement for 1.0.0
- 1.1.0 is for debugging only
- Production apps should use 1.0.0 (or future versions)
- Both versions will coexist

## Comparison: 1.0.0 vs 1.1.0

| Aspect | 1.0.0 (Production) | 1.1.0 (Debug) |
|--------|-------------------|---------------|
| Inputs | 5 parameters (polygons, grid, seed) | 1 number |
| Outputs | 3 arrays (transforms, scores, KPIs) | 1 number |
| Components | 10+ (Python, geometry, etc) | 3 (param, add, param) |
| Python | Yes | No |
| Geometry | Yes (rhino3dm) | No |
| Purpose | Production placement solver | Infrastructure testing |
| Complexity | High | Minimal |
| Execution Time | 1-4 minutes (if working) | <1 second |

## Deployment Instructions

1. Copy `ghlogic.ghx` to: `C:\compute\sitefit\1.1.0\ghlogic.ghx`
2. Restart IIS
3. Test with minimal request
4. If successful, infrastructure is working
5. Then debug 1.0.0 business logic separately

