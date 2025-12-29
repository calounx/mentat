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

    # SECURITY: Always require checksum verification - fail if unavailable
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    # SECURITY: Fail installation if checksum verification fails
    # NEVER fall back to unverified downloads
    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed for mysqld_exporter"
        log_error "Refusing to install unverified binary"
        return 1
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

        # Auto-generate password if not provided
        if [[ -z "${MYSQL_EXPORTER_PASSWORD:-}" ]]; then
            MYSQL_EXPORTER_PASSWORD=$(openssl rand -base64 16)
            log_warn "Auto-generated MySQL exporter password: ${MYSQL_EXPORTER_PASSWORD}"
            log_warn "Save this password securely - you'll need it to create the MySQL user"
        fi

        cat > "$CONFIG_DIR/.my.cnf" << EOF
[client]
user=exporter
password=${MYSQL_EXPORTER_PASSWORD}
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

    # Extract password from config file to display in instructions
    local exporter_password
    exporter_password=$(grep "^password=" "$CONFIG_DIR/.my.cnf" 2>/dev/null | cut -d= -f2)

    # Try to start the service
    systemctl start "$SERVICE_NAME" 2>/dev/null

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "$MODULE_NAME running (port $MODULE_PORT)"
    else
        log_warn "MySQL Exporter installed but NOT started (MySQL user not configured)"
        log_warn "Create the MySQL user with these commands (run as MySQL root):"
        echo ""
        echo "  CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY '${exporter_password}';"
        echo "  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
        echo "  FLUSH PRIVILEGES;"
        echo ""
        log_warn "Then run: systemctl start mysqld_exporter"
    fi
}

main() {
    if ! command -v mysql &>/dev/null && ! command -v mariadb &>/dev/null; then
        log_warn "MySQL/MariaDB not found, skipping $MODULE_NAME"
        return 0
    fi

    # H-7: Stop service with robust 3-layer verification before binary replacement
    if systemctl list-units --type=service --all | grep -q "^[[:space:]]*$SERVICE_NAME.service" 2>/dev/null; then
        if type stop_and_verify_service &>/dev/null; then
            stop_and_verify_service "$SERVICE_NAME" "$INSTALL_PATH" || {
                log_error "Failed to stop $SERVICE_NAME safely"
                return 1
            }
        else
            # Fallback if stop_and_verify_service not available
            log_warn "stop_and_verify_service not available, using enhanced basic stop"
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true

            # Wait for process to exit
            local wait_count=0
            while pgrep -f "$INSTALL_PATH" >/dev/null 2>&1 && [[ $wait_count -lt 30 ]]; do
                sleep 1
                ((wait_count++))
            done

            # Force kill if needed
            pkill -9 -f "$INSTALL_PATH" 2>/dev/null || true

            # CRITICAL: Wait for file lock release
            wait_count=0
            while [[ $wait_count -lt 30 ]]; do
                if ! lsof "$INSTALL_PATH" &>/dev/null 2>&1; then
                    log_success "Binary file lock released"
                    break
                fi
                sleep 1
                ((wait_count++))
            done

            # Final verification
            if lsof "$INSTALL_PATH" &>/dev/null 2>&1; then
                log_error "File lock still held on $INSTALL_PATH - cannot replace binary"
                return 1
            fi
        fi
    fi

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
