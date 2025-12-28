# Makefile for Mentat Monorepo
# Testing and development commands for both Observability Stack and CHOM

.PHONY: help test test-all test-obs test-chom clean install-deps

# Default target
.DEFAULT_GOAL := help

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Show this help message
	@echo ""
	@echo "$(BLUE)Mentat Monorepo - Testing Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Component-specific targets:$(NC)"
	@echo "  $(YELLOW)make test-obs$(NC)        - Test observability stack only"
	@echo "  $(YELLOW)make test-chom$(NC)       - Test CHOM application only"
	@echo ""

test: test-all ## Run all tests (observability + CHOM)

test-all: ## Run tests for both observability stack and CHOM
	@echo "$(BLUE)====================================================$(NC)"
	@echo "$(BLUE)Running All Tests - Mentat Monorepo$(NC)"
	@echo "$(BLUE)====================================================$(NC)"
	@echo ""
	@$(MAKE) test-obs
	@echo ""
	@$(MAKE) test-chom
	@echo ""
	@echo "$(GREEN)====================================================$(NC)"
	@echo "$(GREEN)All Tests Completed!$(NC)"
	@echo "$(GREEN)====================================================$(NC)"

test-obs: ## Run observability stack tests (BATS + ShellCheck)
	@echo "$(BLUE)Running Observability Stack Tests...$(NC)"
	@cd observability-stack && $(MAKE) test-quick

test-chom: ## Run CHOM Laravel tests (PHPUnit)
	@echo "$(BLUE)Running CHOM Application Tests...$(NC)"
	@if [ ! -f chom/vendor/bin/phpunit ]; then \
		echo "$(YELLOW)Installing CHOM dependencies first...$(NC)"; \
		cd chom && composer install --quiet; \
	fi
	@cd chom && php artisan test

test-obs-all: ## Run all observability stack tests
	@echo "$(BLUE)Running All Observability Stack Tests...$(NC)"
	@cd observability-stack && $(MAKE) test-all

test-chom-coverage: ## Run CHOM tests with coverage
	@echo "$(BLUE)Running CHOM Tests with Coverage...$(NC)"
	@cd chom && php artisan test --coverage

lint: ## Run linting for all components
	@echo "$(BLUE)Running Linters...$(NC)"
	@cd observability-stack && $(MAKE) test-shellcheck
	@if [ -f chom/vendor/bin/pint ]; then \
		echo "$(BLUE)Running Laravel Pint...$(NC)"; \
		cd chom && ./vendor/bin/pint --test; \
	fi

clean: ## Clean up test artifacts
	@echo "$(BLUE)Cleaning up test artifacts...$(NC)"
	@cd observability-stack && $(MAKE) clean
	@cd chom && rm -rf vendor node_modules .phpunit.cache .phpunit.result.cache
	@echo "$(GREEN)Cleanup complete!$(NC)"

install-deps: ## Install dependencies for all components
	@echo "$(BLUE)Installing dependencies...$(NC)"
	@echo ""
	@echo "$(YELLOW)1. Observability Stack (bats, shellcheck)$(NC)"
	@cd observability-stack && $(MAKE) install-deps
	@echo ""
	@echo "$(YELLOW)2. CHOM (composer, npm)$(NC)"
	@if command -v composer >/dev/null 2>&1; then \
		cd chom && composer install; \
	else \
		echo "$(YELLOW)Warning: composer not found, skipping PHP dependencies$(NC)"; \
	fi
	@if command -v npm >/dev/null 2>&1; then \
		cd chom && npm install; \
	else \
		echo "$(YELLOW)Warning: npm not found, skipping JavaScript dependencies$(NC)"; \
	fi
	@echo "$(GREEN)Dependencies installed!$(NC)"

build: ## Build all components
	@echo "$(BLUE)Building all components...$(NC)"
	@echo ""
	@echo "$(YELLOW)1. Observability Stack (no build needed)$(NC)"
	@echo "$(GREEN)✓ Observability stack ready$(NC)"
	@echo ""
	@echo "$(YELLOW)2. CHOM Frontend Assets$(NC)"
	@cd chom && npm run build
	@echo "$(GREEN)Build complete!$(NC)"

dev-chom: ## Start CHOM development server
	@echo "$(BLUE)Starting CHOM development server...$(NC)"
	@cd chom && php artisan serve

dev-chom-watch: ## Watch CHOM frontend assets
	@echo "$(BLUE)Watching CHOM frontend assets...$(NC)"
	@cd chom && npm run dev

stats: ## Show repository statistics
	@echo "$(BLUE)====================================================$(NC)"
	@echo "$(BLUE)Mentat Monorepo Statistics$(NC)"
	@echo "$(BLUE)====================================================$(NC)"
	@echo ""
	@echo "$(GREEN)Observability Stack:$(NC)"
	@echo "  Shell scripts: $$(find observability-stack/scripts -name '*.sh' 2>/dev/null | wc -l)"
	@echo "  Test cases: $$(grep -c '^@test' observability-stack/tests/*.bats 2>/dev/null || echo '0')"
	@echo "  Modules: $$(find observability-stack/modules -name 'module.yaml' 2>/dev/null | wc -l)"
	@echo ""
	@echo "$(GREEN)CHOM Application:$(NC)"
	@echo "  PHP files: $$(find chom/app -name '*.php' 2>/dev/null | wc -l)"
	@echo "  Controllers: $$(find chom/app/Http/Controllers -name '*.php' 2>/dev/null | wc -l)"
	@echo "  Models: $$(find chom/app/Models -name '*.php' 2>/dev/null | wc -l)"
	@echo "  Livewire components: $$(find chom/app/Livewire -name '*.php' 2>/dev/null | wc -l)"
	@echo "  Test files: $$(find chom/tests -name '*.php' 2>/dev/null | wc -l)"
	@echo ""

.PHONY: check
check: test ## Alias for test (run all tests)

.PHONY: ci
ci: test-all lint ## Run CI pipeline (tests + linting)
	@echo "$(GREEN)CI checks passed!$(NC)"
