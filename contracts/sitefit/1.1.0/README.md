# SiteFit v1.1.0 - Debug Version

## Purpose

This is a **minimal debug version** created for testing the end-to-end pipeline without complex geometry or Python scripts.

## Contract

**Input:**
- `value` (number): A single number between 0-1000

**Output:**
- `result` (number): The input value + 10

## Grasshopper Logic

The GHX file contains:
1. **Input Parameter** (`input_value`) - Number Slider
2. **Addition Component** - Adds 10 to the input
3. **Output Parameter** (`output_value`) - Panel

No Python scripts, no geometry, no complex logic.

## Example Usage

### Request
```json
{
  "app_id": "sitefit",
  "definition": "sitefit",
  "version": "1.1.0",
  "inputs": {
    "value": 42
  }
}
```

### Expected Response
```json
{
  "result": 52
}
```

## Testing

```bash
# Submit test job
curl -X POST "https://kuduso-dev-sitefit-api.../jobs/run" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "sitefit",
    "definition": "sitefit",
    "version": "1.1.0",
    "inputs": {"value": 42}
  }'
```

## Deployment

1. Place `ghlogic.ghx` in: `C:\compute\sitefit\1.1.0\ghlogic.ghx`
2. Restart IIS on Rhino VM
3. Test with AppServer

## Why This Version?

- **No geometry** - Eliminates rhino3dm complexity
- **No Python** - Eliminates script errors
- **Simple math** - Easy to verify correctness
- **Fast** - Should complete in <1 second

Perfect for debugging infrastructure, not business logic.

