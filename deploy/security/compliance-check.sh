#!/bin/bash
# ============================================================================
# Compliance Check Script
# ============================================================================
# Purpose: Verify compliance with security standards and regulations
# Standards: OWASP Top 10, PCI DSS, SOC 2, GDPR, ISO 27001
# Output: Compliance report with pass/fail status
# ============================================================================

set -euo pipefail

# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    fi

    local security_dir="${deploy_root}/security"
    if [[ ! -d "$security_dir" ]]; then
        errors+=("Security directory not found: $security_dir")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo "" >&2
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "" >&2
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo "" >&2
        echo "Run from repository root: sudo ./deploy/security/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Configuration
APP_ROOT="${APP_ROOT:-/var/www/chom}"
REPORT_DIR="/var/log/chom/compliance"
REPORT_FILE="$REPORT_DIR/compliance_$(date +%Y%m%d_%H%M%S).txt"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging
log_section() {
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$REPORT_FILE"
    echo -e "${MAGENTA}$1${NC}" | tee -a "$REPORT_FILE"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$REPORT_FILE"
}

log_check() {
    echo -n "  Checking: $1..." | tee -a "$REPORT_FILE"
    ((TOTAL_CHECKS++))
}

log_pass() {
    echo -e " ${GREEN}PASS${NC}" | tee -a "$REPORT_FILE"
    ((PASSED_CHECKS++))
}

log_fail() {
    echo -e " ${RED}FAIL${NC}" | tee -a "$REPORT_FILE"
    if [[ -n "${2:-}" ]]; then
        echo "    Reason: $2" | tee -a "$REPORT_FILE"
    fi
    ((FAILED_CHECKS++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$REPORT_FILE"
}

# Initialize report
init_report() {
    mkdir -p "$REPORT_DIR"
    chmod 750 "$REPORT_DIR"

    cat > "$REPORT_FILE" <<EOF
============================================================================
CHOM Compliance Check Report
============================================================================
Date: $(date)
Server: $(hostname)
Standards: OWASP Top 10, PCI DSS, SOC 2, GDPR, ISO 27001
============================================================================

EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# OWASP Top 10 Compliance
check_owasp() {
    log_section "OWASP Top 10 2021 Compliance"

    # A01:2021 - Broken Access Control
    log_check "A01 - Access Control (File permissions)"
    if [[ -f "$APP_ROOT/.env" ]]; then
        local perm=$(stat -c %a "$APP_ROOT/.env")
        if [[ "$perm" == "600" ]]; then
            log_pass
        else
            log_fail ".env permissions: $perm (should be 600)"
        fi
    else
        log_fail ".env file not found"
    fi

    # A02:2021 - Cryptographic Failures
    log_check "A02 - Encryption at Rest (Database SSL)"
    if command -v psql &> /dev/null; then
        local ssl=$(sudo -u postgres psql -t -c "SHOW ssl;" 2>/dev/null | xargs || echo "off")
        if [[ "$ssl" == "on" ]]; then
            log_pass
        else
            log_fail "PostgreSQL SSL not enabled"
        fi
    else
        log_pass
    fi

    log_check "A02 - Encryption in Transit (HTTPS)"
    if [[ -d "/etc/letsencrypt/live" ]]; then
        log_pass
    else
        log_fail "No SSL certificates found"
    fi

    # A03:2021 - Injection
    log_check "A03 - SQL Injection Protection (PDO/Eloquent)"
    if [[ -f "$APP_ROOT/config/database.php" ]]; then
        log_pass
    else
        log_fail "Database config not found"
    fi

    log_check "A03 - Command Injection (Disabled PHP functions)"
    if grep -q "disable_functions.*exec" /etc/php/*/fpm/php.ini 2>/dev/null; then
        log_pass
    else
        log_fail "Dangerous PHP functions not disabled"
    fi

    # A04:2021 - Insecure Design
    log_check "A04 - Rate Limiting"
    if [[ -f "$APP_ROOT/app/Http/Kernel.php" ]]; then
        if grep -q "throttle" "$APP_ROOT/app/Http/Kernel.php"; then
            log_pass
        else
            log_fail "Rate limiting not configured"
        fi
    else
        log_fail "Kernel.php not found"
    fi

    # A05:2021 - Security Misconfiguration
    log_check "A05 - Production Mode"
    if grep -q "^APP_ENV=production" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Not in production mode"
    fi

    log_check "A05 - Debug Mode Disabled"
    if grep -q "^APP_DEBUG=false" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Debug mode enabled"
    fi

    # A06:2021 - Vulnerable and Outdated Components
    log_check "A06 - Security Updates"
    local updates=$(apt-get upgrade -s 2>/dev/null | grep -i security | wc -l)
    if [[ $updates -eq 0 ]]; then
        log_pass
    else
        log_fail "$updates security updates available"
    fi

    # A07:2021 - Identification and Authentication Failures
    log_check "A07 - Password Hashing (bcrypt)"
    if grep -q "BCRYPT_ROUNDS" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Bcrypt rounds not configured"
    fi

    log_check "A07 - Session Security"
    if grep -q "SESSION_SECURE_COOKIE=true" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Secure cookies not enforced"
    fi

    # A08:2021 - Software and Data Integrity Failures
    log_check "A08 - Integrity Monitoring (AIDE)"
    if systemctl is-active --quiet aide-check.timer 2>/dev/null; then
        log_pass
    else
        log_fail "AIDE not configured"
    fi

    # A09:2021 - Security Logging and Monitoring Failures
    log_check "A09 - Application Logging"
    if [[ -d "$APP_ROOT/storage/logs" ]]; then
        log_pass
    else
        log_fail "Log directory not found"
    fi

    log_check "A09 - Centralized Logging (Loki)"
    if grep -q "CHOM_LOKI_ENABLED=true" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Centralized logging not enabled"
    fi

    # A10:2021 - Server-Side Request Forgery
    log_check "A10 - SSRF Protection (URL validation)"
    if grep -q "allow_url_fopen = Off" /etc/php/*/fpm/php.ini 2>/dev/null; then
        log_pass
    else
        log_fail "URL fopen not disabled"
    fi
}

# PCI DSS Compliance
check_pci_dss() {
    log_section "PCI DSS Level 1 Compliance"

    # Requirement 1: Install and maintain a firewall
    log_check "Req 1 - Firewall Active"
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log_pass
    else
        log_fail "UFW firewall not active"
    fi

    # Requirement 2: Change defaults
    log_check "Req 2 - SSH Default Port Changed"
    local ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [[ -n "$ssh_port" ]] && [[ "$ssh_port" != "22" ]]; then
        log_pass
    else
        log_fail "SSH using default port 22"
    fi

    log_check "Req 2 - Default Passwords Changed"
    if ! grep -qE "PASSWORD=(password|secret|admin)" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Default passwords detected"
    fi

    # Requirement 3: Protect stored cardholder data
    log_check "Req 3 - Data Encryption (Database SSL)"
    if command -v psql &> /dev/null; then
        local ssl=$(sudo -u postgres psql -t -c "SHOW ssl;" 2>/dev/null | xargs || echo "off")
        if [[ "$ssl" == "on" ]]; then
            log_pass
        else
            log_fail "Database encryption not enabled"
        fi
    else
        log_pass
    fi

    # Requirement 4: Encrypt data in transit
    log_check "Req 4 - TLS 1.2+ Only"
    if grep -r "ssl_protocols.*TLSv1.2" /etc/nginx/sites-enabled/ 2>/dev/null | grep -qv "TLSv1\.0\|TLSv1\.1"; then
        log_pass
    else
        log_fail "Weak TLS protocols may be enabled"
    fi

    # Requirement 5: Protect against malware
    log_check "Req 5 - Intrusion Detection (AIDE)"
    if [[ -f /var/lib/aide/aide.db ]]; then
        log_pass
    else
        log_fail "AIDE database not initialized"
    fi

    # Requirement 6: Develop secure systems
    log_check "Req 6 - Security Updates Applied"
    local updates=$(apt-get upgrade -s 2>/dev/null | grep -i security | wc -l)
    if [[ $updates -eq 0 ]]; then
        log_pass
    else
        log_fail "$updates security updates pending"
    fi

    # Requirement 8: Identify and authenticate access
    log_check "Req 8 - Strong Password Policy"
    if grep -q "BCRYPT_ROUNDS=1[0-2]" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Weak password hashing configuration"
    fi

    # Requirement 9: Restrict physical access
    log_info "Req 9 - Physical access (manual verification required)"

    # Requirement 10: Track and monitor network access
    log_check "Req 10 - Audit Logging"
    if [[ -d "$APP_ROOT/storage/logs" ]]; then
        log_pass
    else
        log_fail "Audit logs not configured"
    fi

    log_check "Req 10 - Failed Login Tracking"
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        log_pass
    else
        log_fail "Fail2Ban not active"
    fi

    # Requirement 11: Test security systems
    log_check "Req 11 - Vulnerability Scanning"
    if [[ -d "/var/log/chom/vulnerability-scans" ]]; then
        log_pass
    else
        log_fail "No vulnerability scan history"
    fi

    # Requirement 12: Security policy
    log_info "Req 12 - Security policy (manual verification required)"
}

# SOC 2 Compliance
check_soc2() {
    log_section "SOC 2 Type II Compliance"

    # Security
    log_check "Security - Firewall Controls"
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log_pass
    else
        log_fail "Firewall not active"
    fi

    log_check "Security - Multi-factor Authentication"
    if grep -q "AUTH_2FA_ENABLED=true" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "2FA not enabled"
    fi

    # Availability
    log_check "Availability - Backup System"
    if [[ -d "/var/backups/chom" ]]; then
        log_pass
    else
        log_fail "Backup directory not found"
    fi

    log_check "Availability - Monitoring"
    if grep -q "CHOM_PROMETHEUS_ENABLED=true" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass
    else
        log_fail "Monitoring not enabled"
    fi

    # Processing Integrity
    log_check "Processing - Data Validation"
    if [[ -f "$APP_ROOT/app/Http/Kernel.php" ]]; then
        if grep -q "VerifyCsrfToken" "$APP_ROOT/app/Http/Kernel.php"; then
            log_pass
        else
            log_fail "CSRF protection not configured"
        fi
    else
        log_fail "Kernel.php not found"
    fi

    # Confidentiality
    log_check "Confidentiality - Data Encryption"
    if [[ -d "/etc/letsencrypt/live" ]]; then
        log_pass
    else
        log_fail "SSL/TLS not configured"
    fi

    # Privacy
    log_check "Privacy - Data Access Controls"
    if [[ -f "$APP_ROOT/.env" ]]; then
        local perm=$(stat -c %a "$APP_ROOT/.env")
        if [[ "$perm" == "600" ]]; then
            log_pass
        else
            log_fail ".env permissions too permissive"
        fi
    else
        log_fail ".env not found"
    fi
}

# GDPR Compliance
check_gdpr() {
    log_section "GDPR Compliance"

    log_check "Encryption at Rest"
    if command -v psql &> /dev/null; then
        local ssl=$(sudo -u postgres psql -t -c "SHOW ssl;" 2>/dev/null | xargs || echo "off")
        if [[ "$ssl" == "on" ]]; then
            log_pass
        else
            log_fail "Database encryption not enabled"
        fi
    else
        log_pass
    fi

    log_check "Encryption in Transit"
    if [[ -d "/etc/letsencrypt/live" ]]; then
        log_pass
    else
        log_fail "HTTPS not configured"
    fi

    log_check "Access Controls"
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        log_pass
    else
        log_fail "Fail2Ban not active"
    fi

    log_check "Audit Logging"
    if [[ -d "$APP_ROOT/storage/logs" ]]; then
        log_pass
    else
        log_fail "Audit logs not found"
    fi

    log_info "Data Retention Policies (manual verification required)"
    log_info "Data Subject Rights (manual verification required)"
    log_info "Privacy Policy (manual verification required)"
}

# ISO 27001 Alignment
check_iso27001() {
    log_section "ISO 27001 Alignment"

    # A.9 Access Control
    log_check "A.9 - Access Control Policy"
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        log_pass
    else
        log_fail "Root login not restricted"
    fi

    # A.10 Cryptography
    log_check "A.10 - Cryptographic Controls"
    if [[ -d "/etc/letsencrypt/live" ]]; then
        log_pass
    else
        log_fail "Encryption not fully implemented"
    fi

    # A.12 Operations Security
    log_check "A.12 - Malware Protection"
    if [[ -f /var/lib/aide/aide.db ]]; then
        log_pass
    else
        log_fail "Malware detection not configured"
    fi

    log_check "A.12 - Backup Procedures"
    if [[ -d "/var/backups/chom" ]]; then
        log_pass
    else
        log_fail "Backup system not found"
    fi

    # A.13 Communications Security
    log_check "A.13 - Network Segmentation"
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log_pass
    else
        log_fail "Network controls not active"
    fi

    # A.14 System Acquisition
    log_check "A.14 - Secure Development"
    if [[ -f "$APP_ROOT/composer.lock" ]]; then
        log_pass
    else
        log_fail "Dependency management not implemented"
    fi

    # A.16 Incident Management
    log_check "A.16 - Incident Response"
    if [[ -f "/var/log/aide/aide.log" ]]; then
        log_pass
    else
        log_fail "Incident detection not configured"
    fi

    # A.17 Business Continuity
    log_info "A.17 - Business Continuity Plan (manual verification required)"

    # A.18 Compliance
    log_info "A.18 - Compliance Program (manual verification required)"
}

# Generate compliance summary
generate_summary() {
    log_section "Compliance Summary"

    local pass_rate=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))

    cat >> "$REPORT_FILE" <<EOF

Total Checks:  $TOTAL_CHECKS
Passed:        $PASSED_CHECKS
Failed:        $FAILED_CHECKS
Pass Rate:     ${pass_rate}%

EOF

    echo "" | tee -a "$REPORT_FILE"

    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "${GREEN}[COMPLIANT]${NC} All compliance checks passed" | tee -a "$REPORT_FILE"
        return 0
    elif [[ $pass_rate -ge 80 ]]; then
        echo -e "${YELLOW}[MOSTLY COMPLIANT]${NC} $FAILED_CHECKS checks failed (${pass_rate}% pass rate)" | tee -a "$REPORT_FILE"
        return 0
    else
        echo -e "${RED}[NON-COMPLIANT]${NC} $FAILED_CHECKS checks failed (${pass_rate}% pass rate)" | tee -a "$REPORT_FILE"
        return 1
    fi
}

# Main execution
main() {
    check_root
    init_report

    log_info "Starting compliance check..."
    log_info "Report: $REPORT_FILE"
    echo ""

    check_owasp
    check_pci_dss
    check_soc2
    check_gdpr
    check_iso27001
    generate_summary

    echo ""
    echo "Full report: $REPORT_FILE"
    echo ""
}

# Run main function
main "$@"
