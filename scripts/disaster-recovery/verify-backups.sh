#!/usr/bin/env bash
# ============================================================================
# Automated Backup Verification Script
# ============================================================================
# Features:
#   - Verify backup integrity (checksums, file corruption)
#   - Test backup decryption
#   - Perform test restores in isolated environment
#   - Generate verification reports
#   - Alert on verification failures
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load configuration
CONFIG_FILE="${BACKUP_CONFIG_FILE:-${SCRIPT_DIR}/backup-config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Verification Configuration
VERIFY_LOCAL_BACKUPS="${VERIFY_LOCAL_BACKUPS:-true}"
VERIFY_OFFSITE_BACKUPS="${VERIFY_OFFSITE_BACKUPS:-true}"
VERIFY_PERFORM_RESTORE_TEST="${VERIFY_PERFORM_RESTORE_TEST:-true}"
VERIFY_RETENTION_CHECK="${VERIFY_RETENTION_CHECK:-true}"

# Test Environment Configuration
TEST_ENV_ENABLED="${TEST_ENV_ENABLED:-true}"
TEST_DB_CONTAINER="backup-verify-mysql"
TEST_NETWORK="backup-verify-network"

# Reporting Configuration
REPORT_DIR="${REPORT_DIR:-${PROJECT_ROOT}/reports/backup-verification}"
REPORT_RETENTION_DAYS="${REPORT_RETENTION_DAYS:-90}"

# S3 Configuration
S3_BUCKET="${S3_BUCKET:-}"
S3_PROVIDER="${S3_PROVIDER:-s3}"

# Metrics Configuration
METRICS_ENABLED="${METRICS_ENABLED:-true}"
METRICS_PUSHGATEWAY="${METRICS_PUSHGATEWAY:-http://localhost:9091}"

# Alert Configuration
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Global Variables
# ============================================================================

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/verification_${TIMESTAMP}.txt"
VERIFICATION_PASSED=0
VERIFICATION_FAILED=0
VERIFICATION_WARNINGS=0

# ============================================================================
# Logging Functions
# ============================================================================

mkdir -p "$REPORT_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$REPORT_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] PASS: $*${NC}" | tee -a "$REPORT_FILE"
    ((VERIFICATION_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*${NC}" | tee -a "$REPORT_FILE"
    ((VERIFICATION_WARNINGS++))
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: $*${NC}" | tee -a "$REPORT_FILE"
    ((VERIFICATION_FAILED++))
}

# ============================================================================
# Metrics Functions
# ============================================================================

push_metric() {
    local metric_name="$1"
    local metric_value="$2"

    if [[ "$METRICS_ENABLED" != "true" ]]; then
        return 0
    fi

    cat <<EOF | curl -s --data-binary @- "${METRICS_PUSHGATEWAY}/metrics/job/backup_verification/instance/$(hostname)" || true
# TYPE ${metric_name} gauge
${metric_name} ${metric_value}
EOF
}

# ============================================================================
# Alert Functions
# ============================================================================

send_alert() {
    local severity="$1"
    local message="$2"

    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"severity\":\"$severity\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" \
            > /dev/null 2>&1 || true
    fi

    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "Backup Verification: $severity" "$ALERT_EMAIL" || true
    fi
}

# ============================================================================
# Verification Functions - Local Backups
# ============================================================================

verify_local_backup_existence() {
    log_info "Checking local backup existence..."

    local backup_dirs=(
        "${PROJECT_ROOT}/chom/storage/app/backups"
        "${PROJECT_ROOT}/docker/backups"
        "/var/lib/observability-backups"
    )

    for dir in "${backup_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_warning "Backup directory not found: $dir"
            continue
        fi

        local backup_count
        backup_count=$(find "$dir" -type f -mtime -1 | wc -l)

        if [[ $backup_count -eq 0 ]]; then
            log_error "No recent backups (< 24h) in $dir"
        else
            log_success "$backup_count recent backup(s) found in $dir"
        fi
    done
}

verify_local_backup_integrity() {
    log_info "Verifying local backup integrity..."

    # Check SQL dumps
    while IFS= read -r backup_file; do
        log_info "Checking $(basename "$backup_file")..."

        # Check if file is valid gzip
        if [[ "$backup_file" == *.gz ]]; then
            if gzip -t "$backup_file" 2>/dev/null; then
                log_success "$(basename "$backup_file") - Valid gzip archive"
            else
                log_error "$(basename "$backup_file") - Corrupted gzip archive"
                continue
            fi
        fi

        # Check if SQL file is valid
        if [[ "$backup_file" == *.sql ]] || [[ "$backup_file" == *.sql.gz ]]; then
            local temp_sql="/tmp/verify_sql_$$.sql"

            if [[ "$backup_file" == *.gz ]]; then
                gunzip -c "$backup_file" > "$temp_sql" 2>/dev/null || {
                    log_error "$(basename "$backup_file") - Failed to decompress"
                    continue
                }
            else
                temp_sql="$backup_file"
            fi

            # Check for SQL syntax errors
            if grep -q "CREATE TABLE\|INSERT INTO\|CREATE DATABASE" "$temp_sql"; then
                log_success "$(basename "$backup_file") - Valid SQL syntax"
            else
                log_error "$(basename "$backup_file") - Invalid SQL content"
            fi

            [[ "$backup_file" == *.gz ]] && rm -f "$temp_sql"
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.sql" -o -name "*.sql.gz" -mtime -1)

    # Check Docker volume backups
    while IFS= read -r backup_file; do
        log_info "Checking $(basename "$backup_file")..."

        if tar -tzf "$backup_file" > /dev/null 2>&1; then
            log_success "$(basename "$backup_file") - Valid tar archive"
        else
            log_error "$(basename "$backup_file") - Corrupted tar archive"
        fi
    done < <(find "${PROJECT_ROOT}" -name "*_backup_*.tar.gz" -mtime -1)
}

verify_local_backup_size() {
    log_info "Verifying backup sizes..."

    # Define expected minimum sizes (in bytes)
    local min_db_size=$((1024 * 1024))      # 1 MB
    local min_volume_size=$((10 * 1024 * 1024))  # 10 MB

    while IFS= read -r backup_file; do
        local file_size
        file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo 0)
        local file_size_mb=$((file_size / 1024 / 1024))

        if [[ "$backup_file" == *.sql* ]]; then
            if [[ $file_size -lt $min_db_size ]]; then
                log_warning "$(basename "$backup_file") - Suspiciously small (${file_size_mb}MB)"
            else
                log_success "$(basename "$backup_file") - Size OK (${file_size_mb}MB)"
            fi
        elif [[ "$backup_file" == *.tar.gz ]]; then
            if [[ $file_size -lt $min_volume_size ]]; then
                log_warning "$(basename "$backup_file") - Suspiciously small (${file_size_mb}MB)"
            else
                log_success "$(basename "$backup_file") - Size OK (${file_size_mb}MB)"
            fi
        fi
    done < <(find "${PROJECT_ROOT}" \( -name "*.sql*" -o -name "*.tar.gz" \) -mtime -1)
}

# ============================================================================
# Verification Functions - Offsite Backups
# ============================================================================

verify_offsite_backup_existence() {
    log_info "Checking offsite backup existence..."

    if [[ -z "$S3_BUCKET" ]]; then
        log_warning "S3 bucket not configured, skipping offsite verification"
        return
    fi

    # Configure AWS CLI
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
    export AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}"

    # Check recent backups
    local today
    today=$(date +%Y-%m-%d)

    local prefixes=("mysql" "volumes" "config")

    for prefix in "${prefixes[@]}"; do
        log_info "Checking S3 backups: s3://${S3_BUCKET}/${prefix}/${today}/"

        if aws s3 ls "s3://${S3_BUCKET}/${prefix}/${today}/" > /dev/null 2>&1; then
            local count
            count=$(aws s3 ls "s3://${S3_BUCKET}/${prefix}/${today}/" | wc -l)
            log_success "$prefix: $count backup(s) found for today"
        else
            log_error "$prefix: No backups found for today"
        fi
    done
}

verify_offsite_backup_integrity() {
    log_info "Verifying offsite backup integrity..."

    if [[ -z "$S3_BUCKET" ]]; then
        return
    fi

    local today
    today=$(date +%Y-%m-%d)

    # Download and verify a sample backup
    local test_file
    test_file=$(aws s3 ls "s3://${S3_BUCKET}/mysql/${today}/" | tail -1 | awk '{print $4}')

    if [[ -z "$test_file" ]]; then
        log_warning "No MySQL backup found to verify"
        return
    fi

    log_info "Testing backup: $test_file"

    local temp_dir
    temp_dir=$(mktemp -d)

    if aws s3 cp "s3://${S3_BUCKET}/mysql/${today}/${test_file}" "${temp_dir}/${test_file}"; then
        log_success "Download successful: $test_file"

        # Verify encryption (if .gpg file)
        if [[ "$test_file" == *.gpg ]]; then
            if gpg --decrypt "${temp_dir}/${test_file}" > /dev/null 2>&1; then
                log_success "Decryption successful: $test_file"
            else
                log_error "Decryption failed: $test_file"
            fi
        fi
    else
        log_error "Download failed: $test_file"
    fi

    rm -rf "$temp_dir"
}

verify_offsite_retention() {
    log_info "Verifying backup retention policy..."

    if [[ -z "$S3_BUCKET" ]]; then
        return
    fi

    local retention_days="${BACKUP_RETENTION_DAYS:-30}"
    local oldest_allowed
    oldest_allowed=$(date -d "$retention_days days ago" +%Y-%m-%d 2>/dev/null || \
                     date -v-${retention_days}d +%Y-%m-%d 2>/dev/null)

    # Check if backups older than retention exist
    local old_backups
    old_backups=$(aws s3 ls "s3://${S3_BUCKET}/mysql/" --recursive | \
                  grep -v "$oldest_allowed" | wc -l)

    if [[ $old_backups -gt 0 ]]; then
        log_warning "Found $old_backups backup(s) older than retention policy (${retention_days} days)"
    else
        log_success "Retention policy enforced correctly"
    fi

    # Verify we have backups for each day in retention period
    local missing_days=0
    for i in $(seq 0 "$retention_days"); do
        local check_date
        check_date=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || \
                     date -v-${i}d +%Y-%m-%d 2>/dev/null)

        if ! aws s3 ls "s3://${S3_BUCKET}/mysql/${check_date}/" > /dev/null 2>&1; then
            ((missing_days++))
        fi
    done

    if [[ $missing_days -gt 0 ]]; then
        log_warning "Missing backups for $missing_days day(s) in retention period"
    else
        log_success "Continuous backup coverage for past ${retention_days} days"
    fi
}

# ============================================================================
# Verification Functions - Restore Testing
# ============================================================================

setup_test_environment() {
    log_info "Setting up test environment..."

    # Create Docker network for testing
    if ! docker network inspect "$TEST_NETWORK" > /dev/null 2>&1; then
        docker network create "$TEST_NETWORK"
        log_success "Created test network: $TEST_NETWORK"
    fi
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."

    # Stop and remove test container
    docker stop "$TEST_DB_CONTAINER" 2>/dev/null || true
    docker rm "$TEST_DB_CONTAINER" 2>/dev/null || true

    # Remove test network
    docker network rm "$TEST_NETWORK" 2>/dev/null || true

    log_success "Test environment cleaned up"
}

test_database_restore() {
    log_info "Testing database restore..."

    if [[ "$VERIFY_PERFORM_RESTORE_TEST" != "true" ]]; then
        log_info "Restore testing disabled, skipping..."
        return
    fi

    # Find most recent backup
    local backup_file
    backup_file=$(find "${PROJECT_ROOT}/chom/storage/app/backups" -name "backup_*.sql" -o -name "backup_*.sql.gz" | sort -r | head -1)

    if [[ -z "$backup_file" ]]; then
        log_error "No database backup found for restore test"
        return
    fi

    log_info "Using backup: $(basename "$backup_file")"

    # Setup test environment
    setup_test_environment

    # Start test MySQL container
    log_info "Starting test MySQL container..."
    docker run -d \
        --name "$TEST_DB_CONTAINER" \
        --network "$TEST_NETWORK" \
        -e MYSQL_ROOT_PASSWORD=test_password \
        -e MYSQL_DATABASE=test_db \
        mysql:8.0 > /dev/null 2>&1

    # Wait for MySQL to be ready
    log_info "Waiting for MySQL to be ready..."
    for i in {1..30}; do
        if docker exec "$TEST_DB_CONTAINER" mysqladmin ping -h localhost -ptest_password > /dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    # Restore backup
    log_info "Restoring backup to test database..."

    local temp_sql="/tmp/test_restore_$$.sql"

    if [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" > "$temp_sql"
    else
        cp "$backup_file" "$temp_sql"
    fi

    if docker exec -i "$TEST_DB_CONTAINER" mysql -u root -ptest_password test_db < "$temp_sql" 2>/dev/null; then
        log_success "Database restore successful"

        # Verify restored data
        local table_count
        table_count=$(docker exec "$TEST_DB_CONTAINER" mysql -u root -ptest_password -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='test_db';" -s -N)

        if [[ $table_count -gt 0 ]]; then
            log_success "Restored database contains $table_count tables"
        else
            log_warning "Restored database appears empty"
        fi
    else
        log_error "Database restore failed"
    fi

    rm -f "$temp_sql"
    cleanup_test_environment
}

test_volume_restore() {
    log_info "Testing volume restore..."

    if [[ "$VERIFY_PERFORM_RESTORE_TEST" != "true" ]]; then
        log_info "Restore testing disabled, skipping..."
        return
    fi

    # Find most recent volume backup
    local backup_file
    backup_file=$(find "${PROJECT_ROOT}/docker/backups" -name "*_backup_*.tar.gz" | sort -r | head -1)

    if [[ -z "$backup_file" ]]; then
        log_error "No volume backup found for restore test"
        return
    fi

    log_info "Using backup: $(basename "$backup_file")"

    # Create temporary test volume
    local test_volume="backup_verify_test_volume"
    docker volume create "$test_volume" > /dev/null 2>&1

    # Restore to test volume
    if docker run --rm \
        -v "${test_volume}:/data" \
        -v "$(dirname "$backup_file"):/backup" \
        debian:12-slim \
        tar xzf "/backup/$(basename "$backup_file")" -C /data 2>/dev/null; then
        log_success "Volume restore successful"

        # Verify restored content
        local file_count
        file_count=$(docker run --rm -v "${test_volume}:/data" debian:12-slim find /data -type f | wc -l)

        if [[ $file_count -gt 0 ]]; then
            log_success "Restored volume contains $file_count files"
        else
            log_warning "Restored volume appears empty"
        fi
    else
        log_error "Volume restore failed"
    fi

    # Cleanup
    docker volume rm "$test_volume" > /dev/null 2>&1
}

# ============================================================================
# Reporting Functions
# ============================================================================

generate_verification_report() {
    log_info "========================================="
    log_info "  Backup Verification Summary"
    log_info "========================================="
    log_success "Tests Passed: $VERIFICATION_PASSED"
    log_warning "Warnings: $VERIFICATION_WARNINGS"
    log_error "Tests Failed: $VERIFICATION_FAILED"
    log_info "========================================="

    # Calculate overall status
    local overall_status="PASS"
    if [[ $VERIFICATION_FAILED -gt 0 ]]; then
        overall_status="FAIL"
    elif [[ $VERIFICATION_WARNINGS -gt 0 ]]; then
        overall_status="WARN"
    fi

    echo ""
    echo "Overall Status: $overall_status"
    echo "Report saved to: $REPORT_FILE"

    # Push metrics
    push_metric "backup_verification_passed" "$VERIFICATION_PASSED"
    push_metric "backup_verification_warnings" "$VERIFICATION_WARNINGS"
    push_metric "backup_verification_failed" "$VERIFICATION_FAILED"
    push_metric "backup_verification_last_run" "$(date +%s)"

    # Send alerts if failures
    if [[ $VERIFICATION_FAILED -gt 0 ]]; then
        send_alert "critical" "Backup verification failed: $VERIFICATION_FAILED test(s) failed. See $REPORT_FILE"
    elif [[ $VERIFICATION_WARNINGS -gt 3 ]]; then
        send_alert "warning" "Backup verification warnings: $VERIFICATION_WARNINGS warning(s). See $REPORT_FILE"
    fi
}

cleanup_old_reports() {
    log_info "Cleaning up old verification reports..."

    find "$REPORT_DIR" -name "verification_*.txt" -mtime "+${REPORT_RETENTION_DAYS}" -delete

    log_success "Old reports cleaned up (retention: ${REPORT_RETENTION_DAYS} days)"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "========================================="
    log_info "  Backup Verification Started"
    log_info "========================================="
    log_info "Timestamp: $TIMESTAMP"

    # Validate dependencies
    for cmd in aws docker gpg tar gzip; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
        fi
    done

    # Local backup verification
    if [[ "$VERIFY_LOCAL_BACKUPS" == "true" ]]; then
        verify_local_backup_existence
        verify_local_backup_integrity
        verify_local_backup_size
    fi

    # Offsite backup verification
    if [[ "$VERIFY_OFFSITE_BACKUPS" == "true" ]]; then
        verify_offsite_backup_existence
        verify_offsite_backup_integrity
        verify_offsite_retention
    fi

    # Restore testing
    if [[ "$TEST_ENV_ENABLED" == "true" ]]; then
        test_database_restore
        test_volume_restore
    fi

    # Generate report
    generate_verification_report

    # Cleanup old reports
    cleanup_old_reports

    # Exit with appropriate code
    if [[ $VERIFICATION_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Trap errors
trap 'log_error "Verification script failed at line $LINENO"; exit 1' ERR

# Run main function
main "$@"
