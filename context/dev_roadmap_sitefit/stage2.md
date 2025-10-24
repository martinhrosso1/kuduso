**Stage 2 — Cloud Infrastructure (OpenTofu/Terragrunt)** 

Practical guide to **Stage 2 — Cloud Infrastructure (OpenTofu/Terragrunt)** in the *platform vs. app* split you chose. The goal is to stand up everything you’ll need for Stage 3 code to run against: **ACA env, Service Bus (namespace + per-app queue shells), Key Vault, Storage, Log Analytics, ACR, Supabase, AppServer, and a dev Rhino VM**—all reproducibly with IaC.


* **Platform (shared, 1× per env)**
  RG, **ACR**, **Log Analytics**, **Key Vault**, **Storage (Blob)**, **Service Bus namespace**, **ACA environment**, **AppServer (internal)**, **Rhino Compute dev VM** (public IP locked down).
* **Per-app (sitefit)**
  **Service Bus queue**, **API app (external)** and **Worker app (internal)** deployed to ACA with identities and secret refs (Worker min=0).
* **Supabase** (DB+Auth) created and its `DATABASE_URL`, JWKS URL stored in **Key Vault**.
* **Logs** land in Log Analytics; **secrets** are read from Key Vault; **images** pulled from ACR.

---

# 2.1 Repo infra layout (recap)

```
infra/
  modules/
    shared-core/          # RG, ACR, LAW, KV, Storage, SB namespace, ACA env
    shared-appserver/     # ACA: AppServer (internal), roles, secret refs
    app-stack/            # ACA: API (ext), Worker (int), SB queue, KEDA
    rhino-vm/             # dev-only Windows VM + NSG
    # later: rhino-vmss-ilb/, network/, dns/
  live/
    dev/
      shared/
        core/             # -> modules/shared-core
        rhino/            # -> modules/rhino-vm
        appserver/        # -> modules/shared-appserver
      apps/
        sitefit/          # -> modules/app-stack
    # prod/ mirrors dev/
terragrunt.hcl            # root: state, providers, tags
```

> Terragrunt glues modules with dependencies so `run-all apply` brings them up in the right order.

---

# 2.2 Order of operations (dev environment)

1. **shared/core** → 2) **push images to ACR** → 3) **shared/rhino** → 4) **shared/appserver** → 5) **apps/sitefit**

---

# 2.3 Module contracts (inputs/outputs)

## `shared-core` (once per env)

* **Inputs:** `name_prefix`, `location`, `tags`
* **Creates:** RG, ACR, LAW, KV, Storage (+ container `artifacts`), SB namespace, ACA environment
* **Outputs:** `resource_group_name`, `acr_server`, `kv_id`, `kv_name`, `sb_namespace_name`, `storage_account_name`, `acaenv_id`

## `shared-appserver`

* **Inputs:** `core_rg_name`, `acr_server`, `acaenv_id`, `kv_name`, `image`, `contracts_dir`, `use_compute`, `compute_url`, `compute_api_key_kv_secret_name`
* **Creates:** ACA internal app (**AppServer**) with Managed Identity, secret refs, ACR pull
* **Outputs:** `appserver_internal_fqdn`, `principal_id`

## `app-stack` (per app)

* **Inputs:** `app_id`, `core_rg_name`, `acr_server`, `acaenv_id`, `kv_name`, `sb_namespace_name`, `storage_account`, images, queue name, env vars, KV secret names
* **Creates:** SB **queue**, ACA **API (external)** + **Worker (internal)** with KEDA scaler, MI, secret refs, ACR pull
* **Outputs:** `api_fqdn`, `queue_name`, `api_principal_id`, `worker_principal_id`

## `rhino-vm` (dev only)

* **Inputs:** `resource_group`, `name_prefix`, `location`, `allowed_source_ip`, `vm_size`
* **Creates:** Windows VM, Public IP, NSG (80/8081 inbound only from allowed IP)
* **Outputs:** `public_ip`

---

# 2.4 Terragrunt files (essentials)

## Root `infra/terragrunt.hcl`

* Sets **azurerm** provider, remote state in Azure Storage, global `tags`.

## `live/dev/shared/core/terragrunt.hcl`

* `source = ../../../modules/shared-core`
* Inputs: `name_prefix="kuduso-dev"`, `location="westeurope"`

## `live/dev/shared/rhino/terragrunt.hcl`

* Depends on **core** (for RG)
* Inputs: `allowed_source_ip = ${env.MY_IP}` → lock down the VM

## `live/dev/shared/appserver/terragrunt.hcl`

* Depends on **core** and **rhino**
* Inputs:
  `image = "<acr>/appserver-node:${env.IMG_SHA}"`,
  `use_compute=false` (flip later),
  `compute_url = "http://<rhino_public_ip>:8081/"`,
  `compute_api_key_kv_secret_name="COMPUTE-API-KEY"`

## `live/dev/apps/sitefit/terragrunt.hcl`

* Depends on **core** and **appserver**
* Inputs:
  `api_image="<acr>/api-fastapi:${env.IMG_SHA}"`,
  `worker_image="<acr>/worker-fastapi:${env.IMG_SHA}"`,
  `queue_name="jobs-sitefit"`,
  `appserver_url="http://aca-appserver.internal/gh/{def}:{ver}/solve"`,
  KV secret names: `DATABASE-URL`, `SERVICEBUS-CONN`, `BLOB-SAS-SIGNING`

---

# 2.5 Supabase (DB + Auth)

* Create manually in the Supabase UI now (fast).

**Minimum you need for Stage 2 outputs:**

* `DATABASE_URL` (service role or privileged URL for the API/Worker)
* `JWT_JWKS_URL` (for API to verify user tokens)

**Store both in Key Vault** (`DATABASE-URL` secret; JWKS URL as plain env var in `app-stack` module).

> **Schema/RLS:** DO NOT model tables in TF. Keep migrations (DDL/RLS/seed) in your app repo and run them from CI once `DATABASE_URL` is live.

---

# 2.6 Secrets model (Stage 2)

Create in **Key Vault** (once per env):

* `DATABASE-URL` → Supabase connection string
* `SERVICEBUS-CONN` → (Stage 2: connection string; later switch to RBAC/MI)
* `BLOB-SAS-SIGNING` → Storage account key (or use MI + user delegation SAS later)
* `COMPUTE-API-KEY` → For Rhino.Compute

The modules reference them via **ACA KeyVaultRef**:

```
secret { name="database-url" value="keyvaultref://<kv-name>/secrets/DATABASE-URL" }
```

and map to env:

```
env { name="DATABASE_URL" secret_name="database-url" }
```

Each Container App gets **system-assigned identity**; modules grant **AcrPull** and **Key Vault Secrets User** roles.

---

# 2.7 KEDA scaler (Worker)

In `app-stack` the Worker template includes:

* `min_replicas = 0`, `max_replicas = <<= Rhino seats>`
* **Scale rule** type `azure-servicebus` on the **per-app queue**, e.g.:

  * `metadata: { namespace=<sb_ns>, queueName=<queue>, messageCount="5" }`
  * `auth: { secret_name="servicebus-conn", trigger_parameter="connection" }`

> Later you can switch to **Managed Identity** auth on Premium SB; adjust the scaler accordingly.

---

# 2.8 Build & push images

After **shared/core** creates ACR:

```bash
GIT_SHA=$(git rev-parse --short HEAD)
ACR=$(terragrunt -chdir=infra/live/dev/shared/core output -raw acr_server)

docker build -t $ACR/appserver-node:$GIT_SHA ./shared/appserver-node
docker build -t $ACR/api-fastapi:$GIT_SHA     ./apps/sitefit/api-fastapi
docker build -t $ACR/worker-fastapi:$GIT_SHA  ./apps/sitefit/worker-fastapi

az acr login -n ${ACR%%.*}
docker push $ACR/appserver-node:$GIT_SHA
docker push $ACR/api-fastapi:$GIT_SHA
docker push $ACR/worker-fastapi:$GIT_SHA

export IMG_SHA=$GIT_SHA
```

---

# 2.9 Apply (dev)

```bash
# optional: prep KV secrets first, or do it between steps below
cd infra/live/dev

# 1) Platform core
terragrunt run-all apply --terragrunt-include-dir shared/core

# 2) Add secrets to Key Vault (from outputs/known values)
KV=$(terragrunt -chdir=shared/core output -raw kv_name)
az keyvault secret set --vault-name $KV --name DATABASE-URL     --value "<supabase-url>"
az keyvault secret set --vault-name $KV --name SERVICEBUS-CONN  --value "Endpoint=sb://..."
az keyvault secret set --vault-name $KV --name BLOB-SAS-SIGNING --value "<storage-key>"
az keyvault secret set --vault-name $KV --name COMPUTE-API-KEY  --value "<rhino-key>"

# 3) Rhino VM (dev)
MY_IP=$(curl -s ifconfig.me)/32
export MY_IP
terragrunt run-all apply --terragrunt-include-dir shared/rhino

# 4) AppServer (internal)
export IMG_SHA
terragrunt run-all apply --terragrunt-include-dir shared/appserver

# 5) Sitefit app (API + Worker + Queue)
terragrunt run-all apply --terragrunt-include-dir apps/sitefit
```

---

# 2.10 Verifications (infra-only smoke)

* **ACA env:** exists; three apps deployed (AppServer internal, API external, Worker internal).
* **Service Bus:** namespace exists; **queue `jobs-sitefit`** exists; DLQ enabled.
* **Key Vault:** secrets are present; API/Worker/AppServer identities have **Key Vault Secrets User**.
* **ACR pulls:** all container apps run with images from your ACR.
* **Storage:** account + container `artifacts` exist.
* **Logs:** see ACA logs in **Log Analytics** (ContainerAppConsoleLogs_CL).
* **Rhino VM:** reachable on `http://<public_ip>:8081/` only from your IP (you’ll point AppServer later).

> At this point, **no business traffic** yet—Stage 3 turns on the code paths that use SB + Supabase with the **mock** compute.

---

# 2.11 Security & minimum hardening (Stage 2)

* **Ingress**: API **external**, AppServer/Worker **internal-only**.
* **CORS**: API limited to your Vercel domains (configure later in app).
* **Secrets**: only in Key Vault; never inline in Terragrunt inputs.
* **RBAC**: identities have only **AcrPull** + **KV Secrets User**; nothing more.
* **Rhino VM**: NSG allows 80/8081 only from `MY_IP` (or your NAT egress); API key set.
* **Quota caps**: in `app-stack`, set Worker `max_replicas` ≤ Rhino seats.

---

# 2.12 Cost guardrails

* **Worker** `min=0`.
* **AppServer** `min=1` (or 0 if okay with cold starts).
* **Log Analytics** retention 30d; set a daily cap.
* **SB** Standard tier.
* **Storage** LRS; no premium needed.

---

# 2.13 Common pitfalls

* **Secrets in state**: don’t pass raw secrets to modules—write to KV then reference `keyvaultref://`.
* **Unbounded worker scale**: cap `max_replicas`; keep KEDA threshold sensible (`messageCount=5–20`).
* **Forgetting identities/RBAC**: ensure each Container App has **system-assigned identity** and gets **AcrPull** + **KV Secrets User**.
* **Rhino wide-open**: keep NSG tight; later move to **VMSS + ILB** (no public IP).

---

# 2.14 Handoff to Stage 3

With infra live:

* Put `NEXT_PUBLIC_API_BASE_URL` (from `apps/sitefit.api_fqdn`) into your frontend env.
* Configure **API** and **Worker** app settings (already templated in `app-stack`):
  `SERVICEBUS_QUEUE`, `SERVICEBUS_CONN` (or MI later), `DATABASE_URL`, `BLOB_SAS_SIGNING`, `APP_SERVER_URL`, `JWT_JWKS_URL`.
* Stage 3 will:

  * flip API from local/in-memory → **enqueue to SB** and **write to Supabase**,
  * start Worker (scale from 0) to consume queue and call **AppServer (mock)**,
  * use **Blob SAS** for artifacts.

---

### TL;DR

Stage 2 gives you a **running cloud platform + app shells** with **OpenTofu/Terragrunt**: ACA env, SB ns + app queue, KV, Storage, ACR, Log Analytics, AppServer (internal), Rhino dev VM, and Supabase wired via KV. Nothing else in your code changes yet—Stage 3 simply switches the code to use this infra while still mocking compute.
