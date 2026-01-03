#!/usr/bin/env bash
# Auto-create stilgar user with sudo access (IDEMPOTENT - STANDALONE VERSION)
# This script safely creates the deployment user on any server
# NO EXTERNAL DEPENDENCIES - Can be copied and run anywhere
#
# Usage: ./setup-stilgar-user-standalone.sh [username]
#
# Example:
#   ./setup-stilgar-user-standalone.sh         # Creates 'stilgar' user
#   ./setup-stilgar-user-standalone.sh myuser  # Creates 'myuser' user

set -euo pipefail

# Configuration
DEPLOY_USER="${1:-stilgar}"

# Colors (embedded)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions (embedded)
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

print_section() {
    echo ""
    echo -e "${BLUE}▶${NC} $*"
    echo ""
}

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $*"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

# Check if script is run as root or with sudo
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    print_info "Usage: sudo $0 [username]"
    exit 1
fi

TIMER_START=$(date +%s)

print_header "Setting up deployment user: $DEPLOY_USER"

# Step 1: Check if user exists
print_info "Checking if user $DEPLOY_USER exists"
if id "$DEPLOY_USER" &>/dev/null; then
    print_success "User $DEPLOY_USER already exists"
    USER_EXISTS=true
else
    print_info "Creating user $DEPLOY_USER"
    useradd -m -s /bin/bash "$DEPLOY_USER"
    print_success "User $DEPLOY_USER created"
    USER_EXISTS=false
fi

# Step 2: Configure sudo access
print_info "Configuring sudo access for $DEPLOY_USER"

# Add to sudo group if not already
if groups "$DEPLOY_USER" | grep -q '\bsudo\b'; then
    print_success "User $DEPLOY_USER is already in sudo group"
else
    usermod -aG sudo "$DEPLOY_USER"
    print_success "Added $DEPLOY_USER to sudo group"
fi

# Configure NOPASSWD sudo
SUDOERS_FILE="/etc/sudoers.d/${DEPLOY_USER}-nopasswd"
if [[ -f "$SUDOERS_FILE" ]] && grep -q "NOPASSWD:ALL" "$SUDOERS_FILE" 2>/dev/null; then
    print_success "NOPASSWD sudo already configured"
else
    echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"

    # Validate sudoers file
    if visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        print_success "NOPASSWD sudo configured successfully"
    else
        print_error "Invalid sudoers configuration"
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
fi

# Step 3: Setup SSH directory
print_info "Setting up SSH directory for $DEPLOY_USER"
SSH_DIR="/home/${DEPLOY_USER}/.ssh"

if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "$SSH_DIR"
    print_success "SSH directory created"
else
    print_success "SSH directory already exists"
fi

# Ensure authorized_keys exists with correct permissions
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
if [[ ! -f "$AUTHORIZED_KEYS" ]]; then
    touch "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "$AUTHORIZED_KEYS"
fi

# Fix permissions if needed
chmod 700 "$SSH_DIR"
chmod 600 "$AUTHORIZED_KEYS" 2>/dev/null || true
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$SSH_DIR"
print_success "SSH directory configured"

# Step 4: Configure bash profile
print_info "Configuring bash profile for $DEPLOY_USER"
BASHRC="/home/${DEPLOY_USER}/.bashrc"

if [[ -f "$BASHRC" ]]; then
    if grep -q "CHOM Deployment User" "$BASHRC" 2>/dev/null; then
        print_success "Bash profile already configured"
    else
        cat >> "$BASHRC" << 'EOF'

# CHOM Deployment User Configuration
export PATH="$PATH:/usr/local/bin"
export EDITOR=nano
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
EOF
        print_success "Bash profile configured"
    fi
else
    print_warning "Bash profile not found, skipping"
fi

# Step 5: Set home directory permissions
print_info "Setting home directory permissions"
chmod 750 "/home/${DEPLOY_USER}"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}"
print_success "Home directory permissions set"

# Step 6: Display user information
print_section "User Information"
print_info "Username: $DEPLOY_USER"
print_info "UID: $(id -u $DEPLOY_USER)"
print_info "GID: $(id -g $DEPLOY_USER)"
print_info "Groups: $(groups $DEPLOY_USER | cut -d: -f2)"
print_info "Home: /home/${DEPLOY_USER}"
print_info "Shell: $(getent passwd $DEPLOY_USER | cut -d: -f7)"
print_info "Sudo: NOPASSWD enabled"

# Calculate duration
TIMER_END=$(date +%s)
DURATION=$((TIMER_END - TIMER_START))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
print_info "User setup completed in ${MINUTES}m ${SECONDS}s"

print_header "User Setup Complete"
print_success "User $DEPLOY_USER is ready for deployment operations"
echo ""
print_info "Next steps:"
print_info "  1. Add SSH public keys to /home/${DEPLOY_USER}/.ssh/authorized_keys"
print_info "  2. Or run ssh-copy-id to copy keys"
echo ""
print_info "Test sudo access:"
print_info "  sudo -u $DEPLOY_USER sudo whoami"
echo ""

exit 0
