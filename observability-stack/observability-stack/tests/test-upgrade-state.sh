#!/usr/bin/env bash
#
# Upgrade State Machine Test Suite
#
# Tests state transitions, idempotency, crash recovery,
# and concurrency safety.
#
# Author: Observability Stack Team
# License: MIT

set -euo pipefail

# Test configuration
readonly TEST_DIR="/tmp/upgrade-state-tests-$$"
readonly LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib" && pwd)"

# Override state directory for testing
export UPGRADE_STATE_DIR="${TEST_DIR}/state"
export UPGRADE_HISTORY_DIR="${UPGRADE_STATE_DIR}/history"
export UPGRADE_BACKUPS_DIR="${UPGRADE_STATE_DIR}/backups"
export UPGRADE_STATE_FILE="${UPGRADE_STATE_DIR}/state.json"
export UPGRADE_LOCK_FILE="${UPGRADE_STATE_DIR}/upgrade.lock"
export UPGRADE_TEMP_DIR="${UPGRADE_STATE_DIR}/tmp"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Print test result
# Arguments:
#   $1 - Test name
#   $2 - Result (0=pass, 1=fail)
#   $3 - (Optional) Error message
#######################################
print_test_result() {
    local test_name="$1"
    local result="$2"
    local error_msg="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ $result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} ${test_name}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} ${test_name}"
        if [[ -n "$error_msg" ]]; then
            echo -e "  ${RED}Error: ${error_msg}${NC}"
        fi
    fi
}

#######################################
# Setup test environment
#######################################
setup_test_env() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"

    # Source the upgrade state library
    # shellcheck source=../scripts/lib/upgrade-state.sh
    source "${LIB_DIR}/upgrade-state.sh"

    # Initialize directories
    upgrade_state_init_dirs
}

#######################################
# Cleanup test environment
#######################################
cleanup_test_env() {
    upgrade_lock_release 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

#######################################
# Test: State initialization
#######################################
test_state_init() {
    local test_name="State initialization"
    local upgrade_id
    local error_msg=""

    if upgrade_id=$(upgrade_state_init); then
        if [[ -f "$UPGRADE_STATE_FILE" ]]; then
            local state
            state=$(jq -r '.current_state' "$UPGRADE_STATE_FILE")
            if [[ "$state" == "IDLE" ]]; then
                print_test_result "$test_name" 0
                return 0
            else
                error_msg="Initial state is not IDLE: $state"
            fi
        else
            error_msg="State file not created"
        fi
    else
        error_msg="Failed to initialize state"
    fi

    print_test_result "$test_name" 1 "$error_msg"
    return 1
}

#######################################
# Test: State transitions
#######################################
test_state_transitions() {
    local test_name="Valid state transitions"
    local error_msg=""

    upgrade_state_init >/dev/null

    local states=(
        "IDLE"
        "PLANNING"
        "BACKING_UP"
        "UPGRADING"
        "VALIDATING"
        "COMPLETED"
    )

    for i in "${!states[@]}"; do
        if [[ $i -eq 0 ]]; then
            continue
        fi

        local prev_state="${states[$((i-1))]}"
        local next_state="${states[$i]}"

        if ! upgrade_state_set "$next_state" 2>/dev/null; then
            error_msg="Failed transition: $prev_state → $next_state"
            print_test_result "$test_name" 1 "$error_msg"
            return 1
        fi

        local current
        current=$(upgrade_state_get_current)
        if [[ "$current" != "$next_state" ]]; then
            error_msg="State mismatch: expected $next_state, got $current"
            print_test_result "$test_name" 1 "$error_msg"
            return 1
        fi
    done

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Invalid state transitions
#######################################
test_invalid_transitions() {
    local test_name="Invalid state transitions blocked"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "COMPLETED" >/dev/null 2>&1 || true

    # Try invalid transition: COMPLETED → UPGRADING
    if upgrade_state_set "UPGRADING" 2>/dev/null; then
        error_msg="Invalid transition allowed: COMPLETED → UPGRADING"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Phase management
#######################################
test_phase_management() {
    local test_name="Phase management"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true

    if ! upgrade_phase_start "exporters"; then
        error_msg="Failed to start phase"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local phase
    phase=$(jq -r '.current_phase' "$UPGRADE_STATE_FILE")
    if [[ "$phase" != "exporters" ]]; then
        error_msg="Phase not set correctly: $phase"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    if ! upgrade_phase_complete "exporters"; then
        error_msg="Failed to complete phase"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local phase_state
    phase_state=$(jq -r '.phases.exporters.state' "$UPGRADE_STATE_FILE")
    if [[ "$phase_state" != "COMPLETED" ]]; then
        error_msg="Phase state not COMPLETED: $phase_state"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Component tracking
#######################################
test_component_tracking() {
    local test_name="Component tracking"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true
    upgrade_phase_start "exporters" >/dev/null

    if ! upgrade_component_start "node_exporter" "1.7.0" "1.9.1"; then
        error_msg="Failed to start component upgrade"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local comp_state
    comp_state=$(jq -r '.phases.exporters.components.node_exporter.state' "$UPGRADE_STATE_FILE")
    if [[ "$comp_state" != "UPGRADING" ]]; then
        error_msg="Component state not UPGRADING: $comp_state"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    if ! upgrade_component_complete "node_exporter"; then
        error_msg="Failed to complete component"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    comp_state=$(jq -r '.phases.exporters.components.node_exporter.state' "$UPGRADE_STATE_FILE")
    if [[ "$comp_state" != "COMPLETED" ]]; then
        error_msg="Component state not COMPLETED: $comp_state"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Idempotency
#######################################
test_idempotency() {
    local test_name="Idempotent component checks"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true
    upgrade_phase_start "exporters" >/dev/null
    upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null
    upgrade_component_complete "node_exporter" >/dev/null

    # Check if component is already upgraded
    if ! upgrade_component_is_upgraded "node_exporter"; then
        error_msg="Component not detected as upgraded"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    # Check component that's not upgraded
    upgrade_component_start "nginx_exporter" "1.1.0" "1.5.1" >/dev/null

    if upgrade_component_is_upgraded "nginx_exporter"; then
        error_msg="In-progress component detected as upgraded"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Crash recovery
#######################################
test_crash_recovery() {
    local test_name="Crash recovery and resume"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "PLANNING" >/dev/null 2>&1 || true
    upgrade_state_set "BACKING_UP" >/dev/null 2>&1 || true
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true
    upgrade_phase_start "exporters" >/dev/null
    upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null

    # Simulate crash - load state and check resume
    if ! upgrade_can_resume; then
        error_msg="Cannot resume after simulated crash"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local resume_info
    resume_info=$(upgrade_get_resume_point)
    local resume_state
    resume_state=$(echo "$resume_info" | jq -r '.state')

    if [[ "$resume_state" != "UPGRADING" ]]; then
        error_msg="Incorrect resume state: $resume_state"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    if ! upgrade_resume; then
        error_msg="Failed to resume upgrade"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Lock acquisition
#######################################
test_lock_acquisition() {
    local test_name="Lock acquisition and release"
    local error_msg=""

    if ! upgrade_lock_acquire; then
        error_msg="Failed to acquire lock"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    if ! upgrade_lock_is_held; then
        error_msg="Lock not detected as held"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    if ! upgrade_lock_release; then
        error_msg="Failed to release lock"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    if upgrade_lock_is_held; then
        error_msg="Lock still held after release"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Concurrent lock prevention
#######################################
test_concurrent_lock() {
    local test_name="Concurrent lock prevention"
    local error_msg=""

    # Acquire lock in main process
    if ! upgrade_lock_acquire; then
        error_msg="Failed to acquire initial lock"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    # Try to acquire in subshell (simulates concurrent process)
    if (
        source "${LIB_DIR}/upgrade-state.sh"
        upgrade_lock_acquire 2>/dev/null
    ); then
        upgrade_lock_release
        error_msg="Concurrent lock acquisition succeeded (should fail)"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    upgrade_lock_release

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Stale lock removal
#######################################
test_stale_lock() {
    local test_name="Stale lock detection and removal"
    local error_msg=""

    # Create a lock with non-existent PID
    echo "99999|2025-01-01T00:00:00Z|test|test" > "$UPGRADE_LOCK_FILE"

    # Check stale locks (should remove it)
    upgrade_lock_check_stale

    if [[ -f "$UPGRADE_LOCK_FILE" ]]; then
        error_msg="Stale lock not removed"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Rollback tracking
#######################################
test_rollback_tracking() {
    local test_name="Rollback point tracking"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true
    upgrade_phase_start "exporters" >/dev/null
    upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null

    local backup_path="/tmp/test-backup.tar.gz"
    if ! upgrade_mark_rollback_point "node_exporter" "$backup_path"; then
        error_msg="Failed to mark rollback point"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local rollback_info
    rollback_info=$(upgrade_get_rollback_info)
    local is_available
    is_available=$(echo "$rollback_info" | jq -r '.rollback_available')

    if [[ "$is_available" != "true" ]]; then
        error_msg="Rollback not marked as available"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local component_backup
    component_backup=$(echo "$rollback_info" | jq -r '.components[0].backup_path')

    if [[ "$component_backup" != "$backup_path" ]]; then
        error_msg="Backup path not recorded correctly: $component_backup"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Progress calculation
#######################################
test_progress_calculation() {
    local test_name="Progress percentage calculation"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true
    upgrade_phase_start "exporters" >/dev/null

    # Add 4 components
    upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null
    upgrade_component_start "nginx_exporter" "1.1.0" "1.5.1" >/dev/null
    upgrade_component_start "mysqld_exporter" "0.14.0" "0.16.1" >/dev/null
    upgrade_component_start "phpfpm_exporter" "2.2.0" "2.3.1" >/dev/null

    # Complete 2 of 4 (50%)
    upgrade_component_complete "node_exporter" >/dev/null
    upgrade_component_complete "nginx_exporter" >/dev/null

    local progress
    progress=$(upgrade_get_progress_percent)

    if [[ "$progress" != "50" ]]; then
        error_msg="Incorrect progress: expected 50, got $progress"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: History tracking
#######################################
test_history_tracking() {
    local test_name="History tracking"
    local error_msg=""

    local upgrade_id
    upgrade_id=$(upgrade_state_init)
    upgrade_state_set "COMPLETED" >/dev/null 2>&1 || true

    if ! upgrade_save_to_history; then
        error_msg="Failed to save to history"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local history_file="${UPGRADE_HISTORY_DIR}/${upgrade_id}.json"
    if [[ ! -f "$history_file" ]]; then
        error_msg="History file not created"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local saved_id
    saved_id=$(jq -r '.upgrade_id' "$history_file")
    if [[ "$saved_id" != "$upgrade_id" ]]; then
        error_msg="History upgrade_id mismatch"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Component failure tracking
#######################################
test_component_failure() {
    local test_name="Component failure tracking"
    local error_msg=""

    upgrade_state_init >/dev/null
    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true
    upgrade_phase_start "exporters" >/dev/null
    upgrade_component_start "node_exporter" "1.7.0" "1.9.1" >/dev/null

    local error_message="Download failed"
    if ! upgrade_component_fail "node_exporter" "$error_message"; then
        error_msg="Failed to mark component as failed"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local comp_state
    comp_state=$(jq -r '.phases.exporters.components.node_exporter.state' "$UPGRADE_STATE_FILE")
    if [[ "$comp_state" != "FAILED" ]]; then
        error_msg="Component state not FAILED: $comp_state"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local last_error
    last_error=$(jq -r '.phases.exporters.components.node_exporter.last_error' "$UPGRADE_STATE_FILE")
    if [[ "$last_error" != "$error_message" ]]; then
        error_msg="Error message not recorded: $last_error"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    local attempts
    attempts=$(jq -r '.phases.exporters.components.node_exporter.attempts' "$UPGRADE_STATE_FILE")
    if [[ "$attempts" != "2" ]]; then
        error_msg="Attempts not incremented: $attempts"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Atomic state writes
#######################################
test_atomic_writes() {
    local test_name="Atomic state file writes"
    local error_msg=""

    upgrade_state_init >/dev/null

    # Save valid JSON
    local valid_json='{"test": "data", "number": 123}'
    if ! upgrade_state_write_atomic "$valid_json"; then
        error_msg="Failed to write valid JSON"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    # Try to save invalid JSON (should fail)
    local invalid_json='{"test": invalid}'
    if upgrade_state_write_atomic "$invalid_json" 2>/dev/null; then
        error_msg="Invalid JSON write succeeded (should fail)"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    # State file should still be valid
    if ! jq '.' "$UPGRADE_STATE_FILE" >/dev/null 2>&1; then
        error_msg="State file corrupted after failed write"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Test: Upgrade in progress detection
#######################################
test_in_progress_detection() {
    local test_name="Upgrade in-progress detection"
    local error_msg=""

    upgrade_state_init >/dev/null

    # Should not be in progress initially
    if upgrade_is_in_progress; then
        error_msg="Idle state detected as in-progress"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    upgrade_state_set "UPGRADING" >/dev/null 2>&1 || true

    # Should be in progress now
    if ! upgrade_is_in_progress; then
        error_msg="Upgrading state not detected as in-progress"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    upgrade_state_set "VALIDATING" >/dev/null 2>&1 || true

    # Should still be in progress
    if ! upgrade_is_in_progress; then
        error_msg="Validating state not detected as in-progress"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    upgrade_state_set "COMPLETED" >/dev/null 2>&1 || true

    # Should not be in progress anymore
    if upgrade_is_in_progress; then
        error_msg="Completed state detected as in-progress"
        print_test_result "$test_name" 1 "$error_msg"
        return 1
    fi

    print_test_result "$test_name" 0
    return 0
}

#######################################
# Run all tests
#######################################
run_all_tests() {
    echo -e "${BLUE}=== Upgrade State Machine Test Suite ===${NC}\n"

    # Basic functionality tests
    echo -e "${YELLOW}Basic Functionality:${NC}"
    setup_test_env
    test_state_init
    cleanup_test_env

    setup_test_env
    test_state_transitions
    cleanup_test_env

    setup_test_env
    test_invalid_transitions
    cleanup_test_env

    setup_test_env
    test_phase_management
    cleanup_test_env

    setup_test_env
    test_component_tracking
    cleanup_test_env

    setup_test_env
    test_component_failure
    cleanup_test_env

    echo ""

    # Idempotency and recovery tests
    echo -e "${YELLOW}Idempotency & Recovery:${NC}"
    setup_test_env
    test_idempotency
    cleanup_test_env

    setup_test_env
    test_crash_recovery
    cleanup_test_env

    setup_test_env
    test_rollback_tracking
    cleanup_test_env

    echo ""

    # Concurrency tests
    echo -e "${YELLOW}Concurrency Safety:${NC}"
    setup_test_env
    test_lock_acquisition
    cleanup_test_env

    setup_test_env
    test_concurrent_lock
    cleanup_test_env

    setup_test_env
    test_stale_lock
    cleanup_test_env

    echo ""

    # Utility tests
    echo -e "${YELLOW}Utilities:${NC}"
    setup_test_env
    test_progress_calculation
    cleanup_test_env

    setup_test_env
    test_history_tracking
    cleanup_test_env

    setup_test_env
    test_atomic_writes
    cleanup_test_env

    setup_test_env
    test_in_progress_detection
    cleanup_test_env

    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo -e "Total tests run: ${TESTS_RUN}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Run tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
    exit $?
fi
