#!/bin/bash

###############################################################################
# CHOM Emergency Diagnostics Tool
# Quickly captures system state for troubleshooting
# Target: Complete in under 30 seconds
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
OUTPUT_DIR="/tmp/chom-diagnostics-$(date +%Y%m%d-%H%M%S)"
TARBALL="/tmp/chom-diagnostics-$(date +%Y%m%d-%H%M%S).tar.gz"

START_TIME=$(date +%s)

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║            CHOM Emergency Diagnostics                         ║"
echo "║            Capturing system state for analysis...             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

log_info "Creating diagnostics directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

###############################################################################
# CAPTURE SYSTEM STATE
###############################################################################

log_info "Capturing system information..."

# System info
{
    echo "=== SYSTEM INFORMATION ==="
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    ssh "$DEPLOY_USER@$APP_SERVER" "uname -a"
    echo ""
    ssh "$DEPLOY_USER@$APP_SERVER" "cat /etc/os-release 2>/dev/null || echo 'OS release info not available'"
    echo ""
    echo "Hostname: $(ssh "$DEPLOY_USER@$APP_SERVER" "hostname")"
    echo "Uptime: $(ssh "$DEPLOY_USER@$APP_SERVER" "uptime")"
} > "$OUTPUT_DIR/system-info.txt" 2>&1

log_success "System information captured"

###############################################################################
# CAPTURE SERVICE STATUS
###############################################################################

log_info "Capturing service status..."

{
    echo "=== SERVICE STATUS ==="
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""

    for service in nginx php-fpm php7.4-fpm php8.0-fpm php8.1-fpm php8.2-fpm postgresql redis redis-server supervisor; do
        echo "--- $service ---"
        ssh "$DEPLOY_USER@$APP_SERVER" "sudo systemctl status $service 2>&1 || echo 'Service not found or not using systemd'"
        echo ""
    done
} > "$OUTPUT_DIR/service-status.txt" 2>&1

log_success "Service status captured"

###############################################################################
# CAPTURE PROCESS LIST
###############################################################################

log_info "Capturing process list..."

{
    echo "=== PROCESS LIST ==="
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    ssh "$DEPLOY_USER@$APP_SERVER" "ps auxf"
    echo ""
    echo "=== TOP PROCESSES ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "top -bn1 | head -30"
} > "$OUTPUT_DIR/processes.txt" 2>&1

log_success "Process list captured"

###############################################################################
# CAPTURE RESOURCE USAGE
###############################################################################

log_info "Capturing resource usage..."

{
    echo "=== MEMORY USAGE ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "free -h"
    echo ""
    echo "=== DISK USAGE ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "df -h"
    echo ""
    echo "=== INODE USAGE ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "df -i"
    echo ""
    echo "=== CPU INFO ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "lscpu 2>/dev/null || echo 'lscpu not available'"
} > "$OUTPUT_DIR/resource-usage.txt" 2>&1

log_success "Resource usage captured"

###############################################################################
# CAPTURE NETWORK STATUS
###############################################################################

log_info "Capturing network status..."

{
    echo "=== NETWORK INTERFACES ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "ip addr show"
    echo ""
    echo "=== ROUTING TABLE ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "ip route"
    echo ""
    echo "=== NETWORK CONNECTIONS ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "ss -tunapl 2>/dev/null | head -100"
    echo ""
    echo "=== LISTENING PORTS ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo netstat -tlnp 2>/dev/null || ss -tlnp"
} > "$OUTPUT_DIR/network-status.txt" 2>&1

log_success "Network status captured"

###############################################################################
# CAPTURE APPLICATION LOGS
###############################################################################

log_info "Capturing application logs..."

# Laravel logs
{
    echo "=== LARAVEL ERROR LOG (Last 500 lines) ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "tail -500 $APP_PATH/storage/logs/laravel.log 2>/dev/null || echo 'Log file not found'"
} > "$OUTPUT_DIR/laravel-log.txt" 2>&1

log_success "Application logs captured"

###############################################################################
# CAPTURE WEB SERVER LOGS
###############################################################################

log_info "Capturing web server logs..."

# Nginx error log
{
    echo "=== NGINX ERROR LOG (Last 500 lines) ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -500 /var/log/nginx/error.log 2>/dev/null || echo 'Log file not found'"
} > "$OUTPUT_DIR/nginx-error-log.txt" 2>&1

# Nginx access log
{
    echo "=== NGINX ACCESS LOG (Last 500 lines) ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -500 /var/log/nginx/access.log 2>/dev/null || echo 'Log file not found'"
} > "$OUTPUT_DIR/nginx-access-log.txt" 2>&1

log_success "Web server logs captured"

###############################################################################
# CAPTURE PHP LOGS
###############################################################################

log_info "Capturing PHP logs..."

{
    echo "=== PHP-FPM ERROR LOG (Last 500 lines) ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -500 /var/log/php*-fpm.log 2>/dev/null || echo 'Log file not found'"
    echo ""
    echo "=== PHP ERROR LOG ==="
    local php_log=$(ssh "$DEPLOY_USER@$APP_SERVER" "php -i 2>/dev/null | grep 'error_log' | grep -oP '/[^ ]+' | head -1" || echo "")
    if [[ -n "$php_log" ]]; then
        ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -500 $php_log 2>/dev/null || echo 'Cannot read log file'"
    else
        echo "PHP error log path not found"
    fi
} > "$OUTPUT_DIR/php-logs.txt" 2>&1

log_success "PHP logs captured"

###############################################################################
# CAPTURE CONFIGURATION FILES
###############################################################################

log_info "Capturing configuration files..."

# Application .env (sanitized)
{
    echo "=== APPLICATION ENVIRONMENT (SANITIZED) ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "cat $APP_PATH/.env 2>/dev/null | sed 's/\(PASSWORD\|SECRET\|KEY\)=.*/\1=***REDACTED***/g' || echo '.env not found'"
} > "$OUTPUT_DIR/app-env-sanitized.txt" 2>&1

# Nginx config
{
    echo "=== NGINX CONFIGURATION ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo nginx -T 2>/dev/null || echo 'Cannot retrieve Nginx config'"
} > "$OUTPUT_DIR/nginx-config.txt" 2>&1

# PHP-FPM config
{
    echo "=== PHP-FPM CONFIGURATION ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "php-fpm -tt 2>&1 || echo 'Cannot retrieve PHP-FPM config'"
} > "$OUTPUT_DIR/php-fpm-config.txt" 2>&1

log_success "Configuration files captured"

###############################################################################
# CAPTURE DATABASE STATUS
###############################################################################

log_info "Capturing database status..."

{
    echo "=== DATABASE STATUS ==="
    echo ""
    echo "--- PostgreSQL Version ---"
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo -u postgres psql -c 'SELECT version();' 2>/dev/null || echo 'Cannot connect to database'"
    echo ""
    echo "--- Active Connections ---"
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo -u postgres psql -c 'SELECT count(*) FROM pg_stat_activity;' 2>/dev/null || echo 'Cannot query database'"
    echo ""
    echo "--- Database Sizes ---"
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo -u postgres psql -c 'SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC LIMIT 10;' 2>/dev/null || echo 'Cannot query database'"
    echo ""
    echo "--- Long Running Queries ---"
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo -u postgres psql -c \"SELECT pid, now() - pg_stat_activity.query_start AS duration, query FROM pg_stat_activity WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';\" 2>/dev/null || echo 'Cannot query database'"
} > "$OUTPUT_DIR/database-status.txt" 2>&1

log_success "Database status captured"

###############################################################################
# CAPTURE QUEUE STATUS
###############################################################################

log_info "Capturing queue status..."

{
    echo "=== QUEUE WORKERS ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "ps aux | grep 'queue:work' | grep -v grep || echo 'No queue workers running'"
    echo ""
    echo "=== FAILED JOBS ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan queue:failed 2>/dev/null | head -50 || echo 'Cannot retrieve failed jobs'"
} > "$OUTPUT_DIR/queue-status.txt" 2>&1

log_success "Queue status captured"

###############################################################################
# CAPTURE DEPLOYMENT STATE
###############################################################################

log_info "Capturing deployment state..."

{
    echo "=== CURRENT RELEASE ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "readlink -f /var/www/chom/current 2>/dev/null | xargs basename || echo 'Cannot determine current release'"
    echo ""
    echo "=== AVAILABLE RELEASES ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "ls -lt /var/www/chom/releases 2>/dev/null || echo 'Cannot list releases'"
    echo ""
    echo "=== GIT STATUS ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && git status 2>/dev/null || echo 'Not a git repository'"
    echo ""
    echo "=== GIT LOG ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && git log --oneline -10 2>/dev/null || echo 'Cannot retrieve git log'"
    echo ""
    echo "=== COMPOSER PACKAGES ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && composer show 2>/dev/null | head -50 || echo 'Cannot retrieve composer packages'"
} > "$OUTPUT_DIR/deployment-state.txt" 2>&1

log_success "Deployment state captured"

###############################################################################
# CAPTURE RECENT SYSTEM LOGS
###############################################################################

log_info "Capturing system logs..."

{
    echo "=== SYSTEM LOG (Last 200 lines) ==="
    ssh "$DEPLOY_USER@$APP_SERVER" "sudo journalctl -n 200 --no-pager 2>/dev/null || tail -200 /var/log/syslog 2>/dev/null || echo 'Cannot retrieve system logs'"
} > "$OUTPUT_DIR/system-log.txt" 2>&1

log_success "System logs captured"

###############################################################################
# CREATE SUMMARY
###############################################################################

log_info "Creating diagnostic summary..."

{
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           CHOM Emergency Diagnostics Summary                  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "Server: $APP_SERVER"
    echo ""
    echo "=== QUICK STATUS ==="
    echo ""

    # Application status
    local app_status=$(ssh "$DEPLOY_USER@$APP_SERVER" "curl -sSL -w '%{http_code}' -o /dev/null -m 5 'http://localhost' 2>/dev/null" || echo "000")
    echo "Application HTTP Status: $app_status"

    # Service status
    echo ""
    echo "Service Status:"
    for service in nginx postgresql redis; do
        local status=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo systemctl is-active $service 2>/dev/null" || echo "unknown")
        echo "  $service: $status"
    done

    # Resource usage
    echo ""
    echo "Resource Usage:"
    local mem_percent=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{printf \"%.1f\", (\$3/\$2) * 100}'" 2>/dev/null || echo "0")
    echo "  Memory: ${mem_percent}%"

    local disk_percent=$(ssh "$DEPLOY_USER@$APP_SERVER" "df / | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null || echo "0")
    echo "  Disk: ${disk_percent}%"

    # Error counts
    echo ""
    echo "Recent Errors:"
    local app_errors=$(ssh "$DEPLOY_USER@$APP_SERVER" "tail -100 $APP_PATH/storage/logs/laravel.log 2>/dev/null | grep -c 'ERROR\|Exception' || echo '0'" || echo "0")
    echo "  Application: $app_errors errors in last 100 log lines"

    local nginx_errors=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -100 /var/log/nginx/error.log 2>/dev/null | grep -c 'error' || echo '0'" || echo "0")
    echo "  Nginx: $nginx_errors errors in last 100 log lines"

    echo ""
    echo "=== FILES CAPTURED ==="
    echo ""
    ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{printf "  %-30s %8s\n", $9, $5}'

} > "$OUTPUT_DIR/SUMMARY.txt" 2>&1

log_success "Summary created"

###############################################################################
# CREATE TARBALL
###############################################################################

log_info "Creating diagnostic tarball..."

tar -czf "$TARBALL" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")" 2>&1

if [[ -f "$TARBALL" ]]; then
    log_success "Diagnostic tarball created: $TARBALL"
    local tarball_size=$(du -h "$TARBALL" | cut -f1)
    echo ""
    echo -e "${GREEN}Diagnostics package: $TARBALL ($tarball_size)${NC}"
else
    log_error "Failed to create tarball"
fi

# Calculate execution time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ Diagnostics Complete                                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Execution time: ${BOLD}${DURATION}s${NC}"
echo ""
echo "Files captured:"
echo "  - System information and resource usage"
echo "  - Service status and configuration"
echo "  - Application logs (Laravel, Nginx, PHP)"
echo "  - Database and queue status"
echo "  - Deployment state and git history"
echo "  - Network and process information"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review SUMMARY.txt: cat $(dirname "$OUTPUT_DIR")/$(basename "$OUTPUT_DIR")/SUMMARY.txt"
echo "  2. Share diagnostic package: $TARBALL"
echo "  3. For remote analysis, use: scp $TARBALL your-local-machine:/path/"
echo ""

# Cleanup
if [[ "$DURATION" -lt 30 ]]; then
    echo -e "${GREEN}✓ Completed within 30 second target${NC}"
else
    echo -e "${YELLOW}⚠ Took ${DURATION}s (target: 30s)${NC}"
fi
