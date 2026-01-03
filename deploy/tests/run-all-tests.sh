#!/usr/bin/env bash
# Run all deployment logic tests
#
# Usage: ./run-all-tests.sh [--tap] [--verbose] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Options
OUTPUT_FORMAT="pretty"
VERBOSE=false
GENERATE_REPORT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tap)
            OUTPUT_FORMAT="tap"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --help)
            cat <<EOF
Deployment Logic Test Runner

Usage: $0 [OPTIONS]

OPTIONS:
    --tap           Output in TAP format
    --verbose       Show detailed test output
    --report        Generate comprehensive test report
    --help          Show this help message

EXAMPLES:
    # Run all tests with pretty output
    $0

    # Run tests and generate report
    $0 --report

    # Run tests in TAP format
    $0 --tap

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}ERROR: bats is not installed${NC}"
    echo ""
    echo "Install bats:"
    echo "  # On Debian/Ubuntu:"
    echo "  sudo apt-get install bats"
    echo ""
    echo "  # On macOS:"
    echo "  brew install bats-core"
    echo ""
    echo "  # Or via npm:"
    echo "  npm install -g bats"
    echo ""
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Logic Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Find all test files
TEST_FILES=(
    "${SCRIPT_DIR}/01-argument-parsing.bats"
    "${SCRIPT_DIR}/02-dependency-validation.bats"
    "${SCRIPT_DIR}/03-phase-execution.bats"
    "${SCRIPT_DIR}/04-error-handling.bats"
    "${SCRIPT_DIR}/05-file-paths.bats"
    "${SCRIPT_DIR}/06-user-detection.bats"
    "${SCRIPT_DIR}/07-ssh-operations.bats"
)

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Results file for report generation
RESULTS_FILE="${SCRIPT_DIR}/test-results.txt"
> "$RESULTS_FILE"

# Run each test file
for test_file in "${TEST_FILES[@]}"; do
    if [[ ! -f "$test_file" ]]; then
        echo -e "${YELLOW}Warning: Test file not found: $test_file${NC}"
        continue
    fi

    test_name=$(basename "$test_file" .bats)
    echo -e "${BLUE}Running: ${test_name}${NC}"

    # Run bats with appropriate options
    if [[ "$OUTPUT_FORMAT" == "tap" ]]; then
        bats_output=$(bats --tap "$test_file" 2>&1)
    else
        bats_output=$(bats --pretty "$test_file" 2>&1)
    fi

    bats_exit_code=$?

    # Save output
    echo "=== $test_name ===" >> "$RESULTS_FILE"
    echo "$bats_output" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"

    # Parse results
    if [[ "$bats_exit_code" -eq 0 ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
    fi

    # Count tests from output
    if [[ "$bats_output" =~ ([0-9]+)\ test ]]; then
        count=${BASH_REMATCH[1]}
        TOTAL_TESTS=$((TOTAL_TESTS + count))
    fi

    # Count passes/failures
    passed=$(echo "$bats_output" | grep -c "^ok " || true)
    failed=$(echo "$bats_output" | grep -c "^not ok " || true)

    PASSED_TESTS=$((PASSED_TESTS + passed))
    FAILED_TESTS=$((FAILED_TESTS + failed))

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$bats_output"
    fi

    echo ""
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Total tests:   ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:        ${PASSED_TESTS}${NC}"

if [[ $FAILED_TESTS -gt 0 ]]; then
    echo -e "${RED}Failed:        ${FAILED_TESTS}${NC}"
fi

if [[ $SKIPPED_TESTS -gt 0 ]]; then
    echo -e "${YELLOW}Skipped:       ${SKIPPED_TESTS}${NC}"
fi

echo ""

# Generate report if requested
if [[ "$GENERATE_REPORT" == "true" ]]; then
    echo -e "${BLUE}Generating comprehensive test report...${NC}"
    bash "${SCRIPT_DIR}/generate-test-report.sh"
    echo -e "${GREEN}Report generated: ${SCRIPT_DIR}/DEPLOYMENT-LOGIC-TEST-REPORT.md${NC}"
    echo ""
fi

# Exit with appropriate code
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    echo -e "View detailed results: ${RESULTS_FILE}"
    exit 1
fi
