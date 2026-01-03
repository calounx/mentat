#!/usr/bin/env bash
# Bootstrap SSH Access - Initial Setup Script
# Sets up SSH access between mentat and landsraad using current user
#
# This script must be run FIRST, before the automated deployment
# It sets up passwordless SSH so deployment can proceed
#
# Usage:
#   Run on mentat.arewel.com as current user (calounx):
#   ./deploy/scripts/bootstrap-ssh-access.sh landsraad.arewel.com
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        CHOM Bootstrap - SSH Access Setup                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

print_success() {
    echo -e "${GREEN}✓${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

print_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

# Check arguments
if [[ $# -lt 1 ]]; then
    print_error "Usage: $0 <remote-host>"
    echo ""
    echo "Example:"
    echo "  $0 landsraad.arewel.com"
    exit 1
fi

REMOTE_HOST="$1"
CURRENT_USER="$(whoami)"

print_header

echo "This script will set up passwordless SSH access from mentat to landsraad"
echo "using your current user account (${CURRENT_USER})."
echo ""
echo "Settings:"
echo "  Local host:  $(hostname)"
echo "  Remote host: ${REMOTE_HOST}"
echo "  User:        ${CURRENT_USER}"
echo ""

# Step 1: Check if SSH key exists
print_info "Step 1: Checking for SSH key..."
if [[ ! -f ~/.ssh/id_ed25519 ]] && [[ ! -f ~/.ssh/id_rsa ]]; then
    print_warning "No SSH key found. Generating ED25519 key..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${CURRENT_USER}@$(hostname)"
    print_success "SSH key generated: ~/.ssh/id_ed25519"
else
    if [[ -f ~/.ssh/id_ed25519 ]]; then
        print_success "ED25519 key already exists"
    elif [[ -f ~/.ssh/id_rsa ]]; then
        print_success "RSA key already exists"
    fi
fi
echo ""

# Step 2: Test if passwordless SSH already works
print_info "Step 2: Testing existing SSH access..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no "${CURRENT_USER}@${REMOTE_HOST}" "echo 'SSH OK'" &>/dev/null; then
    print_success "Passwordless SSH already configured!"
    echo ""
    print_info "You can now run the automated deployment:"
    echo "  sudo ./deploy/deploy-chom-automated.sh"
    exit 0
else
    print_warning "Passwordless SSH not configured yet"
fi
echo ""

# Step 3: Copy SSH key to remote host
print_info "Step 3: Setting up passwordless SSH to ${REMOTE_HOST}..."
echo ""
print_warning "You will be prompted for the password for ${CURRENT_USER}@${REMOTE_HOST}"
print_warning "This is the ONLY time you'll need to enter a password"
echo ""

if ssh-copy-id -i ~/.ssh/id_ed25519.pub "${CURRENT_USER}@${REMOTE_HOST}" 2>/dev/null || \
   ssh-copy-id -i ~/.ssh/id_rsa.pub "${CURRENT_USER}@${REMOTE_HOST}" 2>/dev/null; then
    print_success "SSH key copied to ${REMOTE_HOST}"
else
    print_error "Failed to copy SSH key"
    echo ""
    echo "Manual steps:"
    echo "  1. On ${REMOTE_HOST}, create .ssh directory:"
    echo "     mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    echo ""
    echo "  2. Copy your public key:"
    if [[ -f ~/.ssh/id_ed25519.pub ]]; then
        echo "     echo '$(cat ~/.ssh/id_ed25519.pub)' >> ~/.ssh/authorized_keys"
    elif [[ -f ~/.ssh/id_rsa.pub ]]; then
        echo "     echo '$(cat ~/.ssh/id_rsa.pub)' >> ~/.ssh/authorized_keys"
    fi
    echo ""
    echo "  3. Set correct permissions:"
    echo "     chmod 600 ~/.ssh/authorized_keys"
    exit 1
fi
echo ""

# Step 4: Test passwordless SSH
print_info "Step 4: Testing passwordless SSH..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "${CURRENT_USER}@${REMOTE_HOST}" "echo 'SSH OK'" &>/dev/null; then
    print_success "Passwordless SSH is working!"
else
    print_error "Passwordless SSH test failed"
    exit 1
fi
echo ""

# Step 5: Check sudo access on remote
print_info "Step 5: Checking sudo access on ${REMOTE_HOST}..."
if ssh "${CURRENT_USER}@${REMOTE_HOST}" "sudo -n true" &>/dev/null; then
    print_success "Passwordless sudo already configured on ${REMOTE_HOST}"
else
    print_warning "Passwordless sudo not configured on ${REMOTE_HOST}"
    echo ""
    echo "To enable passwordless sudo for ${CURRENT_USER} on ${REMOTE_HOST}:"
    echo ""
    echo "  1. SSH to ${REMOTE_HOST}:"
    echo "     ssh ${CURRENT_USER}@${REMOTE_HOST}"
    echo ""
    echo "  2. Edit sudoers file:"
    echo "     sudo visudo"
    echo ""
    echo "  3. Add this line at the end:"
    echo "     ${CURRENT_USER} ALL=(ALL) NOPASSWD:ALL"
    echo ""
    echo "  4. Save and exit (Ctrl+X, Y, Enter in nano)"
    echo ""
    read -p "Press Enter when passwordless sudo is configured..."
fi
echo ""

# Step 6: Verify sudo works
print_info "Step 6: Verifying sudo access..."
if ssh "${CURRENT_USER}@${REMOTE_HOST}" "sudo -n true" &>/dev/null; then
    print_success "Sudo access verified!"
else
    print_error "Passwordless sudo still not working"
    echo ""
    print_warning "The deployment will require sudo access."
    print_warning "Please configure passwordless sudo before proceeding."
    exit 1
fi
echo ""

# Success
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ SSH BOOTSTRAP COMPLETE                                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Run the automated deployment:"
echo "     cd ~/chom-deployment"
echo "     sudo ./deploy/deploy-chom-automated.sh"
echo ""
echo "  2. The deployment will now use passwordless SSH as ${CURRENT_USER}"
echo ""
