#!/bin/bash

###############################################################################
# CHOM Log Analysis Tool
# Analyzes application and server logs for errors and patterns
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
APP_PATH="/var/www/chom/current"
TIME_WINDOW=60  # minutes
MAX_EXAMPLES=5

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --minutes)
            TIME_WINDOW="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--minutes N]"
            echo "  --minutes N  Analyze logs from last N minutes (default: 60)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging
log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

###############################################################################
# ANALYSIS FUNCTIONS
###############################################################################

analyze_laravel_logs() {
    log_section "Laravel Application Logs (Last ${TIME_WINDOW}m)"

    local log_file="$APP_PATH/storage/logs/laravel.log"

    # Check if log exists
    if ! ssh "$DEPLOY_USER@$APP_SERVER" "test -f $log_file" &>/dev/null; then
        echo -e "${YELLOW}No Laravel log file found${NC}"
        return
    fi

    # Get log entries from last N minutes
    local cutoff_time=$(($(date +%s) - (TIME_WINDOW * 60)))

    # Count error types
    echo -e "${CYAN}Error Summary:${NC}"

    local total_errors
    total_errors=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'ERROR\|Exception\|CRITICAL' $log_file 2>/dev/null | tail -1000 | wc -l" || echo "0")

    echo -e "  Total Errors/Exceptions: ${BOLD}$total_errors${NC}"

    if [[ "$total_errors" -eq 0 ]]; then
        echo -e "  ${GREEN}No errors found in recent logs${NC}"
        return
    fi

    # Group by error type
    echo ""
    echo -e "${CYAN}Error Types:${NC}"

    ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'Exception' $log_file 2>/dev/null | tail -1000 | grep -oP '\\\\([A-Za-z]+Exception)' | sort | uniq -c | sort -rn | head -10" | while read -r count exception; do
        echo -e "  ${count}x ${RED}${exception}${NC}"
    done

    # Find most common error messages
    echo ""
    echo -e "${CYAN}Common Error Messages:${NC}"

    ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'ERROR' $log_file 2>/dev/null | tail -500 | cut -d':' -f4- | sort | uniq -c | sort -rn | head -5" | while read -r line; do
        echo -e "  ${YELLOW}$line${NC}"
    done

    # Show recent errors
    echo ""
    echo -e "${CYAN}Recent Errors (last $MAX_EXAMPLES):${NC}"

    ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'ERROR\|Exception' $log_file 2>/dev/null | tail -$MAX_EXAMPLES" | while read -r line; do
        # Extract timestamp and message
        local timestamp=$(echo "$line" | grep -oP '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]' || echo "")
        local message=$(echo "$line" | cut -c50- | head -c 120)
        echo -e "  ${BLUE}${timestamp}${NC} ${message}..."
    done
}

analyze_nginx_errors() {
    log_section "Nginx Error Logs (Last ${TIME_WINDOW}m)"

    local error_log="/var/log/nginx/error.log"

    # Check if log exists
    if ! ssh "$DEPLOY_USER@$APP_SERVER" "sudo test -f $error_log" &>/dev/null; then
        echo -e "${YELLOW}No Nginx error log found${NC}"
        return
    fi

    # Count errors by severity
    echo -e "${CYAN}Error Severity:${NC}"

    local crit_count
    crit_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $error_log 2>/dev/null | grep -c '\\[crit\\]\\|\\[alert\\]\\|\\[emerg\\]' || echo '0'" || echo "0")

    local error_count
    error_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $error_log 2>/dev/null | grep -c '\\[error\\]' || echo '0'" || echo "0")

    local warn_count
    warn_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $error_log 2>/dev/null | grep -c '\\[warn\\]' || echo '0'" || echo "0")

    if [[ "$crit_count" -gt 0 ]]; then
        echo -e "  Critical/Alert:  ${RED}${BOLD}$crit_count${NC}"
    else
        echo -e "  Critical/Alert:  ${GREEN}0${NC}"
    fi

    echo -e "  Errors:          ${BOLD}$error_count${NC}"
    echo -e "  Warnings:        ${BOLD}$warn_count${NC}"

    if [[ "$error_count" -gt 0 ]]; then
        echo ""
        echo -e "${CYAN}Recent Nginx Errors:${NC}"

        ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $error_log 2>/dev/null | grep '\\[error\\]' | tail -$MAX_EXAMPLES" | while read -r line; do
            local message=$(echo "$line" | cut -c1-120)
            echo -e "  ${RED}${message}...${NC}"
        done
    fi
}

analyze_nginx_access() {
    log_section "Nginx Access Log Analysis (Last ${TIME_WINDOW}m)"

    local access_log="/var/log/nginx/access.log"

    if ! ssh "$DEPLOY_USER@$APP_SERVER" "sudo test -f $access_log" &>/dev/null; then
        echo -e "${YELLOW}No Nginx access log found${NC}"
        return
    fi

    # Count HTTP status codes
    echo -e "${CYAN}HTTP Status Codes (last 1000 requests):${NC}"

    local status_2xx
    status_2xx=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $access_log 2>/dev/null | grep -c ' 2[0-9][0-9] ' || echo '0'" || echo "0")

    local status_3xx
    status_3xx=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $access_log 2>/dev/null | grep -c ' 3[0-9][0-9] ' || echo '0'" || echo "0")

    local status_4xx
    status_4xx=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $access_log 2>/dev/null | grep -c ' 4[0-9][0-9] ' || echo '0'" || echo "0")

    local status_5xx
    status_5xx=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $access_log 2>/dev/null | grep -c ' 5[0-9][0-9] ' || echo '0'" || echo "0")

    echo -e "  2xx (Success):   ${GREEN}$status_2xx${NC}"
    echo -e "  3xx (Redirect):  ${CYAN}$status_3xx${NC}"
    echo -e "  4xx (Client):    ${YELLOW}$status_4xx${NC}"
    echo -e "  5xx (Server):    ${RED}$status_5xx${NC}"

    # Show 5xx errors if any
    if [[ "$status_5xx" -gt 0 ]]; then
        echo ""
        echo -e "${CYAN}Recent 5xx Errors:${NC}"

        ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $access_log 2>/dev/null | grep ' 5[0-9][0-9] ' | tail -$MAX_EXAMPLES" | while read -r line; do
            local ip=$(echo "$line" | awk '{print $1}')
            local method=$(echo "$line" | awk '{print $6}' | tr -d '"')
            local uri=$(echo "$line" | awk '{print $7}' | cut -c1-50)
            local status=$(echo "$line" | awk '{print $9}')

            echo -e "  ${RED}[$status]${NC} $method $uri ${DIM}(from $ip)${NC}"
        done
    fi

    # Top requested URLs
    echo ""
    echo -e "${CYAN}Top Requested URLs:${NC}"

    ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 $access_log 2>/dev/null | awk '{print \$7}' | sort | uniq -c | sort -rn | head -5" | while read -r count url; do
        echo -e "  ${count}x ${BLUE}${url}${NC}"
    done
}

analyze_slow_queries() {
    log_section "Slow Database Queries"

    # This requires query logging to be enabled in PostgreSQL
    echo -e "${CYAN}Analyzing slow queries...${NC}"

    # Check Laravel query log (if enabled)
    local has_slow_queries
    has_slow_queries=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'Slow query' $APP_PATH/storage/logs/laravel.log 2>/dev/null | tail -100 | wc -l" || echo "0")

    if [[ "$has_slow_queries" -gt 0 ]]; then
        echo -e "  ${YELLOW}Found $has_slow_queries slow query warnings${NC}"

        echo ""
        echo -e "${CYAN}Recent Slow Queries:${NC}"

        ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'Slow query' $APP_PATH/storage/logs/laravel.log 2>/dev/null | tail -$MAX_EXAMPLES" | while read -r line; do
            local message=$(echo "$line" | cut -c1-120)
            echo -e "  ${YELLOW}${message}...${NC}"
        done
    else
        echo -e "  ${GREEN}No slow queries detected in application logs${NC}"
    fi
}

analyze_failed_jobs() {
    log_section "Failed Queue Jobs"

    local failed_jobs
    failed_jobs=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan queue:failed --json 2>/dev/null | grep -c '\"id\"' || echo '0'" 2>/dev/null || echo "0")

    if [[ "$failed_jobs" -gt 0 ]]; then
        echo -e "  ${RED}Failed Jobs: $failed_jobs${NC}"

        echo ""
        echo -e "${CYAN}Recent Failed Jobs:${NC}"

        ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan queue:failed 2>/dev/null | head -20" | while read -r line; do
            if [[ -n "$line" ]]; then
                echo -e "  ${YELLOW}$line${NC}"
            fi
        done
    else
        echo -e "  ${GREEN}No failed jobs${NC}"
    fi
}

analyze_php_errors() {
    log_section "PHP Error Log"

    # Find PHP error log
    local php_log
    php_log=$(ssh "$DEPLOY_USER@$APP_SERVER" "php -i 2>/dev/null | grep 'error_log' | grep -oP '/[^ ]+' | head -1" || echo "/var/log/php-fpm-error.log")

    if ssh "$DEPLOY_USER@$APP_SERVER" "sudo test -f $php_log" &>/dev/null; then
        local php_errors
        php_errors=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -100 $php_log 2>/dev/null | grep -c 'PHP' || echo '0'" || echo "0")

        if [[ "$php_errors" -gt 0 ]]; then
            echo -e "  ${YELLOW}PHP Errors Found: $php_errors${NC}"

            echo ""
            echo -e "${CYAN}Recent PHP Errors:${NC}"

            ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -100 $php_log 2>/dev/null | grep 'PHP' | tail -$MAX_EXAMPLES" | while read -r line; do
                local message=$(echo "$line" | cut -c1-120)
                echo -e "  ${RED}${message}...${NC}"
            done
        else
            echo -e "  ${GREEN}No recent PHP errors${NC}"
        fi
    else
        echo -e "  ${YELLOW}PHP error log not found at $php_log${NC}"
    fi
}

generate_summary() {
    log_section "Analysis Summary"

    # Count total issues
    local total_app_errors
    total_app_errors=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -a 'ERROR\|Exception' $APP_PATH/storage/logs/laravel.log 2>/dev/null | tail -1000 | wc -l" || echo "0")

    local total_nginx_errors
    total_nginx_errors=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 /var/log/nginx/error.log 2>/dev/null | grep -c '\\[error\\]' || echo '0'" || echo "0")

    local total_5xx
    total_5xx=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo tail -1000 /var/log/nginx/access.log 2>/dev/null | grep -c ' 5[0-9][0-9] ' || echo '0'" || echo "0")

    echo -e "${CYAN}Issue Counts (last ${TIME_WINDOW}m or last 1000 log entries):${NC}"
    echo -e "  Application Errors:  ${BOLD}$total_app_errors${NC}"
    echo -e "  Nginx Errors:        ${BOLD}$total_nginx_errors${NC}"
    echo -e "  5xx Responses:       ${BOLD}$total_5xx${NC}"

    echo ""

    local total_issues=$((total_app_errors + total_nginx_errors + total_5xx))

    if [[ "$total_issues" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ No significant issues detected${NC}"
    elif [[ "$total_issues" -lt 10 ]]; then
        echo -e "${YELLOW}⚠ Minor issues detected - review logs above${NC}"
    else
        echo -e "${RED}✗ Significant issues detected - immediate attention required${NC}"
    fi

    # Recommendations
    echo ""
    echo -e "${CYAN}Recommendations:${NC}"

    if [[ "$total_app_errors" -gt 10 ]]; then
        echo -e "  ${YELLOW}• High error rate in application logs - check error patterns above${NC}"
    fi

    if [[ "$total_5xx" -gt 5 ]]; then
        echo -e "  ${YELLOW}• Server errors occurring - check application health and resources${NC}"
    fi

    if [[ "$total_nginx_errors" -gt 10 ]]; then
        echo -e "  ${YELLOW}• Nginx errors detected - check server configuration${NC}"
    fi

    if [[ "$total_issues" -eq 0 ]]; then
        echo -e "  ${GREEN}• All systems operating normally${NC}"
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            CHOM Log Analysis Tool                             ║"
    echo "║            Analyzing logs for errors and patterns...          ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "Time window: Last ${BOLD}${TIME_WINDOW}${NC} minutes"

    analyze_laravel_logs
    analyze_nginx_errors
    analyze_nginx_access
    analyze_slow_queries
    analyze_failed_jobs
    analyze_php_errors
    generate_summary

    echo ""
}

main "$@"
