# Stage 8 — Preview Lane

Blueprint for **Stage 8 — Preview Lane** that lets users drag sliders and see near-instant visual feedback **without** disturbing the batch lane.

---

# 8.1 What “preview” really is

A **best-effort, low-latency** compute path optimized for interaction (sub-second), not for authoritative results. It trades exactness for speed, applies strict limits, and is **isolated** from batch so it can never clog production runs.

---

# 8.2 Architecture (lane split)

* **Frontend (Next.js)**
  Sliders/inputs fire **debounced** preview requests over **WebSocket or SSE** and render returned **deltas** (transform + KPIs). The batch “Run” button still posts to `/jobs/run`.

* **API (FastAPI)**

  * Exposes `/preview/connect` (WS or SSE) and `/preview/{def}:{ver}` (HTTP fallback).
  * Implements **per-tenant rate limit** + **concurrency caps** (tiny).
  * Forwards preview calls to **AppServer** with a **short timeout** (e.g., 400–800 ms).
  * Enforces **token → tenant** mapping; carries `x-correlation-id`.

* **AppServer (Node)**

  * New endpoint: `/preview/{def}:{ver}`.
  * **Strict guardrails**: timebox, input **discretization**, tiny **semaphore** (reserved seats), **LRU cache**.
  * Returns **deltas** (pose/score/KPIs), not heavy geometry.
  * Calls Rhino.Compute only if **cache miss** and within the timebox.

* **Rhino.Compute (VM/VMSS)**

  * A **reserved fraction** of total seats (e.g., 1 out of 4) for preview.
  * Same GH definition, but **fast path** recipe (lightweight graph branch if available).

**QoS separation:**

* Different **semaphores** in AppServer: `previewSeats` vs `batchSeats`.
* If preview exhausted → **immediate 429** (don’t queue).
* If preview calls exceed budget, they **fail fast**; batch is unaffected.

---

# 8.3 Data contracts

## Preview request (client → API → AppServer)

```json
{
  "app_id": "sitefit",
  "definition": "sitefit",
  "version": "1.0.0",
  "inputs": {
    "parcel": {...},
    "house": {...},
    "rotation": {"theta": 37.3},
    "translation": {"x": 1.2, "y": -0.4},
    "seed": 123
  }
}
```

## Discretization (AppServer)

Before hashing/caching, **snap** inputs so nearby slider ticks coalesce:

* `theta` → round to 1–2° (configurable)
* `x,y` → round to 0.1–0.25 m
* Drop non-essential fields; clamp to caps

`preview_key = sha256(json.dumps(discretized_inputs, sort_keys=True))`

## Preview response (deltas)

```json
{
  "delta": {
    "transform": { "theta": 36, "dx": 1.25, "dy": -0.5 },  // snapped pose
    "kpis": { "score": 0.82, "coverage_pct": 55.1, "yard_m2": 124.3 },
    "quality": "approx|cached|fresh"
  },
  "expires_at": "2025-11-06T16:10:00Z"
}
```

* Keep it **tiny**. For visuals, the FE applies the transform to the **already-loaded footprint**; heavy meshes stay out of band.

---

# 8.4 API layer: transport & throttling

* **Choose transport**

  * **SSE** (Server-Sent Events): simple, one-way push, great for many clients.
  * **WebSocket**: bi-directional; useful if you’ll add multi-user or cursor sync later.
  * Keep an **HTTP POST fallback** for environments that block WS/SSE.

* **Client cadence**

  * Debounce **on input** (e.g., 120–200 ms).
  * If a new request arrives, **cancel the in-flight** (client-side abort + server checks `AbortSignal`).

* **Rate limits (API)**

  * Token bucket per **tenant**: e.g., 10 req/s burst 20, enforced per connection.
  * **1–2 in-flight** preview requests per client; reject extra with `429`.

* **Timeouts**

  * API → AppServer: **hard deadline** 400–600 ms (config).
  * If exceeded, return last cached delta if available; else return a **hint** (`“preview busy; try slower drag”`).

---

# 8.5 AppServer: performance core

* **Semaphore**: `previewSeats = 1` (or 20–25% of seats). Try-acquire; if fail → `429` instantly.

* **LRU cache**:

  * Size: 1–5k entries (few MB).
  * TTL: 2–10 minutes (sliders often revisit nearby states).
  * Key: **discretized** inputs.
  * Value: **delta** (transform + KPIs).
  * On hit: return immediately (`quality: "cached"` in response).

* **Short-circuit** routes

  * **Heuristics first**: if trivial math can estimate KPIs/placement, do it server-side (no Rhino call).
  * **Compute call** only on **cache miss** and **seat available**.

* **Timebox**

  * Use `AbortSignal.timeout(PREVIEW_TIMEOUT_MS)` on the `/grasshopper` request.
  * If timer fires, **cancel request**, release seat, return the **last known cached** delta if any; else `204` with no delta.

* **Discretization strategy**

  * Choose snapping that matches slider steps (θ step 1–2°, dx/dy step 0.1–0.25 m).
  * Optional: **adaptive** snapping by zoom level (coarser when far, finer when close).

* **Micro-batching (optional)**

  * If 2+ identical preview requests arrive within 10–30 ms, coalesce to one Compute call and multicast result.

---

# 8.6 Rhino/Grasshopper tips for speed

* **Fast branch** in GH**:** Toggle a boolean “preview mode” that:

  * Uses simplified geometry (meshes, polylines).
  * Skips expensive analysis.
  * Limits candidate sampling to 1–3 checks (vs. full grid in batch).
* Avoid file IO; avoid plugins with heavy initialization.
* Keep the footprint primitive (polyline) resident in memory; only re-evaluate dependent nodes.

---

# 8.7 Frontend UX patterns

* **Optimistic transform** while waiting: apply the snapped pose locally, then reconcile when delta arrives (maybe tweak KPI numbers).
* **Latency masking**:

  * Show **tiny “lightning” badge** when response is cached.
  * **Skeleton KPI** until first delta; subsequent deltas cross-fade numbers.
* **Backoff on pressure**: if you get 429s or timeouts, increase client debounce and/or send updates only on **pointerup** every N frames.

---

# 8.8 Isolation from batch

* Separate **semaphores**: preview can never starve batch.
* Batch Worker replicas can scale independently; preview never enqueues to SB.
* If preview repeatedly fails, **do not** auto-fallback to batch; just instruct the user to release the slider or reduce step size.

---

# 8.9 Security & quotas

* **Auth**: Same Supabase JWT, but preview endpoints might allow **lower role** (read-only).
* **Quotas** (per tenant): max preview connections, req/s, and compute minutes/hour. Return `429` with a friendly message once exceeded.

---

# 8.10 Observability & alerts (preview lane)

* Metrics:

  * Preview p50/p95 latency
  * Cache hit rate (%)
  * 429 rate (%)
  * Timeout rate (%)
  * Seat utilization (preview semaphore occupancy)
* Alerts:

  * p95 > 800 ms for 5 min
  * Cache hit rate < 50% for 10 min
  * 429 > 10% for 10 min

Add a **small panel** in your Stage-6 dashboard for Preview.

---

# 8.11 Failure & fallback logic

* **Compute unavailable** → return last cached delta; if none, send “busy” hint.
* **Timeout** → same; optionally **increase snapping** on next request (server tells client via header/field `suggested_snap={"theta":2,"dx":0.25}`).

---

# 8.12 Minimal pseudo-code

**API (FastAPI SSE example)**

```python
@app.get("/preview/connect")
async def preview_stream(request: Request):
    cid = new_correlation_id()
    async def events():
        async for payload in client_events(request):  # messages from browser
            try:
                resp = await appserver.preview(payload, timeout=0.6)
                yield sse_event("delta", resp, cid)
            except PreviewBusy:
                yield sse_event("hint", {"message":"busy"}, cid)
    return EventSourceResponse(events())
```

**AppServer (Node)**

```ts
const PREVIEW_TIMEOUT_MS = 600;
const seats = new Semaphore(1);
const cache = new LRU({ max: 2000, ttl: 5 * 60_000 });

app.post("/preview/:def::ver", async (req,res) => {
  const key = makePreviewKey(discretize(req.body.inputs));
  const hit = cache.get(key);
  if (hit) return res.json({...hit, quality:"cached"});

  if (!seats.tryAcquire()) return res.status(429).json({hint:"preview capacity"});

  try {
    const delta = await withTimeout(PREVIEW_TIMEOUT_MS, callCompute(req.params, req.body.inputs));
    cache.set(key, delta);
    return res.json({...delta, quality:"fresh"});
  } catch (e) {
    const fallback = cache.get(key);
    if (fallback) return res.json({...fallback, quality:"approx"});
    return res.status(204).end();
  } finally {
    seats.release();
  }
});
```

---

# 8.13 Acceptance criteria (measurable)

* **Latency**: 95% of preview responses < **800 ms** with your dev VM.
* **Protection**: Batch job latency distributions unchanged when users drag sliders.
* **User feel**: Sliders feel “live”; KPIs update smoothly; no UI hitches.
* **Stability**: Under rapid dragging, no memory growth, no unhandled rejections.

---

## TL;DR

Build a **separate, timeboxed preview lane** with WS/SSE to the API, a **discretized + cached** `/preview` on AppServer, and **reserved Rhino seats**. Return **tiny deltas**, not heavy geometry. Debounce on the client, abort in flight, and fail fast with helpful hints. Keep batch isolated and untouched—and hit the **<800 ms** p95 target without sacrificing reliability.
