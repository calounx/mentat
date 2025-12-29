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

# Set a password for initial ssh-copy-id
log_info "Setting password for $USERNAME (needed for initial ssh-copy-id)"
passwd "$USERNAME"

echo ""
echo "${GREEN}✓ User $USERNAME configured successfully!${NC}"
echo ""
echo "${YELLOW}Next steps (from your control machine):${NC}"
echo ""

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}' || echo "<this-server-ip>")

echo "  ${CYAN}1. Copy your SSH key using ssh-copy-id:${NC}"
echo "     ssh-copy-id $USERNAME@$SERVER_IP"
echo ""
echo "  ${CYAN}2. Update inventory.yaml:${NC}"
echo "     ssh_user: $USERNAME"
echo ""
echo "  ${CYAN}3. Test SSH connection:${NC}"
echo "     ssh $USERNAME@$SERVER_IP"
echo ""
echo "  ${CYAN}4. Test sudo access:${NC}"
echo "     ssh $USERNAME@$SERVER_IP 'sudo whoami'"
echo ""

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
