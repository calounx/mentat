#!/bin/bash

# Deployment Test Runner Script
# Orchestrates execution of all deployment test suites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="$PROJECT_ROOT/storage/test-reports/deployment_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default configuration
RUN_SMOKE=true
RUN_INTEGRATION=true
RUN_LOAD=false
RUN_CHAOS=false
PARALLEL=false
COVERAGE=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --smoke-only)
            RUN_SMOKE=true
            RUN_INTEGRATION=false
            RUN_LOAD=false
            RUN_CHAOS=false
            shift
            ;;
        --integration-only)
            RUN_SMOKE=false
            RUN_INTEGRATION=true
            RUN_LOAD=false
            RUN_CHAOS=false
            shift
            ;;
        --load)
            RUN_LOAD=true
            shift
            ;;
        --chaos)
            RUN_CHAOS=true
            shift
            ;;
        --all)
            RUN_SMOKE=true
            RUN_INTEGRATION=true
            RUN_LOAD=true
            RUN_CHAOS=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --coverage)
            COVERAGE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --smoke-only      Run only smoke tests (fast, critical paths)"
            echo "  --integration-only Run only integration tests"
            echo "  --load            Include load/performance tests"
            echo "  --chaos           Include chaos/failure tests"
            echo "  --all             Run all test suites"
            echo "  --parallel        Run tests in parallel"
            echo "  --coverage        Generate code coverage report"
            echo "  --verbose, -v     Verbose output"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --smoke-only          # Quick smoke tests"
            echo "  $0 --all --coverage      # Full test suite with coverage"
            echo "  $0 --integration-only -v # Integration tests with verbose output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Create report directory
mkdir -p "$REPORT_DIR"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  DEPLOYMENT TEST SUITE${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Timestamp: $TIMESTAMP"
echo "Report directory: $REPORT_DIR"
echo ""

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Function to run test suite
run_test_suite() {
    local suite_name=$1
    local filter=$2
    local log_file="$REPORT_DIR/${suite_name}.log"

    echo -e "${YELLOW}Running ${suite_name} tests...${NC}"

    # Build PHPUnit command
    local cmd="cd $PROJECT_ROOT && vendor/bin/phpunit"

    if [ "$COVERAGE" = true ]; then
        cmd="$cmd --coverage-html $REPORT_DIR/coverage-${suite_name}"
    fi

    if [ "$VERBOSE" = true ]; then
        cmd="$cmd --verbose"
    fi

    cmd="$cmd --filter '$filter' --log-junit $REPORT_DIR/${suite_name}-junit.xml"

    # Run tests
    if eval "$cmd" > "$log_file" 2>&1; then
        echo -e "${GREEN}✓${NC} ${suite_name} tests passed"
        return 0
    else
        echo -e "${RED}✗${NC} ${suite_name} tests failed"
        return 1
    fi
}

# Function to parse test results
parse_results() {
    local log_file=$1

    if [ -f "$log_file" ]; then
        local tests=$(grep -oP 'Tests: \K\d+' "$log_file" | head -1 || echo "0")
        local assertions=$(grep -oP 'Assertions: \K\d+' "$log_file" | head -1 || echo "0")
        local failures=$(grep -oP 'Failures: \K\d+' "$log_file" | head -1 || echo "0")
        local errors=$(grep -oP 'Errors: \K\d+' "$log_file" | head -1 || echo "0")
        local skipped=$(grep -oP 'Skipped: \K\d+' "$log_file" | head -1 || echo "0")

        TOTAL_TESTS=$((TOTAL_TESTS + tests))
        FAILED_TESTS=$((FAILED_TESTS + failures + errors))
        SKIPPED_TESTS=$((SKIPPED_TESTS + skipped))
        PASSED_TESTS=$((PASSED_TESTS + tests - failures - errors - skipped))
    fi
}

# Change to project directory
cd "$PROJECT_ROOT"

# Run test suites
START_TIME=$(date +%s)

if [ "$RUN_SMOKE" = true ]; then
    run_test_suite "smoke" "Tests\\\\Deployment\\\\Smoke" || true
    parse_results "$REPORT_DIR/smoke.log"
fi

if [ "$RUN_INTEGRATION" = true ]; then
    run_test_suite "integration" "Tests\\\\Deployment\\\\Integration" || true
    parse_results "$REPORT_DIR/integration.log"
fi

if [ "$RUN_LOAD" = true ]; then
    run_test_suite "load" "Tests\\\\Deployment\\\\Load" || true
    parse_results "$REPORT_DIR/load.log"
fi

if [ "$RUN_CHAOS" = true ]; then
    run_test_suite "chaos" "Tests\\\\Deployment\\\\Chaos" || true
    parse_results "$REPORT_DIR/chaos.log"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Generate summary report
SUMMARY_FILE="$REPORT_DIR/summary.txt"

cat > "$SUMMARY_FILE" << EOF
========================================
DEPLOYMENT TEST SUITE SUMMARY
========================================
Date: $(date)
Duration: ${DURATION}s

Test Configuration:
- Smoke tests: $RUN_SMOKE
- Integration tests: $RUN_INTEGRATION
- Load tests: $RUN_LOAD
- Chaos tests: $RUN_CHAOS
- Parallel execution: $PARALLEL
- Coverage enabled: $COVERAGE

Results:
- Total tests: $TOTAL_TESTS
- Passed: $PASSED_TESTS
- Failed: $FAILED_TESTS
- Skipped: $SKIPPED_TESTS

Status: $([ $FAILED_TESTS -eq 0 ] && echo "PASSED" || echo "FAILED")
========================================

Detailed logs available in:
$REPORT_DIR

EOF

# Display summary
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  TEST SUMMARY${NC}"
echo -e "${BLUE}=========================================${NC}"
cat "$SUMMARY_FILE"

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Check logs for details.${NC}"
    exit 1
fi
