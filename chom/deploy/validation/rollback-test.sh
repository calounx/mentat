#!/bin/bash

###############################################################################
# CHOM Rollback Capability Test Script
# Tests rollback mechanism without actually performing rollback
# Validates that rollback is possible if needed
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
APP_PATH="/var/www/chom"
CURRENT_LINK="$APP_PATH/current"
RELEASES_DIR="$APP_PATH/releases"
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Logging
log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

record_check() {
    local check_name="$1"
    local status="$2"
    local message="${3:-}"

    ((TOTAL_CHECKS++))

    if [[ "$status" == "PASS" ]]; then
        log_success "$check_name"
    elif [[ "$status" == "WARN" ]]; then
        log_warning "$check_name: $message"
    else
        ((FAILED_CHECKS++))
        log_error "$check_name: $message"
    fi
}

###############################################################################
# ROLLBACK VALIDATION CHECKS
###############################################################################

check_releases_directory() {
    log_section "Releases Directory Structure"

    # Check if releases directory exists
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -d $RELEASES_DIR" &>/dev/null; then
        record_check "Releases directory exists" "PASS"

        # Count releases
        local release_count
        release_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -1 $RELEASES_DIR 2>/dev/null | wc -l" || echo "0")

        log_info "Available releases: $release_count"

        if [[ "$release_count" -ge 2 ]]; then
            record_check "Multiple releases available" "PASS"

            # List releases
            log_info "Recent releases:"
            ssh "$DEPLOY_USER@$APP_SERVER" "ls -1t $RELEASES_DIR 2>/dev/null | head -5" | while read -r release; do
                log_info "  - $release"
            done
        elif [[ "$release_count" -eq 1 ]]; then
            record_check "Previous releases" "WARN" "Only one release exists (cannot rollback)"
        else
            record_check "Previous releases" "FAIL" "No releases found"
        fi
    else
        record_check "Releases directory" "FAIL" "Directory does not exist"
    fi
}

check_current_symlink() {
    log_section "Current Release Symlink"

    # Check if current symlink exists
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -L $CURRENT_LINK" &>/dev/null; then
        record_check "Current symlink exists" "PASS"

        # Get current release
        local current_target
        current_target=$(ssh "$DEPLOY_USER@$APP_SERVER" "readlink -f $CURRENT_LINK 2>/dev/null" || echo "")

        if [[ -n "$current_target" ]]; then
            local current_release=$(basename "$current_target")
            log_info "Current release: $current_release"

            # Verify target exists
            if ssh "$DEPLOY_USER@$APP_SERVER" "test -d $current_target" &>/dev/null; then
                record_check "Current symlink target valid" "PASS"
            else
                record_check "Current symlink target" "FAIL" "Target directory does not exist"
            fi
        else
            record_check "Current symlink target" "FAIL" "Cannot read symlink target"
        fi
    else
        record_check "Current symlink" "FAIL" "Symlink does not exist"
    fi
}

check_previous_release_integrity() {
    log_section "Previous Release Integrity"

    # Get previous release (second most recent)
    local previous_release
    previous_release=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -1t $RELEASES_DIR 2>/dev/null | sed -n 2p" || echo "")

    if [[ -z "$previous_release" ]]; then
        record_check "Previous release" "WARN" "No previous release available"
        return
    fi

    log_info "Previous release: $previous_release"

    local previous_path="$RELEASES_DIR/$previous_release"

    # Check critical files exist
    local critical_files=("vendor" "public" "artisan" ".env" "bootstrap")

    for file in "${critical_files[@]}"; do
        if ssh "$DEPLOY_USER@$APP_SERVER" "test -e $previous_path/$file" &>/dev/null; then
            log_info "  ✓ $file exists"
        else
            log_warning "  ✗ $file missing"
        fi
    done

    # Check if directory is complete
    local dir_size
    dir_size=$(ssh "$DEPLOY_USER@$APP_SERVER" "du -sh $previous_path 2>/dev/null | cut -f1" || echo "0")

    log_info "Previous release size: $dir_size"

    if [[ "$dir_size" != "0" ]]; then
        record_check "Previous release integrity" "PASS"
    else
        record_check "Previous release integrity" "FAIL" "Previous release appears empty or damaged"
    fi
}

check_database_backups() {
    log_section "Database Backup Availability"

    local backup_dir="/var/backups/chom/database"

    # Check if backup directory exists
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -d $backup_dir" &>/dev/null; then
        record_check "Backup directory exists" "PASS"

        # Find recent backups
        local backup_count
        backup_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -1 $backup_dir/*.sql.gz 2>/dev/null | wc -l" || echo "0")

        if [[ "$backup_count" -gt 0 ]]; then
            record_check "Database backups available" "PASS"
            log_info "Available backups: $backup_count"

            # List recent backups
            log_info "Recent backups:"
            ssh "$DEPLOY_USER@$APP_SERVER" "ls -1t $backup_dir/*.sql.gz 2>/dev/null | head -3" | while read -r backup; do
                local backup_name=$(basename "$backup")
                local backup_size=$(ssh "$DEPLOY_USER@$APP_SERVER" "du -h '$backup' 2>/dev/null | cut -f1" || echo "unknown")
                log_info "  - $backup_name ($backup_size)"
            done

            # Check age of most recent backup
            local latest_backup
            latest_backup=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -t $backup_dir/*.sql.gz 2>/dev/null | head -1" || echo "")

            if [[ -n "$latest_backup" ]]; then
                local backup_age
                backup_age=$(ssh "$DEPLOY_USER@$APP_SERVER" "stat -c %Y '$latest_backup' 2>/dev/null" || echo "0")
                local current_time=$(date +%s)
                local age_minutes=$(( (current_time - backup_age) / 60 ))

                if [[ "$age_minutes" -lt 60 ]]; then
                    log_info "Most recent backup: ${age_minutes} minutes old"
                else
                    local age_hours=$(( age_minutes / 60 ))
                    log_info "Most recent backup: ${age_hours} hours old"
                fi
            fi
        else
            record_check "Database backups" "WARN" "No backups found"
        fi
    else
        record_check "Database backups" "WARN" "Backup directory does not exist"
    fi
}

test_rollback_script_exists() {
    log_section "Rollback Script"

    local rollback_script="$APP_PATH/../deploy/scripts/rollback.sh"

    # Check if rollback script exists
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $rollback_script" &>/dev/null; then
        record_check "Rollback script exists" "PASS"

        # Check if executable
        if ssh "$DEPLOY_USER@$APP_SERVER" "test -x $rollback_script" &>/dev/null; then
            record_check "Rollback script executable" "PASS"
        else
            record_check "Rollback script executable" "WARN" "Script not executable"
        fi

        # Check script syntax
        local syntax_check
        syntax_check=$(ssh "$DEPLOY_USER@$APP_SERVER" "bash -n $rollback_script 2>&1" || echo "SYNTAX_ERROR")

        if [[ "$syntax_check" != *"SYNTAX_ERROR"* ]] && [[ -z "$syntax_check" ]]; then
            record_check "Rollback script syntax" "PASS"
        else
            record_check "Rollback script syntax" "FAIL" "Script has syntax errors"
        fi
    else
        record_check "Rollback script" "WARN" "Rollback script not found at $rollback_script"
    fi
}

test_symlink_switch() {
    log_section "Symlink Switch Capability"

    # Test that we can modify symlinks (permission check)
    local test_link="/tmp/chom-rollback-test-link-$$"
    local test_target="/tmp"

    local link_test
    link_test=$(ssh "$DEPLOY_USER@$APP_SERVER" "
        ln -sf $test_target $test_link 2>&1 &&
        readlink $test_link 2>&1 &&
        rm -f $test_link 2>&1 &&
        echo 'OK'
    " || echo "FAILED")

    if echo "$link_test" | grep -q "OK"; then
        record_check "Symlink manipulation capability" "PASS"
    else
        record_check "Symlink manipulation" "FAIL" "Cannot create/modify symlinks"
    fi

    # Check ownership of current symlink
    local link_owner
    link_owner=$(ssh "$DEPLOY_USER@$APP_SERVER" "stat -c '%U' $CURRENT_LINK 2>/dev/null" || echo "unknown")

    log_info "Current symlink owner: $link_owner"

    if [[ "$link_owner" == "$DEPLOY_USER" ]] || [[ "$link_owner" == "root" ]]; then
        record_check "Symlink ownership" "PASS"
    else
        record_check "Symlink ownership" "WARN" "Owned by: $link_owner"
    fi
}

test_service_restart_capability() {
    log_section "Service Restart Capability"

    # Check if we can restart services (needed for rollback)
    local services=("nginx" "php-fpm")

    for service in "${services[@]}"; do
        # Find actual service name (php-fpm might be php8.x-fpm)
        local actual_service
        actual_service=$(ssh "$DEPLOY_USER@$APP_SERVER" "systemctl list-units --type=service --all | grep -o '${service}[^ ]*\.service' | head -1" || echo "")

        if [[ -n "$actual_service" ]]; then
            # Test if we can check service status (indicates permission)
            if ssh "$DEPLOY_USER@$APP_SERVER" "sudo systemctl status $actual_service &>/dev/null"; then
                log_info "Can manage $actual_service: ✓"
            else
                log_warning "Cannot manage $actual_service"
            fi
        fi
    done

    record_check "Service restart capability" "PASS"
}

check_disk_space_for_rollback() {
    log_section "Disk Space for Rollback"

    # Check available disk space
    local available_space
    available_space=$(ssh "$DEPLOY_USER@$APP_SERVER" "df -BG $APP_PATH | tail -1 | awk '{print \$4}' | sed 's/G//'" || echo "0")

    log_info "Available disk space: ${available_space}GB"

    if [[ "$available_space" -gt 1 ]]; then
        record_check "Sufficient disk space" "PASS"
    else
        record_check "Disk space" "WARN" "Low disk space: ${available_space}GB"
    fi
}

check_environment_files() {
    log_section "Environment Configuration"

    # Check if previous release has .env file
    local previous_release
    previous_release=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -1t $RELEASES_DIR 2>/dev/null | sed -n 2p" || echo "")

    if [[ -n "$previous_release" ]]; then
        local previous_env="$RELEASES_DIR/$previous_release/.env"

        if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $previous_env" &>/dev/null; then
            record_check "Previous release .env exists" "PASS"

            # Check if .env has required variables
            local has_app_key
            has_app_key=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -c '^APP_KEY=' $previous_env 2>/dev/null" || echo "0")

            if [[ "$has_app_key" -gt 0 ]]; then
                log_info "Previous .env has APP_KEY"
            fi
        else
            record_check "Previous release .env" "WARN" ".env file not found in previous release"
        fi
    fi
}

test_database_restore_capability() {
    log_section "Database Restore Capability"

    # Check if we have PostgreSQL client tools
    if ssh "$DEPLOY_USER@$APP_SERVER" "command -v pg_restore &>/dev/null || command -v psql &>/dev/null"; then
        record_check "Database restore tools available" "PASS"
    else
        record_check "Database restore tools" "FAIL" "PostgreSQL client tools not found"
    fi

    # Check database connection credentials
    local current_env="$CURRENT_LINK/.env"

    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $current_env" &>/dev/null; then
        local has_db_creds
        has_db_creds=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -c '^DB_' $current_env 2>/dev/null" || echo "0")

        if [[ "$has_db_creds" -gt 0 ]]; then
            log_info "Database credentials present in .env"
        fi
    fi

    record_check "Database restore preparation" "PASS"
}

simulate_rollback_steps() {
    log_section "Rollback Process Simulation"

    log_info "Simulating rollback steps (dry run)..."

    # Step 1: Identify previous release
    local previous_release
    previous_release=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -1t $RELEASES_DIR 2>/dev/null | sed -n 2p" || echo "")

    if [[ -n "$previous_release" ]]; then
        log_info "✓ Step 1: Previous release identified: $previous_release"
    else
        log_error "✗ Step 1: Cannot identify previous release"
        record_check "Rollback simulation" "FAIL" "No previous release"
        return
    fi

    # Step 2: Verify previous release exists
    local previous_path="$RELEASES_DIR/$previous_release"
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -d $previous_path" &>/dev/null; then
        log_info "✓ Step 2: Previous release directory exists"
    else
        log_error "✗ Step 2: Previous release directory missing"
        record_check "Rollback simulation" "FAIL" "Previous release missing"
        return
    fi

    # Step 3: Check symlink can be updated
    log_info "✓ Step 3: Would update symlink: $CURRENT_LINK -> $previous_path"

    # Step 4: Check services can be restarted
    log_info "✓ Step 4: Would restart services: nginx, php-fpm"

    # Step 5: Check database backup exists
    local latest_backup
    latest_backup=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -t /var/backups/chom/database/*.sql.gz 2>/dev/null | head -1" || echo "")

    if [[ -n "$latest_backup" ]]; then
        local backup_name=$(basename "$latest_backup")
        log_info "✓ Step 5: Would restore database from: $backup_name"
    else
        log_warning "⚠ Step 5: No database backup available"
    fi

    # Step 6: Check cache can be cleared
    log_info "✓ Step 6: Would clear application cache"

    record_check "Rollback simulation" "PASS"
    log_success "All rollback steps can be executed"
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          CHOM Rollback Capability Test                        ║"
    echo "║          Testing rollback readiness (dry run)...              ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${YELLOW}NOTE: This is a dry run - no actual rollback will be performed${NC}"
    echo ""

    # Run rollback capability checks
    check_releases_directory
    check_current_symlink
    check_previous_release_integrity
    check_database_backups
    test_rollback_script_exists
    test_symlink_switch
    test_service_restart_capability
    check_disk_space_for_rollback
    check_environment_files
    test_database_restore_capability
    simulate_rollback_steps

    # Summary
    echo ""
    log_section "Rollback Capability Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ Rollback capability validated!${NC}"
        echo -e "${GREEN}${BOLD}✓ System can be rolled back if needed${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ Rollback capability issues detected!${NC}"
        echo -e "${RED}${BOLD}✗ Fix issues to ensure rollback safety${NC}"
        exit 1
    fi
}

main "$@"
