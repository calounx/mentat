#!/bin/bash
#
# CHOM Infrastructure Deployment
# Deploys Observability Stack and VPSManager to vanilla Debian 13 VPS
#
# Usage: ./deploy.sh [observability|vpsmanager|all] [--dry-run]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/configs/inventory.yaml"
KEYS_DIR="${SCRIPT_DIR}/keys"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
check_dependencies() {
    local deps=("ssh" "scp" "yq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Missing dependency: $dep"
            if [[ "$dep" == "yq" ]]; then
                log_info "Install yq: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
            fi
            exit 1
        fi
    done
}

# Generate SSH key if not exists
ensure_ssh_key() {
    local key_path="${KEYS_DIR}/chom_deploy_key"
    if [[ ! -f "$key_path" ]]; then
        log_info "Generating deployment SSH key..."
        mkdir -p "$KEYS_DIR"
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "chom-deploy"
        chmod 600 "$key_path"
        log_success "SSH key generated at $key_path"
        log_warn "Add this public key to your VPS servers:"
        cat "${key_path}.pub"
        echo ""
    fi
}

# Read config value using yq
get_config() {
    yq eval "$1" "$CONFIG_FILE"
}

# Execute command on remote VPS
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4
    local key_path="${KEYS_DIR}/chom_deploy_key"

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$key_path" -p "$port" "${user}@${host}" "$cmd"
}

# Copy file to remote VPS
remote_copy() {
    local host=$1
    local user=$2
    local port=$3
    local src=$4
    local dest=$5
    local key_path="${KEYS_DIR}/chom_deploy_key"

    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$key_path" -P "$port" "$src" "${user}@${host}:${dest}"
}

# Deploy Observability Stack
deploy_observability() {
    log_info "Deploying Observability Stack..."

    local ip=$(get_config '.observability.ip')
    local user=$(get_config '.observability.ssh_user')
    local port=$(get_config '.observability.ssh_port')
    local hostname=$(get_config '.observability.hostname')

    if [[ "$ip" == "0.0.0.0" ]]; then
        log_error "Please configure observability.ip in configs/inventory.yaml"
        exit 1
    fi

    log_info "Target: ${user}@${ip}:${port}"

    # Copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" "${SCRIPTS_DIR}/setup-observability-vps.sh" "/tmp/setup-observability-vps.sh"

    # Execute setup
    log_info "Executing setup (this may take 5-10 minutes)..."
    remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-observability-vps.sh && /tmp/setup-observability-vps.sh"

    log_success "Observability Stack deployed successfully!"
    log_info "Grafana: http://${ip}:3000"
    log_info "Prometheus: http://${ip}:9090"
}

# Deploy VPSManager
deploy_vpsmanager() {
    log_info "Deploying VPSManager..."

    local ip=$(get_config '.vpsmanager.ip')
    local user=$(get_config '.vpsmanager.ssh_user')
    local port=$(get_config '.vpsmanager.ssh_port')
    local hostname=$(get_config '.vpsmanager.hostname')
    local obs_ip=$(get_config '.observability.ip')

    if [[ "$ip" == "0.0.0.0" ]]; then
        log_error "Please configure vpsmanager.ip in configs/inventory.yaml"
        exit 1
    fi

    log_info "Target: ${user}@${ip}:${port}"

    # Copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" "${SCRIPTS_DIR}/setup-vpsmanager-vps.sh" "/tmp/setup-vpsmanager-vps.sh"

    # Execute setup with observability server IP
    log_info "Executing setup (this may take 10-15 minutes)..."
    remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-vpsmanager-vps.sh && OBSERVABILITY_IP=${obs_ip} /tmp/setup-vpsmanager-vps.sh"

    log_success "VPSManager deployed successfully!"
    log_info "Dashboard: http://${ip}:8080"
}

# Main
main() {
    local target="${1:-all}"
    local dry_run=false

    if [[ "${2:-}" == "--dry-run" ]]; then
        dry_run=true
        log_warn "Dry run mode - no changes will be made"
    fi

    echo ""
    echo "=========================================="
    echo "  CHOM Infrastructure Deployment"
    echo "=========================================="
    echo ""

    check_dependencies
    ensure_ssh_key

    case "$target" in
        observability)
            deploy_observability
            ;;
        vpsmanager)
            deploy_vpsmanager
            ;;
        all)
            deploy_observability
            echo ""
            deploy_vpsmanager
            ;;
        *)
            log_error "Unknown target: $target"
            echo "Usage: $0 [observability|vpsmanager|all] [--dry-run]"
            exit 1
            ;;
    esac

    echo ""
    log_success "Deployment complete!"
}

main "$@"
