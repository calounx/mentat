#!/usr/bin/env bash
# Deploy observability stack to mentat.arewel.com
# NATIVE INSTALLATION - No Docker, uses systemd services
# Usage: ./deploy-observability.sh [--config-dir /path/to/config]

set -euo pipefail

# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
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
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

source "${SCRIPT_DIR}/../utils/logging.sh"
source "${SCRIPT_DIR}/../utils/dependency-validation.sh"

# Configuration
OBSERVABILITY_DIR="${OBSERVABILITY_DIR:-/opt/observability}"
CONFIG_DIR="${CONFIG_DIR:-/etc/observability}"
DATA_DIR="${DATA_DIR:-/var/lib/observability}"
DEPLOY_USER="${DEPLOY_USER:-stilgar}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config-dir)
            SRC_CONFIG_DIR="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

SRC_CONFIG_DIR="${SRC_CONFIG_DIR:-${SCRIPT_DIR}/../config/mentat}"

init_deployment_log "deploy-observability-$(date +%Y%m%d_%H%M%S)"
log_section "Observability Stack Deployment (NATIVE)"

# Deploy systemd service files with correct configuration
deploy_systemd_services() {
    log_step "Deploying systemd service files"

    # Prometheus service with external-url for path prefix support
    cat << EOF | sudo tee /etc/systemd/system/prometheus.service > /dev/null
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=${OBSERVABILITY_DIR}/bin/prometheus \\
    --config.file=${CONFIG_DIR}/prometheus/prometheus.yml \\
    --storage.tsdb.path=${DATA_DIR}/prometheus \\
    --storage.tsdb.retention.time=15d \\
    --web.listen-address=:9090 \\
    --web.enable-lifecycle \\
    --web.external-url=https://mentat.arewel.com/prometheus \\
    --web.route-prefix=/prometheus
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    log_success "Prometheus service deployed"

    # Alertmanager service with external-url
    cat << EOF | sudo tee /etc/systemd/system/alertmanager.service > /dev/null
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=${OBSERVABILITY_DIR}/bin/alertmanager \\
    --config.file=${CONFIG_DIR}/alertmanager/alertmanager.yml \\
    --storage.path=${DATA_DIR}/alertmanager \\
    --web.external-url=https://mentat.arewel.com/alertmanager \\
    --web.route-prefix=/alertmanager
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    log_success "Alertmanager service deployed"

    sudo systemctl daemon-reload
    log_success "Systemd daemon reloaded"
}

# Deploy nginx configuration
deploy_nginx_config() {
    log_step "Deploying nginx configuration"

    local nginx_src="${SRC_CONFIG_DIR}/nginx-observability.conf"
    local nginx_dest="/etc/nginx/sites-available/observability"

    if [[ -f "$nginx_src" ]]; then
        sudo cp "$nginx_src" "$nginx_dest"
        sudo ln -sf "$nginx_dest" /etc/nginx/sites-enabled/observability
        sudo rm -f /etc/nginx/sites-enabled/default

        # Test nginx configuration
        if sudo nginx -t 2>&1; then
            sudo systemctl reload nginx
            log_success "Nginx configuration deployed and reloaded"
        else
            log_error "Nginx configuration test failed"
            return 1
        fi
    else
        log_info "No custom nginx config found, using default"
    fi
}

# Deploy Grafana dashboards
deploy_grafana_dashboards() {
    log_step "Deploying Grafana dashboards"

    local dashboard_src="${SRC_CONFIG_DIR}/grafana-dashboards"
    local dashboard_dest="/var/lib/grafana/dashboards"
    local provisioning_dir="/etc/grafana/provisioning/dashboards"

    # Create dashboard provisioning config
    sudo mkdir -p "$provisioning_dir"
    sudo mkdir -p "$dashboard_dest"

    # Create provisioning YAML
    cat << 'DASHBOARD_YAML' | sudo tee "${provisioning_dir}/chom.yaml" > /dev/null
apiVersion: 1

providers:
  - name: 'CHOM'
    orgId: 1
    folder: 'CHOM'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards/chom
      foldersFromFilesStructure: false
DASHBOARD_YAML
    log_success "Dashboard provisioning config created"

    # Copy dashboards if they exist
    if [[ -d "$dashboard_src" ]]; then
        sudo mkdir -p "${dashboard_dest}/chom"
        sudo cp "${dashboard_src}"/*.json "${dashboard_dest}/chom/" 2>/dev/null || true
        sudo chown -R grafana:grafana "${dashboard_dest}"

        local count=$(ls -1 "${dashboard_src}"/*.json 2>/dev/null | wc -l)
        log_success "Deployed ${count} Grafana dashboard(s)"
    else
        log_info "No dashboards found in ${dashboard_src}"
    fi
}

# Deploy configuration files
deploy_configuration() {
    log_step "Deploying configuration files"

    # Ensure Prometheus targets directory exists
    sudo mkdir -p "${CONFIG_DIR}/prometheus/targets"
    sudo chown observability:observability "${CONFIG_DIR}/prometheus/targets"

    # Copy Prometheus configuration if exists
    if [[ -f "${SRC_CONFIG_DIR}/prometheus.yml" ]]; then
        sudo cp "${SRC_CONFIG_DIR}/prometheus.yml" "${CONFIG_DIR}/prometheus/"
        sudo chown observability:observability "${CONFIG_DIR}/prometheus/prometheus.yml"
        log_success "Prometheus configuration deployed"
    else
        log_info "Using default Prometheus configuration"
    fi

    # Copy AlertManager configuration if exists
    if [[ -f "${SRC_CONFIG_DIR}/alertmanager.yml" ]]; then
        sudo cp "${SRC_CONFIG_DIR}/alertmanager.yml" "${CONFIG_DIR}/alertmanager/"
        sudo chown observability:observability "${CONFIG_DIR}/alertmanager/alertmanager.yml"
        log_success "AlertManager configuration deployed"
    else
        log_info "Using default AlertManager configuration"
    fi

    # Copy Grafana datasources if exists
    if [[ -f "${SRC_CONFIG_DIR}/grafana-datasources.yml" ]]; then
        sudo mkdir -p /etc/grafana/provisioning/datasources
        sudo cp "${SRC_CONFIG_DIR}/grafana-datasources.yml" /etc/grafana/provisioning/datasources/datasources.yaml
        log_success "Grafana datasources deployed"
    else
        log_info "Using default Grafana datasources"
    fi

    # Deploy Grafana dashboards
    deploy_grafana_dashboards

    # Ensure Loki directories exist with correct permissions
    log_step "Ensuring Loki directories and permissions"
    sudo mkdir -p "${DATA_DIR}/loki"/{chunks,rules,compactor,rules-temp}
    sudo mkdir -p "${CONFIG_DIR}/loki"
    sudo chown -R observability:observability "${DATA_DIR}/loki"
    sudo chown -R observability:observability "${CONFIG_DIR}/loki"
    log_success "Loki directories verified"

    # Copy Loki configuration if exists
    if [[ -f "${SRC_CONFIG_DIR}/loki-config.yml" ]]; then
        sudo cp "${SRC_CONFIG_DIR}/loki-config.yml" "${CONFIG_DIR}/loki/"
        sudo chown observability:observability "${CONFIG_DIR}/loki/loki-config.yml"
        log_success "Loki configuration deployed"
    else
        log_info "Using default Loki configuration"
    fi

    # Copy Promtail configuration if exists
    if [[ -f "${SRC_CONFIG_DIR}/promtail-config.yml" ]]; then
        sudo cp "${SRC_CONFIG_DIR}/promtail-config.yml" "${CONFIG_DIR}/promtail/"
        sudo chown observability:observability "${CONFIG_DIR}/promtail/promtail-config.yml"
        log_success "Promtail configuration deployed"
    else
        log_info "Using default Promtail configuration"
    fi

    # Deploy Prometheus alert rules
    deploy_alert_rules

    log_success "Configuration files deployed"
}

# Deploy Prometheus alert rules
deploy_alert_rules() {
    log_step "Deploying Prometheus alert rules"

    local alerts_src="${SRC_CONFIG_DIR}/prometheus-alerts"
    local alerts_dest="${CONFIG_DIR}/prometheus/rules"

    sudo mkdir -p "$alerts_dest"

    if [[ -d "$alerts_src" ]]; then
        sudo cp "${alerts_src}"/*.yml "${alerts_dest}/" 2>/dev/null || true
        sudo chown -R observability:observability "${alerts_dest}"

        local count=$(ls -1 "${alerts_src}"/*.yml 2>/dev/null | wc -l)
        log_success "Deployed ${count} alert rule file(s)"
    else
        log_info "No alert rules found in ${alerts_src}"
    fi
}

# Validate configuration files
validate_configuration() {
    log_step "Validating configuration files"

    local validation_failed=0

    # Validate Prometheus configuration
    if sudo -u observability ${OBSERVABILITY_DIR}/bin/promtool check config "${CONFIG_DIR}/prometheus/prometheus.yml" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Prometheus configuration is valid"
    else
        log_error "Prometheus configuration validation failed"
        validation_failed=1
    fi

    # Validate AlertManager configuration
    if sudo -u observability ${OBSERVABILITY_DIR}/bin/amtool check-config "${CONFIG_DIR}/alertmanager/alertmanager.yml" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "AlertManager configuration is valid"
    else
        log_error "AlertManager configuration validation failed"
        validation_failed=1
    fi

    if [[ $validation_failed -eq 1 ]]; then
        log_error "Configuration validation failed"
        return 1
    fi

    log_success "All configurations are valid"
}

# Stop all services
stop_services() {
    log_step "Stopping existing observability services"

    local services=("prometheus" "grafana-server" "loki" "promtail" "alertmanager" "node_exporter")

    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet "$service"; then
            sudo systemctl stop "$service"
            log_info "$service stopped"
        fi
    done

    log_success "All services stopped"
}

# Start all services
start_services() {
    log_step "Starting observability services"

    sudo systemctl daemon-reload

    local services=("prometheus" "node_exporter" "loki" "promtail" "alertmanager" "grafana-server")

    for service in "${services[@]}"; do
        if sudo systemctl start "$service"; then
            log_success "$service started"
        else
            log_error "Failed to start $service"
            return 1
        fi
    done

    log_success "All services started"
}

# Wait for services to be ready
wait_for_services() {
    log_step "Waiting for services to be ready"

    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        local healthy=0

        # Check Prometheus (uses /prometheus prefix)
        if curl -sf http://localhost:9090/prometheus/-/healthy > /dev/null 2>&1; then
            ((healthy++))
        fi

        # Check Grafana
        if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
            ((healthy++))
        fi

        # Check AlertManager
        if curl -sf http://localhost:9093/-/healthy > /dev/null 2>&1; then
            ((healthy++))
        fi

        # Check Loki
        if curl -sf http://localhost:3100/ready > /dev/null 2>&1; then
            ((healthy++))
        fi

        log_info "Attempt $((attempt + 1))/$max_attempts - Healthy services: $healthy/4"

        if [[ $healthy -ge 4 ]]; then
            log_success "All services are healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 5
    done

    log_warning "Timeout waiting for services, but continuing anyway"
    return 0
}

# Check service health
check_services() {
    log_step "Checking service health"

    local failed=0

    # Check Prometheus (uses /prometheus prefix)
    log_info "Checking Prometheus..."
    if curl -sf http://localhost:9090/prometheus/-/healthy > /dev/null 2>&1; then
        log_success "Prometheus is healthy (https://mentat.arewel.com/prometheus)"
    else
        log_error "Prometheus is not healthy"
        sudo systemctl status prometheus --no-pager | tail -n 10
        failed=1
    fi

    # Check Grafana
    log_info "Checking Grafana..."
    if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
        log_success "Grafana is healthy (http://localhost:3000)"
    else
        log_error "Grafana is not healthy"
        sudo systemctl status grafana-server --no-pager | tail -n 10
        failed=1
    fi

    # Check AlertManager
    log_info "Checking AlertManager..."
    if curl -sf http://localhost:9093/-/healthy > /dev/null 2>&1; then
        log_success "AlertManager is healthy (http://localhost:9093)"
    else
        log_error "AlertManager is not healthy"
        sudo systemctl status alertmanager --no-pager | tail -n 10
        failed=1
    fi

    # Check Loki
    log_info "Checking Loki..."
    if curl -sf http://localhost:3100/ready > /dev/null 2>&1; then
        log_success "Loki is healthy (http://localhost:3100)"
    else
        log_warning "Loki is not responding (may still be starting)"
        sudo systemctl status loki --no-pager | tail -n 10
    fi

    # Check Node Exporter
    log_info "Checking Node Exporter..."
    if curl -sf http://localhost:9100/metrics > /dev/null 2>&1; then
        log_success "Node Exporter is healthy (http://localhost:9100)"
    else
        log_warning "Node Exporter is not responding"
        sudo systemctl status node_exporter --no-pager | tail -n 10
    fi

    if [[ $failed -eq 1 ]]; then
        return 1
    fi

    return 0
}

# Show service status
show_status() {
    log_step "Service status"

    local services=("prometheus" "grafana-server" "loki" "promtail" "alertmanager" "node_exporter")

    for service in "${services[@]}"; do
        echo "---"
        sudo systemctl status "$service" --no-pager | head -n 10
    done
}

# Get Grafana admin password
get_grafana_password() {
    log_step "Retrieving Grafana admin password"

    local password=$(sudo grep 'admin_password' /etc/grafana/grafana.ini | grep -v '^;' | cut -d'=' -f2 | tr -d ' ')

    if [[ -n "$password" ]]; then
        log_info "Grafana admin password: $password"
    else
        log_info "Grafana admin password: admin (default)"
    fi
}

# Main execution
main() {
    start_timer

    print_header "Observability Stack Deployment (NATIVE - No Docker)"

    deploy_systemd_services
    deploy_nginx_config
    deploy_configuration
    validate_configuration
    stop_services
    start_services

    # Wait for services (increased to avoid false-negatives)
    log_info "Waiting 10 seconds for services to initialize..."
    sleep 10
    wait_for_services

    # Check health
    log_section "Health Checks"
    check_services

    # Show status
    log_section "Service Status"
    show_status

    # Get Grafana password
    get_grafana_password

    # Deploy exporters automatically
    log_section "Exporter Deployment"
    if [[ -x "${SCRIPT_DIR}/deploy-exporters.sh" ]]; then
        log_info "Deploying exporters for detected services..."
        sudo bash "${SCRIPT_DIR}/deploy-exporters.sh" || log_warning "Exporter deployment completed with warnings"
    else
        log_warn "deploy-exporters.sh not found or not executable"
    fi

    end_timer "Observability deployment"

    print_header "Observability Stack Deployed (NATIVE)"
    log_success "Stack is running on mentat.arewel.com using systemd services"
    log_info ""
    log_info "Access points (HTTPS with path routing):"
    log_info "  Grafana:      https://mentat.arewel.com/"
    log_info "  Prometheus:   https://mentat.arewel.com/prometheus"
    log_info "  AlertManager: https://mentat.arewel.com/alertmanager"
    log_info "  Loki:         https://mentat.arewel.com/loki"
    log_info ""
    log_info "Direct ports (internal/debugging):"
    log_info "  Prometheus:    localhost:9090"
    log_info "  Grafana:       localhost:3000"
    log_info "  AlertManager:  localhost:9093"
    log_info "  Loki:          localhost:3100"
    log_info "  Node Exporter: localhost:9100"
    log_info ""
    log_info "Service management:"
    log_info "  View logs:     sudo journalctl -u <service-name> -f"
    log_info "  Restart:       sudo systemctl restart <service-name>"
    log_info "  Stop:          sudo systemctl stop <service-name>"
    log_info "  Status:        sudo systemctl status <service-name>"
    log_info ""
    log_info "Services: prometheus, grafana-server, loki, promtail, alertmanager, node_exporter"
}

main
