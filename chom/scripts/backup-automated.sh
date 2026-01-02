#!/bin/bash

# Automated Backup Script for CHOM Production
# Handles database, files, and configuration backups with S3 sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/chom/backup_${TIMESTAMP}.log"

# Configuration
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/chom}"
APP_PATH="${APP_PATH:-/var/www/chom}"
S3_BUCKET="${S3_BUCKET:-chom-backups}"
S3_REGION="${S3_REGION:-eu-west-1}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
RETENTION_LOCAL_DAYS="${RETENTION_LOCAL_DAYS:-7}"
RETENTION_S3_DAYS="${RETENTION_S3_DAYS:-90}"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"
BACKUP_TYPES="${BACKUP_TYPES:-database,files,config}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
mkdir -p "$(dirname "$LOG_FILE")"

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

# Send notification
send_notification() {
    local status=$1
    local message=$2

    if [ -n "$SLACK_WEBHOOK" ]; then
        local color="good"
        [ "$status" = "error" ] && color="danger"
        [ "$status" = "warning" ] && color="warning"

        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Backup $status\",\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\",\"ts\":$(date +%s)}]}" \
            "$SLACK_WEBHOOK" > /dev/null 2>&1 || true
    fi
}

# Error handler
error_handler() {
    log_error "Backup failed at line $1"
    send_notification "error" "Automated backup failed at line $1. Check logs: $LOG_FILE"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Create backup directories
create_backup_dirs() {
    log_info "Creating backup directories..."
    mkdir -p "${BACKUP_ROOT}"/{database,files,config,temp}
    log_success "Backup directories created"
}

# Backup database
backup_database() {
    log_info "========================================="
    log_info "  DATABASE BACKUP"
    log_info "========================================="

    local backup_file="${BACKUP_ROOT}/database/db_backup_${TIMESTAMP}.sql"
    local compressed_file="${backup_file}.gz"

    cd "$APP_PATH"

    # Get database credentials from .env
    DB_CONNECTION=$(grep "^DB_CONNECTION=" .env | cut -d= -f2)
    DB_DATABASE=$(grep "^DB_DATABASE=" .env | cut -d= -f2)
    DB_HOST=$(grep "^DB_HOST=" .env | cut -d= -f2 || echo "localhost")
    DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d= -f2)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d= -f2)
    DB_PORT=$(grep "^DB_PORT=" .env | cut -d= -f2 || echo "3306")

    log_info "Backing up database: ${DB_DATABASE}"

    if [ "$DB_CONNECTION" = "mysql" ]; then
        # MySQL backup
        mysqldump \
            --host="${DB_HOST}" \
            --port="${DB_PORT}" \
            --user="${DB_USERNAME}" \
            --password="${DB_PASSWORD}" \
            --single-transaction \
            --quick \
            --lock-tables=false \
            --routines \
            --triggers \
            --events \
            "${DB_DATABASE}" > "${backup_file}"

        # Compress
        gzip -9 "${backup_file}"
        backup_file="${compressed_file}"

    elif [ "$DB_CONNECTION" = "sqlite" ]; then
        # SQLite backup
        sqlite3 "${APP_PATH}/database/database.sqlite" ".backup '${backup_file}'"
        gzip -9 "${backup_file}"
        backup_file="${compressed_file}"
    else
        log_error "Unsupported database type: ${DB_CONNECTION}"
        return 1
    fi

    # Encrypt if key provided
    if [ -n "$ENCRYPTION_KEY" ]; then
        log_info "Encrypting database backup..."
        openssl enc -aes-256-cbc -salt -pbkdf2 \
            -in "${backup_file}" \
            -out "${backup_file}.enc" \
            -k "$ENCRYPTION_KEY"
        rm "${backup_file}"
        backup_file="${backup_file}.enc"
    fi

    local size=$(du -h "${backup_file}" | cut -f1)
    log_success "Database backup created: ${backup_file} (${size})"

    # Upload to S3
    if command -v aws &> /dev/null; then
        log_info "Uploading to S3..."
        aws s3 cp "${backup_file}" "s3://${S3_BUCKET}/database/" \
            --region "${S3_REGION}" \
            --storage-class STANDARD_IA
        log_success "Database backup uploaded to S3"
    else
        log_warning "AWS CLI not found, skipping S3 upload"
    fi

    # Verify backup
    if [ -s "${backup_file}" ]; then
        log_success "Database backup verified (non-zero size)"
    else
        log_error "Database backup is empty!"
        return 1
    fi

    echo "${backup_file}"
}

# Backup files (storage directory)
backup_files() {
    log_info "========================================="
    log_info "  FILES BACKUP"
    log_info "========================================="

    local backup_file="${BACKUP_ROOT}/files/storage_backup_${TIMESTAMP}.tar.gz"
    local storage_path="${APP_PATH}/storage"

    if [ ! -d "$storage_path" ]; then
        log_warning "Storage directory not found: ${storage_path}"
        return 0
    fi

    log_info "Backing up storage directory..."

    # Create tar archive excluding logs and cache
    tar -czf "${backup_file}" \
        -C "$(dirname "$storage_path")" \
        --exclude='logs/*' \
        --exclude='framework/cache/*' \
        --exclude='framework/sessions/*' \
        --exclude='framework/views/*' \
        "$(basename "$storage_path")"

    # Encrypt if key provided
    if [ -n "$ENCRYPTION_KEY" ]; then
        log_info "Encrypting files backup..."
        openssl enc -aes-256-cbc -salt -pbkdf2 \
            -in "${backup_file}" \
            -out "${backup_file}.enc" \
            -k "$ENCRYPTION_KEY"
        rm "${backup_file}"
        backup_file="${backup_file}.enc"
    fi

    local size=$(du -h "${backup_file}" | cut -f1)
    log_success "Files backup created: ${backup_file} (${size})"

    # Upload to S3
    if command -v aws &> /dev/null; then
        log_info "Uploading to S3..."
        aws s3 cp "${backup_file}" "s3://${S3_BUCKET}/files/" \
            --region "${S3_REGION}" \
            --storage-class STANDARD_IA
        log_success "Files backup uploaded to S3"
    fi

    echo "${backup_file}"
}

# Backup configuration files
backup_config() {
    log_info "========================================="
    log_info "  CONFIGURATION BACKUP"
    log_info "========================================="

    local backup_file="${BACKUP_ROOT}/config/config_backup_${TIMESTAMP}.tar.gz"
    local temp_dir="${BACKUP_ROOT}/temp/config_${TIMESTAMP}"

    mkdir -p "$temp_dir"

    # Collect configuration files
    log_info "Collecting configuration files..."

    # Application .env
    if [ -f "${APP_PATH}/.env" ]; then
        cp "${APP_PATH}/.env" "${temp_dir}/.env"
    fi

    # Nginx configs
    if [ -d "/etc/nginx/sites-available" ]; then
        mkdir -p "${temp_dir}/nginx"
        cp -r /etc/nginx/sites-available "${temp_dir}/nginx/"
        cp /etc/nginx/nginx.conf "${temp_dir}/nginx/" 2>/dev/null || true
    fi

    # SSL certificates
    if [ -d "/etc/letsencrypt" ]; then
        mkdir -p "${temp_dir}/ssl"
        cp -r /etc/letsencrypt "${temp_dir}/ssl/" 2>/dev/null || true
    fi

    # Supervisor configs
    if [ -d "/etc/supervisor/conf.d" ]; then
        mkdir -p "${temp_dir}/supervisor"
        cp -r /etc/supervisor/conf.d "${temp_dir}/supervisor/" 2>/dev/null || true
    fi

    # Cron jobs
    crontab -l > "${temp_dir}/crontab.txt" 2>/dev/null || true

    # System info
    cat > "${temp_dir}/system_info.txt" <<EOF
Backup Date: $(date)
Hostname: $(hostname)
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)
PHP Version: $(php -v | head -1)
MySQL Version: $(mysql --version)
Nginx Version: $(nginx -v 2>&1)
EOF

    # Create archive
    tar -czf "${backup_file}" -C "${temp_dir}" .

    # Encrypt (configuration contains sensitive data)
    if [ -n "$ENCRYPTION_KEY" ]; then
        log_info "Encrypting configuration backup..."
        openssl enc -aes-256-cbc -salt -pbkdf2 \
            -in "${backup_file}" \
            -out "${backup_file}.enc" \
            -k "$ENCRYPTION_KEY"
        rm "${backup_file}"
        backup_file="${backup_file}.enc"
    else
        log_warning "No encryption key provided for configuration backup!"
    fi

    # Cleanup temp directory
    rm -rf "$temp_dir"

    local size=$(du -h "${backup_file}" | cut -f1)
    log_success "Configuration backup created: ${backup_file} (${size})"

    # Upload to S3
    if command -v aws &> /dev/null; then
        log_info "Uploading to S3..."
        aws s3 cp "${backup_file}" "s3://${S3_BUCKET}/config/" \
            --region "${S3_REGION}" \
            --storage-class STANDARD_IA
        log_success "Configuration backup uploaded to S3"
    fi

    echo "${backup_file}"
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "========================================="
    log_info "  CLEANUP OLD BACKUPS"
    log_info "========================================="

    # Local cleanup
    log_info "Cleaning up local backups older than ${RETENTION_LOCAL_DAYS} days..."

    for dir in database files config; do
        find "${BACKUP_ROOT}/${dir}" -type f -mtime "+${RETENTION_LOCAL_DAYS}" -delete 2>/dev/null || true
        local count=$(find "${BACKUP_ROOT}/${dir}" -type f | wc -l)
        log_info "  ${dir}: ${count} backups remaining"
    done

    # S3 cleanup (if AWS CLI available)
    if command -v aws &> /dev/null; then
        log_info "Cleaning up S3 backups older than ${RETENTION_S3_DAYS} days..."

        # Set lifecycle policy (run once, then policy handles it)
        cat > /tmp/lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "Id": "DeleteOldDatabaseBackups",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "database/"
      },
      "Expiration": {
        "Days": ${RETENTION_S3_DAYS}
      }
    },
    {
      "Id": "DeleteOldFileBackups",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "files/"
      },
      "Expiration": {
        "Days": ${RETENTION_S3_DAYS}
      }
    },
    {
      "Id": "TransitionOldBackupsToGlacier",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "GLACIER"
        }
      ]
    }
  ]
}
EOF

        aws s3api put-bucket-lifecycle-configuration \
            --bucket "${S3_BUCKET}" \
            --lifecycle-configuration file:///tmp/lifecycle-policy.json \
            2>/dev/null || log_warning "Failed to set S3 lifecycle policy"

        rm /tmp/lifecycle-policy.json
    fi

    log_success "Cleanup completed"
}

# Verify backups
verify_backups() {
    log_info "========================================="
    log_info "  BACKUP VERIFICATION"
    log_info "========================================="

    local verification_passed=true

    # Verify latest database backup
    local latest_db=$(ls -t "${BACKUP_ROOT}/database/"* 2>/dev/null | head -1)
    if [ -n "$latest_db" ] && [ -s "$latest_db" ]; then
        log_success "Latest database backup verified: $(basename "$latest_db")"
    else
        log_error "No valid database backup found!"
        verification_passed=false
    fi

    # Verify latest files backup
    local latest_files=$(ls -t "${BACKUP_ROOT}/files/"* 2>/dev/null | head -1)
    if [ -n "$latest_files" ] && [ -s "$latest_files" ]; then
        log_success "Latest files backup verified: $(basename "$latest_files")"
    else
        log_warning "No valid files backup found"
    fi

    # Verify S3 sync
    if command -v aws &> /dev/null; then
        local s3_count=$(aws s3 ls "s3://${S3_BUCKET}/database/" --recursive | wc -l)
        log_info "S3 database backups count: ${s3_count}"
    fi

    if [ "$verification_passed" = true ]; then
        log_success "Backup verification passed"
        return 0
    else
        log_error "Backup verification failed"
        return 1
    fi
}

# Generate backup report
generate_report() {
    log_info "========================================="
    log_info "  BACKUP REPORT"
    log_info "========================================="

    local report_file="${BACKUP_ROOT}/reports/backup_report_${TIMESTAMP}.txt"
    mkdir -p "$(dirname "$report_file")"

    cat > "$report_file" <<EOF
================================================================================
CHOM AUTOMATED BACKUP REPORT
================================================================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Duration: ${SECONDS} seconds
Status: ${BACKUP_STATUS}

BACKUP LOCATIONS
--------------------------------------------------------------------------------
Local: ${BACKUP_ROOT}
S3: s3://${S3_BUCKET}
Region: ${S3_REGION}

BACKUP SIZES
--------------------------------------------------------------------------------
Database: $(du -sh "${BACKUP_ROOT}/database" 2>/dev/null | cut -f1)
Files: $(du -sh "${BACKUP_ROOT}/files" 2>/dev/null | cut -f1)
Config: $(du -sh "${BACKUP_ROOT}/config" 2>/dev/null | cut -f1)
Total Local: $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)

BACKUP COUNTS
--------------------------------------------------------------------------------
Database Backups: $(find "${BACKUP_ROOT}/database" -type f 2>/dev/null | wc -l)
Files Backups: $(find "${BACKUP_ROOT}/files" -type f 2>/dev/null | wc -l)
Config Backups: $(find "${BACKUP_ROOT}/config" -type f 2>/dev/null | wc -l)

RETENTION POLICY
--------------------------------------------------------------------------------
Local: ${RETENTION_LOCAL_DAYS} days
S3: ${RETENTION_S3_DAYS} days

ENCRYPTION
--------------------------------------------------------------------------------
Enabled: $([ -n "$ENCRYPTION_KEY" ] && echo "Yes" || echo "No")

LOG FILE
--------------------------------------------------------------------------------
${LOG_FILE}

================================================================================
EOF

    log_info "Report generated: ${report_file}"
    cat "$report_file"
}

# Main execution
main() {
    log_info "========================================="
    log_info "  AUTOMATED BACKUP STARTED"
    log_info "========================================="
    log_info "Timestamp: ${TIMESTAMP}"
    log_info "Backup types: ${BACKUP_TYPES}"

    BACKUP_STATUS="SUCCESS"

    # Create directories
    create_backup_dirs

    # Perform backups based on configuration
    IFS=',' read -ra TYPES <<< "$BACKUP_TYPES"

    for backup_type in "${TYPES[@]}"; do
        case "$backup_type" in
            database)
                backup_database || BACKUP_STATUS="PARTIAL_FAILURE"
                ;;
            files)
                backup_files || BACKUP_STATUS="PARTIAL_FAILURE"
                ;;
            config)
                backup_config || BACKUP_STATUS="PARTIAL_FAILURE"
                ;;
            *)
                log_warning "Unknown backup type: ${backup_type}"
                ;;
        esac
    done

    # Cleanup old backups
    cleanup_old_backups

    # Verify backups
    if ! verify_backups; then
        BACKUP_STATUS="VERIFICATION_FAILED"
    fi

    # Generate report
    generate_report

    # Send notification
    if [ "$BACKUP_STATUS" = "SUCCESS" ]; then
        send_notification "success" "Automated backup completed successfully in ${SECONDS} seconds"
        log_success "========================================="
        log_success "  BACKUP COMPLETED SUCCESSFULLY"
        log_success "========================================="
        exit 0
    else
        send_notification "warning" "Backup completed with status: ${BACKUP_STATUS}. Check logs: ${LOG_FILE}"
        log_warning "========================================="
        log_warning "  BACKUP COMPLETED WITH ISSUES"
        log_warning "  Status: ${BACKUP_STATUS}"
        log_warning "========================================="
        exit 1
    fi
}

# Run main function
main
