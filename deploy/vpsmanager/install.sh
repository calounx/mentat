#!/usr/bin/env bash
# VPSManager Installation Script
# Installs vpsmanager CLI tool on a VPS server
#
# Usage: sudo ./install.sh [--uninstall]

set -euo pipefail

# Installation paths
INSTALL_DIR="/opt/vpsmanager"
BIN_LINK="/usr/local/bin/vpsmanager"
SITES_ROOT="/var/www/sites"
BACKUP_ROOT="/var/backups/sites"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install vpsmanager
install_vpsmanager() {
    log_info "Installing VPSManager to ${INSTALL_DIR}"

    # Create installation directory
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warn "Existing installation found, backing up..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%s)"
    fi

    mkdir -p "$INSTALL_DIR"

    # Copy files
    log_info "Copying files..."
    cp -r "${SCRIPT_DIR}/bin" "$INSTALL_DIR/"
    cp -r "${SCRIPT_DIR}/lib" "$INSTALL_DIR/"
    cp -r "${SCRIPT_DIR}/config" "$INSTALL_DIR/"
    cp -r "${SCRIPT_DIR}/templates" "$INSTALL_DIR/"

    # Create data and var directories
    mkdir -p "${INSTALL_DIR}/data"
    mkdir -p "${INSTALL_DIR}/var/log"

    # Initialize sites registry
    if [[ ! -f "${INSTALL_DIR}/data/sites.json" ]]; then
        echo '{"sites":[]}' > "${INSTALL_DIR}/data/sites.json"
    fi

    # Set permissions
    log_info "Setting permissions..."
    chmod +x "${INSTALL_DIR}/bin/vpsmanager"
    chmod 755 "${INSTALL_DIR}"
    chmod -R 755 "${INSTALL_DIR}/bin"
    chmod -R 755 "${INSTALL_DIR}/lib"
    chmod 644 "${INSTALL_DIR}/config/vpsmanager.conf"
    chmod -R 644 "${INSTALL_DIR}/templates"/*
    chmod 755 "${INSTALL_DIR}/templates"

    # Create symlink
    log_info "Creating symlink in /usr/local/bin..."
    if [[ -L "$BIN_LINK" ]]; then
        rm -f "$BIN_LINK"
    fi
    ln -sf "${INSTALL_DIR}/bin/vpsmanager" "$BIN_LINK"

    # Create sites directory
    if [[ ! -d "$SITES_ROOT" ]]; then
        log_info "Creating sites directory: ${SITES_ROOT}"
        mkdir -p "$SITES_ROOT"
        chown www-data:www-data "$SITES_ROOT"
        chmod 755 "$SITES_ROOT"
    fi

    # Create backup directory
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        log_info "Creating backup directory: ${BACKUP_ROOT}"
        mkdir -p "$BACKUP_ROOT"
        chown www-data:www-data "$BACKUP_ROOT"
        chmod 750 "$BACKUP_ROOT"
    fi

    # Check dependencies
    log_info "Checking dependencies..."
    check_dependencies

    log_info "VPSManager installed successfully!"
    log_info ""
    log_info "Usage: vpsmanager <command> [options]"
    log_info ""
    log_info "Commands:"
    log_info "  site:create <domain> --type=<type> --php-version=<version>"
    log_info "  site:delete <domain> [--force]"
    log_info "  site:list"
    log_info "  ssl:issue <domain>"
    log_info "  backup:create <domain>"
    log_info "  monitor:health"
    log_info ""
    log_info "Run 'vpsmanager help' for more information."
}

# Uninstall vpsmanager
uninstall_vpsmanager() {
    log_info "Uninstalling VPSManager..."

    if [[ -L "$BIN_LINK" ]]; then
        rm -f "$BIN_LINK"
        log_info "Removed symlink: ${BIN_LINK}"
    fi

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log_info "Removed installation directory: ${INSTALL_DIR}"
    fi

    log_info "VPSManager uninstalled."
    log_warn "Sites directory (${SITES_ROOT}) and backups (${BACKUP_ROOT}) were preserved."
}

# Check required dependencies
check_dependencies() {
    local missing=()

    # Required commands
    local required_cmds=(
        "nginx"
        "php"
        "mysql"
        "certbot"
        "jq"
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing recommended dependencies: ${missing[*]}"
        log_warn "Some features may not work without these packages."
        log_warn ""
        log_warn "Install with: apt install nginx php-fpm mariadb-server certbot jq"
    else
        log_info "All dependencies found"
    fi

    # Check PHP-FPM
    local php_version="${PHP_VERSION:-8.2}"
    if ! systemctl is-active --quiet "php${php_version}-fpm" 2>/dev/null; then
        log_warn "PHP-FPM ${php_version} is not running"
    fi

    # Check nginx
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        log_warn "Nginx is not running"
    fi
}

# Update configuration
configure_vpsmanager() {
    local config_file="${INSTALL_DIR}/config/vpsmanager.conf"

    log_info "Configuring VPSManager..."

    # Prompt for configuration (if interactive)
    if [[ -t 0 ]]; then
        read -p "Certbot email for SSL certificates [admin@example.com]: " certbot_email
        certbot_email="${certbot_email:-admin@example.com}"

        # Update config file
        sed -i "s|CERTBOT_EMAIL=.*|CERTBOT_EMAIL=\"${certbot_email}\"|" "$config_file"

        log_info "Configuration updated"
    else
        log_warn "Non-interactive mode, using default configuration"
        log_warn "Edit ${config_file} to customize settings"
    fi
}

# Main
main() {
    check_root

    case "${1:-install}" in
        --uninstall|uninstall)
            uninstall_vpsmanager
            ;;
        --configure|configure)
            configure_vpsmanager
            ;;
        install|*)
            install_vpsmanager
            configure_vpsmanager
            ;;
    esac
}

main "$@"
