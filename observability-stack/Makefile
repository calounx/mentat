# Makefile for Observability Stack Testing

.PHONY: help test test-unit test-integration test-security test-shellcheck test-quick test-all clean install-deps

# Default target
.DEFAULT_GOAL := help

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Show this help message
	@echo ""
	@echo "$(BLUE)Observability Stack - Testing Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

install-deps: ## Install test dependencies (bats, shellcheck)
	@echo "$(BLUE)Installing test dependencies...$(NC)"
	@if command -v apt-get >/dev/null 2>&1; then \
		echo "Detected apt-get (Debian/Ubuntu)"; \
		sudo apt-get update && sudo apt-get install -y bats shellcheck; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "Detected Homebrew (macOS)"; \
		brew install bats-core shellcheck; \
	else \
		echo "$(YELLOW)Warning: Could not detect package manager$(NC)"; \
		echo "Please install bats and shellcheck manually"; \
		echo "  Bats: https://github.com/bats-core/bats-core"; \
		echo "  ShellCheck: https://github.com/koalaman/shellcheck"; \
		exit 1; \
	fi
	@echo "$(GREEN)Dependencies installed successfully!$(NC)"

test: test-quick ## Run quick tests (unit + shellcheck)

test-all: ## Run all test suites
	@echo "$(BLUE)Running all test suites...$(NC)"
	@./tests/run-tests.sh all

test-unit: ## Run unit tests only
	@echo "$(BLUE)Running unit tests...$(NC)"
	@./tests/run-tests.sh unit

test-integration: ## Run integration tests only
	@echo "$(BLUE)Running integration tests...$(NC)"
	@./tests/run-tests.sh integration

test-security: ## Run security tests only
	@echo "$(BLUE)Running security tests...$(NC)"
	@./tests/run-tests.sh security

test-shellcheck: ## Run shellcheck analysis only
	@echo "$(BLUE)Running shellcheck analysis...$(NC)"
	@./tests/run-tests.sh shellcheck

test-quick: ## Run quick tests (unit + shellcheck)
	@echo "$(BLUE)Running quick tests...$(NC)"
	@./tests/run-tests.sh quick

test-verbose: ## Run all tests with verbose output
	@echo "$(BLUE)Running all tests (verbose)...$(NC)"
	@./tests/run-tests.sh --verbose all

test-coverage: ## Show test coverage report
	@echo "$(BLUE)Test Coverage Report$(NC)"
	@echo ""
	@echo "$(GREEN)Unit Tests:$(NC)"
	@grep -c "^@test" tests/test-common.bats || echo "0"
	@echo ""
	@echo "$(GREEN)Integration Tests:$(NC)"
	@grep -c "^@test" tests/test-integration.bats || echo "0"
	@echo ""
	@echo "$(GREEN)Security Tests:$(NC)"
	@grep -c "^@test" tests/test-security.bats || echo "0"
	@echo ""
	@echo "$(GREEN)Total Test Cases:$(NC)"
	@grep -c "^@test" tests/*.bats || echo "0"
	@echo ""
	@echo "$(GREEN)Shell Scripts:$(NC)"
	@find scripts -name "*.sh" -type f | wc -l
	@echo ""

clean: ## Clean up test artifacts
	@echo "$(BLUE)Cleaning up test artifacts...$(NC)"
	@rm -rf test-results*.xml
	@rm -rf shellcheck-results.txt
	@rm -rf coverage-summary.md
	@rm -rf /tmp/bats-test-* 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete!$(NC)"

lint: test-shellcheck ## Alias for test-shellcheck

check: test-quick ## Alias for test-quick

ci: test-all ## Run tests as they would in CI
	@echo "$(GREEN)CI tests completed!$(NC)"

watch: ## Watch for changes and run tests (requires entr)
	@if ! command -v entr >/dev/null 2>&1; then \
		echo "$(YELLOW)Warning: entr is not installed$(NC)"; \
		echo "Install with: sudo apt-get install entr (Ubuntu) or brew install entr (macOS)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Watching for changes...$(NC)"
	@find scripts tests -name "*.sh" -o -name "*.bats" | entr -c make test-quick

.PHONY: validate-yaml
validate-yaml: ## Validate all YAML files
	@echo "$(BLUE)Validating YAML files...$(NC)"
	@if command -v yamllint >/dev/null 2>&1; then \
		find . -name "*.yaml" -o -name "*.yml" | xargs yamllint || true; \
	else \
		echo "$(YELLOW)yamllint not installed, using Python$(NC)"; \
		find . -name "*.yaml" -o -name "*.yml" -exec python3 -c "import yaml; yaml.safe_load(open('{}'))" \; 2>&1 | grep -v "Traceback" || true; \
	fi

.PHONY: syntax-check
syntax-check: ## Check bash syntax of all scripts
	@echo "$(BLUE)Checking bash syntax...$(NC)"
	@find scripts -name "*.sh" -type f -exec bash -n {} \; && \
		find modules -name "*.sh" -type f -exec bash -n {} \; && \
		echo "$(GREEN)All scripts have valid syntax!$(NC)"

.PHONY: pre-commit
pre-commit: test-quick validate-yaml syntax-check ## Run pre-commit checks
	@echo "$(GREEN)Pre-commit checks passed!$(NC)"

.PHONY: setup-hooks
setup-hooks: ## Setup git pre-commit hooks
	@echo "$(BLUE)Setting up git hooks...$(NC)"
	@mkdir -p .git/hooks
	@cat > .git/hooks/pre-commit <<'EOF'
#!/bin/bash
# Pre-commit hook - run tests before commit
echo "Running pre-commit checks..."
make pre-commit || exit 1
echo "Pre-commit checks passed!"
EOF
	@chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)Git hooks installed!$(NC)"
	@echo "Tests will run automatically before each commit"

.PHONY: docker-test
docker-test: ## Run tests in Docker container
	@echo "$(BLUE)Running tests in Docker...$(NC)"
	@docker run --rm -v $(PWD):/workspace -w /workspace ubuntu:latest bash -c '\
		apt-get update && \
		apt-get install -y bats shellcheck && \
		./tests/run-tests.sh all'

.PHONY: stats
stats: ## Show repository statistics
	@echo "$(BLUE)Repository Statistics$(NC)"
	@echo ""
	@echo "$(GREEN)Scripts:$(NC)"
	@echo "  Shell scripts: $$(find scripts -name '*.sh' | wc -l)"
	@echo "  Total lines: $$(find scripts -name '*.sh' -exec cat {} \; | wc -l)"
	@echo ""
	@echo "$(GREEN)Tests:$(NC)"
	@echo "  Test suites: $$(find tests -name '*.bats' | wc -l)"
	@echo "  Test cases: $$(grep -c '^@test' tests/*.bats)"
	@echo "  Test lines: $$(find tests -name '*.bats' -exec cat {} \; | wc -l)"
	@echo ""
	@echo "$(GREEN)Modules:$(NC)"
	@echo "  Total modules: $$(find modules -name 'module.yaml' | wc -l)"
	@echo ""
