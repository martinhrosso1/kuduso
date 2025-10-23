# Kuduso Monorepo Makefile
# Quick commands for local development and deployment

.PHONY: help
help: ## Show this help message
	@echo "Kuduso Monorepo Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# Contract validation
.PHONY: contracts-install
contracts-install: ## Install contract validation dependencies
	@echo "Installing Node.js dependencies..."
	cd contracts && npm install
	@echo "Installing Python dependencies..."
	pip install -r contracts/requirements.txt

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
	cd apps/sitefit/api-fastapi && uvicorn main:app --reload --port 8081

.PHONY: dev-frontend
dev-frontend: ## Start Frontend (Next.js) on port 3000
	@echo "Starting Frontend..."
	cd apps/sitefit/frontend && npm run dev

# General development
.PHONY: install
install: contracts-install ## Install all dependencies
	@echo "Installing all dependencies..."
	@echo "Installing AppServer dependencies..."
	cd shared/appserver-node && npm install
	@echo "Installing Frontend dependencies..."
	cd apps/sitefit/frontend && npm install
	@echo "Installing API dependencies..."
	pip install -r apps/sitefit/api-fastapi/requirements.txt
	@echo "Installing E2E test dependencies..."
	pip install -r tests-e2e/api/requirements.txt

.PHONY: dev
dev: ## Start all services (requires tmux)
	@echo "Starting all services in tmux..."
	tmux new-session -d -s kuduso 'make dev-appserver' \; \
		split-window -h 'make dev-api' \; \
		split-window -v 'make dev-frontend' \; \
		select-layout even-horizontal \; \
		attach

.PHONY: test
test: contracts-validate test-e2e ## Run all tests
	@echo "All tests completed!"

.PHONY: test-e2e
test-e2e: ## Run end-to-end tests
	@echo "Running E2E tests..."
	cd tests-e2e/api && pytest -v

.PHONY: lint
lint: ## Run linters
	@echo "Running linters..."
	# Add lint commands here

.PHONY: clean
clean: ## Clean build artifacts
	@echo "Cleaning..."
	find . -type d -name "node_modules" -exec rm -rf {} +
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
