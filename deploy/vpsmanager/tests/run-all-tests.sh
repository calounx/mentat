#!/usr/bin/env bash
# VPSManager Master Test Runner
# Runs all available tests (unit and integration)
#
# Usage:
#   ./run-all-tests.sh           # Run all tests
#   ./run-all-tests.sh unit      # Run only unit tests
#   ./run-all-tests.sh integration # Run only integration tests

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_TESTS_DIR="${SCRIPT_DIR}/unit"
INTEGRATION_TESTS_DIR="${SCRIPT_DIR}/integration"

# Track results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# ============================================================================
# Color output helpers
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
}

print_suite() {
    echo -e "\n${BOLD}${BLUE}Running Test Suite:${NC} $1"
    echo "----------------------------------------"
}

print_success() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

print_error() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ INFO:${NC} $1"
}

# ============================================================================
# Test runners
# ============================================================================

run_test_suite() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file")

    ((TOTAL_SUITES++))

    print_suite "$test_name"

    if bash "$test_file"; then
        ((PASSED_SUITES++))
        print_success "Test suite passed: $test_name"
        return 0
    else
        ((FAILED_SUITES++))
        print_error "Test suite failed: $test_name"
        return 1
    fi
}

run_unit_tests() {
    print_header "Running Unit Tests"

    local unit_tests
    mapfile -t unit_tests < <(find "$UNIT_TESTS_DIR" -name "test-*.sh" -type f | sort)

    if [[ ${#unit_tests[@]} -eq 0 ]]; then
        print_warning "No unit tests found in $UNIT_TESTS_DIR"
        return 0
    fi

    print_info "Found ${#unit_tests[@]} unit test suite(s)"

    for test in "${unit_tests[@]}"; do
        run_test_suite "$test" || true
    done

    echo ""
}

run_integration_tests() {
    print_header "Running Integration Tests"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "Integration tests require root privileges"
        print_info "Please run: sudo $0 integration"
        return 1
    fi

    local integration_tests
    mapfile -t integration_tests < <(find "$INTEGRATION_TESTS_DIR" -name "test-*.sh" -type f | sort)

    if [[ ${#integration_tests[@]} -eq 0 ]]; then
        print_warning "No integration tests found in $INTEGRATION_TESTS_DIR"
        return 0
    fi

    print_info "Found ${#integration_tests[@]} integration test suite(s)"

    for test in "${integration_tests[@]}"; do
        run_test_suite "$test" || true
    done

    echo ""
}

# ============================================================================
# Main
# ============================================================================

show_usage() {
    cat <<EOF
VPSManager Test Runner

Usage:
  $0 [type]

Arguments:
  type    Test type to run (optional):
          - all          Run all tests (default)
          - unit         Run only unit tests
          - integration  Run only integration tests (requires root)

Examples:
  $0                    # Run all tests
  $0 unit               # Run only unit tests
  sudo $0 integration   # Run only integration tests

EOF
}

main() {
    local test_type="${1:-all}"

    case "$test_type" in
        unit)
            print_header "VPSManager Test Runner - Unit Tests Only"
            run_unit_tests
            ;;
        integration)
            print_header "VPSManager Test Runner - Integration Tests Only"
            run_integration_tests
            ;;
        all)
            print_header "VPSManager Test Runner - All Tests"
            run_unit_tests
            if [[ $EUID -eq 0 ]]; then
                run_integration_tests
            else
                print_warning "Skipping integration tests (require root)"
                print_info "Run 'sudo $0 integration' to run integration tests"
            fi
            ;;
        --help|-h|help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR: Unknown test type: $test_type${NC}"
            echo ""
            show_usage
            exit 1
            ;;
    esac

    # Print summary
    print_header "Test Results Summary"
    echo -e "${BOLD}Total Test Suites:${NC} $TOTAL_SUITES"
    echo -e "${GREEN}${BOLD}Passed:${NC} $PASSED_SUITES"
    if [[ $FAILED_SUITES -gt 0 ]]; then
        echo -e "${RED}${BOLD}Failed:${NC} $FAILED_SUITES"
    else
        echo -e "${GREEN}${BOLD}Failed:${NC} 0"
    fi

    echo ""
    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ ALL TEST SUITES PASSED${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ SOME TEST SUITES FAILED${NC}"
        exit 1
    fi
}

# Run main
main "$@"
