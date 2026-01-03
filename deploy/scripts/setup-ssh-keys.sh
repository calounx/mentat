#!/usr/bin/env bash
# Setup SSH keys for deployment
# Usage: ./setup-ssh-keys.sh [--user stilgar] [--target-host landsraad.arewel.com]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Default values
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
TARGET_HOST="${TARGET_HOST:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            DEPLOY_USER="$2"
            shift 2
            ;;
        --target-host)
            TARGET_HOST="$2"
            shift 2
            ;;
        --key-path)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --key-type)
            SSH_KEY_TYPE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

init_deployment_log "ssh-setup-$(date +%Y%m%d_%H%M%S)"
log_section "SSH Key Setup"

# Generate SSH key if it doesn't exist
setup_local_ssh_key() {
    log_step "Setting up local SSH key"

    if [[ -f "$SSH_KEY_PATH" ]]; then
        log_success "SSH key already exists: $SSH_KEY_PATH"
        return 0
    fi

    log_info "Generating new SSH key: $SSH_KEY_PATH"

    ssh-keygen -t "$SSH_KEY_TYPE" -f "$SSH_KEY_PATH" -N "" -C "${DEPLOY_USER}@deployment-key"

    if [[ $? -eq 0 ]]; then
        log_success "SSH key generated successfully"
    else
        log_fatal "Failed to generate SSH key"
    fi
}

# Copy SSH key to target host
copy_ssh_key_to_target() {
    local target="$1"

    log_step "Copying SSH key to $target"

    if ! ssh-copy-id -i "$SSH_KEY_PATH" "${DEPLOY_USER}@${target}" 2>&1 | tee -a "$LOG_FILE"; then
        log_warning "ssh-copy-id failed, trying manual copy"

        # Manual copy method
        local pub_key=$(cat "${SSH_KEY_PATH}.pub")

        ssh "${DEPLOY_USER}@${target}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

        if [[ $? -eq 0 ]]; then
            log_success "SSH key copied manually to $target"
        else
            log_error "Failed to copy SSH key to $target"
            return 1
        fi
    else
        log_success "SSH key copied to $target"
    fi
}

# Test SSH connection
test_ssh_connection() {
    local target="$1"

    log_step "Testing SSH connection to $target"

    if ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSH_KEY_PATH" "${DEPLOY_USER}@${target}" "echo 'SSH connection successful'" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "SSH connection to $target successful"
        return 0
    else
        log_error "SSH connection to $target failed"
        return 1
    fi
}

# Configure SSH client
configure_ssh_client() {
    log_step "Configuring SSH client"

    local ssh_config="$HOME/.ssh/config"

    if [[ ! -f "$ssh_config" ]]; then
        touch "$ssh_config"
        chmod 600 "$ssh_config"
    fi

    # Add configuration for deployment servers
    local config_entry=$(cat <<EOF

# CHOM Deployment Servers
Host mentat mentat.arewel.com
    HostName mentat.arewel.com
    User $DEPLOY_USER
    IdentityFile $SSH_KEY_PATH
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host landsraad landsraad.arewel.com
    HostName landsraad.arewel.com
    User $DEPLOY_USER
    IdentityFile $SSH_KEY_PATH
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
)

    if ! grep -q "CHOM Deployment Servers" "$ssh_config"; then
        echo "$config_entry" >> "$ssh_config"
        log_success "SSH config updated"
    else
        log_info "SSH config already contains CHOM deployment configuration"
    fi
}

# Setup SSH agent
setup_ssh_agent() {
    log_step "Setting up SSH agent"

    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_info "Starting SSH agent"
        eval "$(ssh-agent -s)"
    fi

    ssh-add "$SSH_KEY_PATH" 2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "SSH key added to agent"
    else
        log_warning "Failed to add SSH key to agent (this is optional)"
    fi
}

# Main execution
main() {
    start_timer

    setup_local_ssh_key
    configure_ssh_client
    setup_ssh_agent

    if [[ -n "$TARGET_HOST" ]]; then
        copy_ssh_key_to_target "$TARGET_HOST"
        test_ssh_connection "$TARGET_HOST"
    else
        log_info "No target host specified, skipping key copy and test"
        log_info "To copy keys to a server, run with: --target-host <hostname>"
    fi

    end_timer "SSH key setup"

    print_header "SSH Key Setup Complete"
    log_success "SSH key path: $SSH_KEY_PATH"
    log_success "Public key: ${SSH_KEY_PATH}.pub"

    if [[ -n "$TARGET_HOST" ]]; then
        log_success "Key deployed to: ${DEPLOY_USER}@${TARGET_HOST}"
    fi
}

main
