#!/usr/bin/env bats
# Test error handling and rollback mechanisms

load test-helper

setup() {
    setup_test_env
    create_mock_utils

    # Create test script with error handling
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-error-handling.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXECUTION_LOG="${SCRIPT_DIR}/execution.log"
ROLLBACK_LOG="${SCRIPT_DIR}/rollback.log"

# Mock validation
validate_deployment_dependencies() { return 0; }

# Source mock utils
source "${SCRIPT_DIR}/deploy/utils/logging.sh"
source "${SCRIPT_DIR}/deploy/utils/notifications.sh"

# Configuration - passed via environment
PHASE_TO_FAIL="${PHASE_TO_FAIL:-}"
FAIL_WITH_CODE="${FAIL_WITH_CODE:-1}"

# Initialize
init_deployment_log "test-deploy"

# Rollback function
rollback_deployment() {
    local phase="$1"
    local error_code="$2"

    echo "ROLLBACK triggered at phase: $phase (exit code: $error_code)" >> "$ROLLBACK_LOG"

    # Specific rollback actions based on phase
    case "$phase" in
        "user_setup")
            echo "Rollback: Remove created users" >> "$ROLLBACK_LOG"
            ;;
        "ssh_setup")
            echo "Rollback: Remove SSH keys" >> "$ROLLBACK_LOG"
            ;;
        "secrets")
            echo "Rollback: Remove generated secrets" >> "$ROLLBACK_LOG"
            ;;
        "mentat_prep")
            echo "Rollback: Cleanup mentat changes" >> "$ROLLBACK_LOG"
            ;;
        "landsraad_prep")
            echo "Rollback: Cleanup landsraad changes" >> "$ROLLBACK_LOG"
            ;;
        "app_deploy")
            echo "Rollback: Restore previous application version" >> "$ROLLBACK_LOG"
            ;;
        "observability")
            echo "Rollback: Stop observability services" >> "$ROLLBACK_LOG"
            ;;
    esac

    echo "ROLLBACK completed" >> "$ROLLBACK_LOG"
}

# Error handler
deployment_error_handler() {
    local exit_code=$?
    local phase="${CURRENT_PHASE:-unknown}"

    echo "ERROR: Deployment failed in phase: $phase (exit code: $exit_code)" >> "$EXECUTION_LOG"

    # Trigger rollback
    rollback_deployment "$phase" "$exit_code"

    # Notify failure
    notify_deployment_failure "test-env" "Failed at phase: $phase"

    exit "$exit_code"
}

trap deployment_error_handler ERR

# Phase implementations
phase_user_setup() {
    export CURRENT_PHASE="user_setup"
    echo "Phase 1: User Setup" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "user_setup" ]]; then
        echo "Simulating failure in user_setup" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

phase_ssh_setup() {
    export CURRENT_PHASE="ssh_setup"
    echo "Phase 2: SSH Setup" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "ssh_setup" ]]; then
        echo "Simulating failure in ssh_setup" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

phase_secrets_generation() {
    export CURRENT_PHASE="secrets"
    echo "Phase 3: Secrets Generation" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "secrets" ]]; then
        echo "Simulating failure in secrets" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

phase_prepare_mentat() {
    export CURRENT_PHASE="mentat_prep"
    echo "Phase 4: Prepare Mentat" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "mentat_prep" ]]; then
        echo "Simulating failure in mentat_prep" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

phase_prepare_landsraad() {
    export CURRENT_PHASE="landsraad_prep"
    echo "Phase 5: Prepare Landsraad" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "landsraad_prep" ]]; then
        echo "Simulating failure in landsraad_prep" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

phase_deploy_application() {
    export CURRENT_PHASE="app_deploy"
    echo "Phase 6: Deploy Application" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "app_deploy" ]]; then
        echo "Simulating failure in app_deploy" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

phase_deploy_observability() {
    export CURRENT_PHASE="observability"
    echo "Phase 7: Deploy Observability" >> "$EXECUTION_LOG"

    if [[ "$PHASE_TO_FAIL" == "observability" ]]; then
        echo "Simulating failure in observability" >> "$EXECUTION_LOG"
        exit "$FAIL_WITH_CODE"
    fi
}

# Execute phases
phase_user_setup
phase_ssh_setup
phase_secrets_generation
phase_prepare_mentat
phase_prepare_landsraad
phase_deploy_application
phase_deploy_observability

echo "SUCCESS: All phases completed" >> "$EXECUTION_LOG"

# Output logs
echo "=== EXECUTION LOG ==="
cat "$EXECUTION_LOG"

if [[ -f "$ROLLBACK_LOG" ]]; then
    echo "=== ROLLBACK LOG ==="
    cat "$ROLLBACK_LOG"
fi
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "Successful deployment - no rollback" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "SUCCESS: All phases completed" ]]
    [[ ! "$output" =~ "ROLLBACK" ]]
}

@test "Failure in phase 1 triggers rollback" {
    PHASE_TO_FAIL="user_setup" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR: Deployment failed in phase: user_setup" ]]
    [[ "$output" =~ "ROLLBACK triggered at phase: user_setup" ]]
    [[ "$output" =~ "Rollback: Remove created users" ]]
}

@test "Failure in phase 2 triggers rollback" {
    PHASE_TO_FAIL="ssh_setup" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 1: User Setup" ]]
    [[ "$output" =~ "ERROR: Deployment failed in phase: ssh_setup" ]]
    [[ "$output" =~ "ROLLBACK triggered at phase: ssh_setup" ]]
    [[ "$output" =~ "Rollback: Remove SSH keys" ]]
}

@test "Failure in secrets phase triggers rollback" {
    PHASE_TO_FAIL="secrets" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 1: User Setup" ]]
    [[ "$output" =~ "Phase 2: SSH Setup" ]]
    [[ "$output" =~ "ERROR: Deployment failed in phase: secrets" ]]
    [[ "$output" =~ "Rollback: Remove generated secrets" ]]
}

@test "Failure in mentat prep triggers rollback" {
    PHASE_TO_FAIL="mentat_prep" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 3: Secrets Generation" ]]
    [[ "$output" =~ "ERROR: Deployment failed in phase: mentat_prep" ]]
    [[ "$output" =~ "Rollback: Cleanup mentat changes" ]]
}

@test "Failure in landsraad prep triggers rollback" {
    PHASE_TO_FAIL="landsraad_prep" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
    [[ "$output" =~ "ERROR: Deployment failed in phase: landsraad_prep" ]]
    [[ "$output" =~ "Rollback: Cleanup landsraad changes" ]]
}

@test "Failure in app deploy triggers rollback" {
    PHASE_TO_FAIL="app_deploy" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 5: Prepare Landsraad" ]]
    [[ "$output" =~ "ERROR: Deployment failed in phase: app_deploy" ]]
    [[ "$output" =~ "Rollback: Restore previous application version" ]]
}

@test "Failure in observability triggers rollback" {
    PHASE_TO_FAIL="observability" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 6: Deploy Application" ]]
    [[ "$output" =~ "ERROR: Deployment failed in phase: observability" ]]
    [[ "$output" =~ "Rollback: Stop observability services" ]]
}

@test "Failure sends notification" {
    PHASE_TO_FAIL="app_deploy" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Deployment failed: Failed at phase: app_deploy" ]]
}

@test "Different exit codes are preserved" {
    PHASE_TO_FAIL="app_deploy" FAIL_WITH_CODE="42" run "$TEST_SCRIPT"

    [ "$status" -eq 42 ]
    [[ "$output" =~ "exit code: 42" ]]
}

@test "Phases before failure are executed" {
    PHASE_TO_FAIL="landsraad_prep" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 1: User Setup" ]]
    [[ "$output" =~ "Phase 2: SSH Setup" ]]
    [[ "$output" =~ "Phase 3: Secrets Generation" ]]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
}

@test "Phases after failure are not executed" {
    PHASE_TO_FAIL="mentat_prep" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
    [[ ! "$output" =~ "Phase 5: Prepare Landsraad" ]]
    [[ ! "$output" =~ "Phase 6: Deploy Application" ]]
}

@test "Rollback completes even on failure" {
    PHASE_TO_FAIL="app_deploy" run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ROLLBACK triggered" ]]
    [[ "$output" =~ "ROLLBACK completed" ]]
}
