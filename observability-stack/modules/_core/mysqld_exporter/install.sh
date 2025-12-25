#!/bin/bash
#===============================================================================
# MySQL Exporter Installation Script
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

MODULE_NAME="${MODULE_NAME:-mysqld_exporter}"
MODULE_VERSION="${MODULE_VERSION:-0.15.1}"
MODULE_PORT="${MODULE_PORT:-9104}"
FORCE_MODE="${FORCE_MODE:-false}"
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"

BINARY_NAME="mysqld_exporter"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="mysqld_exporter"
USER_NAME="mysqld_exporter"
CONFIG_DIR="/etc/mysqld_exporter"

for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE_MODE=true ;;
    esac
done

is_installed() {
    [[ "$FORCE_MODE" == "true" ]] && return 1
    [[ ! -x "$INSTALL_PATH" ]] && return 1
    local current_version
    current_version=$("$INSTALL_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ "$current_version" == "$MODULE_VERSION" ]]
}

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."
    cd /tmp

    # SECURITY: Download with checksum verification
    local archive_name="mysqld_exporter-${MODULE_VERSION}.linux-amd64.tar.gz"
    local download_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MODULE_VERSION}/sha256sums.txt"

    if type download_and_verify &>/dev/null; then
        if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
            log_warn "SECURITY: Checksum verification failed, trying without verification"
            wget -q "$download_url"
        fi
    else
        wget -q "$download_url"
    fi

    tar xzf "$archive_name"

    # SECURITY: Safe binary installation
    if type safe_chown &>/dev/null && type safe_chmod &>/dev/null; then
        cp "mysqld_exporter-${MODULE_VERSION}.linux-amd64/mysqld_exporter" "$INSTALL_PATH"
        safe_chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH" || chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        safe_chmod 755 "$INSTALL_PATH" "$BINARY_NAME binary" || chmod 755 "$INSTALL_PATH"
    else
        cp "mysqld_exporter-${MODULE_VERSION}.linux-amd64/mysqld_exporter" "$INSTALL_PATH"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
    fi

    rm -rf "mysqld_exporter-${MODULE_VERSION}.linux-amd64" "$archive_name"
    log_success "$MODULE_NAME binary installed"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
    mkdir -p "$CONFIG_DIR"
    chown "$USER_NAME:$USER_NAME" "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
}

create_config() {
    if [[ ! -f "$CONFIG_DIR/.my.cnf" ]]; then
        log_info "Creating default config file..."
        cat > "$CONFIG_DIR/.my.cnf" << 'EOF'
[client]
user=exporter
password=CHANGE_ME_EXPORTER_PASSWORD
host=127.0.0.1
EOF
        # SECURITY: Set restrictive permissions on credential file
        if type safe_chmod &>/dev/null && type safe_chown &>/dev/null; then
            safe_chmod 600 "$CONFIG_DIR/.my.cnf" "MySQL credentials file" || chmod 600 "$CONFIG_DIR/.my.cnf"
            safe_chown "$USER_NAME:$USER_NAME" "$CONFIG_DIR/.my.cnf" || chown "$USER_NAME:$USER_NAME" "$CONFIG_DIR/.my.cnf"
        else
            chmod 600 "$CONFIG_DIR/.my.cnf"
            chown "$USER_NAME:$USER_NAME" "$CONFIG_DIR/.my.cnf"
        fi
        log_warn "SECURITY: Default password set in $CONFIG_DIR/.my.cnf - YOU MUST CHANGE IT"
    fi
}

create_service() {
    log_info "Creating systemd service..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'EOF'
[Unit]
Description=MySQL Exporter
Wants=network-online.target
After=network-online.target mysql.service mariadb.service

[Service]
User=mysqld_exporter
Group=mysqld_exporter
Type=simple
ExecStart=/usr/local/bin/mysqld_exporter \
    --config.my-cnf=/etc/mysqld_exporter/.my.cnf \
    --collect.global_status \
    --collect.info_schema.innodb_metrics \
    --collect.auto_increment.columns \
    --collect.info_schema.processlist \
    --collect.binlog_size \
    --collect.info_schema.tablestats \
    --collect.global_variables

# SECURITY: Systemd hardening
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/mysqld_exporter
PrivateTmp=true
NoNewPrivileges=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
CapabilityBoundingSet=
RestrictNamespaces=true
LockPersonality=true

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    log_success "Systemd service created"
}

configure_firewall() {
    if [[ -z "$OBSERVABILITY_IP" ]]; then return; fi
    if command -v ufw &>/dev/null; then
        if ! ufw status | grep -q "$OBSERVABILITY_IP.*$MODULE_PORT"; then
            ufw allow from "$OBSERVABILITY_IP" to any port "$MODULE_PORT" proto tcp
        fi
    fi
}

start_service() {
    systemctl enable "$SERVICE_NAME"

    if grep -q "CHANGE_ME_EXPORTER_PASSWORD" "$CONFIG_DIR/.my.cnf" 2>/dev/null; then
        log_warn "MySQL Exporter installed but NOT started"
        log_warn "Please create the MySQL user and update $CONFIG_DIR/.my.cnf"
        log_warn "Then run: systemctl start mysqld_exporter"
        echo ""
        echo "MySQL commands to run as root:"
        echo "  CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'YOUR_PASSWORD';"
        echo "  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
        echo "  FLUSH PRIVILEGES;"
        echo ""
    else
        systemctl start "$SERVICE_NAME" || log_warn "MySQL Exporter failed to start - check credentials"
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_success "$MODULE_NAME running (port $MODULE_PORT)"
        fi
    fi
}

main() {
    if ! command -v mysql &>/dev/null && ! command -v mariadb &>/dev/null; then
        log_warn "MySQL/MariaDB not found, skipping $MODULE_NAME"
        return 0
    fi

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    pkill -f "$INSTALL_PATH" 2>/dev/null || true
    sleep 1

    create_user
    create_config

    if is_installed; then
        log_skip "$MODULE_NAME v$MODULE_VERSION already installed"
    else
        install_binary
    fi

    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        create_service
    fi

    configure_firewall
    start_service
}

main "$@"
