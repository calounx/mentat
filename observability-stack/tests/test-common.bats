#!/usr/bin/env bats
#===============================================================================
# Unit Tests for common.sh
# Tests all utility functions in scripts/lib/common.sh
#===============================================================================

# Load test helpers
load helpers

# Setup and teardown
setup() {
    setup_test_environment
    # Source the common library
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
}

teardown() {
    cleanup_test_environment
}

#===============================================================================
# YAML PARSING TESTS
#===============================================================================

@test "yaml_get: retrieves simple key-value pair" {
    create_test_config "test.yaml" "hostname: test-server"

    result=$(yaml_get "${TEST_TEMP_DIR}/config/test.yaml" "hostname")
    [[ "$result" == "test-server" ]]
}

@test "yaml_get: returns empty for non-existent key" {
    create_test_config "test.yaml" "hostname: test-server"

    result=$(yaml_get "${TEST_TEMP_DIR}/config/test.yaml" "nonexistent")
    [[ -z "$result" ]]
}

@test "yaml_get: handles quoted values" {
    create_test_config "test.yaml" 'password: "my-secret-123"'

    result=$(yaml_get "${TEST_TEMP_DIR}/config/test.yaml" "password")
    [[ "$result" == "my-secret-123" ]]
}

@test "yaml_get: strips inline comments" {
    create_test_config "test.yaml" "hostname: test-server # this is a comment"

    result=$(yaml_get "${TEST_TEMP_DIR}/config/test.yaml" "hostname")
    [[ "$result" == "test-server" ]]
}

@test "yaml_get: handles values with spaces" {
    create_test_config "test.yaml" "description: This is a test server"

    result=$(yaml_get "${TEST_TEMP_DIR}/config/test.yaml" "description")
    [[ "$result" == "This is a test server" ]]
}

@test "yaml_get: returns error for non-existent file" {
    run yaml_get "/nonexistent/file.yaml" "key"
    [[ $status -ne 0 ]]
}

@test "yaml_get_nested: retrieves nested values" {
    create_test_config "test.yaml" "$(cat <<EOF
server:
  hostname: test-server
  ip: 192.168.1.100
EOF
)"

    result=$(yaml_get_nested "${TEST_TEMP_DIR}/config/test.yaml" "server" "hostname")
    [[ "$result" == "test-server" ]]
}

@test "yaml_get_nested: retrieves nested IP address" {
    create_test_config "test.yaml" "$(cat <<EOF
server:
  hostname: test-server
  ip: 192.168.1.100
EOF
)"

    result=$(yaml_get_nested "${TEST_TEMP_DIR}/config/test.yaml" "server" "ip")
    [[ "$result" == "192.168.1.100" ]]
}

@test "yaml_get_deep: retrieves deeply nested values" {
    create_test_config "test.yaml" "$(cat <<EOF
prometheus:
  scrape_configs:
    interval: 15s
EOF
)"

    result=$(yaml_get_deep "${TEST_TEMP_DIR}/config/test.yaml" "prometheus" "scrape_configs" "interval")
    [[ "$result" == "15s" ]]
}

@test "yaml_get_array: retrieves array items" {
    create_test_config "test.yaml" "$(cat <<EOF
modules:
  - node_exporter
  - promtail
  - nginx_exporter
EOF
)"

    result=$(yaml_get_array "${TEST_TEMP_DIR}/config/test.yaml" "modules")
    [[ "$result" == *"node_exporter"* ]]
    [[ "$result" == *"promtail"* ]]
    [[ "$result" == *"nginx_exporter"* ]]
}

@test "yaml_has_key: returns true for existing key" {
    create_test_config "test.yaml" "hostname: test-server"

    run yaml_has_key "${TEST_TEMP_DIR}/config/test.yaml" "hostname"
    [[ $status -eq 0 ]]
}

@test "yaml_has_key: returns false for non-existent key" {
    create_test_config "test.yaml" "hostname: test-server"

    run yaml_has_key "${TEST_TEMP_DIR}/config/test.yaml" "nonexistent"
    [[ $status -ne 0 ]]
}

#===============================================================================
# VERSION COMPARISON TESTS
#===============================================================================

@test "version_compare: equal versions return 0" {
    run version_compare "1.2.3" "1.2.3"
    [[ $status -eq 0 ]]
}

@test "version_compare: first version greater returns 1" {
    run version_compare "2.0.0" "1.9.9"
    [[ $status -eq 1 ]]
}

@test "version_compare: first version lesser returns 2" {
    run version_compare "1.0.0" "2.0.0"
    [[ $status -eq 2 ]]
}

@test "version_compare: compares minor versions correctly" {
    run version_compare "1.10.0" "1.9.0"
    [[ $status -eq 1 ]]
}

@test "version_compare: compares patch versions correctly" {
    run version_compare "1.0.5" "1.0.10"
    [[ $status -eq 2 ]]
}

@test "version_compare: handles different length versions" {
    run version_compare "1.0" "1.0.0"
    [[ $status -eq 0 ]]
}

@test "check_binary_version: validates correct version" {
    # Create a mock binary
    cat > "${TEST_TEMP_DIR}/test-binary" <<EOF
#!/bin/bash
echo "version 1.2.3"
EOF
    chmod +x "${TEST_TEMP_DIR}/test-binary"

    run check_binary_version "${TEST_TEMP_DIR}/test-binary" "1.2.3"
    [[ $status -eq 0 ]]
}

@test "check_binary_version: rejects wrong version" {
    # Create a mock binary
    cat > "${TEST_TEMP_DIR}/test-binary" <<EOF
#!/bin/bash
echo "version 1.2.3"
EOF
    chmod +x "${TEST_TEMP_DIR}/test-binary"

    run check_binary_version "${TEST_TEMP_DIR}/test-binary" "1.2.4"
    [[ $status -ne 0 ]]
}

@test "check_binary_version: fails for non-existent binary" {
    run check_binary_version "/nonexistent/binary" "1.0.0"
    [[ $status -ne 0 ]]
}

#===============================================================================
# PATH UTILITIES TESTS
#===============================================================================

@test "get_stack_root: returns valid path" {
    result=$(get_stack_root)
    [[ -n "$result" ]]
    [[ -d "$result" ]]
}

@test "get_modules_dir: returns modules path" {
    result=$(get_modules_dir)
    [[ "$result" == *"/modules" ]]
}

@test "get_config_dir: returns config path" {
    result=$(get_config_dir)
    [[ "$result" == *"/config" ]]
}

@test "get_hosts_config_dir: returns hosts config path" {
    result=$(get_hosts_config_dir)
    [[ "$result" == *"/config/hosts" ]]
}

#===============================================================================
# FILE UTILITIES TESTS
#===============================================================================

@test "ensure_dir: creates directory if not exists" {
    local test_dir="${TEST_TEMP_DIR}/new-directory"

    ensure_dir "$test_dir"

    [[ -d "$test_dir" ]]
}

@test "ensure_dir: sets correct permissions" {
    skip_if_not_root

    local test_dir="${TEST_TEMP_DIR}/new-directory"

    ensure_dir "$test_dir" "root" "root" "0755"

    perms=$(stat -c '%a' "$test_dir" 2>/dev/null || stat -f '%A' "$test_dir")
    [[ "$perms" == "755" ]]
}

@test "ensure_dir: does not fail if directory exists" {
    local test_dir="${TEST_TEMP_DIR}/existing-directory"
    mkdir -p "$test_dir"

    run ensure_dir "$test_dir"
    [[ $status -eq 0 ]]
}

@test "check_config_diff: returns 0 for non-existent file" {
    export FORCE_MODE="true"

    run check_config_diff "/nonexistent/file.conf" "new content" "test config"
    [[ $status -eq 0 ]]
}

@test "check_config_diff: returns 1 for identical content" {
    local test_file="${TEST_TEMP_DIR}/test.conf"
    echo "test content" > "$test_file"

    run check_config_diff "$test_file" "test content" "test config"
    [[ $status -eq 1 ]]
}

@test "check_config_diff: returns 0 in force mode for different content" {
    export FORCE_MODE="true"
    local test_file="${TEST_TEMP_DIR}/test.conf"
    echo "old content" > "$test_file"

    run check_config_diff "$test_file" "new content" "test config"
    [[ $status -eq 0 ]]
}

#===============================================================================
# NETWORK UTILITIES TESTS
#===============================================================================

@test "check_port: succeeds for open port" {
    skip "Requires network setup"
}

@test "check_port: fails for closed port" {
    # Try to connect to a port that should be closed
    run check_port "127.0.0.1" "65534" "1"
    [[ $status -ne 0 ]]
}

@test "wait_for_service: times out for unavailable service" {
    # Should timeout quickly for closed port
    run wait_for_service "127.0.0.1" "65534" "2" "1"
    [[ $status -ne 0 ]]
}

#===============================================================================
# TEMPLATE UTILITIES TESTS
#===============================================================================

@test "template_render: substitutes single variable" {
    result=$(template_render "Hello \${NAME}" "NAME=World")
    [[ "$result" == "Hello World" ]]
}

@test "template_render: substitutes multiple variables" {
    result=$(template_render "Hello \${NAME}, age \${AGE}" "NAME=Alice" "AGE=30")
    [[ "$result" == "Hello Alice, age 30" ]]
}

@test "template_render: handles dollar-prefix variables" {
    result=$(template_render "Hello \$NAME" "NAME=Bob")
    [[ "$result" == "Hello Bob" ]]
}

@test "template_render: leaves unmatched variables unchanged" {
    result=$(template_render "Hello \${NAME} and \${OTHER}" "NAME=Alice")
    [[ "$result" == "Hello Alice and \${OTHER}" ]]
}

@test "template_render_file: renders template from file" {
    local template="${TEST_TEMP_DIR}/template.txt"
    echo "Server: \${HOSTNAME}" > "$template"

    result=$(template_render_file "$template" "HOSTNAME=test-server")
    [[ "$result" == "Server: test-server" ]]
}

@test "template_render_file: fails for non-existent template" {
    run template_render_file "/nonexistent/template.txt" "VAR=value"
    [[ $status -ne 0 ]]
}

#===============================================================================
# LOGGING FUNCTIONS TESTS
#===============================================================================

@test "log_info: outputs with INFO prefix" {
    run log_info "test message"
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"test message"* ]]
}

@test "log_success: outputs with SUCCESS prefix" {
    run log_success "operation completed"
    [[ "$output" == *"[SUCCESS]"* ]]
    [[ "$output" == *"operation completed"* ]]
}

@test "log_warn: outputs with WARN prefix" {
    run log_warn "warning message"
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"warning message"* ]]
}

@test "log_error: outputs to stderr" {
    run log_error "error occurred"
    [[ "$output" == *"[ERROR]"* ]]
    [[ "$output" == *"error occurred"* ]]
}

@test "log_debug: outputs only when DEBUG is true" {
    export DEBUG="false"
    run log_debug "debug message"
    [[ -z "$output" ]]

    export DEBUG="true"
    run log_debug "debug message"
    [[ "$output" == *"[DEBUG]"* ]]
}

@test "log_fatal: exits with error code" {
    run log_fatal "fatal error"
    [[ $status -eq 1 ]]
    [[ "$output" == *"[FATAL]"* ]]
}

#===============================================================================
# PROCESS UTILITIES TESTS
#===============================================================================

@test "check_root: succeeds when running as root" {
    skip_if_not_root
    run check_root
    [[ $status -eq 0 ]]
}

@test "check_root: fails when not running as root" {
    if [[ $EUID -eq 0 ]]; then
        skip "Running as root"
    fi

    run check_root
    [[ $status -eq 1 ]]
}

@test "safe_stop_service: handles non-existent service gracefully" {
    skip_if_not_root
    run safe_stop_service "nonexistent-service-xyz"
    # Should not fail even if service doesn't exist
    [[ $status -eq 0 ]]
}
