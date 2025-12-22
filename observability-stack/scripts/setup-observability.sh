#!/bin/bash
#===============================================================================
# Observability Stack Setup Script for Debian 13
# Installs: Prometheus, Loki, Grafana, Alertmanager, Nginx (reverse proxy)
# All configuration is read from global.yaml
#
# This script is IDEMPOTENT - safe to run multiple times:
#   - Skips installation of already installed components (at correct version)
#   - Skips firewall configuration if already configured
#   - Renews SSL certificates only if expired or expiring within 7 days
#   - Always updates configuration files to reflect latest settings
#
# Usage:
#   ./setup-observability.sh           # Normal run (idempotent)
#   ./setup-observability.sh --force   # Force reinstall everything from scratch
#===============================================================================

set -euo pipefail

# Force mode flag
FORCE_MODE=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force, -f    Force reinstall everything from scratch"
                echo "  --help, -h     Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Parse arguments before anything else
parse_args "$@"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BASE_DIR}/config/global.yaml"

# Versions (update as needed)
PROMETHEUS_VERSION="2.48.1"
ALERTMANAGER_VERSION="0.26.0"
LOKI_VERSION="2.9.3"
NODE_EXPORTER_VERSION="1.7.0"

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_skip() {
    echo -e "${GREEN}[SKIP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Parse YAML value (basic parser - handles simple key: value)
yaml_get() {
    local file="$1"
    local key="$2"
    grep -E "^\s*${key}:" "$file" | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'"
}

# Parse nested YAML value
yaml_get_nested() {
    local file="$1"
    local parent="$2"
    local key="$3"
    awk -v parent="$parent" -v key="$key" '
        $0 ~ "^"parent":" { in_section=1; next }
        in_section && /^[a-z]/ { in_section=0 }
        in_section && $0 ~ "^  "key":" { gsub(/.*: */, ""); gsub(/["'\'']/, ""); print; exit }
    ' "$file"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
}

#===============================================================================
# VERSION CHECK FUNCTIONS
#===============================================================================

# Check if a binary exists and matches expected version
check_binary_version() {
    local binary="$1"
    local expected_version="$2"
    local version_flag="${3:---version}"

    # Force mode bypasses all checks
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi

    if [[ ! -x "$binary" ]]; then
        return 1
    fi

    local current_version
    current_version=$("$binary" "$version_flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$current_version" == "$expected_version" ]]; then
        return 0
    fi
    return 1
}

# Check if Prometheus is installed at correct version
is_prometheus_installed() {
    check_binary_version "/usr/local/bin/prometheus" "$PROMETHEUS_VERSION"
}

# Check if Node Exporter is installed at correct version
is_node_exporter_installed() {
    check_binary_version "/usr/local/bin/node_exporter" "$NODE_EXPORTER_VERSION"
}

# Check if Alertmanager is installed at correct version
is_alertmanager_installed() {
    check_binary_version "/usr/local/bin/alertmanager" "$ALERTMANAGER_VERSION"
}

# Check if Loki is installed at correct version
is_loki_installed() {
    check_binary_version "/usr/local/bin/loki" "$LOKI_VERSION" "-version"
}

# Check if Grafana is installed
is_grafana_installed() {
    # Force mode bypasses all checks
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi
    dpkg -l grafana &>/dev/null
}

# Check if SSL certificate exists and is valid (not expired within 7 days)
is_ssl_valid() {
    local domain="$1"
    local cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"

    # Force mode bypasses all checks
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi

    if [[ ! -f "$cert_file" ]]; then
        return 1
    fi

    # Check if certificate expires within 7 days
    if openssl x509 -checkend 604800 -noout -in "$cert_file" &>/dev/null; then
        return 0
    fi
    return 1
}

check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
    fi
    log_info "Using configuration from: $CONFIG_FILE"
}

#===============================================================================
# CONFIGURATION PARSING
#===============================================================================

parse_config() {
    log_info "Parsing configuration..."

    # Network settings
    GRAFANA_DOMAIN=$(yaml_get_nested "$CONFIG_FILE" "network" "grafana_domain")
    LETSENCRYPT_EMAIL=$(yaml_get_nested "$CONFIG_FILE" "network" "letsencrypt_email")

    # SMTP settings
    SMTP_HOST=$(yaml_get_nested "$CONFIG_FILE" "smtp" "host")
    SMTP_PORT=$(yaml_get_nested "$CONFIG_FILE" "smtp" "port")
    SMTP_USERNAME=$(yaml_get_nested "$CONFIG_FILE" "smtp" "username")
    SMTP_PASSWORD=$(yaml_get_nested "$CONFIG_FILE" "smtp" "password")
    SMTP_FROM=$(yaml_get_nested "$CONFIG_FILE" "smtp" "from_address")
    SMTP_STARTTLS=$(yaml_get_nested "$CONFIG_FILE" "smtp" "starttls")

    # Get first email from to_addresses
    SMTP_TO=$(grep -A1 "to_addresses:" "$CONFIG_FILE" | tail -1 | sed 's/.*- *//' | tr -d '"')

    # Slack settings
    SLACK_WEBHOOK=$(yaml_get_nested "$CONFIG_FILE" "slack" "webhook_url")
    SLACK_CHANNEL=$(yaml_get_nested "$CONFIG_FILE" "slack" "channel")
    SLACK_USERNAME=$(yaml_get_nested "$CONFIG_FILE" "slack" "username")

    # Retention
    RETENTION_DAYS=$(yaml_get_nested "$CONFIG_FILE" "retention" "metrics_days")

    # Grafana
    GRAFANA_ADMIN_PASS=$(yaml_get_nested "$CONFIG_FILE" "grafana" "admin_password")

    # Security
    PROMETHEUS_USER=$(yaml_get_nested "$CONFIG_FILE" "security" "prometheus_basic_auth_user")
    PROMETHEUS_PASS=$(yaml_get_nested "$CONFIG_FILE" "security" "prometheus_basic_auth_password")
    LOKI_USER=$(yaml_get_nested "$CONFIG_FILE" "security" "loki_basic_auth_user")
    LOKI_PASS=$(yaml_get_nested "$CONFIG_FILE" "security" "loki_basic_auth_password")

    log_success "Configuration parsed successfully"
    log_info "  Domain: $GRAFANA_DOMAIN"
    log_info "  SMTP: $SMTP_HOST:$SMTP_PORT"
    log_info "  Retention: ${RETENTION_DAYS} days"
}

#===============================================================================
# SYSTEM PREPARATION
#===============================================================================

prepare_system() {
    log_info "Preparing system..."

    # Update package lists
    apt-get update -qq

    # Install required packages (apt-get install is idempotent)
    # Note: apt-transport-https and software-properties-common not needed on Debian 13+
    apt-get install -y -qq \
        wget \
        curl \
        gnupg \
        ufw \
        apache2-utils \
        nginx \
        certbot \
        python3-certbot-nginx \
        jq \
        unzip

    log_success "System packages verified/installed"
}

#===============================================================================
# FIREWALL CONFIGURATION
#===============================================================================

configure_firewall() {
    log_info "Configuring firewall..."

    # Check if firewall is already configured with required rules
    local needs_config=false

    # Force mode always reconfigures
    if [[ "$FORCE_MODE" == "true" ]]; then
        needs_config=true
        log_info "Force mode: resetting firewall..."
        ufw --force reset
    elif ! ufw status | grep -q "Status: active"; then
        needs_config=true
    elif ! ufw status | grep -qE "22/tcp.*ALLOW"; then
        needs_config=true
    elif ! ufw status | grep -qE "80/tcp.*ALLOW"; then
        needs_config=true
    elif ! ufw status | grep -qE "443/tcp.*ALLOW"; then
        needs_config=true
    fi

    if [[ "$needs_config" == "false" ]]; then
        log_skip "Firewall already configured"
        return
    fi

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp

    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Enable firewall
    ufw --force enable

    log_success "Firewall configured"
}

#===============================================================================
# PROMETHEUS INSTALLATION
#===============================================================================

install_prometheus() {
    if is_prometheus_installed; then
        log_skip "Prometheus ${PROMETHEUS_VERSION} already installed"
        # Ensure directories and user exist
        useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
        mkdir -p /etc/prometheus/rules /var/lib/prometheus
        return
    fi

    log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop prometheus 2>/dev/null || true

    # Create user
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true

    # Create directories
    mkdir -p /etc/prometheus/rules
    mkdir -p /var/lib/prometheus

    # Download and extract
    cd /tmp
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    # Install binaries
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/

    # Copy console files
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" /etc/prometheus/
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" /etc/prometheus/

    # Cleanup
    rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64" "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    # Set ownership
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

    log_success "Prometheus installed"
}

configure_prometheus() {
    log_info "Configuring Prometheus..."

    # Generate targets from global.yaml
    NODE_TARGETS=""
    NGINX_TARGETS=""
    MYSQL_TARGETS=""
    PHPFPM_TARGETS=""

    # Parse monitored hosts from config
    while IFS= read -r line; do
        if [[ "$line" =~ ip:\ *\"?([0-9.]+)\"? ]]; then
            IP="${BASH_REMATCH[1]}"
            if [[ -n "$IP" && "$IP" != "MONITORED_HOST"* ]]; then
                # Get the name from previous lines
                NAME=$(grep -B5 "ip: .*$IP" "$CONFIG_FILE" | grep "name:" | head -1 | sed 's/.*name: *//' | tr -d '"')
                if [[ -n "$NAME" ]]; then
                    NODE_TARGETS="${NODE_TARGETS}      - targets: ['${IP}:9100']\n        labels:\n          instance: '${NAME}'\n"
                    NGINX_TARGETS="${NGINX_TARGETS}      - targets: ['${IP}:9113']\n        labels:\n          instance: '${NAME}'\n"
                    MYSQL_TARGETS="${MYSQL_TARGETS}      - targets: ['${IP}:9104']\n        labels:\n          instance: '${NAME}'\n"
                    PHPFPM_TARGETS="${PHPFPM_TARGETS}      - targets: ['${IP}:9253']\n        labels:\n          instance: '${NAME}'\n"
                fi
            fi
        fi
    done < "$CONFIG_FILE"

    # Create prometheus.yml from template
    sed -e "s|{{NODE_EXPORTER_TARGETS}}|${NODE_TARGETS}|g" \
        -e "s|{{NGINX_EXPORTER_TARGETS}}|${NGINX_TARGETS}|g" \
        -e "s|{{MYSQL_EXPORTER_TARGETS}}|${MYSQL_TARGETS}|g" \
        -e "s|{{PHPFPM_EXPORTER_TARGETS}}|${PHPFPM_TARGETS}|g" \
        "${BASE_DIR}/prometheus/prometheus.yml.template" > /etc/prometheus/prometheus.yml

    # Copy alert rules
    cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/

    # Set ownership
    chown -R prometheus:prometheus /etc/prometheus

    # Create systemd service
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus/ \\
    --storage.tsdb.retention.time=${RETENTION_DAYS}d \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.enable-lifecycle \\
    --web.enable-admin-api

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable prometheus
    systemctl restart prometheus

    log_success "Prometheus configured and started"
}

#===============================================================================
# NODE EXPORTER (for self-monitoring)
#===============================================================================

install_node_exporter() {
    if is_node_exporter_installed; then
        log_skip "Node Exporter ${NODE_EXPORTER_VERSION} already installed"
        # Ensure service is running
        systemctl is-active --quiet node_exporter || systemctl start node_exporter
        return
    fi

    log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop node_exporter 2>/dev/null || true

    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl restart node_exporter

    log_success "Node Exporter installed and started"
}

#===============================================================================
# ALERTMANAGER INSTALLATION
#===============================================================================

install_alertmanager() {
    if is_alertmanager_installed; then
        log_skip "Alertmanager ${ALERTMANAGER_VERSION} already installed"
        # Ensure directories and user exist
        useradd --no-create-home --shell /bin/false alertmanager 2>/dev/null || true
        mkdir -p /etc/alertmanager/templates /var/lib/alertmanager
        return
    fi

    log_info "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop alertmanager 2>/dev/null || true

    useradd --no-create-home --shell /bin/false alertmanager 2>/dev/null || true

    mkdir -p /etc/alertmanager/templates
    mkdir -p /var/lib/alertmanager

    cd /tmp
    wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" /usr/local/bin/

    chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool

    rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64" "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

    log_success "Alertmanager installed"
}

configure_alertmanager() {
    log_info "Configuring Alertmanager..."

    # Convert starttls to boolean
    if [[ "$SMTP_STARTTLS" == "true" ]]; then
        SMTP_TLS="true"
    else
        SMTP_TLS="false"
    fi

    # Process template
    sed -e "s|{{SMTP_HOST}}|${SMTP_HOST}|g" \
        -e "s|{{SMTP_PORT}}|${SMTP_PORT}|g" \
        -e "s|{{SMTP_FROM}}|${SMTP_FROM}|g" \
        -e "s|{{SMTP_USERNAME}}|${SMTP_USERNAME}|g" \
        -e "s|{{SMTP_PASSWORD}}|${SMTP_PASSWORD}|g" \
        -e "s|{{SMTP_STARTTLS}}|${SMTP_TLS}|g" \
        -e "s|{{SMTP_TO}}|${SMTP_TO}|g" \
        -e "s|{{SLACK_WEBHOOK_URL}}|${SLACK_WEBHOOK}|g" \
        -e "s|{{SLACK_CHANNEL}}|${SLACK_CHANNEL}|g" \
        -e "s|{{SLACK_USERNAME}}|${SLACK_USERNAME}|g" \
        "${BASE_DIR}/alertmanager/alertmanager.yml.template" > /etc/alertmanager/alertmanager.yml

    # Copy email template
    sed "s|{{GRAFANA_DOMAIN}}|${GRAFANA_DOMAIN}|g" \
        "${BASE_DIR}/alertmanager/templates/email.tmpl" > /etc/alertmanager/templates/email.tmpl

    chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

    cat > /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \\
    --config.file=/etc/alertmanager/alertmanager.yml \\
    --storage.path=/var/lib/alertmanager/ \\
    --web.external-url=https://${GRAFANA_DOMAIN}/alertmanager/

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable alertmanager
    systemctl restart alertmanager

    log_success "Alertmanager configured and started"
}

#===============================================================================
# LOKI INSTALLATION
#===============================================================================

install_loki() {
    if is_loki_installed; then
        log_skip "Loki ${LOKI_VERSION} already installed"
        # Ensure directories and user exist
        useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
        mkdir -p /etc/loki /var/lib/loki/{chunks,rules,wal,tsdb-index,tsdb-cache,compactor}
        return
    fi

    log_info "Installing Loki ${LOKI_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop loki 2>/dev/null || true

    useradd --no-create-home --shell /bin/false loki 2>/dev/null || true

    mkdir -p /etc/loki
    mkdir -p /var/lib/loki/{chunks,rules,wal,tsdb-index,tsdb-cache,compactor}

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
    unzip -o loki-linux-amd64.zip
    chmod +x loki-linux-amd64
    mv loki-linux-amd64 /usr/local/bin/loki

    rm -f loki-linux-amd64.zip

    log_success "Loki installed"
}

configure_loki() {
    log_info "Configuring Loki..."

    # Update retention in config
    RETENTION_HOURS=$((RETENTION_DAYS * 24))
    sed "s/retention_period: 360h/retention_period: ${RETENTION_HOURS}h/g" \
        "${BASE_DIR}/loki/loki-config.yaml" > /etc/loki/loki-config.yaml

    chown -R loki:loki /etc/loki /var/lib/loki

    cat > /etc/systemd/system/loki.service << 'EOF'
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml

Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable loki
    systemctl restart loki

    log_success "Loki configured and started"
}

#===============================================================================
# GRAFANA INSTALLATION
#===============================================================================

install_grafana() {
    if is_grafana_installed; then
        log_skip "Grafana already installed"
        return
    fi

    log_info "Installing Grafana..."

    # Add Grafana repository
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

    apt-get update -qq

    # In force mode, reinstall even if already present
    if [[ "$FORCE_MODE" == "true" ]]; then
        apt-get install -y -qq --reinstall grafana
    else
        apt-get install -y -qq grafana
    fi

    log_success "Grafana installed"
}

configure_grafana() {
    log_info "Configuring Grafana..."

    # Generate secret key only once (preserve across reruns to keep sessions valid)
    local secret_key_file="/etc/grafana/.secret_key"
    if [[ ! -f "$secret_key_file" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        openssl rand -hex 32 > "$secret_key_file"
        chmod 600 "$secret_key_file"
    fi
    local GRAFANA_SECRET_KEY
    GRAFANA_SECRET_KEY=$(cat "$secret_key_file")

    # Update grafana.ini
    cat > /etc/grafana/grafana.ini << EOF
[server]
protocol = http
http_addr = 127.0.0.1
http_port = 3000
domain = ${GRAFANA_DOMAIN}
root_url = https://${GRAFANA_DOMAIN}/
serve_from_sub_path = false

[database]
type = sqlite3

[session]
provider = file

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASS}
secret_key = ${GRAFANA_SECRET_KEY}
disable_gravatar = true

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[alerting]
enabled = true

[unified_alerting]
enabled = true

[smtp]
enabled = true
host = ${SMTP_HOST}:${SMTP_PORT}
user = ${SMTP_USERNAME}
password = ${SMTP_PASSWORD}
from_address = ${SMTP_FROM}
from_name = Grafana Alerts
startTLS_policy = MandatoryStartTLS

[log]
mode = console file
level = info

[log.file]
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7
EOF

    # Copy provisioning files
    mkdir -p /etc/grafana/provisioning/datasources
    mkdir -p /etc/grafana/provisioning/dashboards
    mkdir -p /var/lib/grafana/dashboards

    cp "${BASE_DIR}/grafana/provisioning/datasources/datasources.yaml" /etc/grafana/provisioning/datasources/
    cp "${BASE_DIR}/grafana/provisioning/dashboards/dashboards.yaml" /etc/grafana/provisioning/dashboards/
    cp "${BASE_DIR}/grafana/dashboards/"*.json /var/lib/grafana/dashboards/

    chown -R grafana:grafana /etc/grafana /var/lib/grafana

    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl restart grafana-server

    log_success "Grafana configured and started"
}

#===============================================================================
# NGINX CONFIGURATION
#===============================================================================

configure_nginx() {
    log_info "Configuring Nginx..."

    # Create/update htpasswd files (always update to reflect config changes)
    htpasswd -cb /etc/nginx/.htpasswd_prometheus "$PROMETHEUS_USER" "$PROMETHEUS_PASS" 2>/dev/null
    htpasswd -cb /etc/nginx/.htpasswd_loki "$LOKI_USER" "$LOKI_PASS" 2>/dev/null

    # Create certbot webroot
    mkdir -p /var/www/certbot

    # Only create initial HTTP config if SSL config doesn't exist yet or force mode
    # (setup_ssl will handle the full SSL config)
    if [[ "$FORCE_MODE" == "true" ]] || [[ ! -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]]; then
        # Create initial nginx config (HTTP only for certbot)
        cat > /etc/nginx/sites-available/observability << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${GRAFANA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'Waiting for SSL certificate...';
        add_header Content-Type text/plain;
    }
}
EOF
    fi

    ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx

    log_success "Nginx initial configuration complete"
}

setup_ssl() {
    log_info "Setting up SSL certificate..."

    local need_cert=false
    local cert_file="/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem"

    # Check if certificate exists and is valid
    if [[ ! -f "$cert_file" ]]; then
        log_info "SSL certificate not found, obtaining new certificate..."
        need_cert=true
    elif ! is_ssl_valid "$GRAFANA_DOMAIN"; then
        log_info "SSL certificate expired or expiring soon, renewing..."
        need_cert=true
    else
        log_skip "SSL certificate is valid"
    fi

    if [[ "$need_cert" == "true" ]]; then
        # Ensure nginx is serving HTTP for certbot challenge
        if ! grep -q "acme-challenge" /etc/nginx/sites-available/observability 2>/dev/null; then
            # Create temporary HTTP-only config for certbot
            cat > /etc/nginx/sites-available/observability << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${GRAFANA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'Waiting for SSL certificate...';
        add_header Content-Type text/plain;
    }
}
EOF
            nginx -t && systemctl reload nginx
        fi

        # Get/renew certificate
        # Only use --force-renewal in force mode to avoid Let's Encrypt rate limits
        local certbot_args="--webroot -w /var/www/certbot -d ${GRAFANA_DOMAIN} --email ${LETSENCRYPT_EMAIL} --agree-tos --non-interactive --expand"
        if [[ "$FORCE_MODE" == "true" ]]; then
            certbot_args="$certbot_args --force-renewal"
        fi

        if ! certbot certonly $certbot_args; then
            log_warn "Failed to obtain SSL certificate. Continuing without HTTPS..."
            return
        fi
        log_success "SSL certificate obtained/renewed"
    fi

    # Install full nginx config with SSL (always update in case config changed)
    sed -e "s|{{GRAFANA_DOMAIN}}|${GRAFANA_DOMAIN}|g" \
        "${BASE_DIR}/nginx/observability.conf.template" > /etc/nginx/sites-available/observability

    nginx -t && systemctl reload nginx

    # Setup auto-renewal
    systemctl enable certbot.timer
    systemctl start certbot.timer

    log_success "SSL certificate configured"
}

#===============================================================================
# FINAL CONFIGURATION
#===============================================================================

final_setup() {
    log_info "Final setup..."

    # Wait for services to be ready
    sleep 5

    # Verify all services are running
    for service in prometheus node_exporter alertmanager loki grafana-server nginx; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_warn "$service is not running"
        fi
    done

    # Print summary
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Observability Stack Setup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Access Grafana at: https://${GRAFANA_DOMAIN}"
    echo ""
    echo "Default Grafana login:"
    echo "  Username: admin"
    echo "  Password: ${GRAFANA_ADMIN_PASS}"
    echo ""
    echo "Protected endpoints (use configured basic auth):"
    echo "  Prometheus: https://${GRAFANA_DOMAIN}/prometheus/"
    echo "  Loki: https://${GRAFANA_DOMAIN}/loki/"
    echo "  Alertmanager: https://${GRAFANA_DOMAIN}/alertmanager/"
    echo ""
    echo "Important next steps:"
    echo "1. Change the Grafana admin password after first login"
    echo "2. Run the agent setup script on each monitored host"
    echo "3. Verify alerts are working by checking test notifications"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "Observability Stack Setup for Debian 13"
    echo "=========================================="
    if [[ "$FORCE_MODE" == "true" ]]; then
        echo -e "${YELLOW}>>> FORCE MODE: Reinstalling everything from scratch <<<${NC}"
    fi
    echo ""

    check_root
    check_config
    parse_config

    prepare_system
    configure_firewall

    install_prometheus
    install_node_exporter
    install_alertmanager
    install_loki
    install_grafana

    configure_prometheus
    configure_alertmanager
    configure_loki
    configure_grafana
    configure_nginx
    setup_ssl

    final_setup
}

# Run main
main "$@"
