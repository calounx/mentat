#!/bin/bash
#===============================================================================
# Fail2ban Exporter Installation Script
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

MODULE_NAME="${MODULE_NAME:-fail2ban_exporter}"
MODULE_VERSION="${MODULE_VERSION:-0.10.3}"
MODULE_PORT="${MODULE_PORT:-9191}"
FORCE_MODE="${FORCE_MODE:-false}"
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"

BINARY_NAME="fail2ban-prometheus-exporter"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="fail2ban_exporter"
USER_NAME="fail2ban_exporter"

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
    local archive_name="fail2ban_exporter_${MODULE_VERSION}_linux_amd64.tar.gz"
    local download_url="https://gitlab.com/hctrdev/fail2ban-prometheus-exporter/-/releases/v${MODULE_VERSION}/downloads/${archive_name}"
    local checksum_url="https://gitlab.com/hctrdev/fail2ban-prometheus-exporter/-/releases/v${MODULE_VERSION}/downloads/checksums.txt"

    # SECURITY: Always require checksum verification - fail if unavailable
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    # SECURITY: Fail installation if checksum verification fails
    # NEVER fall back to unverified downloads
    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed for fail2ban_exporter"
        log_error "Refusing to install unverified binary"
        return 1
    fi

    tar xzf "$archive_name"

    # SECURITY: Safe binary installation
    if type safe_chown &>/dev/null && type safe_chmod &>/dev/null; then
        cp fail2ban_exporter "$INSTALL_PATH"
        safe_chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH" || chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        safe_chmod 755 "$INSTALL_PATH" "$BINARY_NAME binary" || chmod 755 "$INSTALL_PATH"
    else
        cp fail2ban_exporter "$INSTALL_PATH"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
    fi

    rm -rf "$archive_name" fail2ban_exporter LICENSE README.md
    log_success "$MODULE_NAME binary installed"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
    if getent group fail2ban > /dev/null 2>&1; then
        usermod -a -G fail2ban "$USER_NAME" 2>/dev/null || true
    fi
}

configure_socket_permissions() {
    if [[ -S /var/run/fail2ban/fail2ban.sock ]]; then
        chmod g+rw /var/run/fail2ban/fail2ban.sock 2>/dev/null || true
    fi
}

create_service() {
    log_info "Creating systemd service..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'EOF'
[Unit]
Description=Fail2ban Prometheus Exporter
Wants=network-online.target
After=network-online.target fail2ban.service

[Service]
User=fail2ban_exporter
Group=fail2ban_exporter
Type=simple
ExecStart=/usr/local/bin/fail2ban-prometheus-exporter \
    --web.listen-address=":9191"

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
    systemctl start "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "$MODULE_NAME running (port $MODULE_PORT)"
    else
        log_error "$MODULE_NAME failed to start"
        return 1
    fi
}

main() {
    if ! command -v fail2ban-client &>/dev/null; then
        log_warn "Fail2ban not found, skipping $MODULE_NAME"
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
            log_warn "stop_and_verify_service not available, using basic stop"
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            pkill -9 -f "$BINARY_NAME" 2>/dev/null || true
            sleep 2
        fi
    fi

    create_user
    configure_socket_permissions

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
