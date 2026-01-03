#!/bin/bash

###############################################################################
# Master Observability Stack Installation Script
# Native Debian 13 - NO DOCKER
# Installs: Prometheus, Grafana, Loki, Promtail, AlertManager, Node Exporter
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/observability-install.log"
MONITORING_SERVER="mentat.arewel.com"
APP_SERVER="landsraad.arewel.com"

# Component selection (can be overridden with environment variables)
INSTALL_PROMETHEUS="${INSTALL_PROMETHEUS:-true}"
INSTALL_GRAFANA="${INSTALL_GRAFANA:-true}"
INSTALL_LOKI="${INSTALL_LOKI:-true}"
INSTALL_PROMTAIL="${INSTALL_PROMTAIL:-true}"
INSTALL_ALERTMANAGER="${INSTALL_ALERTMANAGER:-true}"
INSTALL_NODE_EXPORTER="${INSTALL_NODE_EXPORTER:-true}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN} $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

print_banner() {
    clear
    echo -e "${BOLD}${MAGENTA}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     CHOM Observability Stack Installation                       ║
║     Native Debian 13 - NO DOCKER                                ║
║                                                                  ║
║     Components:                                                  ║
║       - Prometheus (Metrics Collection)                          ║
║       - Grafana (Visualization)                                  ║
║       - Loki (Log Aggregation)                                   ║
║       - Promtail (Log Shipping)                                  ║
║       - AlertManager (Alert Routing)                             ║
║       - Node Exporter (System Metrics)                           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_debian_version() {
    log_info "Checking Debian version..."

    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script requires Debian"
        exit 1
    fi

    local debian_version=$(cat /etc/debian_version | cut -d. -f1)
    log_info "Detected Debian version: $(cat /etc/debian_version)"

    if [[ "$debian_version" -lt 11 ]]; then
        log_warning "This script is designed for Debian 11+, your version might not be fully supported"
    fi
}

check_system_requirements() {
    log_section "System Requirements Check"

    # Check available disk space (need at least 10GB)
    local available_gb=$(df / | tail -1 | awk '{print $4}' | xargs -I {} echo "scale=0; {}/1024/1024" | bc)
    log_info "Available disk space: ${available_gb}GB"

    if [[ "$available_gb" -lt 10 ]]; then
        log_error "Insufficient disk space. Need at least 10GB free."
        exit 1
    fi

    # Check available RAM (need at least 2GB)
    local available_ram_mb=$(free -m | grep Mem: | awk '{print $2}')
    local available_ram_gb=$(echo "scale=1; $available_ram_mb/1024" | bc)
    log_info "Available RAM: ${available_ram_gb}GB"

    if [[ "$available_ram_mb" -lt 2048 ]]; then
        log_warning "Less than 2GB RAM available. Performance may be degraded."
    fi

    # Check CPU cores
    local cpu_cores=$(nproc)
    log_info "CPU cores: $cpu_cores"

    if [[ "$cpu_cores" -lt 2 ]]; then
        log_warning "Less than 2 CPU cores. Consider upgrading for better performance."
    fi

    log_success "System requirements check complete"
}

install_prerequisites() {
    log_section "Installing Prerequisites"

    log_info "Updating package cache..."
    apt-get update -qq

    log_info "Installing required packages..."
    apt-get install -y -qq \
        curl \
        wget \
        tar \
        gzip \
        unzip \
        ca-certificates \
        gnupg2 \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        bc \
        jq

    log_success "Prerequisites installed"
}

run_component_installer() {
    local component=$1
    local script=$2

    log_section "Installing $component"

    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        log_error "Installer script not found: $SCRIPT_DIR/$script"
        return 1
    fi

    chmod +x "$SCRIPT_DIR/$script"

    log_info "Running $script..."

    if bash "$SCRIPT_DIR/$script" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "$component installed successfully"
        return 0
    else
        log_error "$component installation failed"
        return 1
    fi
}

install_components() {
    local failed_components=()

    if [[ "$INSTALL_NODE_EXPORTER" == "true" ]]; then
        run_component_installer "Node Exporter" "install-node-exporter.sh" || failed_components+=("Node Exporter")
    fi

    if [[ "$INSTALL_PROMETHEUS" == "true" ]]; then
        run_component_installer "Prometheus" "install-prometheus.sh" || failed_components+=("Prometheus")
    fi

    if [[ "$INSTALL_ALERTMANAGER" == "true" ]]; then
        run_component_installer "AlertManager" "install-alertmanager.sh" || failed_components+=("AlertManager")
    fi

    if [[ "$INSTALL_LOKI" == "true" ]]; then
        run_component_installer "Loki" "install-loki.sh" || failed_components+=("Loki")
    fi

    if [[ "$INSTALL_PROMTAIL" == "true" ]]; then
        run_component_installer "Promtail" "install-promtail.sh" || failed_components+=("Promtail")
    fi

    if [[ "$INSTALL_GRAFANA" == "true" ]]; then
        run_component_installer "Grafana" "install-grafana.sh" || failed_components+=("Grafana")
    fi

    # Report failures
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        log_warning "The following components failed to install:"
        for component in "${failed_components[@]}"; do
            log_warning "  - $component"
        done
        return 1
    fi

    return 0
}

verify_services() {
    log_section "Verifying Services"

    local services=()
    [[ "$INSTALL_PROMETHEUS" == "true" ]] && services+=("prometheus")
    [[ "$INSTALL_GRAFANA" == "true" ]] && services+=("grafana-server")
    [[ "$INSTALL_LOKI" == "true" ]] && services+=("loki")
    [[ "$INSTALL_PROMTAIL" == "true" ]] && services+=("promtail")
    [[ "$INSTALL_ALERTMANAGER" == "true" ]] && services+=("alertmanager")
    [[ "$INSTALL_NODE_EXPORTER" == "true" ]] && services+=("node_exporter")

    local failed_services=()

    for service in "${services[@]}"; do
        log_info "Checking $service..."
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_error "$service is not running"
            failed_services+=("$service")
        fi
    done

    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warning "The following services are not running:"
        for service in "${failed_services[@]}"; do
            log_warning "  - $service"
            log_info "Status:"
            systemctl status "$service" --no-pager | head -20 | tee -a "$LOG_FILE"
        done
        return 1
    fi

    log_success "All services are running"
    return 0
}

create_monitoring_summary() {
    log_section "Creating Monitoring Summary"

    cat > /root/observability-stack-info.txt <<EOF
CHOM Observability Stack - Installation Summary
================================================

Installation Date: $(date)
Hostname: $(hostname)
Server: $MONITORING_SERVER

Components Installed
====================

$(if [[ "$INSTALL_PROMETHEUS" == "true" ]]; then
    echo "✓ Prometheus - http://localhost:9090"
    echo "  - Metrics collection and querying"
    echo "  - Config: /etc/prometheus/prometheus.yml"
    echo "  - Service: systemctl status prometheus"
    echo ""
fi)

$(if [[ "$INSTALL_GRAFANA" == "true" ]]; then
    echo "✓ Grafana - http://localhost:3000"
    echo "  - Dashboards and visualization"
    echo "  - Default login: admin / changeme (CHANGE THIS!)"
    echo "  - Config: /etc/grafana/grafana.ini"
    echo "  - Service: systemctl status grafana-server"
    echo ""
fi)

$(if [[ "$INSTALL_LOKI" == "true" ]]; then
    echo "✓ Loki - http://localhost:3100"
    echo "  - Log aggregation"
    echo "  - Config: /etc/loki/loki.yml"
    echo "  - Service: systemctl status loki"
    echo ""
fi)

$(if [[ "$INSTALL_PROMTAIL" == "true" ]]; then
    echo "✓ Promtail - http://localhost:9080"
    echo "  - Log shipping to Loki"
    echo "  - Config: /etc/promtail/promtail.yml"
    echo "  - Service: systemctl status promtail"
    echo ""
fi)

$(if [[ "$INSTALL_ALERTMANAGER" == "true" ]]; then
    echo "✓ AlertManager - http://localhost:9093"
    echo "  - Alert routing and notifications"
    echo "  - Config: /etc/alertmanager/alertmanager.yml"
    echo "  - Service: systemctl status alertmanager"
    echo ""
fi)

$(if [[ "$INSTALL_NODE_EXPORTER" == "true" ]]; then
    echo "✓ Node Exporter - http://localhost:9100"
    echo "  - System metrics collection"
    echo "  - Service: systemctl status node_exporter"
    echo ""
fi)

Quick Start
===========

1. Access Grafana: http://$MONITORING_SERVER:3000
   - Login: admin / changeme
   - CHANGE PASSWORD IMMEDIATELY!

2. Verify Prometheus: http://$MONITORING_SERVER:9090
   - Check targets: http://$MONITORING_SERVER:9090/targets
   - All targets should be "UP"

3. Check AlertManager: http://$MONITORING_SERVER:9093
   - Review alert routing configuration

4. View Logs in Grafana:
   - Use the Loki datasource
   - Query: {job="chom"}

Common Commands
===============

Service Management:
  systemctl status <service>   - Check service status
  systemctl restart <service>  - Restart service
  systemctl stop <service>     - Stop service
  systemctl start <service>    - Start service

View Logs:
  journalctl -u prometheus -f
  journalctl -u grafana-server -f
  journalctl -u loki -f
  journalctl -u promtail -f
  journalctl -u alertmanager -f
  journalctl -u node_exporter -f

Configuration Files:
  /etc/prometheus/prometheus.yml
  /etc/grafana/grafana.ini
  /etc/loki/loki.yml
  /etc/promtail/promtail.yml
  /etc/alertmanager/alertmanager.yml

Service Files:
  /etc/systemd/system/prometheus.service
  /etc/systemd/system/grafana-server.service (via APT)
  /etc/systemd/system/loki.service
  /etc/systemd/system/promtail.service
  /etc/systemd/system/alertmanager.service
  /etc/systemd/system/node_exporter.service

Next Steps
==========

1. Change Grafana admin password
2. Configure AlertManager email notifications
3. Import Grafana dashboards from /var/lib/grafana/dashboards
4. Review and adjust Prometheus scrape targets
5. Configure alert rules in /etc/prometheus/rules/
6. Set up backup for configuration files
7. Review security settings and firewall rules

Troubleshooting
===============

If a service fails to start:
  1. Check logs: journalctl -u <service> -n 100
  2. Verify config: Use service-specific validation tools
  3. Check permissions: ls -la /etc/<service>/
  4. Check ports: ss -tlnp | grep <port>

Installation Log: $LOG_FILE

EOF

    chmod 600 /root/observability-stack-info.txt
    log_success "Summary created: /root/observability-stack-info.txt"
}

print_final_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║              Installation Complete!                              ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${BOLD}Access URLs:${NC}"
    [[ "$INSTALL_GRAFANA" == "true" ]] && echo -e "  Grafana:      ${CYAN}http://$MONITORING_SERVER:3000${NC} (admin/changeme)"
    [[ "$INSTALL_PROMETHEUS" == "true" ]] && echo -e "  Prometheus:   ${CYAN}http://$MONITORING_SERVER:9090${NC}"
    [[ "$INSTALL_ALERTMANAGER" == "true" ]] && echo -e "  AlertManager: ${CYAN}http://$MONITORING_SERVER:9093${NC}"
    [[ "$INSTALL_LOKI" == "true" ]] && echo -e "  Loki:         ${CYAN}http://$MONITORING_SERVER:3100${NC}"

    echo ""
    echo -e "${BOLD}${YELLOW}IMPORTANT:${NC}"
    echo -e "  1. ${RED}Change Grafana password immediately!${NC}"
    echo -e "  2. Configure AlertManager email notifications"
    echo -e "  3. Review firewall rules for production use"
    echo ""
    echo -e "${BOLD}Documentation:${NC}"
    echo -e "  Installation summary: ${CYAN}/root/observability-stack-info.txt${NC}"
    echo -e "  Installation log:     ${CYAN}$LOG_FILE${NC}"
    echo ""
    echo -e "${BOLD}Quick Health Check:${NC}"
    echo -e "  systemctl status prometheus grafana-server loki promtail alertmanager node_exporter"
    echo ""
}

main() {
    print_banner

    # Initialize log
    echo "=== Observability Stack Installation Started: $(date) ===" > "$LOG_FILE"

    check_root
    check_debian_version
    check_system_requirements
    install_prerequisites

    # Install all components
    if install_components; then
        log_success "All components installed successfully"
    else
        log_warning "Some components failed to install. Check logs for details."
    fi

    # Wait for services to stabilize
    log_info "Waiting for services to stabilize..."
    sleep 5

    # Verify services
    verify_services || log_warning "Some services are not running properly"

    # Create summary
    create_monitoring_summary

    # Print final summary
    print_final_summary

    echo "=== Observability Stack Installation Completed: $(date) ===" >> "$LOG_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-prometheus)
            INSTALL_PROMETHEUS=false
            shift
            ;;
        --no-grafana)
            INSTALL_GRAFANA=false
            shift
            ;;
        --no-loki)
            INSTALL_LOKI=false
            shift
            ;;
        --no-promtail)
            INSTALL_PROMTAIL=false
            shift
            ;;
        --no-alertmanager)
            INSTALL_ALERTMANAGER=false
            shift
            ;;
        --no-node-exporter)
            INSTALL_NODE_EXPORTER=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-prometheus      Skip Prometheus installation"
            echo "  --no-grafana         Skip Grafana installation"
            echo "  --no-loki            Skip Loki installation"
            echo "  --no-promtail        Skip Promtail installation"
            echo "  --no-alertmanager    Skip AlertManager installation"
            echo "  --no-node-exporter   Skip Node Exporter installation"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Example:"
            echo "  $0                   # Install all components"
            echo "  $0 --no-grafana      # Install all except Grafana"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main "$@"
