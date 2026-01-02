#!/usr/bin/env bats
#===============================================================================
# Unit Tests for common.sh Library Functions
# Tests all utility functions in the common library
#===============================================================================

# Setup test environment
setup() {
    # Load the library under test
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    # Create temporary test directory
    TEST_TMP="$BATS_TEST_TMPDIR/common_tests_$$"
    mkdir -p "$TEST_TMP"

    # Set log directory to temp location (before sourcing common.sh)
    # This prevents permission errors when logging
    export LOG_BASE_DIR="$TEST_TMP"

    # Source the common library
    source "$LIB_DIR/common.sh"

    # Note: Color variables (RED, GREEN, etc.) are readonly from common.sh
    # Tests run with colors enabled - output is captured by BATS anyway
}

# Cleanup after each test
teardown() {
    if [[ -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

#===============================================================================
# PATH UTILITIES TESTS
#===============================================================================

@test "get_stack_root returns absolute path" {
    result=$(get_stack_root)

    # Should return an absolute path
    [[ "$result" == /* ]]

    # Should contain 'observability-stack'
    [[ "$result" == *"observability-stack"* ]]
}

@test "get_modules_dir returns correct path" {
    result=$(get_modules_dir)

    # Should end with /modules
    [[ "$result" == *"/modules" ]]

    # Directory should exist
    [[ -d "$result" ]]
}

@test "get_config_dir returns correct path" {
    result=$(get_config_dir)

    # Should end with /config
    [[ "$result" == *"/config" ]]
}

@test "get_hosts_config_dir returns correct path" {
    result=$(get_hosts_config_dir)

    # Should end with /config/hosts
    [[ "$result" == *"/config/hosts" ]]
}

#===============================================================================
# YAML PARSING TESTS
#===============================================================================

@test "yaml_get extracts simple key-value pairs" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
name: test_module
version: 1.0.0
port: 9100
EOF

    result=$(yaml_get "$TEST_TMP/test.yaml" "name")
    [[ "$result" == "test_module" ]]

    result=$(yaml_get "$TEST_TMP/test.yaml" "version")
    [[ "$result" == "1.0.0" ]]

    result=$(yaml_get "$TEST_TMP/test.yaml" "port")
    [[ "$result" == "9100" ]]
}

@test "yaml_get handles quoted values" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
single: 'quoted value'
double: "quoted value"
mixed: "value with 'quotes'"
EOF

    result=$(yaml_get "$TEST_TMP/test.yaml" "single")
    [[ "$result" == "quoted value" ]]

    result=$(yaml_get "$TEST_TMP/test.yaml" "double")
    [[ "$result" == "quoted value" ]]
}

@test "yaml_get handles comments" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
key: value # This is a comment
port: 9100 # Port number
EOF

    result=$(yaml_get "$TEST_TMP/test.yaml" "key")
    [[ "$result" == "value" ]]

    result=$(yaml_get "$TEST_TMP/test.yaml" "port")
    [[ "$result" == "9100" ]]
}

@test "yaml_get returns empty for missing key" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
existing: value
EOF

    result=$(yaml_get "$TEST_TMP/test.yaml" "missing")
    [[ -z "$result" ]]
}

@test "yaml_get fails for missing file" {
    run yaml_get "$TEST_TMP/nonexistent.yaml" "key"
    [[ $status -ne 0 ]]
}

@test "yaml_get_nested extracts nested values" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
module:
  name: test_module
  version: 1.0.0
  description: Test module for testing
exporter:
  port: 9100
  protocol: http
EOF

    result=$(yaml_get_nested "$TEST_TMP/test.yaml" "module" "name")
    [[ "$result" == "test_module" ]]

    result=$(yaml_get_nested "$TEST_TMP/test.yaml" "module" "version")
    [[ "$result" == "1.0.0" ]]

    result=$(yaml_get_nested "$TEST_TMP/test.yaml" "exporter" "port")
    [[ "$result" == "9100" ]]
}

@test "yaml_get_deep extracts three-level nested values" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
level1:
  level2:
    level3: deep_value
    other: other_value
  sibling: sibling_value
EOF

    result=$(yaml_get_deep "$TEST_TMP/test.yaml" "level1" "level2" "level3")
    [[ "$result" == "deep_value" ]]

    result=$(yaml_get_deep "$TEST_TMP/test.yaml" "level1" "level2" "other")
    [[ "$result" == "other_value" ]]
}

@test "yaml_get_array extracts array items" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
commands:
  - systemctl status nginx
  - which nginx
  - test -f /etc/nginx/nginx.conf
files:
  - /etc/nginx
  - /var/log/nginx
EOF

    result=$(yaml_get_array "$TEST_TMP/test.yaml" "commands")

    # Should have 3 lines
    line_count=$(echo "$result" | wc -l)
    [[ $line_count -eq 3 ]]

    # Check content
    echo "$result" | grep -q "systemctl status nginx"
    echo "$result" | grep -q "which nginx"
    echo "$result" | grep -q "test -f /etc/nginx/nginx.conf"
}

@test "yaml_get_array handles empty arrays" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
dependencies:
EOF

    result=$(yaml_get_array "$TEST_TMP/test.yaml" "dependencies")
    [[ -z "$result" ]]
}

@test "yaml_has_key detects existing keys" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
name: test
version: 1.0.0
EOF

    yaml_has_key "$TEST_TMP/test.yaml" "name"
    yaml_has_key "$TEST_TMP/test.yaml" "version"
}

@test "yaml_has_key returns false for missing keys" {
    cat > "$TEST_TMP/test.yaml" << 'EOF'
name: test
EOF

    run yaml_has_key "$TEST_TMP/test.yaml" "missing"
    [[ $status -ne 0 ]]
}

#===============================================================================
# VERSION UTILITIES TESTS
#===============================================================================

@test "version_compare handles equal versions" {
    version_compare "1.0.0" "1.0.0"
    [[ $? -eq 0 ]]

    version_compare "2.5.3" "2.5.3"
    [[ $? -eq 0 ]]
}

@test "version_compare detects greater version" {
    run version_compare "2.0.0" "1.0.0"
    [[ $status -eq 1 ]]

    run version_compare "1.5.0" "1.4.0"
    [[ $status -eq 1 ]]

    run version_compare "1.0.10" "1.0.9"
    [[ $status -eq 1 ]]
}

@test "version_compare detects lesser version" {
    run version_compare "1.0.0" "2.0.0"
    [[ $status -eq 2 ]]

    run version_compare "1.4.0" "1.5.0"
    [[ $status -eq 2 ]]

    run version_compare "1.0.9" "1.0.10"
    [[ $status -eq 2 ]]
}

@test "version_compare handles different length versions" {
    version_compare "1.0" "1.0.0"
    [[ $? -eq 0 ]]

    run version_compare "2.0" "1.9.9"
    [[ $status -eq 1 ]]
}

@test "check_binary_version validates correct version" {
    # Create a mock binary that outputs version
    cat > "$TEST_TMP/mockbin" << 'EOF'
#!/bin/bash
echo "mockbin version 1.2.3"
EOF
    chmod +x "$TEST_TMP/mockbin"

    check_binary_version "$TEST_TMP/mockbin" "1.2.3"
    [[ $? -eq 0 ]]
}

@test "check_binary_version fails for wrong version" {
    cat > "$TEST_TMP/mockbin" << 'EOF'
#!/bin/bash
echo "mockbin version 1.2.3"
EOF
    chmod +x "$TEST_TMP/mockbin"

    run check_binary_version "$TEST_TMP/mockbin" "1.2.4"
    [[ $status -ne 0 ]]
}

@test "check_binary_version fails for non-executable" {
    echo "not executable" > "$TEST_TMP/mockbin"

    run check_binary_version "$TEST_TMP/mockbin" "1.0.0"
    [[ $status -ne 0 ]]
}

#===============================================================================
# TEMPLATE UTILITIES TESTS
#===============================================================================

@test "template_render substitutes simple variables" {
    template='Hello ${NAME}, you are ${AGE} years old'

    result=$(template_render "$template" "NAME=John" "AGE=30")
    [[ "$result" == "Hello John, you are 30 years old" ]]
}

@test "template_render handles both brace and non-brace syntax" {
    template='${VAR1} and $VAR2'

    result=$(template_render "$template" "VAR1=first" "VAR2=second")
    [[ "$result" == "first and second" ]]
}

@test "template_render handles multiple occurrences" {
    template='${NAME} ${NAME} ${NAME}'

    result=$(template_render "$template" "NAME=test")
    [[ "$result" == "test test test" ]]
}

@test "template_render_file renders file templates" {
    cat > "$TEST_TMP/template.txt" << 'EOF'
Server: ${SERVER}
Port: ${PORT}
User: ${USER}
EOF

    result=$(template_render_file "$TEST_TMP/template.txt" "SERVER=localhost" "PORT=8080" "USER=admin")

    echo "$result" | grep -q "Server: localhost"
    echo "$result" | grep -q "Port: 8080"
    echo "$result" | grep -q "User: admin"
}

@test "template_render_file fails for missing file" {
    run template_render_file "$TEST_TMP/missing.txt" "VAR=value"
    [[ $status -ne 0 ]]
}

#===============================================================================
# FILE UTILITIES TESTS
#===============================================================================

@test "ensure_dir creates directory" {
    test_dir="$TEST_TMP/new_directory"

    [[ ! -d "$test_dir" ]]

    # Use current user/group for testing (root privileges required for default root:root)
    ensure_dir "$test_dir" "$(id -un)" "$(id -gn)"

    [[ -d "$test_dir" ]]
}

@test "ensure_dir is idempotent" {
    test_dir="$TEST_TMP/existing_directory"
    mkdir -p "$test_dir"

    # Use current user/group for testing
    ensure_dir "$test_dir" "$(id -un)" "$(id -gn)"

    [[ -d "$test_dir" ]]
}

@test "check_config_diff detects no changes" {
    existing="$TEST_TMP/existing.conf"
    echo "existing content" > "$existing"

    FORCE_MODE=false
    run check_config_diff "$existing" "existing content" "test config"
    [[ $status -eq 1 ]]  # Returns 1 when no changes needed
}

@test "check_config_diff detects changes in force mode" {
    existing="$TEST_TMP/existing.conf"
    echo "old content" > "$existing"

    FORCE_MODE=true
    run check_config_diff "$existing" "new content" "test config"
    [[ $status -eq 0 ]]  # Returns 0 when should overwrite
}

@test "check_config_diff creates new file" {
    nonexistent="$TEST_TMP/nonexistent.conf"

    FORCE_MODE=false
    check_config_diff "$nonexistent" "new content" "test config"
    [[ $? -eq 0 ]]  # Returns 0 when file doesn't exist
}

#===============================================================================
# NETWORK UTILITIES TESTS
#===============================================================================

@test "check_port detects open port" {
    skip "Requires network setup"
    # This would require starting a test server
}

@test "check_port detects closed port" {
    # Test connection to non-listening port (should fail quickly)
    run check_port "127.0.0.1" "54321" 1
    [[ $status -ne 0 ]]
}

@test "wait_for_service times out on unavailable service" {
    run wait_for_service "127.0.0.1" "54321" 2 1
    [[ $status -ne 0 ]]
}

#===============================================================================
# PROCESS UTILITIES TESTS
#===============================================================================

@test "check_root detects non-root user" {
    if [[ $EUID -eq 0 ]]; then
        skip "Running as root"
    fi

    run check_root
    [[ $status -ne 0 ]]
}

@test "safe_stop_service handles non-existent service" {
    # Should not error on non-existent service
    safe_stop_service "nonexistent_service_12345"
    [[ $? -eq 0 ]]
}

#===============================================================================
# LOGGING TESTS
#===============================================================================

@test "log_info outputs info message" {
    run log_info "test message"
    [[ "$output" == *"test message"* ]]
}

@test "log_error outputs to stderr" {
    run log_error "error message"
    [[ "$output" == *"error message"* ]]
}

@test "log_debug outputs only when DEBUG=true" {
    DEBUG=false
    run log_debug "debug message"
    [[ -z "$output" ]]

    DEBUG=true
    run log_debug "debug message"
    [[ "$output" == *"debug message"* ]]
}

@test "log_success outputs success message" {
    run log_success "operation succeeded"
    [[ "$output" == *"operation succeeded"* ]]
}

@test "log_warn outputs warning message" {
    run log_warn "warning message"
    [[ "$output" == *"warning message"* ]]
}

#===============================================================================
# EXIT CODES TESTS
#===============================================================================

@test "exit codes are defined" {
    [[ $E_SUCCESS -eq 0 ]]
    [[ $E_GENERAL -eq 1 ]]
    [[ $E_MODULE_NOT_FOUND -eq 2 ]]
    [[ $E_VALIDATION_FAILED -eq 3 ]]
    [[ $E_INSTALL_FAILED -eq 4 ]]
    [[ $E_PERMISSION_DENIED -eq 5 ]]
    [[ $E_CONFIG_ERROR -eq 6 ]]
    [[ $E_NETWORK_ERROR -eq 7 ]]
}

#===============================================================================
# PATH CONSTANTS TESTS
#===============================================================================

@test "path constants are defined" {
    [[ -n "$INSTALL_BIN_DIR" ]]
    [[ -n "$CONFIG_BASE_DIR" ]]
    [[ -n "$DATA_BASE_DIR" ]]
    [[ -n "$LOG_BASE_DIR" ]]
    [[ -n "$SYSTEMD_DIR" ]]
}

@test "path constants have sensible defaults" {
    [[ "$INSTALL_BIN_DIR" == "/usr/local/bin" ]]
    [[ "$CONFIG_BASE_DIR" == "/etc" ]]
    [[ "$DATA_BASE_DIR" == "/var/lib" ]]
    # LOG_BASE_DIR is overridden in setup() to TEST_TMP
    [[ "$LOG_BASE_DIR" == "$TEST_TMP" ]]
    [[ "$SYSTEMD_DIR" == "/etc/systemd/system" ]]
}
