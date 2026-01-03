#!/bin/bash
# ============================================================================
# Access Control Configuration Script
# ============================================================================
# Purpose: Configure user access with principle of least privilege
# Features: User management, sudo configuration, SSH access, auditing
# Compliance: PCI DSS 7.1, SOC 2, ISO 27001 A.9
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
APP_USER="${APP_USER:-www-data}"
APP_ROOT="${APP_ROOT:-/var/www/chom}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Create deployment user
create_deploy_user() {
    log_info "Creating deployment user: $DEPLOY_USER"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_info "User $DEPLOY_USER already exists"
    else
        # Create user with home directory
        useradd -m -s /bin/bash -c "CHOM Deployment User" "$DEPLOY_USER"

        # Set secure password (will be disabled for key-only auth)
        local temp_password=$(openssl rand -base64 32)
        echo "$DEPLOY_USER:$temp_password" | chpasswd

        log_success "User $DEPLOY_USER created"
    fi

    # Create user group if needed
    if ! getent group "$DEPLOY_GROUP" &>/dev/null; then
        groupadd "$DEPLOY_GROUP"
        usermod -aG "$DEPLOY_GROUP" "$DEPLOY_USER"
        log_success "Group $DEPLOY_GROUP created"
    fi
}

# Configure sudo access
configure_sudo() {
    log_info "Configuring sudo access for $DEPLOY_USER..."

    # Create sudoers file for deployment user
    cat > "/etc/sudoers.d/${DEPLOY_USER}" <<EOF
# CHOM Deployment User Sudo Configuration
# Principle of least privilege - only necessary commands

# Allow specific deployment commands without password
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart nginx
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl reload nginx
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart php*-fpm
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart postgresql
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl restart redis
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/composer install
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/php /var/www/chom/artisan *

# Allow user management (with password)
${DEPLOY_USER} ALL=(root) /usr/sbin/useradd, /usr/sbin/usermod, /usr/sbin/userdel

# Allow file ownership changes for deployment
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chown -R ${APP_USER}\:${APP_USER} ${APP_ROOT}
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chmod -R * ${APP_ROOT}/storage
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chmod -R * ${APP_ROOT}/bootstrap/cache

# Deny dangerous commands
${DEPLOY_USER} ALL=!/bin/rm -rf /, !/bin/dd, !/sbin/reboot, !/sbin/shutdown

# Logging
Defaults:${DEPLOY_USER} log_input, log_output
Defaults:${DEPLOY_USER} logfile="/var/log/sudo/${DEPLOY_USER}.log"
EOF

    chmod 440 "/etc/sudoers.d/${DEPLOY_USER}"

    # Create sudo log directory
    mkdir -p /var/log/sudo
    chmod 750 /var/log/sudo

    # Verify sudo configuration
    if visudo -c -f "/etc/sudoers.d/${DEPLOY_USER}" &>/dev/null; then
        log_success "Sudo configuration valid"
    else
        log_error "Sudo configuration is invalid"
        rm "/etc/sudoers.d/${DEPLOY_USER}"
        return 1
    fi

    log_success "Sudo access configured"
}

# Configure SSH access
configure_ssh_access() {
    log_info "Configuring SSH access for $DEPLOY_USER..."

    local ssh_dir="/home/$DEPLOY_USER/.ssh"

    # Create .ssh directory
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Create authorized_keys if it doesn't exist
    if [[ ! -f "$ssh_dir/authorized_keys" ]]; then
        touch "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
    fi

    # Set ownership
    chown -R "$DEPLOY_USER:$DEPLOY_GROUP" "$ssh_dir"

    log_success "SSH directory configured"
    log_info "Add public keys to: $ssh_dir/authorized_keys"
}

# Lock system accounts
lock_system_accounts() {
    log_info "Locking unnecessary system accounts..."

    local system_users=("games" "news" "uucp" "proxy" "list" "irc" "gnats" "nobody")
    local locked=0

    for user in "${system_users[@]}"; do
        if id "$user" &>/dev/null; then
            passwd -l "$user" &>/dev/null || true
            usermod -s /usr/sbin/nologin "$user" &>/dev/null || true
            ((locked++))
        fi
    done

    log_success "Locked $locked system accounts"
}

# Disable unused users
disable_unused_users() {
    log_info "Checking for unused user accounts..."

    # Find users who haven't logged in for 90 days
    local inactive_users=$(lastlog -b 90 | tail -n +2 | awk '{print $1}' | grep -v "^root$\|^$DEPLOY_USER$" || echo "")

    if [[ -n "$inactive_users" ]]; then
        log_warning "Found inactive users (not logged in for 90+ days):"
        echo "$inactive_users"
        log_info "Consider disabling or removing these accounts"
    else
        log_success "No inactive user accounts found"
    fi
}

# Configure password policy
configure_password_policy() {
    log_info "Configuring password policy..."

    # Install libpam-pwquality
    apt-get update -qq
    apt-get install -y libpam-pwquality

    # Configure password quality requirements
    cat > /etc/security/pwquality.conf <<EOF
# CHOM Password Quality Requirements
# PCI DSS 8.2, NIST SP 800-63B

# Minimum password length
minlen = 14

# Require at least one digit
dcredit = -1

# Require at least one uppercase
ucredit = -1

# Require at least one lowercase
lcredit = -1

# Require at least one special character
ocredit = -1

# Maximum number of allowed consecutive characters
maxrepeat = 2

# Maximum number of allowed consecutive characters of same class
maxclassrepeat = 3

# Reject passwords containing username
usercheck = 1

# Enforce for root
enforce_for_root
EOF

    # Configure password aging
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    14/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

    log_success "Password policy configured"
}

# Configure account lockout
configure_account_lockout() {
    log_info "Configuring account lockout policy..."

    # Configure PAM for account lockout
    local pam_auth="/etc/pam.d/common-auth"

    if ! grep -q "pam_faillock" "$pam_auth"; then
        # Backup original
        cp "$pam_auth" "${pam_auth}.backup"

        # Add faillock before pam_unix.so
        sed -i '/pam_unix.so/i auth    required    pam_faillock.so preauth deny=5 unlock_time=1800' "$pam_auth"
        sed -i '/pam_unix.so/a auth    [default=die]    pam_faillock.so authfail' "$pam_auth"
        sed -i '/pam_permit.so/a auth    sufficient    pam_faillock.so authsucc' "$pam_auth"

        log_success "Account lockout configured (5 attempts, 30 min lockout)"
    else
        log_info "Account lockout already configured"
    fi
}

# Create user audit script
create_user_audit_script() {
    log_info "Creating user audit script..."

    cat > /usr/local/bin/chom-user-audit <<'EOF'
#!/bin/bash
# CHOM User Access Audit

echo "=============================================="
echo "CHOM User Access Audit"
echo "=============================================="
echo ""

echo "=== All User Accounts ==="
awk -F: '{if ($3 >= 1000) print $1 " (UID: " $3 ")"}' /etc/passwd
echo ""

echo "=== Users with Sudo Access ==="
grep -E "^sudo:" /etc/group | cut -d: -f4
echo ""

echo "=== Users with UID 0 (root equivalent) ==="
awk -F: '{if ($3 == 0) print $1}' /etc/passwd
echo ""

echo "=== Users with Empty Passwords ==="
awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null || echo "Permission denied"
echo ""

echo "=== Recent Logins (last 20) ==="
last -20
echo ""

echo "=== Failed Login Attempts ==="
grep "Failed password" /var/log/auth.log | tail -20
echo ""

echo "=== Currently Logged In Users ==="
who
echo ""

echo "=== Locked Accounts ==="
passwd -S -a 2>/dev/null | grep " L " | awk '{print $1}'
echo ""

echo "=== SSH Authorized Keys ==="
for user_home in /home/*; do
    user=$(basename "$user_home")
    if [[ -f "$user_home/.ssh/authorized_keys" ]]; then
        echo "$user:"
        wc -l "$user_home/.ssh/authorized_keys"
    fi
done
echo ""

echo "=== Sudo Command History ==="
if [[ -f /var/log/sudo/stilgar.log ]]; then
    tail -20 /var/log/sudo/stilgar.log
else
    echo "No sudo logs found"
fi
EOF

    chmod +x /usr/local/bin/chom-user-audit

    log_success "User audit script created: /usr/local/bin/chom-user-audit"
}

# Configure session timeout
configure_session_timeout() {
    log_info "Configuring session timeout..."

    # Set idle timeout for SSH sessions
    cat >> /etc/ssh/sshd_config <<EOF

# Session timeout (15 minutes)
ClientAliveInterval 300
ClientAliveCountMax 3
EOF

    # Set shell timeout
    cat > /etc/profile.d/chom-timeout.sh <<EOF
# CHOM Session Timeout
# Auto-logout after 15 minutes of inactivity
export TMOUT=900
readonly TMOUT
EOF

    chmod +x /etc/profile.d/chom-timeout.sh

    log_success "Session timeout configured (15 minutes)"
}

# Configure audit logging
configure_audit_logging() {
    log_info "Configuring access audit logging..."

    # Install auditd
    apt-get install -y auditd audispd-plugins

    # Configure audit rules
    cat > /etc/audit/rules.d/chom-access.rules <<EOF
# CHOM Access Control Audit Rules

# Monitor user/group modifications
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor sudo usage
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd

# Monitor login/logout
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# Monitor file permission changes
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
EOF

    # Restart auditd
    service auditd restart

    log_success "Audit logging configured"
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "Access Control Configuration Complete"
    log_success "=========================================="
    echo ""

    log_info "User Configuration:"
    echo "  Deployment User: $DEPLOY_USER"
    echo "  Application User: $APP_USER"
    echo ""

    log_info "Access Controls:"
    echo "  ✓ Deployment user created"
    echo "  ✓ Sudo access configured (least privilege)"
    echo "  ✓ SSH access configured"
    echo "  ✓ System accounts locked"
    echo "  ✓ Password policy enforced (14 chars, complexity)"
    echo "  ✓ Account lockout enabled (5 attempts, 30 min)"
    echo "  ✓ Session timeout (15 minutes)"
    echo "  ✓ Audit logging enabled"
    echo ""

    log_info "Password Requirements:"
    echo "  Minimum length: 14 characters"
    echo "  Complexity: uppercase, lowercase, digit, special"
    echo "  Maximum age: 90 days"
    echo "  Lockout: 5 failed attempts"
    echo ""

    log_info "Management Commands:"
    echo "  chom-user-audit         - Run user access audit"
    echo "  sudo -l                 - List allowed sudo commands"
    echo "  ausearch -k identity    - Search audit logs for user changes"
    echo ""

    log_info "Next Steps:"
    echo "  1. Add SSH public keys to: /home/$DEPLOY_USER/.ssh/authorized_keys"
    echo "  2. Test sudo access for deployment user"
    echo "  3. Review and adjust sudo permissions as needed"
    echo "  4. Run regular access audits: chom-user-audit"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  1. Never use root account for daily operations"
    echo "  2. Review sudo logs regularly"
    echo "  3. Remove unused accounts promptly"
    echo "  4. Enforce strong passwords for all users"
    echo "  5. Monitor failed login attempts"
    echo ""
}

# Main execution
main() {
    log_info "Starting access control configuration..."
    echo ""

    check_root
    create_deploy_user
    configure_sudo
    configure_ssh_access
    lock_system_accounts
    disable_unused_users
    configure_password_policy
    configure_account_lockout
    configure_session_timeout
    configure_audit_logging
    create_user_audit_script
    display_summary

    log_success "Access control configuration complete!"
}

# Run main function
main "$@"
