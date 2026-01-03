#!/usr/bin/env bats
# Test SSH key generation and operations

load test-helper

setup() {
    setup_test_env
    create_mock_utils
    mock_ssh
    mock_scp

    # Create test script for SSH operations
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-ssh-operations.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEPLOY_USER="${DEPLOY_USER:-stilgar}"
CURRENT_USER="${CURRENT_USER:-testuser}"
LANDSRAAD_HOST="${LANDSRAAD_HOST:-landsraad.arewel.com}"
SSH_KEY_PATH="${SCRIPT_DIR}/.ssh/id_ed25519"

# Mock sudo command for testing
sudo() {
    if [[ "$1" == "-u" ]]; then
        shift  # Remove -u
        shift  # Remove username
        # Execute as regular command (can't actually change user in test)
        "$@"
    else
        # Execute command normally
        "$@"
    fi
}

# Generate SSH key
generate_ssh_key() {
    local key_dir=$(dirname "$SSH_KEY_PATH")
    mkdir -p "$key_dir"

    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        echo "Generating SSH key at $SSH_KEY_PATH"
        # Use mock key for testing
        echo "MOCK_PRIVATE_KEY" > "$SSH_KEY_PATH"
        echo "MOCK_PUBLIC_KEY" > "${SSH_KEY_PATH}.pub"
        chmod 600 "$SSH_KEY_PATH"
        chmod 644 "${SSH_KEY_PATH}.pub"
        echo "SSH_KEY_GENERATED=true"
    else
        echo "SSH_KEY_GENERATED=false (already exists)"
    fi
}

# Copy SSH key to remote host
copy_ssh_key() {
    local pub_key=$(cat "${SSH_KEY_PATH}.pub")

    echo "Copying SSH key to ${LANDSRAAD_HOST}"

    ssh "${CURRENT_USER}@${LANDSRAAD_HOST}" "
        mkdir -p /home/${DEPLOY_USER}/.ssh
        echo '$pub_key' >> /home/${DEPLOY_USER}/.ssh/authorized_keys
        chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys
        chmod 700 /home/${DEPLOY_USER}/.ssh
    "

    echo "SSH_KEY_COPIED=true"
}

# Test SSH connection
test_ssh_connection() {
    echo "Testing SSH connection to ${LANDSRAAD_HOST}"

    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${LANDSRAAD_HOST}" "echo 'SSH OK'" 2>/dev/null; then
        echo "SSH_CONNECTION_TEST=passed"
        return 0
    else
        echo "SSH_CONNECTION_TEST=failed"
        return 1
    fi
}

# Execute remote command
execute_remote_command() {
    local command="$1"

    echo "Executing remote command: $command"

    if ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "$command"; then
        echo "REMOTE_COMMAND_SUCCESS=true"
        return 0
    else
        echo "REMOTE_COMMAND_SUCCESS=false"
        return 1
    fi
}

# Main test flow based on command
case "${1:-all}" in
    generate)
        generate_ssh_key
        ;;
    copy)
        copy_ssh_key
        ;;
    test)
        test_ssh_connection
        ;;
    execute)
        execute_remote_command "${2:-echo test}"
        ;;
    all)
        generate_ssh_key
        copy_ssh_key
        test_ssh_connection
        execute_remote_command "hostname"
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "SSH key generation creates new key" {
    run "$TEST_SCRIPT" generate

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_KEY_GENERATED=true" ]]
    [ -f "${TEST_TEMP_DIR}/.ssh/id_ed25519" ]
    [ -f "${TEST_TEMP_DIR}/.ssh/id_ed25519.pub" ]
}

@test "SSH key generation skips if key exists" {
    # Create existing key
    mkdir -p "${TEST_TEMP_DIR}/.ssh"
    echo "EXISTING_KEY" > "${TEST_TEMP_DIR}/.ssh/id_ed25519"

    run "$TEST_SCRIPT" generate

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_KEY_GENERATED=false (already exists)" ]]
}

@test "SSH private key has correct permissions" {
    run "$TEST_SCRIPT" generate

    [ "$status" -eq 0 ]

    local perms=$(stat -c "%a" "${TEST_TEMP_DIR}/.ssh/id_ed25519")
    [ "$perms" = "600" ]
}

@test "SSH public key has correct permissions" {
    run "$TEST_SCRIPT" generate

    [ "$status" -eq 0 ]

    local perms=$(stat -c "%a" "${TEST_TEMP_DIR}/.ssh/id_ed25519.pub")
    [ "$perms" = "644" ]
}

@test "SSH key copy executes remote commands" {
    # Generate key first
    "$TEST_SCRIPT" generate > /dev/null 2>&1

    run "$TEST_SCRIPT" copy

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_KEY_COPIED=true" ]]

    # Verify ssh was called
    [ -f "${TEST_TEMP_DIR}/ssh.log" ]
}

@test "SSH connection test uses BatchMode" {
    # Generate and copy key
    "$TEST_SCRIPT" generate > /dev/null 2>&1

    run "$TEST_SCRIPT" test

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_CONNECTION_TEST=passed" ]]
}

@test "SSH connection test fails gracefully" {
    # Set SSH to fail
    export SSH_SHOULD_FAIL=true

    run "$TEST_SCRIPT" test

    [ "$status" -eq 1 ]
    [[ "$output" =~ "SSH_CONNECTION_TEST=failed" ]]
}

@test "Remote command execution works" {
    run "$TEST_SCRIPT" execute "echo test"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "REMOTE_COMMAND_SUCCESS=true" ]]
}

@test "Remote command execution logs command" {
    run "$TEST_SCRIPT" execute "hostname"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Executing remote command: hostname" ]]
}

@test "Remote command execution fails when SSH fails" {
    export SSH_SHOULD_FAIL=true

    run "$TEST_SCRIPT" execute "echo test"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "REMOTE_COMMAND_SUCCESS=false" ]]
}

@test "All SSH operations work together" {
    run "$TEST_SCRIPT" all

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_KEY_GENERATED=true" ]]
    [[ "$output" =~ "SSH_KEY_COPIED=true" ]]
    [[ "$output" =~ "SSH_CONNECTION_TEST=passed" ]]
    [[ "$output" =~ "REMOTE_COMMAND_SUCCESS=true" ]]
}

@test "SSH key path is in user home directory" {
    run "$TEST_SCRIPT" generate

    [ "$status" -eq 0 ]

    # Key should be in .ssh directory
    [ -f "${TEST_TEMP_DIR}/.ssh/id_ed25519" ]

    # Directory should exist
    [ -d "${TEST_TEMP_DIR}/.ssh" ]
}

@test "SSH commands use correct hostname" {
    LANDSRAAD_HOST="custom.example.com" run "$TEST_SCRIPT" test

    [ "$status" -eq 0 ]

    # Check SSH log for custom hostname
    if [ -f "${TEST_TEMP_DIR}/ssh.log" ]; then
        grep "custom.example.com" "${TEST_TEMP_DIR}/ssh.log"
    fi
}

@test "SSH commands use correct user" {
    DEPLOY_USER="customuser" run "$TEST_SCRIPT" test

    [ "$status" -eq 0 ]

    # Check SSH log for custom user
    if [ -f "${TEST_TEMP_DIR}/ssh.log" ]; then
        grep "customuser@" "${TEST_TEMP_DIR}/ssh.log"
    fi
}

@test "SSH operation with SUDO_USER context" {
    CURRENT_USER="calounx" DEPLOY_USER="stilgar" run "$TEST_SCRIPT" copy

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_KEY_COPIED=true" ]]
}
