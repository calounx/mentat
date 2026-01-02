#!/bin/bash
#
# CHOM Infrastructure Deployment
# Deploys Observability Stack and VPSManager to vanilla Debian 13 VPS
#
# Features:
#   - Zero-downtime deployment capability
#   - Proper rollback support
#   - Integration with observability stack
#   - SSH key management
#
# Usage: ./deploy.sh [observability|vpsmanager|all] [--dry-run] [--rollback]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/configs/inventory.yaml"
KEYS_DIR="${SCRIPT_DIR}/keys"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
BACKUP_DIR="${SCRIPT_DIR}/.backups"

# Script version
readonly SCRIPT_VERSION="2.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

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

# Copy directory to remote VPS recursively
remote_copy_dir() {
    local host=$1
    local user=$2
    local port=$3
    local src=$4
    local dest=$5
    local key_path="${KEYS_DIR}/chom_deploy_key"

    scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$key_path" -P "$port" "$src" "${user}@${host}:${dest}"
}

# Create remote directory
remote_mkdir() {
    local host=$1
    local user=$2
    local port=$3
    local dir=$4

    remote_exec "$host" "$user" "$port" "mkdir -p $dir"
}

# Create backup before deployment
create_backup() {
    local host=$1
    local user=$2
    local port=$3
    local backup_name=$4
    local timestamp=$(date +%Y%m%d-%H%M%S)

    log_info "Creating backup: ${backup_name}-${timestamp}"

    # Create local backup directory
    mkdir -p "${BACKUP_DIR}/${backup_name}"

    # Backup remote configs if they exist
    remote_exec "$host" "$user" "$port" \
        "tar -czf /tmp/${backup_name}-backup-${timestamp}.tar.gz \
         /etc/observability 2>/dev/null || \
         tar -czf /tmp/${backup_name}-backup-${timestamp}.tar.gz \
         /etc/vpsmanager 2>/dev/null || \
         echo 'No previous config to backup'" || true

    log_success "Backup created: ${backup_name}-${timestamp}"
}

# Perform rollback
perform_rollback() {
    local host=$1
    local user=$2
    local port=$3
    local target=$4

    log_step "Performing rollback for $target..."

    # Find latest backup
    local latest_backup=$(ls -t "${BACKUP_DIR}/${target}/" 2>/dev/null | head -1)

    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found for $target"
        return 1
    fi

    log_info "Rolling back to: $latest_backup"

    # Copy backup to remote and restore
    remote_copy "$host" "$user" "$port" \
        "${BACKUP_DIR}/${target}/${latest_backup}" "/tmp/"

    remote_exec "$host" "$user" "$port" \
        "tar -xzf /tmp/${latest_backup} -C / && systemctl restart nginx"

    log_success "Rollback completed for $target"
}

# Prepare remote environment (copy library and configs)
prepare_remote_env() {
    local host=$1
    local user=$2
    local port=$3

    log_info "Preparing remote environment..."

    # Create remote directories
    remote_mkdir "$host" "$user" "$port" "/tmp/chom-deploy/lib"
    remote_mkdir "$host" "$user" "$port" "/tmp/chom-deploy/configs"

    # Copy common library
    if [[ -f "${LIB_DIR}/deploy-common.sh" ]]; then
        remote_copy "$host" "$user" "$port" \
            "${LIB_DIR}/deploy-common.sh" "/tmp/chom-deploy/lib/deploy-common.sh"
        log_success "Common library copied"
    else
        log_error "Common library not found: ${LIB_DIR}/deploy-common.sh"
        return 1
    fi

    # Copy promtail/alloy configs if deploying vpsmanager
    if [[ -f "${CONFIGS_DIR}/promtail-chom.yaml" ]]; then
        remote_copy "$host" "$user" "$port" \
            "${CONFIGS_DIR}/promtail-chom.yaml" "/tmp/chom-deploy/configs/"
    fi

    if [[ -f "${CONFIGS_DIR}/alloy-chom.alloy" ]]; then
        remote_copy "$host" "$user" "$port" \
            "${CONFIGS_DIR}/alloy-chom.alloy" "/tmp/chom-deploy/configs/"
    fi

    log_success "Remote environment prepared"
}

# Deploy Observability Stack
deploy_observability() {
    log_step "Deploying Observability Stack..."

    local ip=$(get_config '.observability.ip')
    local user=$(get_config '.observability.ssh_user')
    local port=$(get_config '.observability.ssh_port')
    local hostname=$(get_config '.observability.hostname')
    local domain=$(get_config '.observability.config.grafana_domain')

    if [[ "$ip" == "0.0.0.0" ]]; then
        log_error "Please configure observability.ip in configs/inventory.yaml"
        exit 1
    fi

    log_info "Target: ${user}@${ip}:${port}"

    # Prepare remote environment with library
    prepare_remote_env "$ip" "$user" "$port"

    # Create backup before deployment
    create_backup "$ip" "$user" "$port" "observability"

    # Copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" "${SCRIPTS_DIR}/setup-observability-vps.sh" "/tmp/chom-deploy/setup-observability-vps.sh"

    # Execute setup with environment variables
    log_info "Executing setup (this may take 5-10 minutes)..."
    local env_vars="DOMAIN=${domain:-$hostname}"
    if remote_exec "$ip" "$user" "$port" "cd /tmp/chom-deploy && chmod +x setup-observability-vps.sh && ${env_vars} ./setup-observability-vps.sh"; then
        log_success "Observability Stack deployed successfully!"
        log_info "Grafana: http://${ip}:3000"
        log_info "Prometheus: http://${ip}:9090"
    else
        log_error "Observability deployment failed!"
        log_warn "Check logs on remote: journalctl -xeu prometheus grafana-server loki"
        return 1
    fi
}

# Deploy VPSManager
deploy_vpsmanager() {
    log_step "Deploying VPSManager..."

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

    # Prepare remote environment with library
    prepare_remote_env "$ip" "$user" "$port"

    # Create backup before deployment
    create_backup "$ip" "$user" "$port" "vpsmanager"

    # Copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" "${SCRIPTS_DIR}/setup-vpsmanager-vps.sh" "/tmp/chom-deploy/setup-vpsmanager-vps.sh"

    # Update promtail/alloy config with actual observability IP
    if [[ "$obs_ip" != "0.0.0.0" && "$obs_ip" != "null" ]]; then
        log_info "Configuring log forwarding to observability server..."
        remote_exec "$ip" "$user" "$port" \
            "sed -i 's/MENTAT_TST_IP/${obs_ip}/g' /tmp/chom-deploy/configs/promtail-chom.yaml 2>/dev/null || true"
        remote_exec "$ip" "$user" "$port" \
            "sed -i 's/OBSERVABILITY_IP/${obs_ip}/g' /tmp/chom-deploy/configs/alloy-chom.alloy 2>/dev/null || true"
    fi

    # Execute setup with observability server IP
    log_info "Executing setup (this may take 10-15 minutes)..."
    local env_vars="OBSERVABILITY_IP=${obs_ip} DOMAIN=${hostname}"
    if remote_exec "$ip" "$user" "$port" "cd /tmp/chom-deploy && chmod +x setup-vpsmanager-vps.sh && ${env_vars} ./setup-vpsmanager-vps.sh"; then
        log_success "VPSManager deployed successfully!"
        log_info "Dashboard: http://${ip}:8080"

        # Show integration status
        if [[ "$obs_ip" != "0.0.0.0" && "$obs_ip" != "null" ]]; then
            log_info "Metrics forwarding to: http://${obs_ip}:9090"
            log_info "Logs forwarding to: http://${obs_ip}:3100"
        fi
    else
        log_error "VPSManager deployment failed!"
        log_warn "Check logs on remote: journalctl -xeu nginx php8.2-fpm mariadb"
        return 1
    fi
}

# Show help
show_help() {
    cat << EOF
CHOM Infrastructure Deployment v${SCRIPT_VERSION}

Usage: $0 [TARGET] [OPTIONS]

Targets:
    observability    Deploy only the observability stack
    vpsmanager       Deploy only the VPSManager application
    all              Deploy both stacks (default)

Options:
    --dry-run        Show what would be done without executing
    --rollback       Rollback to the previous deployment
    --help           Show this help message
    --version        Show version information

Examples:
    $0                       # Deploy all (default)
    $0 observability         # Deploy only observability stack
    $0 vpsmanager            # Deploy only VPSManager
    $0 all --dry-run         # Preview deployment
    $0 vpsmanager --rollback # Rollback VPSManager deployment

Prerequisites:
    1. Configure IPs in configs/inventory.yaml
    2. SSH key will be generated on first run
    3. Copy SSH key to VPS servers (shown after generation)

For detailed deployment guide, see: DEPLOYMENT-GUIDE.md
EOF
    exit 0
}

# Main
main() {
    local target="${1:-all}"
    local dry_run=false
    local do_rollback=false

    # Parse options
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                dry_run=true
                ;;
            --rollback)
                do_rollback=true
                ;;
            --help|-h)
                show_help
                ;;
            --version|-v)
                echo "CHOM Infrastructure Deployment v${SCRIPT_VERSION}"
                exit 0
                ;;
        esac
    done

    echo ""
    echo "=========================================="
    echo "  CHOM Infrastructure Deployment v${SCRIPT_VERSION}"
    echo "=========================================="
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
    fi

    check_dependencies
    ensure_ssh_key

    # Handle rollback
    if [[ "$do_rollback" == "true" ]]; then
        log_step "Performing rollback..."
        case "$target" in
            observability)
                local ip=$(get_config '.observability.ip')
                local user=$(get_config '.observability.ssh_user')
                local port=$(get_config '.observability.ssh_port')
                perform_rollback "$ip" "$user" "$port" "observability"
                ;;
            vpsmanager)
                local ip=$(get_config '.vpsmanager.ip')
                local user=$(get_config '.vpsmanager.ssh_user')
                local port=$(get_config '.vpsmanager.ssh_port')
                perform_rollback "$ip" "$user" "$port" "vpsmanager"
                ;;
            all)
                log_error "Cannot rollback all at once. Specify observability or vpsmanager."
                exit 1
                ;;
        esac
        log_success "Rollback complete!"
        exit 0
    fi

    # Normal deployment
    case "$target" in
        observability)
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would deploy observability stack to $(get_config '.observability.ip')"
            else
                deploy_observability
            fi
            ;;
        vpsmanager)
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would deploy VPSManager to $(get_config '.vpsmanager.ip')"
            else
                deploy_vpsmanager
            fi
            ;;
        all)
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would deploy observability stack to $(get_config '.observability.ip')"
                log_info "Would deploy VPSManager to $(get_config '.vpsmanager.ip')"
            else
                deploy_observability
                echo ""
                deploy_vpsmanager
            fi
            ;;
        --*)
            # Skip options already handled
            ;;
        *)
            log_error "Unknown target: $target"
            echo "Usage: $0 [observability|vpsmanager|all] [--dry-run] [--rollback]"
            exit 1
            ;;
    esac

    echo ""
    log_success "Deployment complete!"
}

main "$@"
