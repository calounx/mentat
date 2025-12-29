#!/bin/bash
#===============================================================================
# Nginx Exporter Installation Script
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

MODULE_NAME="${MODULE_NAME:-nginx_exporter}"
MODULE_VERSION="${MODULE_VERSION:-1.1.0}"
MODULE_PORT="${MODULE_PORT:-9113}"
FORCE_MODE="${FORCE_MODE:-false}"
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"

BINARY_NAME="nginx-prometheus-exporter"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="nginx_exporter"
USER_NAME="nginx_exporter"

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

# Detect existing stub_status configuration
detect_stub_status_url() {
    local stub_port="" stub_path=""

    for conf_file in /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*; do
        if [[ -f "$conf_file" ]] && grep -q "stub_status" "$conf_file" 2>/dev/null; then
            local listen_line
            listen_line=$(grep -B20 "stub_status" "$conf_file" | grep "listen" | tail -1)

            if [[ -n "$listen_line" ]]; then
                if echo "$listen_line" | grep -qE ":[0-9]+"; then
                    stub_port=$(echo "$listen_line" | grep -oE ":[0-9]+" | tr -d ':')
                else
                    stub_port=$(echo "$listen_line" | grep -oE "[0-9]+" | head -1)
                fi
            fi

            stub_path=$(grep -E "location.*(stub_status|nginx_status)" "$conf_file" | grep -oE "/[a-z_]+" | head -1)
            [[ -z "$stub_path" ]] && stub_path="/nginx_status"

            if [[ -n "$stub_port" ]]; then
                log_info "Detected existing stub_status in $conf_file (port $stub_port, path $stub_path)"
                echo "http://127.0.0.1:${stub_port}${stub_path}"
                return 0
            fi
        fi
    done
    return 1
}

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."
    cd /tmp

    # SECURITY: Download with checksum verification
    local archive_name="nginx-prometheus-exporter_${MODULE_VERSION}_linux_amd64.tar.gz"
    local download_url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${MODULE_VERSION}/checksums.txt"

    # SECURITY: Always require checksum verification - fail if unavailable
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    # SECURITY: Fail installation if checksum verification fails
    # NEVER fall back to unverified downloads
    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed for nginx_exporter"
        log_error "Refusing to install unverified binary"
        return 1
    fi

    tar xzf "$archive_name"

    # SECURITY: Safe binary installation
    if type safe_chown &>/dev/null && type safe_chmod &>/dev/null; then
        cp nginx-prometheus-exporter "$INSTALL_PATH"
        safe_chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH" || chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        safe_chmod 755 "$INSTALL_PATH" "$BINARY_NAME binary" || chmod 755 "$INSTALL_PATH"
    else
        cp nginx-prometheus-exporter "$INSTALL_PATH"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
    fi

    rm -rf nginx-prometheus-exporter "$archive_name"
    log_success "$MODULE_NAME binary installed"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi
}

create_service() {
    local STUB_STATUS_URL
    if STUB_STATUS_URL=$(detect_stub_status_url); then
        log_info "Using existing stub_status at: $STUB_STATUS_URL"
    else
        log_info "No existing stub_status found, creating one on port 8080..."

        # H-1: Check if port 8080 is available before creating stub_status config
        if ss -tlnp 2>/dev/null | grep -q ':8080 ' || netstat -tlnp 2>/dev/null | grep -q ':8080 '; then
            log_error "Port 8080 is already in use, cannot create stub_status endpoint"
            log_error "Please configure stub_status manually on an available port"
            return 1
        fi

        cat > /etc/nginx/conf.d/stub_status.conf << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
        # H-2: Add cleanup of stub_status.conf if nginx -t fails
        if ! nginx -t; then
            log_error "Nginx configuration test failed, removing stub_status.conf"
            rm -f /etc/nginx/conf.d/stub_status.conf
            return 1
        fi
        systemctl reload nginx
        STUB_STATUS_URL="http://127.0.0.1:8080/nginx_status"
    fi

    log_info "Creating systemd service..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=$USER_NAME
Group=$USER_NAME
Type=simple
ExecStart=$INSTALL_PATH \\
    --nginx.scrape-uri=${STUB_STATUS_URL}

# SECURITY: Systemd hardening
ProtectSystem=strict
ProtectHome=true
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
    if ! command -v nginx &>/dev/null; then
        log_warn "Nginx not found, skipping $MODULE_NAME"
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
            local wait_count=0
            while pgrep -f "$INSTALL_PATH" >/dev/null 2>&1 && [[ $wait_count -lt 30 ]]; do
                sleep 1
                ((wait_count++))
            done
            pkill -9 -f "$INSTALL_PATH" 2>/dev/null || true
            sleep 2
        fi
    fi

    create_user

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
