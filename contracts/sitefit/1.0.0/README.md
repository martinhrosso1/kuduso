# SiteFit Contract v1.0.0

## Purpose

SiteFit is a computational definition for placing a house footprint onto a land parcel under geometric and spatial constraints. It evaluates multiple placement options (rotation and translation) and returns scored solutions with transforms and key performance indicators.

## Inputs Summary

| Parameter | Type | Units | Default | Description |
|-----------|------|-------|---------|-------------|
| `crs` | string | - | *required* | Coordinate reference system (e.g., `EPSG:5514`) |
| `parcel.coordinates` | array | CRS units | *required* | Parcel boundary as closed polygon `[[x,y], ...]` |
| `house.coordinates` | array | CRS units | *required* | House footprint as closed polygon `[[x,y], ...]` |
| `rotation.min` | number | degrees | `0` | Minimum rotation angle to test |
| `rotation.max` | number | degrees | `180` | Maximum rotation angle to test |
| `rotation.step` | number | degrees | `5` | Rotation increment step |
| `grid_step` | number | meters | `0.5` | Grid spacing for placement sampling |
| `seed` | integer | - | `1` | Random seed for deterministic results |

## Outputs Summary

### Results Array
Each placement solution includes:
- **transform**: Rotation, translation, and scale to apply to house footprint
- **score**: Quality metric (higher is better)
- **metrics**: KPIs such as:
  - Distance to parcel boundaries
  - Overlap percentage
  - Orientation score
  - Constraint violations
- **tags**: Descriptive labels (e.g., "optimal", "feasible", "warning:close-to-edge")

### Artifacts
Generated files available for download:
- **GeoJSON**: 2D geometry overlay
- **glTF**: 3D visualization model
- **PDF**: Report with placement analysis (optional)

### Metadata
Execution provenance:
- Contract definition and version
- Units (length, angle, CRS)
- Random seed used
- Timestamp and engine information
- Cache hit status
- Warnings (if any)

## Operational Limits (from manifest.json)

- **Timeout**: 240 seconds
- **Max vertices**: 10,000 (combined parcel + house)
- **Max samples**: 10,000 (rotation × translation grid points)
- **Max results**: 5 (top-ranked placements returned)
- **Concurrency class**: `batch` (authoritative runs; weight=1)

## Engine Notes

- **Grasshopper definition**: `sitefit.ghx` (headless-safe)
- **Expected units**: Meters for lengths, degrees for angles
- **CRS handling**: Worker normalizes inputs to canonical meters CRS before calling AppServer
- **Determinism**: Seed is required and recorded in output metadata

## Required Plugins

- **Rhino.Compute**: 8.7.x
- **Human**: 1.3.2 (required)
- **LunchBox**: 2024.5.0 (optional)

## Error Handling

| Status Code | Meaning |
|-------------|---------|
| `400` | Schema validation failed (inputs don't match schema) |
| `422` | Domain infeasible (e.g., house doesn't fit in parcel under any transform) |
| `429` | Concurrency limit hit, retry later |
| `504` | Compute engine timeout |

## Versioning

- **Version**: 1.0.0
- **Breaking changes**: Will increment MAJOR version
- **Backward-compatible additions**: Will increment MINOR version
- **Documentation/constraint tweaks**: Will increment PATCH version

## Changelog

### 1.0.0 (Initial Release)
- Initial contract definition
- Support for rotation and translation placement search
- Basic scoring and KPI metrics
- GeoJSON and glTF artifact generation

## Examples

See `examples/` directory:
- `valid/minimal.json` - Minimal valid payload
- `valid/typical.json` - Realistic scenario with all parameters
- `invalid/missing-required.json` - Missing required fields
- `invalid/bad-crs.json` - Invalid CRS format

## Usage

```bash
# Validate an input payload
npm run validate:contracts -- examples/valid/minimal.json

# Run mock computation (Stage 1)
curl -X POST http://localhost:8080/gh/sitefit:1.0.0/solve \
  -H "Content-Type: application/json" \
  -d @examples/valid/minimal.json
```

## Contact

For questions or contract change requests, open an issue in the repository.
