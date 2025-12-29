#!/bin/bash
#
# Comprehensive Validation Script for Observability Stack
# Runs all Python validation tools in sequence
#

set -e

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD='\033[1m'
NC=$'\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "${BOLD}Observability Stack - Comprehensive Validation${NC}"
echo "================================================================"
echo ""

# Track overall status
VALIDATION_FAILED=0

# Function to run a validation step
run_validation() {
    local name="$1"
    local cmd="$2"
    local required="${3:-yes}"

    echo "${BLUE}${BOLD}Running: ${name}${NC}"
    echo "Command: $cmd"
    echo ""

    if eval "$cmd"; then
        echo "${GREEN}✓ ${name} - PASSED${NC}"
        echo ""
        return 0
    else
        exit_code=$?
        if [ "$required" = "yes" ]; then
            echo "${RED}✗ ${name} - FAILED (exit code: $exit_code)${NC}"
            VALIDATION_FAILED=1
        else
            echo "${YELLOW}⚠ ${name} - FAILED (exit code: $exit_code) - Non-blocking${NC}"
        fi
        echo ""
        return $exit_code
    fi
}

# Change to repository root
cd "$REPO_ROOT"

echo "Repository: $REPO_ROOT"
echo ""

# 1. Check Python dependencies
echo "${BLUE}${BOLD}Checking Python dependencies...${NC}"
if ! python3 -c "import yaml" 2>/dev/null; then
    echo "${RED}Missing dependency: PyYAML${NC}"
    echo "Install with: pip install PyYAML"
    exit 1
fi

if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "${YELLOW}Optional dependency missing: jsonschema${NC}"
    echo "Some tools may not work. Install with: pip install jsonschema"
    echo ""
fi

echo "${GREEN}Python dependencies OK${NC}"
echo ""
echo "================================================================"
echo ""

# 2. YAML Schema Validation
if python3 -c "import jsonschema" 2>/dev/null; then
    run_validation \
        "YAML Schema Validation - Global Config" \
        "python3 scripts/tools/validate_schema.py config/global.yaml"

    run_validation \
        "YAML Schema Validation - All Modules" \
        "python3 scripts/tools/validate_schema.py modules/ --recursive"
else
    echo "${YELLOW}Skipping schema validation (jsonschema not installed)${NC}"
    echo ""
fi

# 3. Module Linting
run_validation \
    "Module Linting - All Modules" \
    "python3 scripts/tools/lint_module.py modules/ --recursive"

# 4. Dependency Resolution
run_validation \
    "Dependency Resolution - Check Cycles" \
    "python3 scripts/tools/resolve_deps.py modules/ --check-cycles"

# 5. Port Conflict Detection
# Note: This may fail if ports are intentionally duplicated in global and modules
run_validation \
    "Port Conflict Detection" \
    "python3 scripts/tools/check_ports.py --modules modules/ --global config/global.yaml" \
    "no"

# 6. Secret Scanning
# Note: This will warn about placeholder values, which is expected
run_validation \
    "Secret Scanning" \
    "python3 scripts/tools/scan_secrets.py config/ --recursive" \
    "no"

# 7. YAML Formatting Check
run_validation \
    "YAML Formatting Check" \
    "python3 scripts/tools/format_yaml.py modules/ --recursive --check" \
    "no"

# Summary
echo "================================================================"
echo "${BOLD}Validation Summary${NC}"
echo "================================================================"
echo ""

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "${GREEN}${BOLD}✓ All critical validations passed!${NC}"
    echo ""
    echo "Your observability stack configuration is valid and ready to use."
    exit 0
else
    echo "${RED}${BOLD}✗ Some validations failed!${NC}"
    echo ""
    echo "Please review the errors above and fix the issues before deploying."
    exit 1
fi
