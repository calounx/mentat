#!/bin/bash
#===============================================================================
# Test Infrastructure Setup Script
# Checks for BATS installation and sets up the test environment
#===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}Observability Stack Test Infrastructure Setup${NC}"
echo "=============================================="
echo ""

#===============================================================================
# CHECK DEPENDENCIES
#===============================================================================

check_command() {
    local cmd="$1"
    local package="$2"

    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $cmd found"
        return 0
    else
        echo -e "${RED}✗${NC} $cmd not found"
        echo -e "  ${YELLOW}Install with:${NC} $package"
        return 1
    fi
}

echo "Checking dependencies..."
echo ""

MISSING_DEPS=0

# Check for BATS
if ! check_command bats "sudo npm install -g bats || git clone https://github.com/bats-core/bats-core.git && cd bats-core && sudo ./install.sh /usr/local"; then
    MISSING_DEPS=1
fi

# Check for shellcheck
if ! check_command shellcheck "sudo apt-get install shellcheck || brew install shellcheck"; then
    MISSING_DEPS=1
fi

# Check for yq (YAML processor)
if ! check_command yq "sudo snap install yq || brew install yq"; then
    echo -e "${YELLOW}⚠${NC} yq not found (optional, tests will use awk-based parsing)"
fi

# Check for promtool
if ! check_command promtool "sudo apt-get install prometheus || brew install prometheus"; then
    echo -e "${YELLOW}⚠${NC} promtool not found (optional, some integration tests will be skipped)"
fi

echo ""

if [[ $MISSING_DEPS -eq 1 ]]; then
    echo -e "${RED}ERROR:${NC} Required dependencies are missing. Please install them first."
    echo ""
    echo "Quick setup for BATS:"
    echo "  git clone https://github.com/bats-core/bats-core.git /tmp/bats-core"
    echo "  cd /tmp/bats-core"
    echo "  sudo ./install.sh /usr/local"
    echo ""
    exit 1
fi

#===============================================================================
# SETUP TEST ENVIRONMENT
#===============================================================================

echo "Setting up test environment..."
echo ""

# Create test directories
mkdir -p "$SCRIPT_DIR"/{unit,integration,security,errors,fixtures}

# Create fixtures directory structure
mkdir -p "$SCRIPT_DIR/fixtures"/{modules,hosts,configs}

# Set up test environment variables
export OBSERVABILITY_STACK_ROOT="$REPO_ROOT"
export TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
export TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/observability-stack-tests}"

# Clean and recreate temp directory
if [[ -d "$TEST_TMP_DIR" ]]; then
    rm -rf "$TEST_TMP_DIR"
fi
mkdir -p "$TEST_TMP_DIR"

echo -e "${GREEN}✓${NC} Test directories created"
echo -e "${GREEN}✓${NC} Test environment configured"
echo ""

#===============================================================================
# VERIFY TEST STRUCTURE
#===============================================================================

echo "Verifying test structure..."
echo ""

count_tests() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        find "$dir" -name "*.bats" -o -name "test_*.sh" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

UNIT_TESTS=$(count_tests "$SCRIPT_DIR/unit")
INTEGRATION_TESTS=$(count_tests "$SCRIPT_DIR/integration")
SECURITY_TESTS=$(count_tests "$SCRIPT_DIR/security")
ERROR_TESTS=$(count_tests "$SCRIPT_DIR/errors")

echo "Test suite summary:"
echo "  Unit tests:        $UNIT_TESTS"
echo "  Integration tests: $INTEGRATION_TESTS"
echo "  Security tests:    $SECURITY_TESTS"
echo "  Error tests:       $ERROR_TESTS"
echo "  Total:             $((UNIT_TESTS + INTEGRATION_TESTS + SECURITY_TESTS + ERROR_TESTS))"
echo ""

#===============================================================================
# SETUP COMPLETE
#===============================================================================

echo -e "${GREEN}✓ Test infrastructure setup complete!${NC}"
echo ""
echo "To run tests:"
echo "  All tests:         ./tests/run-all-tests.sh"
echo "  Unit tests:        bats tests/unit/"
echo "  Integration tests: bats tests/integration/"
echo "  Specific test:     bats tests/unit/test_common.bats"
echo ""
echo "Environment variables:"
echo "  OBSERVABILITY_STACK_ROOT=$OBSERVABILITY_STACK_ROOT"
echo "  TEST_FIXTURES_DIR=$TEST_FIXTURES_DIR"
echo "  TEST_TMP_DIR=$TEST_TMP_DIR"
echo ""
