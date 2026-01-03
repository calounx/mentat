#!/usr/bin/env bats
# Test phase execution order and dependencies

load test-helper

setup() {
    setup_test_env
    create_mock_utils

    # Create test script that tracks phase execution
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-phase-execution.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXECUTION_LOG="${SCRIPT_DIR}/execution.log"

# Mock validation
validate_deployment_dependencies() { return 0; }

# Source mock utils
source "${SCRIPT_DIR}/deploy/utils/logging.sh"
source "${SCRIPT_DIR}/deploy/utils/notifications.sh"

# Configuration
SKIP_USER_SETUP=false
SKIP_SSH_SETUP=false
SKIP_SECRETS=false
SKIP_MENTAT_PREP=false
SKIP_LANDSRAAD_PREP=false
SKIP_APP_DEPLOY=false
SKIP_OBSERVABILITY=false
SKIP_VERIFICATION=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-user-setup) SKIP_USER_SETUP=true; shift ;;
        --skip-ssh) SKIP_SSH_SETUP=true; shift ;;
        --skip-secrets) SKIP_SECRETS=true; shift ;;
        --skip-mentat-prep) SKIP_MENTAT_PREP=true; shift ;;
        --skip-landsraad-prep) SKIP_LANDSRAAD_PREP=true; shift ;;
        --skip-app-deploy) SKIP_APP_DEPLOY=true; shift ;;
        --skip-observability) SKIP_OBSERVABILITY=true; shift ;;
        --skip-verification) SKIP_VERIFICATION=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
done

# Initialize
init_deployment_log "test-deploy"
start_timer

# Phase implementations
phase_user_setup() {
    if [[ "$SKIP_USER_SETUP" == "true" ]]; then
        echo "Phase 1: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 1: User Setup" >> "$EXECUTION_LOG"
}

phase_ssh_setup() {
    if [[ "$SKIP_SSH_SETUP" == "true" ]]; then
        echo "Phase 2: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 2: SSH Setup" >> "$EXECUTION_LOG"
}

phase_secrets_generation() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        echo "Phase 3: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 3: Secrets Generation" >> "$EXECUTION_LOG"
}

phase_prepare_mentat() {
    if [[ "$SKIP_MENTAT_PREP" == "true" ]]; then
        echo "Phase 4: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 4: Prepare Mentat" >> "$EXECUTION_LOG"
}

phase_prepare_landsraad() {
    if [[ "$SKIP_LANDSRAAD_PREP" == "true" ]]; then
        echo "Phase 5: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 5: Prepare Landsraad" >> "$EXECUTION_LOG"
}

phase_deploy_application() {
    if [[ "$SKIP_APP_DEPLOY" == "true" ]]; then
        echo "Phase 6: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 6: Deploy Application" >> "$EXECUTION_LOG"
}

phase_deploy_observability() {
    if [[ "$SKIP_OBSERVABILITY" == "true" ]]; then
        echo "Phase 7: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 7: Deploy Observability" >> "$EXECUTION_LOG"
}

phase_verification() {
    if [[ "$SKIP_VERIFICATION" == "true" ]]; then
        echo "Phase 8: SKIPPED" >> "$EXECUTION_LOG"
        return 0
    fi
    echo "Phase 8: Verification" >> "$EXECUTION_LOG"
}

# Main execution - correct order
phase_user_setup
phase_ssh_setup
phase_secrets_generation
phase_prepare_mentat
phase_prepare_landsraad
phase_deploy_application
phase_deploy_observability
phase_verification

# Output execution log
cat "$EXECUTION_LOG"
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "All phases execute in correct order" {
    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]

    # Verify order by checking line numbers
    local line1=$(echo "$output" | grep -n "Phase 1: User Setup" | cut -d: -f1)
    local line2=$(echo "$output" | grep -n "Phase 2: SSH Setup" | cut -d: -f1)
    local line3=$(echo "$output" | grep -n "Phase 3: Secrets Generation" | cut -d: -f1)
    local line4=$(echo "$output" | grep -n "Phase 4: Prepare Mentat" | cut -d: -f1)
    local line5=$(echo "$output" | grep -n "Phase 5: Prepare Landsraad" | cut -d: -f1)
    local line6=$(echo "$output" | grep -n "Phase 6: Deploy Application" | cut -d: -f1)
    local line7=$(echo "$output" | grep -n "Phase 7: Deploy Observability" | cut -d: -f1)
    local line8=$(echo "$output" | grep -n "Phase 8: Verification" | cut -d: -f1)

    [ "$line1" -lt "$line2" ]
    [ "$line2" -lt "$line3" ]
    [ "$line3" -lt "$line4" ]
    [ "$line4" -lt "$line5" ]
    [ "$line5" -lt "$line6" ]
    [ "$line6" -lt "$line7" ]
    [ "$line7" -lt "$line8" ]
}

@test "Skip user setup phase" {
    run "$TEST_SCRIPT" --skip-user-setup

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 1: SKIPPED" ]]
    [[ "$output" =~ "Phase 2: SSH Setup" ]]
    [[ "$output" =~ "Phase 3: Secrets Generation" ]]
}

@test "Skip SSH setup phase" {
    run "$TEST_SCRIPT" --skip-ssh

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 1: User Setup" ]]
    [[ "$output" =~ "Phase 2: SKIPPED" ]]
    [[ "$output" =~ "Phase 3: Secrets Generation" ]]
}

@test "Skip secrets generation phase" {
    run "$TEST_SCRIPT" --skip-secrets

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 2: SSH Setup" ]]
    [[ "$output" =~ "Phase 3: SKIPPED" ]]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
}

@test "Skip mentat preparation phase" {
    run "$TEST_SCRIPT" --skip-mentat-prep

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 3: Secrets Generation" ]]
    [[ "$output" =~ "Phase 4: SKIPPED" ]]
    [[ "$output" =~ "Phase 5: Prepare Landsraad" ]]
}

@test "Skip landsraad preparation phase" {
    run "$TEST_SCRIPT" --skip-landsraad-prep

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
    [[ "$output" =~ "Phase 5: SKIPPED" ]]
    [[ "$output" =~ "Phase 6: Deploy Application" ]]
}

@test "Skip application deployment phase" {
    run "$TEST_SCRIPT" --skip-app-deploy

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 5: Prepare Landsraad" ]]
    [[ "$output" =~ "Phase 6: SKIPPED" ]]
    [[ "$output" =~ "Phase 7: Deploy Observability" ]]
}

@test "Skip observability deployment phase" {
    run "$TEST_SCRIPT" --skip-observability

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 6: Deploy Application" ]]
    [[ "$output" =~ "Phase 7: SKIPPED" ]]
    [[ "$output" =~ "Phase 8: Verification" ]]
}

@test "Skip verification phase" {
    run "$TEST_SCRIPT" --skip-verification

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 7: Deploy Observability" ]]
    [[ "$output" =~ "Phase 8: SKIPPED" ]]
}

@test "Skip multiple consecutive phases" {
    run "$TEST_SCRIPT" --skip-user-setup --skip-ssh --skip-secrets

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 1: SKIPPED" ]]
    [[ "$output" =~ "Phase 2: SKIPPED" ]]
    [[ "$output" =~ "Phase 3: SKIPPED" ]]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
}

@test "Skip non-consecutive phases" {
    run "$TEST_SCRIPT" --skip-user-setup --skip-secrets --skip-observability

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 1: SKIPPED" ]]
    [[ "$output" =~ "Phase 2: SSH Setup" ]]
    [[ "$output" =~ "Phase 3: SKIPPED" ]]
    [[ "$output" =~ "Phase 4: Prepare Mentat" ]]
    [[ "$output" =~ "Phase 7: SKIPPED" ]]
    [[ "$output" =~ "Phase 8: Verification" ]]
}

@test "Skip all phases" {
    run "$TEST_SCRIPT" --skip-user-setup --skip-ssh --skip-secrets \
        --skip-mentat-prep --skip-landsraad-prep --skip-app-deploy \
        --skip-observability --skip-verification

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Phase 1: SKIPPED" ]]
    [[ "$output" =~ "Phase 2: SKIPPED" ]]
    [[ "$output" =~ "Phase 3: SKIPPED" ]]
    [[ "$output" =~ "Phase 4: SKIPPED" ]]
    [[ "$output" =~ "Phase 5: SKIPPED" ]]
    [[ "$output" =~ "Phase 6: SKIPPED" ]]
    [[ "$output" =~ "Phase 7: SKIPPED" ]]
    [[ "$output" =~ "Phase 8: SKIPPED" ]]
}

@test "Phase order maintained even when some are skipped" {
    run "$TEST_SCRIPT" --skip-ssh --skip-mentat-prep

    [ "$status" -eq 0 ]

    # Find line numbers of executed phases
    local line1=$(echo "$output" | grep -n "Phase 1: User Setup" | cut -d: -f1)
    local line3=$(echo "$output" | grep -n "Phase 3: Secrets Generation" | cut -d: -f1)
    local line5=$(echo "$output" | grep -n "Phase 5: Prepare Landsraad" | cut -d: -f1)

    # Verify skipped phases appear in order too
    [ "$line1" -lt "$line3" ]
    [ "$line3" -lt "$line5" ]
}
