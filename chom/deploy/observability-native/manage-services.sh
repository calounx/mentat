#!/bin/bash

###############################################################################
# Observability Stack Service Management Script
# Manage all observability services from one place
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Services
SERVICES=(
    "prometheus"
    "grafana-server"
    "loki"
    "promtail"
    "alertmanager"
    "node_exporter"
)

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   Observability Stack Service Manager                  ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

service_exists() {
    local service=$1
    systemctl list-unit-files | grep -q "^${service}.service"
}

get_service_status() {
    local service=$1

    if ! service_exists "$service"; then
        echo "not-installed"
        return
    fi

    if systemctl is-active --quiet "$service"; then
        echo "running"
    elif systemctl is-enabled --quiet "$service"; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

get_status_color() {
    local status=$1
    case $status in
        running)
            echo "${GREEN}"
            ;;
        stopped)
            echo "${YELLOW}"
            ;;
        disabled)
            echo "${RED}"
            ;;
        not-installed)
            echo "${MAGENTA}"
            ;;
        *)
            echo "${NC}"
            ;;
    esac
}

show_status() {
    echo -e "${BOLD}Service Status Overview${NC}"
    echo ""
    printf "%-20s %-15s %-10s %s\n" "SERVICE" "STATUS" "ENABLED" "UPTIME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for service in "${SERVICES[@]}"; do
        local status=$(get_service_status "$service")
        local color=$(get_status_color "$status")
        local enabled="N/A"
        local uptime="N/A"

        if [[ "$status" != "not-installed" ]]; then
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                enabled="${GREEN}yes${NC}"
            else
                enabled="${RED}no${NC}"
            fi

            if [[ "$status" == "running" ]]; then
                uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value | xargs -I {} date -d "{}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
            fi
        fi

        printf "%-20s ${color}%-15s${NC} %-18s %s\n" "$service" "$status" "$enabled" "$uptime"
    done

    echo ""
}

start_all() {
    log_info "Starting all observability services..."
    local failed=0

    for service in "${SERVICES[@]}"; do
        if service_exists "$service"; then
            echo -n "Starting $service... "
            if systemctl start "$service" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                ((failed++))
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All services started successfully"
    else
        log_error "$failed service(s) failed to start"
        return 1
    fi
}

stop_all() {
    log_info "Stopping all observability services..."
    local failed=0

    for service in "${SERVICES[@]}"; do
        if service_exists "$service"; then
            echo -n "Stopping $service... "
            if systemctl stop "$service" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                ((failed++))
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All services stopped successfully"
    else
        log_error "$failed service(s) failed to stop"
        return 1
    fi
}

restart_all() {
    log_info "Restarting all observability services..."
    local failed=0

    for service in "${SERVICES[@]}"; do
        if service_exists "$service"; then
            echo -n "Restarting $service... "
            if systemctl restart "$service" 2>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FAILED${NC}"
                ((failed++))
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All services restarted successfully"
    else
        log_error "$failed service(s) failed to restart"
        return 1
    fi
}

reload_all() {
    log_info "Reloading all observability service configurations..."
    local failed=0

    for service in "${SERVICES[@]}"; do
        if service_exists "$service"; then
            if systemctl is-active --quiet "$service"; then
                echo -n "Reloading $service... "
                if systemctl reload "$service" 2>/dev/null; then
                    echo -e "${GREEN}OK${NC}"
                else
                    # Some services don't support reload, try restart
                    if systemctl restart "$service" 2>/dev/null; then
                        echo -e "${YELLOW}RESTARTED${NC}"
                    else
                        echo -e "${RED}FAILED${NC}"
                        ((failed++))
                    fi
                fi
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All configurations reloaded successfully"
    else
        log_error "$failed service(s) failed to reload"
        return 1
    fi
}

show_logs() {
    local service=$1
    local lines=${2:-50}

    if ! service_exists "$service"; then
        log_error "Service $service not found"
        return 1
    fi

    echo -e "${BOLD}Last $lines lines from $service:${NC}"
    echo ""
    journalctl -u "$service" -n "$lines" --no-pager
}

follow_logs() {
    local service=$1

    if ! service_exists "$service"; then
        log_error "Service $service not found"
        return 1
    fi

    log_info "Following logs for $service (Ctrl+C to exit)"
    journalctl -u "$service" -f
}

check_health() {
    echo -e "${BOLD}Health Check${NC}"
    echo ""

    # Prometheus
    if service_exists "prometheus"; then
        echo -n "Prometheus health: "
        if curl -sf http://localhost:9090/-/healthy >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi

    # Grafana
    if service_exists "grafana-server"; then
        echo -n "Grafana health: "
        if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi

    # Loki
    if service_exists "loki"; then
        echo -n "Loki health: "
        if curl -sf http://localhost:3100/ready >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi

    # Promtail
    if service_exists "promtail"; then
        echo -n "Promtail health: "
        if curl -sf http://localhost:9080/ready >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi

    # AlertManager
    if service_exists "alertmanager"; then
        echo -n "AlertManager health: "
        if curl -sf http://localhost:9093/-/healthy >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi

    # Node Exporter
    if service_exists "node_exporter"; then
        echo -n "Node Exporter health: "
        if curl -sf http://localhost:9100/metrics | head -1 | grep -q "# HELP"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi

    echo ""
}

show_ports() {
    echo -e "${BOLD}Service Ports${NC}"
    echo ""
    printf "%-20s %-10s %s\n" "SERVICE" "PORT" "STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local ports=(
        "prometheus:9090"
        "grafana:3000"
        "loki:3100"
        "promtail:9080"
        "alertmanager:9093"
        "node_exporter:9100"
    )

    for entry in "${ports[@]}"; do
        local service="${entry%%:*}"
        local port="${entry##*:}"
        local status="closed"

        if ss -tlnp | grep -q ":${port} "; then
            status="${GREEN}listening${NC}"
        else
            status="${RED}closed${NC}"
        fi

        printf "%-20s %-10s %s\n" "$service" "$port" "$status"
    done

    echo ""
}

show_disk_usage() {
    echo -e "${BOLD}Disk Usage${NC}"
    echo ""

    local dirs=(
        "/var/lib/prometheus"
        "/var/lib/grafana"
        "/var/lib/loki"
        "/var/lib/alertmanager"
        "/etc/prometheus"
        "/etc/grafana"
        "/etc/loki"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            printf "%-30s %s\n" "$dir" "$size"
        fi
    done

    echo ""
}

interactive_menu() {
    while true; do
        clear
        print_header
        show_status

        echo -e "${BOLD}Actions:${NC}"
        echo "  1) Start all services"
        echo "  2) Stop all services"
        echo "  3) Restart all services"
        echo "  4) Reload configurations"
        echo "  5) Check health"
        echo "  6) Show ports"
        echo "  7) Show disk usage"
        echo "  8) View logs"
        echo "  9) Follow logs"
        echo "  0) Exit"
        echo ""
        read -rp "Select action: " action

        case $action in
            1)
                start_all
                read -rp "Press Enter to continue..."
                ;;
            2)
                stop_all
                read -rp "Press Enter to continue..."
                ;;
            3)
                restart_all
                read -rp "Press Enter to continue..."
                ;;
            4)
                reload_all
                read -rp "Press Enter to continue..."
                ;;
            5)
                check_health
                read -rp "Press Enter to continue..."
                ;;
            6)
                show_ports
                read -rp "Press Enter to continue..."
                ;;
            7)
                show_disk_usage
                read -rp "Press Enter to continue..."
                ;;
            8)
                echo "Available services:"
                for i in "${!SERVICES[@]}"; do
                    echo "  $((i+1))) ${SERVICES[$i]}"
                done
                read -rp "Select service (1-${#SERVICES[@]}): " svc_num
                if [[ $svc_num -ge 1 && $svc_num -le ${#SERVICES[@]} ]]; then
                    show_logs "${SERVICES[$((svc_num-1))]}"
                fi
                read -rp "Press Enter to continue..."
                ;;
            9)
                echo "Available services:"
                for i in "${!SERVICES[@]}"; do
                    echo "  $((i+1))) ${SERVICES[$i]}"
                done
                read -rp "Select service (1-${#SERVICES[@]}): " svc_num
                if [[ $svc_num -ge 1 && $svc_num -le ${#SERVICES[@]} ]]; then
                    follow_logs "${SERVICES[$((svc_num-1))]}"
                fi
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid selection"
                sleep 1
                ;;
        esac
    done
}

show_help() {
    cat <<EOF
Observability Stack Service Manager

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  status              Show status of all services
  start               Start all services
  stop                Stop all services
  restart             Restart all services
  reload              Reload service configurations
  health              Check health endpoints
  ports               Show listening ports
  disk                Show disk usage
  logs SERVICE [N]    Show last N lines of logs (default: 50)
  follow SERVICE      Follow logs in real-time
  interactive         Interactive menu (default)

Examples:
  $0 status                    # Show service status
  $0 restart                   # Restart all services
  $0 logs prometheus 100       # Show last 100 lines of Prometheus logs
  $0 follow grafana-server     # Follow Grafana logs in real-time

Available services:
  prometheus, grafana-server, loki, promtail, alertmanager, node_exporter

EOF
}

main() {
    local command=${1:-interactive}

    case $command in
        status)
            print_header
            show_status
            ;;
        start)
            check_root
            start_all
            ;;
        stop)
            check_root
            stop_all
            ;;
        restart)
            check_root
            restart_all
            ;;
        reload)
            check_root
            reload_all
            ;;
        health)
            check_health
            ;;
        ports)
            show_ports
            ;;
        disk)
            show_disk_usage
            ;;
        logs)
            if [[ -z ${2:-} ]]; then
                log_error "Please specify a service"
                exit 1
            fi
            show_logs "$2" "${3:-50}"
            ;;
        follow)
            if [[ -z ${2:-} ]]; then
                log_error "Please specify a service"
                exit 1
            fi
            follow_logs "$2"
            ;;
        interactive)
            check_root
            interactive_menu
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
