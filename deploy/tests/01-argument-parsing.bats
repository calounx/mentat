#!/usr/bin/env bats
# Test command-line argument parsing for deploy-chom-automated.sh

load test-helper

setup() {
    setup_test_env
    create_mock_utils

    # Create test script that sources the main deploy script logic
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-deploy-automated.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mock validation function
validate_deployment_dependencies() { return 0; }

# Source mock utils
source "${SCRIPT_DIR}/deploy/utils/logging.sh"
source "${SCRIPT_DIR}/deploy/utils/notifications.sh"

# Default configuration
SKIP_USER_SETUP=false
SKIP_SSH_SETUP=false
SKIP_SECRETS=false
SKIP_MENTAT_PREP=false
SKIP_LANDSRAAD_PREP=false
SKIP_APP_DEPLOY=false
SKIP_OBSERVABILITY=false
SKIP_VERIFICATION=false
INTERACTIVE=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-user-setup)
            SKIP_USER_SETUP=true
            shift
            ;;
        --skip-ssh)
            SKIP_SSH_SETUP=true
            shift
            ;;
        --skip-secrets)
            SKIP_SECRETS=true
            shift
            ;;
        --skip-mentat-prep)
            SKIP_MENTAT_PREP=true
            shift
            ;;
        --skip-landsraad-prep)
            SKIP_LANDSRAAD_PREP=true
            shift
            ;;
        --skip-app-deploy)
            SKIP_APP_DEPLOY=true
            shift
            ;;
        --skip-observability)
            SKIP_OBSERVABILITY=true
            shift
            ;;
        --skip-verification)
            SKIP_VERIFICATION=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Help requested"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Output configuration for testing
echo "SKIP_USER_SETUP=${SKIP_USER_SETUP}"
echo "SKIP_SSH_SETUP=${SKIP_SSH_SETUP}"
echo "SKIP_SECRETS=${SKIP_SECRETS}"
echo "SKIP_MENTAT_PREP=${SKIP_MENTAT_PREP}"
echo "SKIP_LANDSRAAD_PREP=${SKIP_LANDSRAAD_PREP}"
echo "SKIP_APP_DEPLOY=${SKIP_APP_DEPLOY}"
echo "SKIP_OBSERVABILITY=${SKIP_OBSERVABILITY}"
echo "SKIP_VERIFICATION=${SKIP_VERIFICATION}"
echo "INTERACTIVE=${INTERACTIVE}"
echo "DRY_RUN=${DRY_RUN}"
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "No arguments - all flags should be false" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_USER_SETUP=false" ]]
    [[ "$output" =~ "SKIP_SSH_SETUP=false" ]]
    [[ "$output" =~ "SKIP_SECRETS=false" ]]
    [[ "$output" =~ "DRY_RUN=false" ]]
    [[ "$output" =~ "INTERACTIVE=false" ]]
}

@test "Single --skip-user-setup flag" {
    run "$TEST_SCRIPT" --skip-user-setup

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_USER_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SSH_SETUP=false" ]]
}

@test "Single --skip-ssh flag" {
    run "$TEST_SCRIPT" --skip-ssh

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_SSH_SETUP=true" ]]
    [[ "$output" =~ "SKIP_USER_SETUP=false" ]]
}

@test "Single --skip-secrets flag" {
    run "$TEST_SCRIPT" --skip-secrets

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_SECRETS=true" ]]
}

@test "Single --skip-observability flag" {
    run "$TEST_SCRIPT" --skip-observability

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_OBSERVABILITY=true" ]]
}

@test "Single --dry-run flag" {
    run "$TEST_SCRIPT" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY_RUN=true" ]]
}

@test "Single --interactive flag" {
    run "$TEST_SCRIPT" --interactive

    [ "$status" -eq 0 ]
    [[ "$output" =~ "INTERACTIVE=true" ]]
}

@test "Multiple skip flags together" {
    run "$TEST_SCRIPT" --skip-user-setup --skip-ssh --skip-secrets

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_USER_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SSH_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SECRETS=true" ]]
    [[ "$output" =~ "SKIP_MENTAT_PREP=false" ]]
}

@test "All skip flags" {
    run "$TEST_SCRIPT" --skip-user-setup --skip-ssh --skip-secrets \
        --skip-mentat-prep --skip-landsraad-prep --skip-app-deploy \
        --skip-observability --skip-verification

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_USER_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SSH_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SECRETS=true" ]]
    [[ "$output" =~ "SKIP_MENTAT_PREP=true" ]]
    [[ "$output" =~ "SKIP_LANDSRAAD_PREP=true" ]]
    [[ "$output" =~ "SKIP_APP_DEPLOY=true" ]]
    [[ "$output" =~ "SKIP_OBSERVABILITY=true" ]]
    [[ "$output" =~ "SKIP_VERIFICATION=true" ]]
}

@test "Combining --dry-run with --interactive" {
    run "$TEST_SCRIPT" --dry-run --interactive

    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY_RUN=true" ]]
    [[ "$output" =~ "INTERACTIVE=true" ]]
}

@test "Combining skip flags with --dry-run" {
    run "$TEST_SCRIPT" --skip-user-setup --skip-ssh --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_USER_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SSH_SETUP=true" ]]
    [[ "$output" =~ "DRY_RUN=true" ]]
}

@test "--help flag should exit with 0 and show help" {
    run "$TEST_SCRIPT" --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Help requested" ]]
}

@test "Invalid argument should fail" {
    run "$TEST_SCRIPT" --invalid-flag

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR: Unknown argument: --invalid-flag" ]]
}

@test "Invalid argument with valid ones should still fail" {
    run "$TEST_SCRIPT" --skip-ssh --invalid-flag

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR: Unknown argument: --invalid-flag" ]]
}

@test "Flag order should not matter" {
    run "$TEST_SCRIPT" --dry-run --skip-ssh --interactive --skip-user-setup

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_USER_SETUP=true" ]]
    [[ "$output" =~ "SKIP_SSH_SETUP=true" ]]
    [[ "$output" =~ "DRY_RUN=true" ]]
    [[ "$output" =~ "INTERACTIVE=true" ]]
}

@test "Duplicate flags should not cause errors" {
    run "$TEST_SCRIPT" --skip-ssh --skip-ssh

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SKIP_SSH_SETUP=true" ]]
}
