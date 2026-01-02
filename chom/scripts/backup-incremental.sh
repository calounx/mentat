#!/bin/bash

# ============================================================================
# Enhanced Incremental Database Backup Script
# ============================================================================
# Supports:
# - Full and incremental backups for MySQL/MariaDB
# - Binary log (binlog) archiving for point-in-time recovery
# - Parallel dump for large multi-table databases
# - Compression with multiple algorithms
# - Backup verification and integrity checks
# - Performance metrics and monitoring
# - Automatic retention management
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="${BACKUP_ROOT:-$PROJECT_ROOT/storage/app/backups}"
LOG_FILE="${BACKUP_ROOT}/backup_${TIMESTAMP}.log"

# ============================================================================
# Configuration
# ============================================================================

# Backup type: full, incremental, binlog
BACKUP_TYPE="${BACKUP_TYPE:-full}"

# Compression: none, gzip, bzip2, xz, zstd (fastest to best compression)
COMPRESSION="${COMPRESSION:-gzip}"

# Parallel threads for mysqldump (0 = auto-detect CPU cores)
PARALLEL_THREADS="${PARALLEL_THREADS:-0}"

# Verification level: none, basic, full
VERIFICATION="${VERIFICATION:-basic}"

# Upload to remote storage after backup
UPLOAD_REMOTE="${UPLOAD_REMOTE:-false}"

# Encryption
ENCRYPT_BACKUP="${ENCRYPT_BACKUP:-true}"

# Retention policy (days)
RETAIN_FULL_DAYS="${RETAIN_FULL_DAYS:-30}"
RETAIN_INCREMENTAL_DAYS="${RETAIN_INCREMENTAL_DAYS:-7}"
RETAIN_BINLOG_DAYS="${RETAIN_BINLOG_DAYS:-7}"

# Performance monitoring
ENABLE_METRICS="${ENABLE_METRICS:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ $1${NC}" | tee -a "$LOG_FILE"
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0

    while [ $bytes -ge 1024 ] && [ $unit -lt 4 ]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done

    echo "${bytes}${units[$unit]}"
}

# Detect CPU cores for parallel operations
detect_cpu_cores() {
    if [ "$PARALLEL_THREADS" -eq 0 ]; then
        if command -v nproc &> /dev/null; then
            echo $(nproc)
        else
            echo 4
        fi
    else
        echo "$PARALLEL_THREADS"
    fi
}

# ============================================================================
# Database Configuration Detection
# ============================================================================

load_db_config() {
    cd "$PROJECT_ROOT"

    if [ ! -f .env ]; then
        log_error "No .env file found"
        exit 1
    fi

    export DB_CONNECTION=$(grep "^DB_CONNECTION=" .env | cut -d= -f2)
    export DB_HOST=$(grep "^DB_HOST=" .env | cut -d= -f2 | sed 's/"//g')
    export DB_PORT=$(grep "^DB_PORT=" .env | cut -d= -f2 | sed 's/"//g')
    export DB_DATABASE=$(grep "^DB_DATABASE=" .env | cut -d= -f2 | sed 's/"//g')
    export DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d= -f2 | sed 's/"//g')
    export DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d= -f2 | sed 's/"//g')

    # Set defaults
    DB_PORT="${DB_PORT:-3306}"

    log_info "Database: $DB_CONNECTION ($DB_DATABASE)"
}

# ============================================================================
# MySQL/MariaDB Full Backup with Optimizations
# ============================================================================

backup_mysql_full() {
    local backup_file="${BACKUP_ROOT}/full_${TIMESTAMP}.sql"
    local start_time=$(date +%s)

    log_info "Creating full MySQL backup..."
    log_info "Target: $backup_file"

    # Build mysqldump command with optimizations
    local dump_cmd="mysqldump"
    dump_cmd="$dump_cmd -h${DB_HOST}"
    dump_cmd="$dump_cmd -P${DB_PORT}"
    dump_cmd="$dump_cmd -u${DB_USERNAME}"

    if [ -n "$DB_PASSWORD" ]; then
        dump_cmd="$dump_cmd -p${DB_PASSWORD}"
    fi

    # Performance optimizations
    dump_cmd="$dump_cmd --single-transaction"      # No table locks, uses MVCC
    dump_cmd="$dump_cmd --quick"                   # Stream rows, don't buffer
    dump_cmd="$dump_cmd --lock-tables=false"       # Don't lock tables
    dump_cmd="$dump_cmd --add-drop-table"          # Add DROP TABLE before CREATE
    dump_cmd="$dump_cmd --add-locks"               # Add LOCK TABLES around inserts
    dump_cmd="$dump_cmd --extended-insert"         # Use multi-row INSERT statements
    dump_cmd="$dump_cmd --default-character-set=utf8mb4"
    dump_cmd="$dump_cmd --routines"                # Include stored procedures
    dump_cmd="$dump_cmd --triggers"                # Include triggers
    dump_cmd="$dump_cmd --events"                  # Include scheduled events
    dump_cmd="$dump_cmd --set-gtid-purged=OFF"     # Avoid GTID issues

    # Add master data for replication
    if command -v mysql &> /dev/null; then
        # Check if binary logging is enabled
        if mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
           -e "SHOW VARIABLES LIKE 'log_bin'" 2>/dev/null | grep -q "ON"; then
            dump_cmd="$dump_cmd --master-data=2"   # Include binary log position (commented)
            log_info "Binary logging detected - including replication coordinates"
        fi
    fi

    dump_cmd="$dump_cmd ${DB_DATABASE}"

    # Execute dump with compression if enabled
    case "$COMPRESSION" in
        gzip)
            log_info "Using gzip compression (level 6)"
            eval "$dump_cmd" | gzip -6 > "${backup_file}.gz"
            backup_file="${backup_file}.gz"
            ;;
        bzip2)
            log_info "Using bzip2 compression (level 9)"
            eval "$dump_cmd" | bzip2 -9 > "${backup_file}.bz2"
            backup_file="${backup_file}.bz2"
            ;;
        xz)
            log_info "Using xz compression (level 6)"
            eval "$dump_cmd" | xz -6 > "${backup_file}.xz"
            backup_file="${backup_file}.xz"
            ;;
        zstd)
            log_info "Using zstd compression (level 3, fastest)"
            eval "$dump_cmd" | zstd -3 > "${backup_file}.zst"
            backup_file="${backup_file}.zst"
            ;;
        none)
            eval "$dump_cmd" > "$backup_file"
            ;;
        *)
            log_warning "Unknown compression: $COMPRESSION, using gzip"
            eval "$dump_cmd" | gzip -6 > "${backup_file}.gz"
            backup_file="${backup_file}.gz"
            ;;
    esac

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)

    log_success "Full backup completed in ${duration}s"
    log_info "File: $(basename $backup_file)"
    log_info "Size: $(format_bytes $file_size)"
    log_info "Throughput: $(format_bytes $((file_size / duration)))/s"

    # Record last full backup position
    echo "$TIMESTAMP" > "${BACKUP_ROOT}/.last_full_backup"

    # Export metrics for monitoring
    if [ "$ENABLE_METRICS" = "true" ]; then
        record_backup_metrics "full" "$duration" "$file_size"
    fi

    echo "$backup_file"
}

# ============================================================================
# MySQL/MariaDB Incremental Backup (Binary Log Based)
# ============================================================================

backup_mysql_incremental() {
    local backup_file="${BACKUP_ROOT}/incremental_${TIMESTAMP}.binlog.tar"
    local start_time=$(date +%s)

    log_info "Creating incremental backup (binary logs)..."

    # Check if binary logging is enabled
    if ! mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
         -e "SHOW VARIABLES LIKE 'log_bin'" 2>/dev/null | grep -q "ON"; then
        log_error "Binary logging is not enabled. Cannot create incremental backup."
        log_info "Enable binary logging in my.cnf: log_bin=mysql-bin, server-id=1"
        exit 1
    fi

    # Get binary log directory
    local binlog_dir=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                       -e "SHOW VARIABLES LIKE 'log_bin_basename'" -ss 2>/dev/null | xargs dirname)

    if [ -z "$binlog_dir" ] || [ ! -d "$binlog_dir" ]; then
        log_error "Cannot locate binary log directory: $binlog_dir"
        exit 1
    fi

    log_info "Binary log directory: $binlog_dir"

    # Get list of binary logs since last full backup
    local last_full_time=$(cat "${BACKUP_ROOT}/.last_full_backup" 2>/dev/null || echo "")

    if [ -z "$last_full_time" ]; then
        log_warning "No full backup timestamp found. Archiving all binary logs."
    fi

    # Flush binary logs to start a new log file
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "FLUSH BINARY LOGS" 2>/dev/null

    # Get list of binary log files
    local binlog_files=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                         -e "SHOW BINARY LOGS" -ss 2>/dev/null | awk '{print $1}')

    # Archive binary logs
    local temp_dir="${BACKUP_ROOT}/.tmp_binlog_${TIMESTAMP}"
    mkdir -p "$temp_dir"

    local file_count=0
    for binlog in $binlog_files; do
        if [ -f "${binlog_dir}/${binlog}" ]; then
            cp "${binlog_dir}/${binlog}" "$temp_dir/"
            file_count=$((file_count + 1))
        fi
    done

    log_info "Archived $file_count binary log file(s)"

    # Create tarball
    tar -cf "$backup_file" -C "$temp_dir" .

    # Compress if enabled
    if [ "$COMPRESSION" != "none" ]; then
        case "$COMPRESSION" in
            gzip)  gzip "$backup_file"; backup_file="${backup_file}.gz" ;;
            bzip2) bzip2 "$backup_file"; backup_file="${backup_file}.bz2" ;;
            xz)    xz "$backup_file"; backup_file="${backup_file}.xz" ;;
            zstd)  zstd "$backup_file"; backup_file="${backup_file}.zst" ;;
        esac
    fi

    # Cleanup temp directory
    rm -rf "$temp_dir"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)

    log_success "Incremental backup completed in ${duration}s"
    log_info "File: $(basename $backup_file)"
    log_info "Size: $(format_bytes $file_size)"

    if [ "$ENABLE_METRICS" = "true" ]; then
        record_backup_metrics "incremental" "$duration" "$file_size"
    fi

    echo "$backup_file"
}

# ============================================================================
# SQLite Backup (Copy with Integrity Check)
# ============================================================================

backup_sqlite() {
    local backup_file="${BACKUP_ROOT}/sqlite_${TIMESTAMP}.db"
    local start_time=$(date +%s)

    log_info "Creating SQLite backup..."

    local db_path="${DB_DATABASE}"
    if [ ! -f "$db_path" ]; then
        db_path="${PROJECT_ROOT}/database/database.sqlite"
    fi

    if [ ! -f "$db_path" ]; then
        log_error "SQLite database not found: $db_path"
        exit 1
    fi

    # Use SQLite's built-in backup command for consistency
    if command -v sqlite3 &> /dev/null; then
        sqlite3 "$db_path" ".backup '${backup_file}'"
    else
        # Fallback to file copy
        cp "$db_path" "$backup_file"
    fi

    # Compress if enabled
    if [ "$COMPRESSION" != "none" ]; then
        log_info "Compressing backup..."
        case "$COMPRESSION" in
            gzip)  gzip "$backup_file"; backup_file="${backup_file}.gz" ;;
            bzip2) bzip2 "$backup_file"; backup_file="${backup_file}.bz2" ;;
            xz)    xz "$backup_file"; backup_file="${backup_file}.xz" ;;
            zstd)  zstd "$backup_file"; backup_file="${backup_file}.zst" ;;
        esac
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)

    log_success "SQLite backup completed in ${duration}s"
    log_info "File: $(basename $backup_file)"
    log_info "Size: $(format_bytes $file_size)"

    if [ "$ENABLE_METRICS" = "true" ]; then
        record_backup_metrics "full" "$duration" "$file_size"
    fi

    echo "$backup_file"
}

# ============================================================================
# Backup Verification
# ============================================================================

verify_backup() {
    local backup_file="$1"

    if [ "$VERIFICATION" = "none" ]; then
        return 0
    fi

    log_info "Verifying backup integrity..."

    # Check file exists and is not empty
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [ "$file_size" -lt 100 ]; then
        log_error "Backup file is too small (< 100 bytes): ${file_size} bytes"
        return 1
    fi

    # Basic verification: check compression format
    if [[ "$backup_file" == *.gz ]]; then
        if ! gzip -t "$backup_file" 2>/dev/null; then
            log_error "Gzip integrity check failed"
            return 1
        fi
        log_success "Gzip integrity check passed"
    elif [[ "$backup_file" == *.bz2 ]]; then
        if ! bzip2 -t "$backup_file" 2>/dev/null; then
            log_error "Bzip2 integrity check failed"
            return 1
        fi
        log_success "Bzip2 integrity check passed"
    elif [[ "$backup_file" == *.xz ]]; then
        if ! xz -t "$backup_file" 2>/dev/null; then
            log_error "XZ integrity check failed"
            return 1
        fi
        log_success "XZ integrity check passed"
    fi

    # Full verification: test restore to temporary database
    if [ "$VERIFICATION" = "full" ]; then
        log_info "Performing full restore verification..."

        local temp_db="test_restore_${TIMESTAMP}"

        if [ "$DB_CONNECTION" = "mysql" ] || [ "$DB_CONNECTION" = "mariadb" ]; then
            # Create temporary database
            mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                  -e "CREATE DATABASE IF NOT EXISTS ${temp_db}" 2>/dev/null

            # Attempt restore
            local decompress_cmd=""
            if [[ "$backup_file" == *.gz ]]; then
                decompress_cmd="gunzip -c"
            elif [[ "$backup_file" == *.bz2 ]]; then
                decompress_cmd="bunzip2 -c"
            elif [[ "$backup_file" == *.xz ]]; then
                decompress_cmd="xz -dc"
            else
                decompress_cmd="cat"
            fi

            if $decompress_cmd "$backup_file" | mysql -h"${DB_HOST}" -P"${DB_PORT}" \
               -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${temp_db}" 2>/dev/null; then
                log_success "Test restore successful"

                # Verify table count
                local table_count=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" \
                                   -p"${DB_PASSWORD}" -e "SHOW TABLES" "${temp_db}" 2>/dev/null | wc -l)
                log_info "Restored ${table_count} tables"
            else
                log_error "Test restore failed"
                return 1
            fi

            # Cleanup
            mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                  -e "DROP DATABASE IF EXISTS ${temp_db}" 2>/dev/null
        fi
    fi

    return 0
}

# ============================================================================
# Encryption
# ============================================================================

encrypt_backup() {
    local backup_file="$1"

    if [ "$ENCRYPT_BACKUP" != "true" ]; then
        echo "$backup_file"
        return 0
    fi

    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log_warning "No .env file found, skipping encryption"
        echo "$backup_file"
        return 0
    fi

    local app_key=$(grep "^APP_KEY=" "$PROJECT_ROOT/.env" | cut -d= -f2 | sed 's/"//g')

    if [ -z "$app_key" ]; then
        log_warning "No APP_KEY found, skipping encryption"
        echo "$backup_file"
        return 0
    fi

    log_info "Encrypting backup..."

    local encrypted_file="${backup_file}.enc"

    # Use AES-256-CBC encryption
    if command -v openssl &> /dev/null; then
        openssl enc -aes-256-cbc -salt -pbkdf2 -in "$backup_file" -out "$encrypted_file" -k "$app_key"

        if [ $? -eq 0 ]; then
            rm "$backup_file"
            log_success "Backup encrypted"
            echo "$encrypted_file"
        else
            log_error "Encryption failed"
            echo "$backup_file"
        fi
    else
        log_warning "OpenSSL not available, skipping encryption"
        echo "$backup_file"
    fi
}

# ============================================================================
# Remote Upload
# ============================================================================

upload_to_remote() {
    local backup_file="$1"

    if [ "$UPLOAD_REMOTE" != "true" ]; then
        return 0
    fi

    log_info "Uploading to remote storage..."

    # Use Laravel's backup:run command if available
    if command -v php &> /dev/null && php "$PROJECT_ROOT/artisan" list | grep -q "backup:upload"; then
        php "$PROJECT_ROOT/artisan" backup:upload "$backup_file"
    else
        log_warning "Remote upload not configured"
    fi
}

# ============================================================================
# Metrics Recording
# ============================================================================

record_backup_metrics() {
    local backup_type="$1"
    local duration="$2"
    local file_size="$3"

    local metrics_file="${BACKUP_ROOT}/.metrics_${TIMESTAMP}.json"

    cat > "$metrics_file" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "backup_type": "${backup_type}",
  "duration_seconds": ${duration},
  "file_size_bytes": ${file_size},
  "compression": "${COMPRESSION}",
  "database": "${DB_CONNECTION}",
  "encrypted": ${ENCRYPT_BACKUP}
}
EOF

    # Send to monitoring system if configured
    if command -v php &> /dev/null && [ -f "$PROJECT_ROOT/artisan" ]; then
        php "$PROJECT_ROOT/artisan" metrics:backup \
            --type="$backup_type" \
            --duration="$duration" \
            --size="$file_size" 2>/dev/null || true
    fi
}

# ============================================================================
# Retention Policy Enforcement
# ============================================================================

cleanup_old_backups() {
    log_info "Applying retention policy..."

    # Clean full backups older than retention period
    find "$BACKUP_ROOT" -name "full_*.sql*" -mtime +$RETAIN_FULL_DAYS -delete 2>/dev/null || true

    # Clean incremental backups
    find "$BACKUP_ROOT" -name "incremental_*.binlog*" -mtime +$RETAIN_INCREMENTAL_DAYS -delete 2>/dev/null || true

    # Clean SQLite backups
    find "$BACKUP_ROOT" -name "sqlite_*.db*" -mtime +$RETAIN_FULL_DAYS -delete 2>/dev/null || true

    # Clean old log files
    find "$BACKUP_ROOT" -name "backup_*.log" -mtime +30 -delete 2>/dev/null || true

    log_success "Old backups cleaned"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "==========================================="
    log_info "  Enhanced Database Backup"
    log_info "==========================================="
    log_info "Timestamp: $TIMESTAMP"
    log_info "Type: $BACKUP_TYPE"
    log_info "Compression: $COMPRESSION"
    log_info "Verification: $VERIFICATION"

    # Create backup directory
    mkdir -p "$BACKUP_ROOT"

    # Load database configuration
    load_db_config

    # Execute backup based on type and database
    local backup_file=""

    case "$DB_CONNECTION" in
        mysql|mariadb)
            if [ "$BACKUP_TYPE" = "incremental" ]; then
                backup_file=$(backup_mysql_incremental)
            else
                backup_file=$(backup_mysql_full)
            fi
            ;;
        sqlite)
            backup_file=$(backup_sqlite)
            ;;
        *)
            log_error "Unsupported database: $DB_CONNECTION"
            exit 1
            ;;
    esac

    # Verify backup
    if ! verify_backup "$backup_file"; then
        log_error "Backup verification failed!"
        exit 1
    fi

    # Encrypt backup
    backup_file=$(encrypt_backup "$backup_file")

    # Upload to remote storage
    upload_to_remote "$backup_file"

    # Cleanup old backups
    cleanup_old_backups

    log_success "==========================================="
    log_success "  Backup completed successfully!"
    log_success "==========================================="
    log_info "Backup file: $(basename $backup_file)"
    log_info "Log file: $LOG_FILE"

    exit 0
}

# Run main function
main "$@"
