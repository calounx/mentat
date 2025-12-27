#!/usr/bin/env bats
#===============================================================================
# Unit Tests for deploy/lib/common.sh
#
# Tests cover:
#   - Placeholder detection
#   - Configuration validation
#   - Version resolution
#   - Idempotency helpers
#   - Download functions
#===============================================================================

# Test setup
setup() {
    # Source the library under test
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    STACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    DEPLOY_LIB="$STACK_DIR/deploy/lib/common.sh"

    # Create temp directory for test files
    TEST_TEMP_DIR=$(mktemp -d)

    # Source the library (mock log functions first)
    log_info() { :; }
    log_warn() { :; }
    log_error() { :; }
    log_step() { :; }
    log_success() { :; }

    export -f log_info log_warn log_error log_step log_success
    export STACK_DIR TEST_TEMP_DIR

    source "$DEPLOY_LIB"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#===============================================================================
# Placeholder Detection Tests
#===============================================================================

@test "is_placeholder: detects CHANGE_ME" {
    run is_placeholder "CHANGE_ME_IMMEDIATELY"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: detects YOUR_ prefix" {
    run is_placeholder "YOUR_BREVO_SMTP_KEY"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: detects EXAMPLE" {
    run is_placeholder "EXAMPLE_PASSWORD"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: detects PLACEHOLDER" {
    run is_placeholder "PLACEHOLDER_VALUE"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: detects REPLACE_" {
    run is_placeholder "REPLACE_WITH_REAL_VALUE"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: detects TODO" {
    run is_placeholder "TODO_SET_THIS"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: detects _IP suffix" {
    run is_placeholder "MONITORED_HOST_1_IP"
    [ "$status" -eq 0 ]
}

@test "is_placeholder: accepts real IP address" {
    run is_placeholder "192.168.1.100"
    [ "$status" -eq 1 ]
}

@test "is_placeholder: accepts real password" {
    run is_placeholder "xK9#mP2@vL5nQ8wR"
    [ "$status" -eq 1 ]
}

@test "is_placeholder: accepts real domain" {
    run is_placeholder "grafana.example.com"
    [ "$status" -eq 1 ]
}

@test "is_placeholder: empty value is not a placeholder" {
    run is_placeholder ""
    [ "$status" -eq 1 ]
}

#===============================================================================
# Configuration Validation Tests
#===============================================================================

@test "validate_config_no_placeholders: passes for valid config" {
    cat > "$TEST_TEMP_DIR/valid-config.yaml" << 'EOF'
network:
  observability_vps_ip: "192.168.1.100"
smtp:
  password: "real_smtp_password_123"
grafana:
  admin_password: "SecureP@ssw0rd!"
security:
  prometheus_basic_auth_password: "prom_secret_456"
  loki_basic_auth_password: "loki_secret_789"
EOF

    run validate_config_no_placeholders "$TEST_TEMP_DIR/valid-config.yaml"
    [ "$status" -eq 0 ]
}

@test "validate_config_no_placeholders: fails for placeholder IP" {
    cat > "$TEST_TEMP_DIR/bad-config.yaml" << 'EOF'
network:
  observability_vps_ip: "YOUR_OBSERVABILITY_VPS_IP"
smtp:
  password: "real_password"
grafana:
  admin_password: "real_password"
security:
  prometheus_basic_auth_password: "real_password"
  loki_basic_auth_password: "real_password"
EOF

    run validate_config_no_placeholders "$TEST_TEMP_DIR/bad-config.yaml"
    [ "$status" -eq 1 ]
}

@test "validate_config_no_placeholders: fails for CHANGE_ME password" {
    cat > "$TEST_TEMP_DIR/bad-config.yaml" << 'EOF'
network:
  observability_vps_ip: "192.168.1.100"
smtp:
  password: "real_password"
grafana:
  admin_password: "CHANGE_ME_IMMEDIATELY"
security:
  prometheus_basic_auth_password: "real_password"
  loki_basic_auth_password: "real_password"
EOF

    run validate_config_no_placeholders "$TEST_TEMP_DIR/bad-config.yaml"
    [ "$status" -eq 1 ]
}

@test "validate_config_no_placeholders: handles missing config file" {
    run validate_config_no_placeholders "/nonexistent/config.yaml"
    [ "$status" -eq 0 ]  # Should skip validation gracefully
}

#===============================================================================
# Version Resolution Tests
#===============================================================================

@test "get_component_version: returns environment override" {
    export VERSION_OVERRIDE_PROMETHEUS="2.99.0"
    run get_component_version "prometheus" "2.48.1"
    [ "$output" = "2.99.0" ]
    unset VERSION_OVERRIDE_PROMETHEUS
}

@test "get_component_version: returns fallback when no config" {
    # Temporarily unset STACK_DIR to force fallback
    local old_stack_dir="$STACK_DIR"
    STACK_DIR="/nonexistent"
    run get_component_version "prometheus" "2.48.1"
    [ "$output" = "2.48.1" ]
    STACK_DIR="$old_stack_dir"
}

@test "get_component_version: reads from versions.yaml" {
    mkdir -p "$TEST_TEMP_DIR/config"
    cat > "$TEST_TEMP_DIR/config/versions.yaml" << 'EOF'
components:
  node_exporter:
    fallback_version: "1.7.0"
  prometheus:
    fallback_version: "2.55.1"
EOF
    STACK_DIR="$TEST_TEMP_DIR"
    run get_component_version "node_exporter" "1.0.0"
    [ "$output" = "1.7.0" ]
}

#===============================================================================
# Idempotency Helper Tests
#===============================================================================

@test "user_exists: returns true for root" {
    run user_exists "root"
    [ "$status" -eq 0 ]
}

@test "user_exists: returns false for nonexistent user" {
    run user_exists "nonexistent_user_12345"
    [ "$status" -eq 1 ]
}

@test "binary_installed: returns false for nonexistent binary" {
    run binary_installed "/nonexistent/binary"
    [ "$status" -eq 1 ]
}

@test "binary_installed: returns true for existing binary" {
    run binary_installed "/bin/bash"
    [ "$status" -eq 0 ]
}

#===============================================================================
# Checksum Verification Tests
#===============================================================================

@test "verify_checksum: passes for correct SHA256" {
    echo "test content" > "$TEST_TEMP_DIR/testfile.txt"
    local expected_hash
    expected_hash=$(sha256sum "$TEST_TEMP_DIR/testfile.txt" | awk '{print $1}')

    run verify_checksum "$TEST_TEMP_DIR/testfile.txt" "$expected_hash" "sha256"
    [ "$status" -eq 0 ]
}

@test "verify_checksum: fails for incorrect checksum" {
    echo "test content" > "$TEST_TEMP_DIR/testfile.txt"

    run verify_checksum "$TEST_TEMP_DIR/testfile.txt" "invalid_checksum_here" "sha256"
    [ "$status" -eq 1 ]
}

@test "verify_checksum: fails for nonexistent file" {
    run verify_checksum "/nonexistent/file.txt" "somechecksum" "sha256"
    [ "$status" -eq 1 ]
}

@test "verify_checksum: fails for unsupported algorithm" {
    echo "test" > "$TEST_TEMP_DIR/testfile.txt"
    run verify_checksum "$TEST_TEMP_DIR/testfile.txt" "checksum" "invalid_algo"
    [ "$status" -eq 1 ]
}

#===============================================================================
# Download Function Tests
#===============================================================================

@test "download_file: rejects non-HTTPS URLs" {
    run download_file "http://example.com/file" "$TEST_TEMP_DIR/file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Only HTTPS URLs are allowed"* ]]
}

@test "download_file: accepts localhost HTTP" {
    # This will fail to connect but should pass the URL validation
    run download_file "http://localhost:8080/file" "$TEST_TEMP_DIR/file" 1
    # Status 1 is expected (connection refused), but not from URL rejection
    [[ "$output" != *"Only HTTPS URLs are allowed"* ]]
}

@test "download_file: accepts 127.x.x.x HTTP" {
    run download_file "http://127.0.0.1:8080/file" "$TEST_TEMP_DIR/file" 1
    [[ "$output" != *"Only HTTPS URLs are allowed"* ]]
}

#===============================================================================
# Service Helper Tests
#===============================================================================

@test "service_exists: returns true for known service" {
    # Skip if systemd not available
    if ! command -v systemctl &>/dev/null; then
        skip "systemctl not available"
    fi

    # Most systems have ssh or sshd
    if systemctl list-unit-files ssh.service &>/dev/null; then
        run service_exists "ssh"
        [ "$status" -eq 0 ]
    elif systemctl list-unit-files sshd.service &>/dev/null; then
        run service_exists "sshd"
        [ "$status" -eq 0 ]
    else
        skip "No common service found for testing"
    fi
}

@test "service_exists: returns false for nonexistent service" {
    if ! command -v systemctl &>/dev/null; then
        skip "systemctl not available"
    fi

    run service_exists "nonexistent_service_12345"
    [ "$status" -eq 1 ]
}

#===============================================================================
# Directory Helper Tests
#===============================================================================

@test "ensure_directory: creates new directory" {
    local test_dir="$TEST_TEMP_DIR/new_directory"

    ensure_directory "$test_dir" "$(id -un):$(id -gn)" 755

    [ -d "$test_dir" ]
}

@test "ensure_directory: handles existing directory" {
    local test_dir="$TEST_TEMP_DIR/existing_directory"
    mkdir -p "$test_dir"

    run ensure_directory "$test_dir" "$(id -un):$(id -gn)" 755
    [ "$status" -eq 0 ]
    [ -d "$test_dir" ]
}
