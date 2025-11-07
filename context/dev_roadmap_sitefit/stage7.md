# Stage 7 — Frontend UX Polish

Stage 7 is where the app stops feeling like a tech demo and starts feeling like a product. Below is a concrete plan for polishing the **frontend UX** for your house-fit MVP, tuned to your stack (Next.js + Vercel, FastAPI API, artifacts via Blob SAS, contracts in JSON Schema).

---

# 7.1 Core UX goals

* **Clarity**: users always know *what to do next* and *what’s happening now*.
* **Speed feel**: snappy forms, instant feedback, skeletons while loading.
* **Trust**: inputs validated client-side against the same contracts, errors are human.
* **Delight**: clean 2D/3D viewers, useful KPIs, easy export/share.

---

# 7.2 Page & component map (Next.js App Router)

```
/ (Home)                      – product value, CTA “Start a placement”
/app/sitefit/new              – Run form (parcel/house upload or draw), live validation
/app/sitefit/runs/[jobId]     – Status → Result page (timeline, preview, artifacts)
/app/sitefit/history          – Recent runs (tenant-scoped)
/legal/{privacy,terms}        – basics
```

**Key components**

* `RunForm` – JSON-schema-driven inputs + CRS hint; supports file drop (GeoJSON) or draw mode.
* `RunButton` – creates job; shows queued → running state instantly.
* `JobStatusCard` – queued/running/succeeded/failed with ETA & tips.
* `ResultKPIs` – compact numbers (score, area, coverage, setbacks, etc.).
* `Viewer2D` – parcel/house overlay (Canvas/SVG/MapLibre).
* `Viewer3D` – glTF viewer (Three.js) with orbit controls.
* `ArtifactsList` – download/open links (SAS), with expiry countdown.
* `ToastCenter` – toasts for validation, job created, errors.
* `EmptyState` – if no runs yet.

Use Tailwind + shadcn/ui for consistency (Cards, Button, Tabs, Skeleton, Toast).

---

# 7.3 Input UX (contracts-first)

**Validate on the client using the exact JSON Schemas**

* Generate TS types + validators from `contracts/.../inputs.schema.json` (e.g., via `ajv` compiled at build or `typescript-json-schema`).
* **Inline validation** with clear, human messages:

  * CRS pattern (`^EPSG:\d+$`)
  * Closed polygon, no self-intersections, min vertices
  * Bounds on rotation `{min,max,step}`, `grid_step >= 0.1`
* **Help text & examples**: one click to load `examples/valid/minimal.json`.

**Data entry modes**

* Upload **GeoJSON** (drag & drop) OR draw with a simple 2D editor:

  * Draw polygon for parcel, polygon for house footprint.
  * Snap & close polygon; show perimeter/area as you draw.
* Auto-detect CRS of uploaded GeoJSON; if missing, ask user (dropdown).
* Show a tiny **CRS caution**: “All coordinates assumed in meters (EPSG:xxxx).”

**Nice touch**: pre-check with a local “feasibility quick check” (client-side) before enqueue (e.g., obvious containment impossibilities) and explain why.

---

# 7.4 Job flow (batch run)

**After submit**

* Immediately route to `/app/sitefit/runs/[jobId]` with:

  * **Status banner** (queued → running → succeeded/failed)
  * **Skeleton loaders** for KPIs & viewers
  * **Copy link** button (deep link to this run)

**Polling**

* Start at 1s interval, back off to 2/3/5s.
* Stop when `succeeded|failed|expired`.
* Show a small “this may take ~X sec” tip on first run.

**Status timeline**

* “Queued at 16:02” → “Started at 16:02” → “Finished at 16:03”
* If retried: “Retry 1/5 after brief backoff”

**Failure UX**

* Friendly summary + technical details accordion.
* Offer to “Open inputs JSON” (readonly) and “Duplicate & edit”.

---

# 7.5 Results UX

**KPIs panel (top-left)**

* Score (big), coverage %, yard area m², setbacks OK?, orientation deg.
* Sparkline (optional) if you compute sampled candidates.

**2D viewer**

* Show parcel outline + placed house footprint.
* Toggle original vs placed, label offsets/rotation.
* Export PNG/SVG of the plan.
* If you use MapLibre, keep metric projection if possible; otherwise a neutral Canvas/SVG is simpler for non-geo CRS.

**3D viewer (optional for MVP)**

* If glTF present: Three.js viewer with orbit controls and fit-to-bounds.
* Buttons: “Reset view”, “Download glTF”.

**Artifacts list**

* Each item: kind (GeoJSON|glTF|PDF), size, **SAS expires in** (countdown), “Open” / “Download”.
* Regenerate link if expired (hit the API to re-mint SAS).

**Share**

* Copy run link with small preview image (OG tags).

---

# 7.6 Performance polish

* **Skeletons** everywhere rather than spinners.
* **Client-side caching** by `jobId` with SWR/React Query (stale-while-revalidate).
* **Debounced** re-renders for viewer interactions.
* Only fetch heavy artifacts on demand (lazy “Load 3D”).
* Use **gzip/br** and set long-cache for static assets; `Cache-Control` on artifacts is fine (they have SAS and expiry).
* Keep GeoJSON under control: simplify display geometry (keep raw in artifacts).

---

# 7.7 Accessibility & i18n

* Proper roles/labels on form controls; error text ties to fields via `aria-describedby`.
* Keyboard: form, tabs, viewer focus rings; WASD or arrow support in viewer optional.
* Color contrast AA; avoid color-only signals (use icons/text).
* **i18n:** use `next-intl` or `next-i18next`, prepare Slovak/English bundles (you’ve been bilingual). Put all field labels, help text, and error messages in translations.

---

# 7.8 Analytics (privacy-sane)

* Fire events (GA4/GTM) on:

  * `run_submit` with small payload: `{app_id, has_geojson, rotation_step, grid_step}` (no PII, no raw geometry)
  * `run_status_change` with `{job_id, status, latency_ms}`
  * `artifact_open` with `{kind}`
* Respect Consent Mode; allow opting out in the UI.

---

# 7.9 Error vocabulary (human first)

Map technical errors to plain language:

* `SCHEMA_INVALID` → “Some inputs look off. Check highlighted fields.”
* `DOMAIN_INVALID` → “The shape isn’t valid (must be closed/planar).”
* `RATE_LIMIT` → “Too many runs right now, try again in a moment.”
* `TIMEOUT` → “This attempt ran too long. Try smaller grid or rotation step.”
* `UPSTREAM_UNAVAILABLE` → “The geometry engine is busy; we’ll retry.”

Show **“What to try next”** under each message.

---

# 7.10 Code patterns (snippets)

**Polling hook (React Query)**

```ts
import { useQuery } from "@tanstack/react-query";

export function useJob(jobId: string) {
  return useQuery({
    queryKey: ["job", jobId],
    queryFn: async () => {
      const r = await fetch(`/api/proxy/jobs/status/${jobId}`);
      if (!r.ok) throw new Error("status");
      return r.json();
    },
    refetchInterval: (data) => {
      if (!data) return 1000;
      if (["succeeded","failed"].includes(data.status)) return false;
      return 2000;
    },
  });
}
```

**Schema-driven form (react-hook-form + Ajv)**

```ts
import Ajv from "ajv";
import addFormats from "ajv-formats";
import { useForm } from "react-hook-form";

const ajv = addFormats(new Ajv({ allErrors: true, strict: false }));
const validate = ajv.compile(inputsSchema);

export function useSchemaForm() {
  const form = useForm({ mode: "onChange" });
  const onValidate = (values:any) => {
    const ok = validate(values);
    return { ok, errors: validate.errors ?? [] };
  };
  return { form, onValidate };
}
```

**2D overlay (Canvas idea)**

* Precompute screen coords, draw parcel (thick stroke) and placed house (filled).
* Add a mini legend and north arrow (even if arbitrary) for user orientation.

---

# 7.11 “Nice next” after MVP polish

* **History & compare**: choose two runs, overlay results, compare KPIs.
* **Preset templates**: typical parcels/houses, one-click demos.
* **Inline “quick retry”**: adjust rotation step/grid step and rerun from result page.
* **Download report (PDF)**: KPIs + plan snapshot + metadata (contract version, seed).
* **Autosave form** in localStorage.

---

# 7.12 Quality checklist (acceptance for Stage 7)

* [ ] Form validates against **contracts**; field errors are human.
* [ ] After submit, user sees status immediately and never wonders “what now?”
* [ ] Result page shows **KPIs + 2D overlay**; heavy viewers load on demand.
* [ ] Artifacts open/download; SAS expiry is visible and re-mint works.
* [ ] Copy link works; opening the link reconstructs state without the form.
* [ ] A11y basics pass (keyboard, labels, contrast).
* [ ] i18n works for SK/EN.
* [ ] Analytics events fire (consent-aware).
* [ ] No console errors; lighthouse score ≥ 90 on desktop.

---

## TL;DR

Make the form schema-driven, errors human, and progress obvious. Use skeletons, smart polling, and crisp KPIs. Keep displays lightweight (2D first, 3D on demand). Provide shareable links, artifact handling with expiry, a11y/i18n basics, and a tiny analytics layer. This turns your working pipeline into a product people enjoy using and trust.
