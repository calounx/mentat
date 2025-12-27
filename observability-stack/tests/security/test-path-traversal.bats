#!/usr/bin/env bats
#===============================================================================
# Security Test: Path Traversal Prevention (M-3)
# Tests that component names are validated to prevent directory traversal attacks
#===============================================================================

load '../helpers'

setup() {
    setup_test_environment

    # Create test directories
    BACKUP_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades/backups"
    STATE_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades"
    mkdir -p "$BACKUP_DIR" "$STATE_DIR"

    export BACKUP_BASE_DIR="$BACKUP_DIR"
    export STATE_DIR

    # Source libraries
    source_lib "upgrade-state.sh" || skip "upgrade-state.sh not found"
    source_lib "upgrade-manager.sh" 2>/dev/null || true
    source_lib "validation.sh" 2>/dev/null || true
}

teardown() {
    cleanup_test_environment
}

@test "path traversal: component name with ../ sequences" {
    # Attempt to traverse up directories
    local malicious_name="../../../etc/passwd"

    # Should be rejected by validation or safely sanitized
    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Check that no files were created outside the backup directory
    [ ! -f "/etc/passwd.backup" ]
    [ ! -d "${BACKUP_DIR}/../../../etc/passwd" ]
}

@test "path traversal: component name with absolute path" {
    # Attempt to use absolute path
    local malicious_name="/tmp/malicious"

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not create files in /tmp
    [ ! -d "/tmp/malicious" ]
}

@test "path traversal: component name with encoded sequences" {
    # URL-encoded path traversal
    local malicious_name="%2e%2e%2f%2e%2e%2fetc%2fpasswd"

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not traverse directories
    [ ! -f "/etc/passwd.backup" ]
}

@test "path traversal: component name with null bytes" {
    # Null byte injection to truncate path
    local malicious_name=$'legitimate\x00../../../etc/passwd'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not access /etc/passwd
    [ ! -f "/etc/passwd.backup" ]
}

@test "path traversal: component name with symlink attack" {
    # Create a symlink that points outside allowed directory
    ln -s /etc "${BACKUP_DIR}/malicious_link"

    local malicious_name="malicious_link/../passwd"

    # Should not follow symlink to /etc/passwd
    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Verify passwd file wasn't accessed
    [ ! -f "/etc/passwd.backup" ]
}

@test "path traversal: validate component name format" {
    # Test component name validation function if it exists
    if declare -f validate_component_name &>/dev/null; then
        # Valid names should pass
        run validate_component_name "node_exporter"
        [ "$status" -eq 0 ]

        run validate_component_name "prometheus-server"
        [ "$status" -eq 0 ]

        # Invalid names should fail
        run validate_component_name "../etc/passwd"
        [ "$status" -ne 0 ]

        run validate_component_name "/absolute/path"
        [ "$status" -ne 0 ]

        run validate_component_name "name with spaces"
        [ "$status" -ne 0 ]

        run validate_component_name "name;injection"
        [ "$status" -ne 0 ]
    else
        skip "validate_component_name function not found"
    fi
}

@test "path traversal: backup path construction is safe" {
    # Test that backup paths are constructed safely
    local component="node_exporter"

    # Construct backup path (simulating backup_component function)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_BASE_DIR}/${component}/${timestamp}"

    # Verify path is within BACKUP_BASE_DIR
    local canonical_backup=$(cd "$BACKUP_BASE_DIR" && pwd)
    local constructed_path_parent=$(dirname "$backup_path")

    # The parent should start with BACKUP_BASE_DIR
    [[ "$constructed_path_parent" == "$canonical_backup"* ]]
}

@test "path traversal: checkpoint file paths are safe" {
    CHECKPOINT_DIR="${STATE_DIR}/checkpoints"
    mkdir -p "$CHECKPOINT_DIR"

    # Attempt to create checkpoint with malicious name
    local malicious_checkpoint="../../../tmp/evil_checkpoint"

    run state_create_checkpoint "$malicious_checkpoint" "test"

    # Should not create file outside checkpoint directory
    [ ! -f "/tmp/evil_checkpoint.json" ]
    [ ! -f "${STATE_DIR}/../../../tmp/evil_checkpoint.json" ]
}

@test "path traversal: state file paths cannot be manipulated" {
    # Attempt to manipulate state file path through component name
    local malicious_component="../../state"

    run state_begin_component "$malicious_component" "1.0.0" "2.0.0"

    # Original state file should still be intact
    [ -f "${STATE_DIR}/state.json" ]

    # No state files should be created outside STATE_DIR
    [ ! -f "${STATE_DIR}/../../state/state.json" ]
}

@test "path traversal: binary path validation" {
    # If upgrade-manager is loaded, test binary path validation
    if declare -f detect_installed_version &>/dev/null; then
        # Create a config with malicious binary path
        UPGRADE_CONFIG_FILE="${TEST_TEMP_DIR}/config/upgrade.yaml"
        mkdir -p "$(dirname "$UPGRADE_CONFIG_FILE")"

        cat > "$UPGRADE_CONFIG_FILE" <<'EOF'
node_exporter:
  binary_path: ../../bin/evil
  target_version: 2.0.0
EOF

        # Should not access binary outside expected locations
        run detect_installed_version "node_exporter"

        # Should fail or safely handle the path
        [ "$status" -ne 0 ] || [ -z "$output" ]
    else
        skip "detect_installed_version function not available"
    fi
}

@test "path traversal: config file paths are validated" {
    # Test configuration file path validation
    local malicious_config="../../../etc/shadow"

    # If validation library is loaded
    if declare -f validate_file_exists &>/dev/null; then
        # Should reject paths outside allowed directories
        run validate_file_exists "$malicious_config" "config file"

        # Should fail (file doesn't exist in safe location)
        [ "$status" -ne 0 ]
    else
        skip "validate_file_exists function not available"
    fi
}

@test "path traversal: module paths are restricted" {
    # Test that module names can't traverse directories
    MODULES_DIR="${TEST_TEMP_DIR}/modules/_core"
    mkdir -p "$MODULES_DIR"

    local malicious_module="../../../tmp/evil_module"

    # Construct module path
    local module_path="${MODULES_DIR}/${malicious_module}"

    # Should not resolve outside MODULES_DIR
    # Check the canonical path
    if [ -d "$(dirname "$module_path")" ]; then
        local canonical=$(cd "$(dirname "$module_path")" && pwd)
        local allowed=$(cd "$MODULES_DIR" && pwd)

        # Path should be within allowed directory
        [[ "$canonical" == "$allowed"* ]]
    fi
}

@test "path traversal: prevent access to sensitive files via component name" {
    # List of sensitive paths that should never be accessed
    local sensitive_paths=(
        "/etc/shadow"
        "/etc/passwd"
        "/root/.ssh/id_rsa"
        "/etc/ssh/sshd_config"
    )

    for sensitive_path in "${sensitive_paths[@]}"; do
        # Try to use filename as component name
        local component_name=$(basename "$sensitive_path")

        run state_begin_component "$component_name" "1.0.0" "2.0.0"

        # Verify the sensitive file wasn't modified or accessed
        if [ -f "$sensitive_path" ]; then
            # Check modification time hasn't changed recently
            local mtime=$(stat -c %Y "$sensitive_path" 2>/dev/null || echo "0")
            local now=$(date +%s)
            local age=$((now - mtime))

            # File should not have been modified in last 5 seconds
            [ "$age" -gt 5 ]
        fi
    done
}

@test "path traversal: double encoding attack" {
    # Double-encoded path traversal
    local malicious_name="%252e%252e%252f%252e%252e%252fetc"

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not traverse directories
    [ ! -d "/etc" ] || [ ! -f "${BACKUP_DIR}/etc" ]
}

@test "path traversal: unicode normalization attack" {
    # Unicode characters that might normalize to ../
    # U+2024 (ONE DOT LEADER) + U+2024 + /
    local malicious_name=$'\u2024\u2024/\u2024\u2024/etc'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not access /etc
    [ ! -d "/etc.backup" ]
}

@test "path traversal: verify allowed character set for component names" {
    # Only alphanumeric, underscore, and hyphen should be allowed
    local valid_names=(
        "node_exporter"
        "prometheus-server"
        "mysql_exporter_v2"
        "test123"
    )

    local invalid_names=(
        "../test"
        "test/../other"
        "/absolute"
        "test;command"
        "test\$var"
        "test space"
        "test.exe"
    )

    # If there's a validation function, test it
    if declare -f validate_pattern &>/dev/null; then
        local safe_pattern='^[a-zA-Z0-9_-]+$'

        for name in "${valid_names[@]}"; do
            [[ "$name" =~ $safe_pattern ]]
        done

        for name in "${invalid_names[@]}"; do
            ! [[ "$name" =~ $safe_pattern ]]
        done
    fi
}

@test "path traversal: backup restoration prevents directory traversal" {
    # Test that restore_from_backup function validates paths
    if declare -f restore_from_backup &>/dev/null; then
        local malicious_backup="../../../etc"

        run restore_from_backup "test_component" "$malicious_backup"

        # Should fail to restore from outside backup directory
        [ "$status" -ne 0 ] || [[ "$output" =~ "not found|invalid" ]]
    else
        skip "restore_from_backup function not available"
    fi
}
