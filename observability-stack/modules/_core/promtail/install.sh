#!/bin/bash
#===============================================================================
# Promtail Installation Script
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_skip() { echo "[SKIP] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

MODULE_NAME="${MODULE_NAME:-promtail}"
MODULE_VERSION="${MODULE_VERSION:-2.9.3}"
MODULE_PORT="${MODULE_PORT:-9080}"
FORCE_MODE="${FORCE_MODE:-false}"

# Promtail-specific config (must be provided)
LOKI_URL="${LOKI_URL:-}"
LOKI_USER="${LOKI_USER:-}"
LOKI_PASS="${LOKI_PASS:-}"

BINARY_NAME="promtail"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="promtail"
USER_NAME="promtail"
CONFIG_DIR="/etc/promtail"
DATA_DIR="/var/lib/promtail"

for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE_MODE=true ;;
    esac
done

is_installed() {
    [[ "$FORCE_MODE" == "true" ]] && return 1
    [[ ! -x "$INSTALL_PATH" ]] && return 1
    local current_version
    current_version=$("$INSTALL_PATH" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ "$current_version" == "$MODULE_VERSION" ]]
}

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."
    cd /tmp

    wget -q "https://github.com/grafana/loki/releases/download/v${MODULE_VERSION}/promtail-linux-amd64.zip"
    unzip -o promtail-linux-amd64.zip
    chmod +x promtail-linux-amd64
    mv promtail-linux-amd64 "$INSTALL_PATH"

    rm -f promtail-linux-amd64.zip
    log_success "$MODULE_NAME binary installed"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
    usermod -a -G adm "$USER_NAME"
    usermod -a -G www-data "$USER_NAME" 2>/dev/null || true

    mkdir -p "$CONFIG_DIR" "$DATA_DIR"
    chown -R "$USER_NAME:$USER_NAME" "$CONFIG_DIR" "$DATA_DIR"
}

create_config() {
    if [[ -z "$LOKI_URL" ]]; then
        log_warn "LOKI_URL not provided, skipping config creation"
        return 1
    fi

    # Normalize LOKI_URL
    LOKI_URL="${LOKI_URL%/}"
    LOKI_URL="${LOKI_URL%/loki}"
    LOKI_URL="${LOKI_URL%/}"

    local HOSTNAME
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)

    log_info "Creating Promtail configuration..."
    cat > "$CONFIG_DIR/promtail.yaml" << EOF
server:
  http_listen_port: $MODULE_PORT
  grpc_listen_port: 0

positions:
  filename: $DATA_DIR/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    basic_auth:
      username: ${LOKI_USER}
      password: ${LOKI_PASS}

scrape_configs:
  - job_name: nginx_access
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx_access
          host: ${HOSTNAME}
          __path__: /var/log/nginx/access.log

  - job_name: nginx_error
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx_error
          host: ${HOSTNAME}
          __path__: /var/log/nginx/error.log

  - job_name: php_error
    static_configs:
      - targets: [localhost]
        labels:
          job: php_error
          host: ${HOSTNAME}
          __path__: /var/log/php*-fpm.log

  - job_name: mysql_slow
    static_configs:
      - targets: [localhost]
        labels:
          job: mysql_slow
          host: ${HOSTNAME}
          __path__: /var/log/mysql/mysql-slow.log
    pipeline_stages:
      - multiline:
          firstline: '^# Time:'
          max_wait_time: 3s

  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/syslog

  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/auth.log

  - job_name: wordpress
    static_configs:
      - targets: [localhost]
        labels:
          job: wordpress
          host: ${HOSTNAME}
          __path__: /var/www/*/wp-content/debug.log
EOF

    chown "$USER_NAME:$USER_NAME" "$CONFIG_DIR/promtail.yaml"
    log_success "Promtail configuration created"
}

create_service() {
    log_info "Creating systemd service..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'EOF'
[Unit]
Description=Promtail
Wants=network-online.target
After=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    log_success "Systemd service created"
}

start_service() {
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "$MODULE_NAME running (log shipping to Loki)"
    else
        log_error "$MODULE_NAME failed to start"
        return 1
    fi
}

main() {
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    pkill -f "$INSTALL_PATH" 2>/dev/null || true
    sleep 1

    create_user

    if is_installed; then
        log_skip "$MODULE_NAME v$MODULE_VERSION already installed"
    else
        install_binary
    fi

    create_config || true

    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        create_service
    fi

    if [[ -f "$CONFIG_DIR/promtail.yaml" ]]; then
        start_service
    else
        log_warn "Promtail installed but not started (no config)"
    fi
}

main "$@"
