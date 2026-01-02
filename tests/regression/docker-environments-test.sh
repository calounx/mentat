#!/bin/bash
# ============================================================================
# Docker Environment Regression Test Suite
# ============================================================================
# Comprehensive regression testing for all Docker test environments
#
# Environments:
#   1. Main Test Environment (docker/docker-compose.yml)
#   2. VPS Simulation (docker/docker-compose.vps.yml)
#   3. Development Environment (chom/docker-compose.yml)
#
# Exit codes:
#   0 = All tests passed
#   1 = Warnings detected
#   2 = Failures detected
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
REPORT_DIR="${SCRIPT_DIR}/reports"

# Compose file paths
COMPOSE_MAIN="${REPO_ROOT}/docker/docker-compose.yml"
COMPOSE_VPS="${REPO_ROOT}/docker/docker-compose.vps.yml"
COMPOSE_DEV="${REPO_ROOT}/chom/docker-compose.yml"

# Test configuration
VERBOSE="${VERBOSE:-false}"
CLEANUP="${CLEANUP:-true}"
RUN_MAIN="${RUN_MAIN:-true}"
RUN_VPS="${RUN_VPS:-true}"
RUN_DEV="${RUN_DEV:-true}"
SKIP_PERSISTENCE="${SKIP_PERSISTENCE:-false}"

# Logging
export LOG_FILE="${REPORT_DIR}/test-execution.log"
export VERBOSE

# ============================================================================
# Source Libraries
# ============================================================================

source "${LIB_DIR}/test-utils.sh"
source "${LIB_DIR}/phase1-setup-tests.sh"
source "${LIB_DIR}/phase2-service-tests.sh"
source "${LIB_DIR}/phase3-integration-tests.sh"
source "${LIB_DIR}/phase4-persistence-tests.sh"

# ============================================================================
# Utility Functions
# ============================================================================

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Comprehensive regression testing for Docker test environments.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    --no-cleanup            Skip cleanup after tests
    --main-only             Only test main environment
    --vps-only              Only test VPS simulation
    --dev-only              Only test development environment
    --skip-persistence      Skip persistence tests (faster)
    --report-dir DIR        Custom report directory (default: ${REPORT_DIR})

EXAMPLES:
    # Run all tests
    $0

    # Run only main environment tests with verbose output
    $0 --main-only -v

    # Run tests without cleanup (for debugging)
    $0 --no-cleanup

    # Quick test without persistence checks
    $0 --skip-persistence

EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -v|--verbose)
                VERBOSE=true
                export VERBOSE
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --main-only)
                RUN_MAIN=true
                RUN_VPS=false
                RUN_DEV=false
                shift
                ;;
            --vps-only)
                RUN_MAIN=false
                RUN_VPS=true
                RUN_DEV=false
                shift
                ;;
            --dev-only)
                RUN_MAIN=false
                RUN_VPS=false
                RUN_DEV=true
                shift
                ;;
            --skip-persistence)
                SKIP_PERSISTENCE=true
                shift
                ;;
            --report-dir)
                REPORT_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

setup_environment() {
    log_info "Setting up test environment..."

    # Create report directory
    mkdir -p "${REPORT_DIR}"

    # Initialize log file
    echo "Docker Environment Regression Test - $(date -Iseconds)" > "${LOG_FILE}"
    echo "========================================================================" >> "${LOG_FILE}"

    # Check prerequisites
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        exit 2
    fi

    if ! command -v docker compose &>/dev/null; then
        log_error "Docker Compose is not installed"
        exit 2
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed (required for JSON parsing)"
        exit 2
    fi

    log_success "Environment setup complete"
}

cleanup_environment() {
    if [[ "${CLEANUP}" != "true" ]]; then
        log_info "Skipping cleanup (--no-cleanup flag set)"
        return 0
    fi

    log_info "Cleaning up test environments..."

    if [[ -f "${COMPOSE_MAIN}" ]]; then
        docker_compose_cleanup "${COMPOSE_MAIN}" || true
    fi

    if [[ -f "${COMPOSE_VPS}" ]]; then
        docker_compose_cleanup "${COMPOSE_VPS}" || true
    fi

    if [[ -f "${COMPOSE_DEV}" ]]; then
        docker_compose_cleanup "${COMPOSE_DEV}" || true
    fi

    log_success "Cleanup complete"
}

# ============================================================================
# Test Runners
# ============================================================================

test_main_environment() {
    log_info "========================================================================"
    log_info "Testing Main Test Environment"
    log_info "========================================================================"
    echo ""

    if [[ ! -f "${COMPOSE_MAIN}" ]]; then
        log_error "Main compose file not found: ${COMPOSE_MAIN}"
        return 1
    fi

    # Phase 1: Setup
    run_phase1_tests "${COMPOSE_MAIN}" || true

    # Phase 2: Services
    run_phase2_tests_main || true

    # Phase 3: Integration
    run_phase3_tests_main || true

    # Phase 4: Persistence
    if [[ "${SKIP_PERSISTENCE}" != "true" ]]; then
        run_phase4_tests "${COMPOSE_MAIN}" || true
    else
        log_info "Skipping persistence tests"
    fi

    echo ""
}

test_vps_environment() {
    log_info "========================================================================"
    log_info "Testing VPS Simulation Environment"
    log_info "========================================================================"
    echo ""

    if [[ ! -f "${COMPOSE_VPS}" ]]; then
        log_error "VPS compose file not found: ${COMPOSE_VPS}"
        return 1
    fi

    # Check if VPS base Dockerfile exists
    if [[ ! -f "${REPO_ROOT}/docker/vps-base/Dockerfile" ]]; then
        log_warn "VPS base Dockerfile not found, skipping VPS tests"
        return 0
    fi

    # Phase 1: Setup
    run_phase1_tests "${COMPOSE_VPS}" || true

    # Phase 2: Services
    run_phase2_tests_vps || true

    # Phase 3: Integration
    run_phase3_tests_vps || true

    # Phase 4: Persistence (skip for VPS as it's primarily for deployment testing)
    if [[ "${SKIP_PERSISTENCE}" != "true" ]]; then
        log_info "Skipping persistence tests for VPS (not applicable)"
    fi

    echo ""
}

test_dev_environment() {
    log_info "========================================================================"
    log_info "Testing Development Environment"
    log_info "========================================================================"
    echo ""

    if [[ ! -f "${COMPOSE_DEV}" ]]; then
        log_error "Dev compose file not found: ${COMPOSE_DEV}"
        return 1
    fi

    # Phase 1: Setup
    run_phase1_tests "${COMPOSE_DEV}" || true

    # Phase 2: Services
    run_phase2_tests_dev || true

    # Phase 3: Integration
    run_phase3_tests_dev || true

    # Phase 4: Persistence (limited for dev environment)
    if [[ "${SKIP_PERSISTENCE}" != "true" ]]; then
        log_info "Skipping full persistence tests for dev environment"
    fi

    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    local start_time
    local end_time

    start_time=$(date +%s)

    # Parse arguments
    parse_arguments "$@"

    # Setup
    setup_environment

    log_info ""
    log_info "========================================================================"
    log_info "Docker Environment Regression Test Suite"
    log_info "========================================================================"
    log_info "Timestamp: $(date -Iseconds)"
    log_info "Main Environment: ${RUN_MAIN}"
    log_info "VPS Simulation: ${RUN_VPS}"
    log_info "Dev Environment: ${RUN_DEV}"
    log_info "Skip Persistence: ${SKIP_PERSISTENCE}"
    log_info "Cleanup: ${CLEANUP}"
    log_info "========================================================================"
    echo ""

    # Run tests
    if [[ "${RUN_MAIN}" == "true" ]]; then
        test_main_environment || true
    fi

    if [[ "${RUN_VPS}" == "true" ]]; then
        test_vps_environment || true
    fi

    if [[ "${RUN_DEV}" == "true" ]]; then
        test_dev_environment || true
    fi

    # Cleanup
    cleanup_environment

    # Generate reports
    end_time=$(date +%s)

    log_info ""
    log_info "Generating test reports..."

    generate_json_report \
        "${REPORT_DIR}/test-results.json" \
        "Docker Environment Regression Tests" \
        "${start_time}" \
        "${end_time}"

    generate_markdown_report \
        "${REPORT_DIR}/test-results.md" \
        "Docker Environment Regression Tests" \
        "${start_time}" \
        "${end_time}"

    # Print summary
    print_summary

    # Performance benchmarks
    log_info "========================================================================"
    log_info "Performance Benchmarks"
    log_info "========================================================================"
    log_info "Total execution time: $((end_time - start_time))s"
    log_info "Log file: ${LOG_FILE}"
    log_info "JSON report: ${REPORT_DIR}/test-results.json"
    log_info "Markdown report: ${REPORT_DIR}/test-results.md"
    log_info "========================================================================"
    echo ""

    # Exit with appropriate code
    if [[ ${TEST_FAILED} -gt 0 ]]; then
        log_error "Test suite completed with failures"
        exit 2
    elif [[ ${TEST_WARNINGS} -gt 0 ]]; then
        log_warn "Test suite completed with warnings"
        exit 1
    else
        log_success "Test suite completed successfully"
        exit 0
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_environment EXIT

# Run main function
main "$@"
