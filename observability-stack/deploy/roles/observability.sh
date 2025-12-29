#!/bin/bash
#===============================================================================
# Observability VPS Installation
#
# Installs: Prometheus, Loki, Tempo, Grafana, Alertmanager, Nginx
#
# Features:
#   - Centralized version management via config/versions.yaml
#   - Idempotent installation (safe to run multiple times)
#   - Pre-flight validation
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$DEPLOY_DIR")"

#===============================================================================
# IPv6 Management
#===============================================================================

disable_ipv6_if_requested() {
    if [[ "${DISABLE_IPV6:-false}" != "true" ]]; then
        log_info "IPv6 management skipped (not requested)"
        return 0
    fi

    log_step "Disabling IPv6 for observability services..."

    # Create sysctl config
    cat > /etc/sysctl.d/99-observability-disable-ipv6.conf << 'EOF'
# Disable IPv6 for observability stack
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    # Apply immediately
    sysctl -p /etc/sysctl.d/99-observability-disable-ipv6.conf >/dev/null 2>&1

    log_success "IPv6 disabled for observability services"
}

#===============================================================================
# Version Resolution
# Versions are sourced from config/versions.yaml with environment overrides
#===============================================================================

resolve_versions() {
    log_step "Resolving component versions..."

    # Use get_component_version from deploy/lib/common.sh
    # Falls back to hardcoded defaults if versions.yaml unavailable
    PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-$(get_component_version prometheus 2.48.1)}"
    LOKI_VERSION="${LOKI_VERSION:-$(get_component_version loki 3.0.0)}"
    TEMPO_VERSION="${TEMPO_VERSION:-$(get_component_version tempo 2.3.1)}"
    ALERTMANAGER_VERSION="${ALERTMANAGER_VERSION:-$(get_component_version alertmanager 0.27.0)}"
    NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-$(get_component_version node_exporter 1.7.0)}"

    log_info "  Prometheus:     ${PROMETHEUS_VERSION}"
    log_info "  Loki:           ${LOKI_VERSION}"
    log_info "  Tempo:          ${TEMPO_VERSION}"
    log_info "  Alertmanager:   ${ALERTMANAGER_VERSION}"
    log_info "  Node Exporter:  ${NODE_EXPORTER_VERSION}"
}

#===============================================================================
# Pre-deployment Service Stop
#===============================================================================

stop_existing_services() {
    log_step "Stopping existing services to prevent conflicts..."

    local services=(
        prometheus
        loki
        tempo
        alertmanager
        grafana-server
        node_exporter
        nginx
    )

    local stopped_count=0
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_info "Stopping $svc..."
            systemctl stop "$svc" 2>/dev/null || true
            stopped_count=$((stopped_count + 1))
        fi
    done

    if [[ $stopped_count -gt 0 ]]; then
        log_success "Stopped $stopped_count existing service(s)"
        sleep 2  # Give ports time to release
    else
        log_info "No existing services to stop"
    fi
}

#===============================================================================
# Main Installation Function
#===============================================================================

install_observability_stack() {
    log_step "Installing Observability Stack..."

    # Stop existing services FIRST to prevent conflicts
    stop_existing_services

    # Resolve versions from config/versions.yaml
    resolve_versions

    install_system_packages

    # Disable IPv6 if requested (before installing services)
    disable_ipv6_if_requested

    install_prometheus
    install_loki
    install_tempo
    install_alertmanager
    install_grafana
    install_node_exporter
    install_nginx
    setup_ssl
    configure_all
    start_all_services
    setup_firewall_observability
    save_installation_info
}

#===============================================================================
# System Packages
#===============================================================================

install_system_packages() {
    log_step "Installing system packages..."

    apt-get update -qq

    # Detect Debian version
    local debian_version=""
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        debian_version="${VERSION_ID:-}"
    fi

    # Build package list
    local packages=(
        nginx
        certbot
        python3-certbot-nginx
        apache2-utils
        jq
        curl
        wget
        unzip
        apt-transport-https
    )

    # Add software-properties-common only for Debian 11-12 (not needed on Debian 13+)
    if [[ "$debian_version" =~ ^(11|12)$ ]]; then
        packages+=(software-properties-common)
        log_info "Adding software-properties-common (Debian $debian_version)"
    else
        log_info "Skipping software-properties-common (Debian $debian_version - not required)"
    fi

    apt-get install -y -qq "${packages[@]}"

    log_success "System packages installed"
}

#===============================================================================
# Prometheus
#===============================================================================

install_prometheus() {
    log_step "Installing Prometheus ${PROMETHEUS_VERSION}..."

    # Idempotency check: skip if already installed with correct version
    if binary_installed /usr/local/bin/prometheus "$PROMETHEUS_VERSION"; then
        log_info "Prometheus ${PROMETHEUS_VERSION} already installed, skipping"
        return 0
    fi

    local arch
    arch=$(get_architecture)
    local tarball="prometheus-${PROMETHEUS_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${tarball}"

    # Create user (idempotent)
    ensure_system_user prometheus prometheus

    # CRITICAL: Stop service AND kill processes BEFORE copying binary
    if systemctl is-active --quiet prometheus 2>/dev/null; then
        log_info "Stopping prometheus service to update binary..."
        systemctl stop prometheus
        sleep 1
    fi

    # Force kill any lingering prometheus processes
    if pgrep -f "/usr/local/bin/prometheus" >/dev/null 2>&1; then
        log_info "Killing lingering prometheus processes..."
        pkill -9 -f "/usr/local/bin/prometheus" 2>/dev/null || true
        sleep 1
    fi

    # Download and extract
    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Install binaries
    cp "prometheus-${PROMETHEUS_VERSION}.linux-${arch}/prometheus" /usr/local/bin/
    cp "prometheus-${PROMETHEUS_VERSION}.linux-${arch}/promtool" /usr/local/bin/

    # Create directories (idempotent)
    ensure_directory /etc/prometheus root:root 755
    ensure_directory /var/lib/prometheus prometheus:prometheus 755

    # Cleanup
    rm -rf "/tmp/prometheus-${PROMETHEUS_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create systemd service (always update to ensure consistency)
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus \\
    --storage.tsdb.retention.time=${METRICS_RETENTION_DAYS:-15}d \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Prometheus installed"
}

#===============================================================================
# Loki
#===============================================================================

install_loki() {
    log_step "Installing Loki ${LOKI_VERSION}..."

    # Idempotency check: skip if already installed with correct version
    if binary_installed /usr/local/bin/loki "$LOKI_VERSION"; then
        log_info "Loki ${LOKI_VERSION} already installed, skipping"
        return 0
    fi

    local arch
    arch=$(get_architecture)
    local binary="loki-linux-${arch}"
    local url="https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/${binary}.zip"

    # Create user (idempotent)
    ensure_system_user loki loki

    # CRITICAL: Stop service AND kill processes BEFORE copying binary
    if systemctl is-active --quiet loki 2>/dev/null; then
        log_info "Stopping loki service to update binary..."
        systemctl stop loki
        sleep 1
    fi

    # Force kill any lingering loki processes
    if pgrep -f "/usr/local/bin/loki" >/dev/null 2>&1; then
        log_info "Killing lingering loki processes..."
        pkill -9 -f "/usr/local/bin/loki" 2>/dev/null || true
        sleep 1
    fi

    # Download and extract
    cd /tmp
    download_file "$url" "loki.zip"
    unzip -o loki.zip

    # Install binary
    chmod +x "${binary}"
    mv "${binary}" /usr/local/bin/loki

    # Create directories (idempotent)
    ensure_directory /etc/loki root:root 755
    ensure_directory /var/lib/loki loki:loki 755

    # Cleanup
    rm -f /tmp/loki.zip

    # Create systemd service
    cat > /etc/systemd/system/loki.service << EOF
[Unit]
Description=Loki
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Loki installed"
}

#===============================================================================
# Tempo
#===============================================================================

install_tempo() {
    log_step "Installing Tempo ${TEMPO_VERSION}..."

    # Idempotency check: skip if already installed with correct version
    if binary_installed /usr/local/bin/tempo "$TEMPO_VERSION"; then
        log_info "Tempo ${TEMPO_VERSION} already installed, skipping"
        return 0
    fi

    local arch
    arch=$(get_architecture)
    local binary="tempo_${TEMPO_VERSION}_linux_${arch}"
    local url="https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/${binary}.tar.gz"

    # Create user (idempotent)
    ensure_system_user tempo tempo

    # CRITICAL: Stop service AND kill processes BEFORE copying binary
    if systemctl is-active --quiet tempo 2>/dev/null; then
        log_info "Stopping tempo service to update binary..."
        systemctl stop tempo
        sleep 1
    fi

    # Force kill any lingering tempo processes
    if pgrep -f "/usr/local/bin/tempo" >/dev/null 2>&1; then
        log_info "Killing lingering tempo processes..."
        pkill -9 -f "/usr/local/bin/tempo" 2>/dev/null || true
        sleep 1
    fi

    # Download and extract
    cd /tmp
    download_file "$url" "tempo.tar.gz"
    tar xzf tempo.tar.gz

    # Install binary
    chmod +x tempo
    mv tempo /usr/local/bin/tempo

    # Create directories (idempotent)
    ensure_directory /etc/tempo root:root 755
    ensure_directory /var/lib/tempo tempo:tempo 755

    # Create default config
    cat > /etc/tempo/tempo.yaml << 'EOF'
server:
  http_listen_port: 3200
  grpc_listen_port: 9095

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
    jaeger:
      protocols:
        thrift_http:
          endpoint: 0.0.0.0:14268

ingester:
  trace_idle_period: 10s
  max_block_bytes: 1_000_000
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 48h

storage:
  trace:
    backend: local
    local:
      path: /var/lib/tempo/traces
    wal:
      path: /var/lib/tempo/wal
EOF

    chown tempo:tempo /etc/tempo/tempo.yaml

    # Cleanup
    rm -f /tmp/tempo.tar.gz

    # Create systemd service
    cat > /etc/systemd/system/tempo.service << EOF
[Unit]
Description=Tempo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tempo
Group=tempo
ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/tempo.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Tempo installed"
}

#===============================================================================
# Alertmanager
#===============================================================================

install_alertmanager() {
    log_step "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

    # Idempotency check: skip if already installed with correct version
    if binary_installed /usr/local/bin/alertmanager "$ALERTMANAGER_VERSION"; then
        log_info "Alertmanager ${ALERTMANAGER_VERSION} already installed, skipping"
        return 0
    fi

    local arch
    arch=$(get_architecture)
    local tarball="alertmanager-${ALERTMANAGER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/${tarball}"

    # Create user (idempotent)
    ensure_system_user alertmanager alertmanager

    # CRITICAL: Stop service AND kill processes BEFORE copying binary
    # This prevents "Text file busy" errors when overwriting running executable
    if systemctl is-active --quiet alertmanager 2>/dev/null; then
        log_info "Stopping alertmanager service to update binary..."
        systemctl stop alertmanager
        sleep 1
    fi

    # Force kill any lingering alertmanager processes
    if pgrep -f "/usr/local/bin/alertmanager" >/dev/null 2>&1; then
        log_info "Killing lingering alertmanager processes..."
        pkill -9 -f "/usr/local/bin/alertmanager" 2>/dev/null || true
        sleep 1
    fi

    # Verify no alertmanager processes are running
    local retry_count=0
    while pgrep -f "/usr/local/bin/alertmanager" >/dev/null 2>&1 && [[ $retry_count -lt 5 ]]; do
        log_warn "Alertmanager process still running, waiting... (attempt $((retry_count + 1))/5)"
        sleep 1
        retry_count=$((retry_count + 1))
    done

    if pgrep -f "/usr/local/bin/alertmanager" >/dev/null 2>&1; then
        log_error "Failed to stop alertmanager process after 5 retries"
        log_error "Active processes:"
        ps aux | grep -v grep | grep alertmanager || true
        return 1
    fi

    # Download and extract
    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Install binaries
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-${arch}/alertmanager" /usr/local/bin/
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-${arch}/amtool" /usr/local/bin/

    # Create directories (idempotent)
    ensure_directory /etc/alertmanager root:root 755
    ensure_directory /var/lib/alertmanager alertmanager:alertmanager 755

    # Cleanup
    rm -rf "/tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create systemd service
    cat > /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=alertmanager
Group=alertmanager
ExecStart=/usr/local/bin/alertmanager \\
    --config.file=/etc/alertmanager/alertmanager.yml \\
    --storage.path=/var/lib/alertmanager
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Alertmanager installed"
}

#===============================================================================
# Grafana
#===============================================================================

install_grafana() {
    log_step "Installing Grafana..."

    # Add Grafana repository
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg

    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
        tee /etc/apt/sources.list.d/grafana.list

    apt-get update -qq
    apt-get install -y -qq grafana

    # Install plugins
    grafana-cli plugins install grafana-lokiexplore-app || true
    grafana-cli plugins install grafana-piechart-panel || true

    log_success "Grafana installed"
}

#===============================================================================
# Node Exporter (for self-monitoring)
#===============================================================================

install_node_exporter() {
    log_step "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    # Idempotency check: skip if already installed with correct version
    if binary_installed /usr/local/bin/node_exporter "$NODE_EXPORTER_VERSION"; then
        log_info "Node Exporter ${NODE_EXPORTER_VERSION} already installed, skipping"
        return 0
    fi

    local arch
    arch=$(get_architecture)
    local tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${tarball}"

    # Create user (idempotent)
    ensure_system_user node_exporter node_exporter

    # Download and extract
    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter" || {
        log_error "Failed to stop node_exporter safely"
        return 1
    }

    # Install binary
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/local/bin/

    # Cleanup
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Node Exporter installed"
}

#===============================================================================
# Nginx
#===============================================================================

install_nginx() {
    log_step "Configuring Nginx..."

    # Nginx already installed via system packages
    mkdir -p /var/www/html/.well-known/acme-challenge

    log_success "Nginx configured"
}

#===============================================================================
# SSL Setup
#===============================================================================

setup_ssl() {
    if [[ "${USE_SSL:-false}" != "true" ]] || [[ -z "${GRAFANA_DOMAIN:-}" ]]; then
        log_info "Skipping SSL setup (no domain configured)"
        return 0
    fi

    log_step "Setting up SSL certificate..."

    # First, create a temporary nginx config for ACME challenge
    cat > /etc/nginx/sites-available/observability << EOF
server {
    listen 80;
    server_name ${GRAFANA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx

    # Get certificate
    if certbot certonly --webroot -w /var/www/html \
        -d "${GRAFANA_DOMAIN}" \
        --email "${LETSENCRYPT_EMAIL}" \
        --agree-tos --non-interactive; then
        log_success "SSL certificate obtained"
    else
        log_warn "SSL certificate failed - continuing without SSL"
        USE_SSL=false
    fi
}

#===============================================================================
# Configuration
#===============================================================================

configure_all() {
    generate_global_config
    generate_prometheus_config
    generate_loki_config
    generate_grafana_config
    generate_alertmanager_config
    generate_nginx_config
}

#===============================================================================
# Start Services
#===============================================================================

start_all_services() {
    log_step "Starting all services..."

    local services=(
        prometheus
        loki
        tempo
        alertmanager
        grafana-server
        node_exporter
        nginx
    )

    for svc in "${services[@]}"; do
        enable_and_start "$svc" || log_warn "Failed to start $svc"
    done

    log_success "All services started"
}

#===============================================================================
# Save Installation Info
#===============================================================================

save_installation_info() {
    log_step "Saving installation info..."

    cat > "$STACK_DIR/.installation" << EOF
# Observability Stack Installation
# Generated: $(date -Iseconds)

ROLE=observability
OBSERVABILITY_IP=${OBSERVABILITY_IP}
GRAFANA_DOMAIN=${GRAFANA_DOMAIN:-}
USE_SSL=${USE_SSL:-false}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}
METRICS_RETENTION_DAYS=${METRICS_RETENTION_DAYS:-15}
LOGS_RETENTION_DAYS=${LOGS_RETENTION_DAYS:-7}
CONFIGURE_SMTP=${CONFIGURE_SMTP:-false}
DISABLE_IPV6=${DISABLE_IPV6:-false}

# Versions
PROMETHEUS_VERSION=${PROMETHEUS_VERSION}
LOKI_VERSION=${LOKI_VERSION}
TEMPO_VERSION=${TEMPO_VERSION}
ALERTMANAGER_VERSION=${ALERTMANAGER_VERSION}
NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION}
EOF

    chmod 600 "$STACK_DIR/.installation"
    log_success "Installation info saved"
}
