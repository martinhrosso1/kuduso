# Kuduso Monorepo Makefile
# Quick commands for local development and deployment

.PHONY: help
help: ## Show this help message
	@echo "Kuduso Monorepo Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# Python virtual environment
VENV := .venv
PYTHON := $(shell pwd)/$(VENV)/bin/python
PIP := $(shell pwd)/$(VENV)/bin/pip
UVICORN := $(shell pwd)/$(VENV)/bin/uvicorn
PYTEST := $(shell pwd)/$(VENV)/bin/pytest

# Contract validation
.PHONY: contracts-install
contracts-install: venv ## Install contract validation dependencies
	@echo "Installing Node.js dependencies..."
	cd contracts && npm install
	@echo "Installing Python dependencies..."
	$(PIP) install -r contracts/requirements.txt

.PHONY: contracts-validate
contracts-validate: ## Validate all contract examples
	@echo "Validating contracts..."
	cd contracts && npm run validate:all

.PHONY: contracts-validate-sitefit
contracts-validate-sitefit: ## Validate sitefit contract examples
	@echo "Validating sitefit contract..."
	cd contracts && npm run validate:sitefit

# Stage 1: Development commands
.PHONY: dev-appserver
dev-appserver: ## Start AppServer (Node.js) on port 8080
	@echo "Starting AppServer..."
	cd shared/appserver-node && npm run dev

.PHONY: dev-api
dev-api: ## Start API (FastAPI) on port 8081
	@echo "Starting API..."
	cd apps/sitefit/api-fastapi && $(UVICORN) main:app --reload --port 8081

.PHONY: dev-frontend
dev-frontend: ## Start Frontend (Next.js) on port 3000
	@echo "Starting Frontend..."
	cd apps/sitefit/frontend && npm run dev

# General development
.PHONY: venv
venv: ## Create Python virtual environment
	@if [ ! -d "$(VENV)" ]; then \
		echo "Creating virtual environment..."; \
		python3 -m venv $(VENV); \
		echo "Virtual environment created at $(VENV)"; \
	else \
		echo "Virtual environment already exists at $(VENV)"; \
	fi

.PHONY: install
install: venv contracts-install ## Install all dependencies
	@echo "Installing all dependencies..."
	@echo "Installing AppServer dependencies..."
	cd shared/appserver-node && npm install
	@echo "Installing Frontend dependencies..."
	cd apps/sitefit/frontend && npm install
	@echo "Installing API dependencies..."
	$(PIP) install -r apps/sitefit/api-fastapi/requirements.txt
	@echo "Installing E2E test dependencies..."
	$(PIP) install -r tests-e2e/api/requirements.txt
	@echo "All dependencies installed!"

.PHONY: dev
dev: ## Start all services (requires tmux - install with: sudo apt install tmux)
	@echo "Starting all services in tmux..."
	@echo "If tmux is not installed, use 'make dev-simple' instead"
	tmux new-session -d -s kuduso 'make dev-appserver' \; \
		split-window -h 'make dev-api' \; \
		split-window -v 'make dev-frontend' \; \
		select-layout even-horizontal \; \
		attach

.PHONY: dev-simple
dev-simple: stop kill-ports ## Start all services in background (no tmux required)
	@echo "Starting all services in background..."
	@echo ""
	@echo "Starting AppServer on port 8080..."
	@cd shared/appserver-node && npm run dev > /tmp/kuduso-appserver.log 2>&1 & echo $$! > /tmp/kuduso-appserver.pid
	@sleep 2
	@echo "Starting API on port 8081..."
	@cd apps/sitefit/api-fastapi && $(UVICORN) main:app --reload --port 8081 > /tmp/kuduso-api.log 2>&1 & echo $$! > /tmp/kuduso-api.pid
	@sleep 2
	@echo "Starting Frontend on port 3000..."
	@cd apps/sitefit/frontend && npm run dev > /tmp/kuduso-frontend.log 2>&1 & echo $$! > /tmp/kuduso-frontend.pid
	@sleep 2
	@echo ""
	@echo "✅ All services started!"
	@echo ""
	@echo "Services:"
	@echo "  - AppServer:  http://localhost:8080 (PID: $$(cat /tmp/kuduso-appserver.pid 2>/dev/null || echo 'failed'))"
	@echo "  - API:        http://localhost:8081 (PID: $$(cat /tmp/kuduso-api.pid 2>/dev/null || echo 'failed'))"
	@echo "  - Frontend:   http://localhost:3000 (PID: $$(cat /tmp/kuduso-frontend.pid 2>/dev/null || echo 'failed'))"
	@echo ""
	@echo "Logs:"
	@echo "  - AppServer:  tail -f /tmp/kuduso-appserver.log"
	@echo "  - API:        tail -f /tmp/kuduso-api.log"
	@echo "  - Frontend:   tail -f /tmp/kuduso-frontend.log"
	@echo ""
	@echo "Commands:"
	@echo "  - Check status: make status"
	@echo "  - View logs:    make logs"
	@echo "  - Stop all:     make stop"

.PHONY: stop
stop: ## Stop all background services
	@echo "Stopping all services..."
	@if [ -f /tmp/kuduso-appserver.pid ]; then kill $$(cat /tmp/kuduso-appserver.pid) 2>/dev/null || true; rm /tmp/kuduso-appserver.pid; fi
	@if [ -f /tmp/kuduso-api.pid ]; then kill $$(cat /tmp/kuduso-api.pid) 2>/dev/null || true; rm /tmp/kuduso-api.pid; fi
	@if [ -f /tmp/kuduso-frontend.pid ]; then kill $$(cat /tmp/kuduso-frontend.pid) 2>/dev/null || true; rm /tmp/kuduso-frontend.pid; fi
	@echo "✅ All services stopped"

.PHONY: kill-ports
kill-ports: ## Force kill any processes using ports 8080, 8081, 3000
	@echo "Killing processes on ports 8080, 8081, 3000..."
	@lsof -ti:8080,8081,3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
	@echo "✅ Ports cleared"

.PHONY: status
status: ## Check status of all services
	@echo "Service Status:"
	@echo ""
	@if [ -f /tmp/kuduso-appserver.pid ] && kill -0 $$(cat /tmp/kuduso-appserver.pid) 2>/dev/null; then \
		echo "  ✅ AppServer (PID: $$(cat /tmp/kuduso-appserver.pid)) - http://localhost:8080"; \
	else \
		echo "  ❌ AppServer - not running"; \
	fi
	@if [ -f /tmp/kuduso-api.pid ] && kill -0 $$(cat /tmp/kuduso-api.pid) 2>/dev/null; then \
		echo "  ✅ API (PID: $$(cat /tmp/kuduso-api.pid)) - http://localhost:8081"; \
	else \
		echo "  ❌ API - not running"; \
	fi
	@if [ -f /tmp/kuduso-frontend.pid ] && kill -0 $$(cat /tmp/kuduso-frontend.pid) 2>/dev/null; then \
		echo "  ✅ Frontend (PID: $$(cat /tmp/kuduso-frontend.pid)) - http://localhost:3000"; \
	else \
		echo "  ❌ Frontend - not running"; \
	fi

.PHONY: logs
logs: ## Show logs from all services
	@echo "Tailing all service logs (Ctrl+C to stop)..."
	@tail -f /tmp/kuduso-*.log

.PHONY: test
test: contracts-validate test-e2e ## Run all tests
	@echo "All tests completed!"

.PHONY: test-e2e
test-e2e: ## Run end-to-end tests
	@echo "Running E2E tests..."
	cd tests-e2e/api && $(PYTEST) -v

.PHONY: lint
lint: ## Run linters
	@echo "Running linters..."
	# Add lint commands here

.PHONY: clean
clean: ## Clean build artifacts
	@echo "Cleaning..."
	find . -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -f /tmp/kuduso-*.log /tmp/kuduso-*.pid 2>/dev/null || true
	@echo "✅ Cleanup complete"
