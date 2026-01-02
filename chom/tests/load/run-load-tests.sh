#!/bin/bash

################################################################################
# CHOM Load Testing Execution Script
#
# This script automates the execution of k6 load tests for the CHOM application.
# It supports running individual tests, test suites, and custom scenarios.
#
# Usage:
#   ./run-load-tests.sh [OPTIONS]
#
# Options:
#   --scenario <name>    Run specific scenario (auth, sites, backups, ramp-up,
#                        sustained, spike, soak, stress, all)
#   --base-url <url>     Override base URL (default: http://localhost:8000)
#   --duration <time>    Override test duration (e.g., 5m, 30s)
#   --vus <number>       Override number of virtual users
#   --output <dir>       Output directory for results (default: results/)
#   --format <format>    Output format: json, csv, influxdb (default: json)
#   --help              Show this help message
#
# Examples:
#   ./run-load-tests.sh --scenario auth
#   ./run-load-tests.sh --scenario all --base-url http://staging:8000
#   ./run-load-tests.sh --scenario sustained --vus 50 --duration 5m
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SCENARIO=""
BASE_URL="${BASE_URL:-http://localhost:8000}"
DURATION=""
VUS=""
OUTPUT_DIR="results"
OUTPUT_FORMAT="json"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

################################################################################
# Functions
################################################################################

print_banner() {
    echo -e "${BLUE}"
    echo "================================================================================"
    echo "  CHOM Load Testing Framework"
    echo "  Version 1.0.0"
    echo "================================================================================"
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Usage: ./run-load-tests.sh [OPTIONS]

Options:
  --scenario <name>    Run specific scenario:
                       - auth: Authentication flow test
                       - sites: Site management test
                       - backups: Backup operations test
                       - ramp-up: Ramp-up scenario
                       - sustained: Sustained load scenario
                       - spike: Spike test scenario
                       - soak: Soak test scenario
                       - stress: Stress test scenario
                       - all: Run all tests

  --base-url <url>     Base URL for tests (default: http://localhost:8000)
  --duration <time>    Override test duration (e.g., 5m, 30s)
  --vus <number>       Override number of virtual users
  --output <dir>       Output directory for results (default: results/)
  --format <format>    Output format: json, csv, influxdb (default: json)
  --help              Show this help message

Examples:
  # Run authentication flow test
  ./run-load-tests.sh --scenario auth

  # Run all tests
  ./run-load-tests.sh --scenario all

  # Run sustained load test with custom settings
  ./run-load-tests.sh --scenario sustained --vus 50 --duration 5m

  # Run tests against staging environment
  ./run-load-tests.sh --scenario all --base-url http://staging.chom.local:8000

EOF
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if k6 is installed
    if ! command -v k6 &> /dev/null; then
        print_error "k6 is not installed. Please install it first."
        echo "  macOS: brew install k6"
        echo "  Linux: See https://k6.io/docs/getting-started/installation/"
        exit 1
    fi

    print_success "k6 is installed: $(k6 version)"

    # Check if application is accessible
    print_info "Checking if CHOM application is accessible at $BASE_URL..."
    if curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/health" | grep -q "200"; then
        print_success "Application is accessible"
    else
        print_warning "Application health check failed. Continuing anyway..."
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    print_success "Output directory ready: $OUTPUT_DIR"
}

run_test() {
    local test_file=$1
    local test_name=$2
    local output_file="${OUTPUT_DIR}/${test_name}_${TIMESTAMP}.${OUTPUT_FORMAT}"

    print_info "Starting test: $test_name"
    print_info "Test file: $test_file"
    print_info "Output: $output_file"
    echo ""

    # Build k6 command
    local k6_cmd="k6 run"

    # Add duration override
    if [ -n "$DURATION" ]; then
        k6_cmd="$k6_cmd --duration $DURATION"
    fi

    # Add VUs override
    if [ -n "$VUS" ]; then
        k6_cmd="$k6_cmd --vus $VUS"
    fi

    # Add output format
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        k6_cmd="$k6_cmd --out json=$output_file"
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        k6_cmd="$k6_cmd --out csv=$output_file"
    fi

    # Add environment variables
    k6_cmd="BASE_URL=$BASE_URL $k6_cmd"

    # Add test file
    k6_cmd="$k6_cmd $test_file"

    # Execute test
    echo -e "${BLUE}Executing: $k6_cmd${NC}"
    echo ""

    if eval "$k6_cmd"; then
        print_success "Test completed successfully: $test_name"
        echo ""
    else
        print_error "Test failed: $test_name"
        return 1
    fi
}

run_scenario() {
    local scenario=$1

    case $scenario in
        auth)
            run_test "scripts/auth-flow.js" "auth-flow"
            ;;
        sites)
            run_test "scripts/site-management.js" "site-management"
            ;;
        backups)
            run_test "scripts/backup-operations.js" "backup-operations"
            ;;
        ramp-up)
            run_test "scenarios/ramp-up-test.js" "ramp-up-test"
            ;;
        sustained)
            run_test "scenarios/sustained-load-test.js" "sustained-load-test"
            ;;
        spike)
            run_test "scenarios/spike-test.js" "spike-test"
            ;;
        soak)
            run_test "scenarios/soak-test.js" "soak-test"
            ;;
        stress)
            run_test "scenarios/stress-test.js" "stress-test"
            ;;
        all)
            print_info "Running complete test suite..."
            echo ""

            # Run all tests in sequence
            run_test "scripts/auth-flow.js" "auth-flow"
            run_test "scripts/site-management.js" "site-management"
            run_test "scripts/backup-operations.js" "backup-operations"
            run_test "scenarios/ramp-up-test.js" "ramp-up-test"
            run_test "scenarios/sustained-load-test.js" "sustained-load-test"
            run_test "scenarios/spike-test.js" "spike-test"

            print_success "Complete test suite finished"
            ;;
        *)
            print_error "Unknown scenario: $scenario"
            echo "Valid scenarios: auth, sites, backups, ramp-up, sustained, spike, soak, stress, all"
            exit 1
            ;;
    esac
}

generate_summary() {
    print_info "Generating test summary..."

    echo ""
    echo "================================================================================"
    echo "  Test Summary"
    echo "================================================================================"
    echo "Scenario: $SCENARIO"
    echo "Base URL: $BASE_URL"
    echo "Timestamp: $TIMESTAMP"
    echo "Results Directory: $OUTPUT_DIR"
    echo ""

    # List result files
    echo "Generated Files:"
    ls -lh "$OUTPUT_DIR"/*_${TIMESTAMP}.* 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    echo ""

    print_success "All tests completed!"
    echo ""
    echo "Next Steps:"
    echo "  1. Review results in: $OUTPUT_DIR"
    echo "  2. Analyze performance metrics"
    echo "  3. Compare with baselines: ./compare-results.sh"
    echo "  4. Generate HTML report: ./generate-report.sh"
    echo ""
}

################################################################################
# Main Script
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario)
                SCENARIO="$2"
                shift 2
                ;;
            --base-url)
                BASE_URL="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            --vus)
                VUS="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$SCENARIO" ]; then
        print_error "Scenario is required"
        show_help
        exit 1
    fi

    # Print banner
    print_banner

    # Check prerequisites
    check_prerequisites

    echo ""
    echo "================================================================================"
    echo "  Test Configuration"
    echo "================================================================================"
    echo "Scenario: $SCENARIO"
    echo "Base URL: $BASE_URL"
    echo "Output Directory: $OUTPUT_DIR"
    echo "Output Format: $OUTPUT_FORMAT"
    [ -n "$DURATION" ] && echo "Duration Override: $DURATION"
    [ -n "$VUS" ] && echo "VUs Override: $VUS"
    echo "Timestamp: $TIMESTAMP"
    echo "================================================================================"
    echo ""

    # Run scenario
    run_scenario "$SCENARIO"

    # Generate summary
    generate_summary
}

# Execute main function
main "$@"
