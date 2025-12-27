#!/bin/bash
#===============================================================================
# Test Helper Functions
# Common utilities for BATS testing framework
#===============================================================================

# Test fixture directory
TEST_FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
TEST_TEMP_DIR=""

#===============================================================================
# SETUP/TEARDOWN HELPERS
#===============================================================================

# Setup test environment with isolated directory
setup_test_environment() {
    # Create temporary directory for this test
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Create mock config structure
    mkdir -p "${TEST_TEMP_DIR}/config/hosts"
    mkdir -p "${TEST_TEMP_DIR}/modules/_core"
    mkdir -p "${TEST_TEMP_DIR}/scripts/lib"

    # Copy common.sh to test location for testing
    if [[ -f "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh" ]]; then
        cp "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh" "${TEST_TEMP_DIR}/scripts/lib/"
    fi

    # Set up environment variables
    export STACK_ROOT="${TEST_TEMP_DIR}"
    export DEBUG="false"
    export FORCE_MODE="false"

    # Create minimal test config
    cat > "${TEST_TEMP_DIR}/config/config.yaml" <<EOF
server:
  hostname: test-server
  ip: 192.168.1.100

prometheus:
  version: 2.45.0
  retention_days: 30

grafana:
  admin_password: test_password
EOF
}

# Cleanup test environment
cleanup_test_environment() {
    if [[ -n "${TEST_TEMP_DIR}" && -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    unset TEST_TEMP_DIR
    unset STACK_ROOT
}

#===============================================================================
# MOCK HELPERS
#===============================================================================

# Create a mock systemctl command
mock_systemctl() {
    local action="$1"
    local expected_return="${2:-0}"

    cat > "${TEST_TEMP_DIR}/systemctl" <<EOF
#!/bin/bash
echo "Mock systemctl \$@" >&2
exit $expected_return
EOF
    chmod +x "${TEST_TEMP_DIR}/systemctl"
    export PATH="${TEST_TEMP_DIR}:${PATH}"
}

# Create a mock service
mock_service() {
    local service_name="$1"
    local status="${2:-active}"

    mkdir -p "${TEST_TEMP_DIR}/systemd"
    cat > "${TEST_TEMP_DIR}/systemd/${service_name}.service" <<EOF
[Unit]
Description=Mock ${service_name}

[Service]
Type=simple
ExecStart=/bin/true

[Install]
WantedBy=multi-user.target
EOF

    # Create status file
    echo "${status}" > "${TEST_TEMP_DIR}/systemd/${service_name}.status"
}

# Mock curl command for download testing
mock_curl() {
    local expected_return="${1:-0}"

    cat > "${TEST_TEMP_DIR}/curl" <<EOF
#!/bin/bash
# Mock curl - just create empty file at output location
for arg in "\$@"; do
    if [[ "\$arg" =~ ^-o$ ]]; then
        shift
        touch "\$1"
        exit $expected_return
    fi
done
exit $expected_return
EOF
    chmod +x "${TEST_TEMP_DIR}/curl"
    export PATH="${TEST_TEMP_DIR}:${PATH}"
}

# Mock wget command
mock_wget() {
    local expected_return="${1:-0}"

    cat > "${TEST_TEMP_DIR}/wget" <<EOF
#!/bin/bash
# Mock wget - just create empty file
for arg in "\$@"; do
    if [[ "\$arg" =~ ^-O$ ]]; then
        shift
        touch "\$1"
        exit $expected_return
    fi
done
exit $expected_return
EOF
    chmod +x "${TEST_TEMP_DIR}/wget"
    export PATH="${TEST_TEMP_DIR}:${PATH}"
}

# Mock sha256sum command
mock_sha256sum() {
    local expected_hash="$1"

    cat > "${TEST_TEMP_DIR}/sha256sum" <<EOF
#!/bin/bash
echo "${expected_hash}  \$1"
EOF
    chmod +x "${TEST_TEMP_DIR}/sha256sum"
    export PATH="${TEST_TEMP_DIR}:${PATH}"
}

#===============================================================================
# CONFIG HELPERS
#===============================================================================

# Create a test YAML config file
create_test_config() {
    local filename="$1"
    local content="$2"

    echo "$content" > "${TEST_TEMP_DIR}/config/${filename}"
}

# Create a test module structure
create_test_module() {
    local module_name="$1"
    local category="${2:-_core}"

    local module_dir="${TEST_TEMP_DIR}/modules/${category}/${module_name}"
    mkdir -p "${module_dir}"

    # Create module.yaml
    cat > "${module_dir}/module.yaml" <<EOF
name: ${module_name}
category: ${category}
description: Test module ${module_name}
version: 1.0.0
auto_detect:
  enabled: false
dependencies: []
conflicts: []
EOF

    # Create install.sh
    cat > "${module_dir}/install.sh" <<EOF
#!/bin/bash
echo "Installing ${module_name}"
exit 0
EOF
    chmod +x "${module_dir}/install.sh"

    # Create uninstall.sh
    cat > "${module_dir}/uninstall.sh" <<EOF
#!/bin/bash
echo "Uninstalling ${module_name}"
exit 0
EOF
    chmod +x "${module_dir}/uninstall.sh"

    echo "${module_dir}"
}

# Create a test host config
create_test_host_config() {
    local hostname="$1"
    local ip="${2:-192.168.1.10}"

    cat > "${TEST_TEMP_DIR}/config/hosts/${hostname}.yaml" <<EOF
hostname: ${hostname}
ip: ${ip}
labels:
  environment: test
  datacenter: dc1

modules:
  - node_exporter
  - promtail
EOF
}

#===============================================================================
# ASSERTION HELPERS
#===============================================================================

# Assert file exists
assert_file_exists() {
    local file="$1"
    [[ -f "$file" ]] || return 1
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
}

# Assert file contains string
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    grep -q "$pattern" "$file"
}

# Assert file does not contain string
assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    ! grep -q "$pattern" "$file"
}

# Assert file has correct permissions
assert_file_permissions() {
    local file="$1"
    local expected_perms="$2"

    local actual_perms
    actual_perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%A' "$file")
    [[ "$actual_perms" == "$expected_perms" ]]
}

# Assert service is running
assert_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Assert valid IP address
assert_valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Assert valid hostname
assert_valid_hostname() {
    local hostname="$1"
    [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

#===============================================================================
# UTILITY HELPERS
#===============================================================================

# Skip test if not running as root
skip_if_not_root() {
    if [[ $EUID -ne 0 ]]; then
        skip "This test requires root privileges"
    fi
}

# Skip test if systemd is not available
skip_if_no_systemd() {
    if ! command -v systemctl &> /dev/null; then
        skip "This test requires systemd"
    fi
}

# Skip test if docker is not available
skip_if_no_docker() {
    if ! command -v docker &> /dev/null; then
        skip "This test requires Docker"
    fi
}

# Get the stack root directory
get_test_stack_root() {
    echo "${TEST_TEMP_DIR}"
}

# Source a library file in test context
source_lib() {
    local lib_file="$1"

    # Try multiple possible locations
    local possible_paths=(
        "${BATS_TEST_DIRNAME}/../scripts/lib/${lib_file}"
        "${BATS_TEST_DIRNAME}/../../scripts/lib/${lib_file}"
        "/home/calounx/repositories/mentat/observability-stack/scripts/lib/${lib_file}"
    )

    for lib_path in "${possible_paths[@]}"; do
        if [[ -f "$lib_path" ]]; then
            # shellcheck disable=SC1090
            source "$lib_path" 2>/dev/null && return 0
        fi
    done

    return 1
}

# Run command and capture output
run_and_capture() {
    local cmd="$1"
    output=$(eval "$cmd" 2>&1)
    status=$?
}

#===============================================================================
# VALIDATION HELPERS
#===============================================================================

# Validate YAML syntax (requires yq or python)
validate_yaml_syntax() {
    local file="$1"

    if command -v yq &> /dev/null; then
        yq eval '.' "$file" > /dev/null 2>&1
    elif command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null
    else
        # Basic validation - just check for common syntax errors
        ! grep -qE '^\s*-\s*$|^\s*:\s*$' "$file"
    fi
}

# Validate JSON syntax
validate_json_syntax() {
    local file="$1"

    if command -v jq &> /dev/null; then
        jq empty "$file" 2>/dev/null
    elif command -v python3 &> /dev/null; then
        python3 -c "import json; json.load(open('$file'))" 2>/dev/null
    else
        return 1
    fi
}

# Check for shell script syntax errors
validate_shell_syntax() {
    local file="$1"
    bash -n "$file" 2>/dev/null
}
