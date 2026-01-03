#!/bin/bash
# ============================================================================
# Secure Deployment User Creation Script
# ============================================================================
# Purpose: Create stilgar deployment user with minimal privileges
# Security: Principle of least privilege, SSH key-only auth, strong umask
# Compliance: OWASP, PCI DSS 7.1, SOC 2, CIS Benchmark
# ============================================================================
# SECURITY FEATURES:
# - Minimal privileges initially (no sudo by default)
# - SSH key-only authentication (password disabled)
# - Strong umask (0027) - group read, no world access
# - Locked password with `passwd -l`
# - Home directory permissions: 750
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
DEPLOY_GROUP="${DEPLOY_GROUP:-stilgar}"
DEPLOY_COMMENT="CHOM Deployment User - SSH Key Only"
DEPLOY_SHELL="/bin/bash"
DEPLOY_HOME_MODE="750"
DEPLOY_UMASK="0027"
AUDIT_LOG="/var/log/chom-deployment/user-creation.log"

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
    echo "$msg" >> "$AUDIT_LOG"
}

log_success() {
    local msg="[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG"
}

log_warning() {
    local msg="[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG"
}

log_error() {
    local msg="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$AUDIT_LOG"
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
    log_info "Creating audit log directory..."

    mkdir -p "$(dirname "$AUDIT_LOG")"
    chmod 750 "$(dirname "$AUDIT_LOG")"

    # Initialize log file
    if [[ ! -f "$AUDIT_LOG" ]]; then
        touch "$AUDIT_LOG"
        chmod 640 "$AUDIT_LOG"
        log_success "Audit log created: $AUDIT_LOG"
    fi
}

# Verify system requirements
verify_system_requirements() {
    log_info "Verifying system requirements..."

    # Check for required commands
    local required_commands=("useradd" "usermod" "passwd" "groupadd" "chown" "chmod")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        exit 1
    fi

    log_success "System requirements verified"
}

# Check if user already exists
check_existing_user() {
    log_info "Checking for existing user: $DEPLOY_USER"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_warning "User $DEPLOY_USER already exists"

        echo ""
        read -p "Do you want to reconfigure this user? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Skipping user creation, proceeding with configuration..."
            return 1
        fi
        log_info "Proceeding with user reconfiguration..."
        return 0
    fi

    log_info "User does not exist, will create new user"
    return 0
}

# Create deployment group
create_deployment_group() {
    log_info "Creating deployment group: $DEPLOY_GROUP"

    if getent group "$DEPLOY_GROUP" &>/dev/null; then
        log_info "Group $DEPLOY_GROUP already exists"
    else
        groupadd "$DEPLOY_GROUP"
        log_success "Group $DEPLOY_GROUP created (GID: $(getent group "$DEPLOY_GROUP" | cut -d: -f3))"
    fi
}

# Create deployment user with minimal privileges
create_deployment_user() {
    log_info "Creating deployment user: $DEPLOY_USER"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_info "User $DEPLOY_USER already exists, skipping creation"
    else
        # Create user with:
        # -m: create home directory
        # -s: set shell
        # -c: comment/description
        # -g: primary group
        # -G: additional groups (none initially - minimal privileges)
        useradd -m \
            -s "$DEPLOY_SHELL" \
            -c "$DEPLOY_COMMENT" \
            -g "$DEPLOY_GROUP" \
            "$DEPLOY_USER"

        local uid=$(id -u "$DEPLOY_USER")
        local gid=$(id -g "$DEPLOY_USER")

        log_success "User $DEPLOY_USER created (UID: $uid, GID: $gid)"

        # Log to system audit
        logger -t chom-security "Deployment user created: $DEPLOY_USER (UID: $uid)"
    fi
}

# Lock password and disable password authentication
lock_user_password() {
    log_info "Locking password for $DEPLOY_USER (SSH key-only authentication)..."

    # Set a strong random password first (will be locked)
    local random_password=$(openssl rand -base64 48)
    echo "$DEPLOY_USER:$random_password" | chpasswd

    # Lock the password to prevent password-based login
    passwd -l "$DEPLOY_USER" &>/dev/null

    # Verify password is locked
    local passwd_status=$(passwd -S "$DEPLOY_USER" | awk '{print $2}')
    if [[ "$passwd_status" == "L" ]]; then
        log_success "Password locked - SSH key authentication only"
    else
        log_error "Failed to lock password"
        exit 1
    fi

    # Expire password immediately to prevent any password-based login
    passwd -e "$DEPLOY_USER" &>/dev/null

    log_success "Password authentication disabled for $DEPLOY_USER"

    # Log security action
    logger -t chom-security "Password locked for user: $DEPLOY_USER"
}

# Configure home directory with secure permissions
configure_home_directory() {
    log_info "Configuring home directory for $DEPLOY_USER..."

    local home_dir="/home/$DEPLOY_USER"

    # Set secure permissions on home directory (750 = rwxr-x---)
    # Owner: read, write, execute
    # Group: read, execute
    # Others: no access
    chmod "$DEPLOY_HOME_MODE" "$home_dir"

    # Ensure ownership is correct
    chown "$DEPLOY_USER:$DEPLOY_GROUP" "$home_dir"

    # Verify permissions
    local actual_perms=$(stat -c '%a' "$home_dir")
    if [[ "$actual_perms" == "$DEPLOY_HOME_MODE" ]]; then
        log_success "Home directory permissions set to $DEPLOY_HOME_MODE"
    else
        log_error "Failed to set home directory permissions (expected: $DEPLOY_HOME_MODE, actual: $actual_perms)"
        exit 1
    fi

    log_info "Home directory: $home_dir (permissions: $DEPLOY_HOME_MODE)"
}

# Configure strong umask for user
configure_user_umask() {
    log_info "Configuring strong umask ($DEPLOY_UMASK) for $DEPLOY_USER..."

    local bashrc="/home/$DEPLOY_USER/.bashrc"
    local profile="/home/$DEPLOY_USER/.profile"

    # Add umask to .bashrc
    if [[ -f "$bashrc" ]]; then
        if ! grep -q "umask $DEPLOY_UMASK" "$bashrc"; then
            cat >> "$bashrc" <<EOF

# CHOM Security: Strong umask for deployment user
# umask $DEPLOY_UMASK = files: 640 (rw-r-----), directories: 750 (rwxr-x---)
umask $DEPLOY_UMASK
EOF
            log_success "Umask $DEPLOY_UMASK added to .bashrc"
        else
            log_info "Umask already configured in .bashrc"
        fi
    fi

    # Add umask to .profile
    if [[ -f "$profile" ]]; then
        if ! grep -q "umask $DEPLOY_UMASK" "$profile"; then
            cat >> "$profile" <<EOF

# CHOM Security: Strong umask for deployment user
umask $DEPLOY_UMASK
EOF
            log_success "Umask $DEPLOY_UMASK added to .profile"
        else
            log_info "Umask already configured in .profile"
        fi
    fi

    # Set ownership
    chown "$DEPLOY_USER:$DEPLOY_GROUP" "$bashrc" "$profile" 2>/dev/null || true

    log_success "Strong umask configured (files: 640, directories: 750)"
}

# Create .ssh directory with secure permissions
create_ssh_directory() {
    log_info "Creating SSH directory for $DEPLOY_USER..."

    local ssh_dir="/home/$DEPLOY_USER/.ssh"

    # Create .ssh directory
    mkdir -p "$ssh_dir"

    # Set strict permissions (700 = rwx------)
    chmod 700 "$ssh_dir"

    # Set ownership
    chown "$DEPLOY_USER:$DEPLOY_GROUP" "$ssh_dir"

    # Create authorized_keys file
    local auth_keys="$ssh_dir/authorized_keys"
    if [[ ! -f "$auth_keys" ]]; then
        touch "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$DEPLOY_USER:$DEPLOY_GROUP" "$auth_keys"
        log_success "Created authorized_keys file: $auth_keys"
    else
        log_info "authorized_keys file already exists"
    fi

    log_success "SSH directory configured: $ssh_dir (permissions: 700)"
    log_info "Add SSH public keys to: $auth_keys"
}

# Configure minimal sudo access (optional, commented by default)
configure_minimal_sudo() {
    log_info "Configuring minimal sudo access (optional, initially disabled)..."

    local sudoers_file="/etc/sudoers.d/${DEPLOY_USER}"

    # Create sudoers file with all commands commented out by default
    cat > "$sudoers_file" <<EOF
# ============================================================================
# CHOM Deployment User Sudo Configuration
# ============================================================================
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# User: $DEPLOY_USER
# Policy: Principle of Least Privilege
# ============================================================================
#
# SECURITY NOTE: By default, all sudo commands are DISABLED (commented out)
# Uncomment only the specific commands needed for deployment operations
# ============================================================================

# Service Management (NOPASSWD - required for automated deployments)
# Uncomment to allow service restarts without password
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart nginx
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl reload nginx
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart php*-fpm
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart redis-server
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl status *

# Laravel/Composer Commands (NOPASSWD - deployment automation)
# Uncomment to allow Laravel artisan and Composer commands
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/php /var/www/chom/artisan *
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/composer install --working-dir=/var/www/chom
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/composer update --working-dir=/var/www/chom

# File Ownership (NOPASSWD - deployment automation)
# Uncomment to allow changing ownership of application files
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chown -R www-data\:www-data /var/www/chom/storage
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chown -R www-data\:www-data /var/www/chom/bootstrap/cache
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chmod -R 775 /var/www/chom/storage
# ${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chmod -R 775 /var/www/chom/bootstrap/cache

# Deny Dangerous Commands (ALWAYS ENFORCED)
${DEPLOY_USER} ALL=!/bin/rm -rf /, !/bin/dd, !/sbin/reboot, !/sbin/shutdown, !/sbin/poweroff, !/sbin/halt

# Audit Logging (ALWAYS ENFORCED)
Defaults:${DEPLOY_USER} log_input, log_output
Defaults:${DEPLOY_USER} logfile="/var/log/sudo/${DEPLOY_USER}.log"

# Security Settings
Defaults:${DEPLOY_USER} !visiblepw
Defaults:${DEPLOY_USER} always_set_home
Defaults:${DEPLOY_USER} secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

    chmod 440 "$sudoers_file"

    # Create sudo log directory
    mkdir -p "/var/log/sudo"
    chmod 750 "/var/log/sudo"

    # Verify sudoers file syntax
    if visudo -c -f "$sudoers_file" &>/dev/null; then
        log_success "Sudoers file created (all commands disabled by default): $sudoers_file"
        log_warning "Sudo access is DISABLED. Edit $sudoers_file to enable specific commands"
    else
        log_error "Invalid sudoers file syntax"
        rm -f "$sudoers_file"
        exit 1
    fi

    log_info "Sudo logging: /var/log/sudo/${DEPLOY_USER}.log"
}

# Set password aging policy
configure_password_aging() {
    log_info "Configuring password aging policy for $DEPLOY_USER..."

    # Set password to never expire (since it's locked and SSH key-only)
    # This prevents unexpected account lockouts
    chage -M -1 "$DEPLOY_USER"
    chage -E -1 "$DEPLOY_USER"

    log_success "Password aging disabled (SSH key-only authentication)"
}

# Create user configuration summary
create_user_summary() {
    local summary_file="/home/$DEPLOY_USER/.chom-user-info"

    cat > "$summary_file" <<EOF
# ============================================================================
# CHOM Deployment User Configuration Summary
# ============================================================================
# User: $DEPLOY_USER
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================

USER INFORMATION:
- Username: $DEPLOY_USER
- UID: $(id -u "$DEPLOY_USER")
- GID: $(id -g "$DEPLOY_USER")
- Home Directory: /home/$DEPLOY_USER
- Shell: $DEPLOY_SHELL

SECURITY CONFIGURATION:
- Authentication: SSH key-only (password disabled)
- Password Status: Locked
- Home Permissions: $DEPLOY_HOME_MODE (rwxr-x---)
- Umask: $DEPLOY_UMASK (files: 640, directories: 750)
- Sudo Access: Disabled by default (see /etc/sudoers.d/$DEPLOY_USER)

SSH CONFIGURATION:
- SSH Directory: /home/$DEPLOY_USER/.ssh (700)
- Authorized Keys: /home/$DEPLOY_USER/.ssh/authorized_keys (600)
- Add public keys to authorized_keys to enable SSH access

AUDIT LOGGING:
- User Creation Log: $AUDIT_LOG
- Sudo Log: /var/log/sudo/$DEPLOY_USER.log
- System Log: journalctl -t chom-security

NEXT STEPS:
1. Add SSH public key to /home/$DEPLOY_USER/.ssh/authorized_keys
2. Test SSH connection: ssh -i <private-key> $DEPLOY_USER@<server>
3. Enable specific sudo commands in /etc/sudoers.d/$DEPLOY_USER (if needed)
4. Review audit logs regularly

SECURITY REMINDERS:
- Never enable password authentication
- Keep private SSH keys secure
- Grant minimal sudo privileges
- Monitor audit logs for suspicious activity
- Rotate SSH keys periodically

============================================================================
EOF

    chmod 640 "$summary_file"
    chown "$DEPLOY_USER:$DEPLOY_GROUP" "$summary_file"

    log_success "User configuration summary: $summary_file"
}

# Verify user configuration
verify_user_configuration() {
    log_info "Verifying user configuration..."

    local errors=0

    # Check user exists
    if ! id "$DEPLOY_USER" &>/dev/null; then
        log_error "User $DEPLOY_USER does not exist"
        ((errors++))
    fi

    # Check password is locked
    local passwd_status=$(passwd -S "$DEPLOY_USER" | awk '{print $2}')
    if [[ "$passwd_status" != "L" ]]; then
        log_error "Password is not locked"
        ((errors++))
    fi

    # Check home directory permissions
    local home_perms=$(stat -c '%a' "/home/$DEPLOY_USER")
    if [[ "$home_perms" != "$DEPLOY_HOME_MODE" ]]; then
        log_error "Home directory permissions incorrect (expected: $DEPLOY_HOME_MODE, actual: $home_perms)"
        ((errors++))
    fi

    # Check .ssh directory permissions
    local ssh_perms=$(stat -c '%a' "/home/$DEPLOY_USER/.ssh")
    if [[ "$ssh_perms" != "700" ]]; then
        log_error "SSH directory permissions incorrect (expected: 700, actual: $ssh_perms)"
        ((errors++))
    fi

    # Check authorized_keys permissions
    if [[ -f "/home/$DEPLOY_USER/.ssh/authorized_keys" ]]; then
        local auth_keys_perms=$(stat -c '%a' "/home/$DEPLOY_USER/.ssh/authorized_keys")
        if [[ "$auth_keys_perms" != "600" ]]; then
            log_error "authorized_keys permissions incorrect (expected: 600, actual: $auth_keys_perms)"
            ((errors++))
        fi
    fi

    # Check sudoers file
    if [[ -f "/etc/sudoers.d/$DEPLOY_USER" ]]; then
        local sudoers_perms=$(stat -c '%a' "/etc/sudoers.d/$DEPLOY_USER")
        if [[ "$sudoers_perms" != "440" ]]; then
            log_error "Sudoers file permissions incorrect (expected: 440, actual: $sudoers_perms)"
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
    log_success "Deployment User Creation Complete"
    log_success "=========================================="
    echo ""

    log_info "User Configuration:"
    echo "  Username: $DEPLOY_USER"
    echo "  UID: $(id -u "$DEPLOY_USER")"
    echo "  GID: $(id -g "$DEPLOY_USER")"
    echo "  Home: /home/$DEPLOY_USER"
    echo "  Shell: $DEPLOY_SHELL"
    echo ""

    log_info "Security Settings:"
    echo "  ✓ Authentication: SSH key-only (password disabled)"
    echo "  ✓ Password Status: Locked"
    echo "  ✓ Home Permissions: $DEPLOY_HOME_MODE (rwxr-x---)"
    echo "  ✓ Umask: $DEPLOY_UMASK (files: 640, directories: 750)"
    echo "  ✓ SSH Directory: 700 (rwx------)"
    echo "  ✓ Authorized Keys: 600 (rw-------)"
    echo "  ✓ Sudo Access: Disabled by default"
    echo ""

    log_info "Audit Logging:"
    echo "  User Creation: $AUDIT_LOG"
    echo "  Sudo Commands: /var/log/sudo/$DEPLOY_USER.log"
    echo "  System Events: journalctl -t chom-security"
    echo ""

    log_warning "NEXT STEPS:"
    echo "  1. Add SSH public key to: /home/$DEPLOY_USER/.ssh/authorized_keys"
    echo "  2. Test SSH connection: ssh -i <key> $DEPLOY_USER@<server>"
    echo "  3. Enable sudo commands if needed: /etc/sudoers.d/$DEPLOY_USER"
    echo "  4. Generate SSH keys: ./generate-ssh-keys-secure.sh"
    echo "  5. Review configuration: cat /home/$DEPLOY_USER/.chom-user-info"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  • Never enable password authentication for this user"
    echo "  • Keep SSH private keys secure and encrypted"
    echo "  • Grant only necessary sudo privileges (least privilege)"
    echo "  • Monitor audit logs for suspicious activity"
    echo "  • Rotate SSH keys every 90 days"
    echo "  • Review sudo access permissions regularly"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "=============================================="
    log_info "CHOM Secure Deployment User Creation"
    log_info "=============================================="
    echo ""

    check_root
    create_audit_directory
    verify_system_requirements

    # Check if user exists before creating
    local user_exists=1
    check_existing_user || user_exists=0

    create_deployment_group
    create_deployment_user
    lock_user_password
    configure_home_directory
    configure_user_umask
    create_ssh_directory
    configure_minimal_sudo
    configure_password_aging
    create_user_summary

    if verify_user_configuration; then
        display_security_summary
        log_success "Deployment user $DEPLOY_USER created successfully!"

        # Log final success
        logger -t chom-security "Deployment user $DEPLOY_USER created and configured successfully"

        exit 0
    else
        log_error "User configuration verification failed"
        log_error "Please review the errors above and re-run the script"
        exit 1
    fi
}

# Run main function
main "$@"
