#!/usr/bin/env bash
# Test helper functions for BATS tests

# Setup test environment
setup_test_env() {
    export TEST_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/deploy-tests-$$"
    mkdir -p "$TEST_TEMP_DIR"

    # Mock directories
    export MOCK_DEPLOY_ROOT="${TEST_TEMP_DIR}/deploy"
    export MOCK_UTILS_DIR="${MOCK_DEPLOY_ROOT}/utils"
    export MOCK_SCRIPTS_DIR="${MOCK_DEPLOY_ROOT}/scripts"

    mkdir -p "$MOCK_UTILS_DIR"
    mkdir -p "$MOCK_SCRIPTS_DIR"
}

# Teardown test environment
teardown_test_env() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Create mock utility files
create_mock_utils() {
    local utils_dir="${1:-$MOCK_UTILS_DIR}"

    # Create logging.sh
    cat > "${utils_dir}/logging.sh" << 'EOF'
#!/usr/bin/env bash
log_info() { echo "[INFO] $*"; }
log_success() { echo "[SUCCESS] $*"; }
log_warning() { echo "[WARNING] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_fatal() { echo "[FATAL] $*" >&2; exit 1; }
log_section() { echo "=== $* ==="; }
log_step() { echo "  - $*"; }
print_header() { echo ">>> $* <<<"; }
print_section() { echo "### $* ###"; }
init_deployment_log() { export LOG_FILE="/tmp/test-deploy.log"; touch "$LOG_FILE"; }
start_timer() { export TIMER_START=$(date +%s); }
end_timer() { echo "Completed in $(($(date +%s) - TIMER_START))s"; }
EOF
    chmod +x "${utils_dir}/logging.sh"

    # Create colors.sh
    cat > "${utils_dir}/colors.sh" << 'EOF'
#!/usr/bin/env bash
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'
print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
print_step() { echo "  > $*"; }
EOF
    chmod +x "${utils_dir}/colors.sh"

    # Create notifications.sh
    cat > "${utils_dir}/notifications.sh" << 'EOF'
#!/usr/bin/env bash
notify_deployment_started() { echo "Deployment started: $*"; }
notify_deployment_success() { echo "Deployment successful: $*"; }
notify_deployment_failure() { echo "Deployment failed: $*"; }
EOF
    chmod +x "${utils_dir}/notifications.sh"

    # Create idempotence.sh
    cat > "${utils_dir}/idempotence.sh" << 'EOF'
#!/usr/bin/env bash
check_idempotence() { return 0; }
mark_step_completed() { return 0; }
EOF
    chmod +x "${utils_dir}/idempotence.sh"

    # Create dependency-validation.sh
    cat > "${utils_dir}/dependency-validation.sh" << 'EOF'
#!/usr/bin/env bash
validate_dependencies() { return 0; }
check_required_commands() { return 0; }
EOF
    chmod +x "${utils_dir}/dependency-validation.sh"
}

# Create a test deployment script wrapper
create_test_script() {
    local script_path="$1"
    local script_content="$2"

    cat > "$script_path" << EOF
#!/usr/bin/env bash
set -euo pipefail
$script_content
EOF
    chmod +x "$script_path"
}

# Mock ssh command
mock_ssh() {
    local behavior="${1:-success}"

    cat > "${TEST_TEMP_DIR}/ssh" << 'EOF'
#!/usr/bin/env bash
# Mock SSH - logs args and returns success/failure
echo "SSH called with: $*" >> "${TEST_TEMP_DIR}/ssh.log"

if [[ "${SSH_SHOULD_FAIL:-false}" == "true" ]]; then
    echo "SSH connection failed" >&2
    exit 255
fi

# Extract and execute the command if present
if [[ "$*" =~ (.*@.*)[[:space:]]\"?(.*)\"?$ ]]; then
    cmd="${BASH_REMATCH[2]}"
    if [[ -n "$cmd" ]]; then
        eval "$cmd"
    fi
fi

exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/ssh"
    export PATH="${TEST_TEMP_DIR}:${PATH}"
}

# Mock scp command
mock_scp() {
    cat > "${TEST_TEMP_DIR}/scp" << 'EOF'
#!/usr/bin/env bash
# Mock SCP - logs args and copies files
echo "SCP called with: $*" >> "${TEST_TEMP_DIR}/scp.log"

if [[ "${SCP_SHOULD_FAIL:-false}" == "true" ]]; then
    echo "SCP failed" >&2
    exit 1
fi

# Simple mock: just return success
exit 0
EOF
    chmod +x "${TEST_TEMP_DIR}/scp"
    export PATH="${TEST_TEMP_DIR}:${PATH}"
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    if [[ ! -f "$file" ]]; then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
    return 0
}

# Assert directory exists
assert_directory_exists() {
    local dir="$1"
    local message="${2:-Directory should exist: $dir}"

    if [[ ! -d "$dir" ]]; then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
    return 0
}

# Assert string contains
assert_output_contains() {
    local expected="$1"
    local message="${2:-Output should contain: $expected}"

    if [[ ! "$output" =~ $expected ]]; then
        echo "ASSERTION FAILED: $message" >&2
        echo "Expected to find: $expected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
    return 0
}

# Assert exit code
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Exit code should be $expected, got $actual}"

    if [[ "$actual" != "$expected" ]]; then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
    return 0
}
