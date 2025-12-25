#!/bin/bash
#===============================================================================
# Backup and Restore Library
# Configuration backup with timestamps, restore, and automatic cleanup
#===============================================================================

[[ -n "${BACKUP_SH_LOADED:-}" ]] && return 0
BACKUP_SH_LOADED=1

_BACKUP_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${COMMON_SH_LOADED:-}" ]] && source "$_BACKUP_DIR_LIB/common.sh"
[[ -z "${ERRORS_SH_LOADED:-}" ]] && source "$_BACKUP_DIR_LIB/errors.sh"
[[ -z "${VALIDATION_SH_LOADED:-}" ]] && source "$_BACKUP_DIR_LIB/validation.sh"

# Backup directory configuration
readonly BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/var/lib/observability-backups}"
readonly BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Backup a file with timestamp
# Usage: backup_file "file_path" ["backup_name"]
backup_file() {
    local file="$1"
    local backup_name="${2:-$(basename "$file")}"
    
    validate_file_exists "$file" || return 1
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_BASE_DIR/files"
    mkdir -p "$backup_dir"
    
    local backup_path="${backup_dir}/${backup_name}.${timestamp}.backup"
    
    cp -a "$file" "$backup_path"
    log_success "Backup created: $backup_path"
    echo "$backup_path"
}

# Backup a directory
# Usage: backup_directory "directory_path" ["backup_name"]
backup_directory() {
    local dir="$1"
    local backup_name="${2:-$(basename "$dir")}"
    
    validate_directory_exists "$dir" || return 1
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_BASE_DIR/directories"
    mkdir -p "$backup_dir"
    
    local backup_path="${backup_dir}/${backup_name}.${timestamp}.tar.gz"
    
    tar -czf "$backup_path" -C "$(dirname "$dir")" "$(basename "$dir")"
    log_success "Backup created: $backup_path"
    echo "$backup_path"
}

# Restore from backup
# Usage: backup_restore "backup_path" "destination"
backup_restore() {
    local backup_path="$1"
    local destination="$2"
    
    validate_file_exists "$backup_path" "backup file" || return 1
    
    error_push_context "Restore backup: $backup_path"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        # Directory backup
        mkdir -p "$destination"
        tar -xzf "$backup_path" -C "$destination"
    else
        # File backup
        cp -a "$backup_path" "$destination"
    fi
    
    error_pop_context
    log_success "Restored from backup: $backup_path to $destination"
}

# List available backups
# Usage: backup_list [name_filter]
backup_list() {
    local filter="${1:-*}"
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_info "No backups found"
        return 0
    fi
    
    echo "Available backups:"
    find "$BACKUP_BASE_DIR" -type f -name "${filter}*.backup" -o -name "${filter}*.tar.gz" | while read -r backup; do
        local size
        size=$(du -h "$backup" | cut -f1)
        local mtime
        mtime=$(stat -c%y "$backup" 2>/dev/null | cut -d. -f1 || stat -f%Sm "$backup" 2>/dev/null)
        printf "  %s - %s (%s)\n" "$(basename "$backup")" "$size" "$mtime"
    done
}

# Get latest backup for a name
# Usage: backup_get_latest "name"
backup_get_latest() {
    local name="$1"
    
    find "$BACKUP_BASE_DIR" -type f \( -name "${name}.*.backup" -o -name "${name}.*.tar.gz" \) 2>/dev/null | sort -r | head -1
}

# Clean up old backups
# Usage: backup_cleanup [days_to_keep]
backup_cleanup() {
    local days="${1:-$BACKUP_RETENTION_DAYS}"
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        return 0
    fi
    
    log_info "Cleaning up backups older than $days days..."
    
    local count=0
    find "$BACKUP_BASE_DIR" -type f -mtime "+$days" | while read -r old_backup; do
        rm -f "$old_backup"
        ((count++))
    done
    
    log_success "Backup cleanup complete (removed $count backups)"
}

# Backup before making changes (convenience wrapper)
# Usage: backup_before_change "file_or_dir"
backup_before_change() {
    local path="$1"
    
    if [[ -f "$path" ]]; then
        backup_file "$path"
    elif [[ -d "$path" ]]; then
        backup_directory "$path"
    else
        error_report "Path does not exist: $path" "$E_NOT_FOUND"
        return 1
    fi
}

# Create backup manifest
# Usage: backup_create_manifest "backup_name" "description"
backup_create_manifest() {
    local backup_name="$1"
    local description="$2"
    
    local manifest_dir="$BACKUP_BASE_DIR/manifests"
    mkdir -p "$manifest_dir"
    
    local manifest="${manifest_dir}/${backup_name}.$(date +%Y%m%d_%H%M%S).manifest"
    
    cat > "$manifest" << EOF
Backup: $backup_name
Created: $(date '+%Y-%m-%d %H:%M:%S')
Description: $description
Hostname: $(hostname)
User: $(whoami)
---
EOF
    
    log_debug "Backup manifest created: $manifest"
}

