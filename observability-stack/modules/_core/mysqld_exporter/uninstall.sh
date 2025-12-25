#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME=$(basename "$SCRIPT_DIR")

log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }

PURGE_DATA=false
for arg in "$@"; do
    [[ "$arg" == "--purge" ]] && PURGE_DATA=true
done

# Map module names to service/binary names
case "$MODULE_NAME" in
    nginx_exporter)
        SERVICE_NAME="nginx_exporter"
        BINARY_PATH="/usr/local/bin/nginx-prometheus-exporter"
        USER_NAME="nginx_exporter"
        ;;
    mysqld_exporter)
        SERVICE_NAME="mysqld_exporter"
        BINARY_PATH="/usr/local/bin/mysqld_exporter"
        USER_NAME="mysqld_exporter"
        ;;
    phpfpm_exporter)
        SERVICE_NAME="phpfpm_exporter"
        BINARY_PATH="/usr/local/bin/php-fpm_exporter"
        USER_NAME="phpfpm_exporter"
        ;;
    fail2ban_exporter)
        SERVICE_NAME="fail2ban_exporter"
        BINARY_PATH="/usr/local/bin/fail2ban-prometheus-exporter"
        USER_NAME="fail2ban_exporter"
        ;;
    promtail)
        SERVICE_NAME="promtail"
        BINARY_PATH="/usr/local/bin/promtail"
        USER_NAME="promtail"
        ;;
esac

log_info "Uninstalling $MODULE_NAME..."

systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload

rm -f "$BINARY_PATH"

userdel "$USER_NAME" 2>/dev/null || true
groupdel "$USER_NAME" 2>/dev/null || true

if [[ "$PURGE_DATA" == "true" ]]; then
    case "$MODULE_NAME" in
        mysqld_exporter) rm -rf /etc/mysqld_exporter ;;
        promtail) rm -rf /etc/promtail /var/lib/promtail ;;
        nginx_exporter) rm -f /etc/nginx/conf.d/stub_status.conf ;;
    esac
fi

log_success "$MODULE_NAME uninstalled"
