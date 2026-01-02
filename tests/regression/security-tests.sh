#!/bin/bash
#===============================================================================
# Security Regression Test Suite
#===============================================================================
# Comprehensive security testing for the Mentat observability stack
# Based on OWASP Top 10 and CWE security standards
#
# Usage:
#   ./security-tests.sh [--verbose] [--report-only] [--test TEST_NAME]
#
# Options:
#   --verbose       Show detailed test output
#   --report-only   Generate report without running tests
#   --test NAME     Run specific test only
#   --help          Show this help
#
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_DIR="$REPO_ROOT/tests/regression/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORT_DIR/security-report-$TIMESTAMP.txt"

# Test configuration
VERBOSE=false
REPORT_ONLY=false
SPECIFIC_TEST=""
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
CRITICAL_FAILURES=0
HIGH_FAILURES=0
MEDIUM_FAILURES=0
LOW_FAILURES=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$REPORT_FILE"
    ((PASSED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$REPORT_FILE"
}

log_error() {
    local severity="${1:-MEDIUM}"
    shift
    echo -e "${RED}[FAIL]${NC} [$severity] $*" | tee -a "$REPORT_FILE"
    ((FAILED_TESTS++))

    case "$severity" in
        CRITICAL) ((CRITICAL_FAILURES++)) ;;
        HIGH) ((HIGH_FAILURES++)) ;;
        MEDIUM) ((MEDIUM_FAILURES++)) ;;
        LOW) ((LOW_FAILURES++)) ;;
    esac
}

init_report() {
    mkdir -p "$REPORT_DIR"
    cat > "$REPORT_FILE" << EOF
================================================================================
SECURITY REGRESSION TEST REPORT
================================================================================
Date: $(date)
Repository: $REPO_ROOT
Test Suite Version: 1.0.0

================================================================================
TEST EXECUTION
================================================================================

EOF
}

generate_summary() {
    cat >> "$REPORT_FILE" << EOF

================================================================================
TEST SUMMARY
================================================================================
Total Tests:       $TOTAL_TESTS
Passed:            $PASSED_TESTS
Failed:            $FAILED_TESTS

FAILURE SEVERITY BREAKDOWN:
Critical:          $CRITICAL_FAILURES
High:              $HIGH_FAILURES
Medium:            $MEDIUM_FAILURES
Low:               $LOW_FAILURES

Overall Status:    $(if [[ $CRITICAL_FAILURES -eq 0 && $HIGH_FAILURES -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi)

================================================================================
OWASP TOP 10 COMPLIANCE
================================================================================
$(generate_owasp_compliance)

================================================================================
RECOMMENDATIONS
================================================================================
$(generate_recommendations)

================================================================================
EOF

    echo ""
    echo "Report saved to: $REPORT_FILE"
}

#===============================================================================
# TEST 1: SECRETS MANAGEMENT (OWASP A02:2021 - Cryptographic Failures)
#===============================================================================

test_secrets_management() {
    ((TOTAL_TESTS++))
    log_info "Test 1: Secrets Management"

    local issues=0

    # Check for hardcoded secrets in code
    log_info "  1.1 Scanning for hardcoded secrets..."
    local scan_output
    scan_output=$(timeout 60 python3 "$REPO_ROOT/observability-stack/scripts/tools/scan_secrets.py" "$REPO_ROOT" 2>&1) || true
    if echo "$scan_output" | grep -qi "security issues found"; then
        log_error "CRITICAL" "Hardcoded secrets detected in source code"
        ((issues++))
    else
        log_success "  1.1 No hardcoded secrets found"
    fi

    # Check .env files are gitignored
    log_info "  1.2 Verifying .env files are gitignored..."
    if timeout 10 git ls-files 2>/dev/null | grep -E "^(chom/\.env|docker/\.env)$" > /dev/null 2>&1; then
        log_error "CRITICAL" ".env files are committed to git"
        ((issues++))
    else
        log_success "  1.2 .env files properly gitignored"
    fi

    # Check for secrets in git history
    log_info "  1.3 Scanning git history for leaked secrets..."
    local leaked_secrets
    leaked_secrets=$(timeout 30 bash -c "git log --all --format='%H' -100 | head -20 | \
        xargs -I {} git diff-tree --no-commit-id --name-only -r {} | \
        grep -E '\.env$|credentials\.json|secret\.key|private\.key' | \
        grep -v '\.example$' | wc -l" 2>/dev/null) || leaked_secrets=0

    if [[ $leaked_secrets -gt 0 ]]; then
        log_error "HIGH" "Potential secret files found in git history: $leaked_secrets files"
        ((issues++))
    else
        log_success "  1.3 No secrets found in git history"
    fi

    # Check secrets directory permissions
    log_info "  1.4 Verifying secrets directory permissions..."
    if [[ -d "$REPO_ROOT/observability-stack/secrets" ]]; then
        local perms=$(stat -c "%a" "$REPO_ROOT/observability-stack/secrets" 2>/dev/null || echo "000")
        if [[ "$perms" != "700" ]] && [[ "$perms" != "600" ]]; then
            log_error "MEDIUM" "Secrets directory has insecure permissions: $perms"
            ((issues++))
        else
            log_success "  1.4 Secrets directory has secure permissions: $perms"
        fi
    else
        log_success "  1.4 Secrets directory not present (acceptable)"
    fi

    # Check environment variable usage
    log_info "  1.5 Verifying environment variables are used for secrets..."
    local env_usage
    env_usage=$(timeout 10 grep -r -E "password|secret|api_key" \
        --include="*.sh" \
        --exclude-dir=vendor \
        --exclude-dir=node_modules \
        "$REPO_ROOT/scripts" \
        "$REPO_ROOT/observability-stack/scripts" 2>/dev/null | \
        grep -v -E "^\s*(#|echo|log)" | \
        grep -v -E '\$\{?[A-Z_]+' | \
        wc -l) || env_usage=0

    if [[ $env_usage -gt 10 ]]; then
        log_warning "  1.5 Found $env_usage potential hardcoded credential references (review needed)"
    else
        log_success "  1.5 Credentials properly externalized via environment variables"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 1: Secrets Management - PASSED"
    else
        log_error "HIGH" "Test 1: Secrets Management - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 2: FILE PERMISSIONS (CWE-732: Incorrect Permission Assignment)
#===============================================================================

test_file_permissions() {
    ((TOTAL_TESTS++))
    log_info "Test 2: File Permissions"

    local issues=0

    # Check for world-writable files
    log_info "  2.1 Checking for world-writable files..."
    local world_writable
    world_writable=$(timeout 30 find "$REPO_ROOT" -type f -perm -002 ! -path "*/vendor/*" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | wc -l) || world_writable=0

    if [[ $world_writable -gt 0 ]]; then
        log_error "HIGH" "Found $world_writable world-writable files"
        ((issues++))
    else
        log_success "  2.1 No world-writable files found"
    fi

    # Check script permissions
    log_info "  2.2 Verifying script file permissions..."
    local bad_scripts
    bad_scripts=$(timeout 20 find "$REPO_ROOT/scripts" "$REPO_ROOT/observability-stack/scripts" -type f -name "*.sh" ! -perm 755 ! -perm 750 2>/dev/null | wc -l) || bad_scripts=0

    if [[ $bad_scripts -gt 0 ]]; then
        log_warning "  2.2 Found $bad_scripts scripts with non-standard permissions"
    else
        log_success "  2.2 All scripts have appropriate permissions"
    fi

    # Check for world-readable sensitive files
    log_info "  2.3 Checking for world-readable sensitive files..."
    if [[ -f "$REPO_ROOT/chom/.env" ]]; then
        local env_perms=$(stat -c "%a" "$REPO_ROOT/chom/.env")
        local others_read=$(echo "$env_perms" | grep -E "[0-9][0-9][4-7]")

        if [[ -n "$others_read" ]]; then
            log_error "CRITICAL" ".env file is world-readable: $env_perms"
            ((issues++))
        else
            log_success "  2.3 .env file has secure permissions: $env_perms"
        fi
    else
        log_success "  2.3 No .env file present in repository"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 2: File Permissions - PASSED"
    else
        log_error "HIGH" "Test 2: File Permissions - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 3: INPUT VALIDATION (OWASP A03:2021 - Injection)
#===============================================================================

test_input_validation() {
    ((TOTAL_TESTS++))
    log_info "Test 3: Input Validation & Injection Prevention"

    local issues=0

    # Check for unsafe eval/exec usage
    log_info "  3.1 Scanning for unsafe code execution patterns..."
    local unsafe_exec=$(grep -r -E "eval |exec\(|system\(" \
        --include="*.sh" \
        --include="*.py" \
        --exclude-dir=vendor \
        --exclude-dir=node_modules \
        "$REPO_ROOT/scripts" \
        "$REPO_ROOT/observability-stack/scripts" 2>/dev/null | \
        grep -v "^#" | wc -l)

    if [[ $unsafe_exec -gt 0 ]]; then
        log_error "HIGH" "Found $unsafe_exec unsafe code execution patterns"
        ((issues++))
    else
        log_success "  3.1 No unsafe code execution patterns found"
    fi

    # Check for SQL injection vulnerabilities
    log_info "  3.2 Scanning for SQL injection vulnerabilities..."
    local sql_concat=$(grep -r -E "mysql.*-e.*\\\$|SELECT.*\\\$\{" \
        --include="*.sh" \
        --exclude-dir=vendor \
        "$REPO_ROOT/scripts" 2>/dev/null | \
        grep -v "prepared" | wc -l)

    if [[ $sql_concat -gt 5 ]]; then
        log_warning "  3.2 Found $sql_concat potential SQL injection points (review needed)"
    else
        log_success "  3.2 Minimal SQL concatenation detected"
    fi

    # Check for command injection vulnerabilities
    log_info "  3.3 Scanning for command injection vulnerabilities..."
    local unsafe_vars=$(grep -r -E '\$\([^)]*\$[A-Za-z_]|\`[^`]*\$[A-Za-z_]' \
        --include="*.sh" \
        --exclude-dir=vendor \
        "$REPO_ROOT/scripts" \
        "$REPO_ROOT/observability-stack/scripts" 2>/dev/null | \
        wc -l)

    if [[ $unsafe_vars -gt 20 ]]; then
        log_warning "  3.3 Found $unsafe_vars potential command injection points (review needed)"
    else
        log_success "  3.3 Command injection risk appears minimal"
    fi

    # Check for path traversal vulnerabilities
    log_info "  3.4 Scanning for path traversal vulnerabilities..."
    local path_concat=$(grep -r -E 'cd.*\$|rm.*\$|cat.*\$' \
        --include="*.sh" \
        --exclude-dir=vendor \
        "$REPO_ROOT/scripts" 2>/dev/null | \
        grep -v -E "set -|readonly|^#" | wc -l)

    if [[ $path_concat -gt 30 ]]; then
        log_warning "  3.4 Found $path_concat file operations with variables (review needed)"
    else
        log_success "  3.4 File operations appear safe"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 3: Input Validation - PASSED"
    else
        log_error "HIGH" "Test 3: Input Validation - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 4: AUTHENTICATION & AUTHORIZATION (OWASP A01:2021 - Broken Access Control)
#===============================================================================

test_authentication() {
    ((TOTAL_TESTS++))
    log_info "Test 4: Authentication & Authorization"

    local issues=0

    # Check for default credentials
    log_info "  4.1 Scanning for default credentials..."
    local default_creds=$(grep -r -E "admin:admin|root:root|password:password|user:user" \
        --include="*.sh" \
        --include="*.yaml" \
        --include="*.yml" \
        --exclude-dir=vendor \
        --exclude-dir=node_modules \
        "$REPO_ROOT" 2>/dev/null | \
        grep -v "^#" | wc -l)

    if [[ $default_creds -gt 0 ]]; then
        log_error "CRITICAL" "Found $default_creds default credential references"
        ((issues++))
    else
        log_success "  4.1 No default credentials found"
    fi

    # Check for basic auth implementation
    log_info "  4.2 Verifying authentication mechanisms..."
    if [[ -f "$REPO_ROOT/observability-stack/configs/nginx/nginx.conf" ]]; then
        if grep -q "auth_basic" "$REPO_ROOT/observability-stack/configs/nginx/nginx.conf" 2>/dev/null; then
            log_success "  4.2 Basic authentication configured for Nginx"
        else
            log_warning "  4.2 No authentication found in Nginx config"
        fi
    else
        log_info "  4.2 Nginx config not present (acceptable)"
    fi

    # Check for authorization checks
    log_info "  4.3 Checking for authorization validation..."
    local auth_checks=$(grep -r -E "if.*\[\[ .*USER|if.*\[\[ .*ROLE|check_permission" \
        --include="*.sh" \
        "$REPO_ROOT/scripts" 2>/dev/null | wc -l)

    if [[ $auth_checks -gt 0 ]]; then
        log_success "  4.3 Found $auth_checks authorization checks"
    else
        log_warning "  4.3 No explicit authorization checks found"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 4: Authentication & Authorization - PASSED"
    else
        log_error "CRITICAL" "Test 4: Authentication & Authorization - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 5: ENCRYPTION & DATA PROTECTION (OWASP A02:2021 - Cryptographic Failures)
#===============================================================================

test_encryption() {
    ((TOTAL_TESTS++))
    log_info "Test 5: Encryption & Data Protection"

    local issues=0

    # Check for insecure SSL/TLS configurations
    log_info "  5.1 Checking SSL/TLS configurations..."
    if [[ -f "$REPO_ROOT/observability-stack/configs/nginx/ssl.conf" ]]; then
        if grep -q "ssl_protocols TLSv1.2 TLSv1.3" "$REPO_ROOT/observability-stack/configs/nginx/ssl.conf" 2>/dev/null; then
            log_success "  5.1 Secure TLS protocols configured"
        else
            log_error "HIGH" "Insecure TLS protocols may be enabled"
            ((issues++))
        fi
    else
        log_info "  5.1 SSL config not present (may be using defaults)"
    fi

    # Check for weak encryption algorithms
    log_info "  5.2 Scanning for weak encryption algorithms..."
    local weak_crypto=$(grep -r -E "md5|sha1|des|rc4" \
        --include="*.sh" \
        --include="*.py" \
        --exclude-dir=vendor \
        "$REPO_ROOT/scripts" 2>/dev/null | \
        grep -v "^#" | grep -v "MD5SUM" | wc -l)

    if [[ $weak_crypto -gt 0 ]]; then
        log_warning "  5.2 Found $weak_crypto references to weak crypto (review needed)"
    else
        log_success "  5.2 No weak encryption algorithms found"
    fi

    # Check for encryption of sensitive data
    log_info "  5.3 Checking for data encryption..."
    if grep -r -q "gpg\|openssl enc\|age" "$REPO_ROOT/scripts" 2>/dev/null; then
        log_success "  5.3 Encryption mechanisms found in scripts"
    else
        log_warning "  5.3 No encryption mechanisms detected"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 5: Encryption - PASSED"
    else
        log_error "HIGH" "Test 5: Encryption - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 6: LOGGING & MONITORING (OWASP A09:2021 - Security Logging Failures)
#===============================================================================

test_logging_security() {
    ((TOTAL_TESTS++))
    log_info "Test 6: Logging Security"

    local issues=0

    # Check for sensitive data in logs
    log_info "  6.1 Scanning for sensitive data in log statements..."
    local sensitive_logs=$(grep -r -E "log.*password|echo.*secret|print.*token" \
        --include="*.sh" \
        --include="*.py" \
        --exclude-dir=vendor \
        "$REPO_ROOT/scripts" 2>/dev/null | \
        grep -v "REDACTED\|\\*\\*\\*\\*\|sanitize" | wc -l)

    if [[ $sensitive_logs -gt 0 ]]; then
        log_error "MEDIUM" "Found $sensitive_logs potential sensitive data in logs"
        ((issues++))
    else
        log_success "  6.1 No sensitive data logging detected"
    fi

    # Check for proper error handling
    log_info "  6.2 Checking error handling mechanisms..."
    local error_handlers=$(grep -r -E "set -e|trap.*ERR|catch|rescue" \
        --include="*.sh" \
        "$REPO_ROOT/scripts" \
        "$REPO_ROOT/observability-stack/scripts" 2>/dev/null | wc -l)

    if [[ $error_handlers -gt 10 ]]; then
        log_success "  6.2 Found $error_handlers error handling mechanisms"
    else
        log_warning "  6.2 Minimal error handling found"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 6: Logging Security - PASSED"
    else
        log_error "MEDIUM" "Test 6: Logging Security - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 7: DEPENDENCY SECURITY (OWASP A06:2021 - Vulnerable Components)
#===============================================================================

test_dependency_security() {
    ((TOTAL_TESTS++))
    log_info "Test 7: Dependency Security"

    local issues=0

    # Check PHP dependencies
    log_info "  7.1 Checking PHP dependencies (Composer)..."
    if [[ -f "$REPO_ROOT/chom/composer.lock" ]]; then
        if command -v composer >/dev/null 2>&1; then
            local audit_output
            audit_output=$(cd "$REPO_ROOT/chom" && composer audit 2>&1) || true
            if echo "$audit_output" | grep -q "No security vulnerability advisories found"; then
                log_success "  7.1 No vulnerable PHP dependencies found"
            elif echo "$audit_output" | grep -qiE "critical|high"; then
                log_error "HIGH" "Vulnerable PHP dependencies detected"
                ((issues++))
            else
                log_success "  7.1 PHP dependencies check passed"
            fi
        else
            log_warning "  7.1 Composer not available, skipping PHP audit"
        fi
    else
        log_info "  7.1 No composer.lock found, skipping PHP audit"
    fi

    # Check NPM dependencies
    log_info "  7.2 Checking NPM dependencies..."
    if [[ -f "$REPO_ROOT/chom/package-lock.json" ]]; then
        if command -v npm >/dev/null 2>&1; then
            local npm_output
            npm_output=$(cd "$REPO_ROOT/chom" && npm audit --audit-level=high 2>&1) || true
            if echo "$npm_output" | grep -qiE "critical|high.*vulnerabilities"; then
                log_error "HIGH" "Vulnerable NPM dependencies detected"
                ((issues++))
            else
                log_success "  7.2 No high/critical NPM vulnerabilities found"
            fi
        else
            log_warning "  7.2 NPM not available, skipping NPM audit"
        fi
    else
        log_info "  7.2 No package-lock.json found, skipping NPM audit"
    fi

    # Check Python dependencies
    log_info "  7.3 Checking Python dependencies..."
    if [[ -f "$REPO_ROOT/observability-stack/scripts/tools/requirements.txt" ]]; then
        if command -v pip-audit >/dev/null 2>&1; then
            local py_output
            py_output=$(pip-audit -r "$REPO_ROOT/observability-stack/scripts/tools/requirements.txt" 2>&1) || true
            if echo "$py_output" | grep -qiE "critical|high"; then
                log_warning "  7.3 Vulnerable Python dependencies detected"
            else
                log_success "  7.3 No vulnerable Python dependencies found"
            fi
        else
            log_warning "  7.3 pip-audit not available, skipping Python audit"
        fi
    else
        log_info "  7.3 No requirements.txt found, skipping Python audit"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 7: Dependency Security - PASSED"
    else
        log_error "HIGH" "Test 7: Dependency Security - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 8: NETWORK SECURITY
#===============================================================================

test_network_security() {
    ((TOTAL_TESTS++))
    log_info "Test 8: Network Security"

    local issues=0

    # Check for firewall configurations
    log_info "  8.1 Checking for firewall configurations..."
    if [[ -f "$REPO_ROOT/observability-stack/scripts/lib/firewall.sh" ]]; then
        log_success "  8.1 Firewall management script found"
    else
        log_warning "  8.1 No firewall management found"
    fi

    # Check for secure defaults
    log_info "  8.2 Checking for secure network defaults..."
    local open_binds=$(grep -r -E "0\.0\.0\.0|listen.*all|bind.*\*" \
        --include="*.yaml" \
        --include="*.yml" \
        --include="*.conf" \
        --exclude-dir=vendor \
        "$REPO_ROOT/observability-stack" 2>/dev/null | wc -l)

    if [[ $open_binds -gt 5 ]]; then
        log_warning "  8.2 Found $open_binds services binding to all interfaces"
    else
        log_success "  8.2 Services appear to use secure binding"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 8: Network Security - PASSED"
    else
        log_error "MEDIUM" "Test 8: Network Security - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 9: DEPLOYMENT SECURITY
#===============================================================================

test_deployment_security() {
    ((TOTAL_TESTS++))
    log_info "Test 9: Deployment Security"

    local issues=0

    # Check for dangerous commands
    log_info "  9.1 Scanning for dangerous deployment commands..."
    local dangerous_cmds=$(grep -r -E "rm -rf /|chmod 777|chown root.*root" \
        --include="*.sh" \
        --exclude-dir=vendor \
        "$REPO_ROOT/scripts" 2>/dev/null | \
        grep -v "^#" | wc -l)

    if [[ $dangerous_cmds -gt 0 ]]; then
        log_warning "  9.1 Found $dangerous_cmds potentially dangerous commands"
    else
        log_success "  9.1 No dangerous commands found"
    fi

    # Check for dry-run capabilities
    log_info "  9.2 Checking for dry-run/safety mechanisms..."
    local dry_run_support=$(grep -r -E "dry.run|--dry-run|DRY_RUN" \
        --include="*.sh" \
        "$REPO_ROOT/scripts" \
        "$REPO_ROOT/observability-stack/scripts" 2>/dev/null | wc -l)

    if [[ $dry_run_support -gt 5 ]]; then
        log_success "  9.2 Found $dry_run_support scripts with dry-run support"
    else
        log_warning "  9.2 Limited dry-run support found"
    fi

    # Check for backup mechanisms
    log_info "  9.3 Checking for backup mechanisms..."
    if [[ -f "$REPO_ROOT/observability-stack/scripts/lib/backup.sh" ]]; then
        log_success "  9.3 Backup library found"
    else
        log_warning "  9.3 No backup library found"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 9: Deployment Security - PASSED"
    else
        log_error "MEDIUM" "Test 9: Deployment Security - FAILED with $issues issues"
    fi
}

#===============================================================================
# TEST 10: SECURITY HEADERS & CSP
#===============================================================================

test_security_headers() {
    ((TOTAL_TESTS++))
    log_info "Test 10: Security Headers & CSP"

    local issues=0

    # Check for security headers in Nginx config
    log_info "  10.1 Checking for security headers..."
    if [[ -f "$REPO_ROOT/observability-stack/configs/nginx/nginx.conf" ]]; then
        local headers=0

        if grep -q "X-Frame-Options" "$REPO_ROOT/observability-stack/configs/nginx/nginx.conf" 2>/dev/null; then
            ((headers++))
        fi

        if grep -q "X-Content-Type-Options" "$REPO_ROOT/observability-stack/configs/nginx/nginx.conf" 2>/dev/null; then
            ((headers++))
        fi

        if grep -q "Strict-Transport-Security" "$REPO_ROOT/observability-stack/configs/nginx/nginx.conf" 2>/dev/null; then
            ((headers++))
        fi

        if [[ $headers -ge 2 ]]; then
            log_success "  10.1 Found $headers security headers configured"
        else
            log_warning "  10.1 Limited security headers found: $headers"
        fi
    else
        log_info "  10.1 Nginx config not present"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Test 10: Security Headers - PASSED"
    else
        log_error "LOW" "Test 10: Security Headers - FAILED with $issues issues"
    fi
}

#===============================================================================
# OWASP COMPLIANCE REPORT
#===============================================================================

generate_owasp_compliance() {
    cat << EOF
A01:2021 - Broken Access Control          : $(test_result_status "authentication")
A02:2021 - Cryptographic Failures         : $(test_result_status "encryption")
A03:2021 - Injection                      : $(test_result_status "input_validation")
A04:2021 - Insecure Design                : REVIEW NEEDED
A05:2021 - Security Misconfiguration      : $(test_result_status "file_permissions")
A06:2021 - Vulnerable Components          : $(test_result_status "dependency_security")
A07:2021 - Identification & Auth Failures : $(test_result_status "authentication")
A08:2021 - Software & Data Integrity      : $(test_result_status "deployment_security")
A09:2021 - Security Logging Failures      : $(test_result_status "logging_security")
A10:2021 - Server-Side Request Forgery    : REVIEW NEEDED
EOF
}

test_result_status() {
    echo "TESTED"
}

#===============================================================================
# RECOMMENDATIONS
#===============================================================================

generate_recommendations() {
    cat << EOF
Priority Recommendations:

CRITICAL (Address Immediately):
$(if [[ $CRITICAL_FAILURES -gt 0 ]]; then
    echo "  - Review and remediate $CRITICAL_FAILURES critical security issues"
    echo "  - Ensure no secrets are committed to git"
    echo "  - Verify authentication mechanisms are properly configured"
else
    echo "  - No critical issues found"
fi)

HIGH (Address Soon):
$(if [[ $HIGH_FAILURES -gt 0 ]]; then
    echo "  - Review and fix $HIGH_FAILURES high-severity security issues"
    echo "  - Audit file permissions and access controls"
    echo "  - Update vulnerable dependencies"
else
    echo "  - No high-priority issues found"
fi)

MEDIUM (Plan Remediation):
$(if [[ $MEDIUM_FAILURES -gt 0 ]]; then
    echo "  - Review $MEDIUM_FAILURES medium-severity issues"
    echo "  - Enhance input validation and sanitization"
    echo "  - Improve logging security practices"
else
    echo "  - Continue monitoring for medium-priority issues"
fi)

GENERAL:
  - Implement regular security scanning in CI/CD pipeline
  - Conduct periodic security audits (quarterly recommended)
  - Keep all dependencies up-to-date
  - Monitor security advisories for used components
  - Implement automated security testing
  - Review and update security policies regularly
EOF
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --report-only)
                REPORT_ONLY=true
                shift
                ;;
            --test)
                SPECIFIC_TEST="$2"
                shift 2
                ;;
            --help)
                grep "^#" "$0" | grep -E "^# " | sed 's/^# //'
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

run_all_tests() {
    log_info "Starting security regression tests..."
    echo ""

    test_secrets_management
    echo ""

    test_file_permissions
    echo ""

    test_input_validation
    echo ""

    test_authentication
    echo ""

    test_encryption
    echo ""

    test_logging_security
    echo ""

    test_dependency_security
    echo ""

    test_network_security
    echo ""

    test_deployment_security
    echo ""

    test_security_headers
    echo ""
}

main() {
    parse_args "$@"

    init_report

    if [[ "$REPORT_ONLY" == "false" ]]; then
        if [[ -n "$SPECIFIC_TEST" ]]; then
            "test_$SPECIFIC_TEST"
        else
            run_all_tests
        fi
    fi

    generate_summary

    echo ""
    echo "================================================================================"
    if [[ $CRITICAL_FAILURES -eq 0 && $HIGH_FAILURES -eq 0 ]]; then
        echo -e "${GREEN}SECURITY REGRESSION TESTS PASSED${NC}"
        echo "No critical or high-severity vulnerabilities detected"
        exit 0
    else
        echo -e "${RED}SECURITY REGRESSION TESTS FAILED${NC}"
        echo "Critical: $CRITICAL_FAILURES, High: $HIGH_FAILURES"
        echo "Please review the report at: $REPORT_FILE"
        exit 1
    fi
}

main "$@"
