#!/bin/bash

###############################################################################
# CHOM Security Validation Script
# Validates security configuration and checks for common vulnerabilities
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
APP_PATH="/var/www/chom/current"
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Logging
log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

record_check() {
    local check_name="$1"
    local status="$2"
    local message="${3:-}"

    ((TOTAL_CHECKS++))

    if [[ "$status" == "PASS" ]]; then
        log_success "$check_name"
    elif [[ "$status" == "WARN" ]]; then
        log_warning "$check_name: $message"
    else
        ((FAILED_CHECKS++))
        log_error "$check_name: $message"
    fi
}

###############################################################################
# SECURITY CHECKS
###############################################################################

check_https_enforcement() {
    log_section "HTTPS Enforcement"

    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ "$app_url" == https://* ]]; then
        record_check "APP_URL uses HTTPS" "PASS"

        # Check if HTTP redirects to HTTPS
        local http_url="${app_url/https:/http:}"
        local redirect_location=$(curl -sSL -I -m 5 "$http_url" 2>/dev/null | grep -i "^location:" | head -1 || echo "")

        if echo "$redirect_location" | grep -qi "https://"; then
            record_check "HTTP to HTTPS redirect" "PASS"
        else
            record_check "HTTP to HTTPS redirect" "WARN" "No redirect detected"
        fi
    else
        record_check "HTTPS enforcement" "FAIL" "APP_URL not using HTTPS"
    fi

    # Check SSL certificate
    if [[ "$app_url" == https://* ]]; then
        local domain=$(echo "$app_url" | sed -e 's|https://||' -e 's|/.*||')
        local ssl_check=$(echo | timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "")

        if [[ -n "$ssl_check" ]]; then
            record_check "SSL certificate valid" "PASS"

            # Check expiration
            local expiry=$(echo "$ssl_check" | grep "notAfter" | cut -d'=' -f2)
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
            local current_epoch=$(date +%s)
            local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [[ "$days_remaining" -gt 30 ]]; then
                log_info "SSL certificate expires in $days_remaining days"
            elif [[ "$days_remaining" -gt 0 ]]; then
                record_check "SSL certificate expiration" "WARN" "Expires in $days_remaining days"
            else
                record_check "SSL certificate expiration" "FAIL" "Certificate has expired"
            fi
        else
            record_check "SSL certificate validation" "FAIL" "Cannot validate certificate"
        fi
    fi
}

check_security_headers() {
    log_section "Security Headers"

    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        return
    fi

    local headers=$(curl -sSL -I -m 5 "$app_url" 2>/dev/null || echo "")

    # X-Frame-Options
    if echo "$headers" | grep -qi "X-Frame-Options"; then
        local value=$(echo "$headers" | grep -i "X-Frame-Options" | cut -d':' -f2- | xargs)
        record_check "X-Frame-Options header" "PASS"
        log_info "  Value: $value"
    else
        record_check "X-Frame-Options header" "WARN" "Not set (clickjacking protection)"
    fi

    # X-Content-Type-Options
    if echo "$headers" | grep -qi "X-Content-Type-Options"; then
        record_check "X-Content-Type-Options header" "PASS"
    else
        record_check "X-Content-Type-Options header" "WARN" "Not set (MIME sniffing protection)"
    fi

    # X-XSS-Protection
    if echo "$headers" | grep -qi "X-XSS-Protection"; then
        record_check "X-XSS-Protection header" "PASS"
    else
        record_check "X-XSS-Protection header" "WARN" "Not set"
    fi

    # Strict-Transport-Security
    if echo "$headers" | grep -qi "Strict-Transport-Security"; then
        local value=$(echo "$headers" | grep -i "Strict-Transport-Security" | cut -d':' -f2- | xargs)
        record_check "Strict-Transport-Security header" "PASS"
        log_info "  Value: $value"
    else
        record_check "Strict-Transport-Security header" "WARN" "Not set (HSTS)"
    fi

    # Content-Security-Policy
    if echo "$headers" | grep -qi "Content-Security-Policy"; then
        record_check "Content-Security-Policy header" "PASS"
    else
        record_check "Content-Security-Policy header" "WARN" "Not set (CSP)"
    fi

    # Referrer-Policy
    if echo "$headers" | grep -qi "Referrer-Policy"; then
        record_check "Referrer-Policy header" "PASS"
    else
        record_check "Referrer-Policy header" "WARN" "Not set"
    fi
}

check_exposed_secrets() {
    log_section "Exposed Secrets Check"

    # Check logs for potential secrets
    local log_file="$APP_PATH/storage/logs/laravel.log"

    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $log_file" &>/dev/null; then
        # Check for common secret patterns
        local secret_patterns=("password" "api_key" "secret" "token" "credentials")

        for pattern in "${secret_patterns[@]}"; do
            local count=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -i '$pattern.*=.*['\''\"'].*['\''\"']' $log_file 2>/dev/null | grep -v 'REDACTED\|***' | wc -l" || echo "0")

            if [[ "$count" -eq 0 ]]; then
                record_check "No exposed $pattern in logs" "PASS"
            else
                record_check "Potential exposed $pattern in logs" "WARN" "Found $count occurrences"
            fi
        done
    fi

    # Check .env file not in public directory
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $APP_PATH/public/.env" &>/dev/null; then
        record_check ".env in public directory" "FAIL" ".env file exposed to web"
    else
        record_check ".env not in public directory" "PASS"
    fi
}

check_file_permissions() {
    log_section "File Permissions"

    # Check .env permissions
    local env_perms=$(ssh "$DEPLOY_USER@$APP_SERVER" "stat -c '%a' $APP_PATH/.env 2>/dev/null" || echo "000")

    if [[ "$env_perms" == "600" ]] || [[ "$env_perms" == "640" ]]; then
        record_check ".env file permissions" "PASS"
    else
        record_check ".env file permissions" "WARN" "Permissions are $env_perms (recommend 600)"
    fi

    # Check storage permissions
    local storage_perms=$(ssh "$DEPLOY_USER@$APP_SERVER" "stat -c '%a' $APP_PATH/storage 2>/dev/null" || echo "000")

    if [[ "$storage_perms" == "755" ]] || [[ "$storage_perms" == "775" ]]; then
        record_check "Storage directory permissions" "PASS"
    else
        record_check "Storage directory permissions" "WARN" "Permissions are $storage_perms"
    fi

    # Check for world-writable files
    local world_writable=$(ssh "$DEPLOY_USER@$APP_SERVER" "find $APP_PATH -type f -perm -002 2>/dev/null | wc -l" || echo "0")

    if [[ "$world_writable" -eq 0 ]]; then
        record_check "No world-writable files" "PASS"
    else
        record_check "World-writable files" "FAIL" "Found $world_writable files with insecure permissions"
    fi

    # Check for executable files in storage
    local executable_storage=$(ssh "$DEPLOY_USER@$APP_SERVER" "find $APP_PATH/storage -type f -executable 2>/dev/null | grep -v '.sh$' | wc -l" || echo "0")

    if [[ "$executable_storage" -eq 0 ]]; then
        record_check "No executable files in storage" "PASS"
    else
        record_check "Executable files in storage" "WARN" "Found $executable_storage executable files"
    fi
}

check_firewall() {
    log_section "Firewall Configuration"

    # Check if ufw is active
    if ssh "$DEPLOY_USER@$APP_SERVER" "sudo ufw status 2>/dev/null | grep -q 'Status: active'" &>/dev/null; then
        record_check "UFW firewall active" "PASS"

        # Check allowed ports
        local allowed_ports=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo ufw status numbered 2>/dev/null" || echo "")
        log_info "Firewall rules:"
        echo "$allowed_ports" | grep "ALLOW" | head -5 | while read -r line; do
            log_info "  $line"
        done
    else
        record_check "UFW firewall" "WARN" "Firewall not active or not using UFW"
    fi

    # Check iptables rules
    local iptables_rules=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo iptables -L -n 2>/dev/null | grep -c 'ACCEPT\|DROP\|REJECT'" || echo "0")

    if [[ "$iptables_rules" -gt 0 ]]; then
        log_info "iptables rules configured: $iptables_rules rules"
    fi
}

check_fail2ban() {
    log_section "Fail2Ban Intrusion Prevention"

    if ssh "$DEPLOY_USER@$APP_SERVER" "sudo systemctl is-active fail2ban &>/dev/null"; then
        record_check "Fail2Ban service running" "PASS"

        # Check active jails
        local jails=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo fail2ban-client status 2>/dev/null | grep 'Jail list' | cut -d':' -f2" || echo "")

        if [[ -n "$jails" ]]; then
            log_info "Active jails: $jails"

            # Check banned IPs
            local banned_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | grep -o '[0-9]*'" || echo "0")
            log_info "Currently banned IPs: $banned_count"
        fi
    else
        record_check "Fail2Ban" "WARN" "Fail2Ban not running"
    fi
}

check_selinux_apparmor() {
    log_section "Mandatory Access Control"

    # Check SELinux
    local selinux_status=$(ssh "$DEPLOY_USER@$APP_SERVER" "getenforce 2>/dev/null" || echo "disabled")

    if [[ "$selinux_status" == "Enforcing" ]]; then
        record_check "SELinux enforcing" "PASS"
    elif [[ "$selinux_status" == "Permissive" ]]; then
        record_check "SELinux permissive" "WARN" "SELinux in permissive mode"
    else
        # Check AppArmor
        if ssh "$DEPLOY_USER@$APP_SERVER" "sudo aa-status &>/dev/null"; then
            local apparmor_profiles=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo aa-status 2>/dev/null | grep 'profiles are loaded' | grep -o '[0-9]*'" || echo "0")

            if [[ "$apparmor_profiles" -gt 0 ]]; then
                record_check "AppArmor active" "PASS"
                log_info "$apparmor_profiles profiles loaded"
            else
                record_check "AppArmor" "WARN" "No profiles loaded"
            fi
        else
            record_check "Mandatory Access Control" "WARN" "Neither SELinux nor AppArmor active"
        fi
    fi
}

check_debug_mode() {
    log_section "Debug Mode Configuration"

    local app_debug=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_DEBUG=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ "$app_debug" == "false" ]]; then
        record_check "APP_DEBUG disabled" "PASS"
    else
        record_check "APP_DEBUG" "FAIL" "Debug mode enabled in production (security risk)"
    fi

    local app_env=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_ENV=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ "$app_env" == "production" ]]; then
        record_check "APP_ENV=production" "PASS"
    else
        record_check "APP_ENV" "WARN" "Not set to production (set to: $app_env)"
    fi
}

check_common_vulnerabilities() {
    log_section "Common Vulnerabilities"

    # Check for exposed git directory
    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -n "$app_url" ]]; then
        local git_exposed=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${app_url}/.git/config" 2>/dev/null || echo "000")

        if [[ "$git_exposed" == "404" ]] || [[ "$git_exposed" == "403" ]]; then
            record_check ".git directory not exposed" "PASS"
        else
            record_check ".git directory exposed" "FAIL" "Git directory accessible via web"
        fi

        # Check for exposed .env
        local env_exposed=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${app_url}/.env" 2>/dev/null || echo "000")

        if [[ "$env_exposed" == "404" ]] || [[ "$env_exposed" == "403" ]]; then
            record_check ".env not exposed" "PASS"
        else
            record_check ".env exposed" "FAIL" "Environment file accessible via web"
        fi

        # Check for exposed phpinfo
        local phpinfo_exposed=$(curl -sSL -m 5 "${app_url}/phpinfo.php" 2>/dev/null | grep -c "phpinfo()" || echo "0")

        if [[ "$phpinfo_exposed" -eq 0 ]]; then
            record_check "phpinfo() not exposed" "PASS"
        else
            record_check "phpinfo() exposed" "FAIL" "phpinfo.php file accessible"
        fi
    fi

    # Check for default credentials files
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $APP_PATH/database.sql" &>/dev/null; then
        record_check "database.sql file" "WARN" "SQL file found in application root"
    fi
}

check_csrf_protection() {
    log_section "CSRF Protection"

    # Check if CSRF middleware is enabled
    local csrf_middleware=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -r 'VerifyCsrfToken' $APP_PATH/app/Http/Kernel.php 2>/dev/null" || echo "")

    if [[ -n "$csrf_middleware" ]]; then
        record_check "CSRF middleware configured" "PASS"
    else
        record_check "CSRF middleware" "WARN" "Cannot verify CSRF protection"
    fi
}

check_sql_injection_protection() {
    log_section "SQL Injection Protection"

    # Check if using Eloquent ORM (provides protection)
    local eloquent_usage=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -r 'use Illuminate\\\\Database\\\\Eloquent\\\\Model' $APP_PATH/app/Models 2>/dev/null | wc -l" || echo "0")

    if [[ "$eloquent_usage" -gt 0 ]]; then
        record_check "Using Eloquent ORM" "PASS"
        log_info "$eloquent_usage models using Eloquent"
    fi

    # Check for raw queries (potential risk)
    local raw_queries=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -r 'DB::raw\\|->raw(' $APP_PATH/app 2>/dev/null | wc -l" || echo "0")

    if [[ "$raw_queries" -eq 0 ]]; then
        record_check "No raw SQL queries" "PASS"
    else
        record_check "Raw SQL queries" "WARN" "Found $raw_queries raw queries (review for SQL injection)"
    fi
}

check_session_security() {
    log_section "Session Security"

    # Check session driver
    local session_driver=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^SESSION_DRIVER=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ "$session_driver" == "redis" ]] || [[ "$session_driver" == "database" ]]; then
        record_check "Secure session driver" "PASS"
        log_info "Using: $session_driver"
    elif [[ "$session_driver" == "file" ]]; then
        record_check "Session driver" "WARN" "Using file driver (consider redis or database)"
    fi

    # Check session lifetime
    local session_lifetime=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^SESSION_LIFETIME=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ -n "$session_lifetime" ]]; then
        if [[ "$session_lifetime" -le 120 ]]; then
            record_check "Session lifetime" "PASS"
            log_info "Session lifetime: $session_lifetime minutes"
        else
            record_check "Session lifetime" "WARN" "Long session lifetime: $session_lifetime minutes"
        fi
    fi

    # Check secure cookies
    local session_secure=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^SESSION_SECURE_COOKIE=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ "$session_secure" == "true" ]]; then
        record_check "Secure session cookies" "PASS"
    else
        record_check "Secure session cookies" "WARN" "SESSION_SECURE_COOKIE not enabled"
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          CHOM Security Validation                             ║"
    echo "║          Checking security configuration...                   ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Run security checks
    check_https_enforcement
    check_security_headers
    check_exposed_secrets
    check_file_permissions
    check_firewall
    check_fail2ban
    check_selinux_apparmor
    check_debug_mode
    check_common_vulnerabilities
    check_csrf_protection
    check_sql_injection_protection
    check_session_security

    # Summary
    echo ""
    log_section "Security Validation Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All security checks passed!${NC}"
        echo -e "${GREEN}${BOLD}✓ No critical security issues detected${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ Security issues detected!${NC}"
        echo -e "${RED}${BOLD}✗ Review and fix issues above${NC}"
        exit 1
    fi
}

main "$@"
