#!/bin/bash
#===============================================================================
# Security and Upgrade System Test Runner
# Runs all security and upgrade-related tests
#===============================================================================

set -euo pipefail

# Color output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# Test directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECURITY_TESTS_DIR="${SCRIPT_DIR}/security"
UNIT_TESTS_DIR="${SCRIPT_DIR}/unit"
INTEGRATION_TESTS_DIR="${SCRIPT_DIR}/integration"

# Output files
REPORT_FILE="${SCRIPT_DIR}/test-results.txt"
SUMMARY_FILE="${SCRIPT_DIR}/test-summary.txt"

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

echo "==============================================================================="
echo "Security and Upgrade System Verification Tests"
echo "==============================================================================="
echo ""

# Function to run tests in a directory
run_test_suite() {
    local suite_name="$1"
    local test_dir="$2"

    echo "${BLUE}Running ${suite_name} Tests...${NC}"
    echo ""

    if [ ! -d "$test_dir" ]; then
        echo "${YELLOW}Warning: Test directory not found: ${test_dir}${NC}"
        return 0
    fi

    # Find all .bats files
    local test_files=$(find "$test_dir" -name "*.bats" -type f | sort)

    if [ -z "$test_files" ]; then
        echo "${YELLOW}No tests found in ${test_dir}${NC}"
        return 0
    fi

    # Run each test file
    for test_file in $test_files; do
        local test_name=$(basename "$test_file" .bats)

        echo "${BLUE}→ ${test_name}${NC}"

        # Run test and capture output
        local output_file="/tmp/bats_output_$$.txt"

        if bats --formatter tap "$test_file" > "$output_file" 2>&1; then
            # Parse TAP output
            local tests=$(grep -c "^ok\|^not ok" "$output_file" || echo "0")
            local passed=$(grep -c "^ok" "$output_file" || echo "0")
            local failed=$(grep -c "^not ok" "$output_file" || echo "0")
            local skipped=$(grep -c "# skip" "$output_file" || echo "0")

            TOTAL_TESTS=$((TOTAL_TESTS + tests))
            PASSED_TESTS=$((PASSED_TESTS + passed - skipped))
            FAILED_TESTS=$((FAILED_TESTS + failed))
            SKIPPED_TESTS=$((SKIPPED_TESTS + skipped))

            if [ "$failed" -eq 0 ]; then
                echo "  ${GREEN}✓ ${passed} tests passed${NC} ${YELLOW}(${skipped} skipped)${NC}"
            else
                echo "  ${RED}✗ ${failed} tests failed${NC}, ${GREEN}${passed} passed${NC}, ${YELLOW}${skipped} skipped${NC}"
            fi
        else
            echo "  ${RED}✗ Test suite failed to run${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        # Save output to report
        echo "=== ${test_name} ===" >> "$REPORT_FILE"
        cat "$output_file" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"

        rm -f "$output_file"
        echo ""
    done
}

# Initialize report files
> "$REPORT_FILE"
> "$SUMMARY_FILE"

echo "Test Execution Started: $(date)" > "$REPORT_FILE"
echo "===============================================================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Run test suites
run_test_suite "Security" "$SECURITY_TESTS_DIR"
run_test_suite "Unit" "$UNIT_TESTS_DIR"
run_test_suite "Integration" "$INTEGRATION_TESTS_DIR"

# Generate summary
echo "==============================================================================="
echo "${BLUE}Test Summary${NC}"
echo "==============================================================================="
echo ""
echo "Total Tests:   $TOTAL_TESTS"
echo "${GREEN}Passed:        $PASSED_TESTS${NC}"
echo "${RED}Failed:        $FAILED_TESTS${NC}"
echo "${YELLOW}Skipped:       $SKIPPED_TESTS${NC}"
echo ""

# Calculate pass rate
if [ "$TOTAL_TESTS" -gt 0 ]; then
    PASS_RATE=$((PASSED_TESTS * 100 / (TOTAL_TESTS - SKIPPED_TESTS)))
    echo "Pass Rate:     ${PASS_RATE}%"
else
    PASS_RATE=0
fi

echo ""

# Save summary
{
    echo "Test Execution Summary"
    echo "======================"
    echo ""
    echo "Date: $(date)"
    echo ""
    echo "Total Tests:   $TOTAL_TESTS"
    echo "Passed:        $PASSED_TESTS"
    echo "Failed:        $FAILED_TESTS"
    echo "Skipped:       $SKIPPED_TESTS"
    echo "Pass Rate:     ${PASS_RATE}%"
    echo ""
} > "$SUMMARY_FILE"

# Detailed results
echo "Detailed results: $REPORT_FILE"
echo "Summary:          $SUMMARY_FILE"
echo ""

# Exit with appropriate code
if [ "$FAILED_TESTS" -gt 0 ]; then
    echo "${RED}Some tests failed!${NC}"
    exit 1
else
    echo "${GREEN}All tests passed!${NC}"
    exit 0
fi
