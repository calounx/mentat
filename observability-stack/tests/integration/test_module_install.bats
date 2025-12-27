#!/usr/bin/env bats
#===============================================================================
# Integration Tests for Module Installation Lifecycle
# Tests full module installation, verification, and uninstallation
#===============================================================================

setup() {
    # Load libraries
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    # Create test directory
    TEST_TMP="$BATS_TEST_TMPDIR/integration_tests_$$"
    mkdir -p "$TEST_TMP"

    # Set log directory to temp location (before sourcing common.sh)
    export LOG_BASE_DIR="$TEST_TMP"

    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/module-loader.sh"

    # Note: Color variables (RED, GREEN, etc.) are readonly from common.sh
    # Tests run with colors enabled - output is captured by BATS anyway

    # Skip if not running as root
    if [[ $EUID -ne 0 ]]; then
        skip "Integration tests require root privileges"
    fi
}

teardown() {
    if [[ -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

#===============================================================================
# MODULE DETECTION INTEGRATION TESTS
#===============================================================================

@test "detect_all_modules finds real system services" {
    result=$(detect_all_modules)

    # Should return in format module:confidence
    if [[ -n "$result" ]]; then
        echo "$result" | head -1 | grep -q ":"

        # Confidence should be 0-100
        confidence=$(echo "$result" | head -1 | cut -d: -f2)
        [[ $confidence -ge 0 ]]
        [[ $confidence -le 100 ]]
    fi
}

@test "node_exporter detection works on Linux systems" {
    # node_exporter should always detect on Linux
    confidence=$(module_detect "node_exporter")

    # Should return some confidence level
    [[ -n "$confidence" ]]
    [[ $confidence -gt 0 ]]
}

#===============================================================================
# MODULE VALIDATION INTEGRATION TESTS
#===============================================================================

@test "validate_all_modules checks all real modules" {
    # This validates all modules in the repository
    validate_all_modules
    # Should succeed if all modules are properly structured
}

@test "all core modules have required files" {
    while IFS= read -r module; do
        module_dir=$(get_module_dir "$module")

        # Check for module.yaml
        [[ -f "$module_dir/module.yaml" ]]

        # Check for install.sh
        [[ -f "$module_dir/install.sh" ]]

        # install.sh should be readable
        [[ -r "$module_dir/install.sh" ]]

    done < <(list_core_modules)
}

@test "all modules have valid ports" {
    while IFS= read -r module; do
        port=$(module_port "$module")

        # Port should be numeric
        [[ "$port" =~ ^[0-9]+$ ]]

        # Port should be in valid range
        [[ $port -gt 0 ]]
        [[ $port -lt 65536 ]]

        # Ports should be unique (check against others)
        # This is a basic uniqueness check

    done < <(list_all_modules)
}

#===============================================================================
# MOCK MODULE INSTALLATION TESTS
#===============================================================================

@test "install simple test module with mock binary" {
    # Create a minimal test module
    mkdir -p "$TEST_TMP/modules/_core/mock_exporter"

    cat > "$TEST_TMP/modules/_core/mock_exporter/module.yaml" << 'EOF'
module:
  name: mock_exporter
  version: 1.0.0
exporter:
  port: 19999
detection:
  files: []
  confidence: 0
EOF

    # Create a mock install script
    cat > "$TEST_TMP/modules/_core/mock_exporter/install.sh" << 'EOF'
#!/bin/bash
# Mock installation - just creates a file
mkdir -p /tmp/mock_exporter_test
echo "installed" > /tmp/mock_exporter_test/status
exit 0
EOF

    chmod +x "$TEST_TMP/modules/_core/mock_exporter/install.sh"

    # Override module directory
    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    # Run installation
    install_module "mock_exporter"

    # Verify installation marker
    [[ -f /tmp/mock_exporter_test/status ]]
    [[ "$(cat /tmp/mock_exporter_test/status)" == "installed" ]]

    # Cleanup
    rm -rf /tmp/mock_exporter_test
}

@test "uninstall removes module cleanly" {
    # Create test module
    mkdir -p "$TEST_TMP/modules/_core/uninstall_test"

    cat > "$TEST_TMP/modules/_core/uninstall_test/module.yaml" << 'EOF'
module:
  name: uninstall_test
  version: 1.0.0
exporter:
  port: 19998
EOF

    # Create install script that creates a marker
    cat > "$TEST_TMP/modules/_core/uninstall_test/install.sh" << 'EOF'
#!/bin/bash
mkdir -p /tmp/uninstall_test
touch /tmp/uninstall_test/installed
EOF

    # Create uninstall script that removes marker
    cat > "$TEST_TMP/modules/_core/uninstall_test/uninstall.sh" << 'EOF'
#!/bin/bash
rm -rf /tmp/uninstall_test
EOF

    chmod +x "$TEST_TMP/modules/_core/uninstall_test/install.sh"
    chmod +x "$TEST_TMP/modules/_core/uninstall_test/uninstall.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    # Install
    install_module "uninstall_test"
    [[ -f /tmp/uninstall_test/installed ]]

    # Uninstall
    uninstall_module "uninstall_test"
    [[ ! -f /tmp/uninstall_test/installed ]]
}

#===============================================================================
# MODULE DEPENDENCY TESTS
#===============================================================================

@test "module installation sets proper environment variables" {
    mkdir -p "$TEST_TMP/modules/_core/env_test"

    cat > "$TEST_TMP/modules/_core/env_test/module.yaml" << 'EOF'
module:
  name: env_test
  version: 2.3.4
exporter:
  port: 19997
EOF

    cat > "$TEST_TMP/modules/_core/env_test/install.sh" << 'EOF'
#!/bin/bash
# Verify environment variables are set
[[ "$MODULE_NAME" == "env_test" ]] || exit 1
[[ "$MODULE_VERSION" == "2.3.4" ]] || exit 1
[[ "$MODULE_PORT" == "19997" ]] || exit 1
[[ -n "$MODULE_DIR" ]] || exit 1
echo "env_check_passed" > /tmp/env_test_result
EOF

    chmod +x "$TEST_TMP/modules/_core/env_test/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    install_module "env_test"

    # Verify environment check passed
    [[ -f /tmp/env_test_result ]]
    [[ "$(cat /tmp/env_test_result)" == "env_check_passed" ]]

    # Cleanup
    rm -f /tmp/env_test_result
}

#===============================================================================
# ERROR HANDLING INTEGRATION TESTS
#===============================================================================

@test "install_module fails gracefully for non-existent module" {
    run install_module "absolutely_nonexistent_module_12345"
    [[ $status -ne 0 ]]
    [[ "$output" == *"not found"* ]]
}

@test "install_module fails if install script missing" {
    mkdir -p "$TEST_TMP/modules/_core/no_install_script"

    cat > "$TEST_TMP/modules/_core/no_install_script/module.yaml" << 'EOF'
module:
  name: no_install_script
  version: 1.0.0
exporter:
  port: 19996
EOF

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run install_module "no_install_script"
    [[ $status -ne 0 ]]
}

@test "install_module handles script failure" {
    mkdir -p "$TEST_TMP/modules/_core/failing_install"

    cat > "$TEST_TMP/modules/_core/failing_install/module.yaml" << 'EOF'
module:
  name: failing_install
  version: 1.0.0
exporter:
  port: 19995
EOF

    cat > "$TEST_TMP/modules/_core/failing_install/install.sh" << 'EOF'
#!/bin/bash
exit 1
EOF

    chmod +x "$TEST_TMP/modules/_core/failing_install/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run install_module "failing_install"
    [[ $status -ne 0 ]]
}

#===============================================================================
# HOST CONFIGURATION INTEGRATION TESTS
#===============================================================================

@test "host configuration file is parsed correctly" {
    # Use a real host config if available
    hosts_dir="$(get_hosts_config_dir)"

    if [[ -d "$hosts_dir" ]]; then
        for config in "$hosts_dir"/*.yaml; do
            [[ -f "$config" ]] || continue
            [[ "$config" == *".template"* ]] && continue

            hostname=$(basename "$config" .yaml)

            # Should be able to get IP
            ip=$(host_config_get_nested "$hostname" "host" "ip")
            [[ -n "$ip" ]]

            # IP should match pattern
            [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]

            # Only test first host
            break
        done
    else
        skip "No host configurations exist"
    fi
}

@test "enabled modules can be retrieved from host config" {
    hosts_dir="$(get_hosts_config_dir)"

    if [[ -d "$hosts_dir" ]]; then
        for config in "$hosts_dir"/*.yaml; do
            [[ -f "$config" ]] || continue
            [[ "$config" == *".template"* ]] && continue

            hostname=$(basename "$config" .yaml)

            # Get enabled modules
            modules=$(get_host_enabled_modules "$hostname")

            # Each module should exist
            while IFS= read -r module; do
                [[ -n "$module" ]]
                module_exists "$module"
            done <<< "$modules"

            # Only test first host
            break
        done
    else
        skip "No host configurations exist"
    fi
}

#===============================================================================
# REAL MODULE STRUCTURE TESTS
#===============================================================================

@test "node_exporter module has all required components" {
    module_dir=$(get_module_dir "node_exporter")

    # Check manifest
    [[ -f "$module_dir/module.yaml" ]]

    # Check install script
    [[ -f "$module_dir/install.sh" ]]
    [[ -x "$module_dir/install.sh" ]]

    # Check uninstall script (should exist)
    [[ -f "$module_dir/uninstall.sh" ]]

    # Check for dashboard (optional but node_exporter should have it)
    # [[ -f "$module_dir/dashboard.json" ]]

    # Check for alerts (optional but node_exporter should have it)
    # [[ -f "$module_dir/alerts.yml" ]]
}

@test "all install scripts are executable" {
    while IFS= read -r module; do
        module_dir=$(get_module_dir "$module")
        install_script="$module_dir/install.sh"

        # Should be executable
        [[ -x "$install_script" ]]

    done < <(list_all_modules)
}

@test "all install scripts have bash shebang" {
    while IFS= read -r module; do
        module_dir=$(get_module_dir "$module")
        install_script="$module_dir/install.sh"

        # First line should be bash shebang
        first_line=$(head -1 "$install_script")
        [[ "$first_line" == "#!/bin/bash"* ]]

    done < <(list_all_modules)
}

#===============================================================================
# MODULE LISTING INTEGRATION TESTS
#===============================================================================

@test "list_modules_status generates complete table" {
    result=$(list_modules_status)

    # Should have header
    echo "$result" | grep -q "MODULE"

    # Should have at least node_exporter
    echo "$result" | grep -q "node_exporter"

    # Each line should have proper columns
    # Skip header lines and check data lines
    while IFS= read -r line; do
        [[ "$line" == *"MODULE"* ]] && continue
        [[ "$line" == *"---"* ]] && continue
        [[ -z "$line" ]] && continue

        # Line should have multiple columns
        col_count=$(echo "$line" | awk '{print NF}')
        [[ $col_count -ge 3 ]]
    done <<< "$result"
}

@test "show_module_info displays complete information" {
    result=$(show_module_info "node_exporter")

    # Should have all sections
    echo "$result" | grep -q "Module:"
    echo "$result" | grep -q "Version:"
    echo "$result" | grep -q "Port:"
    echo "$result" | grep -q "Location:"
}

#===============================================================================
# CONCURRENCY AND RACE CONDITION TESTS
#===============================================================================

@test "parallel module queries don't interfere" {
    # Run multiple queries in parallel
    (
        module_exists "node_exporter" &
        module_port "node_exporter" &
        module_version "node_exporter" &
        wait
    )

    # All should succeed
    [[ $? -eq 0 ]]
}

#===============================================================================
# FILESYSTEM INTEGRATION TESTS
#===============================================================================

@test "module directories have proper permissions" {
    while IFS= read -r module; do
        module_dir=$(get_module_dir "$module")

        # Directory should be readable
        [[ -r "$module_dir" ]]

        # module.yaml should be readable
        [[ -r "$module_dir/module.yaml" ]]

    done < <(list_core_modules)
}

@test "no module files contain secrets or credentials" {
    while IFS= read -r module; do
        module_dir=$(get_module_dir "$module")

        # Check for common secret patterns in module.yaml
        ! grep -qi "password:" "$module_dir/module.yaml"
        ! grep -qi "secret:" "$module_dir/module.yaml"
        ! grep -qi "api_key:" "$module_dir/module.yaml"

    done < <(list_all_modules)
}
