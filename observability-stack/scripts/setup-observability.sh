#!/bin/bash
#===============================================================================
# Observability Stack Setup Script for Debian 13
# Installs: Prometheus, Loki, Grafana, Alertmanager, Nginx (reverse proxy)
# All configuration is read from global.yaml
#===============================================================================

set -euo pipefail

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
    apt-get update

    # Install required packages
    apt-get install -y \
        apt-transport-https \
        software-properties-common \
        wget \
        curl \
        gnupg \
        lsb-release \
        ufw \
        apache2-utils \
        nginx \
        certbot \
        python3-certbot-nginx \
        jq \
        unzip

    log_success "System packages installed"
}

#===============================================================================
# FIREWALL CONFIGURATION
#===============================================================================

configure_firewall() {
    log_info "Configuring firewall..."

    # Reset UFW
    ufw --force reset

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
    log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

    # Create user
    useradd --no-create-home --shell /bin/false prometheus || true

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
    systemctl start prometheus

    log_success "Prometheus configured and started"
}

#===============================================================================
# NODE EXPORTER (for self-monitoring)
#===============================================================================

install_node_exporter() {
    log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    useradd --no-create-home --shell /bin/false node_exporter || true

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
    systemctl start node_exporter

    log_success "Node Exporter installed and started"
}

#===============================================================================
# ALERTMANAGER INSTALLATION
#===============================================================================

install_alertmanager() {
    log_info "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

    useradd --no-create-home --shell /bin/false alertmanager || true

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
    systemctl start alertmanager

    log_success "Alertmanager configured and started"
}

#===============================================================================
# LOKI INSTALLATION
#===============================================================================

install_loki() {
    log_info "Installing Loki ${LOKI_VERSION}..."

    useradd --no-create-home --shell /bin/false loki || true

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
    systemctl start loki

    log_success "Loki configured and started"
}

#===============================================================================
# GRAFANA INSTALLATION
#===============================================================================

install_grafana() {
    log_info "Installing Grafana..."

    # Add Grafana repository
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

    apt-get update
    apt-get install -y grafana

    log_success "Grafana installed"
}

configure_grafana() {
    log_info "Configuring Grafana..."

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
secret_key = $(openssl rand -hex 32)
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
    systemctl start grafana-server

    log_success "Grafana configured and started"
}

#===============================================================================
# NGINX CONFIGURATION
#===============================================================================

configure_nginx() {
    log_info "Configuring Nginx..."

    # Create htpasswd files
    htpasswd -cb /etc/nginx/.htpasswd_prometheus "$PROMETHEUS_USER" "$PROMETHEUS_PASS"
    htpasswd -cb /etc/nginx/.htpasswd_loki "$LOKI_USER" "$LOKI_PASS"

    # Create certbot webroot
    mkdir -p /var/www/certbot

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

    ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx

    log_success "Nginx initial configuration complete"
}

setup_ssl() {
    log_info "Setting up SSL certificate..."

    # Check if certificate already exists
    if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]]; then
        log_info "SSL certificate already exists"
    else
        # Get certificate
        certbot certonly --webroot \
            -w /var/www/certbot \
            -d "${GRAFANA_DOMAIN}" \
            --email "${LETSENCRYPT_EMAIL}" \
            --agree-tos \
            --non-interactive \
            --expand

        if [[ $? -ne 0 ]]; then
            log_warn "Failed to obtain SSL certificate. Continuing without HTTPS..."
            return
        fi
    fi

    # Now install full nginx config with SSL
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
