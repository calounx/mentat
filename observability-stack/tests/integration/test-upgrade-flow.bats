#!/usr/bin/env bats
#===============================================================================
# Integration Test: End-to-End Upgrade Flow
# Tests complete upgrade process from start to finish
#===============================================================================

load '../helpers'

setup() {
    setup_test_environment

    # Create comprehensive test structure
    STATE_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades"
    BACKUP_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades/backups"
    CHECKPOINT_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades/checkpoints"

    mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$CHECKPOINT_DIR"

    export STATE_DIR BACKUP_BASE_DIR="$BACKUP_DIR" CHECKPOINT_DIR

    # Create upgrade configuration
    UPGRADE_CONFIG_FILE="${TEST_TEMP_DIR}/config/upgrade.yaml"
    mkdir -p "$(dirname "$UPGRADE_CONFIG_FILE")"

    cat > "$UPGRADE_CONFIG_FILE" <<'EOF'
global:
  min_disk_space: 1024
  backup_enabled: true

node_exporter:
  binary_path: /usr/local/bin/node_exporter
  target_version: 1.9.1
  from_version: 1.7.0
  service: node_exporter
  phase: 1
  risk_level: low
  dependencies: []

prometheus:
  binary_path: /usr/local/bin/prometheus
  target_version: 2.50.0
  from_version: 2.45.0
  service: prometheus
  phase: 2
  risk_level: high
  dependencies:
    - node_exporter
EOF

    export UPGRADE_CONFIG_FILE

    # Create mock binaries
    mkdir -p "${TEST_TEMP_DIR}/usr/local/bin"

    # Create mock node_exporter
    cat > "${TEST_TEMP_DIR}/usr/local/bin/node_exporter" <<'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "node_exporter, version 1.7.0"
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/usr/local/bin/node_exporter"

    # Create mock prometheus
    cat > "${TEST_TEMP_DIR}/usr/local/bin/prometheus" <<'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "prometheus, version 2.45.0"
fi
EOF
    chmod +x "${TEST_TEMP_DIR}/usr/local/bin/prometheus"

    # Update config to use mock binaries
    sed -i "s|/usr/local/bin/|${TEST_TEMP_DIR}/usr/local/bin/|g" "$UPGRADE_CONFIG_FILE"

    # Source all required libraries
    source_lib "upgrade-state.sh" || skip "upgrade-state.sh not found"
    source_lib "upgrade-manager.sh" 2>/dev/null || skip "upgrade-manager.sh not found"
    source_lib "versions.sh" 2>/dev/null || true
}

teardown() {
    cleanup_test_environment
}

@test "integration: complete upgrade workflow - initialization" {
    # Initialize state
    run state_init
    [ "$status" -eq 0 ]

    # Verify state file was created
    [ -f "${STATE_DIR}/state.json" ]

    # Verify initial state
    local status=$(state_read "status")
    [ "$status" = "idle" ]
}

@test "integration: complete upgrade workflow - begin upgrade" {
    state_init

    # Begin upgrade session
    run state_begin_upgrade "standard"
    [ "$status" -eq 0 ]

    # Verify upgrade started
    local status=$(state_read "status")
    [ "$status" = "in_progress" ]

    # Verify upgrade ID was generated
    local upgrade_id=$(state_read "upgrade_id")
    [ -n "$upgrade_id" ]
    [[ "$upgrade_id" =~ upgrade- ]]
}

@test "integration: complete upgrade workflow - component upgrade sequence" {
    state_init
    state_begin_upgrade "standard"

    # Upgrade node_exporter (phase 1, no dependencies)
    state_begin_component "node_exporter" "1.7.0" "1.9.1"

    # Simulate successful upgrade
    state_complete_component "node_exporter" "checksum123" "${BACKUP_DIR}/node_exporter"

    # Verify component completed
    local comp_status=$(state_read "components.node_exporter.status")
    [ "$comp_status" = "completed" ]

    # Now upgrade prometheus (phase 2, depends on node_exporter)
    state_begin_component "prometheus" "2.45.0" "2.50.0"
    state_complete_component "prometheus" "checksum456" "${BACKUP_DIR}/prometheus"

    # Verify both completed
    local prom_status=$(state_read "components.prometheus.status")
    [ "$prom_status" = "completed" ]
}

@test "integration: complete upgrade workflow - version detection" {
    if declare -f detect_installed_version &>/dev/null; then
        # Detect version of mock node_exporter
        run detect_installed_version "node_exporter"
        [ "$status" -eq 0 ]
        [[ "$output" =~ "1.7.0" ]]

        # Detect version of mock prometheus
        run detect_installed_version "prometheus"
        [ "$status" -eq 0 ]
        [[ "$output" =~ "2.45.0" ]]
    else
        skip "detect_installed_version not available"
    fi
}

@test "integration: complete upgrade workflow - version comparison" {
    if declare -f compare_versions &>/dev/null; then
        # Test version comparisons
        run compare_versions "1.7.0" "1.9.1"
        [ "$status" -eq 0 ]
        [ "$output" = "-1" ]  # 1.7.0 < 1.9.1

        run compare_versions "2.50.0" "2.45.0"
        [ "$status" -eq 0 ]
        [ "$output" = "1" ]  # 2.50.0 > 2.45.0

        run compare_versions "1.0.0" "1.0.0"
        [ "$status" -eq 0 ]
        [ "$output" = "0" ]  # Equal
    else
        skip "compare_versions not available"
    fi
}

@test "integration: complete upgrade workflow - needs upgrade check" {
    if declare -f needs_upgrade &>/dev/null; then
        # node_exporter at 1.7.0, target 1.9.1 - needs upgrade
        run needs_upgrade "node_exporter" "1.9.1"
        [ "$status" -eq 0 ]

        # If we set target to current version, no upgrade needed
        run needs_upgrade "node_exporter" "1.7.0"
        [ "$status" -ne 0 ]
    else
        skip "needs_upgrade not available"
    fi
}

@test "integration: complete upgrade workflow - backup creation" {
    if declare -f backup_component &>/dev/null; then
        # Create backup of node_exporter
        run backup_component "node_exporter"

        # Should succeed or skip if disabled
        [ "$status" -eq 0 ] || [[ "$output" =~ "disabled|skipped" ]]

        # If succeeded, backup should exist
        if [ "$status" -eq 0 ] && [[ ! "$output" =~ "disabled" ]]; then
            [ -n "$output" ]
            [ -d "$output" ]
        fi
    else
        skip "backup_component not available"
    fi
}

@test "integration: complete upgrade workflow - checkpoint management" {
    state_init
    state_begin_upgrade "standard"

    # Create initial checkpoint
    run state_create_checkpoint "pre_upgrade" "Before starting upgrades"
    [ "$status" -eq 0 ]

    # Make some changes
    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    # Create another checkpoint
    run state_create_checkpoint "after_node_exporter" "After node_exporter upgrade"
    [ "$status" -eq 0 ]

    # Restore to first checkpoint
    run state_restore_checkpoint "pre_upgrade"
    [ "$status" -eq 0 ]

    # node_exporter should not be in completed state anymore
    local comp_status=$(state_read "components.node_exporter.status")
    [ -z "$comp_status" ] || [ "$comp_status" = "null" ]
}

@test "integration: complete upgrade workflow - failure and rollback" {
    state_init
    state_begin_upgrade "standard"

    # Start component upgrade
    state_begin_component "node_exporter" "1.7.0" "1.9.1"

    # Simulate failure
    run state_fail_component "node_exporter" "Download failed"
    [ "$status" -eq 0 ]

    # Verify failure recorded
    local comp_status=$(state_read "components.node_exporter.status")
    [ "$comp_status" = "failed" ]

    local error=$(state_read "components.node_exporter.error")
    [[ "$error" =~ "Download failed" ]]
}

@test "integration: complete upgrade workflow - skip component" {
    state_init
    state_begin_upgrade "standard"

    # Skip a component
    run state_skip_component "node_exporter" "Already at target version"
    [ "$status" -eq 0 ]

    # Verify skipped
    local comp_status=$(state_read "components.node_exporter.status")
    [ "$comp_status" = "skipped" ]
}

@test "integration: complete upgrade workflow - complete upgrade" {
    state_init
    state_begin_upgrade "standard"

    # Complete all components
    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    state_begin_component "prometheus" "2.45.0" "2.50.0"
    state_complete_component "prometheus" "def456"

    # Complete upgrade
    run state_complete_upgrade
    [ "$status" -eq 0 ]

    # Verify completed
    local status=$(state_read "status")
    [ "$status" = "completed" ]

    # Should have completion timestamp
    local completed_at=$(state_read "completed_at")
    [ -n "$completed_at" ]
    [ "$completed_at" != "null" ]
}

@test "integration: complete upgrade workflow - history tracking" {
    state_init
    state_begin_upgrade "standard"

    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    state_complete_upgrade

    # Check history
    if declare -f state_list_history &>/dev/null; then
        run state_list_history
        [ "$status" -eq 0 ]

        # Should show our upgrade
        [[ "$output" =~ "upgrade-" ]]
        [[ "$output" =~ "completed" ]]
    fi
}

@test "integration: complete upgrade workflow - resume after crash" {
    state_init
    state_begin_upgrade "standard"

    # Complete first component
    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    # Start second component but don't finish (simulating crash)
    state_begin_component "prometheus" "2.45.0" "2.50.0"

    # Verify state is resumable
    if declare -f state_is_resumable &>/dev/null; then
        run state_is_resumable
        [ "$status" -eq 0 ]
    fi

    # Should be able to determine what needs to be done
    local node_status=$(state_read "components.node_exporter.status")
    local prom_status=$(state_read "components.prometheus.status")

    [ "$node_status" = "completed" ]
    [ "$prom_status" = "in_progress" ]

    # Complete the in-progress component
    state_complete_component "prometheus" "def456"

    # Complete upgrade
    state_complete_upgrade

    # Verify everything completed
    local status=$(state_read "status")
    [ "$status" = "completed" ]
}

@test "integration: complete upgrade workflow - phase ordering" {
    state_init
    state_begin_upgrade "standard"

    # Set phases
    state_set_phase 1

    # Phase 1 component
    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    # Move to phase 2
    state_set_phase 2

    # Phase 2 component
    state_begin_component "prometheus" "2.45.0" "2.50.0"
    state_complete_component "prometheus" "def456"

    # Verify phases were tracked
    local phase=$(state_read "current_phase")
    [ "$phase" = "2" ]
}

@test "integration: complete upgrade workflow - state verification" {
    state_init
    state_begin_upgrade "standard"

    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    # Verify state consistency
    if declare -f state_verify &>/dev/null; then
        run state_verify
        [ "$status" -eq 0 ]

        # Corrupt state
        echo "invalid" > "${STATE_DIR}/state.json"

        run state_verify
        [ "$status" -ne 0 ]
    fi
}

@test "integration: complete upgrade workflow - statistics collection" {
    state_init
    state_begin_upgrade "standard"

    # Create components in different states
    state_begin_component "comp1" "1.0.0" "2.0.0"
    state_complete_component "comp1" "abc123"

    state_begin_component "comp2" "1.0.0" "2.0.0"
    state_fail_component "comp2" "Failed"

    state_skip_component "comp3" "Not needed"

    # Get statistics
    if declare -f state_get_stats &>/dev/null; then
        run state_get_stats
        [ "$status" -eq 0 ]

        [[ "$output" =~ "Completed: 1" ]]
        [[ "$output" =~ "Failed: 1" ]]
        [[ "$output" =~ "Skipped: 1" ]]
        [[ "$output" =~ "Total components: 3" ]]
    fi
}

@test "integration: complete upgrade workflow - state summary" {
    state_init
    state_begin_upgrade "standard"

    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    # Get summary
    if declare -f state_summary &>/dev/null; then
        run state_summary
        [ "$status" -eq 0 ]

        [[ "$output" =~ "Upgrade ID" ]]
        [[ "$output" =~ "Status" ]]
        [[ "$output" =~ "in_progress"|"In progress" ]]
    fi
}

@test "integration: complete upgrade workflow - idempotency check" {
    state_init
    state_begin_upgrade "standard"

    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123"

    # Try to upgrade again (should be idempotent)
    if declare -f state_component_needs_upgrade &>/dev/null; then
        run state_component_needs_upgrade "node_exporter"

        # Should return 1 (false) since already completed
        [ "$status" -ne 0 ]
    fi
}

@test "integration: complete upgrade workflow - atomic state updates" {
    state_init

    # Multiple rapid updates should all succeed
    for i in {1..10}; do
        state_update ".test_field_$i = \"value_$i\"" &
    done

    wait

    # State should still be valid JSON
    run jq empty "${STATE_DIR}/state.json"
    [ "$status" -eq 0 ]

    # All fields should be present
    for i in {1..10}; do
        local value=$(state_read "test_field_$i")
        [ "$value" = "value_$i" ]
    done
}

@test "integration: complete upgrade workflow - error handling" {
    state_init
    state_begin_upgrade "standard"

    # Record multiple errors
    state_begin_component "comp1" "1.0.0" "2.0.0"
    state_fail_component "comp1" "Error 1"

    state_begin_component "comp2" "1.0.0" "2.0.0"
    state_fail_component "comp2" "Error 2"

    # Fail overall upgrade
    state_fail_upgrade "Multiple component failures"

    # Verify all errors recorded
    local status=$(state_read "status")
    [ "$status" = "failed" ]

    local error_count=$(state_read "errors" | jq 'length')
    [ "$error_count" -ge 1 ]
}

@test "integration: complete upgrade workflow - full cycle" {
    # This test runs through a complete upgrade cycle
    state_init

    # Verify initial idle state
    local status=$(state_read "status")
    [ "$status" = "idle" ]

    # Begin upgrade
    state_begin_upgrade "standard"

    # Create pre-upgrade checkpoint
    state_create_checkpoint "pre_upgrade" "Before starting"

    # Upgrade components in order
    state_set_phase 1

    state_begin_component "node_exporter" "1.7.0" "1.9.1"
    state_complete_component "node_exporter" "abc123" "${BACKUP_DIR}/node_exporter"

    state_set_phase 2

    state_begin_component "prometheus" "2.45.0" "2.50.0"
    state_complete_component "prometheus" "def456" "${BACKUP_DIR}/prometheus"

    # Complete upgrade
    state_complete_upgrade

    # Verify final state
    status=$(state_read "status")
    [ "$status" = "completed" ]

    # Verify all components completed
    local node_status=$(state_read "components.node_exporter.status")
    local prom_status=$(state_read "components.prometheus.status")

    [ "$node_status" = "completed" ]
    [ "$prom_status" = "completed" ]

    # Verify checksums recorded
    local node_checksum=$(state_read "components.node_exporter.checksum")
    local prom_checksum=$(state_read "components.prometheus.checksum")

    [ "$node_checksum" = "abc123" ]
    [ "$prom_checksum" = "def456" ]

    # Verify backup paths recorded
    local node_backup=$(state_read "components.node_exporter.backup_path")
    local prom_backup=$(state_read "components.prometheus.backup_path")

    [[ "$node_backup" =~ "node_exporter" ]]
    [[ "$prom_backup" =~ "prometheus" ]]

    # Verify timestamps exist
    local started_at=$(state_read "started_at")
    local completed_at=$(state_read "completed_at")

    [ -n "$started_at" ]
    [ "$started_at" != "null" ]
    [ -n "$completed_at" ]
    [ "$completed_at" != "null" ]

    # Verify upgrade ID exists
    local upgrade_id=$(state_read "upgrade_id")
    [ -n "$upgrade_id" ]
    [[ "$upgrade_id" =~ upgrade- ]]
}
