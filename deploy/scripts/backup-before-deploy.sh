#!/usr/bin/env bash
# Backup database and application files before deployment
# Usage: ./backup-before-deploy.sh [--backup-dir /path/to/backups]

set -euo pipefail
# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
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
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
APP_DIR="${APP_DIR:-/var/www/chom}"
BACKUP_DIR="${BACKUP_DIR:-${APP_DIR}/backups}"
KEEP_BACKUPS="${KEEP_BACKUPS:-10}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --keep)
            KEEP_BACKUPS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

init_deployment_log "backup-$(date +%Y%m%d_%H%M%S)"
log_section "Pre-Deployment Backup"

# Create backup directory
create_backup_directory() {
    log_step "Creating backup directory"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_success "Backup directory created: $BACKUP_DIR"
    else
        log_success "Backup directory exists: $BACKUP_DIR"
    fi
}

# Backup database
backup_database() {
    log_step "Backing up PostgreSQL database"

    if [[ ! -f "${APP_DIR}/current/.env" ]]; then
        log_warning "No .env file found, skipping database backup"
        return 0
    fi

    # Read database credentials from .env
    local db_host=$(grep "^DB_HOST=" "${APP_DIR}/current/.env" | cut -d'=' -f2 | tr -d '"')
    local db_port=$(grep "^DB_PORT=" "${APP_DIR}/current/.env" | cut -d'=' -f2 | tr -d '"')
    local db_database=$(grep "^DB_DATABASE=" "${APP_DIR}/current/.env" | cut -d'=' -f2 | tr -d '"')
    local db_username=$(grep "^DB_USERNAME=" "${APP_DIR}/current/.env" | cut -d'=' -f2 | tr -d '"')
    local db_password=$(grep "^DB_PASSWORD=" "${APP_DIR}/current/.env" | cut -d'=' -f2 | tr -d '"')

    if [[ -z "$db_database" ]]; then
        log_warning "Database name not found in .env, skipping database backup"
        return 0
    fi

    local backup_file="${BACKUP_DIR}/database_${TIMESTAMP}.sql.gz"

    log_info "Backing up database: $db_database"

    # Create database dump with compression
    if PGPASSWORD="$db_password" pg_dump \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_username" \
        -d "$db_database" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists | gzip > "$backup_file"; then

        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Database backup created: $backup_file (size: $backup_size)"

        # Store backup metadata
        echo "timestamp=$TIMESTAMP" > "${backup_file}.meta"
        echo "database=$db_database" >> "${backup_file}.meta"
        echo "size=$backup_size" >> "${backup_file}.meta"
        echo "host=$db_host" >> "${backup_file}.meta"

        return 0
    else
        log_error "Database backup failed"
        return 1
    fi
}

# Backup application files
backup_application() {
    log_step "Backing up application files"

    if [[ ! -d "${APP_DIR}/current" ]]; then
        log_warning "No current release found, skipping application backup"
        return 0
    fi

    local backup_file="${BACKUP_DIR}/application_${TIMESTAMP}.tar.gz"

    log_info "Creating application backup"

    # Create tarball of current release (excluding vendor and node_modules)
    if tar -czf "$backup_file" \
        -C "${APP_DIR}/current" \
        --exclude='vendor' \
        --exclude='node_modules' \
        --exclude='storage/logs/*' \
        --exclude='storage/framework/cache/*' \
        --exclude='storage/framework/sessions/*' \
        --exclude='storage/framework/views/*' \
        . 2>&1 | tee -a "$LOG_FILE"; then

        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Application backup created: $backup_file (size: $backup_size)"

        # Store backup metadata
        echo "timestamp=$TIMESTAMP" > "${backup_file}.meta"
        echo "size=$backup_size" >> "${backup_file}.meta"
        echo "path=${APP_DIR}/current" >> "${backup_file}.meta"

        return 0
    else
        log_error "Application backup failed"
        return 1
    fi
}

# Backup configuration files
backup_configuration() {
    log_step "Backing up configuration files"

    local backup_file="${BACKUP_DIR}/config_${TIMESTAMP}.tar.gz"

    # Files to backup
    local config_files=(
        "/etc/nginx/sites-available/chom"
        "/etc/php/8.2/fpm/pool.d/chom.conf"
        "/etc/supervisor/conf.d/chom-worker.conf"
    )

    # Filter existing files
    local existing_files=()
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            existing_files+=("$file")
        fi
    done

    if [[ ${#existing_files[@]} -eq 0 ]]; then
        log_warning "No configuration files found to backup"
        return 0
    fi

    # Create tarball of configuration files
    if sudo tar -czf "$backup_file" "${existing_files[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        sudo chown $(whoami):$(whoami) "$backup_file"

        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Configuration backup created: $backup_file (size: $backup_size)"

        # Store backup metadata
        echo "timestamp=$TIMESTAMP" > "${backup_file}.meta"
        echo "size=$backup_size" >> "${backup_file}.meta"
        echo "files=${#existing_files[@]}" >> "${backup_file}.meta"

        return 0
    else
        log_error "Configuration backup failed"
        return 1
    fi
}

# Backup environment file
backup_environment() {
    log_step "Backing up environment file"

    if [[ ! -f "${APP_DIR}/current/.env" ]]; then
        log_warning "No .env file found, skipping environment backup"
        return 0
    fi

    local backup_file="${BACKUP_DIR}/env_${TIMESTAMP}"

    # Copy .env file
    cp "${APP_DIR}/current/.env" "$backup_file"

    # Secure the backup (it contains sensitive data)
    chmod 600 "$backup_file"

    log_success "Environment backup created: $backup_file"
}

# Create backup manifest
create_backup_manifest() {
    log_step "Creating backup manifest"

    local manifest_file="${BACKUP_DIR}/backup_${TIMESTAMP}.manifest"

    cat > "$manifest_file" <<EOF
Backup Manifest
===============
Timestamp: $TIMESTAMP
Date: $(date -Iseconds)
Host: $(hostname)
User: $(whoami)

Backup Files:
-------------
EOF

    # List all backup files for this timestamp
    for file in ${BACKUP_DIR}/*_${TIMESTAMP}*; do
        if [[ -f "$file" && "$file" != *.meta ]]; then
            local size=$(du -h "$file" | cut -f1)
            echo "- $(basename "$file") ($size)" >> "$manifest_file"
        fi
    done

    log_success "Backup manifest created: $manifest_file"
}

# Rotate old backups
rotate_backups() {
    log_step "Rotating old backups (keeping last $KEEP_BACKUPS)"

    # Count backups
    local backup_count=$(ls -1 ${BACKUP_DIR}/database_*.sql.gz 2>/dev/null | wc -l)

    if [[ $backup_count -le $KEEP_BACKUPS ]]; then
        log_success "Backup count ($backup_count) is within limit ($KEEP_BACKUPS)"
        return 0
    fi

    # Get list of old backups to delete
    local backups_to_delete=$((backup_count - KEEP_BACKUPS))

    log_info "Deleting $backups_to_delete old backup(s)"

    # Find unique timestamps of old backups
    local old_timestamps=$(ls -1 ${BACKUP_DIR}/database_*.sql.gz | \
        sed 's/.*database_\([0-9_]*\)\.sql\.gz/\1/' | \
        sort | \
        head -n "$backups_to_delete")

    # Delete files for each old timestamp
    for timestamp in $old_timestamps; do
        log_info "Deleting backups from $timestamp"
        rm -f ${BACKUP_DIR}/*_${timestamp}*
    done

    log_success "Old backups rotated"
}

# Verify backups
verify_backups() {
    log_step "Verifying backups"

    local failed=0

    # Verify database backup
    if [[ -f "${BACKUP_DIR}/database_${TIMESTAMP}.sql.gz" ]]; then
        if gzip -t "${BACKUP_DIR}/database_${TIMESTAMP}.sql.gz" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Database backup is valid"
        else
            log_error "Database backup is corrupted"
            failed=1
        fi
    fi

    # Verify application backup
    if [[ -f "${BACKUP_DIR}/application_${TIMESTAMP}.tar.gz" ]]; then
        if tar -tzf "${BACKUP_DIR}/application_${TIMESTAMP}.tar.gz" > /dev/null 2>&1; then
            log_success "Application backup is valid"
        else
            log_error "Application backup is corrupted"
            failed=1
        fi
    fi

    if [[ $failed -eq 1 ]]; then
        log_error "Backup verification failed"
        return 1
    fi

    log_success "All backups verified"
    return 0
}

# Main execution
main() {
    start_timer

    print_header "Pre-Deployment Backup"

    create_backup_directory
    backup_database
    backup_application
    backup_configuration
    backup_environment
    create_backup_manifest
    verify_backups
    rotate_backups

    end_timer "Backup"

    print_header "Backup Complete"
    log_success "All backups created successfully"
    log_info "Backup location: $BACKUP_DIR"
    log_info "Backup timestamp: $TIMESTAMP"
    log_info "To restore: use rollback.sh --timestamp $TIMESTAMP"

    # Export timestamp for use by deployment script
    echo "BACKUP_TIMESTAMP=$TIMESTAMP" > "${BACKUP_DIR}/.last-backup"
}

main
