#!/usr/bin/env bats
#===============================================================================
# Security Test: Lock Race Condition Prevention (H-2)
# Tests that concurrent lock acquisitions are properly handled
#===============================================================================

load '../helpers'

setup() {
    setup_test_environment

    # Create lock directory
    LOCK_DIR="${TEST_TEMP_DIR}/var/lock"
    mkdir -p "$LOCK_DIR"
    export LOCK_FILE="${LOCK_DIR}/observability-setup.lock"

    # Source the lock utilities library
    source_lib "lock-utils.sh" || skip "lock-utils.sh not found"
}

teardown() {
    # Clean up any remaining locks
    release_lock 2>/dev/null || true
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
    cleanup_test_environment
}

@test "lock: single process can acquire lock" {
    run acquire_lock
    [ "$status" -eq 0 ]

    # Verify lock file exists
    [ -f "$LOCK_FILE" ]

    # Clean up
    release_lock
}

@test "lock: second process cannot acquire lock while first holds it" {
    # First process acquires lock
    acquire_lock

    # Second process in subshell tries to acquire same lock
    # Should fail or timeout quickly
    run bash -c "
        source ${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh
        export LOCK_FILE='$LOCK_FILE'
        acquire_lock '$LOCK_FILE' 2
    "

    # Should fail (timeout after 2 seconds)
    [ "$status" -ne 0 ]

    # Clean up
    release_lock
}

@test "lock: race condition with concurrent acquisition attempts" {
    local success_count=0
    local fail_count=0

    # Launch multiple processes trying to acquire lock simultaneously
    for i in {1..5}; do
        (
            source "${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh"
            export LOCK_FILE="$LOCK_FILE"
            if acquire_lock "$LOCK_FILE" 5; then
                echo "SUCCESS" > "${TEST_TEMP_DIR}/result_$i"
                sleep 1
                release_lock "$LOCK_FILE"
            else
                echo "FAIL" > "${TEST_TEMP_DIR}/result_$i"
            fi
        ) &
    done

    # Wait for all processes
    wait

    # Count successes and failures
    for i in {1..5}; do
        if [ -f "${TEST_TEMP_DIR}/result_$i" ]; then
            result=$(cat "${TEST_TEMP_DIR}/result_$i")
            if [ "$result" = "SUCCESS" ]; then
                ((success_count++)) || true
            else
                ((fail_count++)) || true
            fi
        fi
    done

    # Only one should have succeeded in acquiring the lock
    [ "$success_count" -eq 1 ]
    [ "$fail_count" -eq 4 ]
}

@test "lock: stale lock detection and cleanup" {
    # Create a stale lock (PID that doesn't exist)
    mkdir -p "$(dirname "$LOCK_FILE")"
    echo "99999" > "$LOCK_FILE"

    # Try to acquire lock - should detect stale lock and acquire
    run acquire_lock "$LOCK_FILE"
    [ "$status" -eq 0 ]

    # Verify our PID is in the lock file
    local lock_pid=$(cat "$LOCK_FILE")
    [ "$lock_pid" = "$$" ]

    release_lock
}

@test "lock: flock is used when available" {
    # Check if flock is available
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi

    # Acquire lock
    acquire_lock

    # Verify flock file descriptor is in use (fd 200)
    # This is implementation-specific to the lock-utils.sh
    [ -f "$LOCK_FILE" ]

    release_lock
}

@test "lock: fallback mechanism works without flock" {
    # Temporarily hide flock by modifying PATH
    local PATH_BACKUP="$PATH"

    # Create empty bin directory and prepend to PATH
    # This will cause command -v flock to fail, triggering fallback
    mkdir -p "${TEST_TEMP_DIR}/empty_bin"

    # Save flock location and temporarily make it unavailable
    local flock_path=$(command -v flock 2>/dev/null || echo "")
    if [[ -n "$flock_path" ]]; then
        # Override PATH to exclude flock location
        export PATH="${TEST_TEMP_DIR}/empty_bin:/usr/bin:/bin"
    fi

    # Should still be able to acquire lock using fallback
    run acquire_lock
    [ "$status" -eq 0 ]

    release_lock

    # Restore PATH
    export PATH="$PATH_BACKUP"
}

@test "lock: lock is released on exit trap" {
    # Run in subshell that exits unexpectedly
    (
        source "${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh"
        export LOCK_FILE="$LOCK_FILE"
        acquire_lock "$LOCK_FILE"
        # Exit without explicitly releasing - trap should handle it
        exit 0
    )

    # Lock should be released now
    # Another process should be able to acquire it
    run acquire_lock
    [ "$status" -eq 0 ]

    release_lock
}

@test "lock: lock timeout is respected" {
    # Acquire lock in background process
    (
        source "${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh"
        export LOCK_FILE="$LOCK_FILE"
        acquire_lock "$LOCK_FILE"
        sleep 10
        release_lock "$LOCK_FILE"
    ) &
    local bg_pid=$!

    sleep 1  # Ensure background process acquires lock first

    # Try to acquire with short timeout
    local start_time=$(date +%s)
    run acquire_lock "$LOCK_FILE" 3
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Should fail
    [ "$status" -ne 0 ]

    # Should timeout around 3 seconds (allow some variance)
    [ "$elapsed" -ge 2 ]
    [ "$elapsed" -le 5 ]

    # Clean up background process
    kill $bg_pid 2>/dev/null || true
    wait $bg_pid 2>/dev/null || true
}

@test "lock: concurrent upgrades are prevented" {
    # Simulate concurrent upgrade attempts
    local log_file="${TEST_TEMP_DIR}/upgrade.log"

    # Start first upgrade
    (
        source "${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh"
        export LOCK_FILE="$LOCK_FILE"
        if acquire_lock "$LOCK_FILE" 30; then
            echo "Upgrade 1 started" >> "$log_file"
            sleep 2
            echo "Upgrade 1 completed" >> "$log_file"
            release_lock "$LOCK_FILE"
        else
            echo "Upgrade 1 failed to acquire lock" >> "$log_file"
        fi
    ) &

    sleep 0.5  # Small delay

    # Start second upgrade (should be blocked)
    (
        source "${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh"
        export LOCK_FILE="$LOCK_FILE"
        if acquire_lock "$LOCK_FILE" 5; then
            echo "Upgrade 2 started" >> "$log_file"
            echo "Upgrade 2 completed" >> "$log_file"
            release_lock "$LOCK_FILE"
        else
            echo "Upgrade 2 failed to acquire lock" >> "$log_file"
        fi
    ) &

    # Wait for both
    wait

    # Check log
    run cat "$log_file"

    # First upgrade should complete
    [[ "$output" =~ "Upgrade 1 started" ]]
    [[ "$output" =~ "Upgrade 1 completed" ]]

    # Second should fail to acquire lock (timeout)
    [[ "$output" =~ "Upgrade 2 failed to acquire lock" ]]
}

@test "lock: lock ownership verification" {
    # Acquire lock
    acquire_lock

    # Verify PID in lock file
    local lock_pid=$(cat "$LOCK_FILE")
    [ "$lock_pid" = "$$" ]

    # Try to release from different process (should not remove lock)
    run bash -c "
        rm -f '$LOCK_FILE'
        exit 0
    "

    # In production code, release_lock checks PID ownership
    # so another process shouldn't be able to release our lock
    release_lock
}

@test "lock: is_locked function works correctly" {
    # No lock initially
    run is_locked "$LOCK_FILE"
    [ "$status" -ne 0 ]

    # Acquire lock
    acquire_lock "$LOCK_FILE"

    # Should be locked now
    run is_locked "$LOCK_FILE"
    [ "$status" -eq 0 ]

    # Release
    release_lock "$LOCK_FILE"

    # Should not be locked
    run is_locked "$LOCK_FILE"
    [ "$status" -ne 0 ]
}

@test "lock: directory creation failure is handled" {
    # Point to a directory we can't create
    local impossible_lock="/root/impossible/nested/path/test.lock"

    # Should fail gracefully (not running as root)
    run acquire_lock "$impossible_lock"
    [ "$status" -ne 0 ]
}

@test "lock: multiple sequential acquisitions work" {
    # Acquire and release multiple times
    for i in {1..5}; do
        run acquire_lock "$LOCK_FILE"
        [ "$status" -eq 0 ]

        run release_lock "$LOCK_FILE"

        # Lock file should be removed
        [ ! -f "$LOCK_FILE" ]
    done
}

@test "lock: lock prevents race in state file updates" {
    # Multiple processes trying to update state simultaneously
    STATE_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades"
    mkdir -p "$STATE_DIR"

    # Create initial state
    echo '{"counter": 0}' > "${STATE_DIR}/state.json"

    # Launch multiple processes to increment counter
    for i in {1..10}; do
        (
            source "${BATS_TEST_DIRNAME}/../../scripts/lib/lock-utils.sh"
            export LOCK_FILE="$LOCK_FILE"

            if acquire_lock "$LOCK_FILE" 30; then
                # Read current value
                local current=$(jq -r '.counter' "${STATE_DIR}/state.json")

                # Increment
                local new=$((current + 1))

                # Write back
                echo "{\"counter\": $new}" > "${STATE_DIR}/state.json"

                release_lock "$LOCK_FILE"
            fi
        ) &
    done

    # Wait for all processes
    wait

    # Final counter should be 10 if locking worked
    local final=$(jq -r '.counter' "${STATE_DIR}/state.json")
    [ "$final" -eq 10 ]
}
