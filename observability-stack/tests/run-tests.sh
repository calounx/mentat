#!/bin/bash
#===============================================================================
# Test Runner
# Convenient wrapper to run all or specific test suites
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Counters
PASSED=0
FAILED=0
SKIPPED=0

#===============================================================================
# FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    local missing=0

    if ! command -v bats &> /dev/null; then
        log_error "bats is not installed"
        echo "  Install: sudo apt-get install bats (Ubuntu/Debian) or brew install bats-core (macOS)"
        ((missing++))
    fi

    if ! command -v shellcheck &> /dev/null; then
        log_skip "shellcheck is not installed (optional but recommended)"
        echo "  Install: sudo apt-get install shellcheck (Ubuntu/Debian) or brew install shellcheck (macOS)"
    fi

    if [[ $missing -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Run a test suite
run_suite() {
    local suite_name="$1"
    local suite_file="$2"

    echo ""
    echo "=========================================="
    echo "Running: $suite_name"
    echo "=========================================="
    echo ""

    if [[ ! -f "$suite_file" ]]; then
        log_skip "$suite_name - file not found"
        ((SKIPPED++))
        return 0
    fi

    if bats "$suite_file"; then
        log_success "$suite_name passed"
        ((PASSED++))
        return 0
    else
        log_error "$suite_name failed"
        ((FAILED++))
        return 1
    fi
}

# Run shellcheck
run_shellcheck() {
    echo ""
    echo "=========================================="
    echo "Running: ShellCheck"
    echo "=========================================="
    echo ""

    if [[ ! -x "${SCRIPT_DIR}/test-shellcheck.sh" ]]; then
        log_skip "ShellCheck - script not executable"
        ((SKIPPED++))
        return 0
    fi

    if "${SCRIPT_DIR}/test-shellcheck.sh"; then
        log_success "ShellCheck passed"
        ((PASSED++))
        return 0
    else
        log_error "ShellCheck failed"
        ((FAILED++))
        return 1
    fi
}

# Show summary
show_summary() {
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo ""
    printf "Passed:  %s%d%s\n" "$GREEN" $PASSED "$NC"
    printf "Failed:  %s%d%s\n" "$RED" $FAILED "$NC"

    if [[ $SKIPPED -gt 0 ]]; then
        printf "Skipped: %s%d%s\n" "$YELLOW" $SKIPPED "$NC"
    fi

    echo ""

    if [[ $FAILED -eq 0 ]]; then
        log_success "All test suites passed!"
        return 0
    else
        log_error "$FAILED test suite(s) failed"
        return 1
    fi
}

# Show help
show_help() {
    cat <<EOF
Test Runner for Observability Stack

Usage:
  $0 [OPTIONS] [SUITE]

Suites:
  all             Run all test suites (default)
  unit            Run unit tests (test-common.bats)
  integration     Run integration tests (test-integration.bats)
  security        Run security tests (test-security.bats)
  shellcheck      Run shellcheck analysis
  quick           Run quick tests (unit + shellcheck)

Options:
  -h, --help      Show this help message
  -v, --verbose   Verbose output
  -q, --quiet     Quiet output (errors only)

Examples:
  # Run all tests
  $0

  # Run specific suite
  $0 unit

  # Run quick tests
  $0 quick

  # Verbose output
  $0 --verbose all

Environment Variables:
  BATS_OPTS       Additional options for bats
                  Example: export BATS_OPTS="--tap"

Exit Codes:
  0 - All tests passed
  1 - One or more tests failed
  2 - Prerequisites not met
EOF
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    local suite="all"
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                export BATS_OPTS="${BATS_OPTS:-} -t"
                shift
                ;;
            -q|--quiet)
                export BATS_OPTS="${BATS_OPTS:-} --formatter tap"
                shift
                ;;
            all|unit|integration|security|shellcheck|quick)
                suite="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    echo ""
    echo "=========================================="
    echo "Observability Stack Test Runner"
    echo "=========================================="
    echo ""

    # Check prerequisites
    log_info "Checking prerequisites..."
    if ! check_prerequisites; then
        exit 2
    fi
    log_success "Prerequisites OK"

    # Run requested suites
    case $suite in
        all)
            run_suite "Unit Tests" "${SCRIPT_DIR}/test-common.bats"
            run_suite "Integration Tests" "${SCRIPT_DIR}/test-integration.bats"
            run_suite "Security Tests" "${SCRIPT_DIR}/test-security.bats"
            run_shellcheck
            ;;
        unit)
            run_suite "Unit Tests" "${SCRIPT_DIR}/test-common.bats"
            ;;
        integration)
            run_suite "Integration Tests" "${SCRIPT_DIR}/test-integration.bats"
            ;;
        security)
            run_suite "Security Tests" "${SCRIPT_DIR}/test-security.bats"
            ;;
        shellcheck)
            run_shellcheck
            ;;
        quick)
            run_suite "Unit Tests" "${SCRIPT_DIR}/test-common.bats"
            run_shellcheck
            ;;
    esac

    # Show summary and exit
    if show_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
