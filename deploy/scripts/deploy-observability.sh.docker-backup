#!/usr/bin/env bash
# Deploy observability stack to mentat.arewel.com
# Usage: ./deploy-observability.sh [--config-dir /path/to/config]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
OBSERVABILITY_DIR="${OBSERVABILITY_DIR:-/opt/observability}"
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/../config/mentat}"
DATA_DIR="${DATA_DIR:-/var/lib/observability}"
DEPLOY_USER="${DEPLOY_USER:-stilgar}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

init_deployment_log "deploy-observability-$(date +%Y%m%d_%H%M%S)"
log_section "Observability Stack Deployment"

# Copy configuration files
deploy_configuration() {
    log_step "Deploying configuration files"

    # Create config directory
    sudo mkdir -p "${OBSERVABILITY_DIR}/config"

    # Copy Prometheus configuration
    if [[ -f "${CONFIG_DIR}/prometheus.yml" ]]; then
        sudo cp "${CONFIG_DIR}/prometheus.yml" "${OBSERVABILITY_DIR}/config/"
        log_success "Prometheus configuration deployed"
    else
        log_warning "Prometheus configuration not found: ${CONFIG_DIR}/prometheus.yml"
    fi

    # Copy AlertManager configuration
    if [[ -f "${CONFIG_DIR}/alertmanager.yml" ]]; then
        sudo cp "${CONFIG_DIR}/alertmanager.yml" "${OBSERVABILITY_DIR}/config/"
        log_success "AlertManager configuration deployed"
    else
        log_warning "AlertManager configuration not found: ${CONFIG_DIR}/alertmanager.yml"
    fi

    # Copy Grafana datasources
    if [[ -f "${CONFIG_DIR}/grafana-datasources.yml" ]]; then
        sudo mkdir -p "${OBSERVABILITY_DIR}/config/grafana/provisioning/datasources"
        sudo cp "${CONFIG_DIR}/grafana-datasources.yml" "${OBSERVABILITY_DIR}/config/grafana/provisioning/datasources/"
        log_success "Grafana datasources deployed"
    else
        log_warning "Grafana datasources not found: ${CONFIG_DIR}/grafana-datasources.yml"
    fi

    # Copy Loki configuration
    if [[ -f "${CONFIG_DIR}/loki-config.yml" ]]; then
        sudo cp "${CONFIG_DIR}/loki-config.yml" "${OBSERVABILITY_DIR}/config/"
        log_success "Loki configuration deployed"
    else
        log_warning "Loki configuration not found: ${CONFIG_DIR}/loki-config.yml"
    fi

    # Copy Docker Compose file
    if [[ -f "${CONFIG_DIR}/docker-compose.prod.yml" ]]; then
        sudo cp "${CONFIG_DIR}/docker-compose.prod.yml" "${OBSERVABILITY_DIR}/docker-compose.yml"
        log_success "Docker Compose configuration deployed"
    else
        log_error "Docker Compose configuration not found: ${CONFIG_DIR}/docker-compose.prod.yml"
        return 1
    fi

    # Set ownership
    sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} "${OBSERVABILITY_DIR}/config"

    log_success "Configuration files deployed"
}

# Create necessary directories
create_directories() {
    log_step "Creating data directories"

    sudo mkdir -p "${DATA_DIR}/prometheus"
    sudo mkdir -p "${DATA_DIR}/grafana"
    sudo mkdir -p "${DATA_DIR}/alertmanager"
    sudo mkdir -p "${DATA_DIR}/loki"

    # Set permissions
    sudo chown -R 65534:65534 "${DATA_DIR}/prometheus"
    sudo chown -R 472:472 "${DATA_DIR}/grafana"
    sudo chown -R 65534:65534 "${DATA_DIR}/alertmanager"
    sudo chown -R 10001:10001 "${DATA_DIR}/loki"

    log_success "Data directories created"
}

# Pull Docker images
pull_images() {
    log_step "Pulling Docker images"

    cd "$OBSERVABILITY_DIR"

    if sudo -u ${DEPLOY_USER} docker compose pull 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Docker images pulled"
        return 0
    else
        log_error "Failed to pull Docker images"
        return 1
    fi
}

# Stop existing stack
stop_stack() {
    log_step "Stopping existing observability stack"

    cd "$OBSERVABILITY_DIR"

    if sudo -u ${DEPLOY_USER} docker compose down 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Existing stack stopped"
    else
        log_info "No existing stack to stop"
    fi
}

# Start observability stack
start_stack() {
    log_step "Starting observability stack"

    cd "$OBSERVABILITY_DIR"

    if sudo -u ${DEPLOY_USER} docker compose up -d 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Observability stack started"
        return 0
    else
        log_error "Failed to start observability stack"
        return 1
    fi
}

# Wait for services to be healthy
wait_for_services() {
    log_step "Waiting for services to be healthy"

    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        local healthy_count=$(docker compose ps --format json 2>/dev/null | jq -r '.Health' | grep -c "healthy" || echo "0")

        log_info "Attempt $((attempt + 1))/$max_attempts - Healthy services: $healthy_count"

        if [[ $healthy_count -ge 3 ]]; then
            log_success "Services are healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 5
    done

    log_warning "Timeout waiting for services to be healthy"
    return 0  # Don't fail deployment
}

# Check service health
check_services() {
    log_step "Checking service health"

    local failed=0

    # Check Prometheus
    log_info "Checking Prometheus..."
    if curl -sf http://localhost:9090/-/healthy > /dev/null; then
        log_success "Prometheus is healthy"
    else
        log_error "Prometheus is not healthy"
        failed=1
    fi

    # Check Grafana
    log_info "Checking Grafana..."
    if curl -sf http://localhost:3000/api/health > /dev/null; then
        log_success "Grafana is healthy"
    else
        log_error "Grafana is not healthy"
        failed=1
    fi

    # Check AlertManager
    log_info "Checking AlertManager..."
    if curl -sf http://localhost:9093/-/healthy > /dev/null; then
        log_success "AlertManager is healthy"
    else
        log_error "AlertManager is not healthy"
        failed=1
    fi

    # Check Loki
    log_info "Checking Loki..."
    if curl -sf http://localhost:3100/ready > /dev/null; then
        log_success "Loki is healthy"
    else
        log_warning "Loki is not responding (may still be starting)"
    fi

    if [[ $failed -eq 1 ]]; then
        return 1
    fi

    return 0
}

# Show service status
show_status() {
    log_step "Service status"

    cd "$OBSERVABILITY_DIR"

    sudo -u ${DEPLOY_USER} docker compose ps
}

# Enable systemd service
enable_systemd_service() {
    log_step "Enabling systemd service"

    if [[ -f /etc/systemd/system/observability-stack.service ]]; then
        sudo systemctl enable observability-stack.service
        log_success "Systemd service enabled"
    else
        log_warning "Systemd service file not found, skipping"
    fi
}

# Main execution
main() {
    start_timer

    print_header "Observability Stack Deployment"

    create_directories
    deploy_configuration
    pull_images
    stop_stack
    start_stack

    # Wait for services
    sleep 5
    wait_for_services

    # Check health
    log_section "Health Checks"
    check_services

    # Show status
    log_section "Service Status"
    show_status

    # Enable systemd service
    enable_systemd_service

    end_timer "Observability deployment"

    print_header "Observability Stack Deployed"
    log_success "Stack is running on mentat.arewel.com"
    log_info "Access points:"
    log_info "  Prometheus: http://mentat.arewel.com:9090"
    log_info "  Grafana: http://mentat.arewel.com:3000 (admin/admin)"
    log_info "  AlertManager: http://mentat.arewel.com:9093"
    log_info ""
    log_info "To view logs: docker compose -f ${OBSERVABILITY_DIR}/docker-compose.yml logs -f"
    log_info "To stop stack: docker compose -f ${OBSERVABILITY_DIR}/docker-compose.yml down"
}

main
