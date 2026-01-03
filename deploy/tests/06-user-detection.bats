#!/usr/bin/env bats
# Test user detection logic

load test-helper

setup() {
    setup_test_env
    create_mock_utils

    # Create test script for user detection
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-user-detection.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# User detection logic from deploy-chom-automated.sh
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
CURRENT_USER="${SUDO_USER:-$(whoami)}"

# Output for verification
echo "DEPLOY_USER=${DEPLOY_USER}"
echo "CURRENT_USER=${CURRENT_USER}"

# Check if running with sudo
if [[ $EUID -eq 0 ]]; then
    echo "RUNNING_AS_ROOT=true"
else
    echo "RUNNING_AS_ROOT=false"
fi

# Check SUDO_USER
if [[ -n "${SUDO_USER:-}" ]]; then
    echo "SUDO_USER_SET=true"
    echo "SUDO_USER_VALUE=${SUDO_USER}"
else
    echo "SUDO_USER_SET=false"
fi

# Verify whoami fallback
WHOAMI_OUTPUT="$(whoami)"
echo "WHOAMI=${WHOAMI_OUTPUT}"
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "DEPLOY_USER defaults to stilgar" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "DEPLOY_USER=stilgar" ]]
}

@test "DEPLOY_USER can be overridden via environment" {
    DEPLOY_USER="custom_user" run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "DEPLOY_USER=custom_user" ]]
}

@test "CURRENT_USER uses SUDO_USER when available" {
    SUDO_USER="actual_user" run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "CURRENT_USER=actual_user" ]]
    [[ "$output" =~ "SUDO_USER_SET=true" ]]
}

@test "CURRENT_USER falls back to whoami when SUDO_USER not set" {
    # Ensure SUDO_USER is not set
    unset SUDO_USER

    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SUDO_USER_SET=false" ]]

    # CURRENT_USER should equal WHOAMI
    local current_user=$(echo "$output" | grep "^CURRENT_USER=" | cut -d= -f2)
    local whoami_user=$(echo "$output" | grep "^WHOAMI=" | cut -d= -f2)

    [ "$current_user" = "$whoami_user" ]
}

@test "Running as root is detected" {
    skip "Requires root privileges - test in integration environment"
}

@test "Running as non-root is detected" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "RUNNING_AS_ROOT=false" ]]
}

@test "User detection works when called via sudo" {
    skip "Requires sudo setup - test in integration environment"
}

@test "Different DEPLOY_USER values are accepted" {
    local test_users=("deploy" "automation" "ci" "jenkins")

    for user in "${test_users[@]}"; do
        DEPLOY_USER="$user" run "$TEST_SCRIPT"

        [ "$status" -eq 0 ]
        [[ "$output" =~ "DEPLOY_USER=${user}" ]]
    done
}

@test "CURRENT_USER is always set" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]

    # Extract CURRENT_USER value
    local current_user=$(echo "$output" | grep "^CURRENT_USER=" | cut -d= -f2)

    # Should not be empty
    [ -n "$current_user" ]
}

@test "DEPLOY_USER and CURRENT_USER can be different" {
    DEPLOY_USER="stilgar" SUDO_USER="calounx" run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "DEPLOY_USER=stilgar" ]]
    [[ "$output" =~ "CURRENT_USER=calounx" ]]
}

@test "Empty DEPLOY_USER env var uses default" {
    DEPLOY_USER="" run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "DEPLOY_USER=stilgar" ]]
}

@test "User variables contain no special characters" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]

    local deploy_user=$(echo "$output" | grep "^DEPLOY_USER=" | cut -d= -f2)
    local current_user=$(echo "$output" | grep "^CURRENT_USER=" | cut -d= -f2)

    # Check for valid username pattern (alphanumeric, underscore, hyphen)
    [[ "$deploy_user" =~ ^[a-zA-Z0-9_-]+$ ]]
    [[ "$current_user" =~ ^[a-zA-Z0-9_-]+$ ]]
}
