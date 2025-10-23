# Changelog - SiteFit Contract

All notable changes to the SiteFit contract will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-23

### Added
- Initial contract definition for SiteFit (JSON Schema Draft 07)
- Input schema with support for:
  - Parcel and house geometries (closed polygons)
  - Rotation parameters (min, max, step)
  - Grid step for placement sampling
  - Random seed for deterministic results
  - CRS specification
- Output schema with:
  - Placement results with transforms (rotation, translation, scale)
  - Quality scores and metrics
  - Artifacts metadata (GeoJSON, glTF, PDF, etc.)
  - Execution metadata and provenance
- Bindings for Grasshopper parameter mapping
- Manifest with operational limits:
  - 240 second timeout
  - Max 10,000 vertices
  - Max 10,000 samples
  - Max 5 results returned
- Plugin requirements (Rhino.Compute 8.7.x, Human 1.3.2, LunchBox 2024.5.0)
- Example payloads (2 valid, 2 invalid)
- Documentation (README)

### Security
- Strict schema validation with `additionalProperties: false`
- Input size limits to prevent resource exhaustion
- Timeout enforcement

[1.0.0]: https://github.com/kuduso/kuduso/releases/tag/contracts-sitefit-1.0.0
