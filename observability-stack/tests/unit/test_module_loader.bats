#!/usr/bin/env bats
#===============================================================================
# Unit Tests for module-loader.sh Library Functions
# Tests module discovery, validation, detection, and management
#===============================================================================

setup() {
    # Load the libraries under test
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/module-loader.sh"

    # Create temporary test directory
    TEST_TMP="$BATS_TEST_TMPDIR/module_tests_$$"
    mkdir -p "$TEST_TMP"

    # Disable colors
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
}

teardown() {
    if [[ -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

#===============================================================================
# MODULE DISCOVERY TESTS
#===============================================================================

@test "list_all_modules finds existing modules" {
    result=$(list_all_modules)

    # Should find at least node_exporter
    echo "$result" | grep -q "node_exporter"
}

@test "list_all_modules returns unique sorted results" {
    result=$(list_all_modules)

    # Check if sorted
    sorted=$(echo "$result" | sort)
    [[ "$result" == "$sorted" ]]

    # Check uniqueness
    unique=$(echo "$result" | sort -u)
    [[ "$result" == "$unique" ]]
}

@test "list_core_modules finds core modules" {
    result=$(list_core_modules)

    # Core modules should include node_exporter
    echo "$result" | grep -q "node_exporter"
}

@test "get_module_dir returns correct path for existing module" {
    result=$(get_module_dir "node_exporter")

    # Should return a path
    [[ -n "$result" ]]

    # Path should exist
    [[ -d "$result" ]]

    # Path should end with node_exporter
    [[ "$result" == *"node_exporter"* ]]

    # Should contain module.yaml
    [[ -f "$result/module.yaml" ]]
}

@test "get_module_dir fails for non-existent module" {
    run get_module_dir "nonexistent_module_12345"
    [[ $status -ne 0 ]]
}

@test "get_module_manifest returns manifest path" {
    result=$(get_module_manifest "node_exporter")

    # Should end with module.yaml
    [[ "$result" == *"module.yaml" ]]

    # File should exist
    [[ -f "$result" ]]
}

@test "get_module_manifest fails for non-existent module" {
    run get_module_manifest "nonexistent_module"
    [[ $status -ne 0 ]]
}

@test "module_exists detects existing module" {
    module_exists "node_exporter"
    [[ $? -eq 0 ]]
}

@test "module_exists fails for non-existent module" {
    run module_exists "nonexistent_module_12345"
    [[ $status -ne 0 ]]
}

#===============================================================================
# MODULE MANIFEST PARSING TESTS
#===============================================================================

@test "module_get extracts top-level values" {
    # This test relies on real node_exporter module
    result=$(module_get "node_exporter" "module")
    [[ -n "$result" ]]
}

@test "module_get_nested extracts nested values" {
    result=$(module_get_nested "node_exporter" "module" "name")
    [[ "$result" == "node_exporter" ]]

    result=$(module_get_nested "node_exporter" "module" "version")
    [[ -n "$result" ]]
    # Version should match semver pattern
    [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "module_version returns version string" {
    result=$(module_version "node_exporter")

    [[ -n "$result" ]]
    [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "module_display_name returns display name" {
    result=$(module_display_name "node_exporter")

    [[ -n "$result" ]]
    [[ "$result" == "Node Exporter" ]]
}

@test "module_port returns valid port number" {
    result=$(module_port "node_exporter")

    [[ -n "$result" ]]
    [[ "$result" =~ ^[0-9]+$ ]]
    [[ $result -gt 0 ]]
    [[ $result -lt 65536 ]]
}

@test "module_category returns category" {
    result=$(module_category "node_exporter")

    [[ -n "$result" ]]
}

@test "module_description returns description" {
    result=$(module_description "node_exporter")

    [[ -n "$result" ]]
    [[ ${#result} -gt 10 ]]
}

#===============================================================================
# MODULE DETECTION TESTS
#===============================================================================

@test "validate_and_execute_detection_command accepts whitelisted commands" {
    # Test systemctl (should be whitelisted)
    validate_and_execute_detection_command "systemctl --version"
    # May succeed or fail depending on system, but should not error on validation

    # Test 'which' command
    validate_and_execute_detection_command "which bash"
    # Should succeed since bash exists

    # Test 'test' command
    validate_and_execute_detection_command "test -f /etc/passwd"
    # Should succeed since file exists
}

@test "validate_and_execute_detection_command rejects dangerous commands" {
    # Test command injection attempts
    run validate_and_execute_detection_command "rm -rf /"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl; rm -rf /"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl | cat /etc/passwd"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl && malicious"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl \$(whoami)"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl \`id\`"
    [[ $status -ne 0 ]]
}

@test "validate_and_execute_detection_command rejects non-whitelisted commands" {
    run validate_and_execute_detection_command "curl http://evil.com"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "wget http://evil.com"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "nc -l 1234"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "bash -c 'echo test'"
    [[ $status -ne 0 ]]
}

@test "module_detect returns confidence for node_exporter" {
    # node_exporter should be detected on any Linux system
    result=$(module_detect "node_exporter")

    # Should return a number
    [[ "$result" =~ ^[0-9]+$ ]]

    # Confidence should be reasonable (0-100)
    [[ $result -ge 0 ]]
    [[ $result -le 100 ]]
}

@test "module_detect returns empty for non-applicable module" {
    # Create a test module with impossible detection criteria
    mkdir -p "$TEST_TMP/modules/_core/impossible_module"

    cat > "$TEST_TMP/modules/_core/impossible_module/module.yaml" << 'EOF'
module:
  name: impossible_module
  version: 1.0.0
exporter:
  port: 9999
detection:
  files:
    - /this/path/definitely/does/not/exist/12345
  confidence: 100
EOF

    # Temporarily override module directory
    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    result=$(module_detect "impossible_module" 2>/dev/null || echo "")
    [[ -z "$result" ]]
}

@test "detect_all_modules finds multiple modules" {
    result=$(detect_all_modules)

    # Should find at least node_exporter
    echo "$result" | grep -q "node_exporter:"

    # Format should be module:confidence
    echo "$result" | head -1 | grep -q ":"
}

@test "detect_all_modules returns sorted by confidence" {
    result=$(detect_all_modules)

    # Extract confidence values
    confidences=$(echo "$result" | cut -d: -f2)

    # Check if sorted descending
    sorted=$(echo "$confidences" | sort -rn)
    [[ "$confidences" == "$sorted" ]]
}

#===============================================================================
# MODULE VALIDATION TESTS
#===============================================================================

@test "validate_module succeeds for valid module" {
    validate_module "node_exporter"
    [[ $? -eq 0 ]]
}

@test "validate_module fails for non-existent module" {
    run validate_module "nonexistent_module"
    [[ $status -ne 0 ]]
}

@test "validate_module checks required fields" {
    # Create invalid module missing required fields
    mkdir -p "$TEST_TMP/modules/_core/invalid_module"

    cat > "$TEST_TMP/modules/_core/invalid_module/module.yaml" << 'EOF'
# Missing module.name
module:
  version: 1.0.0
EOF

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run validate_module "invalid_module"
    [[ $status -ne 0 ]]
    [[ "$output" == *"name"* ]]
}

@test "validate_module checks for install script" {
    # Create module without install.sh
    mkdir -p "$TEST_TMP/modules/_core/no_install"

    cat > "$TEST_TMP/modules/_core/no_install/module.yaml" << 'EOF'
module:
  name: no_install
  version: 1.0.0
exporter:
  port: 9999
EOF

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run validate_module "no_install"
    [[ $status -ne 0 ]]
    [[ "$output" == *"install.sh"* ]]
}

@test "validate_module checks port is numeric" {
    # Create module with invalid port
    mkdir -p "$TEST_TMP/modules/_core/bad_port"

    cat > "$TEST_TMP/modules/_core/bad_port/module.yaml" << 'EOF'
module:
  name: bad_port
  version: 1.0.0
exporter:
  port: not_a_number
EOF

    # Create dummy install script
    touch "$TEST_TMP/modules/_core/bad_port/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run validate_module "bad_port"
    [[ $status -ne 0 ]]
    [[ "$output" == *"port"* ]]
}

#===============================================================================
# HOST CONFIGURATION TESTS
#===============================================================================

@test "get_host_config returns correct path" {
    result=$(get_host_config "testhost")

    [[ "$result" == *"testhost.yaml" ]]
    [[ "$result" == *"/config/hosts/"* ]]
}

@test "host_config_exists detects existing config" {
    # Create a test host config
    hosts_dir="$(get_hosts_config_dir)"
    mkdir -p "$hosts_dir"

    cat > "$hosts_dir/testhost.yaml" << 'EOF'
host:
  name: testhost
  ip: 192.168.1.100
EOF

    host_config_exists "testhost"
    [[ $? -eq 0 ]]

    # Cleanup
    rm -f "$hosts_dir/testhost.yaml"
}

@test "host_config_exists fails for non-existent config" {
    run host_config_exists "nonexistent_host_12345"
    [[ $status -ne 0 ]]
}

@test "list_configured_hosts finds existing hosts" {
    hosts_dir="$(get_hosts_config_dir)"

    if [[ -d "$hosts_dir" ]] && [[ $(ls -A "$hosts_dir"/*.yaml 2>/dev/null | wc -l) -gt 0 ]]; then
        result=$(list_configured_hosts)

        # Should have at least one line
        [[ -n "$result" ]]
    else
        skip "No host configs exist"
    fi
}

@test "host_config_get extracts values from host config" {
    hosts_dir="$(get_hosts_config_dir)"
    mkdir -p "$hosts_dir"

    cat > "$hosts_dir/testhost.yaml" << 'EOF'
host:
  name: testhost
  ip: 192.168.1.100
monitoring:
  enabled: true
EOF

    result=$(host_config_get_nested "testhost" "host" "ip")
    [[ "$result" == "192.168.1.100" ]]

    # Cleanup
    rm -f "$hosts_dir/testhost.yaml"
}

@test "get_host_enabled_modules returns enabled modules" {
    hosts_dir="$(get_hosts_config_dir)"
    mkdir -p "$hosts_dir"

    cat > "$hosts_dir/testhost.yaml" << 'EOF'
host:
  name: testhost
  ip: 192.168.1.100
modules:
  node_exporter:
    enabled: true
  nginx_exporter:
    enabled: false
  promtail:
    enabled: true
EOF

    result=$(get_host_enabled_modules "testhost")

    # Should contain enabled modules
    echo "$result" | grep -q "node_exporter"
    echo "$result" | grep -q "promtail"

    # Should NOT contain disabled modules
    ! echo "$result" | grep -q "nginx_exporter"

    # Cleanup
    rm -f "$hosts_dir/testhost.yaml"
}

@test "module_enabled_for_host checks module status" {
    hosts_dir="$(get_hosts_config_dir)"
    mkdir -p "$hosts_dir"

    cat > "$hosts_dir/testhost.yaml" << 'EOF'
modules:
  node_exporter:
    enabled: true
  nginx_exporter:
    enabled: false
EOF

    module_enabled_for_host "node_exporter" "testhost"
    [[ $? -eq 0 ]]

    run module_enabled_for_host "nginx_exporter" "testhost"
    [[ $status -ne 0 ]]

    # Cleanup
    rm -f "$hosts_dir/testhost.yaml"
}

#===============================================================================
# MODULE INFORMATION DISPLAY TESTS
#===============================================================================

@test "show_module_info displays module information" {
    result=$(show_module_info "node_exporter")

    echo "$result" | grep -q "Module: node_exporter"
    echo "$result" | grep -q "Version:"
    echo "$result" | grep -q "Port:"
}

@test "show_module_info fails for non-existent module" {
    run show_module_info "nonexistent_module"
    [[ $status -ne 0 ]]
}

@test "list_modules_status displays table" {
    result=$(list_modules_status)

    # Should have header
    echo "$result" | grep -q "MODULE"
    echo "$result" | grep -q "VERSION"
    echo "$result" | grep -q "PORT"

    # Should list node_exporter
    echo "$result" | grep -q "node_exporter"
}

#===============================================================================
# MODULE DIRECTORIES TESTS
#===============================================================================

@test "module directories are defined" {
    [[ -n "$MODULES_CORE_DIR" ]]
    [[ -n "$MODULES_AVAILABLE_DIR" ]]
    [[ -n "$MODULES_CUSTOM_DIR" ]]
}

@test "core modules directory exists" {
    [[ -d "$MODULES_CORE_DIR" ]]
}

#===============================================================================
# EDGE CASES AND ERROR HANDLING
#===============================================================================

@test "functions handle empty module names gracefully" {
    run module_exists ""
    [[ $status -ne 0 ]]

    run get_module_dir ""
    [[ $status -ne 0 ]]
}

@test "functions handle special characters in module names" {
    run module_exists "module/with/slashes"
    [[ $status -ne 0 ]]

    run module_exists "module;with;semicolons"
    [[ $status -ne 0 ]]
}

@test "yaml parsing handles malformed files gracefully" {
    mkdir -p "$TEST_TMP/modules/_core/malformed"

    cat > "$TEST_TMP/modules/_core/malformed/module.yaml" << 'EOF'
this is not: valid: yaml: at: all:
    random indentation
  mixed
EOF

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    # Should not crash, just return empty/error
    run module_get_nested "malformed" "module" "name"
    # Exit code may vary, but should not crash
}
