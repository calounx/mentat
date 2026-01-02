#!/bin/bash
#==============================================================================
# CHOM Backup Automation Script
#==============================================================================
# Purpose: Automate backup of CHOM application components
# Author: DevOps Team
# Version: 1.0
# Created: 2026-01-02
#
# Components:
#   - MariaDB database (full, incremental, binlog)
#   - Application files
#   - Configuration files
#   - SSL certificates
#   - Docker volumes
#   - User uploads
#
# Usage:
#   ./backup-chom.sh --full                          # Full backup of all components
#   ./backup-chom.sh --incremental --component db    # Incremental database backup
#   ./backup-chom.sh --component mysql               # Backup database only
#   ./backup-chom.sh --list                          # List available backups
#   ./backup-chom.sh --status                        # Show backup status
#==============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHOM_ROOT="/opt/chom"
BACKUP_ROOT="/backups/chom"
REMOTE_BACKUP_HOST="${REMOTE_BACKUP_HOST:-51.254.139.78}"
REMOTE_BACKUP_USER="${REMOTE_BACKUP_USER:-deploy}"
REMOTE_BACKUP_PATH="/backups/chom-remote"

# Timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DATE_ONLY=$(date +%Y%m%d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/chom-backup.log"
METRICS_FILE="/var/lib/chom/backup-metrics.prom"

#==============================================================================
# Functions
#==============================================================================

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

write_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local labels="${3:-}"

    mkdir -p "$(dirname "$METRICS_FILE")"

    if [ -n "$labels" ]; then
        echo "${metric_name}{${labels}} ${metric_value} $(date +%s)000" >> "$METRICS_FILE"
    else
        echo "${metric_name} ${metric_value} $(date +%s)000" >> "$METRICS_FILE"
    fi
}

check_requirements() {
    log_info "Checking requirements..."

    # Check if running on landsraad
    if [ ! -d "$CHOM_ROOT" ]; then
        log_error "CHOM root directory not found: $CHOM_ROOT"
        log_error "This script should run on landsraad VPS"
        exit 1
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi

    # Check if containers are running
    if ! docker ps | grep -q chom-mysql; then
        log_warning "MySQL container not running. Some backups may fail."
    fi

    # Create backup directories
    mkdir -p "$BACKUP_ROOT"/{mysql/{full/{daily,weekly,monthly},incremental,binlogs},app/{full,pre-deployment},config,ssl,volumes,uploads/{incremental,full}}

    log_success "Requirements check passed"
}

backup_database_full() {
    log_info "Starting full database backup..."

    local backup_file="$BACKUP_ROOT/mysql/full/daily/full-${TIMESTAMP}.sql.gz"
    local start_time=$(date +%s)

    # Check if MySQL is running
    if ! docker ps | grep -q chom-mysql; then
        log_error "MySQL container not running"
        write_metric "backup_success" "0" "component=\"database\",type=\"full\""
        return 1
    fi

    # Perform backup
    log_info "Dumping database to: $backup_file"

    if docker exec chom-mysql mysqldump \
        --all-databases \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --routines \
        --triggers \
        --events \
        --master-data=2 \
        --flush-logs \
        2>> "$LOG_FILE" \
        | gzip > "$backup_file"; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file")

        log_success "Database backup completed"
        log_info "  Size: $(numfmt --to=iec-i --suffix=B $size)"
        log_info "  Duration: ${duration}s"

        # Create 'latest' symlink
        ln -sf "$backup_file" "$BACKUP_ROOT/mysql/full/latest.sql.gz"

        # Write metrics
        write_metric "backup_success" "1" "component=\"database\",type=\"full\""
        write_metric "backup_size_bytes" "$size" "component=\"database\",type=\"full\""
        write_metric "backup_duration_seconds" "$duration" "component=\"database\",type=\"full\""
        write_metric "backup_timestamp" "$(date +%s)" "component=\"database\",type=\"full\""

        # Verify backup
        if gunzip -t "$backup_file" 2>/dev/null; then
            log_success "Backup verification passed"
            write_metric "backup_verification_success" "1" "component=\"database\""
        else
            log_error "Backup verification failed"
            write_metric "backup_verification_success" "0" "component=\"database\""
            return 1
        fi

        # Weekly backup (Sunday)
        if [ "$(date +%u)" -eq 7 ]; then
            cp "$backup_file" "$BACKUP_ROOT/mysql/full/weekly/full-${DATE_ONLY}.sql.gz"
            log_info "Created weekly backup"
        fi

        # Monthly backup (1st of month)
        if [ "$(date +%d)" -eq 01 ]; then
            cp "$backup_file" "$BACKUP_ROOT/mysql/full/monthly/full-${DATE_ONLY}.sql.gz"
            log_info "Created monthly backup"
        fi

        return 0
    else
        log_error "Database backup failed"
        write_metric "backup_success" "0" "component=\"database\",type=\"full\""
        return 1
    fi
}

backup_database_incremental() {
    log_info "Starting incremental database backup..."

    local backup_file="$BACKUP_ROOT/mysql/incremental/incr-${TIMESTAMP}.sql.gz"
    local start_time=$(date +%s)

    # Incremental backup using binary logs
    if docker exec chom-mysql mysql -e "FLUSH BINARY LOGS;" 2>> "$LOG_FILE"; then
        # Quick mysqldump for recent changes
        if docker exec chom-mysql mysqldump \
            --all-databases \
            --single-transaction \
            --quick \
            --lock-tables=false \
            2>> "$LOG_FILE" \
            | gzip > "$backup_file"; then

            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file")

            log_success "Incremental backup completed"
            log_info "  Size: $(numfmt --to=iec-i --suffix=B $size)"
            log_info "  Duration: ${duration}s"

            write_metric "backup_success" "1" "component=\"database\",type=\"incremental\""
            write_metric "backup_size_bytes" "$size" "component=\"database\",type=\"incremental\""
            write_metric "backup_duration_seconds" "$duration" "component=\"database\",type=\"incremental\""

            return 0
        fi
    fi

    log_error "Incremental backup failed"
    write_metric "backup_success" "0" "component=\"database\",type=\"incremental\""
    return 1
}

backup_application() {
    log_info "Starting application backup..."

    local backup_file="$BACKUP_ROOT/app/full/app-${TIMESTAMP}.tar.gz"
    local start_time=$(date +%s)

    if tar czf "$backup_file" \
        --exclude='vendor' \
        --exclude='node_modules' \
        --exclude='storage/framework/cache/*' \
        --exclude='storage/logs/*.log' \
        --exclude='.git' \
        -C "$CHOM_ROOT" \
        . 2>> "$LOG_FILE"; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file")

        log_success "Application backup completed"
        log_info "  Size: $(numfmt --to=iec-i --suffix=B $size)"
        log_info "  Duration: ${duration}s"

        # Create 'latest' symlink
        ln -sf "$backup_file" "$BACKUP_ROOT/app/full/latest.tar.gz"

        write_metric "backup_success" "1" "component=\"application\",type=\"full\""
        write_metric "backup_size_bytes" "$size" "component=\"application\",type=\"full\""
        write_metric "backup_duration_seconds" "$duration" "component=\"application\",type=\"full\""

        # Verify
        if tar tzf "$backup_file" > /dev/null 2>&1; then
            log_success "Application backup verification passed"
            return 0
        else
            log_error "Application backup verification failed"
            return 1
        fi
    else
        log_error "Application backup failed"
        write_metric "backup_success" "0" "component=\"application\",type=\"full\""
        return 1
    fi
}

backup_configuration() {
    log_info "Starting configuration backup..."

    local backup_file="$BACKUP_ROOT/config/config-${TIMESTAMP}.tar.gz"
    local start_time=$(date +%s)

    # Create temporary directory for configs
    local temp_dir=$(mktemp -d)

    # Copy configuration files
    mkdir -p "$temp_dir/chom"
    cp -p "$CHOM_ROOT/.env" "$temp_dir/chom/" 2>/dev/null || log_warning ".env not found"
    cp -p "$CHOM_ROOT/docker-compose.production.yml" "$temp_dir/chom/" 2>/dev/null || true
    cp -rp "$CHOM_ROOT/docker/production" "$temp_dir/chom/" 2>/dev/null || true
    cp -rp "$CHOM_ROOT/config" "$temp_dir/chom/" 2>/dev/null || true

    # Copy system configs
    mkdir -p "$temp_dir/system"
    cp -p /etc/cron.d/chom-* "$temp_dir/system/" 2>/dev/null || true
    cp -p /etc/systemd/system/chom-*.service "$temp_dir/system/" 2>/dev/null || true

    # Create archive
    if tar czf "$backup_file" -C "$temp_dir" . 2>> "$LOG_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file")

        log_success "Configuration backup completed"
        log_info "  Size: $(numfmt --to=iec-i --suffix=B $size)"

        # Create 'latest' symlink
        ln -sf "$backup_file" "$BACKUP_ROOT/config/latest.tar.gz"

        write_metric "backup_success" "1" "component=\"config\",type=\"full\""
        write_metric "backup_size_bytes" "$size" "component=\"config\",type=\"full\""

        rm -rf "$temp_dir"
        return 0
    else
        log_error "Configuration backup failed"
        write_metric "backup_success" "0" "component=\"config\",type=\"full\""
        rm -rf "$temp_dir"
        return 1
    fi
}

backup_ssl() {
    log_info "Starting SSL certificate backup..."

    local backup_file="$BACKUP_ROOT/ssl/ssl-${DATE_ONLY}.tar.gz"
    local ssl_dir="$CHOM_ROOT/docker/production/ssl"

    if [ ! -d "$ssl_dir" ]; then
        log_warning "SSL directory not found: $ssl_dir"
        return 0
    fi

    if tar czf "$backup_file" -C "$ssl_dir" . 2>> "$LOG_FILE"; then
        local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file")

        log_success "SSL certificate backup completed"
        log_info "  Size: $(numfmt --to=iec-i --suffix=B $size)"

        # Encrypt SSL backup (contains private keys)
        if command -v gpg &> /dev/null; then
            gpg --batch --yes --passphrase "${GPG_PASSPHRASE:-chom-backup-2026}" \
                --symmetric --cipher-algo AES256 \
                "$backup_file" 2>> "$LOG_FILE" || log_warning "GPG encryption failed"
        fi

        write_metric "backup_success" "1" "component=\"ssl\",type=\"full\""
        write_metric "backup_size_bytes" "$size" "component=\"ssl\",type=\"full\""

        return 0
    else
        log_error "SSL certificate backup failed"
        write_metric "backup_success" "0" "component=\"ssl\",type=\"full\""
        return 1
    fi
}

backup_volumes() {
    log_info "Starting Docker volumes backup..."

    local volumes=("mysql_data" "redis_data" "ssl-certs")
    local success=0

    for vol in "${volumes[@]}"; do
        log_info "Backing up volume: $vol"

        local backup_file="$BACKUP_ROOT/volumes/${vol}-${DATE_ONLY}.tar.gz"

        if docker run --rm \
            -v "${vol}:/source:ro" \
            -v "$BACKUP_ROOT/volumes:/backup" \
            alpine \
            tar czf "/backup/${vol}-${DATE_ONLY}.tar.gz" -C /source . 2>> "$LOG_FILE"; then

            local size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file")
            log_success "Volume $vol backed up ($(numfmt --to=iec-i --suffix=B $size))"
            ((success++))
        else
            log_error "Volume $vol backup failed"
        fi
    done

    if [ $success -eq ${#volumes[@]} ]; then
        write_metric "backup_success" "1" "component=\"volumes\",type=\"full\""
        return 0
    else
        write_metric "backup_success" "0" "component=\"volumes\",type=\"full\""
        return 1
    fi
}

backup_uploads() {
    log_info "Starting user uploads backup..."

    local uploads_dir="$CHOM_ROOT/storage/app"
    local backup_dir="$BACKUP_ROOT/uploads/full/${DATE_ONLY}"

    if [ ! -d "$uploads_dir" ]; then
        log_warning "Uploads directory not found: $uploads_dir"
        return 0
    fi

    mkdir -p "$backup_dir"

    if rsync -az --delete "$uploads_dir/" "$backup_dir/" 2>> "$LOG_FILE"; then
        local size=$(du -sb "$backup_dir" | awk '{print $1}')

        log_success "User uploads backup completed"
        log_info "  Size: $(numfmt --to=iec-i --suffix=B $size)"

        write_metric "backup_success" "1" "component=\"uploads\",type=\"full\""
        write_metric "backup_size_bytes" "$size" "component=\"uploads\",type=\"full\""

        return 0
    else
        log_error "User uploads backup failed"
        write_metric "backup_success" "0" "component=\"uploads\",type=\"full\""
        return 1
    fi
}

sync_to_remote() {
    log_info "Syncing backups to remote server..."

    # Check if SSH key exists
    if [ ! -f "$HOME/.ssh/id_rsa" ] && [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        log_warning "No SSH key found, skipping remote sync"
        return 0
    fi

    # Test connectivity
    if ! ssh -o ConnectTimeout=5 "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}" "echo OK" &>/dev/null; then
        log_warning "Cannot connect to remote backup server, skipping sync"
        return 0
    fi

    # Sync to remote
    if rsync -avz --delete \
        -e "ssh -o ConnectTimeout=10" \
        "$BACKUP_ROOT/" \
        "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/" \
        2>> "$LOG_FILE"; then

        log_success "Remote sync completed"
        write_metric "backup_remote_sync_success" "1"
        return 0
    else
        log_error "Remote sync failed"
        write_metric "backup_remote_sync_success" "0"
        return 1
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups..."

    # Daily backups: Keep 7 days
    find "$BACKUP_ROOT/mysql/full/daily/" -name "*.sql.gz" -mtime +7 -delete 2>/dev/null || true
    find "$BACKUP_ROOT/app/full/" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null || true

    # Incremental backups: Keep 24 hours
    find "$BACKUP_ROOT/mysql/incremental/" -name "*.sql.gz" -mtime +1 -delete 2>/dev/null || true

    # Weekly backups: Keep 4 weeks
    find "$BACKUP_ROOT/mysql/full/weekly/" -name "*.sql.gz" -mtime +28 -delete 2>/dev/null || true

    # Monthly backups: Keep 12 months
    find "$BACKUP_ROOT/mysql/full/monthly/" -name "*.sql.gz" -mtime +365 -delete 2>/dev/null || true

    # Config backups: Keep 30 days
    find "$BACKUP_ROOT/config/" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true

    # SSL backups: Keep 90 days
    find "$BACKUP_ROOT/ssl/" -name "*.tar.gz" -mtime +90 -delete 2>/dev/null || true

    # Volume backups: Keep 7 days
    find "$BACKUP_ROOT/volumes/" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null || true

    log_success "Old backups cleaned up"
}

list_backups() {
    echo ""
    echo "==================================================================="
    echo "  CHOM Backup Inventory"
    echo "==================================================================="
    echo ""

    echo "DATABASE BACKUPS:"
    echo "  Full (Daily):"
    ls -lh "$BACKUP_ROOT/mysql/full/daily/" 2>/dev/null | tail -5 || echo "    No backups found"
    echo ""
    echo "  Incremental:"
    ls -lh "$BACKUP_ROOT/mysql/incremental/" 2>/dev/null | tail -5 || echo "    No backups found"
    echo ""

    echo "APPLICATION BACKUPS:"
    ls -lh "$BACKUP_ROOT/app/full/" 2>/dev/null | tail -5 || echo "  No backups found"
    echo ""

    echo "CONFIGURATION BACKUPS:"
    ls -lh "$BACKUP_ROOT/config/" 2>/dev/null | tail -5 || echo "  No backups found"
    echo ""

    echo "SSL CERTIFICATE BACKUPS:"
    ls -lh "$BACKUP_ROOT/ssl/" 2>/dev/null | tail -5 || echo "  No backups found"
    echo ""

    echo "STORAGE USAGE:"
    du -sh "$BACKUP_ROOT"/* 2>/dev/null || echo "  No data"
    echo ""

    echo "TOTAL BACKUP SIZE:"
    du -sh "$BACKUP_ROOT" 2>/dev/null || echo "  No data"
    echo ""
}

show_status() {
    echo ""
    echo "==================================================================="
    echo "  CHOM Backup Status"
    echo "==================================================================="
    echo ""

    echo "LAST BACKUPS:"

    if [ -f "$BACKUP_ROOT/mysql/full/latest.sql.gz" ]; then
        local db_age=$(( $(date +%s) - $(stat -c%Y "$BACKUP_ROOT/mysql/full/latest.sql.gz" 2>/dev/null || stat -f%m "$BACKUP_ROOT/mysql/full/latest.sql.gz") ))
        local db_age_hr=$(( db_age / 3600 ))
        echo "  Database (Full): $(ls -lh "$BACKUP_ROOT/mysql/full/latest.sql.gz" | awk '{print $9, $6, $7, $8}') - ${db_age_hr}h ago"
    else
        echo "  Database (Full): No backup found"
    fi

    if [ -f "$BACKUP_ROOT/app/full/latest.tar.gz" ]; then
        local app_age=$(( $(date +%s) - $(stat -c%Y "$BACKUP_ROOT/app/full/latest.tar.gz" 2>/dev/null || stat -f%m "$BACKUP_ROOT/app/full/latest.tar.gz") ))
        local app_age_hr=$(( app_age / 3600 ))
        echo "  Application: $(ls -lh "$BACKUP_ROOT/app/full/latest.tar.gz" | awk '{print $9, $6, $7, $8}') - ${app_age_hr}h ago"
    else
        echo "  Application: No backup found"
    fi

    echo ""
    echo "DISK USAGE:"
    df -h "$BACKUP_ROOT" | tail -1
    echo ""

    echo "BACKUP HEALTH:"
    local issues=0

    # Check if backups are too old
    if [ -f "$BACKUP_ROOT/mysql/full/latest.sql.gz" ]; then
        local age=$(( $(date +%s) - $(stat -c%Y "$BACKUP_ROOT/mysql/full/latest.sql.gz" 2>/dev/null || stat -f%m "$BACKUP_ROOT/mysql/full/latest.sql.gz") ))
        if [ $age -gt 86400 ]; then
            echo "  WARNING: Database backup is older than 24 hours"
            ((issues++))
        fi
    else
        echo "  ERROR: No database backup found"
        ((issues++))
    fi

    # Check disk space
    local usage=$(df "$BACKUP_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$usage" -gt 80 ]; then
        echo "  WARNING: Backup storage ${usage}% full"
        ((issues++))
    fi

    if [ $issues -eq 0 ]; then
        echo "  OK: All checks passed"
    fi

    echo ""
}

#==============================================================================
# Main
#==============================================================================

usage() {
    cat << EOF
CHOM Backup Automation Script

Usage:
    $0 [OPTIONS]

Options:
    --full                      Full backup of all components
    --incremental               Incremental backup
    --component <name>          Backup specific component
                                Components: database, application, config, ssl, volumes, uploads
    --tag <tag>                 Add tag to backup filename
    --verify                    Verify backup after creation
    --remote <host>             Sync to remote server
    --list                      List available backups
    --status                    Show backup status
    --cleanup                   Clean up old backups
    --help                      Show this help message

Examples:
    $0 --full
    $0 --incremental --component database
    $0 --component mysql
    $0 --component application --tag pre-deployment
    $0 --status

EOF
}

# Parse arguments
BACKUP_TYPE=""
COMPONENT=""
TAG=""
VERIFY=false
REMOTE=""
ACTION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            BACKUP_TYPE="full"
            shift
            ;;
        --incremental)
            BACKUP_TYPE="incremental"
            shift
            ;;
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --remote)
            REMOTE="$2"
            shift 2
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --cleanup)
            ACTION="cleanup"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "CHOM Backup Script started"

    # Handle actions
    if [ "$ACTION" = "list" ]; then
        list_backups
        exit 0
    elif [ "$ACTION" = "status" ]; then
        show_status
        exit 0
    elif [ "$ACTION" = "cleanup" ]; then
        cleanup_old_backups
        exit 0
    fi

    # Check requirements
    check_requirements

    local overall_success=0
    local start_time=$(date +%s)

    # Perform backups based on options
    if [ "$BACKUP_TYPE" = "full" ]; then
        log_info "Starting FULL backup of all components..."

        backup_database_full || ((overall_success++))
        backup_application || ((overall_success++))
        backup_configuration || ((overall_success++))
        backup_ssl || ((overall_success++))
        backup_volumes || ((overall_success++))
        backup_uploads || ((overall_success++))

    elif [ "$BACKUP_TYPE" = "incremental" ]; then
        log_info "Starting INCREMENTAL backup..."

        if [ "$COMPONENT" = "database" ] || [ "$COMPONENT" = "mysql" ]; then
            backup_database_incremental || ((overall_success++))
        else
            log_error "Incremental backup only supported for database"
            exit 1
        fi

    elif [ -n "$COMPONENT" ]; then
        log_info "Starting backup of component: $COMPONENT"

        case "$COMPONENT" in
            database|mysql)
                backup_database_full || ((overall_success++))
                ;;
            application|app)
                backup_application || ((overall_success++))
                ;;
            config|configuration)
                backup_configuration || ((overall_success++))
                ;;
            ssl|certificates)
                backup_ssl || ((overall_success++))
                ;;
            volumes)
                backup_volumes || ((overall_success++))
                ;;
            uploads)
                backup_uploads || ((overall_success++))
                ;;
            *)
                log_error "Unknown component: $COMPONENT"
                exit 1
                ;;
        esac
    else
        log_error "No backup type or component specified"
        usage
        exit 1
    fi

    # Sync to remote if requested
    if [ -n "$REMOTE" ] || [ "$BACKUP_TYPE" = "full" ]; then
        sync_to_remote
    fi

    # Cleanup old backups
    cleanup_old_backups

    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))

    log_info "Backup operation completed in ${total_duration}s"

    if [ $overall_success -eq 0 ]; then
        log_success "ALL BACKUPS SUCCESSFUL"
        exit 0
    else
        log_error "SOME BACKUPS FAILED (${overall_success} failures)"
        exit 1
    fi
}

# Run main function
main
