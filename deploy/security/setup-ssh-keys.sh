#!/bin/bash
# ============================================================================
# SSH Key Setup and Hardening Script
# ============================================================================
# Purpose: Generate and configure SSH key-based authentication with hardening
# Target: landsraad.arewel.com and mentat.arewel.com
# User: stilgar
# Security: SSH key-only auth, disable password authentication, custom port
# ============================================================================

set -euo pipefail

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY_TYPE="ed25519"
SSH_KEY_BITS=""  # ED25519 has fixed length
SSH_KEY_PATH="${HOME}/.ssh/chom_deployment_${SSH_KEY_TYPE}"
SSH_CONFIG_PATH="/etc/ssh/sshd_config"
BACKUP_DIR="/var/backups/ssh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Backup existing SSH configuration
backup_ssh_config() {
    log_info "Backing up SSH configuration..."

    mkdir -p "$BACKUP_DIR"

    if [[ -f "$SSH_CONFIG_PATH" ]]; then
        cp "$SSH_CONFIG_PATH" "$BACKUP_DIR/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
        log_success "SSH configuration backed up"
    fi

    if [[ -d "/home/$DEPLOY_USER/.ssh" ]]; then
        tar -czf "$BACKUP_DIR/ssh_user_backup.$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C "/home/$DEPLOY_USER" .ssh 2>/dev/null || true
        log_success "User SSH directory backed up"
    fi
}

# Generate SSH key pair
generate_ssh_key() {
    log_info "Generating SSH key pair for $DEPLOY_USER..."

    # Create .ssh directory for deploy user
    mkdir -p "/home/$DEPLOY_USER/.ssh"
    chmod 700 "/home/$DEPLOY_USER/.ssh"

    # Generate SSH key
    if [[ -f "$SSH_KEY_PATH" ]]; then
        log_warning "SSH key already exists at $SSH_KEY_PATH"
        read -p "Overwrite existing key? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Keeping existing key"
            return 0
        fi
    fi

    # Generate ED25519 key (recommended)
    sudo -u "$DEPLOY_USER" ssh-keygen \
        -t "$SSH_KEY_TYPE" \
        -f "$SSH_KEY_PATH" \
        -N "" \
        -C "chom-deployment-${DEPLOY_USER}@$(hostname)-$(date +%Y%m%d)"

    log_success "SSH key pair generated"
    log_info "Public key location: ${SSH_KEY_PATH}.pub"
    log_info "Private key location: ${SSH_KEY_PATH}"

    # Display public key
    echo ""
    log_info "Public key content (copy this to remote servers):"
    echo "========================================================================"
    cat "${SSH_KEY_PATH}.pub"
    echo "========================================================================"
    echo ""
}

# Configure SSH authorized_keys
configure_authorized_keys() {
    log_info "Configuring authorized_keys for $DEPLOY_USER..."

    local auth_keys_path="/home/$DEPLOY_USER/.ssh/authorized_keys"

    # Create or update authorized_keys
    touch "$auth_keys_path"
    chmod 600 "$auth_keys_path"

    # Add public key if not already present
    if [[ -f "${SSH_KEY_PATH}.pub" ]]; then
        local pub_key=$(cat "${SSH_KEY_PATH}.pub")
        if ! grep -q "$pub_key" "$auth_keys_path" 2>/dev/null; then
            cat "${SSH_KEY_PATH}.pub" >> "$auth_keys_path"
            log_success "Public key added to authorized_keys"
        else
            log_info "Public key already in authorized_keys"
        fi
    fi

    # Set correct ownership
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"

    log_success "Authorized keys configured"
}

# Harden SSH configuration
harden_ssh_config() {
    log_info "Hardening SSH configuration..."

    # Backup current config
    cp "$SSH_CONFIG_PATH" "${SSH_CONFIG_PATH}.pre-hardening"

    # Create hardened SSH configuration
    cat > "$SSH_CONFIG_PATH" <<EOF
# ============================================================================
# CHOM Hardened SSH Configuration
# Generated: $(date)
# ============================================================================

# Port Configuration
Port $SSH_PORT

# Authentication Methods
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

# Root Access
PermitRootLogin no

# Host-based Authentication
HostbasedAuthentication no
IgnoreRhosts yes

# Login Grace Time and Retries
LoginGraceTime 30s
MaxAuthTries 3
MaxSessions 10

# Client Alive Interval (prevents timeout)
ClientAliveInterval 300
ClientAliveCountMax 2

# X11 and Forwarding
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding yes
PermitTunnel no

# Banner and Messages
PrintMotd no
PrintLastLog yes
Banner none

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Strict Mode
StrictModes yes

# Public Key Directory
AuthorizedKeysFile .ssh/authorized_keys

# Key Exchange Algorithms (Strong Cryptography)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256

# Host Key Algorithms
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# Ciphers (AES-GCM preferred)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# MAC Algorithms
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# User/Group Restrictions
AllowUsers $DEPLOY_USER
# AllowGroups ssh-users

# Additional Security
DebianBanner no
PermitUserEnvironment no
Compression delayed
UseDNS no

# Session Timeout
TCPKeepAlive yes
EOF

    log_success "SSH configuration hardened"
}

# Test SSH configuration
test_ssh_config() {
    log_info "Testing SSH configuration..."

    if sshd -t -f "$SSH_CONFIG_PATH"; then
        log_success "SSH configuration is valid"
        return 0
    else
        log_error "SSH configuration is invalid"
        log_warning "Restoring previous configuration..."
        cp "${SSH_CONFIG_PATH}.pre-hardening" "$SSH_CONFIG_PATH"
        return 1
    fi
}

# Update firewall for new SSH port
update_firewall() {
    log_info "Updating firewall for SSH port $SSH_PORT..."

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        log_warning "UFW not installed, skipping firewall update"
        return 0
    fi

    # Allow new SSH port
    ufw allow "$SSH_PORT/tcp" comment "SSH hardened port"

    log_success "Firewall updated for port $SSH_PORT"
}

# Test SSH connection before disabling password auth
test_ssh_connection() {
    log_warning "CRITICAL: Test SSH connection before logging out!"
    echo ""
    log_info "Test connection from another terminal:"
    echo "  ssh -p $SSH_PORT -i ${SSH_KEY_PATH} ${DEPLOY_USER}@$(hostname -I | awk '{print $1}')"
    echo ""
    log_info "If connection works, press ENTER to restart SSH service"
    log_warning "If connection fails, press Ctrl+C to abort and fix issues"
    echo ""
    read -p "Press ENTER to continue or Ctrl+C to abort: "
}

# Restart SSH service
restart_ssh() {
    log_info "Restarting SSH service..."

    systemctl restart ssh || systemctl restart sshd

    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        log_success "SSH service restarted successfully"
    else
        log_error "SSH service failed to restart"
        log_warning "Restoring previous configuration..."
        cp "${SSH_CONFIG_PATH}.pre-hardening" "$SSH_CONFIG_PATH"
        systemctl restart ssh || systemctl restart sshd
        return 1
    fi
}

# Generate SSH config file for client
generate_client_config() {
    log_info "Generating SSH client configuration..."

    local client_config="/tmp/ssh_client_config.txt"

    cat > "$client_config" <<EOF
# ============================================================================
# SSH Client Configuration for CHOM Deployment
# ============================================================================
# Add this to your local ~/.ssh/config file
# ============================================================================

Host landsraad
    HostName landsraad.arewel.com
    User $DEPLOY_USER
    Port $SSH_PORT
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host mentat
    HostName mentat.arewel.com
    User $DEPLOY_USER
    Port $SSH_PORT
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3

# Shorthand for both servers
Host chom-*
    User $DEPLOY_USER
    Port $SSH_PORT
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking ask
    ServerAliveInterval 60

# Security defaults
Host *
    HashKnownHosts yes
    IdentitiesOnly yes
    PasswordAuthentication no
EOF

    log_success "Client configuration written to $client_config"
    cat "$client_config"
}

# Display security summary
display_security_summary() {
    echo ""
    log_success "=========================================="
    log_success "SSH Security Configuration Complete"
    log_success "=========================================="
    echo ""
    log_info "Security Measures Applied:"
    echo "  ✓ SSH key-based authentication enabled"
    echo "  ✓ Password authentication disabled"
    echo "  ✓ Root login disabled"
    echo "  ✓ SSH port changed to $SSH_PORT"
    echo "  ✓ Strong cryptographic algorithms enforced"
    echo "  ✓ Login attempts limited to 3"
    echo "  ✓ Session timeouts configured"
    echo "  ✓ X11 forwarding disabled"
    echo ""
    log_warning "IMPORTANT SECURITY REMINDERS:"
    echo "  1. Keep your private key secure (${SSH_KEY_PATH})"
    echo "  2. Never share your private key"
    echo "  3. Test SSH connection before logging out"
    echo "  4. Keep a backup access method available"
    echo "  5. Update firewall rules for port $SSH_PORT"
    echo ""
    log_info "Connection command:"
    echo "  ssh -p $SSH_PORT -i ${SSH_KEY_PATH} ${DEPLOY_USER}@<server>"
    echo ""
    log_info "Configuration backups stored in: $BACKUP_DIR"
    echo ""
}

# Remove old SSH port from firewall
cleanup_old_ssh_port() {
    log_info "Cleaning up old SSH port from firewall..."

    if command -v ufw &> /dev/null; then
        # Remove default SSH port if different from new port
        if [[ "$SSH_PORT" != "22" ]]; then
            ufw delete allow 22/tcp 2>/dev/null || true
            log_success "Removed old SSH port 22 from firewall"
        fi
    fi
}

# Create deploy user if not exists
create_deploy_user() {
    log_info "Checking deploy user $DEPLOY_USER..."

    if id "$DEPLOY_USER" &>/dev/null; then
        log_info "User $DEPLOY_USER already exists"
    else
        log_info "Creating user $DEPLOY_USER..."
        useradd -m -s /bin/bash "$DEPLOY_USER"
        usermod -aG sudo "$DEPLOY_USER"
        log_success "User $DEPLOY_USER created"
    fi
}

# Main execution
main() {
    log_info "Starting SSH security hardening..."
    echo ""

    check_root
    create_deploy_user
    backup_ssh_config
    generate_ssh_key
    configure_authorized_keys
    harden_ssh_config

    if ! test_ssh_config; then
        log_error "SSH configuration test failed, aborting"
        exit 1
    fi

    update_firewall
    test_ssh_connection
    restart_ssh
    cleanup_old_ssh_port
    generate_client_config
    display_security_summary

    log_success "SSH hardening complete!"
}

# Run main function
main "$@"
