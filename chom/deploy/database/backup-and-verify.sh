#!/bin/bash
################################################################################
# Database Backup with Verification Script
# Creates encrypted database backups with integrity verification
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-backup_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-chom}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
VERIFY_RESTORE="${VERIFY_RESTORE:-true}"
S3_BUCKET="${S3_BUCKET:-}"
S3_REGION="${S3_REGION:-eu-west-1}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_STAMP=$(date +%Y-%m-%d)

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Database Backup with Verification                      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check prerequisites
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}Enter database password for user ${DB_USER}:${NC}"
    read -s DB_PASSWORD
    echo
fi

# Create backup directories
mkdir -p "${BACKUP_DIR}"/{daily,weekly,monthly,logs}
BACKUP_FILE="${BACKUP_DIR}/daily/${DB_NAME}_${TIMESTAMP}.sql"
LOG_FILE="${BACKUP_DIR}/logs/backup_${TIMESTAMP}.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handler
error_handler() {
    log_error "Backup failed at line $1"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Step 1: Pre-backup checks
echo -e "${BLUE}[1/10]${NC} Running pre-backup checks..."
log "Starting backup process for database: ${DB_NAME}"

# Test database connection
if ! mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; then
    log_error "Cannot connect to database"
    exit 1
fi
log_success "Database connection successful"

# Check disk space (need at least 2x database size)
DB_SIZE=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -N -s -e "
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 0)
    FROM information_schema.tables
    WHERE table_schema = '${DB_NAME}'
")
AVAILABLE_SPACE=$(df -m "${BACKUP_DIR}" | tail -1 | awk '{print $4}')

if [ "$AVAILABLE_SPACE" -lt "$((DB_SIZE * 2))" ]; then
    log_error "Insufficient disk space. Need: $((DB_SIZE * 2))MB, Available: ${AVAILABLE_SPACE}MB"
    exit 1
fi
log_success "Disk space check passed (${AVAILABLE_SPACE}MB available, ${DB_SIZE}MB needed)"
echo

# Step 2: Create database backup
echo -e "${BLUE}[2/10]${NC} Creating database backup..."
log "Database size: ${DB_SIZE}MB"
log "Backup file: ${BACKUP_FILE}"

START_TIME=$(date +%s)

mysqldump \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --user="${DB_USER}" \
    --password="${DB_PASSWORD}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \
    --master-data=2 \
    --flush-logs \
    --databases "${DB_NAME}" > "${BACKUP_FILE}"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_success "Backup created in ${DURATION} seconds"
echo

# Step 3: Compress backup
echo -e "${BLUE}[3/10]${NC} Compressing backup..."
gzip -9 "${BACKUP_FILE}"
BACKUP_FILE="${BACKUP_FILE}.gz"

COMPRESSED_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
log_success "Backup compressed to ${COMPRESSED_SIZE}"
echo

# Step 4: Generate checksum
echo -e "${BLUE}[4/10]${NC} Generating checksum..."
CHECKSUM=$(sha256sum "${BACKUP_FILE}" | awk '{print $1}')
echo "${CHECKSUM}  $(basename ${BACKUP_FILE})" > "${BACKUP_FILE}.sha256"
log_success "Checksum: ${CHECKSUM}"
echo

# Step 5: Encrypt backup
if [ -n "$ENCRYPTION_KEY" ]; then
    echo -e "${BLUE}[5/10]${NC} Encrypting backup..."
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${BACKUP_FILE}" \
        -out "${BACKUP_FILE}.enc" \
        -k "$ENCRYPTION_KEY"

    # Verify encryption
    if [ -s "${BACKUP_FILE}.enc" ]; then
        rm "${BACKUP_FILE}"
        BACKUP_FILE="${BACKUP_FILE}.enc"
        log_success "Backup encrypted successfully"
    else
        log_error "Encryption failed"
        exit 1
    fi
else
    echo -e "${YELLOW}[5/10] Skipping encryption (no key provided)${NC}"
    log "WARNING: Backup not encrypted"
fi
echo

# Step 6: Verify backup integrity
echo -e "${BLUE}[6/10]${NC} Verifying backup integrity..."

if [ -s "${BACKUP_FILE}" ]; then
    ACTUAL_SIZE=$(stat -c%s "${BACKUP_FILE}")
    if [ "$ACTUAL_SIZE" -gt 0 ]; then
        log_success "Backup file is valid (${ACTUAL_SIZE} bytes)"
    else
        log_error "Backup file is empty"
        exit 1
    fi
else
    log_error "Backup file does not exist or is empty"
    exit 1
fi
echo

# Step 7: Test restore (optional)
if [ "$VERIFY_RESTORE" = "true" ]; then
    echo -e "${BLUE}[7/10]${NC} Testing backup restore..."

    # Create temporary test database
    TEST_DB="${DB_NAME}_restore_test_${TIMESTAMP}"
    log "Creating test database: ${TEST_DB}"

    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "CREATE DATABASE ${TEST_DB}"

    # Decrypt if encrypted
    TEST_FILE="${BACKUP_FILE}"
    if [[ "${BACKUP_FILE}" == *.enc ]]; then
        TEST_FILE="${BACKUP_FILE%.enc}"
        openssl enc -aes-256-cbc -d -pbkdf2 \
            -in "${BACKUP_FILE}" \
            -out "${TEST_FILE}" \
            -k "$ENCRYPTION_KEY"
    fi

    # Decompress
    if [[ "${TEST_FILE}" == *.gz ]]; then
        gunzip -c "${TEST_FILE}" > "${TEST_FILE%.gz}"
        TEST_FILE="${TEST_FILE%.gz}"
    fi

    # Restore to test database
    log "Restoring to test database..."
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} "${TEST_DB}" < "${TEST_FILE}"

    # Verify table count
    ORIGINAL_TABLES=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")
    RESTORED_TABLES=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${TEST_DB}'")

    if [ "$ORIGINAL_TABLES" -eq "$RESTORED_TABLES" ]; then
        log_success "Restore test passed (${RESTORED_TABLES} tables restored)"
    else
        log_error "Restore test failed (expected ${ORIGINAL_TABLES} tables, got ${RESTORED_TABLES})"
        mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "DROP DATABASE ${TEST_DB}"
        exit 1
    fi

    # Cleanup
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "DROP DATABASE ${TEST_DB}"
    rm -f "${TEST_FILE}"

    log_success "Test database cleaned up"
else
    echo -e "${YELLOW}[7/10] Skipping restore test${NC}"
fi
echo

# Step 8: Upload to S3 (if configured)
if [ -n "$S3_BUCKET" ]; then
    echo -e "${BLUE}[8/10]${NC} Uploading to S3..."

    if command -v aws &> /dev/null; then
        aws s3 cp "${BACKUP_FILE}" "s3://${S3_BUCKET}/database/${DATE_STAMP}/" \
            --region "${S3_REGION}" \
            --storage-class STANDARD_IA

        aws s3 cp "${BACKUP_FILE}.sha256" "s3://${S3_BUCKET}/database/${DATE_STAMP}/" \
            --region "${S3_REGION}"

        log_success "Backup uploaded to S3: s3://${S3_BUCKET}/database/${DATE_STAMP}/"
    else
        log_error "AWS CLI not found, skipping S3 upload"
    fi
else
    echo -e "${YELLOW}[8/10] Skipping S3 upload (not configured)${NC}"
fi
echo

# Step 9: Manage retention
echo -e "${BLUE}[9/10]${NC} Managing backup retention..."

# Copy to weekly/monthly if needed
DAY_OF_WEEK=$(date +%u)
DAY_OF_MONTH=$(date +%d)

if [ "$DAY_OF_WEEK" -eq 7 ]; then
    cp "${BACKUP_FILE}" "${BACKUP_DIR}/weekly/${DB_NAME}_week_${TIMESTAMP}.sql.gz.enc"
    log "Weekly backup created"
fi

if [ "$DAY_OF_MONTH" -eq 1 ]; then
    cp "${BACKUP_FILE}" "${BACKUP_DIR}/monthly/${DB_NAME}_month_${TIMESTAMP}.sql.gz.enc"
    log "Monthly backup created"
fi

# Remove old daily backups
find "${BACKUP_DIR}/daily" -name "*.sql.gz*" -mtime +${RETENTION_DAYS} -delete
log "Removed daily backups older than ${RETENTION_DAYS} days"

# Keep last 4 weekly backups
ls -t "${BACKUP_DIR}/weekly"/*.sql.gz* 2>/dev/null | tail -n +5 | xargs rm -f 2>/dev/null || true
log "Kept last 4 weekly backups"

# Keep last 12 monthly backups
ls -t "${BACKUP_DIR}/monthly"/*.sql.gz* 2>/dev/null | tail -n +13 | xargs rm -f 2>/dev/null || true
log "Kept last 12 monthly backups"

log_success "Retention policy applied"
echo

# Step 10: Generate backup report
echo -e "${BLUE}[10/10]${NC} Generating backup report..."

REPORT_FILE="${BACKUP_DIR}/logs/backup_report_${TIMESTAMP}.txt"

cat > "$REPORT_FILE" <<EOF
================================================================================
DATABASE BACKUP REPORT
================================================================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Database: ${DB_NAME}
Backup File: ${BACKUP_FILE}
Backup Size: ${COMPRESSED_SIZE}
Checksum: ${CHECKSUM}
Duration: ${DURATION} seconds
Encrypted: $([ -n "$ENCRYPTION_KEY" ] && echo "Yes" || echo "No")
Restore Test: $([ "$VERIFY_RESTORE" = "true" ] && echo "Passed" || echo "Skipped")
S3 Upload: $([ -n "$S3_BUCKET" ] && echo "Yes" || echo "No")

BACKUP INVENTORY
================================================================================
Daily Backups: $(ls -1 "${BACKUP_DIR}/daily"/*.sql.gz* 2>/dev/null | wc -l)
Weekly Backups: $(ls -1 "${BACKUP_DIR}/weekly"/*.sql.gz* 2>/dev/null | wc -l)
Monthly Backups: $(ls -1 "${BACKUP_DIR}/monthly"/*.sql.gz* 2>/dev/null | wc -l)

Total Backup Size: $(du -sh "${BACKUP_DIR}" | cut -f1)

LATEST BACKUPS
================================================================================
EOF

echo "Daily:" >> "$REPORT_FILE"
ls -lh "${BACKUP_DIR}/daily"/*.sql.gz* 2>/dev/null | tail -5 >> "$REPORT_FILE" || echo "  None" >> "$REPORT_FILE"
echo >> "$REPORT_FILE"

echo "Weekly:" >> "$REPORT_FILE"
ls -lh "${BACKUP_DIR}/weekly"/*.sql.gz* 2>/dev/null | tail -4 >> "$REPORT_FILE" || echo "  None" >> "$REPORT_FILE"
echo >> "$REPORT_FILE"

echo "Monthly:" >> "$REPORT_FILE"
ls -lh "${BACKUP_DIR}/monthly"/*.sql.gz* 2>/dev/null | tail -12 >> "$REPORT_FILE" || echo "  None" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" <<EOF

================================================================================
BACKUP VERIFICATION STEPS
================================================================================
1. Verify checksum:
   sha256sum -c ${BACKUP_FILE}.sha256

2. Decrypt backup (if encrypted):
   openssl enc -aes-256-cbc -d -pbkdf2 -in ${BACKUP_FILE} -out backup.sql.gz -k <key>

3. Decompress:
   gunzip backup.sql.gz

4. Restore:
   mysql -h ${DB_HOST} -u ${DB_USER} -p ${DB_NAME} < backup.sql

================================================================================
EOF

log_success "Backup report generated: ${REPORT_FILE}"
echo

# Summary
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Backup completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo "Database: ${DB_NAME}"
echo "Backup File: ${BACKUP_FILE}"
echo "Size: ${COMPRESSED_SIZE}"
echo "Checksum: ${CHECKSUM}"
echo "Duration: ${DURATION} seconds"
echo "Encrypted: $([ -n "$ENCRYPTION_KEY" ] && echo "Yes" || echo "No")"
echo "Report: ${REPORT_FILE}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

exit 0
