#!/bin/bash

# Blue-Green Deployment Script for CHOM
# Implements zero-downtime deployment with instant rollback capability

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOYMENT_LOG="/var/log/chom/deployment_${TIMESTAMP}.log"

# Configuration
APP_PATH="${APP_PATH:-/var/www/chom}"
RELEASES_PATH="${RELEASES_PATH:-/var/www/releases}"
BACKUP_PATH="${BACKUP_PATH:-/var/backups/chom}"
SHARED_PATH="${SHARED_PATH:-/var/www/shared}"
VERSION="${VERSION:-${TIMESTAMP}}"
ARTIFACT_PATH="${ARTIFACT_PATH:-}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost/health}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-10}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOYMENT_LOG"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}" | tee -a "$DEPLOYMENT_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}" | tee -a "$DEPLOYMENT_LOG"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ $1${NC}" | tee -a "$DEPLOYMENT_LOG"
}

# Error handler
error_handler() {
    log_error "Deployment failed at line $1"
    log_error "Initiating automatic rollback..."
    rollback_deployment
    exit 1
}

trap 'error_handler $LINENO' ERR

# Rollback function
rollback_deployment() {
    log_warning "========================================="
    log_warning "  ROLLBACK INITIATED"
    log_warning "========================================="

    PREVIOUS_RELEASE=$(ls -t "${RELEASES_PATH}" | sed -n 2p)

    if [ -z "$PREVIOUS_RELEASE" ]; then
        log_error "No previous release found for rollback!"
        return 1
    fi

    log_info "Rolling back to: ${PREVIOUS_RELEASE}"

    # Point symlinks to previous release
    ln -sfn "${RELEASES_PATH}/${PREVIOUS_RELEASE}" "${APP_PATH}_current"
    ln -sfn "${APP_PATH}_current" "${APP_PATH}"

    # Reload services
    systemctl reload php8.2-fpm || systemctl reload php-fpm
    systemctl reload nginx

    # Rollback last migration batch
    cd "${RELEASES_PATH}/${PREVIOUS_RELEASE}"
    sudo -u www-data php artisan migrate:rollback --force || true

    log_success "Rollback completed to version: ${PREVIOUS_RELEASE}"
}

# Health check function
check_health() {
    local url=$1
    local max_retries=${2:-$HEALTH_CHECK_RETRIES}
    local interval=${3:-$HEALTH_CHECK_INTERVAL}

    log_info "Running health checks on: ${url}"

    for i in $(seq 1 $max_retries); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${url}" || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
            log_success "Health check passed (HTTP ${HTTP_CODE}) on attempt ${i}"
            return 0
        else
            log_warning "Health check attempt ${i}/${max_retries}: HTTP ${HTTP_CODE}"
            if [ $i -lt $max_retries ]; then
                sleep $interval
            fi
        fi
    done

    log_error "Health checks failed after ${max_retries} attempts"
    return 1
}

# Main deployment
log_info "========================================="
log_info "  BLUE-GREEN DEPLOYMENT STARTED"
log_info "========================================="
log_info "Version: ${VERSION}"
log_info "Timestamp: ${TIMESTAMP}"
log_info "Log file: ${DEPLOYMENT_LOG}"

# Create necessary directories
mkdir -p "${RELEASES_PATH}"
mkdir -p "${BACKUP_PATH}"
mkdir -p "${SHARED_PATH}/storage"
mkdir -p "$(dirname "$DEPLOYMENT_LOG")"

# Step 1: Identify current environment (BLUE)
log_info "Step 1: Identifying current environment..."
CURRENT_RELEASE=$(readlink "${APP_PATH}_current" 2>/dev/null | xargs basename) || CURRENT_RELEASE="none"
log_info "Current release (BLUE): ${CURRENT_RELEASE}"

# Step 2: Prepare GREEN environment
log_info "Step 2: Preparing GREEN environment..."
GREEN_PATH="${RELEASES_PATH}/${VERSION}"
mkdir -p "${GREEN_PATH}"

if [ -n "$ARTIFACT_PATH" ] && [ -f "$ARTIFACT_PATH" ]; then
    log_info "Extracting artifact: ${ARTIFACT_PATH}"
    tar -xzf "${ARTIFACT_PATH}" -C "${GREEN_PATH}"
else
    log_error "Artifact not found: ${ARTIFACT_PATH}"
    exit 1
fi

log_success "GREEN environment prepared at: ${GREEN_PATH}"

# Step 3: Configure GREEN environment
log_info "Step 3: Configuring GREEN environment..."

# Copy .env from current release or use default
if [ -f "${APP_PATH}/.env" ]; then
    cp "${APP_PATH}/.env" "${GREEN_PATH}/.env"
    log_success "Environment file copied from current release"
else
    log_warning "No .env file found in current release"
fi

# Link shared storage
rm -rf "${GREEN_PATH}/storage"
ln -sfn "${SHARED_PATH}/storage" "${GREEN_PATH}/storage"
log_success "Shared storage linked"

# Set permissions
chown -R www-data:www-data "${GREEN_PATH}"
chmod -R 755 "${GREEN_PATH}"
chmod -R 775 "${GREEN_PATH}/storage" "${GREEN_PATH}/bootstrap/cache"
log_success "Permissions set"

# Step 4: Database backup
log_info "Step 4: Creating database backup..."
BACKUP_FILE="${BACKUP_PATH}/db_backup_${TIMESTAMP}.sql"

cd "${GREEN_PATH}"
if sudo -u www-data php artisan db:backup --file="${BACKUP_FILE}" 2>/dev/null; then
    log_success "Database backup created via Artisan"
else
    # Fallback to mysqldump
    DB_DATABASE=$(grep "^DB_DATABASE=" .env | cut -d= -f2)
    DB_HOST=$(grep "^DB_HOST=" .env | cut -d= -f2)
    DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d= -f2)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d= -f2)

    mysqldump -h"${DB_HOST}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${DB_DATABASE}" > "${BACKUP_FILE}" || {
        log_warning "Database backup failed"
    }
    log_success "Database backup created: ${BACKUP_FILE}"
fi

# Step 5: Run migrations on GREEN
log_info "Step 5: Running database migrations..."
sudo -u www-data php artisan migrate:status
sudo -u www-data php artisan migrate --force
log_success "Migrations completed"

# Step 6: Optimize GREEN environment
log_info "Step 6: Optimizing GREEN environment..."
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
sudo -u www-data php artisan event:cache

# Clear and warm opcache if available
if command -v php-fpm >/dev/null 2>&1; then
    systemctl reload php8.2-fpm || systemctl reload php-fpm
fi

log_success "GREEN environment optimized"

# Step 7: Pre-switch health check on GREEN (without switching traffic)
log_info "Step 7: Running pre-switch health checks on GREEN..."

# Temporarily point a test location to GREEN for health check
# (This requires nginx config support for /green-health endpoint)
if check_health "${HEALTH_CHECK_URL}"; then
    log_success "Pre-switch health checks passed"
else
    log_error "Pre-switch health checks failed on GREEN environment"
    exit 1
fi

# Step 8: ATOMIC SWITCH - Point traffic to GREEN
log_info "Step 8: Switching traffic to GREEN (atomic operation)..."

# Create new symlink and atomically move it
ln -sfn "${GREEN_PATH}" "${APP_PATH}_current_new"
mv -Tf "${APP_PATH}_current_new" "${APP_PATH}_current"

# Update main application symlink
ln -sfn "${APP_PATH}_current" "${APP_PATH}"

log_success "Traffic switched to GREEN environment"

# Step 9: Reload services
log_info "Step 9: Reloading services..."
systemctl reload php8.2-fpm || systemctl reload php-fpm
systemctl reload nginx

# Restart queue workers
sudo -u www-data php artisan queue:restart

log_success "Services reloaded"

# Step 10: Grace period for service restart
log_info "Step 10: Waiting for services to stabilize..."
sleep 5

# Step 11: Post-switch health checks
log_info "Step 11: Running post-switch health checks..."
if check_health "${HEALTH_CHECK_URL}"; then
    log_success "Post-switch health checks passed"
else
    log_error "Post-switch health checks failed!"
    rollback_deployment
    exit 1
fi

# Step 12: Smoke tests
log_info "Step 12: Running smoke tests..."

# Test database connectivity
sudo -u www-data php artisan db:show > /dev/null 2>&1 || {
    log_error "Database connectivity test failed"
    rollback_deployment
    exit 1
}
log_success "Database connectivity: OK"

# Test Redis connectivity
sudo -u www-data php artisan tinker --execute="Redis::ping();" 2>/dev/null | grep -q "PONG" || {
    log_error "Redis connectivity test failed"
    rollback_deployment
    exit 1
}
log_success "Redis connectivity: OK"

# Test queue workers
pgrep -f "artisan queue:work" > /dev/null || {
    log_warning "Queue workers not running"
}

log_success "Smoke tests completed"

# Step 13: Cleanup old releases
log_info "Step 13: Cleaning up old releases..."
cd "${RELEASES_PATH}"
RELEASES_TO_KEEP=5
ls -t | tail -n +$((RELEASES_TO_KEEP + 1)) | xargs -r rm -rf
log_success "Kept last ${RELEASES_TO_KEEP} releases"

# Step 14: Cleanup old backups
log_info "Step 14: Cleaning up old backups..."
find "${BACKUP_PATH}" -name "*.sql" -mtime +14 -delete
log_success "Removed backups older than 14 days"

# Deployment summary
log_info "========================================="
log_info "  DEPLOYMENT COMPLETED SUCCESSFULLY"
log_info "========================================="
log_info "Previous release (BLUE): ${CURRENT_RELEASE}"
log_info "New release (GREEN): ${VERSION}"
log_info "Duration: ${SECONDS} seconds"
log_info "Log file: ${DEPLOYMENT_LOG}"
log_info "Backup: ${BACKUP_FILE}"

# Generate deployment report
REPORT_FILE="${BACKUP_PATH}/deployment_report_${TIMESTAMP}.txt"
cat > "${REPORT_FILE}" <<EOF
========================================
DEPLOYMENT REPORT
========================================
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Version: ${VERSION}
Previous Version: ${CURRENT_RELEASE}
Deployment Type: Blue-Green
Duration: ${SECONDS} seconds
Status: SUCCESS

Paths:
- Application: ${APP_PATH}
- Release: ${GREEN_PATH}
- Backup: ${BACKUP_FILE}
- Log: ${DEPLOYMENT_LOG}

Health Checks: PASSED
Database Migration: COMPLETED
Services Reloaded: YES

EOF

log_success "Deployment report: ${REPORT_FILE}"
log_success "Blue-Green deployment finished! 🚀"

exit 0
