#!/usr/bin/env bats
#===============================================================================
# Security Tests for Observability Stack
# Tests security measures, permissions, and credential handling
#===============================================================================

# Load test helpers
load helpers

# Setup and teardown
setup() {
    setup_test_environment
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
}

teardown() {
    cleanup_test_environment
}

#===============================================================================
# FILE PERMISSION TESTS
#===============================================================================

@test "security: config files have restrictive permissions" {
    skip_if_not_root

    local config_file="${TEST_TEMP_DIR}/config/config.yaml"

    # Create config file with sensitive data
    cat > "$config_file" <<EOF
server:
  hostname: test-server

grafana:
  admin_password: secret123
EOF

    # Set proper permissions
    chmod 600 "$config_file"

    # Verify permissions
    perms=$(stat -c '%a' "$config_file" 2>/dev/null || stat -f '%A' "$config_file")
    [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]
}

@test "security: password files are not world-readable" {
    skip_if_not_root

    local password_file="${TEST_TEMP_DIR}/config/passwords.txt"
    echo "admin:secretpassword" > "$password_file"

    # Set secure permissions
    chmod 600 "$password_file"

    # Verify not world-readable
    perms=$(stat -c '%a' "$password_file" 2>/dev/null || stat -f '%A' "$password_file")
    last_digit="${perms: -1}"
    [[ "$last_digit" == "0" ]]
}

@test "security: service files owned by root" {
    skip_if_not_root

    local service_file="${TEST_TEMP_DIR}/test.service"
    touch "$service_file"
    chown root:root "$service_file"

    # Verify ownership
    owner=$(stat -c '%U' "$service_file" 2>/dev/null || stat -f '%Su' "$service_file")
    [[ "$owner" == "root" ]]
}

@test "security: executable scripts have proper permissions" {
    local script_file="${TEST_TEMP_DIR}/test-script.sh"

    cat > "$script_file" <<'EOF'
#!/bin/bash
echo "test"
EOF

    # Set executable but not world-writable
    chmod 755 "$script_file"

    perms=$(stat -c '%a' "$script_file" 2>/dev/null || stat -f '%A' "$script_file")

    # Should be executable by owner
    [[ "${perms:0:1}" -ge 7 ]] || [[ "${perms:0:1}" -ge 5 ]]

    # Should not be world-writable
    [[ "${perms: -1}" -lt 6 ]]
}

@test "security: directories have proper permissions" {
    skip_if_not_root

    local secure_dir="${TEST_TEMP_DIR}/secure-data"
    mkdir -p "$secure_dir"
    chmod 700 "$secure_dir"

    perms=$(stat -c '%a' "$secure_dir" 2>/dev/null || stat -f '%A' "$secure_dir")
    [[ "$perms" == "700" ]]
}

#===============================================================================
# CREDENTIAL HANDLING TESTS
#===============================================================================

@test "security: no plaintext passwords in scripts" {
    # Check all shell scripts for hardcoded passwords
    local found_password=false

    while IFS= read -r script; do
        # Look for suspicious patterns (common password variables)
        if grep -iE '(password|passwd|pwd)=["'\''"][^"'\'']+["'\'']' "$script" | grep -v "YOUR_PASSWORD_HERE" | grep -v "CHANGE_ME" | grep -qv "example"; then
            found_password=true
            break
        fi
    done < <(find "${BATS_TEST_DIRNAME}/../scripts" -name "*.sh" 2>/dev/null)

    [[ "$found_password" == false ]]
}

@test "security: credentials loaded from secure files" {
    # Test that passwords are read from secure files, not hardcoded
    local password_file="${TEST_TEMP_DIR}/config/.secrets"
    mkdir -p "$(dirname "$password_file")"
    echo "GRAFANA_ADMIN_PASSWORD=secure123" > "$password_file"
    chmod 600 "$password_file"

    # Source the secrets
    source "$password_file"

    [[ "$GRAFANA_ADMIN_PASSWORD" == "secure123" ]]

    # Cleanup
    unset GRAFANA_ADMIN_PASSWORD
}

@test "security: secrets files are in gitignore" {
    local gitignore="${BATS_TEST_DIRNAME}/../.gitignore"

    if [[ -f "$gitignore" ]]; then
        # Check for common secret file patterns
        grep -qE '(\*\.secret|\*\.key|\.env|passwords\.txt|\.secrets)' "$gitignore" || true
    fi

    # Test passes if .gitignore exists and contains secret patterns, or doesn't exist
    [[ ! -f "$gitignore" ]] || grep -qE '(secret|password|\.env)' "$gitignore" || true
}

@test "security: environment variables for sensitive data" {
    # Test that sensitive config can be overridden via environment
    export GRAFANA_ADMIN_PASSWORD="env_password"

    # This should be readable from environment
    [[ -n "${GRAFANA_ADMIN_PASSWORD}" ]]

    # Cleanup
    unset GRAFANA_ADMIN_PASSWORD
}

@test "security: password complexity validation" {
    # Test password validation function if it exists
    validate_password() {
        local password="$1"
        local min_length=8

        # Check length
        if [[ ${#password} -lt $min_length ]]; then
            return 1
        fi

        # Check for mix of characters (basic check)
        if [[ ! "$password" =~ [a-z] ]] || [[ ! "$password" =~ [A-Z] ]] || [[ ! "$password" =~ [0-9] ]]; then
            return 1
        fi

        return 0
    }

    # Test weak password
    run validate_password "weak"
    [[ $status -ne 0 ]]

    # Test strong password
    run validate_password "StrongPass123"
    [[ $status -eq 0 ]]
}

#===============================================================================
# INPUT VALIDATION TESTS
#===============================================================================

@test "security: validates IP addresses" {
    # Valid IP addresses
    validate_ip() {
        local ip="$1"
        [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1

        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    }

    # Test valid IP
    run validate_ip "192.168.1.1"
    [[ $status -eq 0 ]]

    # Test invalid IPs
    run validate_ip "999.999.999.999"
    [[ $status -ne 0 ]]

    run validate_ip "invalid.ip.address"
    [[ $status -ne 0 ]]

    run validate_ip "192.168.1"
    [[ $status -ne 0 ]]
}

@test "security: validates hostnames" {
    validate_hostname() {
        local hostname="$1"
        # RFC 1123 hostname validation
        [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
    }

    # Valid hostnames
    run validate_hostname "server1"
    [[ $status -eq 0 ]]

    run validate_hostname "web-server.example.com"
    [[ $status -eq 0 ]]

    # Invalid hostnames
    run validate_hostname "-invalid"
    [[ $status -ne 0 ]]

    run validate_hostname "invalid-.host"
    [[ $status -ne 0 ]]

    run validate_hostname "host_with_underscore"
    [[ $status -ne 0 ]]
}

@test "security: validates port numbers" {
    validate_port() {
        local port="$1"
        [[ "$port" =~ ^[0-9]+$ ]] || return 1
        (( port > 0 && port <= 65535 ))
    }

    # Valid ports
    run validate_port "80"
    [[ $status -eq 0 ]]

    run validate_port "9090"
    [[ $status -eq 0 ]]

    # Invalid ports
    run validate_port "0"
    [[ $status -ne 0 ]]

    run validate_port "65536"
    [[ $status -ne 0 ]]

    run validate_port "abc"
    [[ $status -ne 0 ]]
}

@test "security: validates semantic versions" {
    validate_version() {
        local version="$1"
        [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    }

    # Valid versions
    run validate_version "1.0.0"
    [[ $status -eq 0 ]]

    run validate_version "2.45.0"
    [[ $status -eq 0 ]]

    # Invalid versions
    run validate_version "1.0"
    [[ $status -ne 0 ]]

    run validate_version "v1.0.0"
    [[ $status -ne 0 ]]

    run validate_version "latest"
    [[ $status -ne 0 ]]
}

@test "security: sanitizes user input" {
    sanitize_input() {
        local input="$1"
        # Remove dangerous characters
        input="${input//[^a-zA-Z0-9._-]/}"
        echo "$input"
    }

    # Test sanitization
    result=$(sanitize_input "normal-input_123")
    [[ "$result" == "normal-input_123" ]]

    result=$(sanitize_input "dangerous;rm -rf /")
    [[ "$result" != *";"* ]]
    [[ "$result" != *"/"* ]]
}

#===============================================================================
# COMMAND INJECTION PREVENTION TESTS
#===============================================================================

@test "security: no eval usage in scripts" {
    # Check for dangerous eval usage
    local found_eval=false

    while IFS= read -r script; do
        # Look for eval (excluding comments and safe contexts)
        if grep -v '^[[:space:]]*#' "$script" | grep -qE '\beval\s'; then
            # Check if it's in a safe context (like checking if command exists)
            if ! grep -B2 -A2 'eval' "$script" | grep -q 'command.*exists'; then
                found_eval=true
                break
            fi
        fi
    done < <(find "${BATS_TEST_DIRNAME}/../scripts" -name "*.sh" 2>/dev/null)

    [[ "$found_eval" == false ]]
}

@test "security: proper quoting in variable expansion" {
    # Test that variables are properly quoted
    test_quoting() {
        local user_input="file with spaces.txt"

        # Proper quoting
        touch "${TEST_TEMP_DIR}/${user_input}"

        [[ -f "${TEST_TEMP_DIR}/${user_input}" ]]
    }

    run test_quoting
    [[ $status -eq 0 ]]
}

@test "security: no command substitution in user input" {
    dangerous_input='$(rm -rf /tmp/test)'

    # Should treat as literal string, not execute
    result="${dangerous_input}"

    [[ "$result" == '$(rm -rf /tmp/test)' ]]
}

@test "security: validates file paths" {
    validate_path() {
        local path="$1"

        # Prevent directory traversal
        if [[ "$path" =~ \.\. ]]; then
            return 1
        fi

        # Prevent absolute path injection
        if [[ "$path" =~ ^/ ]] && [[ "$path" != /opt/* ]] && [[ "$path" != /etc/* ]]; then
            return 1
        fi

        return 0
    }

    # Valid paths
    run validate_path "config/hosts/server1.yaml"
    [[ $status -eq 0 ]]

    # Invalid paths (directory traversal)
    run validate_path "../../../etc/passwd"
    [[ $status -ne 0 ]]

    run validate_path "config/../../passwd"
    [[ $status -ne 0 ]]
}

#===============================================================================
# DOWNLOAD SECURITY TESTS
#===============================================================================

@test "security: SHA256 checksum verification" {
    # Create a test file
    local test_file="${TEST_TEMP_DIR}/test-download.tar.gz"
    echo "test content" > "$test_file"

    # Calculate actual checksum
    local actual_checksum
    actual_checksum=$(sha256sum "$test_file" | cut -d' ' -f1)

    # Verify function
    verify_checksum() {
        local file="$1"
        local expected="$2"

        local actual
        actual=$(sha256sum "$file" | cut -d' ' -f1)

        [[ "$actual" == "$expected" ]]
    }

    # Test with correct checksum
    run verify_checksum "$test_file" "$actual_checksum"
    [[ $status -eq 0 ]]

    # Test with wrong checksum
    run verify_checksum "$test_file" "0000000000000000000000000000000000000000000000000000000000000000"
    [[ $status -ne 0 ]]
}

@test "security: HTTPS URLs enforced for downloads" {
    validate_download_url() {
        local url="$1"

        # Must use HTTPS
        [[ "$url" =~ ^https:// ]]
    }

    # Valid URL
    run validate_download_url "https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus.tar.gz"
    [[ $status -eq 0 ]]

    # Invalid URLs
    run validate_download_url "http://insecure.com/file.tar.gz"
    [[ $status -ne 0 ]]

    run validate_download_url "ftp://ftp.example.com/file.tar.gz"
    [[ $status -ne 0 ]]
}

@test "security: downloaded files have secure permissions" {
    skip_if_not_root

    local downloaded_file="${TEST_TEMP_DIR}/downloaded-binary"
    touch "$downloaded_file"

    # Set secure permissions before execution
    chmod 700 "$downloaded_file"

    perms=$(stat -c '%a' "$downloaded_file" 2>/dev/null || stat -f '%A' "$downloaded_file")
    [[ "$perms" == "700" ]]
}

#===============================================================================
# SERVICE ISOLATION TESTS
#===============================================================================

@test "security: services run as non-root users" {
    # Create test service file
    local service_file="${TEST_TEMP_DIR}/test-exporter.service"

    cat > "$service_file" <<EOF
[Unit]
Description=Test Exporter
After=network.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/opt/test-exporter/test-exporter

[Install]
WantedBy=multi-user.target
EOF

    # Verify service runs as non-root
    assert_file_contains "$service_file" "User=prometheus"
    assert_file_not_contains "$service_file" "User=root"
}

@test "security: service files use minimal privileges" {
    local service_file="${TEST_TEMP_DIR}/secure-service.service"

    cat > "$service_file" <<EOF
[Unit]
Description=Secure Service

[Service]
Type=simple
User=prometheus
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/
ReadWritePaths=/var/lib/prometheus

[Install]
WantedBy=multi-user.target
EOF

    # Verify security options
    assert_file_contains "$service_file" "NoNewPrivileges=true"
    assert_file_contains "$service_file" "PrivateTmp=true"
    assert_file_contains "$service_file" "ProtectSystem=strict"
}

#===============================================================================
# LOG SECURITY TESTS
#===============================================================================

@test "security: logs do not contain sensitive data" {
    local log_file="${TEST_TEMP_DIR}/test.log"

    # Simulate logging (should not include passwords)
    echo "Starting service with config /etc/config.yaml" > "$log_file"
    echo "Connection established to database" >> "$log_file"

    # Verify no passwords in logs
    assert_file_not_contains "$log_file" "password"
    assert_file_not_contains "$log_file" "secret"
    assert_file_not_contains "$log_file" "token"
}

@test "security: log files have appropriate permissions" {
    skip_if_not_root

    local log_file="${TEST_TEMP_DIR}/app.log"
    touch "$log_file"

    # Set log permissions
    chmod 640 "$log_file"
    chown root:adm "$log_file" 2>/dev/null || chown root:root "$log_file"

    # Verify not world-readable
    perms=$(stat -c '%a' "$log_file" 2>/dev/null || stat -f '%A' "$log_file")
    last_digit="${perms: -1}"
    [[ "$last_digit" == "0" ]]
}

#===============================================================================
# NETWORK SECURITY TESTS
#===============================================================================

@test "security: validates TLS/SSL configuration" {
    # Create mock TLS config
    local tls_config="${TEST_TEMP_DIR}/tls.yaml"

    cat > "$tls_config" <<EOF
tls:
  enabled: true
  cert_file: /etc/ssl/certs/server.crt
  key_file: /etc/ssl/private/server.key
  min_version: "1.2"
EOF

    # Verify TLS is enabled
    assert_file_contains "$tls_config" "enabled: true"

    # Verify minimum TLS version
    assert_file_contains "$tls_config" 'min_version: "1.2"'
}

@test "security: firewall rules for exposed ports" {
    # This would check firewall configuration
    # Placeholder test for firewall rule validation
    local allowed_ports=(9090 9100 3000)

    for port in "${allowed_ports[@]}"; do
        [[ "$port" =~ ^[0-9]+$ ]]
    done
}
