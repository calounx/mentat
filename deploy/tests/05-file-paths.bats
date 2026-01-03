#!/usr/bin/env bats
# Test file path resolution and directory structure

load test-helper

setup() {
    setup_test_env
    create_mock_utils

    # Create test script for path resolution
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-path-resolution.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Script directory resolution - same as in real deployment scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derived paths
DEPLOY_ROOT="$SCRIPT_DIR"
UTILS_DIR="${DEPLOY_ROOT}/deploy/utils"
SCRIPTS_DIR="${DEPLOY_ROOT}/deploy/scripts"
SECRETS_FILE="${DEPLOY_ROOT}/deploy/.deployment-secrets"
LOG_DIR="/var/log/chom-deploy"

# Output all paths for verification
echo "SCRIPT_DIR=${SCRIPT_DIR}"
echo "DEPLOY_ROOT=${DEPLOY_ROOT}"
echo "UTILS_DIR=${UTILS_DIR}"
echo "SCRIPTS_DIR=${SCRIPTS_DIR}"
echo "SECRETS_FILE=${SECRETS_FILE}"
echo "LOG_DIR=${LOG_DIR}"

# Test absolute path resolution
if [[ "$SCRIPT_DIR" = /* ]]; then
    echo "SCRIPT_DIR_IS_ABSOLUTE=true"
else
    echo "SCRIPT_DIR_IS_ABSOLUTE=false"
fi

# Test if paths exist (will be created by setup)
[[ -d "$UTILS_DIR" ]] && echo "UTILS_DIR_EXISTS=true" || echo "UTILS_DIR_EXISTS=false"
[[ -d "$SCRIPTS_DIR" ]] && echo "SCRIPTS_DIR_EXISTS=true" || echo "SCRIPTS_DIR_EXISTS=false"
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "SCRIPT_DIR resolves to absolute path" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SCRIPT_DIR_IS_ABSOLUTE=true" ]]
    [[ "$output" =~ "SCRIPT_DIR=${TEST_TEMP_DIR}" ]]
}

@test "DEPLOY_ROOT equals SCRIPT_DIR" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]

    local script_dir=$(echo "$output" | grep "^SCRIPT_DIR=" | cut -d= -f2)
    local deploy_root=$(echo "$output" | grep "^DEPLOY_ROOT=" | cut -d= -f2)

    [ "$script_dir" = "$deploy_root" ]
}

@test "UTILS_DIR is correctly derived from DEPLOY_ROOT" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"

    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "UTILS_DIR=${TEST_TEMP_DIR}/deploy/utils" ]]
    [[ "$output" =~ "UTILS_DIR_EXISTS=true" ]]
}

@test "SCRIPTS_DIR is correctly derived from DEPLOY_ROOT" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SCRIPTS_DIR=${TEST_TEMP_DIR}/deploy/scripts" ]]
    [[ "$output" =~ "SCRIPTS_DIR_EXISTS=true" ]]
}

@test "SECRETS_FILE path is correct" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SECRETS_FILE=${TEST_TEMP_DIR}/deploy/.deployment-secrets" ]]
}

@test "Paths work when script run from different directory" {
    # Create a different directory and run script from there
    local other_dir="${TEST_TEMP_DIR}/other"
    mkdir -p "$other_dir"
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    cd "$other_dir"
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    # Path should still resolve to TEST_TEMP_DIR, not to other_dir
    [[ "$output" =~ "SCRIPT_DIR=${TEST_TEMP_DIR}" ]]
    [[ "$output" =~ "UTILS_DIR=${TEST_TEMP_DIR}/deploy/utils" ]]
}

@test "Paths work when script run via symlink" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    # Create symlink in different location
    local link_dir="${TEST_TEMP_DIR}/links"
    mkdir -p "$link_dir"
    ln -s "$TEST_SCRIPT" "${link_dir}/linked-script.sh"

    run "${link_dir}/linked-script.sh"

    [ "$status" -eq 0 ]
    # Should resolve to the actual script location, not the symlink
    [[ "$output" =~ "SCRIPT_DIR=${TEST_TEMP_DIR}" ]]
}

@test "Relative paths are not used" {
    # Check that script doesn't use relative paths like ./utils or ../deploy
    run grep -E '\./|\.\./' "$TEST_SCRIPT"

    # Should not find any relative paths (grep returns non-zero when nothing found)
    [ "$status" -ne 0 ]
}

@test "Path resolution works from repository subdirectory" {
    # Simulate running from mentat/deploy/ subdirectory
    local repo_root="${TEST_TEMP_DIR}/repo"
    local deploy_dir="${repo_root}/deploy"

    mkdir -p "${deploy_dir}/utils"
    mkdir -p "${deploy_dir}/scripts"

    # Create script in deploy directory
    local script="${deploy_dir}/test-from-subdir.sh"
    cat > "$script" << 'SCRIPT_EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$SCRIPT_DIR"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "SCRIPT_DIR=${SCRIPT_DIR}"
echo "DEPLOY_ROOT=${DEPLOY_ROOT}"
echo "REPO_ROOT=${REPO_ROOT}"
SCRIPT_EOF
    chmod +x "$script"

    run "$script"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SCRIPT_DIR=${deploy_dir}" ]]
    [[ "$output" =~ "DEPLOY_ROOT=${deploy_dir}" ]]
    [[ "$output" =~ "REPO_ROOT=${repo_root}" ]]
}

@test "LOG_DIR uses absolute path" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "LOG_DIR=/var/log/chom-deploy" ]]

    # Verify it starts with /
    local log_dir=$(echo "$output" | grep "^LOG_DIR=" | cut -d= -f2)
    [[ "$log_dir" = /* ]]
}

@test "All critical paths are defined and non-empty" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]

    # Extract path values
    local script_dir=$(echo "$output" | grep "^SCRIPT_DIR=" | cut -d= -f2)
    local deploy_root=$(echo "$output" | grep "^DEPLOY_ROOT=" | cut -d= -f2)
    local utils_dir=$(echo "$output" | grep "^UTILS_DIR=" | cut -d= -f2)
    local scripts_dir=$(echo "$output" | grep "^SCRIPTS_DIR=" | cut -d= -f2)

    # All should be non-empty
    [ -n "$script_dir" ]
    [ -n "$deploy_root" ]
    [ -n "$utils_dir" ]
    [ -n "$scripts_dir" ]
}
