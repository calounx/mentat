#!/bin/bash

# Staging Deployment Script
# Similar to production but with additional testing features

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOYMENT_LOG="$PROJECT_ROOT/storage/logs/deployment_staging_${TIMESTAMP}.log"

# Configuration
BRANCH="${DEPLOY_BRANCH:-develop}"
MAINTENANCE_RETRY_SECONDS="${MAINTENANCE_RETRY_SECONDS:-30}"
RUN_TESTS="${RUN_TESTS:-true}"
SEED_DATABASE="${SEED_DATABASE:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

error_handler() {
    log_error "Staging deployment failed at line $1"
    exit 1
}

trap 'error_handler $LINENO' ERR

log_info "========================================="
log_info "  STAGING DEPLOYMENT STARTED"
log_info "========================================="
log_info "Timestamp: $TIMESTAMP"
log_info "Branch: $BRANCH"
log_info "Run tests: $RUN_TESTS"
log_info "Seed database: $SEED_DATABASE"

cd "$PROJECT_ROOT"

# Step 1: Pre-deployment checks
log_info "Step 1: Running pre-deployment checks..."
"$SCRIPT_DIR/pre-deployment-check.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG" || {
    log_warning "Pre-deployment checks have warnings (continuing for staging)"
}
log_success "Pre-deployment checks completed"

# Step 2: Enable maintenance mode
log_info "Step 2: Enabling maintenance mode..."
php artisan down --retry="$MAINTENANCE_RETRY_SECONDS" 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Maintenance mode enabled"

trap 'php artisan up' EXIT

# Step 3: Pull latest code
PREVIOUS_COMMIT=$(git rev-parse HEAD)
log_info "Step 3: Pulling latest code from $BRANCH..."
git fetch origin 2>&1 | tee -a "$DEPLOYMENT_LOG"
git checkout "$BRANCH" 2>&1 | tee -a "$DEPLOYMENT_LOG"
git pull origin "$BRANCH" 2>&1 | tee -a "$DEPLOYMENT_LOG"
NEW_COMMIT=$(git rev-parse HEAD)
log_success "Updated to commit: $NEW_COMMIT"

# Step 4: Install dependencies (including dev dependencies for testing)
log_info "Step 4: Installing dependencies..."
composer install --optimize-autoloader --no-interaction 2>&1 | tee -a "$DEPLOYMENT_LOG"
npm ci 2>&1 | tee -a "$DEPLOYMENT_LOG"
npm run build 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Dependencies installed"

# Step 5: Run tests (if enabled)
if [ "$RUN_TESTS" = "true" ]; then
    log_info "Step 5: Running test suite..."

    if php artisan test 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
        log_success "All tests passed"
    else
        log_error "Tests failed! Aborting deployment."
        git reset --hard "$PREVIOUS_COMMIT" 2>&1 | tee -a "$DEPLOYMENT_LOG"
        php artisan up
        exit 1
    fi
fi

# Step 6: Run migrations
log_info "Step 6: Running database migrations..."
php artisan migrate --force 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Migrations completed"

# Step 7: Seed database (if enabled)
if [ "$SEED_DATABASE" = "true" ]; then
    log_info "Step 7: Seeding database..."
    php artisan db:seed --force 2>&1 | tee -a "$DEPLOYMENT_LOG"
    log_success "Database seeded"
fi

# Step 8: Clear and cache
log_info "Step 8: Optimizing application..."
php artisan cache:clear 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan config:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan route:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"
php artisan view:cache 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Application optimized"

# Step 9: Restart queue workers
log_info "Step 9: Restarting queue workers..."
php artisan queue:restart 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Queue workers restarted"

# Step 10: Disable maintenance mode
log_info "Step 10: Disabling maintenance mode..."
php artisan up 2>&1 | tee -a "$DEPLOYMENT_LOG"
log_success "Maintenance mode disabled"

trap - EXIT

# Step 11: Run health checks
log_info "Step 11: Running health checks..."
sleep 3
"$SCRIPT_DIR/health-check.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG" || {
    log_warning "Health checks have warnings"
}

log_info "========================================="
log_info "  STAGING DEPLOYMENT COMPLETED"
log_info "========================================="
log_info "Previous commit: $PREVIOUS_COMMIT"
log_info "New commit: $NEW_COMMIT"
log_info "Duration: $SECONDS seconds"

if [ "$PREVIOUS_COMMIT" != "$NEW_COMMIT" ]; then
    log_info ""
    log_info "Changes deployed:"
    git log --oneline --no-merges "$PREVIOUS_COMMIT..$NEW_COMMIT" | tee -a "$DEPLOYMENT_LOG"
fi

log_success "Staging deployment finished! 🎉"
exit 0
