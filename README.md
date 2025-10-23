# Kuduso

> A platform for building web apps that turn user inputs into 2D/3D geometry, descriptive documents, or decision-ready insights.

## Overview

Kuduso standardizes the flow from validated frontend parameters to reproducible backend computes, offering both instant previews and authoritative batch runs. Under the hood, Kuduso is powered by **Rhino.Compute** and **Grasshopper**, wrapped in contract-driven services.

## Architecture

**Flow:** Next.js (Vercel) → API (FastAPI/ACA) → Azure Service Bus → Worker (ACA) → AppServer (Node/ACA) → Rhino.Compute (Windows VMSS) → Supabase DB + Azure Blob Storage

**Tech Stack:**
- **Frontend**: Next.js on Vercel
- **API**: FastAPI on Azure Container Apps (external)
- **Worker**: FastAPI on Azure Container Apps (internal)
- **AppServer**: Node.js on Azure Container Apps (internal)
- **Messaging**: Azure Service Bus
- **Compute**: Rhino.Compute on Windows VMSS
- **Database**: Supabase (Postgres + PostGIS + RLS)
- **Storage**: Azure Blob Storage
- **Secrets**: Azure Key Vault
- **Observability**: Azure Monitor / Log Analytics

## Monorepo Structure

```
kuduso/
├── contracts/          # Contract definitions (source of truth)
│   ├── sitefit/1.0.0/ # Example: SiteFit app contracts
│   ├── _templates/    # Templates for new contracts
│   └── scripts/       # Validation tooling
├── apps/               # Individual web applications
│   └── sitefit/       # SiteFit MVP
│       ├── frontend/  # Next.js (Vercel)
│       ├── api-fastapi/   # External API + Service Bus producer
│       └── worker-fastapi/ # Worker (Service Bus consumer)
├── shared/             # Shared services
│   └── appserver-node/ # Internal AppServer (schema validation, GH routing)
├── infra/              # Infrastructure as Code
│   ├── modules/       # Terraform modules
│   └── live/          # Terragrunt environments (dev/prod)
├── packages/           # Shared libraries
│   ├── ts-sdk/        # TypeScript client SDK
│   ├── py-sdk/        # Python client SDK
│   └── util-geometry/ # Geometry utilities
├── tests-e2e/          # End-to-end tests
│   ├── api/           # API integration tests
│   └── ui/            # UI journey tests
├── .github/workflows/  # CI/CD pipelines
└── context/            # AI development context
```

## Current Status: Stage 1 Complete ✅

**Stage 1 - Mocked Compute Loop** is complete. All three services (AppServer, API, Frontend) are running with contract validation and mock results.

See **[STAGE1_COMPLETE.md](./STAGE1_COMPLETE.md)** for full details.

### What's Ready
- ✅ **Stage 0**: Contract schemas and validation
- ✅ **Stage 1**: Full mock compute loop
  - AppServer (Node.js) with contract validation
  - API (FastAPI) with job endpoints
  - Frontend (Next.js) with polling UI
  - E2E tests passing
  - Correlation ID tracking
  - Development tooling (Makefile)

### Next: Stage 2
**Messaging & Persistence** - Replace sync calls with Service Bus + Database

## Getting Started

### Prerequisites
- Node.js 18+ (for AppServer and validation)
- Python 3.11+ (for API and Worker)
- Docker (for local Postgres/Supabase)
- Terraform + Terragrunt (for infrastructure)

### Quick Start

```bash
# Install all dependencies
make install

# Validate contracts
make contracts-validate

# Start all services (requires tmux)
make dev

# Or start services individually:
make dev-appserver  # Port 8080
make dev-api        # Port 8081
make dev-frontend   # Port 3000

# Run tests
make test
```

Then open http://localhost:3000 to use the app.

## Documentation

- **Project Context**: [context/kuduso_context.md](./context/kuduso_context.md)
- **Dev Principles**: [context/dev_principles_mvp.md](./context/dev_principles_mvp.md)
- **Implementation Roadmap**: [context/dev_roadmap_sitefit/roadmap.md](./context/dev_roadmap_sitefit/roadmap.md)
- **Contracts Guide**: [contracts/README.md](./contracts/README.md)
- **Stage 0 Completion**: [STAGE0_COMPLETE.md](./STAGE0_COMPLETE.md)
- **Stage 1 Completion**: [STAGE1_COMPLETE.md](./STAGE1_COMPLETE.md)

## Development Workflow

### Contracts First
All new apps start with contract definitions:
1. Define inputs/outputs schemas (JSON Schema)
2. Create bindings for compute engine
3. Set operational limits (manifest)
4. Add example payloads
5. Validate with `make contracts-validate`

### Build & Deploy
1. Implement services (API, Worker, AppServer)
2. Write tests (unit, integration, e2e)
3. Deploy infrastructure (Terraform/Terragrunt)
4. Deploy applications (Container Apps)

## Apps

### SiteFit (MVP)
Places a house footprint onto a land parcel under geometric and spatial constraints.

**Status**: Stage 1 complete (mock compute loop working)  
**Contract**: [contracts/sitefit/1.0.0/](./contracts/sitefit/1.0.0/)  
**Services**:
- AppServer: `shared/appserver-node/` (port 8080)
- API: `apps/sitefit/api-fastapi/` (port 8081)
- Frontend: `apps/sitefit/frontend/` (port 3000)

**Try it**: `make dev` then open http://localhost:3000

## Contributing

This is currently a private project. All development follows the roadmap in `context/dev_roadmap_sitefit/`.

## License

Proprietary - All rights reserved

---

**Built with Windsurf AI Assistant**
