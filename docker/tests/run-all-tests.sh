#!/usr/bin/env bash
#==============================================================================
# CHOM Test Environment - Master Test Runner
#==============================================================================
# Runs all regression tests for observability and CHOM features
#
# Usage:
#   ./run-all-tests.sh              # Run all tests
#   ./run-all-tests.sh observability # Run only observability tests
#   ./run-all-tests.sh chom          # Run only CHOM application tests
#   ./run-all-tests.sh integration   # Run only integration tests
#   ./run-all-tests.sh quick         # Run quick smoke tests only
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test results
declare -A SUITE_RESULTS=()
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
QUICK_MODE=false

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------
log_header() {
    echo ""
    echo -e "${CYAN}============================================================================${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}============================================================================${NC}"
    echo ""
}

log_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

run_test_suite() {
    local suite_name="$1"
    local script_path="$2"

    if [[ ! -f "$script_path" ]]; then
        log_warning "Test suite not found: $script_path"
        SUITE_RESULTS["$suite_name"]="SKIP"
        return 1
    fi

    if [[ ! -x "$script_path" ]]; then
        chmod +x "$script_path"
    fi

    log_section "Running: $suite_name"

    local exit_code=0
    "$script_path" || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        SUITE_RESULTS["$suite_name"]="PASS"
        log_success "$suite_name completed successfully"
    else
        SUITE_RESULTS["$suite_name"]="FAIL"
        log_error "$suite_name failed with exit code $exit_code"
    fi

    return $exit_code
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if containers are running
    local containers
    containers=$(docker ps --format "{{.Names}}" 2>/dev/null || echo "")

    if ! echo "$containers" | grep -q "mentat_tst"; then
        log_error "mentat_tst container is not running"
        echo "Start the test environment with: ./scripts/test-env.sh up"
        exit 1
    fi

    if ! echo "$containers" | grep -q "landsraad_tst"; then
        log_error "landsraad_tst container is not running"
        echo "Start the test environment with: ./scripts/test-env.sh up"
        exit 1
    fi

    # Check required tools
    if ! command -v curl &>/dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

run_observability_tests() {
    log_header "Observability Stack Tests"

    local failed=0

    run_test_suite "Prometheus" "${SCRIPT_DIR}/observability/test-prometheus.sh" || failed=$((failed + 1))
    run_test_suite "Loki" "${SCRIPT_DIR}/observability/test-loki.sh" || failed=$((failed + 1))
    run_test_suite "Grafana" "${SCRIPT_DIR}/observability/test-grafana.sh" || failed=$((failed + 1))
    run_test_suite "Alertmanager" "${SCRIPT_DIR}/observability/test-alertmanager.sh" || failed=$((failed + 1))
    run_test_suite "Tempo" "${SCRIPT_DIR}/observability/test-tempo.sh" || failed=$((failed + 1))

    return $failed
}

run_chom_tests() {
    log_header "CHOM Application Tests"

    local failed=0

    run_test_suite "Webserver" "${SCRIPT_DIR}/chom/test-webserver.sh" || failed=$((failed + 1))
    run_test_suite "Application" "${SCRIPT_DIR}/chom/test-application.sh" || failed=$((failed + 1))

    return $failed
}

run_integration_tests() {
    log_header "Integration Tests"

    local failed=0

    run_test_suite "Metrics Flow" "${SCRIPT_DIR}/integration/test-metrics-flow.sh" || failed=$((failed + 1))
    run_test_suite "Logs Flow" "${SCRIPT_DIR}/integration/test-logs-flow.sh" || failed=$((failed + 1))

    return $failed
}

run_quick_tests() {
    log_header "Quick Smoke Tests"

    local failed=0

    # Quick connectivity checks
    log_section "Service Connectivity"

    echo -n "Prometheus... "
    if curl -sf "http://10.10.100.10:9090/-/healthy" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
    fi

    echo -n "Grafana... "
    if curl -sf "http://10.10.100.10:3000/api/health" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
    fi

    echo -n "Loki... "
    if curl -sf "http://10.10.100.10:3100/ready" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
    fi

    echo -n "Tempo... "
    if curl -sf "http://10.10.100.10:3200/ready" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
    fi

    echo -n "Alertmanager... "
    if curl -sf "http://10.10.100.10:9093/-/healthy" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
    fi

    echo -n "CHOM Web... "
    if curl -sf "http://10.10.100.20/health" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
    fi

    return $failed
}

print_summary() {
    local quick_failed="${1:-0}"

    log_header "Test Summary"

    local total_suites=${#SUITE_RESULTS[@]}

    if [[ $total_suites -eq 0 ]]; then
        # Quick mode - no test suites recorded
        if [[ "$quick_failed" -eq 0 ]]; then
            echo -e "${GREEN}${BOLD}All quick checks passed!${NC}"
            return 0
        else
            echo -e "${RED}${BOLD}$quick_failed quick check(s) failed!${NC}"
            return 1
        fi
    fi

    echo "Suite Results:"
    echo ""

    for suite in "${!SUITE_RESULTS[@]}"; do
        local result="${SUITE_RESULTS[$suite]}"
        local color="${NC}"

        case "$result" in
            PASS) color="${GREEN}" ;;
            FAIL) color="${RED}" ;;
            SKIP) color="${YELLOW}" ;;
        esac

        printf "  %-20s %b%s%b\n" "$suite" "$color" "$result" "$NC"
    done

    echo ""
    echo -e "${BLUE}============================================================================${NC}"

    local passed_suites=0
    local failed_suites=0

    for result in "${SUITE_RESULTS[@]}"; do
        case "$result" in
            PASS) passed_suites=$((passed_suites + 1)) ;;
            FAIL) failed_suites=$((failed_suites + 1)) ;;
        esac
    done

    echo -e "  ${GREEN}Passed Suites:${NC} $passed_suites / $total_suites"
    echo -e "  ${RED}Failed Suites:${NC} $failed_suites / $total_suites"
    echo -e "${BLUE}============================================================================${NC}"
    echo ""

    if [[ $failed_suites -gt 0 ]]; then
        echo -e "${RED}${BOLD}Some tests failed!${NC}"
        return 1
    else
        echo -e "${GREEN}${BOLD}All test suites passed!${NC}"
        return 0
    fi
}

usage() {
    echo "CHOM Test Environment - Master Test Runner"
    echo ""
    echo "Usage: $0 [suite]"
    echo ""
    echo "Suites:"
    echo "  all           Run all test suites (default)"
    echo "  observability Run observability stack tests"
    echo "  chom          Run CHOM application tests"
    echo "  integration   Run integration tests"
    echo "  quick         Run quick smoke tests only"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 observability      # Run only Prometheus, Loki, etc. tests"
    echo "  $0 quick              # Quick health check of all services"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    local suite="${1:-all}"

    log_header "CHOM Test Environment - Regression Tests"
    echo "  mentat_tst (10.10.100.10): Observability Stack"
    echo "  landsraad_tst (10.10.100.20): CHOM Application"
    echo ""

    check_prerequisites

    local total_failed=0

    case "$suite" in
        all)
            run_observability_tests || ((total_failed+=$?))
            run_chom_tests || ((total_failed+=$?))
            run_integration_tests || ((total_failed+=$?))
            ;;
        observability)
            run_observability_tests || ((total_failed+=$?))
            ;;
        chom|application)
            run_chom_tests || ((total_failed+=$?))
            ;;
        integration)
            run_integration_tests || ((total_failed+=$?))
            ;;
        quick|smoke)
            run_quick_tests || ((total_failed+=$?))
            ;;
        help|-h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown suite: $suite"
            usage
            exit 1
            ;;
    esac

    print_summary "$total_failed"

    if [[ $total_failed -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
