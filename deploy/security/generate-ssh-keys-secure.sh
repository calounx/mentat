#!/bin/bash
# ============================================================================
# Secure SSH Key Generation Script
# ============================================================================
# Purpose: Generate SSH keys with modern cryptography and secure practices
# Algorithm: ED25519 (primary), RSA 4096-bit (fallback)
# Security: Proper permissions, restricted key usage, audit logging
# Compliance: OWASP, NIST SP 800-57, FIPS 140-2
# ============================================================================
# SECURITY FEATURES:
# - ED25519 elliptic curve (equivalent to 4096-bit RSA)
# - RSA 4096-bit fallback for legacy systems
# - Proper file permissions (600 private, 644 public)
# - Optional key restrictions in authorized_keys
# - Key fingerprint verification
# - Comprehensive audit logging
# - Idempotent operation (safe to re-run)
# ============================================================================

set -euo pipefail
# Dependency validation - MUST run before doing anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local security_dir="${deploy_root}/security"
    if [[ ! -d "$security_dir" ]]; then
        errors+=("Security directory not found: $security_dir")
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
        echo "Run from repository root: sudo ./deploy/security/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
KEY_TYPE="${KEY_TYPE:-ed25519}"  # ed25519 or rsa
RSA_BITS="${RSA_BITS:-4096}"
KEY_COMMENT="${KEY_COMMENT:-chom-deployment-$(hostname)-$(date +%Y%m%d)}"
KEY_DIR="${KEY_DIR:-/home/$DEPLOY_USER/.ssh}"
KEY_NAME="${KEY_NAME:-chom_deployment_${KEY_TYPE}}"
BACKUP_DIR="/var/backups/chom/ssh-keys"
AUDIT_LOG="/var/log/chom-deployment/ssh-key-generation.log"

# Key restrictions for authorized_keys (optional)
ENABLE_KEY_RESTRICTIONS="${ENABLE_KEY_RESTRICTIONS:-true}"
ALLOWED_COMMANDS="${ALLOWED_COMMANDS:-}"  # Comma-separated list of allowed commands

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    local msg="[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG" 2>/dev/null || true
}

log_success() {
    local msg="[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG" 2>/dev/null || true
}

log_warning() {
    local msg="[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG" 2>/dev/null || true
}

log_error() {
    local msg="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create audit log directory
create_audit_directory() {
    mkdir -p "$(dirname "$AUDIT_LOG")"
    chmod 750 "$(dirname "$AUDIT_LOG")"

    if [[ ! -f "$AUDIT_LOG" ]]; then
        touch "$AUDIT_LOG"
        chmod 640 "$AUDIT_LOG"
    fi
}

# Verify user exists
verify_user_exists() {
    log_info "Verifying user $DEPLOY_USER exists..."

    if ! id "$DEPLOY_USER" &>/dev/null; then
        log_error "User $DEPLOY_USER does not exist"
        log_error "Create the user first: ./create-deployment-user.sh"
        exit 1
    fi

    log_success "User $DEPLOY_USER exists (UID: $(id -u "$DEPLOY_USER"))"
}

# Verify system requirements
verify_system_requirements() {
    log_info "Verifying system requirements..."

    # Check for ssh-keygen
    if ! command -v ssh-keygen &>/dev/null; then
        log_error "ssh-keygen not found. Please install openssh-client"
        exit 1
    fi

    # Check OpenSSH version for ED25519 support
    local ssh_version=$(ssh -V 2>&1 | grep -oP 'OpenSSH_\K[0-9.]+')
    log_info "OpenSSH version: $ssh_version"

    # ED25519 requires OpenSSH 6.5+ (released 2014)
    if [[ "$KEY_TYPE" == "ed25519" ]]; then
        local major_version=$(echo "$ssh_version" | cut -d. -f1)
        if [[ $major_version -lt 7 ]]; then
            log_warning "OpenSSH version < 7.0 may have limited ED25519 support"
            log_warning "Consider upgrading or using RSA keys: KEY_TYPE=rsa"
        fi
    fi

    log_success "System requirements verified"
}

# Create backup directory
create_backup_directory() {
    log_info "Creating backup directory..."

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    log_success "Backup directory: $BACKUP_DIR"
}

# Backup existing keys
backup_existing_keys() {
    local private_key="$KEY_DIR/$KEY_NAME"
    local public_key="$KEY_DIR/${KEY_NAME}.pub"

    if [[ -f "$private_key" ]] || [[ -f "$public_key" ]]; then
        log_warning "Existing keys found, creating backup..."

        local backup_timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$BACKUP_DIR/ssh_keys_${DEPLOY_USER}_${backup_timestamp}.tar.gz"

        # Create backup archive
        tar -czf "$backup_file" \
            -C "$KEY_DIR" \
            --ignore-failed-read \
            "$KEY_NAME" \
            "${KEY_NAME}.pub" \
            2>/dev/null || true

        if [[ -f "$backup_file" ]]; then
            chmod 600 "$backup_file"
            log_success "Backup created: $backup_file"
        fi
    else
        log_info "No existing keys to backup"
    fi
}

# Generate ED25519 SSH key
generate_ed25519_key() {
    log_info "Generating ED25519 SSH key..."

    local private_key="$KEY_DIR/$KEY_NAME"
    local public_key="$KEY_DIR/${KEY_NAME}.pub"

    # Check if key already exists
    if [[ -f "$private_key" ]]; then
        log_warning "Key already exists: $private_key"
        echo ""
        read -p "Overwrite existing key? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Keeping existing key"
            return 0
        fi
    fi

    # Generate ED25519 key
    # -t ed25519: Use ED25519 algorithm
    # -f: Output file
    # -N "": No passphrase (for automated deployments)
    # -C: Comment
    sudo -u "$DEPLOY_USER" ssh-keygen \
        -t ed25519 \
        -f "$private_key" \
        -N "" \
        -C "$KEY_COMMENT"

    if [[ -f "$private_key" ]]; then
        log_success "ED25519 key pair generated"
        log_info "Private key: $private_key"
        log_info "Public key: $public_key"

        # Log security event
        logger -t chom-security "ED25519 SSH key generated for user: $DEPLOY_USER"
    else
        log_error "Failed to generate ED25519 key"
        exit 1
    fi
}

# Generate RSA 4096-bit SSH key
generate_rsa_key() {
    log_info "Generating RSA $RSA_BITS-bit SSH key..."

    local private_key="$KEY_DIR/$KEY_NAME"
    local public_key="$KEY_DIR/${KEY_NAME}.pub"

    # Check if key already exists
    if [[ -f "$private_key" ]]; then
        log_warning "Key already exists: $private_key"
        echo ""
        read -p "Overwrite existing key? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Keeping existing key"
            return 0
        fi
    fi

    # Generate RSA key
    # -t rsa: Use RSA algorithm
    # -b: Key size in bits
    # -f: Output file
    # -N "": No passphrase (for automated deployments)
    # -C: Comment
    sudo -u "$DEPLOY_USER" ssh-keygen \
        -t rsa \
        -b "$RSA_BITS" \
        -f "$private_key" \
        -N "" \
        -C "$KEY_COMMENT"

    if [[ -f "$private_key" ]]; then
        log_success "RSA $RSA_BITS-bit key pair generated"
        log_info "Private key: $private_key"
        log_info "Public key: $public_key"

        # Log security event
        logger -t chom-security "RSA $RSA_BITS-bit SSH key generated for user: $DEPLOY_USER"
    else
        log_error "Failed to generate RSA key"
        exit 1
    fi
}

# Set proper permissions on SSH keys
set_key_permissions() {
    log_info "Setting secure permissions on SSH keys..."

    local private_key="$KEY_DIR/$KEY_NAME"
    local public_key="$KEY_DIR/${KEY_NAME}.pub"

    # Private key: 600 (rw-------)
    if [[ -f "$private_key" ]]; then
        chmod 600 "$private_key"
        chown "$DEPLOY_USER:$DEPLOY_USER" "$private_key"

        local actual_perms=$(stat -c '%a' "$private_key")
        if [[ "$actual_perms" == "600" ]]; then
            log_success "Private key permissions: 600 (rw-------)"
        else
            log_error "Failed to set private key permissions (actual: $actual_perms)"
            exit 1
        fi
    fi

    # Public key: 644 (rw-r--r--)
    if [[ -f "$public_key" ]]; then
        chmod 644 "$public_key"
        chown "$DEPLOY_USER:$DEPLOY_USER" "$public_key"

        local actual_perms=$(stat -c '%a' "$public_key")
        if [[ "$actual_perms" == "644" ]]; then
            log_success "Public key permissions: 644 (rw-r--r--)"
        else
            log_error "Failed to set public key permissions (actual: $actual_perms)"
            exit 1
        fi
    fi

    # Ensure .ssh directory has correct permissions
    chmod 700 "$KEY_DIR"
    chown "$DEPLOY_USER:$DEPLOY_USER" "$KEY_DIR"
}

# Add key to authorized_keys with restrictions
add_to_authorized_keys() {
    log_info "Adding public key to authorized_keys..."

    local public_key="$KEY_DIR/${KEY_NAME}.pub"
    local auth_keys="$KEY_DIR/authorized_keys"

    if [[ ! -f "$public_key" ]]; then
        log_error "Public key not found: $public_key"
        exit 1
    fi

    local pub_key_content=$(cat "$public_key")

    # Check if key already exists
    if [[ -f "$auth_keys" ]] && grep -qF "$pub_key_content" "$auth_keys"; then
        log_info "Public key already in authorized_keys"
        return 0
    fi

    # Create authorized_keys if it doesn't exist
    touch "$auth_keys"

    # Add key with optional restrictions
    if [[ "$ENABLE_KEY_RESTRICTIONS" == "true" ]]; then
        log_info "Adding key with restrictions..."

        # Build restrictions
        local restrictions=""

        # Restrict to specific commands (if provided)
        if [[ -n "$ALLOWED_COMMANDS" ]]; then
            restrictions="command=\"${ALLOWED_COMMANDS}\","
        fi

        # Add security restrictions
        # no-port-forwarding: Prevents SSH tunneling
        # no-X11-forwarding: Prevents X11 forwarding
        # no-agent-forwarding: Prevents SSH agent forwarding
        restrictions="${restrictions}no-port-forwarding,no-X11-forwarding,no-agent-forwarding"

        # Add restricted key to authorized_keys
        echo "${restrictions} ${pub_key_content}" >> "$auth_keys"

        log_success "Public key added with restrictions"
        log_info "Restrictions: $restrictions"
    else
        # Add key without restrictions
        echo "$pub_key_content" >> "$auth_keys"
        log_success "Public key added without restrictions"
    fi

    # Set proper permissions
    chmod 600 "$auth_keys"
    chown "$DEPLOY_USER:$DEPLOY_USER" "$auth_keys"

    log_success "authorized_keys updated: $auth_keys"
}

# Display key fingerprints
display_key_fingerprints() {
    log_info "Generating key fingerprints..."

    local private_key="$KEY_DIR/$KEY_NAME"
    local public_key="$KEY_DIR/${KEY_NAME}.pub"

    echo ""
    echo "=========================================="
    echo "SSH Key Fingerprints"
    echo "=========================================="
    echo ""

    # MD5 fingerprint (legacy compatibility)
    if [[ -f "$public_key" ]]; then
        echo "MD5 Fingerprint:"
        ssh-keygen -l -E md5 -f "$public_key"
        echo ""
    fi

    # SHA256 fingerprint (modern, default)
    if [[ -f "$public_key" ]]; then
        echo "SHA256 Fingerprint:"
        ssh-keygen -l -E sha256 -f "$public_key"
        echo ""
    fi

    # Visual fingerprint (randomart)
    if [[ -f "$public_key" ]]; then
        echo "Visual Fingerprint (Randomart):"
        ssh-keygen -lv -f "$public_key"
        echo ""
    fi
}

# Display public key
display_public_key() {
    local public_key="$KEY_DIR/${KEY_NAME}.pub"

    if [[ ! -f "$public_key" ]]; then
        log_error "Public key not found: $public_key"
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "SSH Public Key"
    echo "=========================================="
    echo ""
    echo "Copy this public key to remote servers:"
    echo ""
    cat "$public_key"
    echo ""
    echo "=========================================="
    echo ""
}

# Create client SSH config
create_client_ssh_config() {
    log_info "Creating SSH client configuration example..."

    local config_example="/tmp/chom_ssh_config_${DEPLOY_USER}.txt"
    local private_key="$KEY_DIR/$KEY_NAME"

    cat > "$config_example" <<EOF
# ============================================================================
# CHOM Deployment SSH Client Configuration
# ============================================================================
# Add this to your local ~/.ssh/config file
# ============================================================================

# Landsraad Server (Application)
Host landsraad
    HostName landsraad.arewel.com
    User $DEPLOY_USER
    Port 2222
    IdentityFile $private_key
    IdentitiesOnly yes
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes

# Mentat Server (Observability)
Host mentat
    HostName mentat.arewel.com
    User $DEPLOY_USER
    Port 2222
    IdentityFile $private_key
    IdentitiesOnly yes
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes

# Wildcard for all CHOM servers
Host chom-*
    User $DEPLOY_USER
    Port 2222
    IdentityFile $private_key
    IdentitiesOnly yes
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3

# Security defaults for all hosts
Host *
    HashKnownHosts yes
    PasswordAuthentication no
    ChallengeResponseAuthentication no
    PubkeyAuthentication yes
    ForwardAgent no
    ForwardX11 no
EOF

    chmod 644 "$config_example"

    log_success "SSH client configuration example: $config_example"
}

# Verify key generation
verify_key_generation() {
    log_info "Verifying SSH key generation..."

    local private_key="$KEY_DIR/$KEY_NAME"
    local public_key="$KEY_DIR/${KEY_NAME}.pub"
    local errors=0

    # Check private key exists
    if [[ ! -f "$private_key" ]]; then
        log_error "Private key not found: $private_key"
        ((errors++))
    fi

    # Check public key exists
    if [[ ! -f "$public_key" ]]; then
        log_error "Public key not found: $public_key"
        ((errors++))
    fi

    # Check private key permissions
    if [[ -f "$private_key" ]]; then
        local private_perms=$(stat -c '%a' "$private_key")
        if [[ "$private_perms" != "600" ]]; then
            log_error "Private key permissions incorrect (expected: 600, actual: $private_perms)"
            ((errors++))
        fi
    fi

    # Check public key permissions
    if [[ -f "$public_key" ]]; then
        local public_perms=$(stat -c '%a' "$public_key")
        if [[ "$public_perms" != "644" ]]; then
            log_error "Public key permissions incorrect (expected: 644, actual: $public_perms)"
            ((errors++))
        fi
    fi

    # Verify key ownership
    if [[ -f "$private_key" ]]; then
        local key_owner=$(stat -c '%U' "$private_key")
        if [[ "$key_owner" != "$DEPLOY_USER" ]]; then
            log_error "Private key owner incorrect (expected: $DEPLOY_USER, actual: $key_owner)"
            ((errors++))
        fi
    fi

    # Test key validity
    if [[ -f "$private_key" ]]; then
        if ! ssh-keygen -l -f "$private_key" &>/dev/null; then
            log_error "Private key validation failed"
            ((errors++))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "All verification checks passed"
        return 0
    else
        log_error "$errors verification check(s) failed"
        return 1
    fi
}

# Display security summary
display_security_summary() {
    echo ""
    log_success "=========================================="
    log_success "SSH Key Generation Complete"
    log_success "=========================================="
    echo ""

    log_info "Key Configuration:"
    echo "  Algorithm: $KEY_TYPE"
    if [[ "$KEY_TYPE" == "rsa" ]]; then
        echo "  Key Size: $RSA_BITS bits"
    else
        echo "  Security Level: Equivalent to RSA 4096-bit"
    fi
    echo "  Comment: $KEY_COMMENT"
    echo ""

    log_info "Key Files:"
    echo "  Private Key: $KEY_DIR/$KEY_NAME (600)"
    echo "  Public Key: $KEY_DIR/${KEY_NAME}.pub (644)"
    echo "  Authorized Keys: $KEY_DIR/authorized_keys (600)"
    echo ""

    log_info "Security Settings:"
    echo "  ✓ Private key permissions: 600 (rw-------)"
    echo "  ✓ Public key permissions: 644 (rw-r--r--)"
    echo "  ✓ SSH directory permissions: 700 (rwx------)"
    echo "  ✓ Key owner: $DEPLOY_USER"
    if [[ "$ENABLE_KEY_RESTRICTIONS" == "true" ]]; then
        echo "  ✓ Key restrictions enabled"
    fi
    echo ""

    log_info "Backups:"
    echo "  Backup directory: $BACKUP_DIR"
    echo ""

    log_info "Audit Logging:"
    echo "  SSH key generation: $AUDIT_LOG"
    echo "  System events: journalctl -t chom-security"
    echo ""

    log_warning "NEXT STEPS:"
    echo "  1. Copy public key to remote servers:"
    echo "     cat $KEY_DIR/${KEY_NAME}.pub | ssh root@<server> 'cat >> /home/$DEPLOY_USER/.ssh/authorized_keys'"
    echo ""
    echo "  2. Test SSH connection:"
    echo "     ssh -i $KEY_DIR/$KEY_NAME -p 2222 $DEPLOY_USER@<server>"
    echo ""
    echo "  3. Add to local SSH config:"
    echo "     cat /tmp/chom_ssh_config_${DEPLOY_USER}.txt >> ~/.ssh/config"
    echo ""
    echo "  4. Test connection with alias:"
    echo "     ssh landsraad"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  • Keep private key secure and never share it"
    echo "  • Backup private key to secure, encrypted storage"
    echo "  • Use SSH agent for key management: ssh-add $KEY_DIR/$KEY_NAME"
    echo "  • Verify fingerprint on first connection"
    echo "  • Rotate keys every 90 days for security"
    echo "  • Monitor audit logs for unauthorized key usage"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "=============================================="
    log_info "CHOM Secure SSH Key Generation"
    log_info "=============================================="
    echo ""

    check_root
    create_audit_directory
    verify_user_exists
    verify_system_requirements
    create_backup_directory
    backup_existing_keys

    # Generate key based on type
    case "$KEY_TYPE" in
        ed25519)
            generate_ed25519_key
            ;;
        rsa)
            generate_rsa_key
            ;;
        *)
            log_error "Unsupported key type: $KEY_TYPE"
            log_error "Supported types: ed25519, rsa"
            exit 1
            ;;
    esac

    set_key_permissions
    add_to_authorized_keys
    display_key_fingerprints
    display_public_key
    create_client_ssh_config

    if verify_key_generation; then
        display_security_summary
        log_success "SSH key generation completed successfully!"

        # Log final success
        logger -t chom-security "SSH key pair generated for user: $DEPLOY_USER (type: $KEY_TYPE)"

        exit 0
    else
        log_error "Key generation verification failed"
        log_error "Please review the errors above and re-run the script"
        exit 1
    fi
}

# Run main function
main "$@"
