# Stage 0 — Bootstrap & Contracts

## 0.1 Repository skeleton

```
housefit/
  contracts/
    sitefit/1.0.0/
      inputs.schema.json
      outputs.schema.json
      bindings.json
      manifest.json
      plugins.json
      README.md
      examples/
        valid/minimal.json
        valid/typical.json
        invalid/missing-required.json
    _templates/
      inputs.schema.template.json
      outputs.schema.template.json
      bindings.template.json
      manifest.template.json
      plugins.template.json
  apps/
    appserver-node/
    api-fastapi/
    worker-fastapi/
    frontend/
  packages/
    ts-sdk/
    py-sdk/
  infra/
    azure/
  tests-e2e/
  .github/workflows/
  Makefile   # or Taskfile.yml
```

* `contracts/{definition}/{version}` is **the source of truth**.
* `_templates` helps stamp new definitions fast.

---

## 0.2 Contract files (what each must contain)

### A) `inputs.schema.json` — request shape

* JSON Schema Draft 2020-12
* Required fields, units/CRS, ranges, enums, descriptions.

**Minimal example**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://kuduso/contracts/sitefit/1.0.0/inputs.schema.json",
  "title": "SiteFit Inputs v1.0.0",
  "type": "object",
  "required": ["crs", "parcel", "house"],
  "properties": {
    "crs": { "type": "string", "pattern": "^EPSG:\\d+$", "description": "Coordinate reference system" },
    "parcel": {
      "type": "object",
      "required": ["coordinates"],
      "properties": {
        "coordinates": {
          "type": "array",
          "minItems": 4,
          "items": { "type": "array", "items": [{ "type": "number" }, { "type": "number" }] },
          "description": "Closed ring [ [x,y], ... ] in CRS units"
        }
      }
    },
    "house": {
      "type": "object",
      "required": ["coordinates"],
      "properties": {
        "coordinates": { "$ref": "#/properties/parcel/properties/coordinates" }
      }
    },
    "rotation": {
      "type": "object",
      "properties": {
        "min": { "type": "number", "default": 0, "description": "deg" },
        "max": { "type": "number", "default": 180, "description": "deg" },
        "step": { "type": "number", "default": 5, "minimum": 0.1, "description": "deg" }
      }
    },
    "grid_step": { "type": "number", "default": 0.5, "minimum": 0.1, "description": "meters in CRS units" },
    "seed": { "type": "integer", "default": 1 }
  },
  "additionalProperties": false
}
```

### B) `outputs.schema.json` — response shape

* General but useful for your UI and storage.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://kuduso/contracts/sitefit/1.0.0/outputs.schema.json",
  "title": "SiteFit Outputs v1.0.0",
  "type": "object",
  "required": ["results"],
  "properties": {
    "results": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["transform"],
        "properties": {
          "id": { "type": "string" },
          "transform": {
            "type": "object",
            "properties": {
              "rotation": {
                "type": "object",
                "properties": {
                  "axis": { "type": "string", "enum": ["x", "y", "z"], "default": "z" },
                  "value": { "type": "number" },
                  "units": { "type": "string", "enum": ["deg", "rad"], "default": "deg" }
                },
                "required": ["value"]
              },
              "translation": {
                "type": "object",
                "properties": {
                  "x": { "type": "number" }, "y": { "type": "number" }, "z": { "type": "number", "default": 0 },
                  "units": { "type": "string", "default": "m" }
                }
              },
              "scale": {
                "oneOf": [
                  { "type": "object", "properties": { "uniform": { "type": "number", "default": 1 } } },
                  { "type": "object", "properties": { "x": { "type": "number" }, "y": { "type": "number" }, "z": { "type": "number" } } }
                ],
                "default": { "uniform": 1 }
              }
            }
          },
          "score": { "type": "number" },
          "metrics": { "type": "object", "additionalProperties": { "type": ["number","string","boolean"] } },
          "tags": { "type": "array", "items": { "type": "string" } }
        },
        "additionalProperties": false
      }
    },
    "artifacts": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["kind", "url"],
        "properties": {
          "kind": { "type": "string", "enum": ["geojson", "gltf", "pdf", "csv", "png"] },
          "url": { "type": "string", "format": "uri" },
          "expires_at": { "type": "string", "format": "date-time" },
          "label": { "type": "string" }
        }
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "definition": { "type": "string" },
        "version": { "type": "string" },
        "units": {
          "type": "object",
          "properties": {
            "length": { "type": "string", "default": "m" },
            "angle": { "type": "string", "default": "deg" },
            "crs": { "type": "string" }
          }
        },
        "seed": { "type": "integer" },
        "generated_at": { "type": "string", "format": "date-time" },
        "engine": { "type": "object" },
        "cache_hit": { "type": "boolean", "default": false },
        "warnings": { "type": "array", "items": { "type": "string" } }
      }
    }
  },
  "additionalProperties": false
}
```

### C) `bindings.json` — JSON → compute graph mapping

* Maps **JSONPath** (or property paths) to Grasshopper param names.
* Keeps AppServer free of bespoke glue.

```json
{
  "engine": "grasshopper",
  "definition": "sitefit.ghx",
  "inputs": [
    { "jsonpath": "$.parcel.coordinates", "gh_param": "parcel_polygon" },
    { "jsonpath": "$.house.coordinates",  "gh_param": "house_polygon"  },
    { "jsonpath": "$.rotation",           "gh_param": "rotation_spec"  },
    { "jsonpath": "$.grid_step",          "gh_param": "grid_step"      },
    { "jsonpath": "$.seed",               "gh_param": "seed"           }
  ],
  "outputs": [
    { "gh_param": "placed_transform", "output_path": "$.results[0].transform" },
    { "gh_param": "kpis",             "output_path": "$.results[0].metrics"   }
  ]
}
```

### D) `manifest.json` — operational guardrails

* Enforced by AppServer **before** calling Rhino.

```json
{
  "timeout_sec": 240,
  "limits": {
    "max_vertices": 10000,
    "max_samples": 10000,
    "max_results": 5
  },
  "concurrency": {
    "class": "batch",          // "preview" | "batch"
    "weight": 1
  },
  "units": { "length": "m", "angle": "deg", "crs_required": true },
  "determinism": { "seed_required": true }
}
```

### E) `plugins.json` — required runtime inventory

* Make runs reproducible; AppServer rejects mismatches.

```json
{
  "engine": { "name": "rhino.compute", "version": "8.7.x" },
  "plugins": [
    { "name": "Human", "version": "1.3.2" },
    { "name": "LunchBox", "version": "2024.5.0" }
  ]
}
```

---

## 0.3 Author examples & tests early

* **`examples/valid/minimal.json`** & **`examples/valid/typical.json`**
  Small payloads the whole team can run.
* **`examples/invalid/*.json`**
  Exercise schema errors (missing fields, bad CRS).
* Optional **contract tests** (run in CI) that:

  * Validate examples against `inputs.schema.json`.
  * Spin the mock AppServer and assert the response matches `outputs.schema.json`.

---

## 0.4 Tooling: validation & codegen

### Node validation (Ajv)

`apps/appserver-node/scripts/validate.ts`

```ts
import Ajv from "ajv";
import addFormats from "ajv-formats";
import inputs from "../../contracts/sitefit/1.0.0/inputs.schema.json";

const ajv = new Ajv({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(inputs);
const payload = JSON.parse(process.argv[2]);
if (!validate(payload)) {
  console.error(JSON.stringify(validate.errors, null, 2));
  process.exit(1);
}
console.log("OK");
```

### Python types (Pydantic)

Generate pydantic models from schema (either use `datamodel-code-generator` or handcraft core models).

`apps/api-fastapi/models/sitefit_v1.py` (handwritten minimal)

```python
from pydantic import BaseModel, Field, conlist
from typing import List, Tuple, Optional, Dict, Any

Coord = conlist(float, min_items=2, max_items=2)
Ring = List[Coord]

class Polygon(BaseModel):
    coordinates: List[Ring]

class RotationSpec(BaseModel):
    min: float = 0
    max: float = 180
    step: float = 5

class Inputs(BaseModel):
    crs: str
    parcel: Polygon
    house: Polygon
    rotation: Optional[RotationSpec] = None
    grid_step: float = Field(0.5, ge=0.1)
    seed: int = 1

class OutputTransform(BaseModel):
    # simplified for brevity
    pass
```

---

## 0.5 Naming & versioning rules

* **Definition name**: lowercase slug (`sitefit`, `daylight`, `viewshed`).
* **Version**: semantic (`MAJOR.MINOR.PATCH`).

  * **MAJOR**: breaking changes (field renamed/removed, meaning changed).
  * **MINOR**: additive, backward-compatible (new optional fields).
  * **PATCH**: docs/constraints tweaks, no schema break.
* **Folder is immutable**: `contracts/sitefit/1.0.0/` never changes post-release; fixes go to `1.0.1`.

Add `CHANGELOG.md` inside the definition folder summarizing deltas.

---

## 0.6 Determinism & idempotency

* **Seed** must be present (or defaulted). Record it in `metadata.seed`.
* **`inputs_hash`** = SHA256 of **normalized** inputs (+ `definition@version`).

  * Normalize (sort keys, fixed decimals) to avoid hash drift.
  * API & Worker use the hash for caching/duplicate collapse.

---

## 0.7 Units, CRS, and geometry conventions

* **CRS required** (e.g., `EPSG:5514` or `EPSG:3857`); Worker reprojects to a canonical meters CRS before compute.
* **Units declared** in outputs metadata: `{ length: "m", angle: "deg", crs: "EPSG:xxxx" }`.
* **Polygons**: closed ring, no self-intersections; define winding (CW/CCW) if needed and stick to it.

---

## 0.8 Error taxonomy (contract-level)

All services must use these status codes:

* `400` — schema validation failed (inputs don’t match `inputs.schema.json`)
* `422` — domain infeasible (violates constraints)
* `429` — busy / concurrency limit hit
* `504` — upstream (compute) timeout
* Include a machine-readable `code` and human `message` in error bodies.

---

## 0.9 AppServer ↔ Engine handshake (contract-driven)

* AppServer **verifies**:

  * `plugins.json` matches actual engine inventory (Rhino version & plugin list).
  * `manifest.json` caps (vertices/samples/timeout) before execution.
  * `bindings.json` covers all required inputs; missing mapping ⇒ `400`.

* AppServer **converts**:

  * JSON arrays → Grasshopper DataTrees (or equivalent).
  * Engine outputs → `outputs.schema.json` shape.

---

## 0.10 CI tasks (run on every PR)

* **contracts-validate**

  * Validate all `examples/valid/*.json` against `inputs.schema.json`.
  * Ensure `manifest.json` values are sane (timeouts ≤ policy, etc).
  * Lint schemas (e.g., `ajv-cli -s inputs.schema.json -m`).

* **codegen/types**

  * Regenerate TypeScript/Python types (if you use codegen) into `packages/ts-sdk` / `packages/py-sdk`.

* **mock e2e**

  * Spin mock AppServer; POST example inputs to API; assert response validates against `outputs.schema.json`.

* **compat check** (on MINOR/PATCH bumps)

  * Backward-compat tool (simple script): new `inputs.schema.json` must accept all examples from previous version; new outputs must be a superset.

---

## 0.11 Definition README (human docs)

`contracts/sitefit/1.0.0/README.md` should include:

* Purpose in one paragraph.
* Inputs summary (table with name, type, units, default).
* Outputs summary (KPIs/metrics list; score semantics).
* Limits from `manifest.json`.
* Engine notes (e.g., graph expects meters; headless-safe).
* **Changelog** link.

---

## 0.12 Acceptance criteria for Stage 0

* [ ] Repo structure created; templates in place.
* [ ] `sitefit/1.0.0` contracts authored with **valid** schemas and examples.
* [ ] `contracts-validate` CI job passes on PR.
* [ ] Mock AppServer can load `inputs.schema.json`, validate a payload, and emit a response that validates against `outputs.schema.json`.
* [ ] Agreement on **units/CRS**, **error taxonomy**, and **versioning policy** is documented.

---

## 0.13 Nice-to-haves (if time allows)

* **OpenAPI** stub in `api-fastapi` that references contract schemas for request/response.
* **Pre-commit hooks**: JSON lint, schema validation, license headers.
* **Golden test** JSON that you’ll use later to verify Grasshopper parity (mock vs real).

---

### TL;DR

Lock down **contracts first**: schemas, bindings, manifest, plugins, examples, tests. Automate validation in CI. With this in place, the rest of the system (API, Worker, AppServer, UI) can be developed in parallel and will click together cleanly when you flip from mock to Rhino.
