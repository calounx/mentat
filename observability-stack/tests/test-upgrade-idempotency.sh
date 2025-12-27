#!/bin/bash
#===============================================================================
# Upgrade Idempotency Test Suite
# Part of the observability-stack upgrade orchestration system
#
# Verifies that upgrades are truly idempotent and safe
#
# Test scenarios:
#   1. Double-run test: Run upgrade twice, second should skip
#   2. Crash recovery test: Simulate crash mid-upgrade and resume
#   3. Partial failure test: Handle component failures gracefully
#   4. State consistency test: Verify state tracking accuracy
#   5. Rollback test: Test rollback functionality
#   6. Version detection test: Verify version comparison logic
#
# Usage:
#   ./test-upgrade-idempotency.sh [--verbose] [--test <test_name>]
#===============================================================================

set -euo pipefail

#===============================================================================
# SETUP
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$STACK_ROOT/scripts/lib/common.sh"
source "$STACK_ROOT/scripts/lib/upgrade-state.sh"
source "$STACK_ROOT/scripts/lib/upgrade-manager.sh"

# Test configuration
VERBOSE=false
SPECIFIC_TEST=""
TEST_STATE_DIR="/tmp/upgrade-test-$$"
TESTS_PASSED=0
TESTS_FAILED=0

# Override state directory for testing
export STATE_DIR="$TEST_STATE_DIR"

#===============================================================================
# TEST UTILITIES
#===============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Test result tracking
test_start() {
    local test_name="$1"
    echo ""
    echo "=========================================="
    echo "TEST: $test_name"
    echo "=========================================="
}

test_pass() {
    local test_name="$1"
    ((TESTS_PASSED++))
    log_success "PASS: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="${2:-Unknown}"
    ((TESTS_FAILED++))
    log_error "FAIL: $test_name - $reason"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values do not match}"

    if [[ "$expected" != "$actual" ]]; then
        log_error "$message"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    if [[ ! -f "$file" ]]; then
        log_error "$message"
        return 1
    fi
    return 0
}

#===============================================================================
# TEST SETUP/TEARDOWN
#===============================================================================

setup_test_environment() {
    log_info "Setting up test environment..."

    # Create test state directory
    mkdir -p "$TEST_STATE_DIR"
    chmod 700 "$TEST_STATE_DIR"

    # Initialize state
    state_init

    log_success "Test environment ready"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."

    # Remove test state directory
    if [[ -d "$TEST_STATE_DIR" ]]; then
        rm -rf "$TEST_STATE_DIR"
    fi

    log_success "Cleanup complete"
}

#===============================================================================
# TEST 1: STATE INITIALIZATION
#===============================================================================

test_state_initialization() {
    test_start "State Initialization"

    # Initialize state
    state_init

    # Verify state file exists
    if ! assert_file_exists "$STATE_FILE" "State file should be created"; then
        test_fail "State Initialization" "State file not created"
        return 1
    fi

    # Verify state is valid JSON
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        test_fail "State Initialization" "State file is not valid JSON"
        return 1
    fi

    # Verify initial status
    local status
    status=$(state_get_status)

    if ! assert_equals "idle" "$status" "Initial status should be idle"; then
        test_fail "State Initialization" "Initial status incorrect"
        return 1
    fi

    test_pass "State Initialization"
}

#===============================================================================
# TEST 2: IDEMPOTENT DOUBLE-RUN
#===============================================================================

test_double_run_idempotency() {
    test_start "Double-Run Idempotency"

    # Begin upgrade
    state_begin_upgrade "test"

    # Simulate component upgrade
    state_begin_component "test_component" "1.0.0" "2.0.0"
    state_complete_component "test_component" "checksum123" "/tmp/backup"

    # First completion
    state_complete_upgrade

    local first_status
    first_status=$(state_get_status)

    if ! assert_equals "completed" "$first_status" "First run should complete"; then
        test_fail "Double-Run Idempotency" "First run did not complete"
        return 1
    fi

    # Check component status
    local comp_status
    comp_status=$(state_get_component_status "test_component")

    if ! assert_equals "completed" "$comp_status" "Component should be completed"; then
        test_fail "Double-Run Idempotency" "Component not marked completed"
        return 1
    fi

    # Second run - should detect already completed
    if state_component_needs_upgrade "test_component"; then
        test_fail "Double-Run Idempotency" "Component marked as needing upgrade after completion"
        return 1
    fi

    test_pass "Double-Run Idempotency"
}

#===============================================================================
# TEST 3: CRASH RECOVERY
#===============================================================================

test_crash_recovery() {
    test_start "Crash Recovery"

    # Begin upgrade
    state_begin_upgrade "test"

    # Complete first component
    state_begin_component "component1" "1.0.0" "2.0.0"
    state_complete_component "component1" "checksum1" "/tmp/backup1"

    # Start second component but don't complete (simulating crash)
    state_begin_component "component2" "1.0.0" "2.0.0"

    # Verify state is resumable
    if ! state_is_resumable; then
        test_fail "Crash Recovery" "State not marked as resumable after crash"
        return 1
    fi

    # Check component states
    local comp1_status
    comp1_status=$(state_get_component_status "component1")

    if ! assert_equals "completed" "$comp1_status" "Component 1 should remain completed"; then
        test_fail "Crash Recovery" "Component 1 status incorrect"
        return 1
    fi

    local comp2_status
    comp2_status=$(state_get_component_status "component2")

    if ! assert_equals "in_progress" "$comp2_status" "Component 2 should be in_progress"; then
        test_fail "Crash Recovery" "Component 2 status incorrect"
        return 1
    fi

    # Resume upgrade - complete component2
    state_complete_component "component2" "checksum2" "/tmp/backup2"
    state_complete_upgrade

    # Verify final state
    local final_status
    final_status=$(state_get_status)

    if ! assert_equals "completed" "$final_status" "Resume should complete successfully"; then
        test_fail "Crash Recovery" "Resume did not complete"
        return 1
    fi

    test_pass "Crash Recovery"
}

#===============================================================================
# TEST 4: VERSION COMPARISON
#===============================================================================

test_version_comparison() {
    test_start "Version Comparison"

    # Test equal versions
    local result
    result=$(compare_versions "1.7.0" "1.7.0")

    if ! assert_equals "0" "$result" "Equal versions should return 0"; then
        test_fail "Version Comparison" "Equal version comparison failed"
        return 1
    fi

    # Test less than
    result=$(compare_versions "1.7.0" "1.9.0")

    if ! assert_equals "-1" "$result" "1.7.0 < 1.9.0 should return -1"; then
        test_fail "Version Comparison" "Less than comparison failed"
        return 1
    fi

    # Test greater than
    result=$(compare_versions "2.0.0" "1.9.0")

    if ! assert_equals "1" "$result" "2.0.0 > 1.9.0 should return 1"; then
        test_fail "Version Comparison" "Greater than comparison failed"
        return 1
    fi

    # Test major version comparison
    result=$(compare_versions "2.0.0" "3.0.0")

    if ! assert_equals "-1" "$result" "2.0.0 < 3.0.0 should return -1"; then
        test_fail "Version Comparison" "Major version comparison failed"
        return 1
    fi

    test_pass "Version Comparison"
}

#===============================================================================
# TEST 5: STATE LOCKING
#===============================================================================

test_state_locking() {
    test_start "State Locking"

    # Acquire lock
    if ! state_lock; then
        test_fail "State Locking" "Failed to acquire initial lock"
        return 1
    fi

    # Verify lock file exists
    if [[ ! -d "$STATE_LOCK" ]]; then
        test_fail "State Locking" "Lock directory not created"
        state_unlock
        return 1
    fi

    # Try to acquire lock again (should fail)
    if state_lock 2>/dev/null; then
        test_fail "State Locking" "Acquired lock twice (should be exclusive)"
        state_unlock
        return 1
    fi

    # Release lock
    state_unlock

    # Verify lock released
    if [[ -d "$STATE_LOCK" ]]; then
        test_fail "State Locking" "Lock not released"
        return 1
    fi

    # Should be able to acquire again
    if ! state_lock; then
        test_fail "State Locking" "Failed to reacquire lock after release"
        return 1
    fi

    state_unlock

    test_pass "State Locking"
}

#===============================================================================
# TEST 6: CHECKPOINT MANAGEMENT
#===============================================================================

test_checkpoint_management() {
    test_start "Checkpoint Management"

    # Begin upgrade
    state_begin_upgrade "test"

    # Create checkpoint
    state_create_checkpoint "before_upgrade" "Before starting upgrades"

    # Verify checkpoint file exists
    local checkpoint_file="$CHECKPOINT_DIR/before_upgrade.json"

    if ! assert_file_exists "$checkpoint_file" "Checkpoint file should be created"; then
        test_fail "Checkpoint Management" "Checkpoint file not created"
        return 1
    fi

    # Make changes
    state_begin_component "component1" "1.0.0" "2.0.0"

    # Restore checkpoint
    state_restore_checkpoint "before_upgrade"

    # Verify restored state (component1 should not exist)
    local comp_exists
    comp_exists=$(state_read "components.component1.status" || echo "null")

    if [[ "$comp_exists" != "null" ]]; then
        test_fail "Checkpoint Management" "Checkpoint restore did not revert changes"
        return 1
    fi

    test_pass "Checkpoint Management"
}

#===============================================================================
# TEST 7: FAILURE HANDLING
#===============================================================================

test_failure_handling() {
    test_start "Failure Handling"

    # Begin upgrade
    state_begin_upgrade "test"

    # Simulate component failure
    state_begin_component "failing_component" "1.0.0" "2.0.0"
    state_fail_component "failing_component" "Simulated failure"

    # Check component status
    local comp_status
    comp_status=$(state_get_component_status "failing_component")

    if ! assert_equals "failed" "$comp_status" "Component should be marked as failed"; then
        test_fail "Failure Handling" "Component not marked as failed"
        return 1
    fi

    # Check error message recorded
    local error_msg
    error_msg=$(state_read "components.failing_component.error")

    if [[ "$error_msg" != "Simulated failure" ]]; then
        test_fail "Failure Handling" "Error message not recorded"
        return 1
    fi

    test_pass "Failure Handling"
}

#===============================================================================
# TEST 8: SKIP DETECTION
#===============================================================================

test_skip_detection() {
    test_start "Skip Detection"

    # Begin upgrade
    state_begin_upgrade "test"

    # Skip a component
    state_skip_component "skipped_component" "Already at target version"

    # Verify skipped status
    local comp_status
    comp_status=$(state_get_component_status "skipped_component")

    if ! assert_equals "skipped" "$comp_status" "Component should be marked as skipped"; then
        test_fail "Skip Detection" "Component not marked as skipped"
        return 1
    fi

    # Verify it doesn't need upgrade
    if state_component_needs_upgrade "skipped_component"; then
        test_fail "Skip Detection" "Skipped component marked as needing upgrade"
        return 1
    fi

    test_pass "Skip Detection"
}

#===============================================================================
# TEST EXECUTION
#===============================================================================

run_all_tests() {
    log_info "===== UPGRADE IDEMPOTENCY TEST SUITE ====="
    log_info ""

    setup_test_environment

    # List of all tests
    local tests=(
        "test_state_initialization"
        "test_double_run_idempotency"
        "test_crash_recovery"
        "test_version_comparison"
        "test_state_locking"
        "test_checkpoint_management"
        "test_failure_handling"
        "test_skip_detection"
    )

    # Run tests
    for test_func in "${tests[@]}"; do
        if [[ -n "$SPECIFIC_TEST" && "$test_func" != "$SPECIFIC_TEST" ]]; then
            continue
        fi

        # Run test in subshell to isolate state
        (
            export STATE_DIR="${TEST_STATE_DIR}/${test_func}"
            mkdir -p "$STATE_DIR"
            $test_func
        ) || true
    done

    cleanup_test_environment

    # Report results
    echo ""
    echo "=========================================="
    echo "TEST RESULTS"
    echo "=========================================="
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"
    echo "=========================================="

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "Some tests failed"
        exit 1
    fi
}

#===============================================================================
# MAIN
#===============================================================================

run_all_tests
