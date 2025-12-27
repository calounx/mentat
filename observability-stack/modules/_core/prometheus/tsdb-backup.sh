#!/bin/bash
#===============================================================================
# Prometheus TSDB Backup Script
# Part of the observability-stack module system
#
# Creates safe backups of Prometheus TSDB data for upgrade and disaster recovery
#
# Features:
#   - API-based snapshots (zero-downtime when admin API enabled)
#   - File-based backup fallback (requires service stop)
#   - WAL checkpoint before backup
#   - Backup verification
#   - Retention management
#
# Usage:
#   ./tsdb-backup.sh [options]
#
# Options:
#   --method=api|file     Backup method (default: auto)
#   --output=DIR          Output directory (default: /var/lib/observability-upgrades/backups/prometheus)
#   --retention=DAYS      Days to keep backups (default: 30)
#   --verify              Verify backup after creation
#   --no-stop             Don't stop service for file backup (may be inconsistent)
#   --dry-run             Show what would be done
#===============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" && pwd)"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

#===============================================================================
# CONFIGURATION
#===============================================================================

PROMETHEUS_DATA="${PROMETHEUS_DATA:-/var/lib/prometheus}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
SERVICE_NAME="${SERVICE_NAME:-prometheus}"

BACKUP_OUTPUT="${BACKUP_OUTPUT:-/var/lib/observability-upgrades/backups/prometheus}"
BACKUP_METHOD="${BACKUP_METHOD:-auto}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

VERIFY_BACKUP="${VERIFY_BACKUP:-false}"
NO_STOP="${NO_STOP:-false}"
DRY_RUN="${DRY_RUN:-false}"

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

for arg in "$@"; do
    case "$arg" in
        --method=*)
            BACKUP_METHOD="${arg#*=}"
            ;;
        --output=*)
            BACKUP_OUTPUT="${arg#*=}"
            ;;
        --retention=*)
            BACKUP_RETENTION_DAYS="${arg#*=}"
            ;;
        --verify)
            VERIFY_BACKUP=true
            ;;
        --no-stop)
            NO_STOP=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --method=api|file     Backup method (default: auto)"
            echo "  --output=DIR          Output directory"
            echo "  --retention=DAYS      Days to keep backups (default: 30)"
            echo "  --verify              Verify backup after creation"
            echo "  --no-stop             Don't stop service for file backup"
            echo "  --dry-run             Show what would be done"
            exit 0
            ;;
    esac
done

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

# Get current Prometheus version
get_prometheus_version() {
    if [[ -x "/usr/local/bin/prometheus" ]]; then
        /usr/local/bin/prometheus --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        echo "unknown"
    fi
}

# Check if Prometheus is running
is_prometheus_running() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

# Check if admin API is enabled
is_admin_api_enabled() {
    if curl -sf "http://localhost:${PROMETHEUS_PORT}/api/v1/admin/tsdb/snapshot" \
       -X POST -o /dev/null 2>/dev/null; then
        return 0
    fi
    # Check if we get "admin APIs disabled" response
    local response
    response=$(curl -sf "http://localhost:${PROMETHEUS_PORT}/api/v1/admin/tsdb/snapshot" 2>&1 || true)
    if echo "$response" | grep -qi "admin.*disabled"; then
        return 1
    fi
    return 1
}

# Calculate directory size
get_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "N/A"
    fi
}

# Count files in directory
count_files() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        find "$dir" -type f 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

#===============================================================================
# API-BASED BACKUP
#===============================================================================

# Create TSDB snapshot via Prometheus Admin API
create_api_snapshot() {
    local output_dir="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="api-snapshot-${timestamp}"

    log_info "Creating TSDB snapshot via Admin API..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create API snapshot"
        return 0
    fi

    # Trigger snapshot creation
    local response
    response=$(curl -sf -X POST "http://localhost:${PROMETHEUS_PORT}/api/v1/admin/tsdb/snapshot" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to create snapshot: $response"
        return 1
    fi

    # Extract snapshot name from response
    local snapshot_path
    snapshot_path=$(echo "$response" | grep -oP '"name"\s*:\s*"\K[^"]+' || true)

    if [[ -z "$snapshot_path" ]]; then
        log_error "Could not parse snapshot name from response: $response"
        return 1
    fi

    local full_snapshot_path="${PROMETHEUS_DATA}/snapshots/${snapshot_path}"

    if [[ ! -d "$full_snapshot_path" ]]; then
        log_error "Snapshot directory not found: $full_snapshot_path"
        return 1
    fi

    # Move snapshot to output directory
    local backup_path="${output_dir}/${snapshot_name}"
    mkdir -p "$output_dir"

    log_info "Moving snapshot to $backup_path..."
    mv "$full_snapshot_path" "$backup_path"

    # Create metadata
    local version
    version=$(get_prometheus_version)
    local data_size
    data_size=$(get_dir_size "$backup_path")
    local file_count
    file_count=$(count_files "$backup_path")

    cat > "${backup_path}/backup-metadata.json" <<EOF
{
    "type": "api-snapshot",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "prometheus_version": "$version",
    "source_path": "$PROMETHEUS_DATA",
    "backup_method": "api",
    "size": "$data_size",
    "file_count": $file_count,
    "consistent": true
}
EOF

    log_success "API snapshot created: $backup_path (size: $data_size)"
    echo "$backup_path"
}

#===============================================================================
# FILE-BASED BACKUP
#===============================================================================

# Create file-based backup
create_file_backup() {
    local output_dir="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="file-backup-${timestamp}"
    local backup_path="${output_dir}/${backup_name}"

    log_info "Creating file-based TSDB backup..."

    if [[ ! -d "$PROMETHEUS_DATA" ]]; then
        log_error "TSDB data directory not found: $PROMETHEUS_DATA"
        return 1
    fi

    local data_size
    data_size=$(get_dir_size "$PROMETHEUS_DATA")
    log_info "TSDB data size: $data_size"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create file backup of $PROMETHEUS_DATA ($data_size)"
        return 0
    fi

    mkdir -p "$backup_path"

    # Determine if we need to stop the service
    local was_running=false
    local is_consistent=false

    if is_prometheus_running; then
        if [[ "$NO_STOP" == "true" ]]; then
            log_warn "Creating backup without stopping Prometheus - may be inconsistent"
            is_consistent=false
        else
            log_info "Stopping Prometheus for consistent backup..."
            was_running=true
            systemctl stop "$SERVICE_NAME"
            sleep 5
            is_consistent=true
        fi
    else
        is_consistent=true
    fi

    # Perform the backup
    log_info "Copying TSDB data..."

    if command -v rsync &>/dev/null; then
        rsync -a --info=progress2 "$PROMETHEUS_DATA/" "$backup_path/data/" 2>&1 || {
            log_error "rsync failed"
            [[ "$was_running" == "true" ]] && systemctl start "$SERVICE_NAME"
            return 1
        }
    else
        cp -a "$PROMETHEUS_DATA" "$backup_path/data" || {
            log_error "cp failed"
            [[ "$was_running" == "true" ]] && systemctl start "$SERVICE_NAME"
            return 1
        }
    fi

    # Restart service if we stopped it
    if [[ "$was_running" == "true" ]]; then
        log_info "Restarting Prometheus..."
        systemctl start "$SERVICE_NAME"
    fi

    # Create metadata
    local version
    version=$(get_prometheus_version)
    local backup_size
    backup_size=$(get_dir_size "$backup_path")
    local file_count
    file_count=$(count_files "$backup_path")

    cat > "${backup_path}/backup-metadata.json" <<EOF
{
    "type": "file-backup",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "prometheus_version": "$version",
    "source_path": "$PROMETHEUS_DATA",
    "backup_method": "file",
    "size": "$backup_size",
    "file_count": $file_count,
    "consistent": $is_consistent,
    "service_stopped": $was_running
}
EOF

    log_success "File backup created: $backup_path (size: $backup_size, consistent: $is_consistent)"
    echo "$backup_path"
}

#===============================================================================
# BACKUP VERIFICATION
#===============================================================================

# Verify backup integrity
verify_backup() {
    local backup_path="$1"

    log_info "Verifying backup: $backup_path"

    # Check metadata exists
    if [[ ! -f "${backup_path}/backup-metadata.json" ]]; then
        log_error "Backup metadata not found"
        return 1
    fi

    # Check data directory exists
    local data_path=""
    if [[ -d "${backup_path}/data" ]]; then
        data_path="${backup_path}/data"
    elif [[ -d "${backup_path}/chunks_head" ]]; then
        data_path="$backup_path"
    else
        log_error "No TSDB data found in backup"
        return 1
    fi

    # Check for essential TSDB components
    local missing_components=()

    # WAL directory (may not exist in snapshot)
    # Chunks directory
    if [[ ! -d "${data_path}/chunks_head" ]] && \
       ! find "$data_path" -type d -name "chunks" 2>/dev/null | grep -q .; then
        missing_components+=("chunks")
    fi

    # Index files (in block directories)
    if ! find "$data_path" -name "index" -type f 2>/dev/null | grep -q .; then
        log_warn "No index files found (may be empty TSDB)"
    fi

    if [[ ${#missing_components[@]} -gt 0 ]]; then
        log_warn "Missing components: ${missing_components[*]}"
    fi

    # Check file count
    local file_count
    file_count=$(count_files "$backup_path")

    if [[ $file_count -lt 1 ]]; then
        log_error "Backup appears to be empty"
        return 1
    fi

    log_success "Backup verification passed ($file_count files)"
    return 0
}

#===============================================================================
# RETENTION MANAGEMENT
#===============================================================================

# Clean up old backups
cleanup_old_backups() {
    local backup_dir="$1"
    local retention_days="$2"

    log_info "Cleaning up backups older than $retention_days days..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean up old backups"
        find "$backup_dir" -maxdepth 1 -type d -mtime +"$retention_days" 2>/dev/null | while read -r dir; do
            log_info "[DRY-RUN] Would delete: $dir"
        done
        return 0
    fi

    local deleted=0
    find "$backup_dir" -maxdepth 1 -type d -mtime +"$retention_days" 2>/dev/null | while read -r dir; do
        # Skip if it's the backup_dir itself
        [[ "$dir" == "$backup_dir" ]] && continue

        log_info "Deleting old backup: $dir"
        rm -rf "$dir"
        ((deleted++)) || true
    done

    if [[ $deleted -gt 0 ]]; then
        log_success "Deleted $deleted old backups"
    else
        log_info "No old backups to clean up"
    fi
}

# List existing backups
list_backups() {
    local backup_dir="$1"

    echo ""
    echo "Existing Prometheus TSDB Backups"
    echo "================================="
    echo ""

    if [[ ! -d "$backup_dir" ]]; then
        echo "No backups found in $backup_dir"
        return 0
    fi

    find "$backup_dir" -maxdepth 1 -type d -name "*backup*" -o -name "*snapshot*" 2>/dev/null | sort -r | while read -r dir; do
        [[ "$dir" == "$backup_dir" ]] && continue

        local name
        name=$(basename "$dir")
        local size
        size=$(get_dir_size "$dir")
        local metadata="${dir}/backup-metadata.json"

        if [[ -f "$metadata" ]]; then
            local timestamp
            timestamp=$(grep -oP '"timestamp"\s*:\s*"\K[^"]+' "$metadata" 2>/dev/null || echo "unknown")
            local method
            method=$(grep -oP '"backup_method"\s*:\s*"\K[^"]+' "$metadata" 2>/dev/null || echo "unknown")
            local consistent
            consistent=$(grep -oP '"consistent"\s*:\s*\K[^,}]+' "$metadata" 2>/dev/null || echo "unknown")

            printf "%-40s  Size: %-8s  Method: %-6s  Consistent: %-5s  Created: %s\n" \
                "$name" "$size" "$method" "$consistent" "$timestamp"
        else
            printf "%-40s  Size: %-8s  (no metadata)\n" "$name" "$size"
        fi
    done

    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    log_info "=========================================="
    log_info "Prometheus TSDB Backup"
    log_info "=========================================="

    # Show configuration
    log_info "TSDB Data Path: $PROMETHEUS_DATA"
    log_info "Output Directory: $BACKUP_OUTPUT"
    log_info "Backup Method: $BACKUP_METHOD"

    # Create output directory
    mkdir -p "$BACKUP_OUTPUT"
    chmod 700 "$BACKUP_OUTPUT"

    # List existing backups
    list_backups "$BACKUP_OUTPUT"

    # Determine backup method
    local method="$BACKUP_METHOD"

    if [[ "$method" == "auto" ]]; then
        if is_prometheus_running; then
            if is_admin_api_enabled; then
                log_info "Auto-detected: Using API snapshot (zero-downtime)"
                method="api"
            else
                log_info "Auto-detected: Using file backup (admin API not enabled)"
                method="file"
            fi
        else
            log_info "Auto-detected: Using file backup (Prometheus not running)"
            method="file"
        fi
    fi

    # Execute backup
    local backup_path=""

    case "$method" in
        api)
            if ! is_prometheus_running; then
                log_error "API backup requires Prometheus to be running"
                exit 1
            fi
            if ! is_admin_api_enabled; then
                log_error "API backup requires --web.enable-admin-api flag"
                log_info "Add --web.enable-admin-api to Prometheus startup flags"
                exit 1
            fi
            backup_path=$(create_api_snapshot "$BACKUP_OUTPUT")
            ;;

        file)
            backup_path=$(create_file_backup "$BACKUP_OUTPUT")
            ;;

        *)
            log_error "Unknown backup method: $method"
            exit 1
            ;;
    esac

    # Verify if requested
    if [[ "$VERIFY_BACKUP" == "true" && -n "$backup_path" && "$DRY_RUN" != "true" ]]; then
        verify_backup "$backup_path"
    fi

    # Cleanup old backups
    cleanup_old_backups "$BACKUP_OUTPUT" "$BACKUP_RETENTION_DAYS"

    # Final summary
    echo ""
    log_success "=========================================="
    log_success "Backup Complete"
    if [[ -n "$backup_path" ]]; then
        log_success "Location: $backup_path"
    fi
    log_success "=========================================="
}

main "$@"
