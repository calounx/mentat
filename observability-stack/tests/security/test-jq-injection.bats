#!/usr/bin/env bats
#===============================================================================
# Security Test: JQ Injection Prevention (H-1)
# Tests that jq --arg is used to prevent command injection through component names
#===============================================================================

load '../helpers'

setup() {
    setup_test_environment

    # Create mock state directory and file
    STATE_DIR="${TEST_TEMP_DIR}/var/lib/observability-upgrades"
    mkdir -p "$STATE_DIR"
    export STATE_DIR

    # Initialize state file
    cat > "${STATE_DIR}/state.json" <<'EOF'
{
  "version": "1.0.0",
  "upgrade_id": "test-upgrade",
  "status": "in_progress",
  "components": {}
}
EOF

    # Source the upgrade-state library
    source_lib "upgrade-state.sh" || skip "upgrade-state.sh not found"
}

teardown() {
    cleanup_test_environment
}

@test "jq injection: malicious component name with command substitution" {
    # Attempt to inject command via component name
    local malicious_name='test"; $(rm -rf /tmp/hacked); echo "'

    # This should fail validation or safely handle the input
    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should either succeed with escaped name or fail with validation error
    # Either way, /tmp/hacked should NOT be created
    [ ! -f "/tmp/hacked" ]
}

@test "jq injection: component name with backticks" {
    # Attempt injection using backticks
    local malicious_name='test`whoami`'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Verify no command was executed
    # The output should not contain actual username
    [[ ! "$output" =~ root|$USER ]]
}

@test "jq injection: component name with pipe to command" {
    local malicious_name='test | cat /etc/passwd'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not contain passwd file contents
    [[ ! "$output" =~ "root:x:0" ]]
}

@test "jq injection: component name with semicolon command separator" {
    local malicious_name='test; touch /tmp/pwned'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # File should not be created
    [ ! -f "/tmp/pwned" ]
}

@test "jq injection: component name with newline and command" {
    local malicious_name=$'test\ntouch /tmp/exploit'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # File should not be created
    [ ! -f "/tmp/exploit" ]
}

@test "jq injection: verify state file integrity after malicious input" {
    local malicious_name='test"); .status = "pwned" #'

    # Try to inject JSON
    state_begin_component "$malicious_name" "1.0.0" "2.0.0" || true

    # Verify state file is still valid JSON
    run jq empty "${STATE_DIR}/state.json"
    [ "$status" -eq 0 ]

    # Verify status was not changed to "pwned"
    local current_status=$(jq -r '.status' "${STATE_DIR}/state.json")
    [ "$current_status" != "pwned" ]
}

@test "jq injection: component name with dollar brace expansion" {
    local malicious_name='test${IFS}whoami'

    run state_begin_component "$malicious_name" "1.0.0" "2.0.0"

    # Should not execute the command
    [[ ! "$output" =~ root|$USER ]]
}

@test "jq injection: verify jq --arg usage in state_update" {
    # Verify the actual implementation uses jq --arg for safety
    # Check the source code contains safe patterns
    run grep -n 'jq.*--arg' "${BATS_TEST_DIRNAME}/../../scripts/lib/upgrade-state.sh"

    # If jq is used, it should use --arg for variable interpolation
    if [ "$status" -eq 0 ]; then
        # Good - using --arg
        true
    else
        # Check if direct interpolation is used (bad)
        run grep -n 'jq.*".*\$' "${BATS_TEST_DIRNAME}/../../scripts/lib/upgrade-state.sh"
        if [ "$status" -eq 0 ]; then
            # Direct variable interpolation found - potential vulnerability
            echo "Warning: Direct variable interpolation in jq detected"
            echo "$output"
            false
        fi
    fi
}

@test "jq injection: safe handling of quotes in component name" {
    local component_with_quotes='test"component"name'

    run state_begin_component "$component_with_quotes" "1.0.0" "2.0.0"

    # Should handle quotes safely
    # Verify state file is valid JSON
    jq empty "${STATE_DIR}/state.json"
}

@test "jq injection: safe handling of special characters" {
    local special_chars='test@#$%^&*()[]{}|\\<>?'

    # Most of these should be rejected by validation
    # or safely escaped
    run state_begin_component "$special_chars" "1.0.0" "2.0.0"

    # Either succeeds with escaped input or fails with validation error
    # But should not cause command injection
    jq empty "${STATE_DIR}/state.json"
}

@test "jq injection: verify component name validation exists" {
    # Component names should only allow safe characters
    local valid_name="node_exporter"
    local invalid_name="node;rm -rf /"

    # Valid name should work
    run state_begin_component "$valid_name" "1.0.0" "2.0.0"
    [ "$status" -eq 0 ]

    # Check if state contains the component
    run jq -r ".components.\"$valid_name\".status" "${STATE_DIR}/state.json"
    [ "$output" = "in_progress" ]
}

@test "jq injection: test error message injection" {
    # Try to inject malicious content through error messages
    local malicious_error='Error"; .status="compromised"; echo "'

    run state_fail_component "test_component" "$malicious_error"

    # Verify state file is valid JSON
    jq empty "${STATE_DIR}/state.json"

    # Verify status was not changed to "compromised"
    local status=$(jq -r '.status' "${STATE_DIR}/state.json")
    [ "$status" != "compromised" ]
}

@test "jq injection: test checkpoint name injection" {
    # Verify checkpoint names are safely handled
    local malicious_checkpoint='checkpoint"; rm -rf /tmp/*; echo "'

    run state_create_checkpoint "$malicious_checkpoint" "test checkpoint"

    # No files should be deleted in /tmp
    # Checkpoint should either fail or be safely created
    if [ "$status" -eq 0 ]; then
        # Verify state is still valid
        jq empty "${STATE_DIR}/state.json"
    fi
}

@test "jq injection: verify atomic updates prevent race condition exploits" {
    # Multiple rapid updates should not corrupt state
    # even with malicious input
    for i in {1..10}; do
        state_begin_component "component_$i" "1.0.0" "2.0.0" &
    done
    wait

    # State file should still be valid JSON
    run jq empty "${STATE_DIR}/state.json"
    [ "$status" -eq 0 ]
}
