#!/bin/bash
#===============================================================================
# PHP-FPM Exporter Installation Script
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

MODULE_NAME="${MODULE_NAME:-phpfpm_exporter}"
MODULE_VERSION="${MODULE_VERSION:-2.2.0}"
MODULE_PORT="${MODULE_PORT:-9253}"
FORCE_MODE="${FORCE_MODE:-false}"
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"

BINARY_NAME="php-fpm_exporter"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="phpfpm_exporter"
USER_NAME="phpfpm_exporter"

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

detect_phpfpm_socket() {
    for sock in /run/php/php*-fpm.sock /var/run/php*-fpm.sock /run/php-fpm/*.sock; do
        if [[ -S "$sock" ]]; then
            echo "$sock"
            return 0
        fi
    done
    return 1
}

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."
    cd /tmp

    # SECURITY: Download with checksum verification
    local archive_name="php-fpm_exporter_${MODULE_VERSION}_linux_amd64.tar.gz"
    local download_url="https://github.com/hipages/php-fpm_exporter/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/hipages/php-fpm_exporter/releases/download/v${MODULE_VERSION}/checksums.txt"

    # SECURITY: Always require checksum verification - fail if unavailable
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    # SECURITY: Fail installation if checksum verification fails
    # NEVER fall back to unverified downloads
    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed for phpfpm_exporter"
        log_error "Refusing to install unverified binary"
        return 1
    fi

    tar xzf "$archive_name"

    # SECURITY: Safe binary installation
    if type safe_chown &>/dev/null && type safe_chmod &>/dev/null; then
        cp php-fpm_exporter "$INSTALL_PATH"
        safe_chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH" || chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        safe_chmod 755 "$INSTALL_PATH" "$BINARY_NAME binary" || chmod 755 "$INSTALL_PATH"
    else
        cp php-fpm_exporter "$INSTALL_PATH"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
    fi

    rm -rf php-fpm_exporter "$archive_name"
    log_success "$MODULE_NAME binary installed"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
    usermod -a -G www-data "$USER_NAME" 2>/dev/null || true
}

enable_status_page() {
    local PHP_FPM_CONF
    PHP_FPM_CONF=$(find /etc/php -name "www.conf" 2>/dev/null | head -1)
    if [[ -n "$PHP_FPM_CONF" ]]; then
        if ! grep -q "^pm.status_path" "$PHP_FPM_CONF"; then
            log_info "Enabling PHP-FPM status page..."
            echo "pm.status_path = /status" >> "$PHP_FPM_CONF"
            local fpm_service
            fpm_service=$(systemctl list-units --type=service | grep "php.*fpm" | awk '{print $1}' | head -1)
            if [[ -n "$fpm_service" ]]; then
                systemctl restart "$fpm_service"
            fi
        fi
    fi
}

create_service() {
    local PHP_FPM_STATUS
    local PHP_FPM_SOCKET

    if PHP_FPM_SOCKET=$(detect_phpfpm_socket); then
        log_info "Found PHP-FPM socket: $PHP_FPM_SOCKET"
        PHP_FPM_STATUS="unix://${PHP_FPM_SOCKET};/status"
    else
        PHP_FPM_STATUS="tcp://127.0.0.1:9000/status"
    fi

    log_info "Creating systemd service..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=PHP-FPM Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$USER_NAME
Group=$USER_NAME
Type=simple
ExecStart=$INSTALL_PATH server \\
    --phpfpm.scrape-uri="${PHP_FPM_STATUS}" \\
    --web.listen-address=":$MODULE_PORT"

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
    if ! systemctl list-units --type=service | grep -q "php.*fpm"; then
        log_warn "PHP-FPM not found, skipping $MODULE_NAME"
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
    enable_status_page

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
