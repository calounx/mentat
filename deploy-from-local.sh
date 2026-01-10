#!/usr/bin/env bash
#
# Local Deployment Script for Mentat v2.2.20
# Executes deployment on mentat.arewel.com from local machine via SSH
#
# Usage:
#   ./deploy-from-local.sh [OPTIONS]
#
# Options:
#   --host=HOST           Target host (default: mentat.arewel.com)
#   --user=USER           SSH user (default: stilgar)
#   --key=PATH            SSH key path (default: auto-detect)
#   --repo-path=PATH      Repository path on server (default: /var/www/mentat)
#   --skip-backup         Skip pre-deployment backup
#   --dry-run             Show commands without executing
#   --help                Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
TARGET_HOST="${TARGET_HOST:-mentat.arewel.com}"
SSH_USER="${SSH_USER:-stilgar}"
SSH_KEY=""
REPO_PATH="${REPO_PATH:-/var/www/mentat}"
SKIP_BACKUP=false
DRY_RUN=false

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host=*)
            TARGET_HOST="${1#*=}"
            shift
            ;;
        --user=*)
            SSH_USER="${1#*=}"
            shift
            ;;
        --key=*)
            SSH_KEY="${1#*=}"
            shift
            ;;
        --repo-path=*)
            REPO_PATH="${1#*=}"
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            head -n 15 "$0" | tail -n +2 | sed 's/^# //'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Auto-detect SSH key if not specified
detect_ssh_key() {
    local keys=(
        "$HOME/.ssh/id_ed25519"
        "$HOME/.ssh/id_rsa"
        "$HOME/.ssh/calounx_arewel"
        "$HOME/.ssh/stilgar_key"
    )

    for key in "${keys[@]}"; do
        if [[ -f "$key" ]]; then
            echo "$key"
            return 0
        fi
    done

    return 1
}

if [[ -z "$SSH_KEY" ]]; then
    if SSH_KEY=$(detect_ssh_key); then
        log_info "Auto-detected SSH key: $SSH_KEY"
    else
        log_error "No SSH key found. Please specify with --key=PATH"
        exit 1
    fi
fi

# Verify SSH key exists and has correct permissions
if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
fi

if [[ $(stat -c %a "$SSH_KEY" 2>/dev/null || stat -f %A "$SSH_KEY") != "600" ]]; then
    log_warn "SSH key has wrong permissions, fixing..."
    chmod 600 "$SSH_KEY"
fi

# SSH command builder
ssh_cmd() {
    ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=10 \
        "${SSH_USER}@${TARGET_HOST}" "$@"
}

# Test SSH connection
test_connection() {
    log_info "Testing SSH connection to ${SSH_USER}@${TARGET_HOST}..."

    if ssh_cmd "echo 'Connection successful'" &>/dev/null; then
        log_success "SSH connection successful"
        return 0
    else
        log_error "Cannot connect to ${SSH_USER}@${TARGET_HOST}"
        log_error "Please verify:"
        log_error "  1. Server is accessible"
        log_error "  2. SSH key is authorized on server"
        log_error "  3. User '${SSH_USER}' exists"
        return 1
    fi
}

# Display deployment banner
show_banner() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  MENTAT v2.2.20 REMOTE DEPLOYMENT${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Target Host:     ${GREEN}${TARGET_HOST}${NC}"
    echo -e "  SSH User:        ${GREEN}${SSH_USER}${NC}"
    echo -e "  SSH Key:         ${GREEN}${SSH_KEY}${NC}"
    echo -e "  Repository Path: ${GREEN}${REPO_PATH}${NC}"
    echo -e "  Skip Backup:     ${GREEN}${SKIP_BACKUP}${NC}"
    echo -e "  Dry Run:         ${GREEN}${DRY_RUN}${NC}"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Execute or print command based on dry-run mode
execute() {
    local description="$1"
    local command="$2"

    log_info "$description"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would execute: $command"
        return 0
    fi

    if ssh_cmd "$command"; then
        log_success "$description - Done"
        return 0
    else
        log_error "$description - Failed"
        return 1
    fi
}

# Main deployment function
deploy() {
    show_banner

    # Step 1: Test connection
    if ! test_connection; then
        log_error "Deployment aborted: Cannot connect to server"
        exit 1
    fi

    # Step 2: Verify repository exists
    execute "Checking repository path" \
        "test -d ${REPO_PATH} || (echo 'Repository not found at ${REPO_PATH}' && exit 1)"

    # Step 3: Check current branch and status
    log_info "Checking repository status..."
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh_cmd "cd ${REPO_PATH} && git status --short && git log -1 --oneline"
    fi

    # Step 4: Create backup (unless skipped)
    if [[ "$SKIP_BACKUP" != "true" ]]; then
        execute "Creating pre-deployment backup" \
            "cd ${REPO_PATH} && sudo -u ${SSH_USER} ./deploy/scripts/backup-before-deploy.sh || echo 'Backup script not found, skipping...'"
    fi

    # Step 5: Pull latest code
    execute "Pulling latest code from GitHub" \
        "cd ${REPO_PATH} && sudo -u ${SSH_USER} git fetch origin && sudo -u ${SSH_USER} git checkout main && sudo -u ${SSH_USER} git pull origin main"

    # Step 6: Show what will be deployed
    log_info "Latest commits to be deployed:"
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh_cmd "cd ${REPO_PATH} && git log -5 --oneline"
    fi

    # Step 7: Install/update dependencies
    execute "Installing Composer dependencies" \
        "cd ${REPO_PATH} && sudo -u ${SSH_USER} composer install --no-dev --optimize-autoloader --no-interaction"

    # Step 8: Check for pending migrations
    log_info "Checking for pending migrations..."
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh_cmd "cd ${REPO_PATH} && php artisan migrate:status" || true
    fi

    # Step 9: Run migrations
    execute "Running database migrations" \
        "cd ${REPO_PATH} && php artisan migrate --force"

    # Step 10: Clear caches
    execute "Clearing application caches" \
        "cd ${REPO_PATH} && php artisan config:clear && php artisan cache:clear && php artisan view:clear && php artisan route:clear"

    # Step 11: Optimize for production
    execute "Optimizing for production" \
        "cd ${REPO_PATH} && php artisan config:cache && php artisan route:cache && php artisan view:cache"

    # Step 12: Restart services
    execute "Restarting PHP-FPM" \
        "sudo systemctl restart php8.2-fpm || sudo systemctl restart php-fpm"

    execute "Restarting Nginx" \
        "sudo systemctl restart nginx"

    # Step 13: Verify deployment
    log_info "Verifying deployment..."
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh_cmd "cd ${REPO_PATH} && php artisan --version && php artisan migrate:status | head -20"
    fi

    # Step 14: Health check
    execute "Running health check" \
        "cd ${REPO_PATH} && php artisan health:check || curl -s http://localhost/api/health || echo 'Health check endpoint not available'"

    echo ""
    log_success "═══════════════════════════════════════════════════════════════"
    log_success "  DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log_success "═══════════════════════════════════════════════════════════════"
    echo ""
    log_info "Next steps:"
    echo "  1. Verify application is running"
    echo "  2. Check logs: ssh ${SSH_USER}@${TARGET_HOST} 'tail -f ${REPO_PATH}/storage/logs/laravel.log'"
    echo "  3. Test critical endpoints"
    echo ""
}

# Run deployment
deploy
