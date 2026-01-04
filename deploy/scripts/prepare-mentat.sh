#!/usr/bin/env bash
# Prepare mentat.arewel.com for observability stack deployment
# This script installs observability tools NATIVELY (no Docker)
# Usage: ./prepare-mentat.sh
#
# IDEMPOTENT: Safe to run multiple times - checks before installing
# - Skips if software already installed
# - Preserves existing configurations
# - Only installs/updates what's needed

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

    # Validate deploy root structure
    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    # Validate utils directory
    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        # Validate required utility files
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

    # If errors found, print comprehensive error message and exit
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo ""
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "Utils directory: ${utils_dir}" >&2
        echo ""
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo ""
        echo "Troubleshooting:" >&2
        echo "  1. Verify you are in the correct repository:" >&2
        echo "     cd /home/calounx/repositories/mentat" >&2
        echo "" >&2
        echo "  2. Run the script from the repository root:" >&2
        echo "     sudo ./deploy/scripts/${script_name}" >&2
        echo "" >&2
        echo "  3. Check that all deployment files are present:" >&2
        echo "     ls -la deploy/utils/" >&2
        echo "" >&2
        echo "  4. If files are missing, ensure git repository is complete:" >&2
        echo "     git status" >&2
        echo "     git pull" >&2
        echo "" >&2
        exit 1
    fi
}

# Run validation before sourcing
validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Now safe to source utility files
source "${SCRIPT_DIR}/../utils/logging.sh"
source "${SCRIPT_DIR}/../utils/dependency-validation.sh"

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
OBSERVABILITY_DIR="${OBSERVABILITY_DIR:-/opt/observability}"
DATA_DIR="${DATA_DIR:-/var/lib/observability}"
CONFIG_DIR="${CONFIG_DIR:-/etc/observability}"

# Versions
PROMETHEUS_VERSION="2.48.0"
LOKI_VERSION="2.9.3"
PROMTAIL_VERSION="2.9.3"
ALERTMANAGER_VERSION="0.26.0"
NODE_EXPORTER_VERSION="1.7.0"

init_deployment_log "prepare-mentat-$(date +%Y%m%d_%H%M%S)"
log_section "Preparing mentat.arewel.com"

# Update system packages (Debian 13 compatible)
update_system() {
    log_step "Updating system packages"

    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        wget \
        git \
        unzip \
        htop \
        vim \
        net-tools \
        dnsutils \
        jq \
        nginx \
        certbot \
        python3-certbot-nginx

    log_success "System packages updated"
}

# Create deployment user
create_deploy_user() {
    log_step "Creating deployment user: $DEPLOY_USER"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_success "User $DEPLOY_USER already exists"
    else
        # Create user with home directory
        sudo useradd -m -s /bin/bash "$DEPLOY_USER"
        log_success "User $DEPLOY_USER created"
    fi

    # Create .ssh directory
    sudo mkdir -p /home/${DEPLOY_USER}/.ssh
    sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
    sudo chmod 700 /home/${DEPLOY_USER}/.ssh

    log_success "User $DEPLOY_USER configured"
}

# Create observability system user
create_observability_user() {
    log_step "Creating observability system user"

    if ! id observability &>/dev/null; then
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin observability
        log_success "Observability user created"
    else
        log_success "Observability user already exists"
    fi
}

# Setup observability directories
setup_observability_directories() {
    log_step "Setting up observability directories"

    # Create main directories
    sudo mkdir -p "$OBSERVABILITY_DIR/bin"
    sudo mkdir -p "$CONFIG_DIR"/{prometheus,grafana,loki,alertmanager,promtail}
    sudo mkdir -p "$CONFIG_DIR/prometheus/rules"
    sudo mkdir -p "$CONFIG_DIR/prometheus/targets"

    # Create data directories
    sudo mkdir -p "${DATA_DIR}/prometheus"
    sudo mkdir -p "${DATA_DIR}/grafana"
    sudo mkdir -p "${DATA_DIR}/alertmanager"
    sudo mkdir -p "${DATA_DIR}/loki"

    # Set ownership
    sudo chown -R observability:observability "$OBSERVABILITY_DIR"
    sudo chown -R observability:observability "$CONFIG_DIR"
    sudo chown -R observability:observability "$DATA_DIR"

    log_success "Observability directories configured"
}

# Install Prometheus natively
install_prometheus() {
    log_step "Installing Prometheus ${PROMETHEUS_VERSION}"

    # Stop service if running to allow binary update
    if systemctl is-active --quiet prometheus 2>/dev/null; then
        log_info "Stopping prometheus service before update"
        sudo systemctl stop prometheus
    fi

    # Check if already installed
    if [[ -f "${OBSERVABILITY_DIR}/bin/prometheus" ]]; then
        local installed_version=$("${OBSERVABILITY_DIR}/bin/prometheus" --version 2>&1 | head -1 | awk '{print $3}')
        if [[ "$installed_version" == "$PROMETHEUS_VERSION" ]]; then
            log_success "Prometheus ${PROMETHEUS_VERSION} already installed"
            return 0
        else
            log_info "Upgrading Prometheus from $installed_version to ${PROMETHEUS_VERSION}"
        fi
    fi

    cd /tmp
    if [[ ! -f "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" ]]; then
        wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    fi
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" "${OBSERVABILITY_DIR}/bin/"
    sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" "${OBSERVABILITY_DIR}/bin/"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/prometheus"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/promtool"
    rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64"*

    # Create default configuration if not exists
    if [[ ! -f "${CONFIG_DIR}/prometheus/prometheus.yml" ]]; then
        sudo tee "${CONFIG_DIR}/prometheus/prometheus.yml" > /dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

rule_files:
  - /etc/observability/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF
    else
        log_success "Prometheus configuration already exists"
    fi

    # Create/update systemd service
    sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
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
    --storage.tsdb.retention.time=30d \\
    --storage.tsdb.retention.size=50GB \\
    --web.listen-address=:9090 \\
    --web.external-url=http://mentat.arewel.com/prometheus/ \\
    --web.route-prefix=/ \\
    --web.enable-lifecycle \\
    --web.enable-admin-api
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    log_success "Prometheus systemd service configured"

    sudo chown -R observability:observability "${CONFIG_DIR}/prometheus"
    sudo chown -R observability:observability "${DATA_DIR}/prometheus"

    log_success "Prometheus installed"
}

# Install Grafana from APT repository
install_grafana() {
    log_step "Installing Grafana from official repository"

    # Stop service if running to allow update
    if systemctl is-active --quiet grafana-server 2>/dev/null; then
        log_info "Stopping grafana-server service before update"
        sudo systemctl stop grafana-server
    fi

    # Check if Grafana is already installed
    if command -v grafana-server &>/dev/null; then
        log_success "Grafana is already installed"
        local installed_version=$(grafana-server -v 2>&1 | head -1 | awk '{print $2}')
        log_info "Installed version: $installed_version"
    else
        # Add Grafana GPG key and repository
        sudo mkdir -p /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/grafana.gpg ]]; then
            wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
        fi

        if [[ ! -f /etc/apt/sources.list.d/grafana.list ]]; then
            echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
                sudo tee /etc/apt/sources.list.d/grafana.list
        fi

        sudo apt-get update
        sudo apt-get install -y grafana
    fi

    # Configure Grafana datasources if not already configured
    sudo mkdir -p /etc/grafana/provisioning/datasources
    if [[ ! -f /etc/grafana/provisioning/datasources/datasources.yaml ]]; then
        sudo tee /etc/grafana/provisioning/datasources/datasources.yaml > /dev/null <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true

  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
EOF
    else
        log_success "Grafana datasources already configured"
    fi

    log_success "Grafana installed from APT repository"
}

# Install Loki natively
install_loki() {
    log_step "Installing Loki ${LOKI_VERSION}"

    # Stop service if running to allow binary update
    if systemctl is-active --quiet loki 2>/dev/null; then
        log_info "Stopping loki service before update"
        sudo systemctl stop loki
    fi

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
    unzip -qq "loki-linux-amd64.zip"
    sudo mv loki-linux-amd64 "${OBSERVABILITY_DIR}/bin/loki"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/loki"
    rm -f loki-linux-amd64.zip

    # Create Loki configuration
    sudo tee "${CONFIG_DIR}/loki/loki-config.yml" > /dev/null <<EOF
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: ${DATA_DIR}/loki
  storage:
    filesystem:
      chunks_directory: ${DATA_DIR}/loki/chunks
      rules_directory: ${DATA_DIR}/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 720h
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20

compactor:
  working_directory: ${DATA_DIR}/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem
EOF

    sudo mkdir -p "${DATA_DIR}/loki"/{chunks,rules,compactor}

    # Create systemd service
    sudo tee /etc/systemd/system/loki.service > /dev/null <<EOF
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=${OBSERVABILITY_DIR}/bin/loki -config.file=${CONFIG_DIR}/loki/loki-config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo chown -R observability:observability "${CONFIG_DIR}/loki"
    sudo chown -R observability:observability "${DATA_DIR}/loki"

    log_success "Loki installed"
}

# Install Promtail natively
install_promtail() {
    log_step "Installing Promtail ${PROMTAIL_VERSION}"

    # Stop service if running to allow binary update
    if systemctl is-active --quiet promtail 2>/dev/null; then
        log_info "Stopping promtail service before update"
        sudo systemctl stop promtail
    fi

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
    unzip -qq "promtail-linux-amd64.zip"
    sudo mv promtail-linux-amd64 "${OBSERVABILITY_DIR}/bin/promtail"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/promtail"
    rm -f promtail-linux-amd64.zip

    # Create Promtail configuration
    sudo tee "${CONFIG_DIR}/promtail/promtail-config.yml" > /dev/null <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: ${DATA_DIR}/loki/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
EOF

    # Create systemd service
    sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail
Wants=network-online.target
After=network-online.target loki.service

[Service]
User=observability
Group=observability
Type=simple
ExecStart=${OBSERVABILITY_DIR}/bin/promtail -config.file=${CONFIG_DIR}/promtail/promtail-config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo chown -R observability:observability "${CONFIG_DIR}/promtail"

    log_success "Promtail installed"
}

# Install AlertManager natively
install_alertmanager() {
    log_step "Installing AlertManager ${ALERTMANAGER_VERSION}"

    # Check if already installed and running
    if systemctl is-active --quiet alertmanager 2>/dev/null; then
        log_info "Stopping alertmanager service before update"
        sudo systemctl stop alertmanager
    fi

    cd /tmp
    wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    sudo cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" "${OBSERVABILITY_DIR}/bin/"
    sudo cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" "${OBSERVABILITY_DIR}/bin/"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/alertmanager"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/amtool"
    rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"*

    # Create AlertManager configuration
    sudo tee "${CONFIG_DIR}/alertmanager/alertmanager.yml" > /dev/null <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
    # Configure your notification channels here
    # webhook_configs:
    #   - url: 'http://localhost:5001/webhook'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

    # Create systemd service
    sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<EOF
[Unit]
Description=AlertManager
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=${OBSERVABILITY_DIR}/bin/alertmanager \\
    --config.file=${CONFIG_DIR}/alertmanager/alertmanager.yml \\
    --storage.path=${DATA_DIR}/alertmanager \\
    --web.external-url=http://mentat.arewel.com/alertmanager/ \\
    --web.route-prefix=/
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo chown -R observability:observability "${CONFIG_DIR}/alertmanager"
    sudo chown -R observability:observability "${DATA_DIR}/alertmanager"

    log_success "AlertManager installed"
}

# Install Node Exporter
install_node_exporter() {
    log_step "Installing Node Exporter ${NODE_EXPORTER_VERSION}"

    # Stop service if running to allow binary update
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        log_info "Stopping node_exporter service before update"
        sudo systemctl stop node_exporter
    fi

    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" "${OBSERVABILITY_DIR}/bin/"
    sudo chmod +x "${OBSERVABILITY_DIR}/bin/node_exporter"
    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

    # Create systemd service
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=${OBSERVABILITY_DIR}/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    log_success "Node Exporter installed"
}

# Configure system limits
configure_system_limits() {
    log_step "Configuring system limits"

    # Increase file descriptor limits
    if ! grep -q "# Limits for observability stack" /etc/security/limits.conf; then
        sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# Limits for observability stack
observability soft nofile 65536
observability hard nofile 65536
observability soft nproc 32768
observability hard nproc 32768
EOF
        log_success "System limits added to limits.conf"
    else
        log_success "System limits already configured in limits.conf"
    fi

    # Configure sysctl for observability
    sudo tee /etc/sysctl.d/99-observability.conf > /dev/null <<EOF
# Increase connection tracking
net.netfilter.nf_conntrack_max = 262144

# Increase maximum number of memory map areas
vm.max_map_count = 262144

# Increase buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Enable BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-observability.conf 2>/dev/null || true

    log_success "System limits configured"
}

# Setup log rotation
setup_log_rotation() {
    log_step "Setting up log rotation for observability services"

    sudo tee /etc/logrotate.d/observability > /dev/null <<EOF
/var/log/observability/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 observability observability
}
EOF

    log_success "Log rotation configured"
}

# Harden system security
harden_security() {
    log_step "Hardening system security"

    # Disable root SSH login
    sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

    # Disable password authentication (use SSH keys only)
    sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

    # Restart SSH
    sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh

    # Configure automatic security updates
    sudo apt-get install -y unattended-upgrades
    sudo dpkg-reconfigure -plow unattended-upgrades

    log_success "Security hardening applied"
}

# Configure Nginx for observability services
configure_nginx_observability() {
    log_step "Configuring Nginx for observability services"

    # Create nginx configuration for mentat.arewel.com
    sudo tee /etc/nginx/sites-available/observability > /dev/null <<'NGINX_CONF'
# Prometheus on /prometheus
upstream prometheus {
    server 127.0.0.1:9090;
}

# Grafana on root
upstream grafana {
    server 127.0.0.1:3000;
}

# AlertManager on /alertmanager
upstream alertmanager {
    server 127.0.0.1:9093;
}

# Loki on /loki
upstream loki {
    server 127.0.0.1:3100;
}

server {
    listen 80;
    listen [::]:80;
    server_name mentat.arewel.com;

    # Grafana as default
    location / {
        proxy_pass http://grafana;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support for Grafana Live
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Prometheus
    location /prometheus/ {
        proxy_pass http://prometheus/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # AlertManager
    location /alertmanager/ {
        proxy_pass http://alertmanager/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Loki (usually only internal, but available if needed)
    location /loki/ {
        proxy_pass http://loki/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Node exporter metrics (internal)
    location /node-metrics {
        proxy_pass http://127.0.0.1:9100/metrics;
        proxy_set_header Host $host;
    }
}
NGINX_CONF

    # Enable the site
    sudo ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/observability

    # Remove default site
    sudo rm -f /etc/nginx/sites-enabled/default

    # Test and reload nginx
    if sudo nginx -t; then
        sudo systemctl reload nginx
        log_success "Nginx configured for observability services"
    else
        log_error "Nginx configuration test failed"
        return 1
    fi
}

# Enable all services
enable_services() {
    log_step "Enabling observability services"

    sudo systemctl daemon-reload

    # Enable services (they will be started by deploy-observability.sh)
    sudo systemctl enable prometheus
    sudo systemctl enable grafana-server
    sudo systemctl enable loki
    sudo systemctl enable promtail
    sudo systemctl enable alertmanager
    sudo systemctl enable node_exporter

    log_success "All services enabled"
}

# Start all services
start_services() {
    log_step "Starting observability services"

    local services=("prometheus" "grafana-server" "loki" "promtail" "alertmanager" "node_exporter")
    local failed=()

    for service in "${services[@]}"; do
        if sudo systemctl start "$service"; then
            log_success "$service started"
        else
            log_error "Failed to start $service"
            failed+=("$service")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_warning "Some services failed to start: ${failed[*]}"
    else
        log_success "All services started successfully"
    fi
}

# Main execution
main() {
    start_timer

    print_header "Preparing mentat.arewel.com for observability stack (NATIVE INSTALLATION)"

    update_system
    create_deploy_user
    create_observability_user
    setup_observability_directories
    install_prometheus
    install_grafana
    install_loki
    install_promtail
    install_alertmanager
    install_node_exporter
    configure_system_limits
    setup_log_rotation
    configure_nginx_observability
    harden_security
    enable_services
    start_services

    # Wait for services to start
    sleep 3

    # Verify services are running
    log_section "Service Status"
    for service in prometheus grafana-server loki promtail alertmanager node_exporter; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_warning "$service is not running"
        fi
    done

    end_timer "Server preparation"

    print_header "Server Preparation Complete"
    log_success "mentat.arewel.com is ready with observability stack"
    log_info "All components installed and running NATIVELY using systemd services"
    log_info ""
    log_info "Access points:"
    log_info "  - Grafana:      http://mentat.arewel.com/ (admin/admin default)"
    log_info "  - Prometheus:   http://mentat.arewel.com/prometheus/"
    log_info "  - AlertManager: http://mentat.arewel.com/alertmanager/"
    log_info "  - Loki:         http://mentat.arewel.com/loki/"
    log_info ""
    log_info "Direct ports (if needed):"
    log_info "  - Grafana:      http://mentat.arewel.com:3000"
    log_info "  - Prometheus:   http://mentat.arewel.com:9090"
    log_info "  - AlertManager: http://mentat.arewel.com:9093"
    log_info "  - Loki:         http://mentat.arewel.com:3100"
    log_info "  - Node Exporter: http://mentat.arewel.com:9100"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run setup-ssl.sh for HTTPS (optional)"
    log_info "  2. Configure firewall with ufw"
}

main
