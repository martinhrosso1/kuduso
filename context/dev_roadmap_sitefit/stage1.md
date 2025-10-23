# Stage 1 — Mocked Compute Loop (local)

## Objectives

* Stand up **three services locally**: AppServer (Node), API (FastAPI), Frontend (Next.js).
* Enforce **contract validation** end-to-end.
* Return a **deterministic mock result** that already matches `outputs.schema.json`.
* Wire **status polling** from the UI.

**Success criteria**

* User fills a minimal form and clicks **Run** → sees a result in <3–5 s.
* Every hop logs a **correlation ID**; invalid inputs return **400** with clear errors.

---

## 1) AppServer (Node) — `/gh/{def}:{ver}/solve` (mock)

**Why first?** Everything depends on it; the API and tests can call it right away.

**Files**

```
shared/appserver-node/
  src/index.ts
  src/validate.ts
  src/mockSolver.ts
  package.json
  tsconfig.json
```

**Key behaviors**

* Load `contracts/<def>/<ver>/inputs.schema.json` and `outputs.schema.json`.
* Validate request with **Ajv**; on failure, return `400` with a machine-readable `errors` array.
* Call `mockSolver()` (deterministic) → shape the response → validate against `outputs.schema.json`.
* Add guardrails you’ll keep later: `x-correlation-id` propagation; `timeout` (e.g., 3s) per request.

**`src/index.ts` (trimmed)**

```ts
import express from "express";
import { validateInputs, validateOutputs } from "./validate";
import { mockSolve } from "./mockSolver";

const app = express();
app.use(express.json());

app.post("/gh/:def::ver/solve", async (req, res) => {
  const cid = req.header("x-correlation-id") || crypto.randomUUID();
  res.setHeader("x-correlation-id", cid);

  const { def, ver } = req.params;
  try {
    const inputs = validateInputs(def, ver, req.body); // throws on error
    const result = await mockSolve(inputs);            // deterministic mock
    validateOutputs(def, ver, result);                 // throws on error
    res.status(200).json(result);
  } catch (e: any) {
    const code = e.code || 400;
    res.status(code).json({ code, message: e.message, details: e.details ?? [] });
  }
});

app.listen(8080, () => console.log("AppServer mock on :8080"));
```

**`src/validate.ts` (core idea)**

```ts
import Ajv from "ajv";
import addFormats from "ajv-formats";
import fs from "node:fs";
import path from "node:path";

const ajv = new Ajv({ allErrors: true, strict: true });
addFormats(ajv);

export function validateInputs(def: string, ver: string, body: any) {
  const p = path.join(process.cwd(), `contracts/${def}/${ver}/inputs.schema.json`);
  const schema = JSON.parse(fs.readFileSync(p, "utf8"));
  const validate = ajv.compile(schema);
  if (!validate(body)) throw { code: 400, message: "Invalid inputs", details: validate.errors };
  return body;
}

export function validateOutputs(def: string, ver: string, body: any) {
  const p = path.join(process.cwd(), `contracts/${def}/${ver}/outputs.schema.json`);
  const schema = JSON.parse(fs.readFileSync(p, "utf8"));
  const validate = ajv.compile(schema);
  if (!validate(body)) throw { code: 500, message: "Mock output violated contract", details: validate.errors };
  return body;
}
```

**`src/mockSolver.ts` (deterministic mock)**

```ts
export async function mockSolve(inputs: any) {
  const seed = inputs.seed ?? 1;
  const theta = 0; // simplest
  const result = {
    results: [
      {
        id: "r1",
        transform: {
          rotation: { axis: "z", value: theta, units: "deg" },
          translation: { x: 0, y: 0, z: 0, units: "m" },
          scale: { uniform: 1 }
        },
        score: 0,
        metrics: { area_m2: 100, seed },
        tags: ["mock", "feasible"]
      }
    ],
    artifacts: [],
    metadata: {
      definition: "sitefit",
      version: "1.0.0",
      units: { length: "m", angle: "deg", crs: inputs.crs },
      seed,
      generated_at: new Date().toISOString(),
      engine: { name: "mock" },
      cache_hit: false,
      warnings: []
    }
  };
  return result;
}
```

**Run locally**

```bash
pnpm -C apps/appserver-node i && pnpm -C apps/appserver-node dev
# POST http://localhost:8080/gh/sitefit:1.0.0/solve with contracts examples
```

---

## 2) API (FastAPI) — `/jobs/run|status|result` (in-memory)

**Why mocked in-memory?** Keeps day-1 friction near zero; persistence comes in Stage 2.

**Files**

```
apps/api-fastapi/
  main.py
  models.py      # Pydantic envelopes
  contracts.py   # schema loading helpers (optional)
```

**Key behaviors**

* POST `/jobs/run`: validate **envelope** (`app_id`, `definition`, `version`, `inputs`), materialize defaults, compute `inputs_hash`.
* **Synchronously** call AppServer (for Stage 1 only), store result in a **process dict**, return `202 {job_id}`.
* GET `/jobs/status/{job_id}` → `succeeded|failed`; GET `/jobs/result/{job_id}` → stored result.
* Set/forward `x-correlation-id`.

**`main.py` (trimmed)**

```python
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
import httpx, hashlib, json, uuid, time

APP_SERVER_URL = "http://localhost:8080/gh/{def}:{ver}/solve"
jobs = {}  # in-memory: { job_id: {"status":..., "result":...}}

class RunEnvelope(BaseModel):
    app_id: str
    definition: str
    version: str
    inputs: dict

app = FastAPI()

def norm_hash(payload: dict, definition: str, version: str) -> str:
    normalized = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256((normalized + definition + version).encode()).hexdigest()

@app.post("/jobs/run")
async def run_job(env: RunEnvelope, x_correlation_id: str | None = Header(default=None)):
    cid = x_correlation_id or str(uuid.uuid4())
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "running"}

    # sync call to mock AppServer for Stage 1
    url = APP_SERVER_URL.format(def=env.definition, ver=env.version)
    headers = {"x-correlation-id": cid}
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(url, json=env.inputs, headers=headers)
        if resp.status_code != 200:
            jobs[job_id] = {"status": "failed", "error": resp.json()}
            raise HTTPException(status_code=resp.status_code, detail=resp.json())
        jobs[job_id] = {"status": "succeeded", "result": resp.json()}
        return {"job_id": job_id}
    except httpx.RequestError as e:
        jobs[job_id] = {"status": "failed", "error": str(e)}
        raise HTTPException(status_code=504, detail="AppServer unreachable")

@app.get("/jobs/status/{job_id}")
def status(job_id: str):
    j = jobs.get(job_id)
    if not j: raise HTTPException(404, "unknown job_id")
    return {"status": j["status"], "has_result": "result" in j}

@app.get("/jobs/result/{job_id}")
def result(job_id: str):
    j = jobs.get(job_id)
    if not j: raise HTTPException(404, "unknown job_id")
    if j["status"] != "succeeded": raise HTTPException(409, "not ready")
    return j["result"]
```

**Run locally**

```bash
uvicorn apps/api-fastapi.main:app --reload --port 8081
# POST http://localhost:8081/jobs/run with {app_id, definition, version, inputs}
```

---

## 3) Frontend (Next.js) — Minimal form + poll

**Files**

```
apps/frontend/
  pages/index.tsx
  lib/api.ts
```

**Behavior**

* Form fields for the smallest valid input (CRS + two polygons textareas).
* `onSubmit` → POST `/jobs/run` → store `job_id` → poll `/jobs/status` every 1s → fetch `/jobs/result` → render result (e.g., show KPIs and transform).

**`lib/api.ts`**

```ts
export async function runJob(payload: any) {
  const res = await fetch("http://localhost:8081/jobs/run", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

export async function pollStatus(jobId: string) {
  const res = await fetch(`http://localhost:8081/jobs/status/${jobId}`);
  return res.json();
}

export async function getResult(jobId: string) {
  const res = await fetch(`http://localhost:8081/jobs/result/${jobId}`);
  return res.json();
}
```

**`pages/index.tsx` (trimmed)**

```tsx
import { useState, useEffect } from "react";
import { runJob, pollStatus, getResult } from "../lib/api";

export default function Home() {
  const [jobId, setJobId] = useState<string>();
  const [status, setStatus] = useState<string>();
  const [result, setResult] = useState<any>();

  async function onRun() {
    const payload = {
      app_id: "sitefit",
      definition: "sitefit",
      version: "1.0.0",
      inputs: {
        crs: "EPSG:3857",
        geometry: {
          primary: { coordinates: [[[0,0],[10,0],[10,8],[0,8],[0,0]]] },
          secondary:{ coordinates: [[[0,0],[4,0],[4,3],[0,3],[0,0]]] }
        }
      }
    };
    const { job_id } = await runJob(payload);
    setJobId(job_id);
    setStatus("queued");
  }

  useEffect(() => {
    if (!jobId) return;
    const t = setInterval(async () => {
      const s = await pollStatus(jobId);
      setStatus(s.status);
      if (s.status === "succeeded") {
        const r = await getResult(jobId);
        setResult(r);
        clearInterval(t);
      }
    }, 1000);
    return () => clearInterval(t);
  }, [jobId]);

  return (
    <main style={{ padding: 24 }}>
      <button onClick={onRun}>Run mock</button>
      <div>Status: {status || "-"}</div>
      <pre>{result ? JSON.stringify(result, null, 2) : null}</pre>
    </main>
  );
}
```

**Run locally**

```bash
pnpm -C apps/frontend dev
# Open http://localhost:3000
```

---

## 4) Correlation IDs & logging

* API: if request lacks `x-correlation-id`, generate and forward to AppServer; include it in responses.
* AppServer: echo the header back; log per-request with `cid`, `definition@version`.

**Minimal logger hint (Node)**

```ts
console.log(JSON.stringify({ level:"info", cid, def, ver, event:"solve.start" }));
```

---

## 5) Tests (mock e2e)

**Files**

```
tests-e2e/api/mock_roundtrip.test.ts
```

**What to test**

* **Happy path**: POST `/jobs/run` with a **valid example** → status becomes `succeeded` → result validates against `outputs.schema.json`.
* **Invalid input**: missing required field → API returns `400` and never calls AppServer.
* **Error propagation**: force AppServer to return `400` → API returns 4xx and `status=failed`.

(Use your preferred test runner; even a Python `pytest` with `httpx` is fine.)

---

## 6) Developer ergonomics

* **Makefile / Taskfile**

  ```make
  dev-appserver:
  	pnpm -C apps/appserver-node dev
  dev-api:
  	uvicorn apps/api-fastapi.main:app --reload --port 8081
  dev-frontend:
  	pnpm -C apps/frontend dev
  dev-all:
  	tmux new-session \; \
  	send-keys 'make dev-appserver' C-m \; \
  	split-window -h 'make dev-api' \; \
  	split-window -v 'make dev-frontend' \;
  ```
* **.env.sample** for API base URLs.
* **Pre-commit**: JSON lint for contracts, TypeScript/Ruff linters.

---

## 7) Common pitfalls (and how to avoid them)

* **Schema drift**: always import `inputs.schema.json`/`outputs.schema.json` from `contracts/`, never retype shapes by hand.
* **Loose validation**: `additionalProperties: false` at the right levels; reject unknown fields early.
* **Inconsistent units/CRS**: document in schema `description`; include units in outputs metadata.
* **Blocking behavior**: Stage 1 uses a synchronous call to AppServer *only* for the mock; don’t carry this pattern to Stage 2 (queue + worker).

---

## 8) Exit checklist (Stage 1)

* [ ] AppServer validates inputs & outputs; returns deterministic mock.
* [ ] API exposes `/jobs/run|status|result`; synchronous mock call works.
* [ ] Frontend form triggers a run and renders results.
* [ ] One e2e test passes using a `contracts/.../examples/valid/*.json`.
* [ ] Correlation IDs flow through responses & logs.

---

With this in place, Stage 2 is a small refactor: keep the same endpoints and contracts, but replace the API’s **sync call** with **enqueue to Service Bus** and have the Worker consume and call the AppServer.
