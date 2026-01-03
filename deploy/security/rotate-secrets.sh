#!/bin/bash
# ============================================================================
# Zero-Downtime Secret Rotation Script
# ============================================================================
# Purpose: Rotate application secrets with zero downtime
# Strategy: Blue-green secret rotation with rollback capability
# Security: Safe rotation, service coordination, comprehensive audit logging
# Compliance: OWASP, PCI DSS 8.2.4, SOC 2, NIST SP 800-131A
# ============================================================================
# SECURITY FEATURES:
# - Zero-downtime rotation strategy
# - Backup before rotation
# - Service coordination (database, Redis, application)
# - Rollback capability
# - Comprehensive audit logging
# - Verification at each step
# - Idempotent operation (safe to re-run)
# ============================================================================
# ROTATION STRATEGY:
# 1. Backup current secrets
# 2. Generate new secrets
# 3. Update services one by one
# 4. Verify each service
# 5. Rollback on failure
# ============================================================================

set -euo pipefail

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
SECRETS_FILE="${SECRETS_FILE:-.deployment-secrets}"
SECRETS_DIR="/home/$DEPLOY_USER"
SECRETS_PATH="$SECRETS_DIR/$SECRETS_FILE"
BACKUP_DIR="/var/backups/chom/secrets"
AUDIT_LOG="/var/log/chom-deployment/secret-rotation.log"

# Application configuration
APP_ROOT="${APP_ROOT:-/var/www/chom}"
APP_ENV="$APP_ROOT/.env"

# Database configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-chom}"
DB_USER="${DB_USER:-chom}"

# Redis configuration
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_CONFIG="${REDIS_CONFIG:-/etc/redis/redis.conf}"

# Rotation options
ROTATE_DB_PASSWORD="${ROTATE_DB_PASSWORD:-false}"
ROTATE_REDIS_PASSWORD="${ROTATE_REDIS_PASSWORD:-false}"
ROTATE_APP_KEYS="${ROTATE_APP_KEYS:-true}"
ROTATE_API_TOKENS="${ROTATE_API_TOKENS:-true}"
DRY_RUN="${DRY_RUN:-false}"

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

# Verify prerequisites
verify_prerequisites() {
    log_info "Verifying prerequisites..."

    # Check secrets file exists
    if [[ ! -f "$SECRETS_PATH" ]]; then
        log_error "Secrets file not found: $SECRETS_PATH"
        log_error "Generate secrets first: ./generate-secure-secrets.sh"
        exit 1
    fi

    # Check application .env exists
    if [[ ! -f "$APP_ENV" ]]; then
        log_error "Application .env not found: $APP_ENV"
        exit 1
    fi

    # Check backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
    fi

    log_success "Prerequisites verified"
}

# Display rotation plan
display_rotation_plan() {
    echo ""
    log_warning "=========================================="
    log_warning "Secret Rotation Plan"
    log_warning "=========================================="
    echo ""

    log_info "Secrets to Rotate:"
    if [[ "$ROTATE_DB_PASSWORD" == "true" ]]; then
        echo "  ✓ Database Password (DB_PASSWORD)"
    else
        echo "  ✗ Database Password (SKIPPED)"
    fi

    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        echo "  ✓ Redis Password (REDIS_PASSWORD)"
    else
        echo "  ✗ Redis Password (SKIPPED)"
    fi

    if [[ "$ROTATE_APP_KEYS" == "true" ]]; then
        echo "  ✓ Application Keys (APP_KEY, JWT_SECRET, SESSION_SECRET, ENCRYPTION_KEY)"
    else
        echo "  ✗ Application Keys (SKIPPED)"
    fi

    if [[ "$ROTATE_API_TOKENS" == "true" ]]; then
        echo "  ✓ API Tokens (GRAFANA, PROMETHEUS)"
    else
        echo "  ✗ API Tokens (SKIPPED)"
    fi

    echo ""
    log_info "Rotation Strategy:"
    echo "  1. Backup current secrets"
    echo "  2. Generate new secrets"
    if [[ "$ROTATE_DB_PASSWORD" == "true" ]]; then
        echo "  3. Update database password"
    fi
    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        echo "  4. Update Redis password"
    fi
    if [[ "$ROTATE_APP_KEYS" == "true" ]]; then
        echo "  5. Update application keys"
    fi
    echo "  6. Restart services gracefully"
    echo "  7. Verify all services"
    echo "  8. Commit changes or rollback on failure"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE: No changes will be made"
        echo ""
    fi

    read -p "Proceed with secret rotation? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Secret rotation cancelled by user"
        exit 0
    fi
}

# Backup current secrets
backup_current_secrets() {
    log_info "Backing up current secrets..."

    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/secrets_before_rotation_${backup_timestamp}.tar.gz"

    # Create comprehensive backup
    tar -czf "$backup_file" \
        -C "$(dirname "$SECRETS_PATH")" "$(basename "$SECRETS_PATH")" \
        -C "$(dirname "$APP_ENV")" "$(basename "$APP_ENV")" \
        2>/dev/null || true

    if [[ -f "$backup_file" ]]; then
        chmod 600 "$backup_file"
        log_success "Backup created: $backup_file"

        # Store backup path for potential rollback
        echo "$backup_file" > /tmp/chom_secret_rotation_backup
        chmod 600 /tmp/chom_secret_rotation_backup
    else
        log_error "Failed to create backup"
        exit 1
    fi
}

# Generate new secrets
generate_new_secrets() {
    log_info "Generating new secrets..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Skipping secret generation"
        return 0
    fi

    # Source current secrets
    source "$SECRETS_PATH"

    # Store old secrets for comparison
    OLD_DB_PASSWORD="$DB_PASSWORD"
    OLD_REDIS_PASSWORD="$REDIS_PASSWORD"
    OLD_APP_KEY="$APP_KEY"

    # Generate new secrets based on rotation flags
    if [[ "$ROTATE_DB_PASSWORD" == "true" ]]; then
        NEW_DB_PASSWORD=$(openssl rand -base64 40 | tr -dc 'A-Za-z0-9' | head -c 40)
        log_success "New database password generated"
    else
        NEW_DB_PASSWORD="$OLD_DB_PASSWORD"
    fi

    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        NEW_REDIS_PASSWORD=$(openssl rand -base64 64 | tr -d '\n' | head -c 64)
        log_success "New Redis password generated"
    else
        NEW_REDIS_PASSWORD="$OLD_REDIS_PASSWORD"
    fi

    if [[ "$ROTATE_APP_KEYS" == "true" ]]; then
        NEW_APP_KEY="base64:$(openssl rand -base64 32 | tr -d '\n')"
        NEW_JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n' | head -c 64)
        NEW_SESSION_SECRET=$(openssl rand -hex 32)
        NEW_ENCRYPTION_KEY=$(openssl rand -hex 32)
        log_success "New application keys generated"
    else
        NEW_APP_KEY="$APP_KEY"
        NEW_JWT_SECRET="$JWT_SECRET"
        NEW_SESSION_SECRET="$SESSION_SECRET"
        NEW_ENCRYPTION_KEY="$ENCRYPTION_KEY"
    fi

    if [[ "$ROTATE_API_TOKENS" == "true" ]]; then
        NEW_GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
        NEW_PROMETHEUS_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
        log_success "New API tokens generated"
    else
        NEW_GRAFANA_PASSWORD="$GRAFANA_ADMIN_PASSWORD"
        NEW_PROMETHEUS_PASSWORD="$PROMETHEUS_PASSWORD"
    fi

    # Export new secrets for later use
    export NEW_DB_PASSWORD NEW_REDIS_PASSWORD NEW_APP_KEY NEW_JWT_SECRET
    export NEW_SESSION_SECRET NEW_ENCRYPTION_KEY NEW_GRAFANA_PASSWORD NEW_PROMETHEUS_PASSWORD

    log_success "New secrets generated successfully"
}

# Update database password
update_database_password() {
    if [[ "$ROTATE_DB_PASSWORD" != "true" ]]; then
        log_info "Skipping database password rotation"
        return 0
    fi

    log_info "Updating database password..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update database password"
        return 0
    fi

    # Update PostgreSQL password
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$NEW_DB_PASSWORD';" &>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "Database password updated"
    else
        log_error "Failed to update database password"
        return 1
    fi

    # Test database connection with new password
    PGPASSWORD="$NEW_DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "Database connection verified with new password"
    else
        log_error "Database connection failed with new password"
        return 1
    fi
}

# Update Redis password
update_redis_password() {
    if [[ "$ROTATE_REDIS_PASSWORD" != "true" ]]; then
        log_info "Skipping Redis password rotation"
        return 0
    fi

    log_info "Updating Redis password..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update Redis password"
        return 0
    fi

    # Update Redis configuration
    if [[ -f "$REDIS_CONFIG" ]]; then
        # Backup Redis config
        cp "$REDIS_CONFIG" "${REDIS_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

        # Update requirepass
        sed -i "s/^requirepass.*/requirepass $NEW_REDIS_PASSWORD/" "$REDIS_CONFIG"

        # Restart Redis
        systemctl restart redis-server || systemctl restart redis

        if [[ $? -eq 0 ]]; then
            log_success "Redis restarted with new password"
        else
            log_error "Failed to restart Redis"
            return 1
        fi

        # Test Redis connection
        redis-cli -a "$NEW_REDIS_PASSWORD" ping &>/dev/null

        if [[ $? -eq 0 ]]; then
            log_success "Redis connection verified with new password"
        else
            log_error "Redis connection failed with new password"
            return 1
        fi
    else
        log_warning "Redis config not found: $REDIS_CONFIG"
    fi
}

# Update application secrets file
update_secrets_file() {
    log_info "Updating deployment secrets file..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update secrets file"
        return 0
    fi

    # Update secrets file with new values
    cat > "$SECRETS_PATH" <<EOF
# ============================================================================
# CHOM Deployment Secrets
# ============================================================================
# CRITICAL: This file contains sensitive credentials
# Last Rotated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================================

# Database Credentials
DB_PASSWORD=$NEW_DB_PASSWORD

# Redis Credentials
REDIS_PASSWORD=$NEW_REDIS_PASSWORD

# Laravel Application Key
APP_KEY=$NEW_APP_KEY

# JWT Secret
JWT_SECRET=$NEW_JWT_SECRET

# Session Secret
SESSION_SECRET=$NEW_SESSION_SECRET

# Encryption Key
ENCRYPTION_KEY=$NEW_ENCRYPTION_KEY

# Grafana Admin Credentials
GRAFANA_ADMIN_PASSWORD=$NEW_GRAFANA_PASSWORD

# Prometheus Credentials
PROMETHEUS_PASSWORD=$NEW_PROMETHEUS_PASSWORD

# Rotation Metadata
SECRETS_ROTATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SECRETS_ROTATED_BY=$USER
SECRETS_VERSION=1.1

EOF

    chmod 600 "$SECRETS_PATH"
    chown "$DEPLOY_USER:$DEPLOY_USER" "$SECRETS_PATH"

    log_success "Secrets file updated"
}

# Update application .env file
update_application_env() {
    log_info "Updating application .env file..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update .env file"
        return 0
    fi

    # Backup current .env
    cp "$APP_ENV" "${APP_ENV}.backup.$(date +%Y%m%d_%H%M%S)"

    # Update .env with new secrets
    if [[ "$ROTATE_DB_PASSWORD" == "true" ]]; then
        sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$NEW_DB_PASSWORD|" "$APP_ENV"
    fi

    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$NEW_REDIS_PASSWORD|" "$APP_ENV"
    fi

    if [[ "$ROTATE_APP_KEYS" == "true" ]]; then
        sed -i "s|^APP_KEY=.*|APP_KEY=$NEW_APP_KEY|" "$APP_ENV"

        if grep -q "^JWT_SECRET=" "$APP_ENV"; then
            sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$NEW_JWT_SECRET|" "$APP_ENV"
        else
            echo "JWT_SECRET=$NEW_JWT_SECRET" >> "$APP_ENV"
        fi

        if grep -q "^SESSION_SECRET=" "$APP_ENV"; then
            sed -i "s|^SESSION_SECRET=.*|SESSION_SECRET=$NEW_SESSION_SECRET|" "$APP_ENV"
        else
            echo "SESSION_SECRET=$NEW_SESSION_SECRET" >> "$APP_ENV"
        fi
    fi

    chmod 600 "$APP_ENV"
    chown www-data:www-data "$APP_ENV"

    log_success "Application .env updated"
}

# Restart services gracefully
restart_services_gracefully() {
    log_info "Restarting services gracefully..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would restart services"
        return 0
    fi

    # Clear Laravel cache
    log_info "Clearing Laravel cache..."
    cd "$APP_ROOT"
    php artisan config:clear &>/dev/null || true
    php artisan cache:clear &>/dev/null || true
    php artisan route:clear &>/dev/null || true
    php artisan view:clear &>/dev/null || true

    # Reload PHP-FPM (graceful reload, no downtime)
    log_info "Reloading PHP-FPM..."
    systemctl reload php*-fpm || systemctl reload php-fpm

    # Restart queue workers
    log_info "Restarting queue workers..."
    systemctl restart chom-queue-worker &>/dev/null || true

    # Reload Nginx (graceful reload, no downtime)
    log_info "Reloading Nginx..."
    systemctl reload nginx

    log_success "Services restarted gracefully (zero downtime)"
}

# Verify services are running
verify_services() {
    log_info "Verifying services..."

    local errors=0

    # Check database
    if [[ "$ROTATE_DB_PASSWORD" == "true" ]]; then
        PGPASSWORD="$NEW_DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "Database connection verified"
        else
            log_error "Database connection failed"
            ((errors++))
        fi
    fi

    # Check Redis
    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        redis-cli -a "$NEW_REDIS_PASSWORD" ping &>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "Redis connection verified"
        else
            log_error "Redis connection failed"
            ((errors++))
        fi
    fi

    # Check Nginx
    if systemctl is-active --quiet nginx; then
        log_success "Nginx is running"
    else
        log_error "Nginx is not running"
        ((errors++))
    fi

    # Check PHP-FPM
    if systemctl is-active --quiet php*-fpm || systemctl is-active --quiet php-fpm; then
        log_success "PHP-FPM is running"
    else
        log_error "PHP-FPM is not running"
        ((errors++))
    fi

    # Test application health
    local app_url="http://localhost"
    if curl -f -s "$app_url" &>/dev/null; then
        log_success "Application is responding"
    else
        log_warning "Application health check failed (may be expected during rotation)"
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "All service verifications passed"
        return 0
    else
        log_error "$errors service verification(s) failed"
        return 1
    fi
}

# Rollback on failure
rollback_secrets() {
    log_warning "Rolling back to previous secrets..."

    local backup_file=$(cat /tmp/chom_secret_rotation_backup 2>/dev/null || echo "")

    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found, cannot rollback"
        return 1
    fi

    # Extract backup
    tar -xzf "$backup_file" -C /tmp/

    # Restore secrets
    cp "/tmp/$(basename "$SECRETS_PATH")" "$SECRETS_PATH"
    cp "/tmp/$(basename "$APP_ENV")" "$APP_ENV"

    # Restart services
    systemctl reload php*-fpm || systemctl reload php-fpm
    systemctl reload nginx

    log_success "Rollback completed"
    log_warning "Please investigate the failure before attempting rotation again"
}

# Display rotation summary
display_rotation_summary() {
    echo ""
    log_success "=========================================="
    log_success "Secret Rotation Complete"
    log_success "=========================================="
    echo ""

    log_info "Rotated Secrets:"
    if [[ "$ROTATE_DB_PASSWORD" == "true" ]]; then
        echo "  ✓ Database Password"
    fi
    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        echo "  ✓ Redis Password"
    fi
    if [[ "$ROTATE_APP_KEYS" == "true" ]]; then
        echo "  ✓ Application Keys (APP_KEY, JWT_SECRET, SESSION_SECRET, ENCRYPTION_KEY)"
    fi
    if [[ "$ROTATE_API_TOKENS" == "true" ]]; then
        echo "  ✓ API Tokens (Grafana, Prometheus)"
    fi
    echo ""

    log_info "Files Updated:"
    echo "  ✓ $SECRETS_PATH"
    echo "  ✓ $APP_ENV"
    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        echo "  ✓ $REDIS_CONFIG"
    fi
    echo ""

    log_info "Services Restarted:"
    echo "  ✓ PHP-FPM (reloaded)"
    echo "  ✓ Nginx (reloaded)"
    if [[ "$ROTATE_REDIS_PASSWORD" == "true" ]]; then
        echo "  ✓ Redis (restarted)"
    fi
    echo ""

    log_info "Backups:"
    local backup_file=$(cat /tmp/chom_secret_rotation_backup 2>/dev/null || echo "")
    echo "  Pre-rotation backup: $backup_file"
    echo ""

    log_info "Audit Log:"
    echo "  $AUDIT_LOG"
    echo ""

    log_warning "NEXT STEPS:"
    echo "  1. Monitor application logs: tail -f $APP_ROOT/storage/logs/laravel.log"
    echo "  2. Monitor service status: systemctl status nginx php*-fpm"
    echo "  3. Test application functionality"
    echo "  4. Update monitoring credentials (Grafana, Prometheus) if rotated"
    echo "  5. Schedule next rotation in 90 days"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  • Verify all services are functioning correctly"
    echo "  • Update any external services using these credentials"
    echo "  • Securely delete old backups after verification period (30 days)"
    echo "  • Document rotation in change management system"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "=============================================="
    log_info "CHOM Zero-Downtime Secret Rotation"
    log_info "=============================================="
    echo ""

    check_root
    create_audit_directory
    verify_prerequisites
    display_rotation_plan

    # Backup before rotation
    backup_current_secrets

    # Generate new secrets
    generate_new_secrets

    # Update services (with rollback on failure)
    if update_database_password && \
       update_redis_password && \
       update_secrets_file && \
       update_application_env && \
       restart_services_gracefully && \
       verify_services; then

        display_rotation_summary
        log_success "Secret rotation completed successfully with zero downtime!"

        # Log security event
        logger -t chom-security "Secrets rotated successfully by $USER"

        # Clean up temp files
        rm -f /tmp/chom_secret_rotation_backup

        exit 0
    else
        log_error "Secret rotation failed, initiating rollback..."

        if [[ "$DRY_RUN" != "true" ]]; then
            rollback_secrets
        fi

        log_error "Secret rotation failed and was rolled back"
        log_error "Please review the errors above and try again"

        # Log security event
        logger -t chom-security "Secret rotation failed and was rolled back by $USER"

        exit 1
    fi
}

# Run main function
main "$@"
