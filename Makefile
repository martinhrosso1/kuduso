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

# General development
.PHONY: install
install: contracts-install ## Install all dependencies
	@echo "Installing all dependencies..."
	# Add more installation commands as components are built

.PHONY: dev
dev: ## Start local development environment
	@echo "Starting local dev environment..."
	# Add dev server commands here

.PHONY: test
test: contracts-validate ## Run all tests
	@echo "Running tests..."
	# Add test commands here

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
