# {DEFINITION_TITLE} Contract v{VERSION}

## Purpose

{DEFINITION_DESCRIPTION}

## Inputs Summary

| Parameter | Type | Units | Default | Description |
|-----------|------|-------|---------|-------------|
| `crs` | string | - | *required* | Coordinate reference system |
| {ADD_MORE_ROWS} | | | | |

## Outputs Summary

### Results Array
{DESCRIBE_OUTPUT_STRUCTURE}

### Artifacts
{DESCRIBE_ARTIFACTS}

### Metadata
Execution provenance including definition, version, units, seed, timestamp, and cache status.

## Operational Limits (from manifest.json)

- **Timeout**: {TIMEOUT} seconds
- **Max vertices**: {MAX_VERTICES}
- **Max samples**: {MAX_SAMPLES}
- **Max results**: {MAX_RESULTS}
- **Concurrency class**: {CONCURRENCY_CLASS}

## Engine Notes

- **Grasshopper definition**: `{DEFINITION_NAME}.ghx`
- **Expected units**: {UNITS_DESCRIPTION}
- **Determinism**: {DETERMINISM_NOTES}

## Required Plugins

{LIST_PLUGINS}

## Error Handling

| Status Code | Meaning |
|-------------|---------|
| `400` | Schema validation failed |
| `422` | Domain infeasible |
| `429` | Concurrency limit hit |
| `504` | Compute engine timeout |

## Versioning

- **Version**: {VERSION}
- Follow semantic versioning (MAJOR.MINOR.PATCH)

## Changelog

### {VERSION} (Initial Release)
- Initial contract definition

## Examples

See `examples/` directory for valid and invalid sample payloads.

## Contact

For questions or contract change requests, open an issue in the repository.
