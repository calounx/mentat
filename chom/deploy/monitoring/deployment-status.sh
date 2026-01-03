#!/bin/bash

###############################################################################
# CHOM Deployment Status Dashboard
# Real-time deployment monitoring with auto-refresh
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
DIM='\033[2m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
APP_PATH="/var/www/chom/current"
REFRESH_INTERVAL=5
AUTO_REFRESH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            AUTO_REFRESH=true
            shift
            ;;
        --interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--watch] [--interval SECONDS]"
            exit 1
            ;;
    esac
done

# Utility functions
get_status_color() {
    local status="$1"
    case "$status" in
        running|active|up|healthy|ok) echo "$GREEN" ;;
        degraded|warning) echo "$YELLOW" ;;
        stopped|down|failed|error) echo "$RED" ;;
        *) echo "$CYAN" ;;
    esac
}

get_status_icon() {
    local status="$1"
    case "$status" in
        running|active|up|healthy|ok) echo "✓" ;;
        degraded|warning) echo "⚠" ;;
        stopped|down|failed|error) echo "✗" ;;
        *) echo "•" ;;
    esac
}

###############################################################################
# DATA COLLECTION
###############################################################################

get_deployment_info() {
    local current_release
    current_release=$(ssh "$DEPLOY_USER@$APP_SERVER" "readlink -f $APP_PATH 2>/dev/null | xargs basename" 2>/dev/null || echo "unknown")

    local deploy_time
    deploy_time=$(ssh "$DEPLOY_USER@$APP_SERVER" "stat -c %y $APP_PATH 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1" 2>/dev/null || echo "unknown")

    echo "$current_release|$deploy_time"
}

get_service_status() {
    local service="$1"

    # Try systemctl first
    local status
    status=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo systemctl is-active $service 2>/dev/null" || echo "unknown")

    if [[ "$status" == "active" ]]; then
        echo "running"
    elif [[ "$status" == "inactive" ]]; then
        echo "stopped"
    elif [[ "$status" == "failed" ]]; then
        echo "failed"
    else
        # Try process check
        if ssh "$DEPLOY_USER@$APP_SERVER" "pgrep -f $service &>/dev/null"; then
            echo "running"
        else
            echo "stopped"
        fi
    fi
}

get_application_health() {
    local app_url
    app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")

    if [[ -z "$app_url" ]]; then
        echo "unknown|0"
        return
    fi

    local start=$(date +%s%N)
    local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "$app_url" 2>/dev/null || echo "000")
    local end=$(date +%s%N)
    local response_time=$(( (end - start) / 1000000 ))

    local status="down"
    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "302" ]]; then
        status="healthy"
    elif [[ "$http_code" == "500" ]] || [[ "$http_code" == "503" ]]; then
        status="error"
    fi

    echo "$status|$response_time"
}

get_error_count() {
    local log_file="$APP_PATH/storage/logs/laravel.log"
    local count
    count=$(ssh "$DEPLOY_USER@$APP_SERVER" "tail -100 $log_file 2>/dev/null | grep -c 'ERROR\|Exception' || echo '0'" 2>/dev/null || echo "0")
    echo "$count"
}

get_queue_status() {
    local worker_count
    worker_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "ps aux | grep -c '[q]ueue:work' || echo '0'" 2>/dev/null || echo "0")

    local failed_jobs
    failed_jobs=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan queue:failed 2>/dev/null | grep -c 'ID' || echo '0'" 2>/dev/null || echo "0")

    echo "$worker_count|$failed_jobs"
}

get_resource_usage() {
    local mem_info
    mem_info=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem:" 2>/dev/null || echo "")

    local mem_percent=0
    if [[ -n "$mem_info" ]]; then
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        mem_percent=$(awk "BEGIN {printf \"%.1f\", ($used / $total) * 100}")
    fi

    local disk_percent
    disk_percent=$(ssh "$DEPLOY_USER@$APP_SERVER" "df /var/www | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null || echo "0")

    local cpu_percent
    cpu_percent=$(ssh "$DEPLOY_USER@$APP_SERVER" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null || echo "0")

    echo "$mem_percent|$disk_percent|$cpu_percent"
}

get_active_users() {
    # This is a placeholder - implement based on your session tracking
    local count
    count=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php -r \"
        require 'vendor/autoload.php';
        \\\$app = require_once 'bootstrap/app.php';
        \\\$app->make('Illuminate\\\\Contracts\\\\Console\\\\Kernel')->bootstrap();
        try {
            // Count active sessions (last 15 minutes)
            \\\$count = DB::table('sessions')->where('last_activity', '>', time() - 900)->count();
            echo \\\$count;
        } catch (Exception \\\$e) {
            echo '0';
        }
    \" 2>/dev/null" || echo "0")

    echo "$count"
}

###############################################################################
# DISPLAY FUNCTIONS
###############################################################################

display_dashboard() {
    # Clear screen
    clear

    # Header
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           CHOM Deployment Status Dashboard                    ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${DIM}Last updated: $timestamp${NC}"
    echo ""

    # Deployment Info
    echo -e "${BOLD}${CYAN}━━━ Deployment Information ━━━${NC}"
    local deploy_info=$(get_deployment_info)
    local current_release=$(echo "$deploy_info" | cut -d'|' -f1)
    local deploy_time=$(echo "$deploy_info" | cut -d'|' -f2)

    echo -e "  Current Release: ${BOLD}$current_release${NC}"
    echo -e "  Deployed At:     ${deploy_time}"
    echo ""

    # Application Health
    echo -e "${BOLD}${CYAN}━━━ Application Health ━━━${NC}"
    local health_info=$(get_application_health)
    local health_status=$(echo "$health_info" | cut -d'|' -f1)
    local response_time=$(echo "$health_info" | cut -d'|' -f2)

    local health_color=$(get_status_color "$health_status")
    local health_icon=$(get_status_icon "$health_status")

    echo -e "  HTTP Status:     ${health_color}${health_icon} ${health_status}${NC}"
    echo -e "  Response Time:   ${response_time}ms"

    local error_count=$(get_error_count)
    if [[ "$error_count" -gt 0 ]]; then
        echo -e "  Recent Errors:   ${RED}${error_count} errors in last 100 log lines${NC}"
    else
        echo -e "  Recent Errors:   ${GREEN}No errors${NC}"
    fi
    echo ""

    # Service Status
    echo -e "${BOLD}${CYAN}━━━ Service Status ━━━${NC}"

    # Nginx
    local nginx_status=$(get_service_status "nginx")
    local nginx_color=$(get_status_color "$nginx_status")
    local nginx_icon=$(get_status_icon "$nginx_status")
    echo -e "  Nginx:           ${nginx_color}${nginx_icon} ${nginx_status}${NC}"

    # PHP-FPM
    local phpfpm_status=$(get_service_status "php.*fpm")
    local phpfpm_color=$(get_status_color "$phpfpm_status")
    local phpfpm_icon=$(get_status_icon "$phpfpm_status")
    echo -e "  PHP-FPM:         ${phpfpm_color}${phpfpm_icon} ${phpfpm_status}${NC}"

    # PostgreSQL
    local pgsql_status=$(get_service_status "postgresql")
    local pgsql_color=$(get_status_color "$pgsql_status")
    local pgsql_icon=$(get_status_icon "$pgsql_status")
    echo -e "  PostgreSQL:      ${pgsql_color}${pgsql_icon} ${pgsql_status}${NC}"

    # Redis
    local redis_status=$(get_service_status "redis")
    local redis_color=$(get_status_color "$redis_status")
    local redis_icon=$(get_status_icon "$redis_status")
    echo -e "  Redis:           ${redis_color}${redis_icon} ${redis_status}${NC}"

    echo ""

    # Queue Workers
    echo -e "${BOLD}${CYAN}━━━ Queue Workers ━━━${NC}"
    local queue_info=$(get_queue_status)
    local worker_count=$(echo "$queue_info" | cut -d'|' -f1)
    local failed_jobs=$(echo "$queue_info" | cut -d'|' -f2)

    if [[ "$worker_count" -gt 0 ]]; then
        echo -e "  Active Workers:  ${GREEN}$worker_count${NC}"
    else
        echo -e "  Active Workers:  ${YELLOW}0 (none running)${NC}"
    fi

    if [[ "$failed_jobs" -gt 0 ]]; then
        echo -e "  Failed Jobs:     ${RED}$failed_jobs${NC}"
    else
        echo -e "  Failed Jobs:     ${GREEN}0${NC}"
    fi
    echo ""

    # Resource Usage
    echo -e "${BOLD}${CYAN}━━━ Server Resources ━━━${NC}"
    local resource_info=$(get_resource_usage)
    local mem_percent=$(echo "$resource_info" | cut -d'|' -f1)
    local disk_percent=$(echo "$resource_info" | cut -d'|' -f2)
    local cpu_percent=$(echo "$resource_info" | cut -d'|' -f3)

    # Memory bar
    local mem_bar=$(create_progress_bar "$mem_percent" 30)
    local mem_color="$GREEN"
    if (( $(awk "BEGIN {print ($mem_percent > 70)}") )); then
        mem_color="$YELLOW"
    fi
    if (( $(awk "BEGIN {print ($mem_percent > 90)}") )); then
        mem_color="$RED"
    fi
    echo -e "  Memory:          ${mem_color}${mem_bar}${NC} ${mem_percent}%"

    # Disk bar
    local disk_bar=$(create_progress_bar "$disk_percent" 30)
    local disk_color="$GREEN"
    if [[ "$disk_percent" -gt 70 ]]; then
        disk_color="$YELLOW"
    fi
    if [[ "$disk_percent" -gt 90 ]]; then
        disk_color="$RED"
    fi
    echo -e "  Disk:            ${disk_color}${disk_bar}${NC} ${disk_percent}%"

    # CPU bar
    local cpu_bar=$(create_progress_bar "$cpu_percent" 30)
    local cpu_color="$GREEN"
    if (( $(awk "BEGIN {print ($cpu_percent > 50)}") )); then
        cpu_color="$YELLOW"
    fi
    if (( $(awk "BEGIN {print ($cpu_percent > 80)}") )); then
        cpu_color="$RED"
    fi
    echo -e "  CPU:             ${cpu_color}${cpu_bar}${NC} ${cpu_percent}%"
    echo ""

    # Active Users
    echo -e "${BOLD}${CYAN}━━━ Activity ━━━${NC}"
    local active_users=$(get_active_users)
    echo -e "  Active Sessions: ${BOLD}$active_users${NC}"
    echo ""

    # Footer
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        echo -e "${DIM}Auto-refreshing every ${REFRESH_INTERVAL}s. Press Ctrl+C to exit.${NC}"
    else
        echo -e "${DIM}Run with --watch to enable auto-refresh${NC}"
    fi
}

create_progress_bar() {
    local percent="$1"
    local width="${2:-20}"

    local filled=$(awk "BEGIN {printf \"%.0f\", ($percent / 100) * $width}")
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar="${bar}█"
    done
    for ((i=0; i<empty; i++)); do
        bar="${bar}░"
    done

    echo "$bar"
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        # Continuous monitoring mode
        while true; do
            display_dashboard
            sleep "$REFRESH_INTERVAL"
        done
    else
        # Single display
        display_dashboard
    fi
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Dashboard stopped${NC}"; exit 0' INT TERM

main "$@"
