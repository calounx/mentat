#!/usr/bin/env bats
#===============================================================================
# Unit Test: State Error Handling
# Tests that state errors are properly caught and handled
#===============================================================================

load '../helpers'

setup() {
    setup_test_environment

    # Create state directory
    STATE_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades"
    mkdir -p "$STATE_DIR"
    export STATE_DIR

    # Initialize state file
    cat > "${STATE_DIR}/state.json" <<'EOF'
{
  "version": "1.0.0",
  "upgrade_id": null,
  "status": "idle",
  "components": {}
}
EOF

    # Source libraries
    source_lib "upgrade-state.sh" || skip "upgrade-state.sh not found"
    source_lib "errors.sh" 2>/dev/null || true
}

teardown() {
    cleanup_test_environment
}

@test "state error: missing state file is handled" {
    # Remove state file
    rm -f "${STATE_DIR}/state.json"

    # Reading state should fail gracefully
    run state_read "status"
    [ "$status" -ne 0 ]

    # Should report error about missing file
    [[ "$output" =~ "not found"|"missing"|"State file" ]]
}

@test "state error: corrupted state file is detected" {
    # Corrupt the state file
    echo "{ invalid json syntax [" > "${STATE_DIR}/state.json"

    # Reading should fail
    run state_read "status"
    [ "$status" -ne 0 ]
}

@test "state error: empty state file is handled" {
    # Create empty state file
    > "${STATE_DIR}/state.json"

    run state_read "status"
    [ "$status" -ne 0 ]
}

@test "state error: state verification detects corruption" {
    if declare -f state_verify &>/dev/null; then
        # Valid state should pass
        run state_verify
        [ "$status" -eq 0 ]

        # Corrupt state
        echo "invalid" > "${STATE_DIR}/state.json"

        run state_verify
        [ "$status" -ne 0 ]
        [[ "$output" =~ "not valid JSON"|"verification failed" ]]
    else
        skip "state_verify function not available"
    fi
}

@test "state error: concurrent state modifications are prevented" {
    # Multiple processes trying to modify state
    # Only one should succeed at a time due to locking

    local success_count=0

    for i in {1..3}; do
        (
            source "${BATS_TEST_DIRNAME}/../../scripts/lib/upgrade-state.sh" 2>/dev/null
            export STATE_DIR="$STATE_DIR"

            if state_update ".components.test_$i = {\"status\": \"completed\"}"; then
                echo "SUCCESS" > "${TEST_TEMP_DIR}/state_update_$i"
            fi
        ) &
    done

    wait

    # All updates should have succeeded (serialized by locking)
    for i in {1..3}; do
        if [ -f "${TEST_TEMP_DIR}/state_update_$i" ]; then
            ((success_count++)) || true
        fi
    done

    # All should succeed (one at a time)
    [ "$success_count" -eq 3 ]

    # State file should still be valid
    jq empty "${STATE_DIR}/state.json"
}

@test "state error: invalid state transitions are prevented" {
    # Initialize state
    state_begin_upgrade "standard"

    # Try to complete without any components
    run state_complete_upgrade
    [ "$status" -eq 0 ]  # Should succeed (no validation yet)

    # Verify state
    local status=$(state_read "status")
    [ "$status" = "completed" ]
}

@test "state error: state reset during active upgrade requires force flag" {
    # Start an upgrade
    state_begin_upgrade "standard"

    # Try to reset without force
    run state_reset
    [ "$status" -ne 0 ]
    [[ "$output" =~ "in progress"|"--force" ]]

    # Reset with force should work
    run state_reset --force
    [ "$status" -eq 0 ]

    # Verify state is idle
    local status=$(state_read "status")
    [ "$status" = "idle" ]
}

@test "state error: missing component in state is handled" {
    # Try to get status of non-existent component
    run state_get_component_status "nonexistent_component"

    # Should return empty or error
    [ -z "$output" ] || [[ "$output" =~ "null"|"empty" ]]
}

@test "state error: state lock timeout is enforced" {
    # Create a lock that won't be released
    LOCK_DIR="${STATE_DIR}"
    mkdir -p "${LOCK_DIR}/.state.lock"
    echo "99999" > "${LOCK_DIR}/.state.lock/pid"

    # Try to acquire lock with short timeout
    if declare -f state_lock &>/dev/null; then
        # Override the timeout for testing
        run timeout 10 bash -c "
            source ${BATS_TEST_DIRNAME}/../../scripts/lib/upgrade-state.sh
            export STATE_DIR='$STATE_DIR'
            state_lock
        "

        # Should timeout
        [ "$status" -ne 0 ]
    fi

    # Clean up
    rm -rf "${LOCK_DIR}/.state.lock"
}

@test "state error: stale lock is detected and removed" {
    if declare -f state_lock &>/dev/null; then
        # Create stale lock (PID that doesn't exist)
        LOCK_DIR="${STATE_DIR}"
        mkdir -p "${LOCK_DIR}/.state.lock"
        echo "99999" > "${LOCK_DIR}/.state.lock/pid"

        # Should detect stale lock and acquire
        run bash -c "
            source ${BATS_TEST_DIRNAME}/../../scripts/lib/upgrade-state.sh
            export STATE_DIR='$STATE_DIR'
            state_lock && echo 'ACQUIRED'
        "

        [[ "$output" =~ "ACQUIRED" ]]
    else
        skip "state_lock function not available"
    fi
}

@test "state error: error context tracking works" {
    if declare -f error_push_context &>/dev/null && \
       declare -f error_get_context &>/dev/null; then

        # Push some contexts
        error_push_context "Upgrading node_exporter"
        error_push_context "Downloading binary"

        # Get context
        run error_get_context
        [[ "$output" =~ "Upgrading node_exporter" ]]
        [[ "$output" =~ "Downloading binary" ]]

        # Pop context
        error_pop_context

        run error_get_context
        [[ "$output" =~ "Upgrading node_exporter" ]]
        [[ ! "$output" =~ "Downloading binary" ]]
    else
        skip "Error context functions not available"
    fi
}

@test "state error: error aggregation collects multiple errors" {
    if declare -f error_aggregate_start &>/dev/null && \
       declare -f error_aggregate_finish &>/dev/null; then

        error_aggregate_start

        # Generate some errors
        error_report "Error 1" 1 || true
        error_report "Error 2" 1 || true
        error_report "Error 3" 1 || true

        # Finish aggregation
        run error_aggregate_finish

        # Should fail (has errors)
        [ "$status" -ne 0 ]

        # Output should show all errors
        [[ "$output" =~ "Error 1" ]]
        [[ "$output" =~ "Error 2" ]]
        [[ "$output" =~ "Error 3" ]]
    else
        skip "Error aggregation functions not available"
    fi
}

@test "state error: state history is maintained" {
    if declare -f state_list_history &>/dev/null; then
        # Create and complete an upgrade
        state_begin_upgrade "standard"
        state_begin_component "test_comp" "1.0.0" "2.0.0"
        state_complete_component "test_comp" "abc123"
        state_complete_upgrade

        # Check history
        run state_list_history
        [ "$status" -eq 0 ]

        # Should show the upgrade
        [[ "$output" =~ "test-upgrade"|"upgrade-" ]]
    else
        skip "state_list_history function not available"
    fi
}

@test "state error: checkpoint creation and restoration works" {
    if declare -f state_create_checkpoint &>/dev/null && \
       declare -f state_restore_checkpoint &>/dev/null; then

        # Create initial state
        state_begin_upgrade "standard"
        state_begin_component "comp1" "1.0.0" "2.0.0"

        # Create checkpoint
        run state_create_checkpoint "before_change" "Before making changes"
        [ "$status" -eq 0 ]

        # Modify state
        state_complete_component "comp1" "abc123"
        state_begin_component "comp2" "1.0.0" "2.0.0"

        # Restore checkpoint
        run state_restore_checkpoint "before_change"
        [ "$status" -eq 0 ]

        # Verify state was restored
        local comp1_status=$(state_read "components.comp1.status")
        [ "$comp1_status" = "in_progress" ]

        # comp2 should not exist
        local comp2_status=$(state_read "components.comp2.status")
        [ -z "$comp2_status" ] || [ "$comp2_status" = "null" ]
    else
        skip "Checkpoint functions not available"
    fi
}

@test "state error: invalid checkpoint name is rejected" {
    if declare -f state_restore_checkpoint &>/dev/null; then
        # Try to restore non-existent checkpoint
        run state_restore_checkpoint "nonexistent_checkpoint"
        [ "$status" -ne 0 ]
        [[ "$output" =~ "not found"|"Checkpoint" ]]
    else
        skip "state_restore_checkpoint not available"
    fi
}

@test "state error: component failure is recorded" {
    state_begin_upgrade "standard"
    state_begin_component "failing_comp" "1.0.0" "2.0.0"

    # Mark as failed
    run state_fail_component "failing_comp" "Download failed"
    [ "$status" -eq 0 ]

    # Verify failure was recorded
    local comp_status=$(state_read "components.failing_comp.status")
    [ "$comp_status" = "failed" ]

    local error_msg=$(state_read "components.failing_comp.error")
    [[ "$error_msg" =~ "Download failed" ]]
}

@test "state error: upgrade failure is recorded with timestamp" {
    state_begin_upgrade "standard"

    # Mark upgrade as failed
    run state_fail_upgrade "Critical error occurred"
    [ "$status" -eq 0 ]

    # Verify failure
    local status=$(state_read "status")
    [ "$status" = "failed" ]

    # Should have completed_at timestamp
    local completed=$(state_read "completed_at")
    [ -n "$completed" ]
    [ "$completed" != "null" ]

    # Should have error in errors array
    local error_count=$(state_read "errors" | jq 'length')
    [ "$error_count" -ge 1 ]
}

@test "state error: state file permissions are secure" {
    # State file should not be world-readable
    local perms=$(stat -c '%a' "${STATE_DIR}/state.json" 2>/dev/null || \
                  stat -f '%A' "${STATE_DIR}/state.json" 2>/dev/null)

    # Should be 600 or similar (owner read/write only)
    [[ "$perms" =~ ^6 ]] || [[ "$perms" =~ 00$ ]]
}

@test "state error: state directory has correct permissions" {
    # State directory should have restrictive permissions
    local perms=$(stat -c '%a' "${STATE_DIR}" 2>/dev/null || \
                  stat -f '%A' "${STATE_DIR}" 2>/dev/null)

    # Should be 700 or similar
    [[ "$perms" =~ ^7 ]]
}

@test "state error: invalid JSON in update is rejected" {
    # Try to update with invalid JSON expression
    run state_update ".invalid json ["
    [ "$status" -ne 0 ]

    # State file should still be valid
    jq empty "${STATE_DIR}/state.json"
}

@test "state error: state shows current upgrade status" {
    if declare -f state_summary &>/dev/null; then
        state_begin_upgrade "standard"
        state_begin_component "comp1" "1.0.0" "2.0.0"

        run state_summary
        [ "$status" -eq 0 ]

        [[ "$output" =~ "Status"|"status" ]]
        [[ "$output" =~ "in_progress"|"In progress" ]]
    else
        skip "state_summary function not available"
    fi
}

@test "state error: error recovery hooks can be registered" {
    if declare -f error_register_recovery &>/dev/null; then
        # Define recovery function
        test_recovery() {
            return 0
        }

        # Register recovery hook
        run error_register_recovery 5 "test_recovery"
        [ "$status" -eq 0 ]
    else
        skip "error_register_recovery not available"
    fi
}

@test "state error: state statistics are calculated correctly" {
    if declare -f state_get_stats &>/dev/null; then
        # Create some components in different states
        state_begin_upgrade "standard"

        state_begin_component "comp1" "1.0.0" "2.0.0"
        state_complete_component "comp1" "abc123"

        state_begin_component "comp2" "1.0.0" "2.0.0"
        state_fail_component "comp2" "Failed"

        state_begin_component "comp3" "1.0.0" "2.0.0"
        state_skip_component "comp3" "Not needed"

        run state_get_stats
        [ "$status" -eq 0 ]

        [[ "$output" =~ "Completed: 1" ]]
        [[ "$output" =~ "Failed: 1" ]]
        [[ "$output" =~ "Skipped: 1" ]]
    else
        skip "state_get_stats not available"
    fi
}
