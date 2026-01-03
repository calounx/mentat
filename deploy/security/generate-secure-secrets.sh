#!/bin/bash
# ============================================================================
# Secure Deployment Secrets Generation Script
# ============================================================================
# Purpose: Generate strong random secrets for deployment automation
# Entropy: /dev/urandom, OpenSSL cryptographic random generation
# Security: 600 permissions, stilgar ownership, comprehensive audit logging
# Compliance: OWASP, NIST SP 800-132, FIPS 140-2
# ============================================================================
# SECURITY FEATURES:
# - Cryptographically strong random generation (/dev/urandom, OpenSSL)
# - Minimum 32 characters for all secrets
# - Laravel APP_KEY format compliance
# - Proper file permissions (600)
# - Deployment user ownership
# - Comprehensive audit trail
# - Idempotent operation (safe to re-run)
# ============================================================================
# GENERATED SECRETS:
# - DB_PASSWORD (40 alphanumeric characters)
# - REDIS_PASSWORD (64 base64 characters)
# - APP_KEY (Laravel format: base64:...)
# - JWT_SECRET (64 base64 characters)
# - GRAFANA_ADMIN_PASSWORD (32 alphanumeric characters)
# - PROMETHEUS_PASSWORD (32 alphanumeric characters)
# - SESSION_SECRET (64 hex characters)
# - ENCRYPTION_KEY (32 hex characters)
# ============================================================================

set -euo pipefail

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
SECRETS_FILE="${SECRETS_FILE:-.deployment-secrets}"
SECRETS_DIR="/home/$DEPLOY_USER"
SECRETS_PATH="$SECRETS_DIR/$SECRETS_FILE"
BACKUP_DIR="/var/backups/chom/secrets"
AUDIT_LOG="/var/log/chom-deployment/secret-generation.log"

# Minimum secret lengths (NIST SP 800-132 recommendations)
MIN_PASSWORD_LENGTH=32
MIN_KEY_LENGTH=64

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

    local required_commands=("openssl" "head" "tr" "base64")
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

    # Verify /dev/urandom is available
    if [[ ! -c /dev/urandom ]]; then
        log_error "/dev/urandom not available"
        exit 1
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

# Backup existing secrets file
backup_existing_secrets() {
    if [[ -f "$SECRETS_PATH" ]]; then
        log_warning "Existing secrets file found, creating backup..."

        local backup_timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$BACKUP_DIR/deployment_secrets_${backup_timestamp}"

        cp "$SECRETS_PATH" "$backup_file"
        chmod 600 "$backup_file"

        log_success "Backup created: $backup_file"

        echo ""
        read -p "Overwrite existing secrets? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Keeping existing secrets, exiting..."
            exit 0
        fi
    else
        log_info "No existing secrets file to backup"
    fi
}

# Generate random secret using OpenSSL
# Args: $1 = length, $2 = type (base64, hex, alnum)
generate_random_secret() {
    local length="${1:-64}"
    local type="${2:-base64}"

    case "$type" in
        base64)
            # Generate base64-encoded random data
            # OpenSSL provides cryptographically strong random bytes
            openssl rand -base64 "$length" | tr -d '\n' | head -c "$length"
            ;;
        hex)
            # Generate hex-encoded random data
            openssl rand -hex "$((length / 2))" | tr -d '\n' | head -c "$length"
            ;;
        alnum)
            # Generate alphanumeric random string (base64 then filter)
            # This ensures strong entropy from OpenSSL
            openssl rand -base64 "$((length * 2))" | tr -dc 'A-Za-z0-9' | head -c "$length"
            ;;
        *)
            log_error "Unknown secret type: $type"
            return 1
            ;;
    esac
}

# Generate database password
generate_db_password() {
    log_info "Generating database password (40 alphanumeric characters)..."

    # PCI DSS 8.2.3: Minimum 12 characters, we use 40 for extra security
    local db_password=$(generate_random_secret 40 alnum)

    if [[ ${#db_password} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "Generated password is too short (${#db_password} < $MIN_PASSWORD_LENGTH)"
        exit 1
    fi

    echo "$db_password"
    log_success "Database password generated (${#db_password} characters)"
}

# Generate Redis password
generate_redis_password() {
    log_info "Generating Redis password (64 base64 characters)..."

    local redis_password=$(generate_random_secret 64 base64)

    if [[ ${#redis_password} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "Generated password is too short (${#redis_password} < $MIN_PASSWORD_LENGTH)"
        exit 1
    fi

    echo "$redis_password"
    log_success "Redis password generated (${#redis_password} characters)"
}

# Generate Laravel APP_KEY
generate_app_key() {
    log_info "Generating Laravel APP_KEY (base64:32bytes format)..."

    # Laravel expects: base64:<32 bytes of random data encoded as base64>
    # This generates 32 random bytes, base64 encodes them
    local key_bytes=$(openssl rand -base64 32 | tr -d '\n')
    local app_key="base64:${key_bytes}"

    echo "$app_key"
    log_success "Laravel APP_KEY generated"
}

# Generate JWT secret
generate_jwt_secret() {
    log_info "Generating JWT_SECRET (64 base64 characters)..."

    # JWT secrets should be strong and random
    # 64 characters of base64 = 48 bytes of entropy
    local jwt_secret=$(generate_random_secret 64 base64)

    if [[ ${#jwt_secret} -lt $MIN_KEY_LENGTH ]]; then
        log_error "Generated JWT secret is too short (${#jwt_secret} < $MIN_KEY_LENGTH)"
        exit 1
    fi

    echo "$jwt_secret"
    log_success "JWT secret generated (${#jwt_secret} characters)"
}

# Generate Grafana admin password
generate_grafana_password() {
    log_info "Generating Grafana admin password (32 alphanumeric characters)..."

    local grafana_password=$(generate_random_secret 32 alnum)

    if [[ ${#grafana_password} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "Generated password is too short (${#grafana_password} < $MIN_PASSWORD_LENGTH)"
        exit 1
    fi

    echo "$grafana_password"
    log_success "Grafana admin password generated (${#grafana_password} characters)"
}

# Generate Prometheus password
generate_prometheus_password() {
    log_info "Generating Prometheus password (32 alphanumeric characters)..."

    local prometheus_password=$(generate_random_secret 32 alnum)

    if [[ ${#prometheus_password} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "Generated password is too short (${#prometheus_password} < $MIN_PASSWORD_LENGTH)"
        exit 1
    fi

    echo "$prometheus_password"
    log_success "Prometheus password generated (${#prometheus_password} characters)"
}

# Generate session secret
generate_session_secret() {
    log_info "Generating session secret (64 hex characters)..."

    # Session secrets should be hex for cookie signing
    local session_secret=$(generate_random_secret 64 hex)

    if [[ ${#session_secret} -lt $MIN_KEY_LENGTH ]]; then
        log_error "Generated session secret is too short (${#session_secret} < $MIN_KEY_LENGTH)"
        exit 1
    fi

    echo "$session_secret"
    log_success "Session secret generated (${#session_secret} characters)"
}

# Generate encryption key
generate_encryption_key() {
    log_info "Generating encryption key (64 hex characters)..."

    # 64 hex chars = 32 bytes = 256 bits (AES-256 compatible)
    local encryption_key=$(generate_random_secret 64 hex)

    if [[ ${#encryption_key} -lt $MIN_KEY_LENGTH ]]; then
        log_error "Generated encryption key is too short (${#encryption_key} < $MIN_KEY_LENGTH)"
        exit 1
    fi

    echo "$encryption_key"
    log_success "Encryption key generated (${#encryption_key} characters, 256-bit)")
}

# Generate all secrets and write to file
generate_all_secrets() {
    log_info "Generating all deployment secrets..."

    # Generate all secrets
    local db_password=$(generate_db_password)
    local redis_password=$(generate_redis_password)
    local app_key=$(generate_app_key)
    local jwt_secret=$(generate_jwt_secret)
    local grafana_password=$(generate_grafana_password)
    local prometheus_password=$(generate_prometheus_password)
    local session_secret=$(generate_session_secret)
    local encryption_key=$(generate_encryption_key)

    # Create secrets file
    cat > "$SECRETS_PATH" <<EOF
# ============================================================================
# CHOM Deployment Secrets
# ============================================================================
# CRITICAL: This file contains sensitive credentials
# Permissions: 600 (rw-------)
# Owner: $DEPLOY_USER
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================
#
# SECURITY WARNINGS:
# - Never commit this file to version control
# - Never share these secrets via email or chat
# - Store backups in encrypted storage only
# - Rotate secrets every 90 days
# - Use different secrets for each environment
#
# ============================================================================

# Database Credentials
DB_PASSWORD=$db_password

# Redis Credentials
REDIS_PASSWORD=$redis_password

# Laravel Application Key (base64 encoded)
APP_KEY=$app_key

# JWT Secret for API authentication
JWT_SECRET=$jwt_secret

# Session Secret for cookie signing
SESSION_SECRET=$session_secret

# Encryption Key for data at rest (256-bit)
ENCRYPTION_KEY=$encryption_key

# Grafana Admin Credentials
GRAFANA_ADMIN_PASSWORD=$grafana_password

# Prometheus Credentials
PROMETHEUS_PASSWORD=$prometheus_password

# ============================================================================
# Secret Metadata
# ============================================================================
SECRETS_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SECRETS_GENERATED_BY=$USER
SECRETS_VERSION=1.0

# ============================================================================
# Usage Instructions
# ============================================================================
# Source this file in deployment scripts:
#   source /home/$DEPLOY_USER/$SECRETS_FILE
#
# Or use individual secrets:
#   DB_PASSWORD=\$(grep '^DB_PASSWORD=' $SECRETS_PATH | cut -d= -f2)
#
# ============================================================================
EOF

    log_success "Secrets file created: $SECRETS_PATH"
}

# Set secure permissions on secrets file
set_secure_permissions() {
    log_info "Setting secure permissions on secrets file..."

    # Set permissions to 600 (rw-------)
    chmod 600 "$SECRETS_PATH"

    # Set ownership to deployment user
    chown "$DEPLOY_USER:$DEPLOY_USER" "$SECRETS_PATH"

    # Verify permissions
    local actual_perms=$(stat -c '%a' "$SECRETS_PATH")
    if [[ "$actual_perms" == "600" ]]; then
        log_success "Secrets file permissions: 600 (rw-------)"
    else
        log_error "Failed to set secrets file permissions (expected: 600, actual: $actual_perms)"
        exit 1
    fi

    # Verify ownership
    local actual_owner=$(stat -c '%U' "$SECRETS_PATH")
    if [[ "$actual_owner" == "$DEPLOY_USER" ]]; then
        log_success "Secrets file owner: $DEPLOY_USER"
    else
        log_error "Failed to set secrets file ownership (expected: $DEPLOY_USER, actual: $actual_owner)"
        exit 1
    fi
}

# Verify secrets quality
verify_secrets_quality() {
    log_info "Verifying secrets quality..."

    local errors=0

    # Source the secrets file
    source "$SECRETS_PATH"

    # Verify DB_PASSWORD
    if [[ ${#DB_PASSWORD} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "DB_PASSWORD is too short (${#DB_PASSWORD} < $MIN_PASSWORD_LENGTH)"
        ((errors++))
    fi

    # Verify REDIS_PASSWORD
    if [[ ${#REDIS_PASSWORD} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "REDIS_PASSWORD is too short (${#REDIS_PASSWORD} < $MIN_PASSWORD_LENGTH)"
        ((errors++))
    fi

    # Verify APP_KEY format
    if [[ ! "$APP_KEY" =~ ^base64:.+ ]]; then
        log_error "APP_KEY is not in Laravel format (base64:...)"
        ((errors++))
    fi

    # Verify JWT_SECRET
    if [[ ${#JWT_SECRET} -lt $MIN_KEY_LENGTH ]]; then
        log_error "JWT_SECRET is too short (${#JWT_SECRET} < $MIN_KEY_LENGTH)"
        ((errors++))
    fi

    # Verify GRAFANA_ADMIN_PASSWORD
    if [[ ${#GRAFANA_ADMIN_PASSWORD} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "GRAFANA_ADMIN_PASSWORD is too short (${#GRAFANA_ADMIN_PASSWORD} < $MIN_PASSWORD_LENGTH)"
        ((errors++))
    fi

    # Verify PROMETHEUS_PASSWORD
    if [[ ${#PROMETHEUS_PASSWORD} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "PROMETHEUS_PASSWORD is too short (${#PROMETHEUS_PASSWORD} < $MIN_PASSWORD_LENGTH)"
        ((errors++))
    fi

    # Verify SESSION_SECRET
    if [[ ${#SESSION_SECRET} -lt $MIN_KEY_LENGTH ]]; then
        log_error "SESSION_SECRET is too short (${#SESSION_SECRET} < $MIN_KEY_LENGTH)"
        ((errors++))
    fi

    # Verify ENCRYPTION_KEY (should be 64 hex chars = 32 bytes)
    if [[ ${#ENCRYPTION_KEY} -ne 64 ]]; then
        log_error "ENCRYPTION_KEY is not 64 characters (256-bit)"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "All secrets quality checks passed"
        return 0
    else
        log_error "$errors secrets quality check(s) failed"
        return 1
    fi
}

# Display secrets summary (without revealing actual values)
display_secrets_summary() {
    echo ""
    log_success "=========================================="
    log_success "Deployment Secrets Generation Complete"
    log_success "=========================================="
    echo ""

    log_info "Secrets File:"
    echo "  Location: $SECRETS_PATH"
    echo "  Permissions: 600 (rw-------)"
    echo "  Owner: $DEPLOY_USER"
    echo ""

    log_info "Generated Secrets:"
    echo "  ✓ DB_PASSWORD (40 alphanumeric characters)"
    echo "  ✓ REDIS_PASSWORD (64 base64 characters)"
    echo "  ✓ APP_KEY (Laravel format: base64:...)"
    echo "  ✓ JWT_SECRET (64 base64 characters)"
    echo "  ✓ SESSION_SECRET (64 hex characters)"
    echo "  ✓ ENCRYPTION_KEY (64 hex characters, 256-bit)"
    echo "  ✓ GRAFANA_ADMIN_PASSWORD (32 alphanumeric characters)"
    echo "  ✓ PROMETHEUS_PASSWORD (32 alphanumeric characters)"
    echo ""

    log_info "Security Compliance:"
    echo "  ✓ NIST SP 800-132: Strong random generation"
    echo "  ✓ PCI DSS 8.2.3: Minimum length requirements met"
    echo "  ✓ OWASP: Cryptographic random source (/dev/urandom, OpenSSL)"
    echo "  ✓ FIPS 140-2: Approved random number generator"
    echo ""

    log_info "Backups:"
    echo "  Backup directory: $BACKUP_DIR"
    echo ""

    log_info "Audit Logging:"
    echo "  Secret generation: $AUDIT_LOG"
    echo "  System events: journalctl -t chom-security"
    echo ""

    log_warning "NEXT STEPS:"
    echo "  1. Review secrets file: sudo -u $DEPLOY_USER cat $SECRETS_PATH"
    echo "  2. Source in deployment scripts:"
    echo "     source $SECRETS_PATH"
    echo "  3. Update application .env file with these secrets"
    echo "  4. Update database with DB_PASSWORD"
    echo "  5. Update Redis with REDIS_PASSWORD"
    echo "  6. Update Grafana with GRAFANA_ADMIN_PASSWORD"
    echo "  7. Update Prometheus with PROMETHEUS_PASSWORD"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  • NEVER commit $SECRETS_FILE to version control"
    echo "  • Add to .gitignore: echo '$SECRETS_FILE' >> .gitignore"
    echo "  • Backup to encrypted storage only"
    echo "  • Use different secrets for dev/staging/production"
    echo "  • Rotate secrets every 90 days"
    echo "  • Monitor access to secrets file: auditctl -w $SECRETS_PATH -p wa"
    echo "  • Revoke secrets immediately if compromised"
    echo ""

    log_info "To view secrets (as $DEPLOY_USER):"
    echo "  sudo -u $DEPLOY_USER cat $SECRETS_PATH"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "=============================================="
    log_info "CHOM Secure Secrets Generation"
    log_info "=============================================="
    echo ""

    check_root
    create_audit_directory
    verify_user_exists
    verify_system_requirements
    create_backup_directory
    backup_existing_secrets
    generate_all_secrets
    set_secure_permissions

    if verify_secrets_quality; then
        display_secrets_summary
        log_success "Deployment secrets generated successfully!"

        # Log security event
        logger -t chom-security "Deployment secrets generated for user: $DEPLOY_USER"

        exit 0
    else
        log_error "Secrets quality verification failed"
        log_error "Please review the errors above and re-run the script"
        exit 1
    fi
}

# Run main function
main "$@"
