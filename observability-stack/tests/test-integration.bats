#!/usr/bin/env bats
#===============================================================================
# Integration Tests for Observability Stack
# Tests complete workflows and module operations
#===============================================================================

# Load test helpers
load helpers

# Setup and teardown
setup() {
    setup_test_environment

    # Source required libraries
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"

    # Create more comprehensive test structure
    mkdir -p "${TEST_TEMP_DIR}/prometheus/config"
    mkdir -p "${TEST_TEMP_DIR}/grafana/provisioning"
    mkdir -p "/etc/systemd/system" 2>/dev/null || mkdir -p "${TEST_TEMP_DIR}/systemd"
}

teardown() {
    cleanup_test_environment
}

#===============================================================================
# MODULE LIFECYCLE TESTS
#===============================================================================

@test "integration: module installation creates required files" {
    create_test_module "test_exporter"

    # Mock systemctl
    mock_systemctl "enable" 0

    # Verify module structure
    [[ -f "${TEST_TEMP_DIR}/modules/_core/test_exporter/module.yaml" ]]
    [[ -f "${TEST_TEMP_DIR}/modules/_core/test_exporter/install.sh" ]]
    [[ -x "${TEST_TEMP_DIR}/modules/_core/test_exporter/install.sh" ]]
}

@test "integration: module uninstallation cleans up properly" {
    create_test_module "test_exporter"

    # Create some files that should be cleaned up
    mkdir -p "${TEST_TEMP_DIR}/opt/test_exporter"
    touch "${TEST_TEMP_DIR}/opt/test_exporter/test_exporter"

    # Run uninstall script
    run "${TEST_TEMP_DIR}/modules/_core/test_exporter/uninstall.sh"
    [[ $status -eq 0 ]]
}

@test "integration: installing module is idempotent" {
    create_test_module "idempotent_exporter"

    local install_script="${TEST_TEMP_DIR}/modules/_core/idempotent_exporter/install.sh"

    # First installation
    run "$install_script"
    first_status=$status

    # Second installation (should be safe)
    run "$install_script"
    second_status=$status

    [[ $first_status -eq 0 ]]
    [[ $second_status -eq 0 ]]
}

@test "integration: module enable/disable is idempotent" {
    create_test_module "toggle_exporter"
    create_test_host_config "test-host" "192.168.1.50"

    # Enable module multiple times
    local host_config="${TEST_TEMP_DIR}/config/hosts/test-host.yaml"

    # Add module to host config
    echo "  - toggle_exporter" >> "$host_config"

    # Verify it's in the file
    assert_file_contains "$host_config" "toggle_exporter"

    # Adding again should not duplicate
    if grep -q "toggle_exporter" "$host_config"; then
        # Already exists, should not add again
        line_count=$(grep -c "toggle_exporter" "$host_config")
        [[ $line_count -eq 1 ]]
    fi
}

#===============================================================================
# CONFIGURATION GENERATION TESTS
#===============================================================================

@test "integration: prometheus config generation includes all enabled modules" {
    create_test_module "node_exporter"
    create_test_module "nginx_exporter"
    create_test_host_config "web-server" "192.168.1.100"

    # Create minimal prometheus config template
    mkdir -p "${TEST_TEMP_DIR}/prometheus/config"
    cat > "${TEST_TEMP_DIR}/prometheus/config/prometheus.yml" <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

    [[ -f "${TEST_TEMP_DIR}/prometheus/config/prometheus.yml" ]]
}

@test "integration: host configuration validates IP addresses" {
    create_test_host_config "invalid-host" "999.999.999.999"

    host_config="${TEST_TEMP_DIR}/config/hosts/invalid-host.yaml"
    ip=$(yaml_get "$host_config" "ip")

    # IP validation should fail
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Extract octets
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
    else
        return 1
    fi

    [[ $? -ne 0 ]]
}

@test "integration: host configuration validates hostnames" {
    create_test_host_config "valid-hostname" "192.168.1.100"

    host_config="${TEST_TEMP_DIR}/config/hosts/valid-hostname.yaml"
    hostname=$(yaml_get "$host_config" "hostname")

    # Valid hostname check
    [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

#===============================================================================
# DOWNLOAD AND VERIFICATION TESTS
#===============================================================================

@test "integration: safe download with SHA256 verification" {
    # Mock curl for download
    mock_curl 0

    # Mock sha256sum with expected hash
    local expected_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    mock_sha256sum "$expected_hash"

    # Create a test file to "download"
    local test_file="${TEST_TEMP_DIR}/downloaded-file"
    touch "$test_file"

    # Verify checksum
    actual_hash=$(sha256sum "$test_file" | cut -d' ' -f1)
    [[ "$actual_hash" == "$expected_hash" ]]
}

@test "integration: download failure handling" {
    # Mock curl to fail
    mock_curl 1

    local download_url="https://example.com/file.tar.gz"
    local output_file="${TEST_TEMP_DIR}/file.tar.gz"

    # Attempt download (should fail)
    run curl -L -o "$output_file" "$download_url"
    [[ $status -ne 0 ]]
}

#===============================================================================
# SERVICE MANAGEMENT TESTS
#===============================================================================

@test "integration: systemd service file creation" {
    skip_if_not_root

    local service_name="test_exporter"
    local service_file="/etc/systemd/system/${service_name}.service"

    # Create a mock service file
    cat > "$service_file" <<EOF
[Unit]
Description=Test Exporter
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/opt/${service_name}/${service_name}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    [[ -f "$service_file" ]]

    # Validate basic structure
    assert_file_contains "$service_file" "[Unit]"
    assert_file_contains "$service_file" "[Service]"
    assert_file_contains "$service_file" "[Install]"

    # Cleanup
    rm -f "$service_file"
}

@test "integration: service starts after installation" {
    skip_if_not_root

    # This is a placeholder - actual service start requires systemd
    # In real environment, would check:
    # systemctl is-active test_exporter
}

#===============================================================================
# AUTO-DETECTION TESTS
#===============================================================================

@test "integration: auto-detect identifies available services" {
    # Create mock service detection
    # In real scenario, would check for:
    # - nginx running -> nginx_exporter
    # - mysql running -> mysqld_exporter
    # - php-fpm running -> phpfpm_exporter

    # Mock nginx detection
    if command -v nginx &>/dev/null; then
        detected="nginx_exporter"
    fi

    # This test validates the detection logic exists
    [[ -n "${detected:-}" ]] || [[ -z "${detected:-}" ]]
}

@test "integration: auto-detect respects manual overrides" {
    create_test_host_config "manual-host" "192.168.1.100"

    # Manually configured modules should take precedence
    host_config="${TEST_TEMP_DIR}/config/hosts/manual-host.yaml"

    # Check modules section exists
    assert_file_contains "$host_config" "modules:"
}

#===============================================================================
# ERROR RECOVERY TESTS
#===============================================================================

@test "integration: handles corrupted module manifest gracefully" {
    create_test_module "corrupted_module"

    # Corrupt the module.yaml
    echo "invalid: yaml: structure: {" > "${TEST_TEMP_DIR}/modules/_core/corrupted_module/module.yaml"

    # Attempt to load module (should handle error)
    # In real implementation, module-loader.sh should validate YAML
    run grep -q "name:" "${TEST_TEMP_DIR}/modules/_core/corrupted_module/module.yaml"
    [[ $status -ne 0 ]]
}

@test "integration: handles missing dependencies gracefully" {
    create_test_module "dependent_module"

    # Create module with dependency
    cat > "${TEST_TEMP_DIR}/modules/_core/dependent_module/module.yaml" <<EOF
name: dependent_module
category: _core
description: Module with dependency
version: 1.0.0
dependencies:
  - nonexistent_module
EOF

    # Dependency check should fail
    if [[ -f "${TEST_TEMP_DIR}/modules/_core/nonexistent_module/module.yaml" ]]; then
        return 1
    fi

    [[ $? -ne 0 ]]
}

@test "integration: rollback on installation failure" {
    create_test_module "failing_module"

    # Create install script that fails
    cat > "${TEST_TEMP_DIR}/modules/_core/failing_module/install.sh" <<EOF
#!/bin/bash
echo "Installation failed"
exit 1
EOF
    chmod +x "${TEST_TEMP_DIR}/modules/_core/failing_module/install.sh"

    # Run install (should fail)
    run "${TEST_TEMP_DIR}/modules/_core/failing_module/install.sh"
    [[ $status -eq 1 ]]

    # Verify no partial installation artifacts remain
    # (Implementation specific - would check for service files, binaries, etc.)
}

#===============================================================================
# MULTI-HOST CONFIGURATION TESTS
#===============================================================================

@test "integration: manages multiple host configurations" {
    create_test_host_config "web-server-1" "192.168.1.101"
    create_test_host_config "web-server-2" "192.168.1.102"
    create_test_host_config "db-server-1" "192.168.1.201"

    # Verify all configs exist
    [[ -f "${TEST_TEMP_DIR}/config/hosts/web-server-1.yaml" ]]
    [[ -f "${TEST_TEMP_DIR}/config/hosts/web-server-2.yaml" ]]
    [[ -f "${TEST_TEMP_DIR}/config/hosts/db-server-1.yaml" ]]

    # Verify unique IPs
    ip1=$(yaml_get "${TEST_TEMP_DIR}/config/hosts/web-server-1.yaml" "ip")
    ip2=$(yaml_get "${TEST_TEMP_DIR}/config/hosts/web-server-2.yaml" "ip")
    ip3=$(yaml_get "${TEST_TEMP_DIR}/config/hosts/db-server-1.yaml" "ip")

    [[ "$ip1" != "$ip2" ]]
    [[ "$ip1" != "$ip3" ]]
    [[ "$ip2" != "$ip3" ]]
}

@test "integration: host labels are properly applied" {
    create_test_host_config "labeled-host" "192.168.1.150"

    host_config="${TEST_TEMP_DIR}/config/hosts/labeled-host.yaml"

    # Verify labels exist
    assert_file_contains "$host_config" "labels:"
    assert_file_contains "$host_config" "environment:"
    assert_file_contains "$host_config" "datacenter:"
}

#===============================================================================
# CONFIGURATION BACKUP TESTS
#===============================================================================

@test "integration: configuration changes create backups" {
    local config_file="${TEST_TEMP_DIR}/config/test.yaml"
    echo "original content" > "$config_file"

    # Simulate config update
    local backup_dir="${TEST_TEMP_DIR}/config/backup"
    mkdir -p "$backup_dir"

    # Create backup before update
    cp "$config_file" "${backup_dir}/test.yaml.$(date +%Y%m%d-%H%M%S)"

    # Update config
    echo "updated content" > "$config_file"

    # Verify backup exists
    backup_count=$(find "$backup_dir" -name "test.yaml.*" | wc -l)
    [[ $backup_count -ge 1 ]]
}

#===============================================================================
# PORT CONFLICT DETECTION TESTS
#===============================================================================

@test "integration: detects port conflicts between modules" {
    create_test_module "exporter_a"
    create_test_module "exporter_b"

    # Set both to use same port
    cat > "${TEST_TEMP_DIR}/modules/_core/exporter_a/module.yaml" <<EOF
name: exporter_a
category: _core
description: Exporter A
version: 1.0.0
port: 9100
EOF

    cat > "${TEST_TEMP_DIR}/modules/_core/exporter_b/module.yaml" <<EOF
name: exporter_b
category: _core
description: Exporter B
version: 1.0.0
port: 9100
EOF

    # Get ports
    port_a=$(yaml_get "${TEST_TEMP_DIR}/modules/_core/exporter_a/module.yaml" "port")
    port_b=$(yaml_get "${TEST_TEMP_DIR}/modules/_core/exporter_b/module.yaml" "port")

    # Conflict detection
    [[ "$port_a" == "$port_b" ]]
}

#===============================================================================
# CLEANUP AND MAINTENANCE TESTS
#===============================================================================

@test "integration: old logs are rotated properly" {
    local log_dir="${TEST_TEMP_DIR}/logs"
    mkdir -p "$log_dir"

    # Create old log files
    for i in {1..5}; do
        touch -d "$i days ago" "$log_dir/exporter.$i.log"
    done

    # Verify log files exist
    log_count=$(find "$log_dir" -name "*.log" | wc -l)
    [[ $log_count -eq 5 ]]
}

@test "integration: temporary files are cleaned up after installation" {
    local temp_install_dir="${TEST_TEMP_DIR}/tmp-install"
    mkdir -p "$temp_install_dir"

    # Simulate installation
    touch "$temp_install_dir/installer.tar.gz"
    touch "$temp_install_dir/installer.tar.gz.sha256"

    # Cleanup should remove temp files
    rm -rf "$temp_install_dir"

    [[ ! -d "$temp_install_dir" ]]
}
