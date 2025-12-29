#!/bin/bash
#===============================================================================
# Create Deployment User with Passwordless Sudo
#
# Usage: sudo ./create-deploy-user.sh [username]
#
# This script creates a dedicated user for CHOM deployment with:
# - Passwordless sudo access
# - SSH key authentication setup
# - Proper permissions
#===============================================================================

set -euo pipefail

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log_info() { echo "${BLUE}[INFO]${NC} $1"; }
log_success() { echo "${GREEN}[✓]${NC} $1"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo "${RED}[✗]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   echo "Usage: sudo $0 [username]"
   exit 1
fi

# Get username (default: deploy)
USERNAME="${1:-deploy}"

echo ""
echo "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo "${GREEN}  CHOM Deployment User Setup${NC}"
echo "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
log_info "Creating deployment user: $USERNAME"
echo ""

# Create user if doesn't exist
if id "$USERNAME" &>/dev/null; then
    log_warn "User $USERNAME already exists"
else
    useradd -m -s /bin/bash "$USERNAME"
    log_success "User $USERNAME created"
fi

# Add to sudo group
usermod -aG sudo "$USERNAME"
log_success "Added $USERNAME to sudo group"

# Configure passwordless sudo
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME"
chmod 0440 /etc/sudoers.d/"$USERNAME"
log_success "Configured passwordless sudo"

# Create .ssh directory
mkdir -p /home/"$USERNAME"/.ssh
chmod 700 /home/"$USERNAME"/.ssh
touch /home/"$USERNAME"/.ssh/authorized_keys
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh
log_success "Created .ssh directory with proper permissions"

# Test sudo
if sudo -u "$USERNAME" sudo -n true 2>/dev/null; then
    log_success "Passwordless sudo verified"
else
    log_error "Passwordless sudo verification failed"
    exit 1
fi

echo ""
echo "${GREEN}✓ User $USERNAME configured successfully!${NC}"
echo ""
echo "${YELLOW}Next steps:${NC}"
echo "  1. Add your SSH public key to: /home/$USERNAME/.ssh/authorized_keys"
echo "  2. Update inventory.yaml: ssh_user: $USERNAME"
echo "  3. Test SSH: ssh $USERNAME@<this-server-ip>"
echo "  4. Test sudo: ssh $USERNAME@<this-server-ip> 'sudo whoami'"
echo ""

# Offer to add SSH key interactively
read -p "Do you want to add an SSH public key now? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Paste your SSH public key (from ~/.ssh/id_rsa.pub on your control machine):"
    echo "Then press Enter twice when done."
    echo ""

    # Read multi-line input
    SSH_KEY=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        SSH_KEY+="$line"$'\n'
    done

    if [[ -n "$SSH_KEY" ]]; then
        echo "$SSH_KEY" >> /home/"$USERNAME"/.ssh/authorized_keys
        chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh/authorized_keys
        log_success "SSH key added!"
    else
        log_warn "No key entered"
    fi
fi

echo ""
echo "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo "${GREEN}  Setup Complete!${NC}"
echo "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "User details:"
echo "  Username: $USERNAME"
echo "  Home: /home/$USERNAME"
echo "  Shell: /bin/bash"
echo "  Sudo: Passwordless (configured)"
echo "  SSH keys: /home/$USERNAME/.ssh/authorized_keys"
echo ""
echo "Test the connection:"
echo "  ${BLUE}ssh $USERNAME@\$(hostname -I | awk '{print \$1}')${NC}"
echo "  ${BLUE}ssh $USERNAME@\$(hostname -I | awk '{print \$1}') 'sudo whoami'${NC}"
echo ""
