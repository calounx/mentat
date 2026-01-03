#!/usr/bin/env bash
# Auto-generate and distribute SSH keys for passwordless deployment (IDEMPOTENT)
# This script sets up SSH key-based authentication between servers
# Usage: ./setup-ssh-automation.sh --from mentat.arewel.com --to landsraad.arewel.com

set -euo pipefail

# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo "" >&2
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "" >&2
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo "" >&2
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

source "${SCRIPT_DIR}/../utils/logging.sh"
source "${SCRIPT_DIR}/../utils/dependency-validation.sh"

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
FROM_HOST=""
TO_HOST=""
KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"
KEY_SIZE="${SSH_KEY_SIZE:-4096}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from)
            FROM_HOST="$2"
            shift 2
            ;;
        --to)
            TO_HOST="$2"
            shift 2
            ;;
        --user)
            DEPLOY_USER="$2"
            shift 2
            ;;
        --key-type)
            KEY_TYPE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 --from <source-host> --to <destination-host> [--user username] [--key-type ed25519|rsa]"
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$FROM_HOST" ]] || [[ -z "$TO_HOST" ]]; then
    echo "Error: Both --from and --to arguments are required"
    echo "Usage: $0 --from <source-host> --to <destination-host>"
    exit 1
fi

init_deployment_log "setup-ssh-$(date +%Y%m%d_%H%M%S)"
log_section "SSH Automation Setup"

log_info "From: $FROM_HOST (user: $DEPLOY_USER)"
log_info "To: $TO_HOST (user: $DEPLOY_USER)"
log_info "Key Type: $KEY_TYPE"

# Generate SSH key pair if doesn't exist
generate_ssh_key() {
    log_step "Generating SSH key pair on $FROM_HOST"

    local key_file="/home/${DEPLOY_USER}/.ssh/id_${KEY_TYPE}"

    # Check if key already exists
    if ssh "$DEPLOY_USER@$FROM_HOST" "test -f $key_file"; then
        log_success "SSH key already exists: $key_file"

        # Display public key
        log_info "Public key:"
        ssh "$DEPLOY_USER@$FROM_HOST" "cat ${key_file}.pub"
        return 0
    fi

    log_info "Creating new SSH key pair"

    # Generate key based on type
    if [[ "$KEY_TYPE" == "ed25519" ]]; then
        ssh "$DEPLOY_USER@$FROM_HOST" "ssh-keygen -t ed25519 -f $key_file -N '' -C '${DEPLOY_USER}@${FROM_HOST}'"
    elif [[ "$KEY_TYPE" == "rsa" ]]; then
        ssh "$DEPLOY_USER@$FROM_HOST" "ssh-keygen -t rsa -b $KEY_SIZE -f $key_file -N '' -C '${DEPLOY_USER}@${FROM_HOST}'"
    else
        log_error "Unsupported key type: $KEY_TYPE"
        return 1
    fi

    log_success "SSH key pair generated"

    # Display public key
    log_info "Public key:"
    ssh "$DEPLOY_USER@$FROM_HOST" "cat ${key_file}.pub"
}

# Copy SSH key to destination
copy_ssh_key() {
    log_step "Copying SSH key to $TO_HOST"

    local key_file="/home/${DEPLOY_USER}/.ssh/id_${KEY_TYPE}"

    # Get public key
    local public_key=$(ssh "$DEPLOY_USER@$FROM_HOST" "cat ${key_file}.pub")

    # Check if key is already in authorized_keys
    if ssh "$DEPLOY_USER@$TO_HOST" "grep -q '$public_key' /home/${DEPLOY_USER}/.ssh/authorized_keys 2>/dev/null"; then
        log_success "SSH key already authorized on $TO_HOST"
        return 0
    fi

    log_info "Adding public key to authorized_keys on $TO_HOST"

    # Ensure .ssh directory exists on destination
    ssh "$DEPLOY_USER@$TO_HOST" "mkdir -p /home/${DEPLOY_USER}/.ssh && chmod 700 /home/${DEPLOY_USER}/.ssh"

    # Add public key to authorized_keys
    ssh "$DEPLOY_USER@$FROM_HOST" "cat ${key_file}.pub" | \
        ssh "$DEPLOY_USER@$TO_HOST" "cat >> /home/${DEPLOY_USER}/.ssh/authorized_keys && chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys"

    log_success "SSH key copied and authorized"
}

# Test SSH connection
test_ssh_connection() {
    log_step "Testing passwordless SSH connection"

    log_info "Testing: $DEPLOY_USER@$FROM_HOST -> $DEPLOY_USER@$TO_HOST"

    # Test SSH connection from FROM_HOST to TO_HOST
    if ssh "$DEPLOY_USER@$FROM_HOST" "ssh -o BatchMode=yes -o ConnectTimeout=5 $DEPLOY_USER@$TO_HOST 'echo SSH connection successful' 2>/dev/null"; then
        log_success "Passwordless SSH connection working"
        return 0
    else
        log_error "SSH connection test failed"
        log_warning "You may need to accept the host key on first connection"
        log_info "Run this command to accept the host key:"
        log_info "  ssh $DEPLOY_USER@$FROM_HOST \"ssh -o StrictHostKeyChecking=accept-new $DEPLOY_USER@$TO_HOST 'exit'\""
        return 1
    fi
}

# Configure SSH client settings
configure_ssh_client() {
    log_step "Configuring SSH client on $FROM_HOST"

    local ssh_config="/home/${DEPLOY_USER}/.ssh/config"

    # Create SSH config entry for destination host
    local config_entry="
Host ${TO_HOST}
    User ${DEPLOY_USER}
    IdentityFile /home/${DEPLOY_USER}/.ssh/id_${KEY_TYPE}
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
"

    # Check if configuration already exists
    if ssh "$DEPLOY_USER@$FROM_HOST" "test -f $ssh_config && grep -q 'Host ${TO_HOST}' $ssh_config 2>/dev/null"; then
        log_success "SSH client config already exists"
    else
        log_info "Adding SSH client configuration"

        ssh "$DEPLOY_USER@$FROM_HOST" "echo '$config_entry' >> $ssh_config && chmod 600 $ssh_config"

        log_success "SSH client configured"
    fi
}

# Setup SSH agent forwarding (optional)
setup_ssh_agent() {
    log_step "Setting up SSH agent configuration"

    local bashrc="/home/${DEPLOY_USER}/.bashrc"

    # Add SSH agent configuration if not already present
    if ssh "$DEPLOY_USER@$FROM_HOST" "grep -q 'SSH Agent Configuration' $bashrc 2>/dev/null"; then
        log_success "SSH agent already configured"
    else
        log_info "Adding SSH agent configuration to .bashrc"

        ssh "$DEPLOY_USER@$FROM_HOST" "cat >> $bashrc" <<'EOF'

# SSH Agent Configuration
if [ -z "$SSH_AUTH_SOCK" ]; then
    # Check for running ssh-agent
    if [ -f ~/.ssh/agent.env ]; then
        . ~/.ssh/agent.env > /dev/null
    fi

    # Start ssh-agent if not running
    if ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
        ssh-agent > ~/.ssh/agent.env
        . ~/.ssh/agent.env > /dev/null
        ssh-add ~/.ssh/id_* 2>/dev/null
    fi
fi
EOF

        log_success "SSH agent configured"
    fi
}

# Display connection information
display_connection_info() {
    log_section "SSH Connection Information"

    log_info "Source: $DEPLOY_USER@$FROM_HOST"
    log_info "Destination: $DEPLOY_USER@$TO_HOST"
    log_info "Key Type: $KEY_TYPE"
    log_info "Key File: /home/${DEPLOY_USER}/.ssh/id_${KEY_TYPE}"
    log_info ""
    log_info "Test connection with:"
    log_info "  ssh $DEPLOY_USER@$FROM_HOST \"ssh $DEPLOY_USER@$TO_HOST 'hostname'\""
}

# Main execution
main() {
    start_timer

    print_header "SSH Automation Setup"
    print_section "Configuring passwordless SSH: $FROM_HOST -> $TO_HOST"

    generate_ssh_key
    copy_ssh_key
    configure_ssh_client
    setup_ssh_agent
    test_ssh_connection
    display_connection_info

    end_timer "SSH setup"

    print_header "SSH Setup Complete"
    log_success "Passwordless SSH configured successfully"
    log_info ""
    log_info "You can now run commands on $TO_HOST from $FROM_HOST without passwords:"
    log_info "  ssh $DEPLOY_USER@$FROM_HOST \"ssh $DEPLOY_USER@$TO_HOST 'command'\""
}

main
