# Kuduso Contracts

This directory contains all contract definitions for Kuduso computational definitions. Contracts are the **source of truth** for input/output schemas, operational limits, and engine requirements.

## Structure

```
contracts/
├── {definition}/
│   └── {version}/
│       ├── inputs.schema.json      # Input payload schema
│       ├── outputs.schema.json     # Output response schema
│       ├── bindings.json           # JSON ↔ compute engine mapping
│       ├── manifest.json           # Operational limits & requirements
│       ├── plugins.json            # Required plugin inventory
│       ├── README.md               # Human documentation
│       └── examples/
│           ├── valid/              # Valid example payloads
│           └── invalid/            # Invalid examples for testing
├── _templates/                     # Templates for new definitions
└── scripts/                        # Validation tooling
```

## Available Definitions

### sitefit/1.0.0
Places a house footprint onto a land parcel under geometric constraints. See [sitefit/1.0.0/README.md](./sitefit/1.0.0/README.md) for details.

## Validation

### Install Dependencies
```bash
cd contracts
npm install
```

### Validate a Single Payload
```bash
npm run validate sitefit 1.0.0 sitefit/1.0.0/examples/valid/minimal.json
```

### Validate All Examples
```bash
# All contracts
npm run validate:all

# Specific contract
npm run validate:sitefit
```

### In CI
```bash
npm test
```

## Creating a New Contract

1. **Copy templates**:
   ```bash
   mkdir -p {definition}/{version}
   cp _templates/* {definition}/{version}/
   ```

2. **Fill in placeholders** in each template file

3. **Create examples**:
   ```bash
   mkdir -p {definition}/{version}/examples/{valid,invalid}
   # Add at least 2 valid and 2 invalid examples
   ```

4. **Validate**:
   ```bash
   npm run validate:all
   ```

## Versioning Rules

- **Folder is immutable**: Once released, `{definition}/{version}/` never changes
- **Semantic versioning**:
  - **MAJOR**: Breaking changes (field renamed/removed, meaning changed)
  - **MINOR**: Additive, backward-compatible (new optional fields)
  - **PATCH**: Documentation/constraint tweaks, no schema break
- **Fixes**: Create new version (e.g., `1.0.1`)

## Contract Components

### inputs.schema.json
JSON Schema (Draft 2020-12) defining:
- Required fields
- Types, ranges, enums
- Units and CRS requirements
- Descriptions

### outputs.schema.json
JSON Schema defining:
- Results array structure
- Artifacts metadata
- Execution metadata/provenance

### bindings.json
Declarative mapping:
- JSON input paths → compute graph parameters
- Compute graph outputs → JSON response paths

### manifest.json
Operational guardrails:
- Timeout limits
- Resource caps (vertices, samples)
- Concurrency class
- Validation policies

### plugins.json
Runtime requirements:
- Engine version (e.g., Rhino.Compute 8.7.x)
- Plugin names and versions
- Verification policy

### README.md
Human documentation:
- Purpose and description
- Input/output summaries
- Limits and requirements
- Example usage
- Changelog

## Error Taxonomy

All services implementing contracts must use:
- `400` - Schema validation failed
- `422` - Domain infeasible (constraint violation)
- `429` - Concurrency limit hit
- `504` - Compute engine timeout

## Integration

Services import these contracts at runtime or build time:
- **AppServer**: Validates inputs/outputs, enforces limits
- **API**: Validates job payloads before enqueuing
- **Worker**: Validates before calling AppServer
- **Frontend**: Generates forms and validation from schemas

## CI/CD

Add to `.github/workflows/contracts.yml`:
```yaml
- name: Validate contracts
  run: |
    cd contracts
    npm ci
    npm test
```

## Support

For questions or contract change requests, open an issue in the main repository.
