#!/usr/bin/env bash
# Auto-create stilgar user with sudo access (IDEMPOTENT)
# This script safely creates the deployment user on any server
# Usage: ./setup-stilgar-user.sh [--remote-host hostname]
#
# Can be run:
# - Locally: ./setup-stilgar-user.sh
# - Remotely: ./setup-stilgar-user.sh --remote-host landsraad.arewel.com

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
REMOTE_HOST=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote-host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --user)
            DEPLOY_USER="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--remote-host hostname] [--user username]"
            exit 1
            ;;
    esac
done

# Check if running remotely
if [[ -n "$REMOTE_HOST" ]]; then
    log_info "Running script on remote host: $REMOTE_HOST"

    # Copy this script to remote and execute
    ssh root@"$REMOTE_HOST" 'bash -s' < "$0"
    exit $?
fi

init_deployment_log "setup-stilgar-user-$(date +%Y%m%d_%H%M%S)"
log_section "Setting up deployment user: $DEPLOY_USER"

# Create user if doesn't exist
create_user() {
    log_step "Checking if user $DEPLOY_USER exists"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_success "User $DEPLOY_USER already exists"

        # Verify user has home directory
        if [[ ! -d "/home/${DEPLOY_USER}" ]]; then
            log_warning "Home directory missing, creating it"
            sudo mkhomedir_helper "$DEPLOY_USER" || sudo mkdir -p "/home/${DEPLOY_USER}"
            sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}"
        fi
    else
        log_info "Creating user $DEPLOY_USER"

        # Create user with home directory and bash shell
        sudo useradd -m -s /bin/bash "$DEPLOY_USER"

        log_success "User $DEPLOY_USER created"
    fi
}

# Add user to sudo group with NOPASSWD
configure_sudo() {
    log_step "Configuring sudo access for $DEPLOY_USER"

    # Add to sudo group
    if groups "$DEPLOY_USER" | grep -q '\bsudo\b'; then
        log_success "User $DEPLOY_USER is already in sudo group"
    else
        log_info "Adding $DEPLOY_USER to sudo group"
        sudo usermod -aG sudo "$DEPLOY_USER"
        log_success "Added to sudo group"
    fi

    # Configure NOPASSWD sudo
    local sudoers_file="/etc/sudoers.d/${DEPLOY_USER}"
    local sudoers_content="${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL"

    if [[ -f "$sudoers_file" ]] && grep -q "^${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" "$sudoers_file"; then
        log_success "NOPASSWD sudo already configured"
    else
        log_info "Configuring NOPASSWD sudo"

        # Create sudoers file
        echo "$sudoers_content" | sudo tee "$sudoers_file" > /dev/null
        sudo chmod 0440 "$sudoers_file"

        # Validate sudoers file
        if sudo visudo -c -f "$sudoers_file" &>/dev/null; then
            log_success "NOPASSWD sudo configured successfully"
        else
            log_error "Sudoers file validation failed"
            sudo rm -f "$sudoers_file"
            return 1
        fi
    fi
}

# Setup SSH directory with proper permissions
setup_ssh_directory() {
    log_step "Setting up SSH directory for $DEPLOY_USER"

    local ssh_dir="/home/${DEPLOY_USER}/.ssh"

    if [[ -d "$ssh_dir" ]]; then
        log_success "SSH directory already exists"
    else
        log_info "Creating SSH directory"
        sudo mkdir -p "$ssh_dir"
    fi

    # Set proper ownership and permissions
    sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$ssh_dir"
    sudo chmod 700 "$ssh_dir"

    # Create authorized_keys if it doesn't exist
    local authorized_keys="${ssh_dir}/authorized_keys"
    if [[ ! -f "$authorized_keys" ]]; then
        sudo touch "$authorized_keys"
        sudo chown "${DEPLOY_USER}:${DEPLOY_USER}" "$authorized_keys"
        sudo chmod 600 "$authorized_keys"
    fi

    log_success "SSH directory configured"
}

# Configure bash profile
configure_bash_profile() {
    log_step "Configuring bash profile for $DEPLOY_USER"

    local bashrc="/home/${DEPLOY_USER}/.bashrc"

    # Add deployment-specific configuration if not already present
    if [[ -f "$bashrc" ]] && grep -q "# CHOM Deployment Configuration" "$bashrc"; then
        log_success "Bash profile already configured"
    else
        log_info "Adding deployment configuration to .bashrc"

        sudo tee -a "$bashrc" > /dev/null <<'EOF'

# CHOM Deployment Configuration
export DEPLOY_USER="${USER}"
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

# Deployment aliases
alias deploy-status='systemctl status chom-worker:* nginx php*-fpm postgresql redis-server'
alias deploy-logs='tail -f /var/log/chom-deploy/deployment.log'
alias app-logs='tail -f /var/www/chom/shared/storage/logs/laravel.log'

# Load deployment utilities if available
if [[ -f /var/www/chom/deploy/utils/logging.sh ]]; then
    source /var/www/chom/deploy/utils/logging.sh
fi
EOF

        sudo chown "${DEPLOY_USER}:${DEPLOY_USER}" "$bashrc"
        log_success "Bash profile configured"
    fi
}

# Set proper home directory permissions
set_home_permissions() {
    log_step "Setting home directory permissions"

    sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}"
    sudo chmod 755 "/home/${DEPLOY_USER}"

    log_success "Home directory permissions set"
}

# Display user information
display_user_info() {
    log_section "User Information"

    log_info "Username: $DEPLOY_USER"
    log_info "UID: $(id -u "$DEPLOY_USER")"
    log_info "GID: $(id -g "$DEPLOY_USER")"
    log_info "Groups: $(groups "$DEPLOY_USER" | cut -d: -f2)"
    log_info "Home: /home/${DEPLOY_USER}"
    log_info "Shell: $(getent passwd "$DEPLOY_USER" | cut -d: -f7)"
    log_info "Sudo: NOPASSWD enabled"
}

# Main execution
main() {
    start_timer

    print_header "Setting up deployment user: $DEPLOY_USER"

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_fatal "This script must be run as root or with sudo privileges"
    fi

    create_user
    configure_sudo
    setup_ssh_directory
    configure_bash_profile
    set_home_permissions
    display_user_info

    end_timer "User setup"

    print_header "User Setup Complete"
    log_success "User $DEPLOY_USER is ready for deployment operations"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run setup-ssh-automation.sh to configure SSH keys"
    log_info "  2. Or manually add SSH public keys to /home/${DEPLOY_USER}/.ssh/authorized_keys"
    log_info ""
    log_info "Test sudo access:"
    log_info "  sudo -u $DEPLOY_USER sudo whoami"
}

main
