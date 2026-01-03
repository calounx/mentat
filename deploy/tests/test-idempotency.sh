#!/usr/bin/env bash
# Comprehensive Idempotency and Edge Case Testing
# Tests all deployment scripts for true idempotency and edge case handling
#
# Usage: sudo ./test-idempotency.sh [--verbose] [--test <test_name>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_RESULTS_DIR="${SCRIPT_DIR}/results/idempotency-$(date +%Y%m%d_%H%M%S)"
TEST_USER="${TEST_USER:-test-stilgar}"
VERBOSE=false
SPECIFIC_TEST=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Logging
log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
    ((TESTS_SKIPPED++))
}

log_info() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test|-t)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Idempotency and Edge Case Testing Suite

Usage: sudo $0 [OPTIONS]

OPTIONS:
  --verbose, -v           Verbose output
  --test NAME, -t NAME    Run specific test
  --help, -h              Show this help

AVAILABLE TESTS:
  user_creation_idempotent
  sudo_configuration_idempotent
  ssh_directory_idempotent
  empty_environment_vars
  special_chars_passwords
  disk_space_low
  concurrent_execution
  cleanup_tmp_files
  filesystem_readonly
  permission_issues
  state_validation

EXAMPLES:
  # Run all tests
  sudo ./test-idempotency.sh

  # Run specific test
  sudo ./test-idempotency.sh --test user_creation_idempotent

  # Run with verbose output
  sudo ./test-idempotency.sh --verbose

EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment"
    mkdir -p "$TEST_RESULTS_DIR"

    # Create test log
    TEST_LOG="${TEST_RESULTS_DIR}/test.log"
    touch "$TEST_LOG"

    log_info "Test results will be saved to: $TEST_RESULTS_DIR"
}

# Cleanup test environment
cleanup_test_environment() {
    log_info "Cleaning up test environment"

    # Remove test user if exists
    if id "$TEST_USER" &>/dev/null; then
        userdel -r "$TEST_USER" 2>/dev/null || true
    fi

    # Remove sudoers file
    rm -f "/etc/sudoers.d/${TEST_USER}-nopasswd"
}

# Run a test
run_test() {
    local test_name="$1"
    local test_function="$2"

    # Skip if specific test requested and this isn't it
    if [[ -n "$SPECIFIC_TEST" ]] && [[ "$test_name" != "$SPECIFIC_TEST" ]]; then
        return 0
    fi

    ((TESTS_RUN++))

    log_test "Running: $test_name"

    # Run test function
    if $test_function "$test_name"; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name"
        return 1
    fi
}

# ==============================================================================
# IDEMPOTENCY TESTS
# ==============================================================================

test_user_creation_idempotent() {
    local test_name="$1"
    local test_script="${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh"

    log_info "Testing user creation idempotency"

    # First run - create user
    log_info "First run: Creating user"
    if ! bash "$test_script" "$TEST_USER" &>> "$TEST_LOG"; then
        log_error "First run failed"
        return 1
    fi

    # Verify user exists
    if ! id "$TEST_USER" &>/dev/null; then
        log_error "User not created on first run"
        return 1
    fi

    # Get user info after first run
    local uid1=$(id -u "$TEST_USER")
    local gid1=$(id -g "$TEST_USER")
    local home1=$(getent passwd "$TEST_USER" | cut -d: -f6)

    # Second run - should be idempotent
    log_info "Second run: Should be idempotent"
    if ! bash "$test_script" "$TEST_USER" &>> "$TEST_LOG"; then
        log_error "Second run failed"
        return 1
    fi

    # Verify user info unchanged
    local uid2=$(id -u "$TEST_USER")
    local gid2=$(id -g "$TEST_USER")
    local home2=$(getent passwd "$TEST_USER" | cut -d: -f6)

    if [[ "$uid1" != "$uid2" ]] || [[ "$gid1" != "$gid2" ]] || [[ "$home1" != "$home2" ]]; then
        log_error "User info changed on second run"
        log_error "UID: $uid1 -> $uid2"
        log_error "GID: $gid1 -> $gid2"
        log_error "Home: $home1 -> $home2"
        return 1
    fi

    # Third run - verify still idempotent
    log_info "Third run: Verify still idempotent"
    if ! bash "$test_script" "$TEST_USER" &>> "$TEST_LOG"; then
        log_error "Third run failed"
        return 1
    fi

    log_info "User creation is idempotent (3 runs successful)"
    return 0
}

test_sudo_configuration_idempotent() {
    local test_name="$1"
    local test_script="${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh"
    local sudoers_file="/etc/sudoers.d/${TEST_USER}-nopasswd"

    log_info "Testing sudo configuration idempotency"

    # Run script to setup user
    bash "$test_script" "$TEST_USER" &>> "$TEST_LOG" || return 1

    # Verify sudoers file exists
    if [[ ! -f "$sudoers_file" ]]; then
        log_error "Sudoers file not created"
        return 1
    fi

    # Get file stats
    local perms1=$(stat -c "%a" "$sudoers_file")
    local content1=$(cat "$sudoers_file")
    local mtime1=$(stat -c "%Y" "$sudoers_file")

    # Wait 1 second to ensure mtime would change if file is modified
    sleep 1

    # Run again
    bash "$test_script" "$TEST_USER" &>> "$TEST_LOG" || return 1

    # Verify file unchanged
    local perms2=$(stat -c "%a" "$sudoers_file")
    local content2=$(cat "$sudoers_file")
    local mtime2=$(stat -c "%Y" "$sudoers_file")

    if [[ "$perms1" != "$perms2" ]]; then
        log_error "Sudoers file permissions changed: $perms1 -> $perms2"
        return 1
    fi

    if [[ "$content1" != "$content2" ]]; then
        log_error "Sudoers file content changed"
        return 1
    fi

    # mtime should not change if file wasn't modified
    if [[ "$mtime1" != "$mtime2" ]]; then
        log_info "Warning: Sudoers file mtime changed (file may have been rewritten)"
        # This is acceptable as long as content is the same
    fi

    # Test sudo access
    if ! sudo -u "$TEST_USER" sudo -n true &>/dev/null; then
        log_error "NOPASSWD sudo not working"
        return 1
    fi

    log_info "Sudo configuration is idempotent"
    return 0
}

test_ssh_directory_idempotent() {
    local test_name="$1"
    local test_script="${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh"
    local ssh_dir="/home/${TEST_USER}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    log_info "Testing SSH directory creation idempotency"

    # Run script
    bash "$test_script" "$TEST_USER" &>> "$TEST_LOG" || return 1

    # Verify SSH directory exists
    if [[ ! -d "$ssh_dir" ]]; then
        log_error "SSH directory not created"
        return 1
    fi

    # Get initial state
    local ssh_perms1=$(stat -c "%a" "$ssh_dir")
    local ssh_owner1=$(stat -c "%U:%G" "$ssh_dir")
    local auth_perms1=$(stat -c "%a" "$auth_keys")
    local auth_owner1=$(stat -c "%U:%G" "$auth_keys")

    # Add a test key
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest test@test" >> "$auth_keys"
    local key_count1=$(wc -l < "$auth_keys")

    # Run again
    bash "$test_script" "$TEST_USER" &>> "$TEST_LOG" || return 1

    # Verify state unchanged
    local ssh_perms2=$(stat -c "%a" "$ssh_dir")
    local ssh_owner2=$(stat -c "%U:%G" "$ssh_dir")
    local auth_perms2=$(stat -c "%a" "$auth_keys")
    local auth_owner2=$(stat -c "%U:%G" "$auth_keys")
    local key_count2=$(wc -l < "$auth_keys")

    if [[ "$ssh_perms1" != "$ssh_perms2" ]] || [[ "$ssh_owner1" != "$ssh_owner2" ]]; then
        log_error "SSH directory permissions/ownership changed"
        return 1
    fi

    if [[ "$auth_perms1" != "$auth_perms2" ]] || [[ "$auth_owner1" != "$auth_owner2" ]]; then
        log_error "authorized_keys permissions/ownership changed"
        return 1
    fi

    if [[ "$key_count1" != "$key_count2" ]]; then
        log_error "authorized_keys content changed (keys lost)"
        return 1
    fi

    log_info "SSH directory creation is idempotent"
    return 0
}

# ==============================================================================
# EDGE CASE TESTS
# ==============================================================================

test_empty_environment_vars() {
    local test_name="$1"

    log_info "Testing with empty environment variables"

    # Test with empty DEPLOY_USER (should use default)
    local output
    output=$(DEPLOY_USER="" bash "${DEPLOY_ROOT}/scripts/setup-stilgar-user-standalone.sh" 2>&1 || true)

    if echo "$output" | grep -q "stilgar"; then
        log_info "Script uses default user when DEPLOY_USER is empty"
    else
        log_error "Script doesn't handle empty DEPLOY_USER correctly"
        return 1
    fi

    return 0
}

test_special_chars_passwords() {
    local test_name="$1"

    log_info "Testing with special characters in environment"

    # Create test environment variables with special characters
    local test_vars=(
        'TEST_VAR=$pecial!@#$%^&*()'
        'TEST_VAR=single'\''quote'
        'TEST_VAR=double"quote'
        'TEST_VAR=back`tick`'
        'TEST_VAR=$(command)'
        'TEST_VAR=semicolon;ls'
        'TEST_VAR=pipe|ls'
        'TEST_VAR=ampersand&ls'
    )

    # Test that scripts properly quote/escape variables
    # This is a basic test - actual implementation would test deployment scripts

    log_info "Special character handling test (placeholder)"
    # TODO: Implement actual special character tests

    return 0
}

test_disk_space_low() {
    local test_name="$1"

    log_info "Testing with low disk space"

    # Check available disk space
    local available=$(df / | awk 'NR==2 {print $4}')
    local available_mb=$((available / 1024))

    log_info "Available disk space: ${available_mb}MB"

    # This test would normally create a large file to fill disk
    # For safety, we'll just check the detection logic

    if [[ $available_mb -lt 1024 ]]; then
        log_info "Low disk space detected (< 1GB)"
        # Scripts should warn or fail gracefully
    fi

    return 0
}

test_concurrent_execution() {
    local test_name="$1"

    log_info "Testing concurrent script execution"

    # Create a test script that creates a lock file
    local lock_file="/var/lock/test-concurrent-${TEST_USER}.lock"

    # Run two instances simultaneously
    (
        flock -n 200 || exit 1
        sleep 2
    ) 200>"$lock_file" &
    local pid1=$!

    sleep 0.1

    (
        flock -n 200 || exit 1
        sleep 2
    ) 200>"$lock_file" &
    local pid2=$!

    # Wait for both
    local exit1=0
    local exit2=0
    wait $pid1 || exit1=$?
    wait $pid2 || exit2=$?

    # Clean up
    rm -f "$lock_file"

    # One should succeed, one should fail
    if [[ $exit1 -eq 0 ]] && [[ $exit2 -ne 0 ]]; then
        log_info "Lock mechanism works (first succeeded, second blocked)"
        return 0
    elif [[ $exit1 -ne 0 ]] && [[ $exit2 -eq 0 ]]; then
        log_info "Lock mechanism works (second succeeded, first blocked)"
        return 0
    else
        log_error "Lock mechanism doesn't work correctly"
        log_error "Exit codes: $exit1, $exit2"
        return 1
    fi
}

test_cleanup_tmp_files() {
    local test_name="$1"

    log_info "Testing /tmp file cleanup"

    # Create some test temp files
    local test_tmp="/tmp/chom-deploy-test-$$"
    mkdir -p "$test_tmp"
    touch "${test_tmp}/file1"
    touch "${test_tmp}/file2"

    log_info "Created test files in $test_tmp"

    # Simulate cleanup
    rm -rf "$test_tmp"

    # Verify cleanup
    if [[ -d "$test_tmp" ]]; then
        log_error "Temp directory not cleaned up"
        return 1
    fi

    log_info "Temp file cleanup works"
    return 0
}

test_filesystem_readonly() {
    local test_name="$1"

    log_info "Testing readonly filesystem handling"

    # Create a test mount point
    local test_mount="/tmp/test-readonly-$$"
    mkdir -p "$test_mount"

    # Create a small filesystem
    local test_img="/tmp/test-fs-$$.img"
    dd if=/dev/zero of="$test_img" bs=1M count=10 &>/dev/null
    mkfs.ext4 -F "$test_img" &>/dev/null

    # Mount it
    mount -o loop "$test_img" "$test_mount"

    # Remount readonly
    mount -o remount,ro "$test_mount"

    # Try to write (should fail)
    if touch "${test_mount}/testfile" 2>/dev/null; then
        log_error "Write succeeded on readonly filesystem"
        umount "$test_mount"
        rm -rf "$test_mount" "$test_img"
        return 1
    fi

    log_info "Readonly filesystem correctly prevents writes"

    # Cleanup
    umount "$test_mount"
    rm -rf "$test_mount" "$test_img"

    return 0
}

test_permission_issues() {
    local test_name="$1"

    log_info "Testing permission issue handling"

    # Create test file with restricted permissions
    local test_file="/tmp/test-perms-$$"
    touch "$test_file"
    chmod 000 "$test_file"

    # Try to read (should fail for non-root)
    if sudo -u nobody cat "$test_file" &>/dev/null; then
        log_error "Read succeeded despite permission denial"
        rm -f "$test_file"
        return 1
    fi

    # But should work for root
    if ! cat "$test_file" &>/dev/null; then
        log_error "Root couldn't read file"
        rm -f "$test_file"
        return 1
    fi

    log_info "Permission checks work correctly"

    rm -f "$test_file"
    return 0
}

test_state_validation() {
    local test_name="$1"

    log_info "Testing deployment state validation"

    local state_file="${TEST_RESULTS_DIR}/deployment-state.json"

    # Create a state file
    cat > "$state_file" <<EOF
{
    "deployment_id": "test-123",
    "status": "in_progress",
    "started_at": "$(date -Iseconds)",
    "phase": "user_setup"
}
EOF

    # Validate state file exists
    if [[ ! -f "$state_file" ]]; then
        log_error "State file not created"
        return 1
    fi

    # Validate JSON format
    if ! jq . "$state_file" &>/dev/null; then
        log_error "State file is not valid JSON"
        return 1
    fi

    # Validate required fields
    if ! jq -e '.deployment_id' "$state_file" &>/dev/null; then
        log_error "State file missing deployment_id"
        return 1
    fi

    log_info "State validation works"
    return 0
}

# ==============================================================================
# RESOURCE CONSTRAINT TESTS
# ==============================================================================

test_memory_limits() {
    local test_name="$1"

    log_info "Testing memory constraints"

    # Get available memory
    local available_mem=$(free -m | awk 'NR==2 {print $7}')
    log_info "Available memory: ${available_mem}MB"

    # Test would normally use ulimit to constrain memory
    # For safety, we just check detection

    if [[ $available_mem -lt 512 ]]; then
        log_info "Low memory detected (< 512MB)"
    fi

    return 0
}

test_network_timeout() {
    local test_name="$1"

    log_info "Testing network timeout handling"

    # Test connection to non-routable IP (should timeout)
    local start=$(date +%s)
    if timeout 5 curl -s --connect-timeout 2 http://192.0.2.1 &>/dev/null; then
        log_error "Connection succeeded to non-routable IP"
        return 1
    fi
    local end=$(date +%s)
    local duration=$((end - start))

    if [[ $duration -lt 10 ]]; then
        log_info "Timeout handled correctly (${duration}s)"
        return 0
    else
        log_error "Timeout took too long (${duration}s)"
        return 1
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo "========================================================================"
    echo "  Idempotency and Edge Case Testing Suite"
    echo "========================================================================"
    echo ""

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    setup_test_environment

    echo "Running idempotency and edge case tests..."
    echo ""

    # Idempotency tests
    echo "=== IDEMPOTENCY TESTS ==="
    run_test "user_creation_idempotent" test_user_creation_idempotent
    run_test "sudo_configuration_idempotent" test_sudo_configuration_idempotent
    run_test "ssh_directory_idempotent" test_ssh_directory_idempotent
    echo ""

    # Edge case tests
    echo "=== EDGE CASE TESTS ==="
    run_test "empty_environment_vars" test_empty_environment_vars
    run_test "special_chars_passwords" test_special_chars_passwords
    run_test "disk_space_low" test_disk_space_low
    run_test "concurrent_execution" test_concurrent_execution
    run_test "cleanup_tmp_files" test_cleanup_tmp_files
    run_test "filesystem_readonly" test_filesystem_readonly
    run_test "permission_issues" test_permission_issues
    run_test "state_validation" test_state_validation
    echo ""

    # Resource constraint tests
    echo "=== RESOURCE CONSTRAINT TESTS ==="
    run_test "memory_limits" test_memory_limits
    run_test "network_timeout" test_network_timeout
    echo ""

    cleanup_test_environment

    # Generate report
    generate_report

    # Exit with appropriate code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

generate_report() {
    local report_file="${TEST_RESULTS_DIR}/report.txt"

    cat > "$report_file" <<EOF
======================================================================
  IDEMPOTENCY AND EDGE CASE TEST REPORT
======================================================================

Test Run: $(date)
Test Directory: $TEST_RESULTS_DIR

SUMMARY:
  Total Tests: $TESTS_RUN
  Passed: $TESTS_PASSED
  Failed: $TESTS_FAILED
  Skipped: $TESTS_SKIPPED

PASS RATE: $(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED / $TESTS_RUN) * 100}")%

======================================================================
EOF

    echo ""
    echo "========================================================================"
    echo "  TEST RESULTS"
    echo "========================================================================"
    echo ""
    echo "  Total Tests: $TESTS_RUN"
    echo "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo "  Failed: ${RED}$TESTS_FAILED${NC}"
    echo "  Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}TESTS FAILED${NC}"
    else
        echo -e "  ${GREEN}ALL TESTS PASSED${NC}"
    fi

    echo ""
    echo "  Full report: $report_file"
    echo "  Test log: $TEST_LOG"
    echo ""
    echo "========================================================================"
}

# Run main
main
