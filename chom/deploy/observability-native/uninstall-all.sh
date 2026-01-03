#!/bin/bash

###############################################################################
# Observability Stack Uninstallation Script
# Removes all native observability components
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

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

confirm_uninstall() {
    echo -e "${BOLD}${RED}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║                      WARNING                                     ║
║                                                                  ║
║   This will COMPLETELY REMOVE all observability components:     ║
║     - Prometheus (and all metrics data)                          ║
║     - Grafana (and all dashboards)                               ║
║     - Loki (and all logs)                                        ║
║     - Promtail                                                   ║
║     - AlertManager                                               ║
║     - Node Exporter                                              ║
║                                                                  ║
║   All data, configurations, and service files will be deleted.   ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    read -rp "Are you ABSOLUTELY sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi

    echo ""
    read -rp "Type 'DELETE ALL DATA' to confirm: " final_confirm
    if [[ "$final_confirm" != "DELETE ALL DATA" ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
}

backup_configs() {
    log_info "Creating backup of configurations..."

    local backup_dir="/root/observability-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup configurations
    [[ -d /etc/prometheus ]] && cp -r /etc/prometheus "$backup_dir/" 2>/dev/null || true
    [[ -d /etc/grafana ]] && cp -r /etc/grafana "$backup_dir/" 2>/dev/null || true
    [[ -d /etc/loki ]] && cp -r /etc/loki "$backup_dir/" 2>/dev/null || true
    [[ -d /etc/promtail ]] && cp -r /etc/promtail "$backup_dir/" 2>/dev/null || true
    [[ -d /etc/alertmanager ]] && cp -r /etc/alertmanager "$backup_dir/" 2>/dev/null || true

    # Create inventory
    cat > "$backup_dir/README.txt" <<EOF
Observability Stack Configuration Backup
========================================

Backup Date: $(date)
Hostname: $(hostname)

This backup contains configuration files from the observability stack
before uninstallation. Data directories are NOT included.

To restore configurations, copy the directories back to /etc/:
  cp -r prometheus /etc/
  cp -r grafana /etc/
  cp -r loki /etc/
  cp -r promtail /etc/
  cp -r alertmanager /etc/

Note: You will need to reinstall the services before restoring configs.
EOF

    log_success "Backup created: $backup_dir"
}

stop_services() {
    log_info "Stopping all services..."

    local services=(
        "prometheus"
        "grafana-server"
        "loki"
        "promtail"
        "alertmanager"
        "node_exporter"
    )

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -n "  Stopping $service... "
            systemctl stop "$service" 2>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}SKIP${NC}"
        fi
    done

    log_success "Services stopped"
}

remove_prometheus() {
    log_info "Removing Prometheus..."

    systemctl disable prometheus 2>/dev/null || true
    rm -f /etc/systemd/system/prometheus.service
    rm -f /usr/local/bin/prometheus
    rm -f /usr/local/bin/promtool
    rm -rf /etc/prometheus
    rm -rf /var/lib/prometheus
    rm -rf /var/log/prometheus

    if id prometheus >/dev/null 2>&1; then
        userdel prometheus 2>/dev/null || true
    fi
    if getent group prometheus >/dev/null 2>&1; then
        groupdel prometheus 2>/dev/null || true
    fi

    log_success "Prometheus removed"
}

remove_grafana() {
    log_info "Removing Grafana..."

    systemctl disable grafana-server 2>/dev/null || true

    # Remove APT package
    if dpkg -l | grep -q grafana; then
        apt-get purge -y grafana 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi

    rm -rf /etc/grafana
    rm -rf /var/lib/grafana
    rm -rf /var/log/grafana
    rm -f /etc/apt/sources.list.d/grafana.list
    rm -f /usr/share/keyrings/grafana.key

    if id grafana >/dev/null 2>&1; then
        userdel grafana 2>/dev/null || true
    fi
    if getent group grafana >/dev/null 2>&1; then
        groupdel grafana 2>/dev/null || true
    fi

    log_success "Grafana removed"
}

remove_loki() {
    log_info "Removing Loki..."

    systemctl disable loki 2>/dev/null || true
    rm -f /etc/systemd/system/loki.service
    rm -f /usr/local/bin/loki
    rm -rf /etc/loki
    rm -rf /var/lib/loki
    rm -rf /var/log/loki

    if id loki >/dev/null 2>&1; then
        userdel loki 2>/dev/null || true
    fi
    if getent group loki >/dev/null 2>&1; then
        groupdel loki 2>/dev/null || true
    fi

    log_success "Loki removed"
}

remove_promtail() {
    log_info "Removing Promtail..."

    systemctl disable promtail 2>/dev/null || true
    rm -f /etc/systemd/system/promtail.service
    rm -f /usr/local/bin/promtail
    rm -rf /etc/promtail
    rm -rf /var/lib/promtail
    rm -rf /var/log/promtail

    if id promtail >/dev/null 2>&1; then
        userdel promtail 2>/dev/null || true
    fi
    if getent group promtail >/dev/null 2>&1; then
        groupdel promtail 2>/dev/null || true
    fi

    log_success "Promtail removed"
}

remove_alertmanager() {
    log_info "Removing AlertManager..."

    systemctl disable alertmanager 2>/dev/null || true
    rm -f /etc/systemd/system/alertmanager.service
    rm -f /usr/local/bin/alertmanager
    rm -f /usr/local/bin/amtool
    rm -rf /etc/alertmanager
    rm -rf /var/lib/alertmanager
    rm -rf /var/log/alertmanager

    if id alertmanager >/dev/null 2>&1; then
        userdel alertmanager 2>/dev/null || true
    fi
    if getent group alertmanager >/dev/null 2>&1; then
        groupdel alertmanager 2>/dev/null || true
    fi

    log_success "AlertManager removed"
}

remove_node_exporter() {
    log_info "Removing Node Exporter..."

    systemctl disable node_exporter 2>/dev/null || true
    rm -f /etc/systemd/system/node_exporter.service
    rm -f /usr/local/bin/node_exporter
    rm -rf /var/lib/node_exporter
    rm -f /usr/local/bin/generate-custom-metrics.sh

    if id node_exporter >/dev/null 2>&1; then
        userdel node_exporter 2>/dev/null || true
    fi
    if getent group node_exporter >/dev/null 2>&1; then
        groupdel node_exporter 2>/dev/null || true
    fi

    log_success "Node Exporter removed"
}

cleanup_firewall() {
    log_info "Cleaning up firewall rules..."

    if command -v ufw &> /dev/null; then
        ufw delete allow 9090/tcp 2>/dev/null || true  # Prometheus
        ufw delete allow 3000/tcp 2>/dev/null || true  # Grafana
        ufw delete allow 3100/tcp 2>/dev/null || true  # Loki
        ufw delete allow 9096/tcp 2>/dev/null || true  # Loki gRPC
        ufw delete allow 9093/tcp 2>/dev/null || true  # AlertManager
        ufw delete allow 9100/tcp 2>/dev/null || true  # Node Exporter
        log_success "UFW rules removed"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-port=9090/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=3000/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=3100/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=9096/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=9093/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=9100/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_success "Firewalld rules removed"
    fi
}

reload_systemd() {
    log_info "Reloading systemd..."
    systemctl daemon-reload
    log_success "Systemd reloaded"
}

remove_documentation() {
    log_info "Removing installation documentation..."

    rm -f /root/observability-stack-info.txt
    rm -f /root/grafana-credentials.txt
    rm -f /var/log/observability-install.log

    log_success "Documentation removed"
}

final_cleanup() {
    log_info "Performing final cleanup..."

    # Remove any remaining temporary files
    find /tmp -name "*prometheus*" -o -name "*grafana*" -o -name "*loki*" -o -name "*promtail*" 2>/dev/null | \
        xargs rm -rf 2>/dev/null || true

    log_success "Cleanup complete"
}

show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║              Uninstallation Complete                             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${BOLD}Removed Components:${NC}"
    echo "  - Prometheus"
    echo "  - Grafana"
    echo "  - Loki"
    echo "  - Promtail"
    echo "  - AlertManager"
    echo "  - Node Exporter"
    echo ""

    if [[ -d /root/observability-backup-* ]]; then
        local backup_dir=$(ls -dt /root/observability-backup-* | head -1)
        echo -e "${BOLD}Configuration Backup:${NC}"
        echo "  $backup_dir"
        echo ""
    fi

    echo -e "${BOLD}Verification:${NC}"
    echo "  Check for any remaining files:"
    echo "    ls -la /etc/ | grep -E 'prometheus|grafana|loki|promtail|alertmanager'"
    echo "    ls -la /var/lib/ | grep -E 'prometheus|grafana|loki|promtail|alertmanager'"
    echo ""
    echo "  Check for running processes:"
    echo "    ps aux | grep -E 'prometheus|grafana|loki|promtail|alertmanager|node_exporter'"
    echo ""
    echo "  Check for listening ports:"
    echo "    ss -tlnp | grep -E '9090|3000|3100|9093|9100'"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   Observability Stack Uninstaller                      ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    check_root
    confirm_uninstall

    echo ""
    log_info "Starting uninstallation..."
    echo ""

    backup_configs
    stop_services
    remove_prometheus
    remove_grafana
    remove_loki
    remove_promtail
    remove_alertmanager
    remove_node_exporter
    cleanup_firewall
    reload_systemd
    remove_documentation
    final_cleanup

    show_summary

    log_success "All observability components have been removed"
    echo ""
}

main "$@"
