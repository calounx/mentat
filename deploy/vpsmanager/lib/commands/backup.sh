#!/usr/bin/env bash
# Backup management commands for vpsmanager

# Configuration
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/sites}"
SITES_ROOT="${SITES_ROOT:-/var/www/sites}"

# Ensure backup directory exists
ensure_backup_dir() {
    local domain="$1"
    local backup_dir="${BACKUP_ROOT}/${domain}"

    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        chown www-data:www-data "$backup_dir"
        chmod 750 "$backup_dir"
    fi

    echo "$backup_dir"
}

# Generate backup ID
generate_backup_id() {
    date +%Y%m%d_%H%M%S
}

# Get backup metadata
get_backup_metadata() {
    local backup_path="$1"
    local metadata_file="${backup_path}.meta"

    if [[ -f "$metadata_file" ]]; then
        cat "$metadata_file"
    else
        echo "{}"
    fi
}

# Save backup metadata
save_backup_metadata() {
    local backup_path="$1"
    local domain="$2"
    local backup_type="$3"
    local size_bytes="$4"
    local metadata_file="${backup_path}.meta"

    local created_at
    created_at=$(date -Iseconds)

    cat > "$metadata_file" <<EOF
{
    "backup_id": "$(basename "$backup_path" .tar.gz)",
    "domain": "${domain}",
    "type": "${backup_type}",
    "size_bytes": ${size_bytes},
    "created_at": "${created_at}",
    "path": "${backup_path}"
}
EOF
}

# Backup site files
backup_files() {
    local domain="$1"
    local backup_dir="$2"
    local backup_id="$3"
    local site_root="${SITES_ROOT}/${domain}"

    if [[ ! -d "$site_root" ]]; then
        log_error "Site directory not found: ${site_root}"
        return 1
    fi

    local backup_file="${backup_dir}/${backup_id}_files.tar.gz"

    log_info "Backing up files for ${domain}"

    if tar -czf "$backup_file" -C "$(dirname "$site_root")" "$(basename "$site_root")" 2>&1; then
        local size_bytes
        size_bytes=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo 0)
        save_backup_metadata "$backup_file" "$domain" "files" "$size_bytes"
        log_info "Files backup completed: ${backup_file} ($(numfmt --to=iec "$size_bytes" 2>/dev/null || echo "${size_bytes}B"))"
        echo "$backup_file"
        return 0
    else
        log_error "Files backup failed for ${domain}"
        return 1
    fi
}

# Backup database
backup_database() {
    local domain="$1"
    local backup_dir="$2"
    local backup_id="$3"

    # Get database name from registry
    local site_info db_name
    site_info=$(get_site_info "$domain")

    if command -v jq &> /dev/null; then
        db_name=$(echo "$site_info" | jq -r '.db_name // empty')
    else
        db_name="site_$(domain_to_dbname "$domain")"
    fi

    if [[ -z "$db_name" ]]; then
        log_warn "No database found for ${domain}"
        return 0
    fi

    local backup_file="${backup_dir}/${backup_id}_database.sql.gz"

    log_info "Backing up database for ${domain}"

    # Use mktemp for secure temporary file
    local temp_sql
    temp_sql=$(mktemp -t "vpsmanager_backup_XXXXXX.sql") || {
        log_error "Failed to create temporary file"
        return 1
    }

    if dump_database "$db_name" "$temp_sql" && gzip -c "$temp_sql" > "$backup_file"; then
        rm -f "$temp_sql"
        local size_bytes
        size_bytes=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo 0)
        save_backup_metadata "$backup_file" "$domain" "database" "$size_bytes"
        log_info "Database backup completed: ${backup_file}"
        echo "$backup_file"
        return 0
    else
        rm -f "$temp_sql"
        log_error "Database backup failed for ${domain}"
        return 1
    fi
}

# ============================================================================
# Command handlers
# ============================================================================

# backup:create command
# Supports: backup:create <domain> or backup:create --site=<domain>
cmd_backup_create() {
    local domain=""
    local backup_type="full"

    # Parse arguments (supports both positional and --site= format)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --site=*)
                domain="${1#*=}"
                shift
                ;;
            --site)
                domain="$2"
                shift 2
                ;;
            --type=*)
                backup_type="${1#*=}"
                shift
                ;;
            --type)
                backup_type="$2"
                shift 2
                ;;
            --components=*)
                # Map components to backup_type
                local components="${1#*=}"
                if [[ "$components" == *"database"* && "$components" == *"files"* ]]; then
                    backup_type="full"
                elif [[ "$components" == *"database"* ]]; then
                    backup_type="database"
                elif [[ "$components" == *"files"* ]]; then
                    backup_type="files"
                fi
                shift
                ;;
            --components)
                local components="$2"
                if [[ "$components" == *"database"* && "$components" == *"files"* ]]; then
                    backup_type="full"
                elif [[ "$components" == *"database"* ]]; then
                    backup_type="database"
                elif [[ "$components" == *"files"* ]]; then
                    backup_type="files"
                fi
                shift 2
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$domain" ]]; then
        json_error "Domain is required (use --site=<domain>)" "MISSING_DOMAIN"
        return 1
    fi

    # Validate backup type
    local validation_error
    if ! validation_error=$(validate_backup_type "$backup_type"); then
        json_error "$validation_error" "INVALID_BACKUP_TYPE"
        return 1
    fi

    # Check if site exists
    if ! site_exists "$domain"; then
        json_error "Site not found: ${domain}" "SITE_NOT_FOUND"
        return 1
    fi

    log_info "Creating ${backup_type} backup for ${domain}"

    local backup_dir backup_id
    backup_dir=$(ensure_backup_dir "$domain")
    backup_id=$(generate_backup_id)

    local files_backup=""
    local database_backup=""
    local total_size=0

    # Create backups based on type
    case "$backup_type" in
        full)
            files_backup=$(backup_files "$domain" "$backup_dir" "$backup_id")
            database_backup=$(backup_database "$domain" "$backup_dir" "$backup_id")
            ;;
        files)
            files_backup=$(backup_files "$domain" "$backup_dir" "$backup_id")
            ;;
        database)
            database_backup=$(backup_database "$domain" "$backup_dir" "$backup_id")
            ;;
    esac

    # Calculate total size
    if [[ -n "$files_backup" && -f "$files_backup" ]]; then
        total_size=$((total_size + $(stat -c%s "$files_backup" 2>/dev/null || stat -f%z "$files_backup" 2>/dev/null || echo 0)))
    fi
    if [[ -n "$database_backup" && -f "$database_backup" ]]; then
        total_size=$((total_size + $(stat -c%s "$database_backup" 2>/dev/null || stat -f%z "$database_backup" 2>/dev/null || echo 0)))
    fi

    # Build response
    local response_data
    response_data=$(json_object \
        "backup_id" "$backup_id" \
        "domain" "$domain" \
        "type" "$backup_type" \
        "files_backup" "${files_backup:-null}" \
        "database_backup" "${database_backup:-null}" \
        "size_bytes" "$total_size" \
        "created_at" "$(date -Iseconds)")

    log_info "Backup created: ${backup_id} (${total_size} bytes)"
    json_success "Backup created successfully" "$response_data"
    return 0
}

# backup:list command
# Supports: backup:list <domain> or backup:list --site=<domain>
cmd_backup_list() {
    local domain=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --site=*)
                domain="${1#*=}"
                shift
                ;;
            --site)
                domain="$2"
                shift 2
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$domain" ]]; then
        json_error "Domain is required (use --site=<domain>)" "MISSING_DOMAIN"
        return 1
    fi

    local backup_dir="${BACKUP_ROOT}/${domain}"

    if [[ ! -d "$backup_dir" ]]; then
        json_success "No backups found" "$(json_object "domain" "$domain" "backups" "[]" "count" "0")"
        return 0
    fi

    log_info "Listing backups for ${domain}"

    local backups=()

    # Find all backup metadata files
    while IFS= read -r meta_file; do
        if [[ -f "$meta_file" ]]; then
            local backup_data
            backup_data=$(cat "$meta_file")
            backups+=("$backup_data")
        fi
    done < <(find "$backup_dir" -name "*.meta" -type f | sort -r)

    # Build JSON array
    local backups_json="["
    local first=true
    for backup in "${backups[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            backups_json+=","
        fi
        backups_json+="$backup"
    done
    backups_json+="]"

    json_success "Backups retrieved" "$(json_object "domain" "$domain" "backups" "$backups_json" "count" "${#backups[@]}")"
    return 0
}

# Find backup by ID (searches all domain backup directories)
find_backup_by_id() {
    local backup_id="$1"

    # Search for backup metadata in all domain directories
    for domain_dir in "${BACKUP_ROOT}"/*; do
        if [[ -d "$domain_dir" ]]; then
            local meta_file="${domain_dir}/${backup_id}_files.tar.gz.meta"
            if [[ -f "$meta_file" ]]; then
                echo "$meta_file"
                return 0
            fi
            # Also check database-only backups
            meta_file="${domain_dir}/${backup_id}_database.sql.gz.meta"
            if [[ -f "$meta_file" ]]; then
                echo "$meta_file"
                return 0
            fi
        fi
    done

    return 1
}

# backup:restore command
# Supports: backup:restore <backup_id> OR backup:restore <domain> <backup_id> OR backup:restore --backup-id=<id>
cmd_backup_restore() {
    local domain=""
    local backup_id=""

    # Parse arguments (supports multiple formats for compatibility)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-id=*)
                backup_id="${1#*=}"
                shift
                ;;
            --backup-id)
                backup_id="$2"
                shift 2
                ;;
            --site=*)
                domain="${1#*=}"
                shift
                ;;
            --site)
                domain="$2"
                shift 2
                ;;
            *)
                # First positional arg could be backup_id (new format) or domain (legacy format)
                if [[ -z "$backup_id" ]] && [[ "$1" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
                    # Looks like a backup_id
                    backup_id="$1"
                elif [[ -z "$domain" ]]; then
                    domain="$1"
                elif [[ -z "$backup_id" ]]; then
                    backup_id="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$backup_id" ]]; then
        json_error "Backup ID is required" "MISSING_BACKUP_ID"
        return 1
    fi

    # Validate backup_id format (YYYYMMDD_HHMMSS) to prevent path traversal
    if ! [[ "$backup_id" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        json_error "Invalid backup ID format" "INVALID_BACKUP_ID"
        return 1
    fi

    # If domain not provided, find it from backup metadata
    if [[ -z "$domain" ]]; then
        local meta_file
        if meta_file=$(find_backup_by_id "$backup_id"); then
            if command -v jq &> /dev/null; then
                domain=$(jq -r '.domain // empty' "$meta_file" 2>/dev/null)
            fi
        fi

        if [[ -z "$domain" ]]; then
            json_error "Could not determine domain for backup ID: ${backup_id}. Specify --site=<domain>" "DOMAIN_NOT_FOUND"
            return 1
        fi
    fi

    # Check if site exists
    if ! site_exists "$domain"; then
        json_error "Site not found: ${domain}" "SITE_NOT_FOUND"
        return 1
    fi

    local backup_dir="${BACKUP_ROOT}/${domain}"
    local site_root="${SITES_ROOT}/${domain}"

    log_info "Restoring backup ${backup_id} for ${domain}"

    local restored_files=false
    local restored_database=false

    # Restore files if backup exists
    local files_backup="${backup_dir}/${backup_id}_files.tar.gz"
    if [[ -f "$files_backup" ]]; then
        log_info "Restoring files from ${files_backup}"

        # Create backup of current files
        if [[ -d "$site_root" ]]; then
            mv "$site_root" "${site_root}.pre-restore.$(date +%s)"
        fi

        # Extract backup
        mkdir -p "$(dirname "$site_root")"
        if tar -xzf "$files_backup" -C "$(dirname "$site_root")" 2>&1; then
            chown -R www-data:www-data "$site_root"
            restored_files=true
            log_info "Files restored successfully"
        else
            log_error "Failed to restore files"
        fi
    fi

    # Restore database if backup exists
    local db_backup="${backup_dir}/${backup_id}_database.sql.gz"
    if [[ -f "$db_backup" ]]; then
        log_info "Restoring database from ${db_backup}"

        # Get database name
        local site_info db_name
        site_info=$(get_site_info "$domain")
        if command -v jq &> /dev/null; then
            db_name=$(echo "$site_info" | jq -r '.db_name // empty')
        else
            db_name="site_$(domain_to_dbname "$domain")"
        fi

        if [[ -n "$db_name" ]]; then
            # Use mktemp for secure temporary file
            local temp_restore
            temp_restore=$(mktemp -t "vpsmanager_restore_XXXXXX.sql") || {
                log_error "Failed to create temporary file"
                json_error "Failed to create temporary file for restore" "TEMP_FILE_ERROR"
                return 1
            }

            # Decompress and restore
            gunzip -c "$db_backup" > "$temp_restore"
            if restore_database "$db_name" "$temp_restore"; then
                restored_database=true
                log_info "Database restored successfully"
            else
                log_error "Failed to restore database"
            fi
            rm -f "$temp_restore"
        fi
    fi

    if [[ "$restored_files" == "true" || "$restored_database" == "true" ]]; then
        json_success "Backup restored" "$(json_object \
            "backup_id" "$backup_id" \
            "domain" "$domain" \
            "files_restored" "$restored_files" \
            "database_restored" "$restored_database")"
        return 0
    else
        json_error "No backup files found for ID: ${backup_id}" "BACKUP_NOT_FOUND"
        return 1
    fi
}
