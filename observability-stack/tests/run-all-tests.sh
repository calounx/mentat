#!/bin/bash
#===============================================================================
# Run All Tests
# Executes the complete test suite with coverage reporting
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}Observability Stack Test Runner${NC}"
echo "==============================="
echo ""

# Check if BATS is installed
if ! command -v bats &>/dev/null; then
    echo -e "${RED}ERROR: BATS is not installed${NC}"
    echo "Please run: $SCRIPT_DIR/setup.sh"
    exit 1
fi

# Set up environment
export OBSERVABILITY_STACK_ROOT="$REPO_ROOT"
export TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
export TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/observability-stack-tests}"

# Clean and create temp directory
rm -rf "$TEST_TMP_DIR"
mkdir -p "$TEST_TMP_DIR"

# Parse arguments
RUN_UNIT=true
RUN_INTEGRATION=true
RUN_SECURITY=true
RUN_ERRORS=true
VERBOSE=false
FAIL_FAST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --unit-only)
            RUN_INTEGRATION=false
            RUN_SECURITY=false
            RUN_ERRORS=false
            shift
            ;;
        --integration-only)
            RUN_UNIT=false
            RUN_SECURITY=false
            RUN_ERRORS=false
            shift
            ;;
        --security-only)
            RUN_UNIT=false
            RUN_INTEGRATION=false
            RUN_ERRORS=false
            shift
            ;;
        --errors-only)
            RUN_UNIT=false
            RUN_INTEGRATION=false
            RUN_SECURITY=false
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --fail-fast|-f)
            FAIL_FAST=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --unit-only         Run only unit tests"
            echo "  --integration-only  Run only integration tests"
            echo "  --security-only     Run only security tests"
            echo "  --errors-only       Run only error handling tests"
            echo "  --verbose, -v       Show detailed test output"
            echo "  --fail-fast, -f     Stop on first test failure"
            echo "  --help, -h          Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Function to run test suite
run_test_suite() {
    local suite_name="$1"
    local test_dir="$2"

    if [[ ! -d "$test_dir" ]]; then
        echo -e "${YELLOW}⚠${NC} $suite_name: directory not found"
        return 0
    fi

    local test_count=$(find "$test_dir" -name "*.bats" 2>/dev/null | wc -l)
    if [[ $test_count -eq 0 ]]; then
        echo -e "${YELLOW}⚠${NC} $suite_name: no tests found"
        return 0
    fi

    echo ""
    echo -e "${BLUE}Running $suite_name ($test_count test files)...${NC}"
    echo "-----------------------------------"

    local suite_failed=false
    local bats_opts=""

    if [[ "$VERBOSE" == "true" ]]; then
        bats_opts="--verbose-run"
    fi

    if [[ "$FAIL_FAST" == "true" ]]; then
        bats_opts="$bats_opts --fail-fast"
    fi

    # Run BATS tests
    if bats $bats_opts "$test_dir" 2>&1 | tee "$TEST_TMP_DIR/${suite_name// /_}.log"; then
        echo -e "${GREEN}✓${NC} $suite_name: PASSED"
    else
        echo -e "${RED}✗${NC} $suite_name: FAILED"
        suite_failed=true
    fi

    # Parse results from log
    local log_file="$TEST_TMP_DIR/${suite_name// /_}.log"
    if [[ -f "$log_file" ]]; then
        local suite_total=$(grep -c "^ok\|^not ok" "$log_file" || echo "0")
        local suite_passed=$(grep -c "^ok" "$log_file" || echo "0")
        local suite_failed_count=$(grep -c "^not ok" "$log_file" || echo "0")
        local suite_skipped=$(grep -c "# skip" "$log_file" || echo "0")

        TOTAL_TESTS=$((TOTAL_TESTS + suite_total))
        PASSED_TESTS=$((PASSED_TESTS + suite_passed))
        FAILED_TESTS=$((FAILED_TESTS + suite_failed_count))
        SKIPPED_TESTS=$((SKIPPED_TESTS + suite_skipped))
    fi

    if [[ "$suite_failed" == "true" ]] && [[ "$FAIL_FAST" == "true" ]]; then
        return 1
    fi

    return 0
}

#===============================================================================
# RUN TEST SUITES
#===============================================================================

START_TIME=$(date +%s)

# Unit Tests
if [[ "$RUN_UNIT" == "true" ]]; then
    run_test_suite "Unit Tests" "$SCRIPT_DIR/unit" || {
        if [[ "$FAIL_FAST" == "true" ]]; then
            echo ""
            echo -e "${RED}Stopping due to test failure (--fail-fast)${NC}"
            exit 1
        fi
    }
fi

# Integration Tests
if [[ "$RUN_INTEGRATION" == "true" ]]; then
    run_test_suite "Integration Tests" "$SCRIPT_DIR/integration" || {
        if [[ "$FAIL_FAST" == "true" ]]; then
            echo ""
            echo -e "${RED}Stopping due to test failure (--fail-fast)${NC}"
            exit 1
        fi
    }
fi

# Security Tests
if [[ "$RUN_SECURITY" == "true" ]]; then
    run_test_suite "Security Tests" "$SCRIPT_DIR/security" || {
        if [[ "$FAIL_FAST" == "true" ]]; then
            echo ""
            echo -e "${RED}Stopping due to test failure (--fail-fast)${NC}"
            exit 1
        fi
    }
fi

# Error Handling Tests
if [[ "$RUN_ERRORS" == "true" ]]; then
    run_test_suite "Error Handling Tests" "$SCRIPT_DIR/errors" || {
        if [[ "$FAIL_FAST" == "true" ]]; then
            echo ""
            echo -e "${RED}Stopping due to test failure (--fail-fast)${NC}"
            exit 1
        fi
    }
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

#===============================================================================
# TEST SUMMARY
#===============================================================================

echo ""
echo ""
echo -e "${BLUE}Test Summary${NC}"
echo "=================================="
echo "Total Tests:   $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC}        $PASSED_TESTS"
if [[ $FAILED_TESTS -gt 0 ]]; then
    echo -e "${RED}Failed:${NC}        $FAILED_TESTS"
else
    echo -e "Failed:        $FAILED_TESTS"
fi
if [[ $SKIPPED_TESTS -gt 0 ]]; then
    echo -e "${YELLOW}Skipped:${NC}       $SKIPPED_TESTS"
fi
echo "Duration:      ${DURATION}s"
echo ""

# Calculate success rate
if [[ $TOTAL_TESTS -gt 0 ]]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Success Rate:  ${SUCCESS_RATE}%"
    echo ""
fi

# Show logs location
echo "Test logs saved to: $TEST_TMP_DIR"
echo ""

# Exit code
if [[ $FAILED_TESTS -gt 0 ]]; then
    echo -e "${RED}✗ TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
fi
