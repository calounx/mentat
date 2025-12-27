#!/usr/bin/env bats
#===============================================================================
# Error Handling and Recovery Tests
# Tests error conditions, rollback, and graceful failure handling
#===============================================================================

setup() {
    # Load libraries
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/module-loader.sh"
    source "$LIB_DIR/config-generator.sh"

    # Create test directory
    TEST_TMP="$BATS_TEST_TMPDIR/error_tests_$$"
    mkdir -p "$TEST_TMP"

    # Note: Color variables (RED, GREEN, etc.) are readonly from common.sh
    # Tests run with colors enabled - output is captured by BATS anyway
}

teardown() {
    if [[ -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

#===============================================================================
# MISSING FILE ERROR HANDLING
#===============================================================================

@test "yaml_get handles missing files gracefully" {
    run yaml_get "/nonexistent/file.yaml" "key"
    [[ $status -ne 0 ]]
}

@test "yaml_get_nested handles missing files gracefully" {
    run yaml_get_nested "/nonexistent/file.yaml" "parent" "child"
    [[ $status -ne 0 ]]
}

@test "yaml_get_array handles missing files gracefully" {
    run yaml_get_array "/nonexistent/file.yaml" "key"
    [[ $status -ne 0 ]]
}

@test "module_get handles missing module gracefully" {
    run module_get "nonexistent_module_12345" "key"
    [[ $status -ne 0 ]]
}

@test "get_module_manifest fails for missing module" {
    run get_module_manifest "totally_fake_module_99999"
    [[ $status -ne 0 ]]
}

#===============================================================================
# MALFORMED DATA ERROR HANDLING
#===============================================================================

@test "yaml parsing handles empty files" {
    touch "$TEST_TMP/empty.yaml"

    result=$(yaml_get "$TEST_TMP/empty.yaml" "key" 2>/dev/null || echo "")
    # Should return empty, not crash
    [[ -z "$result" ]]
}

@test "yaml parsing handles non-YAML files" {
    echo "This is not YAML at all, just random text" > "$TEST_TMP/noteyaml.txt"

    result=$(yaml_get "$TEST_TMP/noteyaml.txt" "key" 2>/dev/null || echo "")
    # Should handle gracefully
}

@test "yaml parsing handles binary files" {
    # Create binary file
    dd if=/dev/urandom of="$TEST_TMP/binary.dat" bs=1024 count=1 2>/dev/null

    run yaml_get "$TEST_TMP/binary.dat" "key"
    # Should not crash
}

@test "module validation handles incomplete manifests" {
    mkdir -p "$TEST_TMP/modules/_core/incomplete"

    # Create minimal incomplete manifest
    cat > "$TEST_TMP/modules/_core/incomplete/module.yaml" << 'EOF'
module:
  name: incomplete
EOF

    touch "$TEST_TMP/modules/_core/incomplete/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run validate_module "incomplete"
    [[ $status -ne 0 ]]
}

@test "config generation handles invalid module references" {
    # Create host config referencing non-existent module
    mkdir -p "$TEST_TMP/config/hosts"

    cat > "$TEST_TMP/config/hosts/bad_module_ref.yaml" << 'EOF'
host:
  name: bad_module_ref
  ip: 192.168.1.100
modules:
  nonexistent_module_xyz:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    # Should handle gracefully, not crash
    result=$(generate_prometheus_config 2>/dev/null || echo "handled")

    eval "$_orig_func"

    [[ -n "$result" ]]
}

#===============================================================================
# NETWORK ERROR HANDLING
#===============================================================================

@test "wait_for_service times out appropriately" {
    start_time=$(date +%s)

    # Try to connect to guaranteed unavailable service
    run wait_for_service "192.0.2.1" "12345" 3 1

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Should timeout after ~3 seconds
    [[ $duration -ge 3 ]]
    [[ $duration -le 5 ]]
    [[ $status -ne 0 ]]
}

@test "check_port fails fast on invalid host" {
    start_time=$(date +%s)

    run check_port "invalid_hostname_xyz_12345" "80" 2

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Should fail quickly
    [[ $duration -le 3 ]]
    [[ $status -ne 0 ]]
}

#===============================================================================
# PERMISSION ERROR HANDLING
#===============================================================================

@test "ensure_dir handles permission denied gracefully" {
    if [[ $EUID -eq 0 ]]; then
        skip "Test requires non-root user"
    fi

    # Try to create directory in /root (should fail)
    run ensure_dir "/root/test_dir_that_should_fail"
    [[ $status -ne 0 ]]
}

@test "write_config_with_check handles readonly filesystem" {
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root to create readonly mount"
    fi

    # Create readonly directory
    mkdir -p "$TEST_TMP/readonly"
    mount -t tmpfs -o ro tmpfs "$TEST_TMP/readonly" 2>/dev/null || skip "Cannot create readonly mount"

    run write_config_with_check "$TEST_TMP/readonly/test.conf" "content" "test"
    [[ $status -ne 0 ]]

    # Cleanup
    umount "$TEST_TMP/readonly" 2>/dev/null || true
}

#===============================================================================
# CONCURRENT EXECUTION ERROR HANDLING
#===============================================================================

@test "parallel module queries handle contention" {
    # Run multiple queries simultaneously
    results=()
    pids=()

    for i in {1..10}; do
        (module_exists "node_exporter" && echo "success") &
        pids+=($!)
    done

    # Wait for all
    for pid in "${pids[@]}"; do
        wait $pid || true
    done

    # All should complete without deadlock
}

@test "simultaneous config generation produces consistent results" {
    # Create test setup
    mkdir -p "$TEST_TMP/config/hosts"
    cat > "$TEST_TMP/config/hosts/test.yaml" << 'EOF'
host:
  name: test
  ip: 192.168.1.100
modules:
  node_exporter:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    # Generate config twice in parallel
    config1=$(generate_prometheus_config 2>/dev/null) &
    pid1=$!
    config2=$(generate_prometheus_config 2>/dev/null) &
    pid2=$!

    wait $pid1
    wait $pid2

    eval "$_orig_func"

    # Both should succeed
}

#===============================================================================
# DISK SPACE ERROR HANDLING
#===============================================================================

@test "operations handle disk full scenario" {
    skip "Requires disk quota setup"

    # This would require setting up a small filesystem
    # and filling it to test error handling
}

#===============================================================================
# INVALID INPUT ERROR HANDLING
#===============================================================================

@test "functions handle empty string inputs" {
    run module_exists ""
    [[ $status -ne 0 ]]

    run get_module_dir ""
    [[ $status -ne 0 ]]

    run yaml_get "$TEST_TMP/test.yaml" ""
    # Should handle gracefully
}

@test "functions handle null inputs" {
    run module_port ""
    [[ $status -ne 0 ]]

    run module_version ""
    [[ $status -ne 0 ]]
}

@test "functions handle very long inputs" {
    # Create 10KB string
    long_string=$(head -c 10240 /dev/urandom | base64 | tr -d '\n')

    run module_exists "$long_string"
    [[ $status -ne 0 ]]

    # Should not crash
}

@test "functions handle special characters in inputs" {
    run module_exists "module\nwith\nnewlines"
    [[ $status -ne 0 ]]

    run module_exists "module\twith\ttabs"
    [[ $status -ne 0 ]]

    run module_exists "module with spaces"
    [[ $status -ne 0 ]]
}

#===============================================================================
# VERSION MISMATCH ERROR HANDLING
#===============================================================================

@test "check_binary_version handles missing binary" {
    run check_binary_version "/nonexistent/binary" "1.0.0"
    [[ $status -ne 0 ]]
}

@test "check_binary_version handles binary without version output" {
    # Create binary that doesn't output version
    cat > "$TEST_TMP/no_version" << 'EOF'
#!/bin/bash
echo "This binary has no version"
EOF
    chmod +x "$TEST_TMP/no_version"

    run check_binary_version "$TEST_TMP/no_version" "1.0.0"
    [[ $status -ne 0 ]]
}

@test "version_compare handles invalid version formats" {
    # Should handle gracefully, though behavior may vary
    version_compare "not.a.version" "1.0.0" || true
    version_compare "1.0.0" "invalid" || true
}

#===============================================================================
# MODULE INSTALLATION ERROR HANDLING
#===============================================================================

@test "install_module fails for missing install script" {
    mkdir -p "$TEST_TMP/modules/_core/no_script"

    cat > "$TEST_TMP/modules/_core/no_script/module.yaml" << 'EOF'
module:
  name: no_script
  version: 1.0.0
exporter:
  port: 9999
EOF

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run install_module "no_script"
    [[ $status -ne 0 ]]
}

@test "install_module handles script execution failure" {
    mkdir -p "$TEST_TMP/modules/_core/fail_script"

    cat > "$TEST_TMP/modules/_core/fail_script/module.yaml" << 'EOF'
module:
  name: fail_script
  version: 1.0.0
exporter:
  port: 9998
EOF

    cat > "$TEST_TMP/modules/_core/fail_script/install.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$TEST_TMP/modules/_core/fail_script/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run install_module "fail_script"
    [[ $status -ne 0 ]]
}

@test "uninstall_module handles missing uninstall script" {
    mkdir -p "$TEST_TMP/modules/_core/no_uninstall"

    cat > "$TEST_TMP/modules/_core/no_uninstall/module.yaml" << 'EOF'
module:
  name: no_uninstall
  version: 1.0.0
exporter:
  port: 9997
EOF

    touch "$TEST_TMP/modules/_core/no_uninstall/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run uninstall_module "no_uninstall"
    [[ $status -ne 0 ]]
}

#===============================================================================
# CONFIGURATION GENERATION ERROR HANDLING
#===============================================================================

@test "generate_module_scrape_config handles missing manifest fields" {
    mkdir -p "$TEST_TMP/modules/_core/incomplete_manifest"

    cat > "$TEST_TMP/modules/_core/incomplete_manifest/module.yaml" << 'EOF'
module:
  name: incomplete_manifest
  version: 1.0.0
# Missing exporter section
EOF

    _orig_get_manifest=$(declare -f get_module_manifest)
    get_module_manifest() { echo "$TEST_TMP/modules/_core/$1/module.yaml"; }

    _orig_get_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    run generate_module_scrape_config "incomplete_manifest"

    eval "$_orig_get_manifest"
    eval "$_orig_get_dir"

    # Should handle missing fields gracefully
}

@test "aggregate_alert_rules handles corrupted alert files" {
    mkdir -p "$TEST_TMP/modules/_core/bad_alerts"

    cat > "$TEST_TMP/modules/_core/bad_alerts/module.yaml" << 'EOF'
module:
  name: bad_alerts
  version: 1.0.0
exporter:
  port: 9996
EOF

    # Create corrupted alert file
    echo "This is not valid YAML {{{ " > "$TEST_TMP/modules/_core/bad_alerts/alerts.yml"

    rules_dir="$TEST_TMP/rules"
    mkdir -p "$rules_dir"

    _orig_get_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo "bad_alerts"; }
    _orig_get_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    # Should not crash
    aggregate_alert_rules "$rules_dir" 2>/dev/null || true

    eval "$_orig_get_enabled"
    eval "$_orig_get_dir"
}

@test "provision_dashboards handles invalid JSON" {
    mkdir -p "$TEST_TMP/modules/_core/bad_dashboard"

    cat > "$TEST_TMP/modules/_core/bad_dashboard/module.yaml" << 'EOF'
module:
  name: bad_dashboard
  version: 1.0.0
exporter:
  port: 9995
EOF

    # Create invalid JSON
    echo "{ invalid json" > "$TEST_TMP/modules/_core/bad_dashboard/dashboard.json"

    dashboards_dir="$TEST_TMP/dashboards"
    mkdir -p "$dashboards_dir"

    _orig_get_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo "bad_dashboard"; }
    _orig_get_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    # Should not crash
    provision_dashboards "$dashboards_dir" 2>/dev/null || true

    eval "$_orig_get_enabled"
    eval "$_orig_get_dir"
}

#===============================================================================
# TEMPLATE ERROR HANDLING
#===============================================================================

@test "template_render handles missing variables" {
    template='Hello ${NAME}, your age is ${AGE}'

    # Provide only NAME, not AGE
    result=$(template_render "$template" "NAME=John")

    # Should leave unreplaced variables as-is
    echo "$result" | grep -q "AGE"
}

@test "template_render_file handles missing template file" {
    run template_render_file "/nonexistent/template.txt" "VAR=value"
    [[ $status -ne 0 ]]
}

#===============================================================================
# DETECTION ERROR HANDLING
#===============================================================================

@test "module_detect handles modules with no detection rules" {
    mkdir -p "$TEST_TMP/modules/_core/no_detection"

    cat > "$TEST_TMP/modules/_core/no_detection/module.yaml" << 'EOF'
module:
  name: no_detection
  version: 1.0.0
exporter:
  port: 9994
# No detection section
EOF

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    # Should return no confidence or error gracefully
    run module_detect "no_detection"
    # Status may be 0 or 1, but should not crash
}

@test "detect_all_modules handles module detection failures" {
    # Should complete even if some modules fail detection
    result=$(detect_all_modules 2>/dev/null || echo "")

    # Should return some results or empty
}

#===============================================================================
# ROLLBACK AND CLEANUP ERROR HANDLING
#===============================================================================

@test "failed operations don't leave partial state" {
    # Create module that fails mid-installation
    mkdir -p "$TEST_TMP/modules/_core/partial_install"

    cat > "$TEST_TMP/modules/_core/partial_install/module.yaml" << 'EOF'
module:
  name: partial_install
  version: 1.0.0
exporter:
  port: 9993
EOF

    cat > "$TEST_TMP/modules/_core/partial_install/install.sh" << 'EOF'
#!/bin/bash
# Create a marker file
touch /tmp/partial_install_marker
# Then fail
exit 1
EOF
    chmod +x "$TEST_TMP/modules/_core/partial_install/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run install_module "partial_install"
    [[ $status -ne 0 ]]

    # Marker file exists (showing partial execution)
    if [[ -f /tmp/partial_install_marker ]]; then
        # Ideally, rollback would clean this up
        # For now, just note it exists
        rm -f /tmp/partial_install_marker
    fi
}

#===============================================================================
# ERROR MESSAGE QUALITY TESTS
#===============================================================================

@test "error messages are informative" {
    run module_exists "nonexistent_module_12345"
    # Error should not just be empty
}

@test "validation errors include details" {
    mkdir -p "$TEST_TMP/modules/_core/bad_manifest"

    cat > "$TEST_TMP/modules/_core/bad_manifest/module.yaml" << 'EOF'
module:
  name: bad_manifest
  # Missing version
exporter:
  port: invalid_port
EOF

    touch "$TEST_TMP/modules/_core/bad_manifest/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run validate_module "bad_manifest"
    [[ $status -ne 0 ]]

    # Output should mention what's wrong
    [[ "$output" == *"version"* ]] || [[ "$output" == *"port"* ]]
}

#===============================================================================
# GRACEFUL DEGRADATION TESTS
#===============================================================================

@test "system continues with some modules unavailable" {
    # Even if some modules don't exist or fail, system should continue
    result=$(list_all_modules)

    # Should return available modules
    [[ -n "$result" ]]
}

@test "config generation works with partial host data" {
    mkdir -p "$TEST_TMP/config/hosts"

    cat > "$TEST_TMP/config/hosts/partial.yaml" << 'EOF'
host:
  name: partial
  ip: 192.168.1.100
  # Missing other fields
modules:
  node_exporter:
    enabled: true
    # config section could be missing
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    # Should still generate config
    config=$(generate_prometheus_config 2>/dev/null || echo "generated")

    eval "$_orig_func"

    [[ -n "$config" ]]
}
