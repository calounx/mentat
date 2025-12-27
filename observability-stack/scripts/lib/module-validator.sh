#!/bin/bash
#===============================================================================
# Module Security Validator
# Validates modules for security issues before execution
#===============================================================================
# SECURITY: This validator implements defense-in-depth module validation
# to prevent execution of malicious or insecure module code.
#===============================================================================

# Guard against multiple sourcing
[[ -n "${MODULE_VALIDATOR_LOADED:-}" ]] && return 0
MODULE_VALIDATOR_LOADED=1

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

#===============================================================================
# SECURITY PATTERNS AND CONFIGURATIONS
#===============================================================================

# SECURITY: Dangerous patterns that should NEVER appear in module scripts
# These patterns indicate potential security vulnerabilities or malicious code
declare -A DANGEROUS_PATTERNS=(
    # Code injection vulnerabilities
    ["eval"]="Command injection risk - eval executes arbitrary code"
    ["curl.*bash"]="Remote code execution - piping curl to bash"
    ["wget.*bash"]="Remote code execution - piping wget to bash"
    ["curl.*sh"]="Remote code execution - piping curl to sh"
    ["wget.*sh"]="Remote code execution - piping wget to sh"
    ['\$\(curl']="Command injection via curl substitution"
    ['\$\(wget']="Command injection via wget substitution"

    # Dangerous download patterns (without verification)
    ["wget.*-O.*\|.*sh"]="Unverified remote execution"
    ["curl.*\|.*bash"]="Unverified remote execution"

    # Data exfiltration patterns
    ["curl.*-X POST"]="Potential data exfiltration"
    ["wget.*--post"]="Potential data exfiltration"
    ["nc.*-e"]="Netcat reverse shell pattern"
    ["bash.*-i.*tcp"]="Reverse shell pattern"

    # Privilege escalation attempts
    ["chmod.*777"]="Overly permissive file permissions"
    ["chmod.*u\+s"]="SUID bit manipulation"
    ["sudo.*NOPASSWD"]="Passwordless sudo configuration"

    # Credential harvesting
    ["cat.*shadow"]="Password hash file access"
    ["cat.*passwd.*grep"]="User enumeration pattern"

    # Process manipulation
    ["kill.*-9.*1"]="Attempting to kill init"
    ["pkill.*-9.*systemd"]="Attempting to kill systemd"

    # Dangerous file operations
    ["rm.*-rf.*/"]="Dangerous recursive deletion at root"
    ["dd.*of=/dev/sd"]="Direct disk writing"
    ["mkfs"]="Filesystem formatting"

    # Network backdoors
    [":.*&.*bash"]="Port binding with shell"
    ["socat.*exec"]="Socat reverse shell"
)

# SECURITY: Suspicious patterns that warrant warnings but may be legitimate
declare -A SUSPICIOUS_PATTERNS=(
    # Base64 encoding (often used to obfuscate)
    ["base64.*-d"]="Base64 decoding - potential obfuscation"

    # Download without verification
    ["wget.*&&.*tar"]="Download and extract without verification"
    ["curl.*&&.*tar"]="Download and extract without verification"

    # Cron job manipulation
    ["crontab.*-"]="Cron job modification"

    # SSH key manipulation
    ["authorized_keys"]="SSH key modification"
    [".ssh/"]="SSH directory access"

    # Systemd manipulation beyond standard service management
    ["systemctl.*daemon-reload.*systemctl.*enable"]="Complex systemd manipulation"

    # Firewall manipulation
    ["iptables.*-F"]="Firewall flush"
    ["ufw.*disable"]="Firewall disable"

    # Package repository modification
    ["add-apt-repository"]="Repository modification"
    ["rpm.*--import"]="RPM key import"
)

# SECURITY: Required security functions that modules should use
declare -A REQUIRED_SECURITY_FUNCTIONS=(
    ["download_and_verify"]="Checksum-verified downloads"
    ["safe_chmod"]="Safe file permission changes"
    ["safe_chown"]="Safe ownership changes"
    ["validate_ip"]="IP address validation"
    ["validate_port"]="Port validation"
)

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

# Validate module directory structure and required files
# Usage: validate_module_structure "module_name" "module_dir"
# Returns: 0 if valid, 1 if validation fails
validate_module_structure() {
    local module_name="$1"
    local module_dir="$2"
    local errors=()

    log_debug "SECURITY: Validating module structure for '$module_name'"

    # SECURITY: Validate module directory exists and is not a symlink
    if [[ ! -d "$module_dir" ]]; then
        log_error "Module directory does not exist: $module_dir"
        return 1
    fi

    if [[ -L "$module_dir" ]]; then
        log_error "SECURITY: Module directory is a symlink (not allowed): $module_dir"
        return 1
    fi

    # SECURITY: Check for required files
    local required_files=("module.yaml" "install.sh")

    for file in "${required_files[@]}"; do
        local file_path="$module_dir/$file"

        if [[ ! -f "$file_path" ]]; then
            errors+=("Missing required file: $file")
            continue
        fi

        # SECURITY: Ensure files are not symlinks
        if [[ -L "$file_path" ]]; then
            errors+=("SECURITY: $file is a symlink (not allowed)")
        fi
    done

    # Report validation results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Module structure validation failed for '$module_name':"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    log_debug "SECURITY: Module structure validation passed for '$module_name'"
    return 0
}

# Validate module manifest (module.yaml) for security issues
# Usage: validate_module_manifest "module_name" "manifest_path"
# Returns: 0 if valid, 1 if validation fails
validate_module_manifest() {
    local module_name="$1"
    local manifest_path="$2"
    local errors=()
    local warnings=()

    log_debug "SECURITY: Validating module manifest for '$module_name'"

    # SECURITY: Check file permissions (should not be world-writable)
    local perms
    perms=$(stat -c "%a" "$manifest_path" 2>/dev/null)

    if [[ "$perms" =~ [0-9][0-9]7$ ]]; then
        errors+=("SECURITY: Manifest is world-writable ($perms)")
    fi

    # SECURITY: Check for required fields
    local required_fields=("module.name" "module.version" "exporter.port")

    for field in "${required_fields[@]}"; do
        local parent="${field%.*}"
        local child="${field#*.}"

        if ! yaml_get_nested "$manifest_path" "$parent" "$child" &>/dev/null; then
            errors+=("Missing required field: $field")
        fi
    done

    # SECURITY: Validate version format (prevent injection via version string)
    local version
    version=$(yaml_get_nested "$manifest_path" "module" "version")

    if [[ -n "$version" ]] && ! is_valid_version "$version"; then
        errors+=("Invalid version format: $version (must be semantic version)")
    fi

    # SECURITY: Validate port is numeric and in valid range
    local port
    port=$(yaml_get_nested "$manifest_path" "exporter" "port")

    if [[ -n "$port" ]]; then
        if ! validate_port "$port"; then
            errors+=("Invalid port: $port (must be 1-65535)")
        fi

        # SECURITY: Warn about privileged ports
        if [[ "$port" -lt 1024 ]]; then
            warnings+=("WARNING: Using privileged port $port (< 1024)")
        fi
    fi

    # SECURITY: Check for hardcoded secrets in manifest
    if grep -qiE "(password|secret|token|key).*:.*['\"]" "$manifest_path" 2>/dev/null; then
        warnings+=("WARNING: Potential hardcoded credentials in manifest")
    fi

    # Report results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Module manifest validation failed for '$module_name':"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        for warning in "${warnings[@]}"; do
            log_warn "$warning"
        done
    fi

    log_debug "SECURITY: Module manifest validation passed for '$module_name'"
    return 0
}

# Scan script for dangerous patterns
# Usage: scan_script_for_dangerous_patterns "script_path" "script_type"
# Returns: 0 if safe, 1 if dangerous patterns found
scan_script_for_dangerous_patterns() {
    local script_path="$1"
    local script_type="$2"
    local found_dangerous=0
    local found_suspicious=0

    log_debug "SECURITY: Scanning $script_type for dangerous patterns"

    # SECURITY: Scan for dangerous patterns (BLOCKING)
    for pattern in "${!DANGEROUS_PATTERNS[@]}"; do
        if grep -qE "$pattern" "$script_path" 2>/dev/null; then
            log_error "SECURITY: DANGEROUS pattern found in $script_type: $pattern"
            log_error "  Reason: ${DANGEROUS_PATTERNS[$pattern]}"

            # Show the problematic line(s)
            log_error "  Line(s):"
            grep -nE "$pattern" "$script_path" | while IFS=: read -r line_num line_content; do
                log_error "    $line_num: $line_content"
            done

            found_dangerous=1
        fi
    done

    # SECURITY: Scan for suspicious patterns (WARNING)
    for pattern in "${!SUSPICIOUS_PATTERNS[@]}"; do
        if grep -qE "$pattern" "$script_path" 2>/dev/null; then
            log_warn "SECURITY: Suspicious pattern found in $script_type: $pattern"
            log_warn "  Reason: ${SUSPICIOUS_PATTERNS[$pattern]}"

            # Show the problematic line(s)
            grep -nE "$pattern" "$script_path" | head -3 | while IFS=: read -r line_num line_content; do
                log_warn "    $line_num: $line_content"
            done

            found_suspicious=1
        fi
    done

    if [[ $found_dangerous -eq 1 ]]; then
        log_error "SECURITY: Module validation FAILED - dangerous patterns detected"
        return 1
    fi

    if [[ $found_suspicious -eq 1 ]]; then
        log_warn "SECURITY: Suspicious patterns found - manual review recommended"
    fi

    return 0
}

# Validate install.sh script for security issues
# Usage: validate_install_script "module_name" "install_script_path"
# Returns: 0 if valid, 1 if validation fails
validate_install_script() {
    local module_name="$1"
    local install_script="$2"
    local errors=()
    local warnings=()

    log_debug "SECURITY: Validating install script for '$module_name'"

    # SECURITY: Check file exists and is executable
    if [[ ! -f "$install_script" ]]; then
        log_error "Install script not found: $install_script"
        return 1
    fi

    if [[ ! -x "$install_script" ]]; then
        warnings+=("Install script is not executable (will be sourced, not executed)")
    fi

    # SECURITY: Check file permissions (should not be world-writable)
    local perms
    perms=$(stat -c "%a" "$install_script" 2>/dev/null)

    if [[ "$perms" =~ [0-9][0-9]7$ ]]; then
        errors+=("SECURITY: Install script is world-writable ($perms)")
    fi

    # SECURITY: Check for bash shebang
    local shebang
    shebang=$(head -1 "$install_script")

    if [[ ! "$shebang" =~ ^#!/bin/(ba)?sh ]]; then
        warnings+=("Missing or invalid shebang: $shebang")
    fi

    # SECURITY: Check for 'set -e' or 'set -euo pipefail' (fail on errors)
    if ! grep -qE "^set -[euo]+.*e" "$install_script"; then
        warnings+=("Script does not use 'set -e' (errors may be silently ignored)")
    fi

    # SECURITY: Scan for dangerous patterns
    if ! scan_script_for_dangerous_patterns "$install_script" "install.sh"; then
        errors+=("Dangerous patterns detected in install script")
    fi

    # SECURITY: Check that downloads use verification
    if grep -qE "(wget|curl).*-O" "$install_script"; then
        if ! grep -q "download_and_verify" "$install_script"; then
            errors+=("SECURITY: Script downloads files but doesn't use download_and_verify")
        fi
    fi

    # SECURITY: Check for hardcoded credentials/secrets
    local -a credential_patterns=(
        "password[[:space:]]*="
        "passwd[[:space:]]*="
        "secret[[:space:]]*="
        "api_key[[:space:]]*="
        "token[[:space:]]*="
    )

    for pattern in "${credential_patterns[@]}"; do
        if grep -qiE "$pattern" "$install_script"; then
            # Check if it's actually a hardcoded value (not a variable assignment from env/file)
            local matches
            matches=$(grep -iE "$pattern" "$install_script" | grep -v "^\s*#" | grep -v "\${" | grep -v "resolve_secret" || true)

            if [[ -n "$matches" ]]; then
                warnings+=("Potential hardcoded credential pattern: $pattern")
                log_warn "  Lines: $matches"
            fi
        fi
    done

    # SECURITY: Validate required security functions are used
    local uses_downloads=0
    if grep -qE "(wget|curl)" "$install_script"; then
        uses_downloads=1
    fi

    if [[ $uses_downloads -eq 1 ]]; then
        if ! grep -q "download_and_verify" "$install_script"; then
            errors+=("SECURITY: Downloads files without checksum verification")
        fi
    fi

    # Report results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Install script validation failed for '$module_name':"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "Install script warnings for '$module_name':"
        for warning in "${warnings[@]}"; do
            log_warn "  - $warning"
        done
    fi

    log_debug "SECURITY: Install script validation passed for '$module_name'"
    return 0
}

# Validate module file permissions
# Usage: validate_module_permissions "module_dir"
# Returns: 0 if valid, 1 if issues found
validate_module_permissions() {
    local module_dir="$1"
    local errors=()
    local warnings=()

    log_debug "SECURITY: Validating module file permissions"

    # SECURITY: Check all files in module directory
    while IFS= read -r -d '' file; do
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null)

        # SECURITY: No files should be world-writable
        if [[ "$perms" =~ [0-9][0-9]7$ ]]; then
            errors+=("World-writable file: $file ($perms)")
        fi

        # SECURITY: Executable files should have appropriate permissions
        if [[ -x "$file" ]] && [[ ! "$perms" =~ ^[0-7]5[0-5]$ ]]; then
            warnings+=("Executable with unusual permissions: $file ($perms)")
        fi

    done < <(find "$module_dir" -type f -print0)

    # Report results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "File permission validation failed:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        for warning in "${warnings[@]}"; do
            log_warn "  - $warning"
        done
    fi

    log_debug "SECURITY: File permission validation passed"
    return 0
}

# Check for required security functions in module
# Usage: validate_security_functions "install_script"
# Returns: 0 if using security functions appropriately
validate_security_functions() {
    local install_script="$1"
    local warnings=()

    log_debug "SECURITY: Validating use of security functions"

    # Check if script uses chmod/chown directly instead of safe versions
    if grep -qE "^\s*chmod\s+" "$install_script"; then
        if ! grep -q "safe_chmod" "$install_script"; then
            warnings+=("Uses 'chmod' directly instead of 'safe_chmod'")
        fi
    fi

    if grep -qE "^\s*chown\s+" "$install_script"; then
        if ! grep -q "safe_chown" "$install_script"; then
            warnings+=("Uses 'chown' directly instead of 'safe_chown'")
        fi
    fi

    # Report warnings
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "Security function recommendations:"
        for warning in "${warnings[@]}"; do
            log_warn "  - $warning"
        done
    fi

    return 0
}

#===============================================================================
# MAIN VALIDATION INTERFACE
#===============================================================================

# Comprehensive module security validation
# Usage: validate_module_security "module_name"
# Returns: 0 if module passes all security checks, 1 otherwise
validate_module_security() {
    local module_name="$1"
    local module_dir
    local validation_failed=0

    log_info "SECURITY: Running comprehensive security validation for module '$module_name'"

    # Get module directory
    module_dir=$(get_module_dir "$module_name")
    if [[ $? -ne 0 ]]; then
        log_error "Module not found: $module_name"
        return 1
    fi

    # Step 1: Validate module structure
    if ! validate_module_structure "$module_name" "$module_dir"; then
        validation_failed=1
    fi

    # Step 2: Validate module manifest
    local manifest="$module_dir/module.yaml"
    if [[ -f "$manifest" ]]; then
        if ! validate_module_manifest "$module_name" "$manifest"; then
            validation_failed=1
        fi
    else
        log_error "Module manifest not found: $manifest"
        validation_failed=1
    fi

    # Step 3: Validate install script
    local install_script="$module_dir/install.sh"
    if [[ -f "$install_script" ]]; then
        if ! validate_install_script "$module_name" "$install_script"; then
            validation_failed=1
        fi

        # Additional security function checks
        validate_security_functions "$install_script"
    else
        log_error "Install script not found: $install_script"
        validation_failed=1
    fi

    # Step 4: Validate file permissions
    if ! validate_module_permissions "$module_dir"; then
        validation_failed=1
    fi

    # Final result
    if [[ $validation_failed -eq 1 ]]; then
        log_error "SECURITY: Module '$module_name' FAILED security validation"
        log_error "SECURITY: Module will NOT be executed for safety"
        return 1
    fi

    log_success "SECURITY: Module '$module_name' passed all security checks"
    return 0
}

# Validate all modules
# Usage: validate_all_modules_security
# Returns: 0 if all modules pass, 1 if any fail
validate_all_modules_security() {
    local has_failures=false
    local total=0
    local passed=0
    local failed=0

    log_info "SECURITY: Validating all modules for security issues"
    echo ""

    while IFS= read -r module; do
        ((total++))

        if validate_module_security "$module"; then
            ((passed++))
        else
            ((failed++))
            has_failures=true
        fi

        echo ""
    done < <(list_all_modules)

    # Summary
    log_info "=========================================="
    log_info "Security Validation Summary"
    log_info "=========================================="
    log_info "Total modules:  $total"
    log_success "Passed:         $passed"

    if [[ $failed -gt 0 ]]; then
        log_error "Failed:         $failed"
    else
        log_info "Failed:         $failed"
    fi

    if [[ "$has_failures" == "true" ]]; then
        log_error "SECURITY: Some modules failed validation"
        return 1
    fi

    log_success "SECURITY: All modules passed validation"
    return 0
}
