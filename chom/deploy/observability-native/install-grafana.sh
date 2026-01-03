#!/bin/bash

###############################################################################
# Native Grafana Installation for Debian 13
# NO DOCKER - Systemd service only
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
GRAFANA_PORT=3000
GRAFANA_CONFIG_DIR="/etc/grafana"
GRAFANA_DATA_DIR="/var/lib/grafana"
GRAFANA_LOG_DIR="/var/log/grafana"
GRAFANA_PROVISIONING_DIR="/etc/grafana/provisioning"

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

install_dependencies() {
    log_info "Installing dependencies..."

    apt-get update -qq
    apt-get install -y -qq \
        apt-transport-https \
        software-properties-common \
        wget \
        gnupg2 \
        curl

    log_success "Dependencies installed"
}

add_grafana_repo() {
    log_info "Adding Grafana official APT repository..."

    # Add GPG key
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key

    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | \
        tee /etc/apt/sources.list.d/grafana.list

    apt-get update -qq

    log_success "Grafana repository added"
}

install_grafana() {
    log_info "Installing Grafana from official repository..."

    apt-get install -y -qq grafana

    log_success "Grafana installed"
}

create_directories() {
    log_info "Creating additional directories..."

    mkdir -p "$GRAFANA_PROVISIONING_DIR/datasources"
    mkdir -p "$GRAFANA_PROVISIONING_DIR/dashboards"
    mkdir -p "$GRAFANA_PROVISIONING_DIR/notifiers"
    mkdir -p "$GRAFANA_PROVISIONING_DIR/plugins"
    mkdir -p "$GRAFANA_DATA_DIR/dashboards"

    chown -R grafana:grafana "$GRAFANA_PROVISIONING_DIR"
    chown -R grafana:grafana "$GRAFANA_DATA_DIR"
    chown -R grafana:grafana "$GRAFANA_LOG_DIR"

    log_success "Directories created"
}

configure_grafana() {
    log_info "Configuring Grafana..."

    # Backup original config
    if [[ -f "$GRAFANA_CONFIG_DIR/grafana.ini" ]]; then
        cp "$GRAFANA_CONFIG_DIR/grafana.ini" "$GRAFANA_CONFIG_DIR/grafana.ini.backup"
    fi

    # Update main configuration
    cat > "$GRAFANA_CONFIG_DIR/grafana.ini" <<EOF
# Grafana Configuration - Native Installation
# NO DOCKER

[paths]
data = $GRAFANA_DATA_DIR
logs = $GRAFANA_LOG_DIR
plugins = $GRAFANA_DATA_DIR/plugins
provisioning = $GRAFANA_PROVISIONING_DIR

[server]
protocol = http
http_addr = 0.0.0.0
http_port = $GRAFANA_PORT
domain = mentat.arewel.com
root_url = http://mentat.arewel.com:$GRAFANA_PORT
enable_gzip = true

[database]
type = sqlite3
path = grafana.db

[session]
provider = file

[security]
admin_user = admin
admin_password = changeme
secret_key = SW2YcwTIb9zpOOhoPsMm
disable_gravatar = false
allow_embedding = false

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[auth.basic]
enabled = true

[auth]
disable_login_form = false
disable_signout_menu = false

[snapshots]
external_enabled = false

[log]
mode = console file
level = info

[log.console]
level = info
format = console

[log.file]
level = info
format = text
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7

[alerting]
enabled = true
execute_alerts = true

[metrics]
enabled = true
interval_seconds = 10

[metrics.graphite]
address =
prefix = prod.grafana.%(instance_name)s.

[grafana_net]
url = https://grafana.net

[external_image_storage]
provider =

[rendering]
server_url =
callback_url =

[panels]
disable_sanitize_html = false

[plugins]
enable_alpha = false
app_tls_skip_verify_insecure = false
EOF

    chown grafana:grafana "$GRAFANA_CONFIG_DIR/grafana.ini"
    chmod 640 "$GRAFANA_CONFIG_DIR/grafana.ini"

    log_success "Grafana configured"
}

provision_datasources() {
    log_info "Provisioning Prometheus datasource..."

    cat > "$GRAFANA_PROVISIONING_DIR/datasources/prometheus.yml" <<'EOF'
# Prometheus Datasource Provisioning
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 15s
      queryTimeout: 60s
      httpMethod: POST
    version: 1

  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    isDefault: false
    editable: true
    jsonData:
      maxLines: 1000
      derivedFields:
        - datasourceUid: Prometheus
          matcherRegex: "traceID=(\\w+)"
          name: TraceID
          url: '$${__value.raw}'
    version: 1
EOF

    chown grafana:grafana "$GRAFANA_PROVISIONING_DIR/datasources/prometheus.yml"
    chmod 644 "$GRAFANA_PROVISIONING_DIR/datasources/prometheus.yml"

    log_success "Datasources provisioned"
}

provision_dashboards() {
    log_info "Provisioning dashboard configuration..."

    cat > "$GRAFANA_PROVISIONING_DIR/dashboards/chom.yml" <<EOF
apiVersion: 1

providers:
  - name: 'CHOM Dashboards'
    orgId: 1
    folder: 'CHOM'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: $GRAFANA_DATA_DIR/dashboards
      foldersFromFilesStructure: true
EOF

    chown grafana:grafana "$GRAFANA_PROVISIONING_DIR/dashboards/chom.yml"
    chmod 644 "$GRAFANA_PROVISIONING_DIR/dashboards/chom.yml"

    log_success "Dashboard provisioning configured"
}

install_plugins() {
    log_info "Installing Grafana plugins..."

    # Install useful plugins
    grafana-cli plugins install grafana-piechart-panel || log_warning "Failed to install piechart plugin"
    grafana-cli plugins install grafana-worldmap-panel || log_warning "Failed to install worldmap plugin"
    grafana-cli plugins install grafana-clock-panel || log_warning "Failed to install clock plugin"

    log_success "Plugins installed"
}

configure_firewall() {
    log_info "Configuring firewall for Grafana..."

    if command -v ufw &> /dev/null; then
        ufw allow "$GRAFANA_PORT/tcp" comment "Grafana"
        log_success "UFW rule added for port $GRAFANA_PORT"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port="$GRAFANA_PORT/tcp"
        firewall-cmd --reload
        log_success "Firewalld rule added for port $GRAFANA_PORT"
    else
        log_warning "No firewall detected. Please manually open port $GRAFANA_PORT"
    fi
}

start_service() {
    log_info "Starting Grafana service..."

    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server

    sleep 5

    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana is running"

        # Test endpoint
        if curl -s http://localhost:$GRAFANA_PORT/api/health > /dev/null; then
            log_success "Grafana health check passed"
        else
            log_warning "Grafana started but health check failed"
        fi
    else
        log_error "Failed to start Grafana"
        systemctl status grafana-server --no-pager
        exit 1
    fi
}

create_admin_notice() {
    log_info "Creating admin credentials file..."

    cat > /root/grafana-credentials.txt <<EOF
Grafana Admin Credentials
========================

URL: http://mentat.arewel.com:$GRAFANA_PORT
Username: admin
Password: changeme

IMPORTANT: Change the default password immediately after first login!

To change password via CLI:
grafana-cli admin reset-admin-password <new-password>

Configuration: $GRAFANA_CONFIG_DIR/grafana.ini
Data: $GRAFANA_DATA_DIR
Logs: $GRAFANA_LOG_DIR

Service commands:
  systemctl status grafana-server
  systemctl restart grafana-server
  journalctl -u grafana-server -f
EOF

    chmod 600 /root/grafana-credentials.txt

    log_success "Credentials saved to /root/grafana-credentials.txt"
}

show_status() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN} Grafana Installation Complete${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Web UI:         ${BOLD}http://localhost:$GRAFANA_PORT${NC}"
    echo -e "Config:         ${BOLD}$GRAFANA_CONFIG_DIR/grafana.ini${NC}"
    echo -e "Data Directory: ${BOLD}$GRAFANA_DATA_DIR${NC}"
    echo -e "Provisioning:   ${BOLD}$GRAFANA_PROVISIONING_DIR${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}Default Credentials:${NC}"
    echo -e "  Username: ${BOLD}admin${NC}"
    echo -e "  Password: ${BOLD}changeme${NC}"
    echo -e "  ${RED}CHANGE THIS PASSWORD IMMEDIATELY!${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  systemctl status grafana-server     - Check service status"
    echo "  systemctl restart grafana-server    - Restart service"
    echo "  journalctl -u grafana-server -f     - View logs"
    echo "  grafana-cli admin reset-admin-password <pass> - Reset password"
    echo "  grafana-cli plugins ls              - List installed plugins"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Access Grafana at http://mentat.arewel.com:$GRAFANA_PORT"
    echo "  2. Login with admin/changeme"
    echo "  3. Change the admin password"
    echo "  4. Verify Prometheus datasource is connected"
    echo "  5. Import dashboards from $GRAFANA_DATA_DIR/dashboards"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Native Grafana Installation - Debian 13               ║"
    echo "║     NO DOCKER - Systemd Service Only                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    install_dependencies
    add_grafana_repo
    install_grafana
    create_directories
    configure_grafana
    provision_datasources
    provision_dashboards
    install_plugins
    configure_firewall
    start_service
    create_admin_notice
    show_status
}

main "$@"
