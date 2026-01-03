#!/usr/bin/env bash
# Rollback CHOM application to previous release
# Usage: ./rollback.sh [--to-release RELEASE_ID] [--restore-database]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"
source "${SCRIPT_DIR}/../utils/notifications.sh"

# Configuration
APP_DIR="${APP_DIR:-/var/www/chom}"
RELEASES_DIR="${APP_DIR}/releases"
CURRENT_LINK="${APP_DIR}/current"
BACKUP_DIR="${APP_DIR}/backups"
PHP_VERSION="${PHP_VERSION:-8.2}"

# Parse arguments
ROLLBACK_TO=""
RESTORE_DATABASE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --to-release)
            ROLLBACK_TO="$2"
            shift 2
            ;;
        --restore-database)
            RESTORE_DATABASE=true
            shift
            ;;
        --timestamp)
            # Find release by backup timestamp
            ROLLBACK_TO=$(find "$RELEASES_DIR" -maxdepth 1 -type d -name "*$2*" | head -1 | xargs basename)
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

init_deployment_log "rollback-$(date +%Y%m%d_%H%M%S)"
log_section "Application Rollback"

notify_rollback "${ENVIRONMENT:-production}" "User initiated rollback"

# Get current release
get_current_release() {
    if [[ -L "$CURRENT_LINK" ]]; then
        basename "$(readlink -f "$CURRENT_LINK")"
    else
        echo ""
    fi
}

# Get previous release
get_previous_release() {
    local current_release=$(get_current_release)

    # List all releases sorted by timestamp (newest first)
    local releases=$(ls -1t "$RELEASES_DIR")

    # Get the release before current
    local found_current=false
    for release in $releases; do
        if [[ "$found_current" == true ]]; then
            echo "$release"
            return 0
        fi

        if [[ "$release" == "$current_release" ]]; then
            found_current=true
        fi
    done

    echo ""
}

# List available releases
list_releases() {
    log_step "Available releases"

    local current_release=$(get_current_release)

    ls -1t "$RELEASES_DIR" | while read release; do
        if [[ "$release" == "$current_release" ]]; then
            log_info "  → $release (current)"
        else
            log_info "    $release"
        fi
    done
}

# Determine rollback target
determine_rollback_target() {
    log_step "Determining rollback target"

    if [[ -n "$ROLLBACK_TO" ]]; then
        if [[ -d "${RELEASES_DIR}/${ROLLBACK_TO}" ]]; then
            log_success "Rolling back to specified release: $ROLLBACK_TO"
            echo "$ROLLBACK_TO"
            return 0
        else
            log_error "Specified release not found: $ROLLBACK_TO"
            list_releases
            exit 1
        fi
    fi

    # Get previous release
    local previous_release=$(get_previous_release)

    if [[ -z "$previous_release" ]]; then
        log_error "No previous release found to rollback to"
        list_releases
        exit 1
    fi

    log_success "Rolling back to previous release: $previous_release"
    echo "$previous_release"
}

# Restore database from backup
restore_database() {
    local backup_timestamp="$1"

    log_step "Restoring database from backup"

    # Find database backup
    local backup_file=$(find "$BACKUP_DIR" -name "database_${backup_timestamp}*.sql.gz" | head -1)

    if [[ -z "$backup_file" ]]; then
        log_warning "No database backup found for timestamp: $backup_timestamp"
        log_warning "Skipping database restore"
        return 0
    fi

    log_info "Found database backup: $backup_file"

    # Read database credentials from current .env
    if [[ ! -f "${CURRENT_LINK}/.env" ]]; then
        log_error ".env file not found"
        return 1
    fi

    local db_host=$(grep "^DB_HOST=" "${CURRENT_LINK}/.env" | cut -d'=' -f2 | tr -d '"')
    local db_port=$(grep "^DB_PORT=" "${CURRENT_LINK}/.env" | cut -d'=' -f2 | tr -d '"')
    local db_database=$(grep "^DB_DATABASE=" "${CURRENT_LINK}/.env" | cut -d'=' -f2 | tr -d '"')
    local db_username=$(grep "^DB_USERNAME=" "${CURRENT_LINK}/.env" | cut -d'=' -f2 | tr -d '"')
    local db_password=$(grep "^DB_PASSWORD=" "${CURRENT_LINK}/.env" | cut -d'=' -f2 | tr -d '"')

    # Create a backup of current database before restore
    log_info "Creating safety backup of current database"
    local safety_backup="${BACKUP_DIR}/database_pre_rollback_$(date +%Y%m%d_%H%M%S).sql.gz"

    PGPASSWORD="$db_password" pg_dump \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_username" \
        -d "$db_database" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists | gzip > "$safety_backup"

    log_success "Safety backup created: $safety_backup"

    # Restore database
    log_info "Restoring database from backup"

    if gunzip -c "$backup_file" | PGPASSWORD="$db_password" psql \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_username" \
        -d "$db_database" \
        2>&1 | tee -a "$LOG_FILE"; then

        log_success "Database restored successfully"
        return 0
    else
        log_error "Database restore failed"
        log_error "Rolling back to safety backup"

        # Restore safety backup
        gunzip -c "$safety_backup" | PGPASSWORD="$db_password" psql \
            -h "$db_host" \
            -p "$db_port" \
            -U "$db_username" \
            -d "$db_database"

        return 1
    fi
}

# Switch to previous release
switch_release() {
    local target_release="$1"
    local target_path="${RELEASES_DIR}/${target_release}"

    log_step "Switching to release: $target_release"

    if [[ ! -d "$target_path" ]]; then
        log_error "Release directory not found: $target_path"
        return 1
    fi

    # Create new symlink
    local temp_link="${APP_DIR}/current.tmp.$$"

    ln -sf "$target_path" "$temp_link"

    # Atomic swap
    mv -Tf "$temp_link" "$CURRENT_LINK"

    log_success "Release switched to: $target_release"
}

# Reload services
reload_services() {
    log_step "Reloading services"

    # Reload PHP-FPM
    log_info "Reloading PHP-FPM"
    sudo systemctl reload php${PHP_VERSION}-fpm

    # Restart queue workers via supervisor
    log_info "Restarting queue workers"
    if command -v supervisorctl &> /dev/null; then
        sudo supervisorctl restart chom-worker:* 2>&1 | tee -a "$LOG_FILE" || true
    fi

    # Clear application cache
    log_info "Clearing application cache"
    cd "$CURRENT_LINK"
    php artisan cache:clear
    php artisan config:clear
    php artisan view:clear
    php artisan route:clear

    log_success "Services reloaded"
}

# Run health checks
run_health_checks() {
    log_step "Running health checks on rolled back release"

    if bash "${SCRIPT_DIR}/health-check.sh" --release-path "$CURRENT_LINK"; then
        log_success "Health checks passed"
        return 0
    else
        log_error "Health checks failed after rollback"
        return 1
    fi
}

# Main execution
main() {
    start_timer

    print_header "CHOM Application Rollback"

    local current_release=$(get_current_release)
    log_info "Current release: ${current_release:-none}"

    # List available releases
    list_releases

    # Determine rollback target
    local target_release=$(determine_rollback_target)

    # Confirm rollback
    print_header "Rollback Confirmation"
    log_warning "You are about to rollback from '$current_release' to '$target_release'"

    if [[ "$RESTORE_DATABASE" == true ]]; then
        log_warning "Database will be restored from backup"
    fi

    # In automated deployments, skip confirmation
    if [[ "${AUTO_CONFIRM:-false}" != "true" ]]; then
        read -p "Are you sure? (yes/no): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Rollback cancelled by user"
            exit 0
        fi
    fi

    # Perform rollback
    log_section "Performing Rollback"

    # Restore database if requested
    if [[ "$RESTORE_DATABASE" == true ]]; then
        # Extract timestamp from release name
        local timestamp=$(echo "$target_release" | grep -oE '[0-9]{8}_[0-9]{6}')

        if [[ -n "$timestamp" ]]; then
            restore_database "$timestamp"
        else
            log_warning "Could not extract timestamp from release name, skipping database restore"
        fi
    fi

    # Switch release
    switch_release "$target_release"

    # Reload services
    reload_services

    # Run health checks
    if run_health_checks; then
        end_timer "Rollback"

        print_header "Rollback Successful"
        log_success "Application rolled back to: $target_release"
        log_success "All services reloaded and health checks passed"

        exit 0
    else
        log_error "Rollback completed but health checks failed"
        log_warning "Manual intervention may be required"

        exit 1
    fi
}

main
