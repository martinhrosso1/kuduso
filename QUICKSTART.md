# Quick Start Guide

## Prerequisites

- Node.js 18+ (for AppServer and Frontend)
- Python 3.11+ (for API)

## Installation

```bash
# Install all dependencies (this will create .venv automatically)
make install
```

This will:
1. Create a Python virtual environment at `.venv/`
2. Install Node.js dependencies for contracts, AppServer, and Frontend
3. Install Python dependencies for API and tests

## Running the Services

### Option 1: Background Mode (Recommended - No tmux required)

```bash
# Start all services in background
make dev-simple
```

This starts all three services in the background and shows:
- Service URLs and PIDs
- Log file locations
- How to stop services

**Check status:**
```bash
make status
```

**View logs:**
```bash
# All logs
make logs

# Or individual logs
tail -f /tmp/kuduso-appserver.log
tail -f /tmp/kuduso-api.log
tail -f /tmp/kuduso-frontend.log
```

**Stop services:**
```bash
make stop
```

### Option 2: Individual Terminals

Open 3 separate terminals and run:

**Terminal 1 - AppServer:**
```bash
make dev-appserver
```

**Terminal 2 - API:**
```bash
make dev-api
```

**Terminal 3 - Frontend:**
```bash
make dev-frontend
```

### Option 3: With tmux (if installed)

```bash
# Install tmux first (optional)
sudo apt install tmux

# Start all services in tmux
make dev
```

## Using the App

1. Open http://localhost:3000 in your browser
2. Adjust CRS or seed if desired (defaults: EPSG:5514, seed 42)
3. Click **"Run Placement"**
4. View the results:
   - Rotation and translation transforms
   - Quality score
   - Metrics (area, distance, etc.)
   - Full JSON output

## Testing

```bash
# Run all tests (contracts + e2e)
make test

# Run only e2e tests
make test-e2e

# Run only contract validation
make contracts-validate
```

**Note:** E2E tests require all services to be running!

## Service Endpoints

- **Frontend**: http://localhost:3000
- **API**: http://localhost:8081
  - Health: http://localhost:8081/health
  - Docs: http://localhost:8081/docs
- **AppServer**: http://localhost:8080
  - Health: http://localhost:8080/health

## Common Commands

```bash
make help              # Show all available commands
make install           # Install all dependencies
make dev-simple        # Start all services (background)
make status            # Check service status
make logs              # View all logs
make stop              # Stop all services
make test              # Run all tests
make clean             # Clean build artifacts
```

## Troubleshooting

### uvicorn not found
Make sure you ran `make install` first. This creates the virtual environment and installs all Python dependencies.

### Port already in use
The `make dev-simple` command automatically stops existing services and clears ports. But if you need to manually clear:
```bash
make kill-ports
```

### Services not starting
Check logs:
```bash
tail -f /tmp/kuduso-*.log
```

### Clean restart
```bash
make stop
make clean
make install
make dev-simple
```

## Next Steps

- Read [STAGE1_COMPLETE.md](./STAGE1_COMPLETE.md) for detailed documentation
- Explore the code in `shared/appserver-node/`, `apps/sitefit/api-fastapi/`, and `apps/sitefit/frontend/`
- Check out the contract schemas in `contracts/sitefit/1.0.0/`
- Run the E2E tests with `make test-e2e`
