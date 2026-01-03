#!/usr/bin/env bats
# Test dependency validation logic

load test-helper

setup() {
    setup_test_env
    create_mock_utils

    # Create test script with dependency validation
    TEST_SCRIPT="${TEST_TEMP_DIR}/test-dependency-validation.sh"

    cat > "$TEST_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dependency validation function (copied from deploy-chom-automated.sh)
validate_deployment_dependencies() {
    local script_dir="$1"
    local script_name="$(basename "$0")"
    local deploy_root="$script_dir"
    local errors=()

    # Validate deploy root structure
    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    # Validate utils directory
    local utils_dir="${deploy_root}/deploy/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        # Validate required utility files
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/notifications.sh"
            "${utils_dir}/idempotence.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
    fi

    # Validate scripts directory
    local scripts_dir="${deploy_root}/deploy/scripts"
    if [[ ! -d "$scripts_dir" ]]; then
        errors+=("Scripts directory not found: $scripts_dir")
    fi

    # If errors found, print and exit
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo ""
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "Utils directory: ${utils_dir}" >&2
        echo ""
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo ""
        exit 1
    fi

    echo "VALIDATION_PASSED"
}

# Run validation
validate_deployment_dependencies "$SCRIPT_DIR"
SCRIPT_EOF

    chmod +x "$TEST_SCRIPT"
}

teardown() {
    teardown_test_env
}

@test "Validation passes with all dependencies present" {
    # Create full directory structure
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    # Create all required utility files
    touch "${TEST_TEMP_DIR}/deploy/utils/logging.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/colors.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/notifications.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/idempotence.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/dependency-validation.sh"

    chmod 644 "${TEST_TEMP_DIR}/deploy/utils/"*.sh

    run "$TEST_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "VALIDATION_PASSED" ]]
}

@test "Validation fails when utils directory missing" {
    # Create only deploy root, no utils
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Utils directory not found" ]]
}

@test "Validation fails when scripts directory missing" {
    # Create utils but no scripts
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    touch "${TEST_TEMP_DIR}/deploy/utils/logging.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/colors.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/notifications.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/idempotence.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/dependency-validation.sh"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Scripts directory not found" ]]
}

@test "Validation fails when logging.sh missing" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    # Create all except logging.sh
    touch "${TEST_TEMP_DIR}/deploy/utils/colors.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/notifications.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/idempotence.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/dependency-validation.sh"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Required utility file not found" ]]
    [[ "$output" =~ "logging.sh" ]]
}

@test "Validation fails when colors.sh missing" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    touch "${TEST_TEMP_DIR}/deploy/utils/logging.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/notifications.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/idempotence.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/dependency-validation.sh"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "colors.sh" ]]
}

@test "Validation fails when notifications.sh missing" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    touch "${TEST_TEMP_DIR}/deploy/utils/logging.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/colors.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/idempotence.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/dependency-validation.sh"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "notifications.sh" ]]
}

@test "Validation fails when multiple files missing" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    # Create only logging.sh
    touch "${TEST_TEMP_DIR}/deploy/utils/logging.sh"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "colors.sh" ]]
    [[ "$output" =~ "notifications.sh" ]]
    [[ "$output" =~ "idempotence.sh" ]]
}

@test "Validation fails when file not readable" {
    mkdir -p "${TEST_TEMP_DIR}/deploy/utils"
    mkdir -p "${TEST_TEMP_DIR}/deploy/scripts"

    # Create all files
    touch "${TEST_TEMP_DIR}/deploy/utils/logging.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/colors.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/notifications.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/idempotence.sh"
    touch "${TEST_TEMP_DIR}/deploy/utils/dependency-validation.sh"

    # Make logging.sh unreadable
    chmod 000 "${TEST_TEMP_DIR}/deploy/utils/logging.sh"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Required utility file not readable" ]]
    [[ "$output" =~ "logging.sh" ]]
}

@test "Validation error message includes troubleshooting steps" {
    # Create empty deploy directory
    mkdir -p "${TEST_TEMP_DIR}/deploy"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR: Missing required dependencies" ]]
    [[ "$output" =~ "Script location:" ]]
    [[ "$output" =~ "Deploy root:" ]]
}

@test "Validation shows all missing dependencies at once" {
    # Create only deploy root - everything else missing
    mkdir -p "${TEST_TEMP_DIR}/deploy"

    run "$TEST_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Utils directory not found" ]]
    [[ "$output" =~ "Scripts directory not found" ]]
}
