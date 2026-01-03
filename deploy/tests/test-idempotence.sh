#!/usr/bin/env bash
# Idempotence Testing Framework
# Tests that deployment scripts can be run multiple times safely
# Usage: ./test-idempotence.sh [--script PATH] [--iterations N] [--cleanup]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
TEST_ITERATIONS="${TEST_ITERATIONS:-2}"
TEST_SCRIPT="${TEST_SCRIPT:-}"
CLEANUP_AFTER_TEST=false
TEST_MODE="safe"  # safe, aggressive
SNAPSHOT_DIR="/tmp/idempotence-snapshots"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --script)
            TEST_SCRIPT="$2"
            shift 2
            ;;
        --iterations)
            TEST_ITERATIONS="$2"
            shift 2
            ;;
        --cleanup)
            CLEANUP_AFTER_TEST=true
            shift
            ;;
        --aggressive)
            TEST_MODE="aggressive"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--script PATH] [--iterations N] [--cleanup] [--aggressive]"
            exit 1
            ;;
    esac
done

init_deployment_log "test-idempotence-$(date +%Y%m%d_%H%M%S)"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# SNAPSHOT AND COMPARISON FUNCTIONS
# ============================================================================

# Create system snapshot before running script
create_snapshot() {
    local snapshot_name="$1"
    local snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}"

    mkdir -p "$snapshot_path"

    log_step "Creating system snapshot: $snapshot_name"

    # Capture list of users
    getent passwd > "${snapshot_path}/users.txt"

    # Capture list of groups
    getent group > "${snapshot_path}/groups.txt"

    # Capture list of installed packages
    dpkg -l > "${snapshot_path}/packages.txt" 2>/dev/null || true

    # Capture list of systemd services
    systemctl list-units --type=service --all --no-pager > "${snapshot_path}/services.txt" 2>/dev/null || true

    # Capture enabled services
    systemctl list-unit-files --type=service --no-pager > "${snapshot_path}/enabled-services.txt" 2>/dev/null || true

    # Capture directory tree of key locations
    for dir in /opt /etc/systemd/system /etc/observability /var/lib/observability; do
        if [[ -d "$dir" ]]; then
            local dir_name=$(echo "$dir" | tr '/' '_')
            find "$dir" -type f -o -type d 2>/dev/null | sort > "${snapshot_path}/tree${dir_name}.txt" || true
        fi
    done

    # Capture UFW status
    sudo ufw status numbered > "${snapshot_path}/ufw-status.txt" 2>/dev/null || echo "UFW not available" > "${snapshot_path}/ufw-status.txt"

    # Capture listening ports
    sudo netstat -tuln > "${snapshot_path}/listening-ports.txt" 2>/dev/null || \
    sudo ss -tuln > "${snapshot_path}/listening-ports.txt" 2>/dev/null || true

    # Capture sysctl settings
    sudo sysctl -a 2>/dev/null | sort > "${snapshot_path}/sysctl.txt" || true

    # Capture cron jobs
    sudo crontab -l > "${snapshot_path}/root-crontab.txt" 2>/dev/null || echo "No root crontab" > "${snapshot_path}/root-crontab.txt"

    log_success "Snapshot created: $snapshot_name"
}

# Compare two snapshots and report differences
compare_snapshots() {
    local snapshot1="$1"
    local snapshot2="$2"

    local path1="${SNAPSHOT_DIR}/${snapshot1}"
    local path2="${SNAPSHOT_DIR}/${snapshot2}"

    log_step "Comparing snapshots: $snapshot1 vs $snapshot2"

    local differences_found=0

    # Compare each snapshot file
    for file in "$path1"/*.txt; do
        local filename=$(basename "$file")
        local file2="${path2}/${filename}"

        if [[ ! -f "$file2" ]]; then
            log_warning "File missing in second snapshot: $filename"
            continue
        fi

        if ! diff -u "$file" "$file2" > /dev/null 2>&1; then
            log_warning "Differences found in: $filename"
            differences_found=$((differences_found + 1))

            # Show diff summary (first 20 lines)
            echo "--- Diff for $filename ---"
            diff -u "$file" "$file2" | head -20
            echo ""
        fi
    done

    if [[ $differences_found -eq 0 ]]; then
        log_success "No differences found - script is idempotent!"
        return 0
    else
        log_warning "Found $differences_found difference(s) between snapshots"
        log_warning "This may indicate non-idempotent behavior"
        return 1
    fi
}

# ============================================================================
# TEST EXECUTION FUNCTIONS
# ============================================================================

# Run a script and capture its exit code and output
run_script_iteration() {
    local script_path="$1"
    local iteration="$2"

    log_section "Running iteration $iteration: $(basename "$script_path")"

    local start_time=$(date +%s)
    local output_file="${SNAPSHOT_DIR}/output-iteration-${iteration}.log"

    # Run the script and capture output
    if bash "$script_path" > "$output_file" 2>&1; then
        local exit_code=0
    else
        local exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "Iteration $iteration completed in ${duration}s with exit code: $exit_code"

    # Show last 30 lines of output
    echo "--- Last 30 lines of output ---"
    tail -30 "$output_file"
    echo ""

    return $exit_code
}

# Test a single script for idempotence
test_script_idempotence() {
    local script_path="$1"

    log_section "Testing Idempotence: $(basename "$script_path")"

    if [[ ! -f "$script_path" ]]; then
        log_error "Script not found: $script_path"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    if [[ ! -x "$script_path" ]]; then
        log_warning "Script is not executable, making it executable"
        chmod +x "$script_path"
    fi

    # Create snapshots directory
    rm -rf "$SNAPSHOT_DIR"
    mkdir -p "$SNAPSHOT_DIR"

    # Create initial baseline snapshot
    create_snapshot "baseline"

    local iteration=1
    local all_iterations_passed=true

    while [[ $iteration -le $TEST_ITERATIONS ]]; do
        log_info "=== Iteration $iteration/$TEST_ITERATIONS ==="

        # Create pre-run snapshot
        create_snapshot "pre-iteration-${iteration}"

        # Run the script
        if run_script_iteration "$script_path" "$iteration"; then
            log_success "Iteration $iteration: Script executed successfully"
        else
            log_error "Iteration $iteration: Script failed with exit code $?"
            all_iterations_passed=false
            break
        fi

        # Create post-run snapshot
        create_snapshot "post-iteration-${iteration}"

        # Compare snapshots for this iteration
        if [[ $iteration -gt 1 ]]; then
            if compare_snapshots "post-iteration-$((iteration - 1))" "post-iteration-${iteration}"; then
                log_success "Iteration $iteration: No changes detected (idempotent)"
            else
                log_warning "Iteration $iteration: Changes detected (may not be idempotent)"
                all_iterations_passed=false
            fi
        fi

        iteration=$((iteration + 1))
        sleep 2  # Brief pause between iterations
    done

    # Final comparison: compare last iteration to baseline
    log_section "Final Idempotence Check"
    if compare_snapshots "post-iteration-1" "post-iteration-${TEST_ITERATIONS}"; then
        log_success "Script is idempotent: Multiple runs produce identical results"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "Script may not be idempotent: Multiple runs produce different results"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# AUTOMATED SCRIPT DISCOVERY AND TESTING
# ============================================================================

# Discover all deployment scripts
discover_deployment_scripts() {
    local deploy_dir="${SCRIPT_DIR}/../scripts"

    log_section "Discovering Deployment Scripts"

    local scripts=(
        "${deploy_dir}/prepare-mentat.sh"
        "${deploy_dir}/prepare-landsraad.sh"
        "${deploy_dir}/deploy-application.sh"
        "${deploy_dir}/deploy-observability.sh"
        "${deploy_dir}/setup-firewall.sh"
        "${deploy_dir}/setup-ssl.sh"
    )

    echo "${scripts[@]}"
}

# Test all discovered scripts
test_all_scripts() {
    log_section "Testing All Deployment Scripts"

    local scripts=($(discover_deployment_scripts))
    local total_scripts=${#scripts[@]}

    log_info "Found $total_scripts scripts to test"

    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo ""
            echo "=========================================="
            test_script_idempotence "$script"
            echo "=========================================="
            echo ""
        else
            log_warning "Script not found: $script"
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        fi
    done
}

# ============================================================================
# SERVICE HEALTH CHECKS
# ============================================================================

# Verify services are still running after script execution
check_service_health() {
    log_section "Service Health Checks"

    local services=(
        "sshd"
        "ssh"
    )

    local failed_services=()

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_success "Service is running: $service"
        else
            # Service might not be installed, check if it exists
            if systemctl list-unit-files "$service.service" &>/dev/null; then
                log_error "Service is not running: $service"
                failed_services+=("$service")
            fi
        fi
    done

    if [[ ${#failed_services[@]} -eq 0 ]]; then
        return 0
    else
        log_error "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# ============================================================================
# SAFETY CHECKS
# ============================================================================

# Check if running in a safe environment for testing
check_test_environment() {
    log_section "Test Environment Safety Checks"

    # Warn if running on production
    if [[ -f /etc/production ]]; then
        log_error "This appears to be a production system!"
        log_error "Idempotence testing should NOT be run on production"
        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            exit 1
        fi
    fi

    # Check if running with appropriate privileges
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root - this is allowed but not recommended"
    else
        if ! sudo -n true 2>/dev/null; then
            log_error "Sudo access is required for idempotence testing"
            exit 1
        fi
    fi

    log_success "Test environment checks passed"
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

# Clean up test artifacts
cleanup_test_artifacts() {
    if [[ "$CLEANUP_AFTER_TEST" == true ]]; then
        log_section "Cleaning Up Test Artifacts"

        if [[ -d "$SNAPSHOT_DIR" ]]; then
            rm -rf "$SNAPSHOT_DIR"
            log_success "Removed snapshot directory"
        fi

        log_success "Cleanup complete"
    else
        log_info "Snapshot data preserved at: $SNAPSHOT_DIR"
        log_info "Use --cleanup flag to remove after testing"
    fi
}

# ============================================================================
# REPORTING
# ============================================================================

# Generate test report
generate_report() {
    log_section "Idempotence Test Report"

    log_info "Tests passed:  $TESTS_PASSED"
    log_info "Tests failed:  $TESTS_FAILED"
    log_info "Tests skipped: $TESTS_SKIPPED"

    local total_tests=$((TESTS_PASSED + TESTS_FAILED))

    if [[ $total_tests -gt 0 ]]; then
        local pass_rate=$(( (TESTS_PASSED * 100) / total_tests ))
        log_info "Pass rate: ${pass_rate}%"
    fi

    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All idempotence tests passed!"
        return 0
    else
        log_error "Some idempotence tests failed"
        log_info "Review the output above for details"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    start_timer

    print_header "Idempotence Testing Framework"

    # Safety checks
    check_test_environment

    # Service health check before testing
    check_service_health

    # Run tests
    if [[ -n "$TEST_SCRIPT" ]]; then
        # Test single script
        test_script_idempotence "$TEST_SCRIPT"
    else
        # Test all scripts
        test_all_scripts
    fi

    # Service health check after testing
    check_service_health

    # Cleanup
    cleanup_test_artifacts

    end_timer "Idempotence testing"

    # Generate report
    generate_report

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main
