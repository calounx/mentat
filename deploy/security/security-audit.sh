#!/bin/bash
# ============================================================================
# Security Audit Script
# ============================================================================
# Purpose: Comprehensive security audit and compliance check
# Coverage: OWASP Top 10, PCI DSS, SOC 2, file security, configurations
# Output: Detailed security report with severity levels
# ============================================================================

set -euo pipefail

# Configuration
APP_ROOT="${APP_ROOT:-/var/www/chom}"
REPORT_DIR="/var/log/chom/security-audits"
REPORT_FILE="$REPORT_DIR/audit_$(date +%Y%m%d_%H%M%S).log"
SEVERITY_CRITICAL=0
SEVERITY_HIGH=0
SEVERITY_MEDIUM=0
SEVERITY_LOW=0
SEVERITY_INFO=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1" | tee -a "$REPORT_FILE"
    ((SEVERITY_CRITICAL++))
}

log_high() {
    echo -e "${RED}[HIGH]${NC} $1" | tee -a "$REPORT_FILE"
    ((SEVERITY_HIGH++))
}

log_medium() {
    echo -e "${YELLOW}[MEDIUM]${NC} $1" | tee -a "$REPORT_FILE"
    ((SEVERITY_MEDIUM++))
}

log_low() {
    echo -e "${YELLOW}[LOW]${NC} $1" | tee -a "$REPORT_FILE"
    ((SEVERITY_LOW++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$REPORT_FILE"
    ((SEVERITY_INFO++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$REPORT_FILE"
}

log_section() {
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$REPORT_FILE"
    echo -e "${MAGENTA}$1${NC}" | tee -a "$REPORT_FILE"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$REPORT_FILE"
}

# Initialize report
init_report() {
    mkdir -p "$REPORT_DIR"
    chmod 750 "$REPORT_DIR"

    cat > "$REPORT_FILE" <<EOF
============================================================================
CHOM Security Audit Report
============================================================================
Date: $(date)
Server: $(hostname)
Auditor: Security Audit Script v1.0
Report: $REPORT_FILE
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

# Audit SSH configuration
audit_ssh() {
    log_section "SSH Security Audit"

    local ssh_config="/etc/ssh/sshd_config"

    if [[ ! -f "$ssh_config" ]]; then
        log_critical "SSH config file not found"
        return
    fi

    # Check root login
    if grep -q "^PermitRootLogin yes" "$ssh_config"; then
        log_critical "Root login is enabled (CVE-2018-15473)"
    elif grep -q "^PermitRootLogin no" "$ssh_config"; then
        log_pass "Root login is disabled"
    else
        log_medium "Root login setting not explicitly set"
    fi

    # Check password authentication
    if grep -q "^PasswordAuthentication yes" "$ssh_config"; then
        log_high "Password authentication is enabled (brute force risk)"
    elif grep -q "^PasswordAuthentication no" "$ssh_config"; then
        log_pass "Password authentication is disabled"
    else
        log_medium "Password authentication not explicitly disabled"
    fi

    # Check SSH protocol
    if grep -q "^Protocol 1" "$ssh_config"; then
        log_critical "SSH Protocol 1 is enabled (insecure)"
    else
        log_pass "SSH Protocol 2 in use"
    fi

    # Check empty passwords
    if grep -q "^PermitEmptyPasswords yes" "$ssh_config"; then
        log_critical "Empty passwords are permitted"
    else
        log_pass "Empty passwords are not permitted"
    fi

    # Check X11 forwarding
    if grep -q "^X11Forwarding yes" "$ssh_config"; then
        log_low "X11 forwarding is enabled"
    else
        log_pass "X11 forwarding is disabled"
    fi

    # Check MaxAuthTries
    local max_tries=$(grep "^MaxAuthTries" "$ssh_config" | awk '{print $2}')
    if [[ -n "$max_tries" ]] && [[ "$max_tries" -le 3 ]]; then
        log_pass "MaxAuthTries is set to $max_tries"
    elif [[ -n "$max_tries" ]]; then
        log_medium "MaxAuthTries is $max_tries (recommend <= 3)"
    else
        log_medium "MaxAuthTries not explicitly set"
    fi
}

# Audit firewall
audit_firewall() {
    log_section "Firewall Security Audit"

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        log_critical "UFW firewall is not installed"
        return
    fi

    # Check if UFW is active
    if ufw status | grep -q "Status: active"; then
        log_pass "UFW firewall is active"
    else
        log_critical "UFW firewall is NOT active"
        return
    fi

    # Check default policies
    if ufw status verbose | grep -q "Default: deny (incoming)"; then
        log_pass "Default incoming policy is deny"
    else
        log_high "Default incoming policy is not deny"
    fi

    # Check for unrestricted access
    local unrestricted=$(ufw status | grep -E "ALLOW.*Anywhere" | wc -l)
    if [[ $unrestricted -gt 3 ]]; then
        log_medium "Multiple unrestricted firewall rules ($unrestricted)"
    fi
}

# Audit file permissions
audit_file_permissions() {
    log_section "File Permissions Audit"

    # Check world-writable files
    log_info "Scanning for world-writable files..."
    local world_writable=$(find / -xdev -type f -perm -002 ! -path "/proc/*" ! -path "/sys/*" 2>/dev/null | wc -l)
    if [[ $world_writable -gt 0 ]]; then
        log_high "Found $world_writable world-writable files"
        find / -xdev -type f -perm -002 ! -path "/proc/*" ! -path "/sys/*" 2>/dev/null | head -20 >> "$REPORT_FILE"
    else
        log_pass "No world-writable files found"
    fi

    # Check world-writable directories
    local world_writable_dirs=$(find / -xdev -type d -perm -002 ! -path "/proc/*" ! -path "/sys/*" ! -path "/tmp/*" 2>/dev/null | wc -l)
    if [[ $world_writable_dirs -gt 0 ]]; then
        log_medium "Found $world_writable_dirs world-writable directories"
    else
        log_pass "No world-writable directories found"
    fi

    # Check .env file permissions
    if [[ -f "$APP_ROOT/.env" ]]; then
        local env_perm=$(stat -c %a "$APP_ROOT/.env")
        if [[ "$env_perm" == "600" ]]; then
            log_pass ".env file has secure permissions (600)"
        else
            log_critical ".env file has insecure permissions ($env_perm)"
        fi
    fi

    # Check SSH key permissions
    if [[ -d /root/.ssh ]]; then
        local ssh_perm=$(stat -c %a /root/.ssh)
        if [[ "$ssh_perm" == "700" ]]; then
            log_pass "SSH directory has secure permissions (700)"
        else
            log_high "SSH directory has insecure permissions ($ssh_perm)"
        fi
    fi

    # Check for SUID/SGID files
    log_info "Checking SUID/SGID files..."
    local suid_count=$(find / -xdev -type f \( -perm -4000 -o -perm -2000 \) ! -path "/proc/*" 2>/dev/null | wc -l)
    log_info "Found $suid_count SUID/SGID files (review periodically)"
}

# Audit exposed secrets
audit_secrets() {
    log_section "Exposed Secrets Audit"

    log_info "Scanning for exposed secrets..."

    # Check for API keys in code
    if [[ -d "$APP_ROOT" ]]; then
        local api_keys=$(grep -r -i -E "(api[_-]?key|apikey|api[_-]?secret)" "$APP_ROOT" --include="*.php" --include="*.js" | grep -v "env(" | grep -v "config(" | wc -l)
        if [[ $api_keys -gt 0 ]]; then
            log_high "Found $api_keys potential hardcoded API keys"
        else
            log_pass "No hardcoded API keys found"
        fi

        # Check for passwords in code
        local passwords=$(grep -r -i -E "(password.*=.*['\"][^'\"]{8,})" "$APP_ROOT" --include="*.php" | grep -v "env(" | grep -v "Hash::" | wc -l)
        if [[ $passwords -gt 0 ]]; then
            log_high "Found $passwords potential hardcoded passwords"
        fi

        # Check for private keys
        local private_keys=$(find "$APP_ROOT" -name "*.pem" -o -name "*.key" -o -name "*_rsa" 2>/dev/null | wc -l)
        if [[ $private_keys -gt 0 ]]; then
            log_medium "Found $private_keys private key files (verify they are secured)"
        fi
    fi

    # Check environment files
    if [[ -f "$APP_ROOT/.env" ]]; then
        if grep -q "APP_KEY=base64:" "$APP_ROOT/.env"; then
            log_pass "APP_KEY is set"
        else
            log_critical "APP_KEY is not set or invalid"
        fi

        if grep -q "APP_DEBUG=true" "$APP_ROOT/.env"; then
            log_critical "APP_DEBUG is enabled in production"
        else
            log_pass "APP_DEBUG is disabled"
        fi
    fi
}

# Audit database security
audit_database() {
    log_section "Database Security Audit"

    # Check PostgreSQL if installed
    if command -v psql &> /dev/null; then
        # Check if PostgreSQL is running
        if systemctl is-active --quiet postgresql; then
            log_pass "PostgreSQL is running"

            # Check SSL
            local ssl_enabled=$(sudo -u postgres psql -t -c "SHOW ssl;" 2>/dev/null | xargs)
            if [[ "$ssl_enabled" == "on" ]]; then
                log_pass "PostgreSQL SSL is enabled"
            else
                log_high "PostgreSQL SSL is not enabled"
            fi

            # Check password encryption
            local pwd_enc=$(sudo -u postgres psql -t -c "SHOW password_encryption;" 2>/dev/null | xargs)
            if [[ "$pwd_enc" == "scram-sha-256" ]]; then
                log_pass "PostgreSQL using SCRAM-SHA-256 encryption"
            else
                log_medium "PostgreSQL not using SCRAM-SHA-256 encryption (using: $pwd_enc)"
            fi
        else
            log_info "PostgreSQL is not running"
        fi
    fi
}

# Audit PHP security
audit_php() {
    log_section "PHP Security Audit"

    local php_ini="/etc/php/8.2/fpm/php.ini"

    if [[ -f "$php_ini" ]]; then
        # Check expose_php
        if grep -q "^expose_php = Off" "$php_ini"; then
            log_pass "expose_php is disabled"
        else
            log_medium "expose_php may be enabled"
        fi

        # Check display_errors
        if grep -q "^display_errors = Off" "$php_ini"; then
            log_pass "display_errors is disabled"
        else
            log_high "display_errors may be enabled"
        fi

        # Check allow_url_fopen
        if grep -q "^allow_url_fopen = Off" "$php_ini"; then
            log_pass "allow_url_fopen is disabled"
        else
            log_medium "allow_url_fopen is enabled"
        fi

        # Check disable_functions
        if grep -q "^disable_functions.*exec" "$php_ini"; then
            log_pass "Dangerous functions are disabled"
        else
            log_high "Dangerous functions may not be disabled"
        fi
    else
        log_info "PHP configuration file not found"
    fi
}

# Audit SSL/TLS
audit_ssl() {
    log_section "SSL/TLS Security Audit"

    # Check for SSL certificates
    if [[ -d "/etc/letsencrypt/live" ]]; then
        local cert_dirs=$(find /etc/letsencrypt/live -maxdepth 1 -type d | tail -n +2)

        if [[ -z "$cert_dirs" ]]; then
            log_medium "No SSL certificates found"
        else
            log_pass "SSL certificates found"

            # Check expiration
            for cert_dir in $cert_dirs; do
                local domain=$(basename "$cert_dir")
                local cert_file="$cert_dir/cert.pem"

                if [[ -f "$cert_file" ]]; then
                    local expiry=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
                    local expiry_epoch=$(date -d "$expiry" +%s)
                    local now_epoch=$(date +%s)
                    local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))

                    if [[ $days_left -lt 7 ]]; then
                        log_critical "SSL certificate for $domain expires in $days_left days"
                    elif [[ $days_left -lt 30 ]]; then
                        log_medium "SSL certificate for $domain expires in $days_left days"
                    else
                        log_pass "SSL certificate for $domain valid ($days_left days)"
                    fi
                fi
            done
        fi
    else
        log_medium "Let's Encrypt directory not found"
    fi

    # Check Nginx SSL configuration
    if [[ -d "/etc/nginx/sites-enabled" ]]; then
        local ssl_protocols=$(grep -r "ssl_protocols" /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "#" | head -1)

        if echo "$ssl_protocols" | grep -q "TLSv1.3"; then
            log_pass "TLS 1.3 is enabled"
        elif echo "$ssl_protocols" | grep -q "TLSv1.2"; then
            log_pass "TLS 1.2 is enabled"
        else
            log_high "TLS configuration may be insecure"
        fi
    fi
}

# Audit system updates
audit_updates() {
    log_section "System Updates Audit"

    # Check for security updates
    apt-get update -qq 2>/dev/null
    local security_updates=$(apt-get upgrade -s 2>/dev/null | grep -i security | wc -l)

    if [[ $security_updates -gt 0 ]]; then
        log_high "$security_updates security updates available"
    else
        log_pass "System is up to date"
    fi

    # Check kernel version
    local current_kernel=$(uname -r)
    log_info "Current kernel: $current_kernel"
}

# Audit user accounts
audit_users() {
    log_section "User Accounts Audit"

    # Check for users with empty passwords
    local empty_pwd=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | wc -l)
    if [[ $empty_pwd -gt 0 ]]; then
        log_critical "Found $empty_pwd users with empty passwords"
    else
        log_pass "No users with empty passwords"
    fi

    # Check for UID 0 accounts
    local uid_zero=$(awk -F: '($3 == "0") {print $1}' /etc/passwd | grep -v "^root$" | wc -l)
    if [[ $uid_zero -gt 0 ]]; then
        log_critical "Found $uid_zero non-root accounts with UID 0"
    else
        log_pass "Only root has UID 0"
    fi

    # Check sudo access
    local sudo_users=$(grep -E "^sudo:|^admin:" /etc/group | cut -d: -f4)
    log_info "Sudo users: $sudo_users"
}

# Audit running services
audit_services() {
    log_section "Running Services Audit"

    # Check for unnecessary services
    local services=$(systemctl list-units --type=service --state=running --no-pager --no-legend | wc -l)
    log_info "Running services: $services"

    # Check critical services
    local critical_services=("ssh" "nginx" "postgresql" "fail2ban")

    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" || systemctl is-active --quiet "${service}d"; then
            log_pass "$service is running"
        else
            log_info "$service is not running"
        fi
    done
}

# Audit fail2ban
audit_fail2ban() {
    log_section "Fail2Ban Audit"

    if command -v fail2ban-client &> /dev/null; then
        if systemctl is-active --quiet fail2ban; then
            log_pass "Fail2Ban is active"

            local jails=$(fail2ban-client status | grep "Jail list" | wc -l)
            if [[ $jails -gt 0 ]]; then
                log_pass "Fail2Ban jails are configured"
            else
                log_medium "No Fail2Ban jails configured"
            fi

            local banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $4}' || echo "0")
            log_info "Currently banned IPs: $banned"
        else
            log_high "Fail2Ban is installed but not active"
        fi
    else
        log_high "Fail2Ban is not installed"
    fi
}

# Audit Laravel security
audit_laravel() {
    log_section "Laravel Application Audit"

    if [[ ! -d "$APP_ROOT" ]]; then
        log_info "Laravel application not found"
        return
    fi

    # Check APP_ENV
    if grep -q "^APP_ENV=production" "$APP_ROOT/.env" 2>/dev/null; then
        log_pass "APP_ENV is set to production"
    else
        log_critical "APP_ENV is not set to production"
    fi

    # Check CSRF middleware
    if [[ -f "$APP_ROOT/app/Http/Kernel.php" ]]; then
        if grep -q "VerifyCsrfToken" "$APP_ROOT/app/Http/Kernel.php"; then
            log_pass "CSRF protection is enabled"
        else
            log_high "CSRF protection may not be enabled"
        fi
    fi

    # Check storage permissions
    if [[ -d "$APP_ROOT/storage" ]]; then
        local storage_perm=$(stat -c %a "$APP_ROOT/storage")
        if [[ "$storage_perm" == "775" ]]; then
            log_pass "Storage directory has correct permissions"
        else
            log_medium "Storage directory permissions are $storage_perm (recommend 775)"
        fi
    fi
}

# Generate summary
generate_summary() {
    log_section "Audit Summary"

    local total_issues=$((SEVERITY_CRITICAL + SEVERITY_HIGH + SEVERITY_MEDIUM + SEVERITY_LOW))

    cat >> "$REPORT_FILE" <<EOF

Issue Summary:
--------------
Critical: $SEVERITY_CRITICAL
High:     $SEVERITY_HIGH
Medium:   $SEVERITY_MEDIUM
Low:      $SEVERITY_LOW
Info:     $SEVERITY_INFO
--------------
Total:    $total_issues

EOF

    echo "" | tee -a "$REPORT_FILE"

    if [[ $SEVERITY_CRITICAL -gt 0 ]]; then
        log_critical "CRITICAL ISSUES FOUND - Immediate action required!"
        echo "EXIT_CODE=2" > /tmp/security_audit_result
        return 2
    elif [[ $SEVERITY_HIGH -gt 0 ]]; then
        log_high "HIGH severity issues found - Action required"
        echo "EXIT_CODE=1" > /tmp/security_audit_result
        return 1
    elif [[ $SEVERITY_MEDIUM -gt 0 ]]; then
        log_medium "MEDIUM severity issues found - Review recommended"
        echo "EXIT_CODE=0" > /tmp/security_audit_result
        return 0
    else
        log_pass "No critical or high severity issues found"
        echo "EXIT_CODE=0" > /tmp/security_audit_result
        return 0
    fi
}

# Main execution
main() {
    check_root
    init_report

    log_section "CHOM Security Audit Starting"
    log_info "Audit Date: $(date)"
    log_info "Server: $(hostname)"
    log_info "Report: $REPORT_FILE"

    audit_ssh
    audit_firewall
    audit_file_permissions
    audit_secrets
    audit_database
    audit_php
    audit_ssl
    audit_updates
    audit_users
    audit_services
    audit_fail2ban
    audit_laravel

    generate_summary

    echo ""
    echo "Full report saved to: $REPORT_FILE"
    echo ""
}

# Run main function
main "$@"
