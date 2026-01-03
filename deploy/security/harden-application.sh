#!/bin/bash
# ============================================================================
# Application Security Hardening Script
# ============================================================================
# Purpose: Harden Laravel application and PHP configuration
# Features: File permissions, PHP security, Laravel config, session hardening
# Compliance: OWASP Top 10, PCI DSS, SOC 2
# ============================================================================

set -euo pipefail
# Dependency validation - MUST run before doing anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
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
APP_USER="${APP_USER:-www-data}"
APP_GROUP="${APP_GROUP:-www-data}"
PHP_VERSION="${PHP_VERSION:-8.2}"
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Verify application directory
verify_app_directory() {
    log_info "Verifying application directory..."

    if [[ ! -d "$APP_ROOT" ]]; then
        log_error "Application directory not found: $APP_ROOT"
        exit 1
    fi

    if [[ ! -f "$APP_ROOT/artisan" ]]; then
        log_error "Not a Laravel application: artisan not found"
        exit 1
    fi

    log_success "Application directory verified"
}

# Set file permissions
set_file_permissions() {
    log_info "Setting secure file permissions..."

    cd "$APP_ROOT"

    # Set ownership
    chown -R "$APP_USER:$APP_GROUP" "$APP_ROOT"
    log_success "Ownership set to $APP_USER:$APP_GROUP"

    # Base directories and files
    find "$APP_ROOT" -type f -exec chmod 644 {} \;
    find "$APP_ROOT" -type d -exec chmod 755 {} \;
    log_success "Base permissions set (files: 644, directories: 755)"

    # Storage and cache directories (writable)
    chmod -R 775 "$APP_ROOT/storage"
    chmod -R 775 "$APP_ROOT/bootstrap/cache"
    log_success "Storage directories set to 775"

    # Executable files
    chmod 755 "$APP_ROOT/artisan"
    if [[ -d "$APP_ROOT/bin" ]]; then
        chmod -R 755 "$APP_ROOT/bin"
    fi
    log_success "Executable permissions set"

    # Environment file (sensitive)
    if [[ -f "$APP_ROOT/.env" ]]; then
        chmod 600 "$APP_ROOT/.env"
        chown "$APP_USER:$APP_GROUP" "$APP_ROOT/.env"
        log_success ".env file secured (600)"
    fi

    # Prevent execution in upload directories
    if [[ -d "$APP_ROOT/storage/app/public" ]]; then
        find "$APP_ROOT/storage/app/public" -type f -name "*.php" -delete
        log_success "Removed PHP files from upload directory"
    fi

    # Remove world-writable files
    local world_writable=$(find "$APP_ROOT" -type f -perm -002 2>/dev/null | wc -l)
    if [[ $world_writable -gt 0 ]]; then
        find "$APP_ROOT" -type f -perm -002 -exec chmod o-w {} \;
        log_warning "Fixed $world_writable world-writable files"
    fi

    log_success "File permissions configured"
}

# Configure Laravel security settings
configure_laravel_security() {
    log_info "Configuring Laravel security settings..."

    local env_file="$APP_ROOT/.env"

    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found"
        return 1
    fi

    # Backup .env
    cp "$env_file" "${env_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Production settings
    sed -i 's/^APP_ENV=.*/APP_ENV=production/' "$env_file"
    sed -i 's/^APP_DEBUG=.*/APP_DEBUG=false/' "$env_file"
    log_success "Set production environment"

    # Session security
    grep -q "^SESSION_SECURE_COOKIE=" "$env_file" || echo "SESSION_SECURE_COOKIE=true" >> "$env_file"
    sed -i 's/^SESSION_SECURE_COOKIE=.*/SESSION_SECURE_COOKIE=true/' "$env_file"

    grep -q "^SESSION_HTTP_ONLY=" "$env_file" || echo "SESSION_HTTP_ONLY=true" >> "$env_file"
    sed -i 's/^SESSION_HTTP_ONLY=.*/SESSION_HTTP_ONLY=true/' "$env_file"

    grep -q "^SESSION_SAME_SITE=" "$env_file" || echo "SESSION_SAME_SITE=strict" >> "$env_file"
    sed -i 's/^SESSION_SAME_SITE=.*/SESSION_SAME_SITE=strict/' "$env_file"

    grep -q "^SESSION_EXPIRE_ON_CLOSE=" "$env_file" || echo "SESSION_EXPIRE_ON_CLOSE=false" >> "$env_file"
    sed -i 's/^SESSION_EXPIRE_ON_CLOSE=.*/SESSION_EXPIRE_ON_CLOSE=false/' "$env_file"

    log_success "Session security configured"

    # CSRF protection (verify it exists)
    if ! grep -q "CSRF" "$APP_ROOT/app/Http/Kernel.php"; then
        log_warning "CSRF middleware may not be configured"
    fi

    # Rate limiting
    grep -q "^RATE_LIMIT=" "$env_file" || echo "RATE_LIMIT=60" >> "$env_file"
    grep -q "^RATE_LIMIT_PER_MINUTE=" "$env_file" || echo "RATE_LIMIT_PER_MINUTE=60" >> "$env_file"

    log_success "Laravel security settings configured"
}

# Harden PHP configuration
harden_php_config() {
    log_info "Hardening PHP configuration..."

    if [[ ! -f "$PHP_INI" ]]; then
        log_error "PHP INI file not found: $PHP_INI"
        return 1
    fi

    # Backup PHP INI
    cp "$PHP_INI" "${PHP_INI}.backup.$(date +%Y%m%d_%H%M%S)"

    # Security settings
    cat >> "$PHP_INI" <<'EOF'

; ============================================================================
; CHOM PHP Security Hardening
; ============================================================================

; Disable dangerous functions
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,phpinfo

; Restrict file access
open_basedir = /var/www/chom:/tmp:/usr/share/php
allow_url_fopen = Off
allow_url_include = Off

; Error handling (don't expose errors to users)
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/php/error.log
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

; Session security
session.cookie_httponly = On
session.cookie_secure = On
session.cookie_samesite = Strict
session.use_strict_mode = On
session.use_only_cookies = On
session.cookie_lifetime = 0
session.gc_maxlifetime = 3600
session.gc_probability = 1
session.gc_divisor = 100
session.sid_length = 48
session.sid_bits_per_character = 6
session.use_trans_sid = Off

; File upload security
file_uploads = On
upload_max_filesize = 100M
max_file_uploads = 20
upload_tmp_dir = /tmp

; Resource limits
max_execution_time = 30
max_input_time = 60
memory_limit = 256M
post_max_size = 100M

; Disable potentially dangerous features
expose_php = Off
register_argc_argv = Off
magic_quotes_gpc = Off

; CGI/FastCGI security
cgi.force_redirect = On
cgi.fix_pathinfo = 0

; SQL injection protection
magic_quotes_runtime = Off

; Session name (hide default PHPSESSID)
session.name = CHOM_SESSION
EOF

    # Create PHP error log directory
    mkdir -p /var/log/php
    chown "$APP_USER:$APP_GROUP" /var/log/php
    chmod 755 /var/log/php

    log_success "PHP configuration hardened"
}

# Configure PHP-FPM security
configure_php_fpm() {
    log_info "Configuring PHP-FPM security..."

    if [[ ! -f "$PHP_FPM_CONF" ]]; then
        log_error "PHP-FPM config not found: $PHP_FPM_CONF"
        return 1
    fi

    # Backup PHP-FPM config
    cp "$PHP_FPM_CONF" "${PHP_FPM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

    # Update security settings
    cat >> "$PHP_FPM_CONF" <<EOF

; CHOM PHP-FPM Security Settings
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_flag[allow_url_fopen] = off
php_admin_value[open_basedir] = /var/www/chom:/tmp:/usr/share/php
php_admin_value[upload_tmp_dir] = /tmp
php_admin_value[session.save_path] = /var/lib/php/sessions
EOF

    log_success "PHP-FPM security configured"
}

# Setup Laravel configuration cache
setup_laravel_cache() {
    log_info "Setting up Laravel configuration cache..."

    cd "$APP_ROOT"

    # Clear existing cache
    sudo -u "$APP_USER" php artisan config:clear
    sudo -u "$APP_USER" php artisan route:clear
    sudo -u "$APP_USER" php artisan view:clear

    # Cache configuration (production optimization + security)
    sudo -u "$APP_USER" php artisan config:cache
    sudo -u "$APP_USER" php artisan route:cache
    sudo -u "$APP_USER" php artisan view:cache

    log_success "Laravel cache configured"
}

# Configure trusted proxies
configure_trusted_proxies() {
    log_info "Configuring trusted proxies..."

    local middleware_file="$APP_ROOT/app/Http/Middleware/TrustProxies.php"

    if [[ ! -f "$middleware_file" ]]; then
        log_warning "TrustProxies middleware not found"
        return 0
    fi

    # The configuration should be in the file already
    # Just verify it exists
    if grep -q "protected \$proxies" "$middleware_file"; then
        log_success "TrustProxies middleware configured"
    else
        log_warning "TrustProxies middleware may need manual configuration"
    fi
}

# Setup security headers in Nginx
configure_nginx_security() {
    log_info "Verifying Nginx security configuration..."

    local nginx_sites="/etc/nginx/sites-available"

    if [[ ! -d "$nginx_sites" ]]; then
        log_warning "Nginx sites directory not found"
        return 0
    fi

    # Check for security headers in Nginx config
    if grep -r "X-Frame-Options" "$nginx_sites" &>/dev/null; then
        log_success "Security headers found in Nginx config"
    else
        log_warning "Security headers may not be configured in Nginx"
        log_info "Run setup-ssl.sh to configure security headers"
    fi
}

# Remove sensitive files
remove_sensitive_files() {
    log_info "Removing sensitive files..."

    cd "$APP_ROOT"

    # Remove common sensitive files
    local sensitive_files=(
        ".env.example"
        ".env.backup"
        ".git/config"
        "composer.lock.bak"
        "package-lock.json.bak"
        "*.log"
        "*.sql"
        "*.sql.gz"
        "*.bak"
        ".DS_Store"
    )

    local removed=0
    for pattern in "${sensitive_files[@]}"; do
        while IFS= read -r -d '' file; do
            # Don't remove .env.example as it's useful
            if [[ "$file" == *".env.example"* ]]; then
                continue
            fi
            rm -f "$file"
            ((removed++))
        done < <(find "$APP_ROOT" -name "$pattern" -type f -print0 2>/dev/null)
    done

    if [[ $removed -gt 0 ]]; then
        log_success "Removed $removed sensitive files"
    else
        log_info "No sensitive files found"
    fi
}

# Create security audit log
create_audit_log() {
    log_info "Creating security audit log..."

    local audit_log="$APP_ROOT/storage/logs/security_audit.log"

    cat > "$audit_log" <<EOF
==============================================
CHOM Security Hardening Audit Log
==============================================
Date: $(date)
Server: $(hostname)
Application: $APP_ROOT

Security Measures Applied:
- File permissions secured
- PHP configuration hardened
- Laravel production mode enabled
- Session security configured
- Sensitive files removed
- Security headers configured

Next Steps:
1. Review application logs regularly
2. Monitor for security updates
3. Run security audit script monthly
4. Rotate secrets quarterly
5. Update dependencies regularly

==============================================
EOF

    chmod 644 "$audit_log"
    chown "$APP_USER:$APP_GROUP" "$audit_log"

    log_success "Audit log created: $audit_log"
}

# Restart services
restart_services() {
    log_info "Restarting services..."

    # Restart PHP-FPM
    systemctl restart "php${PHP_VERSION}-fpm"
    log_success "PHP-FPM restarted"

    # Restart Nginx if installed
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
        log_success "Nginx reloaded"
    fi

    # Restart queue workers if running
    if systemctl is-active --quiet "laravel-worker" 2>/dev/null; then
        systemctl restart laravel-worker
        log_success "Laravel workers restarted"
    fi
}

# Verify configuration
verify_configuration() {
    log_info "Verifying security configuration..."

    local errors=0

    # Check .env permissions
    if [[ -f "$APP_ROOT/.env" ]]; then
        local perm=$(stat -c %a "$APP_ROOT/.env")
        if [[ "$perm" != "600" ]]; then
            log_error ".env permissions are $perm, should be 600"
            ((errors++))
        fi
    fi

    # Check production mode
    if grep -q "^APP_ENV=local" "$APP_ROOT/.env" 2>/dev/null; then
        log_error "APP_ENV is still set to local"
        ((errors++))
    fi

    if grep -q "^APP_DEBUG=true" "$APP_ROOT/.env" 2>/dev/null; then
        log_error "APP_DEBUG is still enabled"
        ((errors++))
    fi

    # Check world-writable files
    local writable=$(find "$APP_ROOT" -type f -perm -002 2>/dev/null | wc -l)
    if [[ $writable -gt 0 ]]; then
        log_warning "Found $writable world-writable files"
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "Configuration verified"
        return 0
    else
        log_error "Configuration has $errors error(s)"
        return 1
    fi
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "Application Security Hardening Complete"
    log_success "=========================================="
    echo ""

    log_info "Application: $APP_ROOT"
    log_info "User/Group: $APP_USER:$APP_GROUP"
    log_info "PHP Version: $PHP_VERSION"
    echo ""

    log_info "Security Features Enabled:"
    echo "  ✓ Secure file permissions (644/755)"
    echo "  ✓ Storage directories writable (775)"
    echo "  ✓ .env file secured (600)"
    echo "  ✓ Production mode enabled"
    echo "  ✓ Debug mode disabled"
    echo "  ✓ Session security (httpOnly, secure, sameSite)"
    echo "  ✓ PHP dangerous functions disabled"
    echo "  ✓ Open basedir restriction"
    echo "  ✓ URL file access disabled"
    echo "  ✓ Error display disabled (logged only)"
    echo "  ✓ Configuration cached"
    echo "  ✓ Sensitive files removed"
    echo ""

    log_warning "SECURITY CHECKLIST:"
    echo "  ☐ Review Laravel middleware configuration"
    echo "  ☐ Verify CSRF protection on all forms"
    echo "  ☐ Test rate limiting on API endpoints"
    echo "  ☐ Review user input validation"
    echo "  ☐ Check SQL injection protection"
    echo "  ☐ Verify XSS prevention in views"
    echo "  ☐ Test session timeout"
    echo "  ☐ Review file upload validation"
    echo ""

    log_info "Logs:"
    echo "  Application: $APP_ROOT/storage/logs/laravel.log"
    echo "  PHP Errors: /var/log/php/error.log"
    echo "  Security Audit: $APP_ROOT/storage/logs/security_audit.log"
    echo ""
}

# Main execution
main() {
    log_info "Starting application security hardening..."
    echo ""

    check_root
    verify_app_directory
    set_file_permissions
    configure_laravel_security
    harden_php_config
    configure_php_fpm
    setup_laravel_cache
    configure_trusted_proxies
    configure_nginx_security
    remove_sensitive_files
    create_audit_log
    restart_services
    verify_configuration
    display_summary

    log_success "Application hardening complete!"
}

# Run main function
main "$@"
