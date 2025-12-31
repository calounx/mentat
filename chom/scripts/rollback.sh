#!/bin/bash

# Rollback Script
# Reverts application to previous version with database rollback

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ROLLBACK_LOG="$PROJECT_ROOT/storage/logs/rollback_${TIMESTAMP}.log"

# Configuration
STEPS="${ROLLBACK_STEPS:-1}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
EMAIL_NOTIFICATION="${EMAIL_NOTIFICATION:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ROLLBACK_LOG"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}" | tee -a "$ROLLBACK_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}" | tee -a "$ROLLBACK_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}" | tee -a "$ROLLBACK_LOG"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ $1${NC}" | tee -a "$ROLLBACK_LOG"
}

send_notification() {
    local status=$1
    local message=$2

    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        local color="warning"
        [ "$status" = "error" ] && color="danger"
        [ "$status" = "success" ] && color="good"

        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Rollback $status\",\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
    fi

    if [ -n "$EMAIL_NOTIFICATION" ] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "Rollback $status" "$EMAIL_NOTIFICATION" || true
    fi
}

error_handler() {
    log_error "Rollback failed at line $1"
    send_notification "error" "Rollback failed at line $1. Manual intervention required!"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--steps)
            STEPS="$2"
            shift 2
            ;;
        -c|--commit)
            TARGET_COMMIT="$2"
            shift 2
            ;;
        --skip-migrations)
            SKIP_MIGRATIONS=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -s, --steps N          Rollback N commits (default: 1)"
            echo "  -c, --commit HASH      Rollback to specific commit"
            echo "  --skip-migrations      Don't rollback migrations"
            echo "  --skip-backup          Don't create backup before rollback"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "========================================="
log_info "  ROLLBACK STARTED"
log_info "========================================="
log_info "Timestamp: $TIMESTAMP"

cd "$PROJECT_ROOT"

# Check git status
if [ ! -d .git ]; then
    log_error "Not a git repository!"
    exit 1
fi

CURRENT_COMMIT=$(git rev-parse HEAD)
log_info "Current commit: $CURRENT_COMMIT"

# Determine target commit
if [ -n "${TARGET_COMMIT:-}" ]; then
    log_info "Target commit: $TARGET_COMMIT"
else
    TARGET_COMMIT=$(git rev-parse HEAD~$STEPS)
    log_info "Rolling back $STEPS commit(s) to: $TARGET_COMMIT"
fi

# Verify target commit exists
if ! git cat-file -e "$TARGET_COMMIT" 2>/dev/null; then
    log_error "Target commit $TARGET_COMMIT does not exist!"
    exit 1
fi

# Show what will be rolled back
log_info ""
log_info "Commits to be rolled back:"
git log --oneline --no-merges "$TARGET_COMMIT..$CURRENT_COMMIT" | tee -a "$ROLLBACK_LOG"
log_info ""

# Confirmation prompt (skip if non-interactive)
if [ -t 0 ]; then
    read -p "Are you sure you want to proceed with rollback? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_info "Rollback cancelled by user"
        exit 0
    fi
fi

send_notification "started" "Rollback to commit $TARGET_COMMIT initiated by $(whoami)"

# Step 1: Create backup (unless skipped)
if [ "${SKIP_BACKUP:-false}" != "true" ]; then
    log_info "Step 1: Creating backup before rollback..."

    if command -v php &> /dev/null && php artisan list | grep -q "backup:run"; then
        php artisan backup:run --only-db 2>&1 | tee -a "$ROLLBACK_LOG" || true
        log_success "Backup created"
    else
        log_warning "Backup command not available"
    fi
else
    log_warning "Skipping backup as requested"
fi

# Step 2: Enable maintenance mode
log_info "Step 2: Enabling maintenance mode..."
php artisan down --retry=60 --secret="rollback-${TIMESTAMP}" 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Maintenance mode enabled"

trap 'php artisan up' EXIT

# Step 3: Count migrations to rollback
MIGRATION_STEPS=0
if [ "${SKIP_MIGRATIONS:-false}" != "true" ]; then
    log_info "Step 3: Determining migration rollback steps..."

    # Get list of new migration files between commits
    NEW_MIGRATIONS=$(git diff --name-only --diff-filter=A "$TARGET_COMMIT" "$CURRENT_COMMIT" database/migrations/ 2>/dev/null | wc -l)

    if [ "$NEW_MIGRATIONS" -gt 0 ]; then
        MIGRATION_STEPS=$NEW_MIGRATIONS
        log_info "Found $MIGRATION_STEPS migration(s) to rollback"
    else
        log_info "No new migrations to rollback"
    fi
fi

# Step 4: Rollback migrations
if [ "$MIGRATION_STEPS" -gt 0 ]; then
    log_info "Step 4: Rolling back $MIGRATION_STEPS migration(s)..."

    for ((i=1; i<=MIGRATION_STEPS; i++)); do
        log_info "Rolling back migration $i/$MIGRATION_STEPS..."
        if php artisan migrate:rollback --step=1 --force 2>&1 | tee -a "$ROLLBACK_LOG"; then
            log_success "Migration $i rolled back"
        else
            log_error "Migration rollback failed at step $i"
            log_error "Manual database intervention may be required!"
            send_notification "error" "Migration rollback failed. Database may be in inconsistent state!"
            exit 1
        fi
    done

    log_success "All migrations rolled back successfully"
else
    log_info "Step 4: No migrations to rollback"
fi

# Step 5: Rollback code
log_info "Step 5: Rolling back code to $TARGET_COMMIT..."
git reset --hard "$TARGET_COMMIT" 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Code rolled back"

# Step 6: Reinstall dependencies
log_info "Step 6: Reinstalling dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Composer dependencies installed"

log_info "Rebuilding frontend assets..."
npm ci --production 2>&1 | tee -a "$ROLLBACK_LOG"
npm run build 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Frontend assets rebuilt"

# Step 7: Clear and rebuild caches
log_info "Step 7: Clearing and rebuilding caches..."
php artisan cache:clear 2>&1 | tee -a "$ROLLBACK_LOG"
php artisan config:clear 2>&1 | tee -a "$ROLLBACK_LOG"
php artisan route:clear 2>&1 | tee -a "$ROLLBACK_LOG"
php artisan view:clear 2>&1 | tee -a "$ROLLBACK_LOG"

php artisan config:cache 2>&1 | tee -a "$ROLLBACK_LOG"
php artisan route:cache 2>&1 | tee -a "$ROLLBACK_LOG"
php artisan view:cache 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Caches rebuilt"

# Step 8: Restart queue workers
log_info "Step 8: Restarting queue workers..."
php artisan queue:restart 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Queue workers restarted"

# Step 9: Disable maintenance mode
log_info "Step 9: Disabling maintenance mode..."
php artisan up 2>&1 | tee -a "$ROLLBACK_LOG"
log_success "Maintenance mode disabled"

trap - EXIT

# Step 10: Run health checks
log_info "Step 10: Running health checks..."
sleep 5

if "$SCRIPT_DIR/health-check.sh" 2>&1 | tee -a "$ROLLBACK_LOG"; then
    log_success "Health checks passed"
else
    log_warning "Health checks failed! Manual verification required."
fi

# Rollback summary
log_info "========================================="
log_info "  ROLLBACK COMPLETED"
log_info "========================================="
log_info "Previous commit: $CURRENT_COMMIT"
log_info "Rolled back to: $TARGET_COMMIT"
log_info "Migrations rolled back: $MIGRATION_STEPS"
log_info "Duration: $SECONDS seconds"
log_info "Log file: $ROLLBACK_LOG"

send_notification "success" "Rollback completed successfully. Rolled back from $CURRENT_COMMIT to $TARGET_COMMIT in $SECONDS seconds."

log_success "Rollback finished! 🔄"
exit 0
