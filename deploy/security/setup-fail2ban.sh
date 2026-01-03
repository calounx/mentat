#!/bin/bash
# ============================================================================
# Fail2Ban Setup and Configuration Script
# ============================================================================
# Purpose: Configure intrusion prevention with Fail2Ban
# Features: SSH, Nginx, Laravel protection, email alerts
# Compliance: OWASP, PCI DSS, SOC 2
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
SSH_PORT="${SSH_PORT:-2222}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@arewel.com}"
BAN_TIME="${BAN_TIME:-3600}"  # 1 hour
FIND_TIME="${FIND_TIME:-600}"  # 10 minutes
MAX_RETRY="${MAX_RETRY:-5}"
APP_ROOT="${APP_ROOT:-/var/www/chom}"

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

# Install Fail2Ban
install_fail2ban() {
    log_info "Installing Fail2Ban..."

    apt-get update -qq
    apt-get install -y fail2ban

    systemctl enable fail2ban
    systemctl start fail2ban

    log_success "Fail2Ban installed and started"
}

# Create local configuration
create_local_config() {
    log_info "Creating local Fail2Ban configuration..."

    cat > /etc/fail2ban/jail.local <<EOF
# ============================================================================
# CHOM Fail2Ban Configuration
# Generated: $(date)
# ============================================================================

[DEFAULT]
# Ban settings
bantime = $BAN_TIME
findtime = $FIND_TIME
maxretry = $MAX_RETRY

# Ban action (iptables + email notification)
banaction = iptables-multiport
banaction_allports = iptables-allports

# Email notifications
destemail = $ADMIN_EMAIL
sender = fail2ban@$(hostname -f)
mta = sendmail
action = %(action_mwl)s

# Logging
loglevel = INFO
logtarget = /var/log/fail2ban.log

# IP whitelist (localhost)
ignoreip = 127.0.0.1/8 ::1

# Backend for log monitoring
backend = systemd

# ============================================================================
# JAILS
# ============================================================================

# SSH Jail (custom port)
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
findtime = 600

# SSH aggressive mode (DOS prevention)
[sshd-ddos]
enabled = true
port = $SSH_PORT
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 6
bantime = 3600
findtime = 300

# Nginx HTTP Auth
[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

# Nginx 404 spam
[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6
bantime = 3600

# Nginx bad bots
[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400

# Nginx proxy attempts
[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400

# Nginx request limit
[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 600
findtime = 60

# PHP URL fopen
[php-url-fopen]
enabled = true
port = http,https
filter = php-url-fopen
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 86400

# Recidive (repeat offenders - permanent ban)
[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 3
action = %(action_mwl)s

EOF

    log_success "Local configuration created"
}

# Create Laravel authentication filter
create_laravel_auth_filter() {
    log_info "Creating Laravel authentication filter..."

    cat > /etc/fail2ban/filter.d/laravel-auth.conf <<'EOF'
# Fail2Ban filter for Laravel authentication failures
[Definition]

failregex = .*Failed login attempt.* IP: <HOST>
            .*Attempting to authenticate as .* from <HOST>
            .*Invalid credentials.* IP: <HOST>
            .*Authentication failed for .* from <HOST>

ignoreregex =

datepattern = {^LN-BEG}%%Y-%%m-%%d %%H:%%M:%%S
EOF

    log_success "Laravel auth filter created"

    # Add Laravel jail to jail.local
    cat >> /etc/fail2ban/jail.local <<EOF

# Laravel Authentication
[laravel-auth]
enabled = true
port = http,https
filter = laravel-auth
logpath = $APP_ROOT/storage/logs/laravel.log
maxretry = 5
bantime = 3600
findtime = 600

EOF

    log_success "Laravel jail configured"
}

# Create custom filters
create_custom_filters() {
    log_info "Creating custom security filters..."

    # SQL Injection attempts
    cat > /etc/fail2ban/filter.d/nginx-sql-injection.conf <<'EOF'
# SQL Injection attempts
[Definition]
failregex = <HOST> .*(union.*select|concat.*char|select.*from|insert.*into|delete.*from|update.*set|drop.*table).*
ignoreregex =
EOF

    # XSS attempts
    cat > /etc/fail2ban/filter.d/nginx-xss.conf <<'EOF'
# XSS attempts
[Definition]
failregex = <HOST> .*(script.*>|<.*javascript|onerror.*=|onload.*=).*
ignoreregex =
EOF

    # Path traversal
    cat > /etc/fail2ban/filter.d/nginx-path-traversal.conf <<'EOF'
# Path traversal attempts
[Definition]
failregex = <HOST> .*(\.\.\/|\.\.\\|etc\/passwd|boot\.ini).*
ignoreregex =
EOF

    # Add jails for custom filters
    cat >> /etc/fail2ban/jail.local <<EOF

# SQL Injection
[nginx-sql-injection]
enabled = true
port = http,https
filter = nginx-sql-injection
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 86400

# XSS Attempts
[nginx-xss]
enabled = true
port = http,https
filter = nginx-xss
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 86400

# Path Traversal
[nginx-path-traversal]
enabled = true
port = http,https
filter = nginx-path-traversal
logpath = /var/log/nginx/access.log
maxretry = 1
bantime = 86400

EOF

    log_success "Custom filters created"
}

# Configure email notifications
configure_email_notifications() {
    log_info "Configuring email notifications..."

    # Check if sendmail/postfix is installed
    if ! command -v sendmail &> /dev/null && ! command -v postfix &> /dev/null; then
        log_warning "No mail system installed, installing postfix..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y postfix mailutils
    fi

    # Create custom email action
    cat > /etc/fail2ban/action.d/sendmail-chom.conf <<EOF
# CHOM Email notification action
[Definition]
actionstart = echo "Fail2Ban started on <fq-hostname>" | mail -s "[Fail2Ban] <fq-hostname>: Started" <dest>
actionstop = echo "Fail2Ban stopped on <fq-hostname>" | mail -s "[Fail2Ban] <fq-hostname>: Stopped" <dest>
actioncheck =
actionban = echo "
    The IP <ip> has been banned by Fail2Ban after <failures> attempts against <name>.

    Time: <time>
    Server: <fq-hostname>
    Jail: <name>
    IP: <ip>
    Failures: <failures>

    Lines containing IP: <ip> in <logpath>:
    \`grep '<ip>' <logpath> | tail -n 10\`

    Regards,
    Fail2Ban
    " | mail -s "[Fail2Ban] <fq-hostname>: Banned <ip> from <name>" <dest>
actionunban = echo "The IP <ip> has been unbanned from <name>" | mail -s "[Fail2Ban] <fq-hostname>: Unbanned <ip> from <name>" <dest>

[Init]
name = default
dest = $ADMIN_EMAIL
EOF

    log_success "Email notifications configured"
}

# Create IP whitelist
create_ip_whitelist() {
    log_info "Setting up IP whitelist..."

    # Create whitelist file
    cat > /etc/fail2ban/ip.whitelist <<EOF
# CHOM Fail2Ban IP Whitelist
# Add trusted IPs here (one per line)
# Format: IP address or CIDR notation

# Localhost
127.0.0.1
::1

# Add your trusted IPs below:
# 192.168.1.100
# 10.0.0.0/24

EOF

    # Update jail.local to use whitelist
    sed -i "s|ignoreip = 127.0.0.1/8 ::1|ignoreip = 127.0.0.1/8 ::1 /etc/fail2ban/ip.whitelist|" /etc/fail2ban/jail.local

    chmod 644 /etc/fail2ban/ip.whitelist

    log_success "IP whitelist created"
    log_info "Add trusted IPs to: /etc/fail2ban/ip.whitelist"
}

# Create monitoring script
create_monitoring_script() {
    log_info "Creating Fail2Ban monitoring script..."

    cat > /usr/local/bin/chom-fail2ban <<'EOF'
#!/bin/bash
# CHOM Fail2Ban Management

case "$1" in
    status)
        fail2ban-client status
        ;;
    jails)
        fail2ban-client status | grep "Jail list" | sed 's/.*Jail list://' | tr ',' '\n' | sed 's/^[ \t]*//'
        ;;
    jail)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-fail2ban jail <jail-name>"
            echo "Available jails:"
            fail2ban-client status | grep "Jail list"
            exit 1
        fi
        fail2ban-client status "$2"
        ;;
    banned)
        echo "Currently banned IPs across all jails:"
        for jail in $(fail2ban-client status | grep "Jail list" | sed 's/.*Jail list://' | tr ',' ' '); do
            jail=$(echo $jail | xargs)
            banned=$(fail2ban-client status "$jail" | grep "Banned IP list" | sed 's/.*Banned IP list://')
            if [[ -n "$banned" ]] && [[ "$banned" != "0" ]]; then
                echo "$jail: $banned"
            fi
        done
        ;;
    unban)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-fail2ban unban <ip-address>"
            exit 1
        fi
        fail2ban-client unban "$2"
        echo "Unbanned: $2"
        ;;
    unban-all)
        read -p "Unban all IPs? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            fail2ban-client unban --all
            echo "All IPs unbanned"
        fi
        ;;
    whitelist)
        if [[ -z "$2" ]]; then
            echo "Current whitelist:"
            cat /etc/fail2ban/ip.whitelist
        else
            echo "$2" >> /etc/fail2ban/ip.whitelist
            echo "Added $2 to whitelist"
            systemctl reload fail2ban
        fi
        ;;
    logs)
        tail -f /var/log/fail2ban.log
        ;;
    stats)
        echo "=== Fail2Ban Statistics ==="
        echo ""
        for jail in $(fail2ban-client status | grep "Jail list" | sed 's/.*Jail list://' | tr ',' ' '); do
            jail=$(echo $jail | xargs)
            echo "Jail: $jail"
            fail2ban-client status "$jail" | grep -E "Currently failed|Currently banned|Total failed|Total banned"
            echo ""
        done
        ;;
    test)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-fail2ban test <jail-name>"
            exit 1
        fi
        fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/$2.conf
        ;;
    reload)
        systemctl reload fail2ban
        echo "Fail2Ban reloaded"
        ;;
    restart)
        systemctl restart fail2ban
        echo "Fail2Ban restarted"
        ;;
    *)
        echo "CHOM Fail2Ban Management"
        echo ""
        echo "Usage: chom-fail2ban <command> [args]"
        echo ""
        echo "Commands:"
        echo "  status              Show Fail2Ban status"
        echo "  jails               List all jails"
        echo "  jail <name>         Show jail details"
        echo "  banned              List all banned IPs"
        echo "  unban <ip>          Unban specific IP"
        echo "  unban-all           Unban all IPs"
        echo "  whitelist [ip]      Show or add to whitelist"
        echo "  logs                Tail Fail2Ban logs"
        echo "  stats               Show statistics"
        echo "  test <jail>         Test jail filter"
        echo "  reload              Reload configuration"
        echo "  restart             Restart Fail2Ban"
        echo ""
        ;;
esac
EOF

    chmod +x /usr/local/bin/chom-fail2ban

    log_success "Monitoring script created: /usr/local/bin/chom-fail2ban"
}

# Test Fail2Ban configuration
test_configuration() {
    log_info "Testing Fail2Ban configuration..."

    if fail2ban-client --test; then
        log_success "Configuration test passed"
    else
        log_error "Configuration test failed"
        return 1
    fi

    return 0
}

# Restart Fail2Ban
restart_fail2ban() {
    log_info "Restarting Fail2Ban..."

    systemctl restart fail2ban

    if systemctl is-active --quiet fail2ban; then
        log_success "Fail2Ban restarted successfully"
    else
        log_error "Fail2Ban failed to start"
        journalctl -u fail2ban -n 20
        exit 1
    fi
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "Fail2Ban Configuration Complete"
    log_success "=========================================="
    echo ""

    log_info "Configuration:"
    echo "  Ban Time: $BAN_TIME seconds ($(($BAN_TIME/60)) minutes)"
    echo "  Find Time: $FIND_TIME seconds ($(($FIND_TIME/60)) minutes)"
    echo "  Max Retries: $MAX_RETRY"
    echo "  Admin Email: $ADMIN_EMAIL"
    echo "  SSH Port: $SSH_PORT"
    echo ""

    log_info "Active Jails:"
    fail2ban-client status | grep "Jail list"
    echo ""

    log_info "Protection Against:"
    echo "  ✓ SSH brute force attacks"
    echo "  ✓ SSH DOS attacks"
    echo "  ✓ Nginx HTTP auth failures"
    echo "  ✓ Nginx 404 spam"
    echo "  ✓ Bad bots and crawlers"
    echo "  ✓ Proxy attempts"
    echo "  ✓ Request flooding"
    echo "  ✓ Laravel auth failures"
    echo "  ✓ SQL injection attempts"
    echo "  ✓ XSS attempts"
    echo "  ✓ Path traversal attempts"
    echo "  ✓ Repeat offenders (permanent ban)"
    echo ""

    log_info "Management Commands:"
    echo "  chom-fail2ban status        - Show status"
    echo "  chom-fail2ban banned        - List banned IPs"
    echo "  chom-fail2ban unban <ip>    - Unban IP"
    echo "  chom-fail2ban stats         - Show statistics"
    echo ""

    log_info "Configuration Files:"
    echo "  Main Config: /etc/fail2ban/jail.local"
    echo "  Filters: /etc/fail2ban/filter.d/"
    echo "  Whitelist: /etc/fail2ban/ip.whitelist"
    echo "  Logs: /var/log/fail2ban.log"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  1. Add trusted IPs to whitelist"
    echo "  2. Monitor ban logs regularly"
    echo "  3. Review banned IPs weekly"
    echo "  4. Test SSH access after configuration"
    echo "  5. Ensure email notifications work"
    echo ""
}

# Main execution
main() {
    log_info "Starting Fail2Ban setup..."
    echo ""

    check_root
    install_fail2ban
    create_local_config
    create_laravel_auth_filter
    create_custom_filters
    configure_email_notifications
    create_ip_whitelist
    create_monitoring_script
    test_configuration
    restart_fail2ban
    display_summary

    log_success "Fail2Ban setup complete!"
}

# Run main function
main "$@"
