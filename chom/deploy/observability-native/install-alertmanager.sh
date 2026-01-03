#!/bin/bash

###############################################################################
# Native AlertManager Installation for Debian 13
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
ALERTMANAGER_VERSION="0.27.0"
ALERTMANAGER_USER="alertmanager"
ALERTMANAGER_GROUP="alertmanager"
ALERTMANAGER_CONFIG_DIR="/etc/alertmanager"
ALERTMANAGER_DATA_DIR="/var/lib/alertmanager"
ALERTMANAGER_LOG_DIR="/var/log/alertmanager"
ALERTMANAGER_PORT=9093
DOWNLOAD_URL="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

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

create_user() {
    log_info "Creating AlertManager user and group..."

    if ! getent group "$ALERTMANAGER_GROUP" > /dev/null 2>&1; then
        groupadd --system "$ALERTMANAGER_GROUP"
        log_success "Created group: $ALERTMANAGER_GROUP"
    fi

    if ! getent passwd "$ALERTMANAGER_USER" > /dev/null 2>&1; then
        useradd --system \
            --gid "$ALERTMANAGER_GROUP" \
            --no-create-home \
            --shell /bin/false \
            "$ALERTMANAGER_USER"
        log_success "Created user: $ALERTMANAGER_USER"
    fi
}

create_directories() {
    log_info "Creating AlertManager directories..."

    mkdir -p "$ALERTMANAGER_CONFIG_DIR"
    mkdir -p "$ALERTMANAGER_CONFIG_DIR/templates"
    mkdir -p "$ALERTMANAGER_DATA_DIR"
    mkdir -p "$ALERTMANAGER_LOG_DIR"

    chown -R "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" "$ALERTMANAGER_CONFIG_DIR"
    chown -R "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" "$ALERTMANAGER_DATA_DIR"
    chown -R "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" "$ALERTMANAGER_LOG_DIR"

    chmod 755 "$ALERTMANAGER_CONFIG_DIR"
    chmod 755 "$ALERTMANAGER_DATA_DIR"
    chmod 755 "$ALERTMANAGER_LOG_DIR"

    log_success "Directories created and permissions set"
}

download_alertmanager() {
    log_info "Downloading AlertManager v${ALERTMANAGER_VERSION}..."

    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        log_error "Failed to download AlertManager"
        rm -rf "$temp_dir"
        exit 1
    fi

    log_info "Extracting AlertManager..."
    tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

    cd "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"

    # Install binaries
    cp alertmanager /usr/local/bin/
    cp amtool /usr/local/bin/

    # Set permissions
    chown "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" /usr/local/bin/alertmanager
    chown "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" /usr/local/bin/amtool
    chmod 755 /usr/local/bin/alertmanager
    chmod 755 /usr/local/bin/amtool

    cd /
    rm -rf "$temp_dir"

    log_success "AlertManager binaries installed"
}

create_config() {
    log_info "Creating AlertManager configuration..."

    cat > "$ALERTMANAGER_CONFIG_DIR/alertmanager.yml" <<'EOF'
# AlertManager Configuration - Native Installation
# NO DOCKER

global:
  resolve_timeout: 5m
  smtp_smarthost: 'localhost:25'
  smtp_from: 'alertmanager@chom.arewel.com'
  smtp_require_tls: false

# Templates for notifications
templates:
  - '/etc/alertmanager/templates/*.tmpl'

# Route tree for alerts
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'

  routes:
    # Critical alerts - immediate notification
    - match:
        severity: critical
      receiver: 'critical'
      group_wait: 0s
      repeat_interval: 5m

    # Warning alerts - grouped notifications
    - match:
        severity: warning
      receiver: 'warning'
      group_wait: 30s
      repeat_interval: 1h

    # Info alerts - daily digest
    - match:
        severity: info
      receiver: 'info'
      group_wait: 5m
      repeat_interval: 24h

# Receivers define how to send notifications
receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'
        send_resolved: true

  - name: 'critical'
    # Email notifications for critical alerts
    email_configs:
      - to: 'ops@arewel.com'
        headers:
          Subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
        html: '{{ template "email.default.html" . }}'
        send_resolved: true

    # Webhook for integration
    webhook_configs:
      - url: 'http://localhost:5001/webhook/critical'
        send_resolved: true

  - name: 'warning'
    email_configs:
      - to: 'ops@arewel.com'
        headers:
          Subject: '[WARNING] {{ .GroupLabels.alertname }}'
        html: '{{ template "email.default.html" . }}'
        send_resolved: true

  - name: 'info'
    webhook_configs:
      - url: 'http://localhost:5001/webhook/info'
        send_resolved: true

# Inhibition rules to mute certain alerts
inhibit_rules:
  # Mute warning if critical is firing
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']

  # Mute InstanceDown if node is down
  - source_match:
      alertname: 'InstanceDown'
    target_match_re:
      alertname: '.*'
    equal: ['instance']
EOF

    chown "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" "$ALERTMANAGER_CONFIG_DIR/alertmanager.yml"
    chmod 644 "$ALERTMANAGER_CONFIG_DIR/alertmanager.yml"

    log_success "Configuration file created"
}

create_email_template() {
    log_info "Creating email notification template..."

    cat > "$ALERTMANAGER_CONFIG_DIR/templates/email.tmpl" <<'EOF'
{{ define "email.default.html" }}
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        .alert {
            padding: 15px;
            margin: 10px 0;
            border-left: 5px solid;
        }
        .critical { border-color: #dc3545; background: #f8d7da; }
        .warning { border-color: #ffc107; background: #fff3cd; }
        .info { border-color: #17a2b8; background: #d1ecf1; }
        .resolved { border-color: #28a745; background: #d4edda; }
        h2 { margin-top: 0; }
        .details { margin-top: 10px; }
        .label { font-weight: bold; }
    </style>
</head>
<body>
    <h1>CHOM Alert Notification</h1>

    {{ range .Alerts }}
    <div class="alert {{ .Labels.severity }}{{ if eq .Status "resolved" }} resolved{{ end }}">
        <h2>{{ .Labels.alertname }}{{ if eq .Status "resolved" }} - RESOLVED{{ end }}</h2>

        <div class="details">
            <p><span class="label">Severity:</span> {{ .Labels.severity }}</p>
            <p><span class="label">Instance:</span> {{ .Labels.instance }}</p>
            <p><span class="label">Job:</span> {{ .Labels.job }}</p>
            <p><span class="label">Summary:</span> {{ .Annotations.summary }}</p>
            <p><span class="label">Description:</span> {{ .Annotations.description }}</p>
            <p><span class="label">Started at:</span> {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}</p>
            {{ if eq .Status "resolved" }}
            <p><span class="label">Resolved at:</span> {{ .EndsAt.Format "2006-01-02 15:04:05 MST" }}</p>
            {{ end }}
        </div>
    </div>
    {{ end }}

    <hr>
    <p style="color: #666; font-size: 12px;">
        This is an automated alert from the CHOM monitoring system.
        <br>
        Dashboard: <a href="http://mentat.arewel.com:3000">Grafana</a> |
        Prometheus: <a href="http://mentat.arewel.com:9090">Prometheus</a> |
        AlertManager: <a href="http://mentat.arewel.com:9093">AlertManager</a>
    </p>
</body>
</html>
{{ end }}
EOF

    chown "$ALERTMANAGER_USER:$ALERTMANAGER_GROUP" "$ALERTMANAGER_CONFIG_DIR/templates/email.tmpl"
    chmod 644 "$ALERTMANAGER_CONFIG_DIR/templates/email.tmpl"

    log_success "Email template created"
}

create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/alertmanager.service <<EOF
[Unit]
Description=Prometheus AlertManager
Documentation=https://prometheus.io/docs/alerting/alertmanager/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$ALERTMANAGER_USER
Group=$ALERTMANAGER_GROUP

ExecStart=/usr/local/bin/alertmanager \\
    --config.file=$ALERTMANAGER_CONFIG_DIR/alertmanager.yml \\
    --storage.path=$ALERTMANAGER_DATA_DIR \\
    --web.listen-address=0.0.0.0:$ALERTMANAGER_PORT \\
    --web.external-url=http://mentat.arewel.com:$ALERTMANAGER_PORT \\
    --cluster.listen-address= \\
    --log.level=info

ExecReload=/bin/kill -HUP \$MAINPID

Restart=on-failure
RestartSec=5s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=alertmanager

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$ALERTMANAGER_DATA_DIR $ALERTMANAGER_LOG_DIR
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

validate_config() {
    log_info "Validating AlertManager configuration..."

    if /usr/local/bin/amtool check-config "$ALERTMANAGER_CONFIG_DIR/alertmanager.yml"; then
        log_success "Configuration is valid"
    else
        log_error "Configuration validation failed"
        exit 1
    fi
}

configure_firewall() {
    log_info "Configuring firewall for AlertManager..."

    if command -v ufw &> /dev/null; then
        ufw allow "$ALERTMANAGER_PORT/tcp" comment "AlertManager"
        log_success "UFW rule added for port $ALERTMANAGER_PORT"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port="$ALERTMANAGER_PORT/tcp"
        firewall-cmd --reload
        log_success "Firewalld rule added for port $ALERTMANAGER_PORT"
    else
        log_warning "No firewall detected. Please manually open port $ALERTMANAGER_PORT"
    fi
}

start_service() {
    log_info "Starting AlertManager service..."

    systemctl enable alertmanager
    systemctl start alertmanager

    sleep 3

    if systemctl is-active --quiet alertmanager; then
        log_success "AlertManager is running"

        # Test endpoint
        if curl -s http://localhost:$ALERTMANAGER_PORT/-/healthy > /dev/null; then
            log_success "AlertManager health check passed"
        else
            log_warning "AlertManager started but health check failed"
        fi
    else
        log_error "Failed to start AlertManager"
        systemctl status alertmanager --no-pager
        exit 1
    fi
}

show_status() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN} AlertManager Installation Complete${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Version:        ${BOLD}$ALERTMANAGER_VERSION${NC}"
    echo -e "Config:         ${BOLD}$ALERTMANAGER_CONFIG_DIR/alertmanager.yml${NC}"
    echo -e "Data Directory: ${BOLD}$ALERTMANAGER_DATA_DIR${NC}"
    echo -e "Web UI:         ${BOLD}http://localhost:$ALERTMANAGER_PORT${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  systemctl status alertmanager   - Check service status"
    echo "  systemctl restart alertmanager  - Restart service"
    echo "  journalctl -u alertmanager -f   - View logs"
    echo "  amtool check-config /etc/alertmanager/alertmanager.yml - Validate config"
    echo "  amtool alert query              - Query active alerts"
    echo "  amtool config routes            - Show routing tree"
    echo ""
    echo -e "${BOLD}Test Alert:${NC}"
    echo "  # Send a test alert"
    cat <<'TESTCMD'
  curl -X POST http://localhost:9093/api/v2/alerts -H "Content-Type: application/json" -d '[{
    "labels": {"alertname": "TestAlert", "severity": "info"},
    "annotations": {"summary": "Test alert", "description": "This is a test"}
  }]'
TESTCMD
    echo ""
    echo -e "${BOLD}Configuration Files:${NC}"
    echo "  Main config:    $ALERTMANAGER_CONFIG_DIR/alertmanager.yml"
    echo "  Templates:      $ALERTMANAGER_CONFIG_DIR/templates/"
    echo "  Service file:   /etc/systemd/system/alertmanager.service"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Configure email settings in alertmanager.yml"
    echo "  2. Update receiver email addresses"
    echo "  3. Test alert routing with amtool"
    echo "  4. Integrate with Prometheus (already configured)"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Native AlertManager Installation - Debian 13          ║"
    echo "║     NO DOCKER - Systemd Service Only                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    create_user
    create_directories
    download_alertmanager
    create_config
    create_email_template
    create_systemd_service
    validate_config
    configure_firewall
    start_service
    show_status
}

main "$@"
