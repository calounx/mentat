#!/bin/bash
#===============================================================================
# Observability Stack Bootstrap Script
#
# Single-command deployment for vanilla Debian 13 VPS
# Usage: curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
#
# This script:
# 1. Validates the environment (Debian 13, root, resources)
# 2. Downloads the observability stack
# 3. Runs the interactive installer
#===============================================================================

set -euo pipefail

# Configuration
REPO_URL="https://github.com/calounx/mentat"
BRANCH="${BRANCH:-master}"
INSTALL_DIR="/opt/observability-stack"
MIN_DISK_GB=10
MIN_RAM_MB=1024

#===============================================================================
# Colors and Output
#===============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  ___  _                              _     _ _ _ _
 / _ \| |__  ___  ___ _ ____   ____ _| |__ (_) (_) |_ _   _
| | | | '_ \/ __|/ _ \ '__\ \ / / _` | '_ \| | | | __| | | |
| |_| | |_) \__ \  __/ |   \ V / (_| | |_) | | | | |_| |_| |
 \___/|_.__/|___/\___|_|    \_/ \__,_|_.__/|_|_|_|\__|\__, |
                                                      |___/
    Stack Deployment for Debian 13
EOF
    echo -e "${NC}"
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

#===============================================================================
# Validation Functions
#===============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "  Try: curl -sSL <url> | sudo bash"
        exit 1
    fi
}

check_debian() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS - /etc/os-release not found"
        exit 1
    fi

    source /etc/os-release

    if [[ "${ID:-}" != "debian" ]]; then
        log_error "This script requires Debian (detected: ${ID:-unknown})"
        exit 1
    fi

    if [[ "${VERSION_ID:-}" != "13" ]]; then
        log_warn "This script is designed for Debian 13 (detected: ${VERSION_ID:-unknown})"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    log_info "Detected: ${PRETTY_NAME:-Debian}"
}

check_resources() {
    # Check disk space
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')

    if [[ $available_gb -lt $MIN_DISK_GB ]]; then
        log_error "Insufficient disk space: ${available_gb}GB available, ${MIN_DISK_GB}GB required"
        exit 1
    fi
    log_info "Disk space: ${available_gb}GB available"

    # Check RAM
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')

    if [[ $total_ram_mb -lt $MIN_RAM_MB ]]; then
        log_warn "Low RAM: ${total_ram_mb}MB (recommended: ${MIN_RAM_MB}MB+)"
    else
        log_info "RAM: ${total_ram_mb}MB"
    fi
}

check_network() {
    log_step "Checking network connectivity..."

    if ! ping -c 1 -W 5 github.com &>/dev/null; then
        log_error "Cannot reach github.com - check network connectivity"
        exit 1
    fi

    log_info "Network connectivity OK"
}

#===============================================================================
# Installation Functions
#===============================================================================

install_prerequisites() {
    log_step "Installing prerequisites..."

    apt-get update -qq
    apt-get install -y -qq \
        git \
        curl \
        wget \
        jq \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        sudo \
        2>/dev/null

    log_info "Prerequisites installed"
}

download_stack() {
    log_step "Downloading observability stack..."

    # Remove existing installation if present
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warn "Existing installation found at $INSTALL_DIR"
        read -p "Remove and reinstall? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            log_info "Using existing installation"
            return 0
        fi
    fi

    # Clone repository
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" /tmp/mentat-clone

    # Move observability-stack to install directory
    mv /tmp/mentat-clone/observability-stack "$INSTALL_DIR"
    rm -rf /tmp/mentat-clone

    # Set permissions
    chmod +x "$INSTALL_DIR"/deploy/*.sh
    chmod +x "$INSTALL_DIR"/deploy/roles/*.sh
    chmod +x "$INSTALL_DIR"/scripts/*.sh

    log_info "Stack downloaded to $INSTALL_DIR"
}

run_installer() {
    log_step "Starting interactive installer..."
    echo

    cd "$INSTALL_DIR"
    exec ./deploy/install.sh
}

#===============================================================================
# Main
#===============================================================================

main() {
    print_banner

    echo -e "${CYAN}This script will install the Observability Stack on your Debian 13 VPS.${NC}"
    echo

    check_root
    check_debian
    check_resources
    check_network

    echo
    read -p "Continue with installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi

    install_prerequisites
    download_stack
    run_installer
}

main "$@"
