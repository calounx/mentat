#!/bin/bash

# Production Deployment Script
# Implements zero-downtime deployment with automated rollback

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOYMENT_LOG="$PROJECT_ROOT/storage/logs/deployment_${TIMESTAMP}.log"

# Configuration
BRANCH="${DEPLOY_BRANCH:-main}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
MAINTENANCE_RETRY_SECONDS="${MAINTENANCE_RETRY_SECONDS:-60}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
EMAIL_NOTIFICATION="${EMAIL_NOTIFICATION:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
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

# Notification function
send_notification() {
    local status=$1
    local message=$2

    # Slack notification
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local color="good"
        [ "$status" = "error" ] && color="danger"
        [ "$status" = "warning" ] && color="warning"

        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Deployment $status\",\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
    fi

    # Email notification (requires mailx or sendmail)
    if [ -n "$EMAIL_NOTIFICATION" ] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "Deployment $status" "$EMAIL_NOTIFICATION" || true
    fi
}

# Error handler
error_handler() {
    log_error "Deployment failed at line $1"
    send_notification "error" "Production deployment failed at line $1. Check logs: $DEPLOYMENT_LOG"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Start deployment
log_info "========================================="
log_info "  PRODUCTION DEPLOYMENT STARTED"
log_info "========================================="
log_info "Timestamp: $TIMESTAMP"
log_info "Branch: $BRANCH"
log_info "Log file: $DEPLOYMENT_LOG"

cd "$PROJECT_ROOT"

# Step 1: Pre-deployment checks
log_info "Step 1: Running pre-deployment checks..."
if "$SCRIPT_DIR/pre-deployment-check.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
    log_success "Pre-deployment checks passed"
else
    log_error "Pre-deployment checks failed"
    send_notification "error" "Pre-deployment checks failed. Deployment aborted."
    exit 1
fi

# Step 2: Create backup
log_info "Step 2: Creating database backup..."
BACKUP_FILE="backup_${TIMESTAMP}.sql"

if command -v php &> /dev/null && php artisan list | grep -q "backup:run"; then
    php artisan backup:run --only-db 2>&1 | tee -a "$DEPLOYMENT_LOG" || true
    log_success "Database backup created using Laravel backup"
else
    # Fallback to manual backup
    DB_CONNECTION=$(grep "^DB_CONNECTION=" .env | cut -d= -f2)
    DB_DATABASE=$(grep "^DB_DATABASE=" .env | cut -d= -f2)

    if [ "$DB_CONNECTION" = "mysql" ]; then
        DB_HOST=$(grep "^DB_HOST=" .env | cut -d= -f2)
        DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d= -f2)
        DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d= -f2)

        mysqldump -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" > "$PROJECT_ROOT/storage/app/backups/$BACKUP_FILE"
        log_success "Database backup created: $BACKUP_FILE"
    elif [ "$DB_CONNECTION" = "sqlite" ]; then
        cp "$PROJECT_ROOT/database/database.sqlite" "$PROJECT_ROOT/storage/app/backups/database_${TIMESTAMP}.sqlite"
        log_success "SQLite database backup created"
    fi
fi

# Step 3: Enable maintenance mode
log_info "Step 3: Enabling maintenance mode..."
php artisan down --retry="$MAINTENANCE_RETRY_SECONDS" --secret="${MAINTENANCE_SECRET:-deployment-secret-$(date +%s)}" 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Maintenance mode enabled (retry after ${MAINTENANCE_RETRY_SECONDS}s)"

# Ensure we disable maintenance mode on exit
trap 'php artisan up' EXIT

# Step 4: Store current commit for rollback
PREVIOUS_COMMIT=$(git rev-parse HEAD)
log_info "Current commit: $PREVIOUS_COMMIT"

# Step 5: Pull latest code
log_info "Step 4: Pulling latest code from $BRANCH..."
git fetch origin 2>&1 | tee -a "$DEPLOYMENT_LOG"
git checkout "$BRANCH" 2>&1 | tee -a "$DEPLOYMENT_LOG"
git pull origin "$BRANCH" 2>&1 | tee -a "$DEPLOYMENT_LOG"
NEW_COMMIT=$(git rev-parse HEAD)
log_success "Updated to commit: $NEW_COMMIT"

# Step 6: Install Composer dependencies
log_info "Step 5: Installing Composer dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Composer dependencies installed"

# Step 7: Install NPM dependencies and build assets
log_info "Step 6: Building frontend assets..."
npm ci --production 2>&1 | tee -a "$DEPLOYMENT_LOG"
npm run build 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Frontend assets built"

# Step 8: Run database migrations
log_info "Step 7: Running database migrations..."
if php artisan migrate --force 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
    log_success "Migrations completed successfully"
else
    log_error "Migration failed! Rolling back..."

    # Rollback migrations
    php artisan migrate:rollback --force 2>&1 | tee -a "$DEPLOYMENT_LOG"

    # Rollback code
    git reset --hard "$PREVIOUS_COMMIT" 2>&1 | tee -a "$DEPLOYMENT_LOG"

    # Restore dependencies
    composer install --no-dev --optimize-autoloader --no-interaction 2>&1 | tee -a "$DEPLOYMENT_LOG"

    php artisan up
    send_notification "error" "Migration failed. Rolled back to commit $PREVIOUS_COMMIT"
    exit 1
fi

# Step 9: Clear and optimize caches
log_info "Step 8: Optimizing application..."

# Clear all caches
php artisan cache:clear 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan config:clear 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan route:clear 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan view:clear 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan event:clear 2>&1 | tee -a "$DEPLOYMENT_LOG"

# Cache optimization
php artisan config:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan route:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan view:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan event:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"

log_success "Application optimized"

# Step 10: Restart queue workers
log_info "Step 9: Restarting queue workers..."
php artisan queue:restart 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Queue workers restarted"

# Step 11: Clear and warm application cache
log_info "Step 10: Warming application cache..."
if php artisan list | grep -q "cache:warm"; then
    php artisan cache:warm 2>&1 | tee -a "$DEPLOYMENT_LOG" || true
fi
log_success "Cache warming completed"

# Step 12: Disable maintenance mode
log_info "Step 11: Disabling maintenance mode..."
php artisan up 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Maintenance mode disabled"

# Remove the trap since we successfully came up
trap - EXIT

# Step 13: Run health checks
log_info "Step 12: Running post-deployment health checks..."
sleep 5  # Give the application time to fully initialize

if "$SCRIPT_DIR/health-check.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
    log_success "Health checks passed"
else
    log_warning "Health checks failed! Manual verification required."
    send_notification "warning" "Deployment completed but health checks failed. Manual verification needed."
fi

# Step 14: Clean old backups
log_info "Step 13: Cleaning old backups..."
find "$PROJECT_ROOT/storage/app/backups" -name "backup_*.sql" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
find "$PROJECT_ROOT/storage/app/backups" -name "database_*.sqlite" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
log_success "Old backups cleaned (retention: $BACKUP_RETENTION_DAYS days)"

# Deployment summary
log_info "========================================="
log_info "  DEPLOYMENT COMPLETED SUCCESSFULLY"
log_info "========================================="
log_info "Previous commit: $PREVIOUS_COMMIT"
log_info "New commit: $NEW_COMMIT"
log_info "Duration: $SECONDS seconds"
log_info "Log file: $DEPLOYMENT_LOG"

# Generate changelog if commits changed
if [ "$PREVIOUS_COMMIT" != "$NEW_COMMIT" ]; then
    log_info ""
    log_info "Changes deployed:"
    git log --oneline --no-merges "$PREVIOUS_COMMIT..$NEW_COMMIT" | tee -a "$DEPLOYMENT_LOG"
fi

send_notification "success" "Production deployment completed successfully. Deployed $(git log --oneline --no-merges "$PREVIOUS_COMMIT..$NEW_COMMIT" | wc -l) commit(s) in $SECONDS seconds."

log_success "Deployment finished! 🎉"
exit 0
