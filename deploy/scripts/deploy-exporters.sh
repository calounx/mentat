#!/usr/bin/env bash
# Universal exporter deployment script
# Auto-detects running services and installs appropriate exporters
# Works on any host (mentat, landsraad, etc.)
# Usage: sudo ./deploy-exporters.sh [--loki-url URL]

set -euo pipefail

# Exporter versions
NODE_EXPORTER_VERSION="1.8.2"
NGINX_EXPORTER_VERSION="1.3.0"
POSTGRES_EXPORTER_VERSION="0.15.0"
REDIS_EXPORTER_VERSION="1.62.0"
PHPFPM_EXPORTER_VERSION="2.2.0"
BLACKBOX_EXPORTER_VERSION="0.25.0"
PROMTAIL_VERSION="3.2.1"

# Configuration
LOKI_URL="${LOKI_URL:-http://mentat.arewel.com:3100}"
PROMETHEUS_HOST="${PROMETHEUS_HOST:-mentat.arewel.com}"
PROMETHEUS_USER="${PROMETHEUS_USER:-stilgar}"
PROMETHEUS_TARGETS_DIR="/etc/observability/prometheus/targets"
INSTALL_DIR="/opt/exporters"
CONFIG_DIR="/etc/exporters"
HOSTNAME=$(hostname -f)
SHORT_HOSTNAME=$(hostname -s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --loki-url)
            LOKI_URL="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# =============================================================================
# SERVICE DETECTION
# =============================================================================

declare -A DETECTED_SERVICES

detect_services() {
    log_info "Detecting running services on ${HOSTNAME}..."

    # Detect by checking if service is running or port is listening

    # Nginx
    if systemctl is-active --quiet nginx 2>/dev/null || pgrep -x nginx >/dev/null 2>&1; then
        DETECTED_SERVICES[nginx]=1
        log_success "Detected: nginx"
    fi

    # PostgreSQL
    if systemctl is-active --quiet postgresql 2>/dev/null || pgrep -x postgres >/dev/null 2>&1; then
        DETECTED_SERVICES[postgresql]=1
        log_success "Detected: postgresql"
    fi

    # Redis
    if systemctl is-active --quiet redis-server 2>/dev/null || systemctl is-active --quiet redis 2>/dev/null || pgrep -x redis-server >/dev/null 2>&1; then
        DETECTED_SERVICES[redis]=1
        log_success "Detected: redis"
    fi

    # PHP-FPM (various versions)
    if systemctl is-active --quiet "php*-fpm" 2>/dev/null || pgrep -f "php-fpm" >/dev/null 2>&1; then
        DETECTED_SERVICES[phpfpm]=1
        log_success "Detected: php-fpm"
    fi

    # Prometheus (only install blackbox if prometheus is running - this is the observability server)
    if systemctl is-active --quiet prometheus 2>/dev/null || pgrep -x prometheus >/dev/null 2>&1; then
        DETECTED_SERVICES[prometheus]=1
        log_success "Detected: prometheus (observability server)"
    fi

    # Loki
    if systemctl is-active --quiet loki 2>/dev/null || pgrep -x loki >/dev/null 2>&1; then
        DETECTED_SERVICES[loki]=1
        log_success "Detected: loki"
    fi

    echo ""
}

# =============================================================================
# SETUP
# =============================================================================

setup_directories() {
    log_info "Setting up directories..."

    mkdir -p "${INSTALL_DIR}/bin"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p /var/lib/promtail

    # Create exporter user if not exists
    if ! id -u exporters &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin exporters
        log_success "Created exporters user"
    fi

    # Also check for observability user (used on mentat)
    if id -u observability &>/dev/null; then
        EXPORTER_USER="observability"
        EXPORTER_GROUP="observability"
    else
        EXPORTER_USER="exporters"
        EXPORTER_GROUP="exporters"
    fi
}

# =============================================================================
# NODE EXPORTER (always install)
# =============================================================================

install_node_exporter() {
    log_info "Checking node_exporter..."

    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        log_success "node_exporter already running"
        return 0
    fi

    if [[ -f "${INSTALL_DIR}/bin/node_exporter" ]] || [[ -f "/opt/observability/bin/node_exporter" ]] || [[ -f "/usr/local/bin/node_exporter" ]]; then
        log_success "node_exporter binary exists"
        return 0
    fi

    log_info "Installing node_exporter ${NODE_EXPORTER_VERSION}..."

    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" "${INSTALL_DIR}/bin/"
    chmod +x "${INSTALL_DIR}/bin/node_exporter"
    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
ExecStart=${INSTALL_DIR}/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    log_success "node_exporter installed on port 9100"
}

# =============================================================================
# NGINX EXPORTER
# =============================================================================

install_nginx_exporter() {
    [[ -z "${DETECTED_SERVICES[nginx]:-}" ]] && return 0

    log_info "Installing nginx_exporter..."

    # Configure nginx stub_status first
    configure_nginx_status

    local bin_path="${INSTALL_DIR}/bin/nginx-prometheus-exporter"
    [[ -f "/opt/observability/bin/nginx-prometheus-exporter" ]] && bin_path="/opt/observability/bin/nginx-prometheus-exporter"

    if [[ ! -f "$bin_path" ]]; then
        cd /tmp
        wget -q "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
        tar xzf "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
        cp nginx-prometheus-exporter "${INSTALL_DIR}/bin/"
        chmod +x "${INSTALL_DIR}/bin/nginx-prometheus-exporter"
        rm -f nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz nginx-prometheus-exporter LICENSE
        bin_path="${INSTALL_DIR}/bin/nginx-prometheus-exporter"
    fi

    cat > /etc/systemd/system/nginx_exporter.service << EOF
[Unit]
Description=Prometheus Nginx Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
ExecStart=${bin_path} --web.listen-address=:9113 --nginx.scrape-uri=http://127.0.0.1:8080/nginx_status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx_exporter
    systemctl restart nginx_exporter
    log_success "nginx_exporter installed on port 9113"
}

configure_nginx_status() {
    if [[ -f /etc/nginx/conf.d/status.conf ]]; then
        return 0
    fi

    cat > /etc/nginx/conf.d/status.conf << 'EOF'
server {
    listen 8080;
    listen [::]:8080;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        allow ::1;
        deny all;
        access_log off;
    }
}
EOF

    if nginx -t 2>&1; then
        systemctl reload nginx
        log_success "nginx stub_status configured on port 8080"
    else
        log_error "nginx configuration test failed"
    fi
}

# =============================================================================
# POSTGRES EXPORTER
# =============================================================================

install_postgres_exporter() {
    [[ -z "${DETECTED_SERVICES[postgresql]:-}" ]] && return 0

    log_info "Installing postgres_exporter..."

    if [[ ! -f "${INSTALL_DIR}/bin/postgres_exporter" ]]; then
        cd /tmp
        wget -q "https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"
        tar xzf "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"
        cp "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64/postgres_exporter" "${INSTALL_DIR}/bin/"
        chmod +x "${INSTALL_DIR}/bin/postgres_exporter"
        rm -rf "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64"*
    fi

    # Setup PostgreSQL monitoring user
    setup_postgres_monitoring_user

    cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=Prometheus PostgreSQL Exporter
Wants=network-online.target
After=network-online.target postgresql.service

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
EnvironmentFile=${CONFIG_DIR}/postgres_exporter.env
ExecStart=${INSTALL_DIR}/bin/postgres_exporter --web.listen-address=:9187
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable postgres_exporter
    systemctl restart postgres_exporter
    log_success "postgres_exporter installed on port 9187"
}

setup_postgres_monitoring_user() {
    local pg_user="postgres_exporter"
    local pg_pass=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

    # Create user if not exists
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pg_user}'" 2>/dev/null | grep -q 1 || \
        sudo -u postgres psql -c "CREATE USER ${pg_user} WITH PASSWORD '${pg_pass}';" 2>/dev/null || true

    # Grant permissions
    sudo -u postgres psql -c "GRANT pg_monitor TO ${pg_user};" 2>/dev/null || true

    # Save connection string
    cat > "${CONFIG_DIR}/postgres_exporter.env" << EOF
DATA_SOURCE_NAME=postgresql://${pg_user}:${pg_pass}@localhost:5432/postgres?sslmode=disable
EOF
    chmod 600 "${CONFIG_DIR}/postgres_exporter.env"
    chown ${EXPORTER_USER}:${EXPORTER_GROUP} "${CONFIG_DIR}/postgres_exporter.env"
    log_success "PostgreSQL monitoring user configured"
}

# =============================================================================
# REDIS EXPORTER
# =============================================================================

install_redis_exporter() {
    [[ -z "${DETECTED_SERVICES[redis]:-}" ]] && return 0

    log_info "Installing redis_exporter..."

    if [[ ! -f "${INSTALL_DIR}/bin/redis_exporter" ]]; then
        cd /tmp
        wget -q "https://github.com/oliver006/redis_exporter/releases/download/v${REDIS_EXPORTER_VERSION}/redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64.tar.gz"
        tar xzf "redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64.tar.gz"
        cp "redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64/redis_exporter" "${INSTALL_DIR}/bin/"
        chmod +x "${INSTALL_DIR}/bin/redis_exporter"
        rm -rf "redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64"*
    fi

    # Get Redis password if set
    local redis_pass=""
    if [[ -f /var/www/chom/.env ]]; then
        redis_pass=$(grep -E "^REDIS_PASSWORD=" /var/www/chom/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
    elif [[ -f /var/www/chom/current/.env ]]; then
        redis_pass=$(grep -E "^REDIS_PASSWORD=" /var/www/chom/current/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
    fi

    cat > "${CONFIG_DIR}/redis_exporter.env" << EOF
REDIS_ADDR=redis://localhost:6379
REDIS_PASSWORD=${redis_pass}
EOF
    chmod 600 "${CONFIG_DIR}/redis_exporter.env"
    chown ${EXPORTER_USER}:${EXPORTER_GROUP} "${CONFIG_DIR}/redis_exporter.env"

    cat > /etc/systemd/system/redis_exporter.service << EOF
[Unit]
Description=Prometheus Redis Exporter
Wants=network-online.target
After=network-online.target redis-server.service redis.service

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
EnvironmentFile=${CONFIG_DIR}/redis_exporter.env
ExecStart=${INSTALL_DIR}/bin/redis_exporter --web.listen-address=:9121
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redis_exporter
    systemctl restart redis_exporter
    log_success "redis_exporter installed on port 9121"
}

# =============================================================================
# PHP-FPM EXPORTER
# =============================================================================

install_phpfpm_exporter() {
    [[ -z "${DETECTED_SERVICES[phpfpm]:-}" ]] && return 0

    log_info "Installing php-fpm_exporter..."

    # Configure PHP-FPM status first
    configure_phpfpm_status

    if [[ ! -f "${INSTALL_DIR}/bin/php-fpm_exporter" ]]; then
        cd /tmp
        wget -q "https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64.tar.gz"
        tar xzf "php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64.tar.gz"
        cp php-fpm_exporter "${INSTALL_DIR}/bin/"
        chmod +x "${INSTALL_DIR}/bin/php-fpm_exporter"
        rm -f php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64.tar.gz php-fpm_exporter LICENSE
    fi

    cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=Prometheus PHP-FPM Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
ExecStart=${INSTALL_DIR}/bin/php-fpm_exporter server --web.listen-address=:9253 --phpfpm.scrape-uri=tcp://127.0.0.1:9000/status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable phpfpm_exporter
    systemctl restart phpfpm_exporter
    log_success "php-fpm_exporter installed on port 9253"
}

configure_phpfpm_status() {
    # Create a minimal PHP-FPM pool for status
    local php_version=""
    for v in 8.3 8.2 8.1 8.0 7.4; do
        if [[ -d "/etc/php/${v}/fpm/pool.d" ]]; then
            php_version="$v"
            break
        fi
    done

    if [[ -z "$php_version" ]]; then
        log_warn "PHP-FPM config directory not found"
        return 0
    fi

    local status_pool="/etc/php/${php_version}/fpm/pool.d/status.conf"
    if [[ ! -f "$status_pool" ]]; then
        cat > "$status_pool" << 'EOF'
[status]
user = www-data
group = www-data
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1
pm = static
pm.max_children = 1
pm.status_path = /status
ping.path = /ping
EOF
        systemctl restart "php${php_version}-fpm" 2>/dev/null || true
        log_success "PHP-FPM status pool configured"
    fi
}

# =============================================================================
# BLACKBOX EXPORTER (only on observability server)
# =============================================================================

install_blackbox_exporter() {
    [[ -z "${DETECTED_SERVICES[prometheus]:-}" ]] && return 0

    log_info "Installing blackbox_exporter..."

    local bin_path="${INSTALL_DIR}/bin/blackbox_exporter"
    [[ -f "/opt/observability/bin/blackbox_exporter" ]] && bin_path="/opt/observability/bin/blackbox_exporter"

    if [[ ! -f "$bin_path" ]]; then
        cd /tmp
        wget -q "https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_EXPORTER_VERSION}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz"
        tar xzf "blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz"
        cp "blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64/blackbox_exporter" "${INSTALL_DIR}/bin/"
        chmod +x "${INSTALL_DIR}/bin/blackbox_exporter"
        rm -rf "blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64"*
        bin_path="${INSTALL_DIR}/bin/blackbox_exporter"
    fi

    mkdir -p "${CONFIG_DIR}/blackbox"
    cat > "${CONFIG_DIR}/blackbox/blackbox.yml" << 'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      valid_status_codes: [200, 201, 202, 204, 301, 302, 303, 307, 308]
      method: GET
      follow_redirects: true
      preferred_ip_protocol: ip4
  tcp_connect:
    prober: tcp
    timeout: 10s
  icmp:
    prober: icmp
    timeout: 5s
EOF
    chown -R ${EXPORTER_USER}:${EXPORTER_GROUP} "${CONFIG_DIR}/blackbox"

    cat > /etc/systemd/system/blackbox_exporter.service << EOF
[Unit]
Description=Prometheus Blackbox Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
ExecStart=${bin_path} --config.file=${CONFIG_DIR}/blackbox/blackbox.yml --web.listen-address=:9115
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable blackbox_exporter
    systemctl restart blackbox_exporter
    log_success "blackbox_exporter installed on port 9115"
}

# =============================================================================
# PROMTAIL (log shipping)
# =============================================================================

install_promtail() {
    # Skip if this IS the Loki server
    if [[ -n "${DETECTED_SERVICES[loki]:-}" ]]; then
        log_info "This is the Loki server, using local promtail config"
        return 0
    fi

    log_info "Installing promtail for log shipping to ${LOKI_URL}..."

    if [[ ! -f "${INSTALL_DIR}/bin/promtail" ]]; then
        cd /tmp
        wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
        unzip -qq "promtail-linux-amd64.zip"
        mv promtail-linux-amd64 "${INSTALL_DIR}/bin/promtail"
        chmod +x "${INSTALL_DIR}/bin/promtail"
        rm -f promtail-linux-amd64.zip
    fi

    # Generate promtail config based on detected services
    generate_promtail_config

    cat > /etc/systemd/system/promtail.service << EOF
[Unit]
Description=Promtail Log Agent
Wants=network-online.target
After=network-online.target

[Service]
User=root
Group=root
Type=simple
ExecStart=${INSTALL_DIR}/bin/promtail -config.file=${CONFIG_DIR}/promtail.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable promtail
    systemctl restart promtail
    log_success "promtail installed, shipping logs to ${LOKI_URL}"
}

generate_promtail_config() {
    cat > "${CONFIG_DIR}/promtail.yml" << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets: [localhost]
        labels:
          job: system
          host: ${HOSTNAME}
          __path__: /var/log/syslog
      - targets: [localhost]
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/auth.log
EOF

    # Add nginx logs if detected
    if [[ -n "${DETECTED_SERVICES[nginx]:-}" ]]; then
        cat >> "${CONFIG_DIR}/promtail.yml" << EOF

  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: ${HOSTNAME}
          __path__: /var/log/nginx/*.log
EOF
    fi

    # Add PostgreSQL logs if detected
    if [[ -n "${DETECTED_SERVICES[postgresql]:-}" ]]; then
        cat >> "${CONFIG_DIR}/promtail.yml" << EOF

  - job_name: postgresql
    static_configs:
      - targets: [localhost]
        labels:
          job: postgresql
          host: ${HOSTNAME}
          __path__: /var/log/postgresql/*.log
EOF
    fi

    # Add PHP-FPM logs if detected
    if [[ -n "${DETECTED_SERVICES[phpfpm]:-}" ]]; then
        cat >> "${CONFIG_DIR}/promtail.yml" << EOF

  - job_name: php-fpm
    static_configs:
      - targets: [localhost]
        labels:
          job: php-fpm
          host: ${HOSTNAME}
          __path__: /var/log/php*-fpm*.log
EOF
    fi

    # Add Laravel logs if app directory exists
    if [[ -d /var/www/chom/current/storage/logs ]] || [[ -d /var/www/chom/storage/logs ]]; then
        local log_path="/var/www/chom/current/storage/logs/*.log"
        [[ -d /var/www/chom/storage/logs ]] && log_path="/var/www/chom/storage/logs/*.log"
        cat >> "${CONFIG_DIR}/promtail.yml" << EOF

  - job_name: laravel
    static_configs:
      - targets: [localhost]
        labels:
          job: laravel
          host: ${HOSTNAME}
          app: chom
          __path__: ${log_path}
    pipeline_stages:
      - multiline:
          firstline: '^\\[\\d{4}-\\d{2}-\\d{2}'
          max_wait_time: 3s
EOF
    fi
}

# =============================================================================
# VERIFY
# =============================================================================

verify_installation() {
    echo ""
    log_info "Verifying installed exporters on ${HOSTNAME}..."
    echo ""

    declare -A ports=(
        [node_exporter]=9100
        [nginx_exporter]=9113
        [postgres_exporter]=9187
        [redis_exporter]=9121
        [phpfpm_exporter]=9253
        [blackbox_exporter]=9115
        [promtail]=9080
    )

    for service in "${!ports[@]}"; do
        local port="${ports[$service]}"
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            if curl -sf "http://localhost:${port}/metrics" >/dev/null 2>&1; then
                log_success "${service} running on port ${port}"
            else
                log_warn "${service} running but not responding on port ${port}"
            fi
        fi
    done
}

# =============================================================================
# CONFIGURE FIREWALL
# =============================================================================

configure_firewall() {
    if ! command -v ufw &>/dev/null; then
        return 0
    fi

    log_info "Configuring firewall for Prometheus scraping..."

    # Allow from mentat IP (observability server)
    local mentat_ip="51.254.139.78"

    declare -A ports=(
        [9100]="node_exporter"
        [9113]="nginx_exporter"
        [9187]="postgres_exporter"
        [9121]="redis_exporter"
        [9253]="phpfpm_exporter"
    )

    for port in "${!ports[@]}"; do
        ufw allow from ${mentat_ip} to any port ${port} proto tcp comment "${ports[$port]} from mentat" 2>/dev/null || true
    done

    log_success "Firewall configured"
}

# =============================================================================
# REGISTER WITH PROMETHEUS (on observability server)
# =============================================================================

register_with_prometheus() {
    log_info "Registering targets with Prometheus on ${PROMETHEUS_HOST}..."

    # Determine if this is the local machine (mentat) or remote
    local is_local=false
    if [[ "$HOSTNAME" == *"mentat"* ]] || [[ -f /opt/observability/bin/prometheus ]]; then
        is_local=true
    fi

    # Create target files
    local targets_dir="/tmp/prometheus_targets"
    mkdir -p "$targets_dir"

    # Get host IP for remote scraping
    local host_ip
    if [[ "$is_local" == "true" ]]; then
        host_ip="localhost"
    else
        host_ip=$(hostname -I | awk '{print $1}')
        # Or use hostname if resolvable
        host_ip="${HOSTNAME}"
    fi

    # Node exporter (always)
    cat > "${targets_dir}/node_${SHORT_HOSTNAME}.yml" << EOF
- targets:
    - '${host_ip}:9100'
  labels:
    host: '${SHORT_HOSTNAME}'
    instance: '${HOSTNAME}'
EOF

    # Nginx exporter
    if [[ -n "${DETECTED_SERVICES[nginx]:-}" ]]; then
        cat > "${targets_dir}/nginx_${SHORT_HOSTNAME}.yml" << EOF
- targets:
    - '${host_ip}:9113'
  labels:
    host: '${SHORT_HOSTNAME}'
    instance: '${HOSTNAME}'
EOF
    fi

    # PostgreSQL exporter
    if [[ -n "${DETECTED_SERVICES[postgresql]:-}" ]]; then
        cat > "${targets_dir}/postgresql_${SHORT_HOSTNAME}.yml" << EOF
- targets:
    - '${host_ip}:9187'
  labels:
    host: '${SHORT_HOSTNAME}'
    instance: '${HOSTNAME}'
EOF
    fi

    # Redis exporter
    if [[ -n "${DETECTED_SERVICES[redis]:-}" ]]; then
        cat > "${targets_dir}/redis_${SHORT_HOSTNAME}.yml" << EOF
- targets:
    - '${host_ip}:9121'
  labels:
    host: '${SHORT_HOSTNAME}'
    instance: '${HOSTNAME}'
EOF
    fi

    # PHP-FPM exporter
    if [[ -n "${DETECTED_SERVICES[phpfpm]:-}" ]]; then
        cat > "${targets_dir}/phpfpm_${SHORT_HOSTNAME}.yml" << EOF
- targets:
    - '${host_ip}:9253'
  labels:
    host: '${SHORT_HOSTNAME}'
    instance: '${HOSTNAME}'
EOF
    fi

    # Deploy target files
    if [[ "$is_local" == "true" ]]; then
        # Local deployment (on mentat)
        sudo mkdir -p "${PROMETHEUS_TARGETS_DIR}"
        sudo cp "${targets_dir}"/*.yml "${PROMETHEUS_TARGETS_DIR}/"
        sudo chown -R observability:observability "${PROMETHEUS_TARGETS_DIR}"
        log_success "Targets registered locally"
    else
        # Remote deployment via SSH - run as stilgar user (has SSH keys)
        log_info "Deploying targets to ${PROMETHEUS_HOST} via SSH..."

        # Change ownership of target files to stilgar so they can be copied
        chown -R stilgar:stilgar "${targets_dir}"

        # SSH as stilgar user (even when script runs as root)
        if sudo -u stilgar ssh -o BatchMode=yes -o ConnectTimeout=5 "${PROMETHEUS_USER}@${PROMETHEUS_HOST}" "sudo mkdir -p ${PROMETHEUS_TARGETS_DIR}" 2>/dev/null; then
            sudo -u stilgar scp -q "${targets_dir}"/*.yml "${PROMETHEUS_USER}@${PROMETHEUS_HOST}:/tmp/"
            sudo -u stilgar ssh "${PROMETHEUS_USER}@${PROMETHEUS_HOST}" "sudo mv /tmp/node_*.yml /tmp/nginx_*.yml /tmp/postgresql_*.yml /tmp/redis_*.yml /tmp/phpfpm_*.yml ${PROMETHEUS_TARGETS_DIR}/ 2>/dev/null; sudo chown -R observability:observability ${PROMETHEUS_TARGETS_DIR}"
            log_success "Targets registered on ${PROMETHEUS_HOST}"
        else
            log_warn "Cannot SSH to ${PROMETHEUS_HOST}. Manual target registration required."
            log_info "Target files created in ${targets_dir}/"
            log_info "Copy manually: scp ${targets_dir}/*.yml ${PROMETHEUS_USER}@${PROMETHEUS_HOST}:/tmp/"
        fi
    fi

    rm -rf "$targets_dir"
}

# =============================================================================
# CREATE BLACKBOX TARGETS (endpoints to monitor)
# =============================================================================

register_blackbox_targets() {
    [[ -z "${DETECTED_SERVICES[prometheus]:-}" ]] && return 0

    log_info "Registering blackbox monitoring targets..."

    mkdir -p "${PROMETHEUS_TARGETS_DIR}"

    cat > "${PROMETHEUS_TARGETS_DIR}/blackbox_endpoints.yml" << 'EOF'
- targets:
    - 'https://chom.arewel.com'
    - 'https://chom.arewel.com/health'
  labels:
    module: 'http_2xx'
EOF

    chown observability:observability "${PROMETHEUS_TARGETS_DIR}/blackbox_endpoints.yml"
    log_success "Blackbox targets registered"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo "==========================================="
    echo "  Universal Exporter Deployment"
    echo "  Host: ${HOSTNAME}"
    echo "==========================================="
    echo ""

    detect_services
    setup_directories

    # Always install node_exporter
    install_node_exporter

    # Install service-specific exporters
    install_nginx_exporter
    install_postgres_exporter
    install_redis_exporter
    install_phpfpm_exporter
    install_blackbox_exporter
    install_promtail

    # Configure firewall (for non-mentat hosts)
    configure_firewall

    # Register targets with Prometheus
    register_with_prometheus
    register_blackbox_targets

    # Verify
    verify_installation

    echo ""
    echo "==========================================="
    echo "  Deployment Complete on ${HOSTNAME}"
    echo "==========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run this script on all monitored hosts"
    echo "  2. On mentat, reload Prometheus: sudo systemctl reload prometheus"
    echo ""
}

main "$@"
