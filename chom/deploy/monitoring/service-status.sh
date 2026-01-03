#!/bin/bash

###############################################################################
# CHOM Service Status Dashboard
# Shows all service statuses with color-coded output
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
AUTO_REFRESH=false
REFRESH_INTERVAL=10

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            AUTO_REFRESH=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

get_service_status() {
    local service="$1"

    local status=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo systemctl is-active $service 2>/dev/null" || echo "unknown")

    case "$status" in
        active) echo "running|$GREEN" ;;
        inactive) echo "stopped|$YELLOW" ;;
        failed) echo "failed|$RED" ;;
        *) echo "unknown|$DIM" ;;
    esac
}

get_process_count() {
    local pattern="$1"
    local count=$(ssh "$DEPLOY_USER@$APP_SERVER" "ps aux | grep -c '[$pattern]' || echo '0'" 2>/dev/null || echo "0")
    echo "$count"
}

display_dashboard() {
    clear

    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            CHOM Service Status Dashboard                      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${DIM}Last updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # System Services
    echo -e "${BOLD}${CYAN}━━━ System Services ━━━${NC}"

    # Nginx
    local nginx_info=$(get_service_status "nginx")
    local nginx_status=$(echo "$nginx_info" | cut -d'|' -f1)
    local nginx_color=$(echo "$nginx_info" | cut -d'|' -f2)
    local nginx_conn=$(ssh "$DEPLOY_USER@$APP_SERVER" "ss -tan | grep -c ':80\\|:443' || echo '0'" 2>/dev/null || echo "0")

    echo -e "  Nginx:           ${nginx_color}● ${nginx_status}${NC}"
    echo -e "  └─ Connections:  $nginx_conn active"

    # PHP-FPM
    local phpfpm_service=$(ssh "$DEPLOY_USER@$APP_SERVER" "systemctl list-units --type=service --all | grep -o 'php[0-9.]*-fpm.service' | head -1" || echo "php-fpm")
    local phpfpm_info=$(get_service_status "$phpfpm_service")
    local phpfpm_status=$(echo "$phpfpm_info" | cut -d'|' -f1)
    local phpfpm_color=$(echo "$phpfpm_info" | cut -d'|' -f2)
    local phpfpm_procs=$(get_process_count "php-fpm")
    local phpfpm_version=$(ssh "$DEPLOY_USER@$APP_SERVER" "php -v 2>/dev/null | head -1 | awk '{print \$2}'" || echo "unknown")

    echo -e "  PHP-FPM:         ${phpfpm_color}● ${phpfpm_status}${NC}"
    echo -e "  ├─ Version:      $phpfpm_version"
    echo -e "  └─ Workers:      $phpfpm_procs processes"

    # PostgreSQL
    local pgsql_info=$(get_service_status "postgresql")
    local pgsql_status=$(echo "$pgsql_info" | cut -d'|' -f1)
    local pgsql_color=$(echo "$pgsql_info" | cut -d'|' -f2)

    echo -e "  PostgreSQL:      ${pgsql_color}● ${pgsql_status}${NC}"

    if [[ "$pgsql_status" == "running" ]]; then
        local pgsql_conn=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo -u postgres psql -t -c 'SELECT count(*) FROM pg_stat_activity;' 2>/dev/null | xargs" || echo "0")
        local pgsql_version=$(ssh "$DEPLOY_USER@$APP_SERVER" "sudo -u postgres psql -t -c 'SELECT version();' 2>/dev/null | head -1 | awk '{print \$2}'" || echo "unknown")

        echo -e "  ├─ Version:      $pgsql_version"
        echo -e "  └─ Connections:  $pgsql_conn active"
    fi

    # Redis
    local redis_info=$(get_service_status "redis-server")
    if [[ "$(echo $redis_info | cut -d'|' -f1)" == "unknown" ]]; then
        redis_info=$(get_service_status "redis")
    fi
    local redis_status=$(echo "$redis_info" | cut -d'|' -f1)
    local redis_color=$(echo "$redis_info" | cut -d'|' -f2)

    echo -e "  Redis:           ${redis_color}● ${redis_status}${NC}"

    if [[ "$redis_status" == "running" ]]; then
        local redis_mem=$(ssh "$DEPLOY_USER@$APP_SERVER" "redis-cli info memory 2>/dev/null | grep 'used_memory_human' | cut -d':' -f2 | tr -d '\\r'" || echo "unknown")
        local redis_keys=$(ssh "$DEPLOY_USER@$APP_SERVER" "redis-cli dbsize 2>/dev/null | awk '{print \$2}'" || echo "0")

        echo -e "  ├─ Memory:       $redis_mem"
        echo -e "  └─ Keys:         $redis_keys"
    fi

    echo ""

    # Application Services
    echo -e "${BOLD}${CYAN}━━━ Application Services ━━━${NC}"

    # Queue Workers
    local queue_workers=$(get_process_count "queue:work")

    if [[ "$queue_workers" -gt 0 ]]; then
        echo -e "  Queue Workers:   ${GREEN}● running${NC}"
        echo -e "  └─ Active:       $queue_workers workers"
    else
        echo -e "  Queue Workers:   ${YELLOW}● stopped${NC}"
        echo -e "  └─ Active:       0 workers"
    fi

    # Failed Jobs
    local failed_jobs=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan queue:failed 2>/dev/null | grep -c 'ID' || echo '0'" 2>/dev/null || echo "0")

    if [[ "$failed_jobs" -gt 0 ]]; then
        echo -e "  Failed Jobs:     ${RED}$failed_jobs${NC}"
    else
        echo -e "  Failed Jobs:     ${GREEN}0${NC}"
    fi

    echo ""

    # Supervisor (if installed)
    if ssh "$DEPLOY_USER@$APP_SERVER" "command -v supervisorctl &>/dev/null"; then
        echo -e "${BOLD}${CYAN}━━━ Supervisor Processes ━━━${NC}"

        local supervisor_info=$(get_service_status "supervisor")
        local supervisor_status=$(echo "$supervisor_info" | cut -d'|' -f1)
        local supervisor_color=$(echo "$supervisor_info" | cut -d'|' -f2)

        echo -e "  Supervisor:      ${supervisor_color}● ${supervisor_status}${NC}"

        if [[ "$supervisor_status" == "running" ]]; then
            ssh "$DEPLOY_USER@$APP_SERVER" "sudo supervisorctl status 2>/dev/null" | while read -r line; do
                local proc_name=$(echo "$line" | awk '{print $1}')
                local proc_status=$(echo "$line" | awk '{print $2}')

                if [[ "$proc_status" == "RUNNING" ]]; then
                    echo -e "  ├─ $proc_name: ${GREEN}● running${NC}"
                else
                    echo -e "  ├─ $proc_name: ${RED}● $proc_status${NC}"
                fi
            done
        fi

        echo ""
    fi

    # Scheduled Tasks
    echo -e "${BOLD}${CYAN}━━━ Scheduled Tasks (Cron) ━━━${NC}"

    local cron_entry=$(ssh "$DEPLOY_USER@$APP_SERVER" "crontab -l 2>/dev/null | grep 'artisan schedule:run' || echo ''" || echo "")

    if [[ -n "$cron_entry" ]]; then
        echo -e "  Laravel Scheduler: ${GREEN}● configured${NC}"
        echo -e "  └─ Schedule:       * * * * * (every minute)"

        # Check last run (if scheduler log exists)
        if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $APP_PATH/storage/logs/scheduler.log" &>/dev/null; then
            local last_run=$(ssh "$DEPLOY_USER@$APP_SERVER" "tail -1 $APP_PATH/storage/logs/scheduler.log 2>/dev/null | cut -c1-50" || echo "")
            if [[ -n "$last_run" ]]; then
                echo -e "  └─ Last run:       ${last_run}..."
            fi
        fi
    else
        echo -e "  Laravel Scheduler: ${YELLOW}● not configured${NC}"
    fi

    echo ""

    # System Health
    echo -e "${BOLD}${CYAN}━━━ System Health ━━━${NC}"

    # Load average
    local load_avg=$(ssh "$DEPLOY_USER@$APP_SERVER" "uptime | awk -F'load average:' '{print \$2}' | xargs" 2>/dev/null || echo "unknown")
    echo -e "  Load Average:    $load_avg"

    # Uptime
    local uptime=$(ssh "$DEPLOY_USER@$APP_SERVER" "uptime -p 2>/dev/null" || echo "unknown")
    echo -e "  Uptime:          $uptime"

    # Memory
    local mem_total_kb=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{print \$2}'" 2>/dev/null || echo "1")
    local mem_used_kb=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{print \$3}'" 2>/dev/null || echo "0")
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used_kb / $mem_total_kb) * 100}")

    local mem_color="$GREEN"
    if (( $(awk "BEGIN {print ($mem_percent > 75)}") )); then mem_color="$YELLOW"; fi
    if (( $(awk "BEGIN {print ($mem_percent > 90)}") )); then mem_color="$RED"; fi

    echo -e "  Memory Usage:    ${mem_color}${mem_percent}%${NC}"

    # Disk
    local disk_percent=$(ssh "$DEPLOY_USER@$APP_SERVER" "df /var/www | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null || echo "0")

    local disk_color="$GREEN"
    if [[ "$disk_percent" -gt 80 ]]; then disk_color="$YELLOW"; fi
    if [[ "$disk_percent" -gt 90 ]]; then disk_color="$RED"; fi

    echo -e "  Disk Usage:      ${disk_color}${disk_percent}%${NC}"

    echo ""

    if [[ "$AUTO_REFRESH" == "true" ]]; then
        echo -e "${DIM}Auto-refreshing every ${REFRESH_INTERVAL}s. Press Ctrl+C to exit.${NC}"
    else
        echo -e "${DIM}Run with --watch to enable auto-refresh${NC}"
    fi
}

main() {
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        while true; do
            display_dashboard
            sleep "$REFRESH_INTERVAL"
        done
    else
        display_dashboard
    fi
}

trap 'echo -e "\n${YELLOW}Dashboard stopped${NC}"; exit 0' INT TERM

main "$@"
