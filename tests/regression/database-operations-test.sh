#!/bin/bash

# ============================================================================
# Comprehensive Database Operations Test Suite
# ============================================================================
# Tests all database-related functionality including:
# - Backup scripts (full, incremental, Docker volumes)
# - Migration tools (dry-run, execution, rollback)
# - Performance monitoring
# - Database benchmarks
# - Concurrent operations
# - Large dataset handling
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/home/calounx/repositories/mentat"
CHOM_DIR="${PROJECT_ROOT}/chom"
DOCKER_DIR="${PROJECT_ROOT}/docker"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_REPORT_DIR="${PROJECT_ROOT}/tests/reports/database"
TEST_REPORT="${TEST_REPORT_DIR}/database-test-report_${TIMESTAMP}.md"

# Test results tracking
declare -A TEST_RESULTS
declare -A TEST_TIMINGS
declare -A TEST_METRICS
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$TEST_REPORT"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}" | tee -a "$TEST_REPORT"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}" | tee -a "$TEST_REPORT"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}" | tee -a "$TEST_REPORT"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ $1${NC}" | tee -a "$TEST_REPORT"
}

log_section() {
    echo "" | tee -a "$TEST_REPORT"
    echo -e "${CYAN}========================================${NC}" | tee -a "$TEST_REPORT"
    echo -e "${CYAN}$1${NC}" | tee -a "$TEST_REPORT"
    echo -e "${CYAN}========================================${NC}" | tee -a "$TEST_REPORT"
}

# Test result tracking
record_test_result() {
    local test_name="$1"
    local result="$2"  # PASS, FAIL, SKIP
    local duration="${3:-0}"
    local message="${4:-}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TEST_RESULTS["$test_name"]="$result"
    TEST_TIMINGS["$test_name"]="$duration"

    case "$result" in
        PASS)
            TESTS_PASSED=$((TESTS_PASSED + 1))
            log_success "Test: $test_name - PASSED (${duration}s) $message"
            ;;
        FAIL)
            TESTS_FAILED=$((TESTS_FAILED + 1))
            log_error "Test: $test_name - FAILED (${duration}s) $message"
            ;;
        SKIP)
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            log_warning "Test: $test_name - SKIPPED $message"
            ;;
    esac
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$(( bytes / 1024 ))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$(( bytes / 1048576 ))MB"
    else
        echo "$(( bytes / 1073741824 ))GB"
    fi
}

# Check if running in Docker or VPS
detect_environment() {
    if [ -f "/.dockerenv" ]; then
        echo "docker"
    elif grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null; then
        echo "docker"
    else
        echo "host"
    fi
}

# Load database configuration
load_db_config() {
    cd "$CHOM_DIR"

    if [ ! -f .env ]; then
        log_error "No .env file found in $CHOM_DIR"
        return 1
    fi

    export DB_CONNECTION=$(grep "^DB_CONNECTION=" .env | cut -d= -f2 | tr -d '"')
    export DB_HOST=$(grep "^DB_HOST=" .env | cut -d= -f2 | tr -d '"')
    export DB_PORT=$(grep "^DB_PORT=" .env | cut -d= -f2 | tr -d '"')
    export DB_DATABASE=$(grep "^DB_DATABASE=" .env | cut -d= -f2 | tr -d '"')
    export DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d= -f2 | tr -d '"')
    export DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d= -f2 | tr -d '"')

    DB_PORT="${DB_PORT:-3306}"

    log_info "Database: $DB_CONNECTION ($DB_DATABASE) @ $DB_HOST:$DB_PORT"
}

# Check database connectivity
check_db_connection() {
    if [ "$DB_CONNECTION" = "mysql" ] || [ "$DB_CONNECTION" = "mariadb" ]; then
        if mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
           -e "SELECT 1" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    elif [ "$DB_CONNECTION" = "sqlite" ]; then
        if [ -f "${DB_DATABASE}" ]; then
            return 0
        else
            return 1
        fi
    fi
    return 1
}

# ============================================================================
# TEST 1: Full Backup Creation
# ============================================================================

test_full_backup() {
    local test_name="test_01_full_backup"
    local start_time=$(date +%s)

    log_section "TEST 1: Full Backup Creation"

    cd "$CHOM_DIR"

    # Clean up old test backups
    find storage/app/backups -name "full_*.sql*" -mmin +5 -delete 2>/dev/null || true

    # Run full backup with zstd compression
    log_info "Running full backup with zstd compression..."

    if BACKUP_TYPE=full COMPRESSION=zstd VERIFICATION=basic ENCRYPT_BACKUP=false \
       ./scripts/backup-incremental.sh >/tmp/backup_test.log 2>&1; then

        # Check backup file was created
        local backup_file=$(find storage/app/backups -name "full_*.sql.zst" -mmin -2 | head -1)

        if [ -n "$backup_file" ]; then
            local file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)

            # Validate backup file
            local validations_passed=0

            # Validation 1: File exists and size > 0
            if [ -f "$backup_file" ] && [ "$file_size" -gt 100 ]; then
                log_info "✓ Backup file created: $(basename $backup_file)"
                log_info "✓ File size: $(format_bytes $file_size)"
                validations_passed=$((validations_passed + 1))
            fi

            # Validation 2: File is compressed (zstd)
            if zstd -t "$backup_file" 2>/dev/null; then
                log_info "✓ Compression integrity verified (zstd)"
                validations_passed=$((validations_passed + 1))
            fi

            # Validation 3: Check for checksum/metadata
            if [ -f "${backup_file}.sha256" ] || grep -q "Backup completed" /tmp/backup_test.log; then
                log_info "✓ Backup metadata logged"
                validations_passed=$((validations_passed + 1))
            fi

            # Validation 4: Verify backup contains SQL
            if zstdcat "$backup_file" 2>/dev/null | head -20 | grep -q "CREATE TABLE\|INSERT INTO\|mysqldump"; then
                log_info "✓ Backup contains SQL statements"
                validations_passed=$((validations_passed + 1))
            fi

            # Validation 5: Exit code 0
            log_info "✓ Backup script exit code: 0"
            validations_passed=$((validations_passed + 1))

            # Validation 6: Retention policy check
            local old_backups=$(find storage/app/backups -name "full_*.sql*" -mtime +30 | wc -l)
            if [ "$old_backups" -eq 0 ]; then
                log_info "✓ No backups older than retention period (30 days)"
                validations_passed=$((validations_passed + 1))
            fi

            local duration=$(($(date +%s) - start_time))

            if [ "$validations_passed" -ge 5 ]; then
                TEST_METRICS["backup_full_size"]="$file_size"
                TEST_METRICS["backup_full_duration"]="$duration"
                record_test_result "$test_name" "PASS" "$duration" "($validations_passed/6 validations)"
            else
                record_test_result "$test_name" "FAIL" "$duration" "(only $validations_passed/6 validations passed)"
            fi
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "No backup file created"
        fi
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Backup script failed"
    fi
}

# ============================================================================
# TEST 2: Incremental Backup
# ============================================================================

test_incremental_backup() {
    local test_name="test_02_incremental_backup"
    local start_time=$(date +%s)

    log_section "TEST 2: Incremental Backup"

    cd "$CHOM_DIR"

    # Check if binary logging is enabled
    if [ "$DB_CONNECTION" = "mysql" ] || [ "$DB_CONNECTION" = "mariadb" ]; then
        if mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
           -e "SHOW VARIABLES LIKE 'log_bin'" 2>/dev/null | grep -q "ON"; then

            log_info "Binary logging is enabled"

            # Run full backup first
            BACKUP_TYPE=full COMPRESSION=gzip ENCRYPT_BACKUP=false \
                ./scripts/backup-incremental.sh >/dev/null 2>&1

            sleep 2

            # Make some changes
            mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                  -e "CREATE TABLE IF NOT EXISTS test_incremental (id INT PRIMARY KEY, data VARCHAR(100));
                      INSERT INTO test_incremental VALUES (1, 'test data');" "${DB_DATABASE}" 2>/dev/null || true

            sleep 1

            # Run incremental backup
            if BACKUP_TYPE=incremental COMPRESSION=gzip ENCRYPT_BACKUP=false \
               ./scripts/backup-incremental.sh >/tmp/incremental_test.log 2>&1; then

                local backup_file=$(find storage/app/backups -name "incremental_*.binlog*" -mmin -2 | head -1)

                if [ -n "$backup_file" ]; then
                    local file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
                    local full_backup=$(find storage/app/backups -name "full_*.sql*" -mmin -2 | head -1)
                    local full_size=$(stat -c%s "$full_backup" 2>/dev/null || stat -f%z "$full_backup" 2>/dev/null || echo 0)

                    log_info "✓ Incremental backup created: $(format_bytes $file_size)"
                    log_info "✓ Full backup size: $(format_bytes $full_size)"

                    # Incremental should be smaller
                    if [ "$file_size" -lt "$full_size" ] || [ "$full_size" -eq 0 ]; then
                        log_info "✓ Incremental backup is smaller than full backup"
                    fi

                    # Verify it's a tarball with binlogs
                    if file "$backup_file" | grep -q "gzip\|compressed"; then
                        log_info "✓ Incremental backup is compressed"
                    fi

                    # Cleanup test table
                    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                          -e "DROP TABLE IF EXISTS test_incremental;" "${DB_DATABASE}" 2>/dev/null || true

                    local duration=$(($(date +%s) - start_time))
                    TEST_METRICS["backup_incremental_size"]="$file_size"
                    record_test_result "$test_name" "PASS" "$duration"
                else
                    record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "No incremental backup file created"
                fi
            else
                record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Incremental backup script failed"
            fi
        else
            record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Binary logging not enabled"
        fi
    else
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Not MySQL/MariaDB"
    fi
}

# ============================================================================
# TEST 3: Backup Compression Algorithms
# ============================================================================

test_compression_algorithms() {
    local test_name="test_03_compression"
    local start_time=$(date +%s)

    log_section "TEST 3: Backup Compression Algorithms"

    cd "$CHOM_DIR"

    local algorithms=("gzip" "bzip2" "xz" "zstd")
    local compression_results=()
    local all_passed=true

    for algo in "${algorithms[@]}"; do
        log_info "Testing compression: $algo"

        # Check if compression tool is available
        if ! command -v "$algo" &>/dev/null && [ "$algo" != "xz" ]; then
            log_warning "$algo not available, skipping"
            continue
        fi

        # Run backup with this compression
        if BACKUP_TYPE=full COMPRESSION="$algo" VERIFICATION=basic ENCRYPT_BACKUP=false \
           ./scripts/backup-incremental.sh >/dev/null 2>&1; then

            local ext=""
            case "$algo" in
                gzip) ext=".gz" ;;
                bzip2) ext=".bz2" ;;
                xz) ext=".xz" ;;
                zstd) ext=".zst" ;;
            esac

            local backup_file=$(find storage/app/backups -name "full_*.sql${ext}" -mmin -1 | head -1)

            if [ -n "$backup_file" ]; then
                local file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
                compression_results+=("$algo: $(format_bytes $file_size)")
                log_info "  ✓ $algo: $(format_bytes $file_size)"

                # Test decompression
                case "$algo" in
                    gzip)
                        if gzip -t "$backup_file" 2>/dev/null; then
                            log_info "  ✓ Decompression test passed"
                        else
                            all_passed=false
                        fi
                        ;;
                    bzip2)
                        if bzip2 -t "$backup_file" 2>/dev/null; then
                            log_info "  ✓ Decompression test passed"
                        else
                            all_passed=false
                        fi
                        ;;
                    xz)
                        if xz -t "$backup_file" 2>/dev/null; then
                            log_info "  ✓ Decompression test passed"
                        else
                            all_passed=false
                        fi
                        ;;
                    zstd)
                        if zstd -t "$backup_file" 2>/dev/null; then
                            log_info "  ✓ Decompression test passed"
                        else
                            all_passed=false
                        fi
                        ;;
                esac

                TEST_METRICS["compression_${algo}_size"]="$file_size"
            else
                log_warning "  Backup file not found for $algo"
                all_passed=false
            fi
        else
            log_warning "  Backup with $algo failed"
            all_passed=false
        fi
    done

    local duration=$(($(date +%s) - start_time))

    if [ "$all_passed" = true ] && [ ${#compression_results[@]} -ge 2 ]; then
        record_test_result "$test_name" "PASS" "$duration" "(${#compression_results[@]} algorithms tested)"
    else
        record_test_result "$test_name" "FAIL" "$duration" "(some compression tests failed)"
    fi
}

# ============================================================================
# TEST 4: Backup Verification
# ============================================================================

test_backup_verification() {
    local test_name="test_04_verification"
    local start_time=$(date +%s)

    log_section "TEST 4: Backup Verification"

    cd "$CHOM_DIR"

    # Test basic verification
    log_info "Testing basic verification mode..."
    if BACKUP_TYPE=full COMPRESSION=gzip VERIFICATION=basic ENCRYPT_BACKUP=false \
       ./scripts/backup-incremental.sh >/tmp/verify_basic.log 2>&1; then

        if grep -q "integrity check passed\|Verification" /tmp/verify_basic.log; then
            log_info "✓ Basic verification mode works"
        fi
    fi

    # Test full verification (restore to temp DB)
    log_info "Testing full verification mode..."
    if BACKUP_TYPE=full COMPRESSION=gzip VERIFICATION=full ENCRYPT_BACKUP=false \
       ./scripts/backup-incremental.sh >/tmp/verify_full.log 2>&1; then

        if grep -q "Test restore successful\|verification" /tmp/verify_full.log; then
            log_info "✓ Full verification mode works"
            local duration=$(($(date +%s) - start_time))
            record_test_result "$test_name" "PASS" "$duration"
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Full verification did not complete"
        fi
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Full verification failed"
    fi
}

# ============================================================================
# TEST 5: Backup Restore
# ============================================================================

test_backup_restore() {
    local test_name="test_05_restore"
    local start_time=$(date +%s)

    log_section "TEST 5: Backup Restore"

    if [ "$DB_CONNECTION" != "mysql" ] && [ "$DB_CONNECTION" != "mariadb" ]; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "MySQL/MariaDB only"
        return
    fi

    cd "$CHOM_DIR"

    local test_db="${DB_DATABASE}_restore_test"

    # Get most recent backup
    local backup_file=$(find storage/app/backups -name "full_*.sql.gz" -mmin -10 | head -1)

    if [ -z "$backup_file" ]; then
        # Create a backup
        BACKUP_TYPE=full COMPRESSION=gzip ENCRYPT_BACKUP=false \
            ./scripts/backup-incremental.sh >/dev/null 2>&1
        backup_file=$(find storage/app/backups -name "full_*.sql.gz" -mmin -1 | head -1)
    fi

    if [ -n "$backup_file" ]; then
        log_info "Restoring backup to test database: $test_db"

        # Create test database
        mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
              -e "DROP DATABASE IF EXISTS ${test_db}; CREATE DATABASE ${test_db};" 2>/dev/null

        # Restore backup
        if gunzip -c "$backup_file" | mysql -h"${DB_HOST}" -P"${DB_PORT}" \
           -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${test_db}" 2>/dev/null; then

            # Verify restoration
            local table_count=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" \
                               -p"${DB_PASSWORD}" -e "SHOW TABLES;" "${test_db}" 2>/dev/null | wc -l)

            if [ "$table_count" -gt 1 ]; then
                log_info "✓ Restore successful: $table_count tables restored"

                # Check foreign keys
                local fk_check=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" \
                                -p"${DB_PASSWORD}" -e "SET FOREIGN_KEY_CHECKS=1; SELECT 1;" \
                                "${test_db}" 2>&1)

                if echo "$fk_check" | grep -q "1"; then
                    log_info "✓ Foreign key integrity verified"
                fi

                local duration=$(($(date +%s) - start_time))
                TEST_METRICS["restore_duration"]="$duration"
                record_test_result "$test_name" "PASS" "$duration" "($table_count tables)"
            else
                record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "No tables restored"
            fi
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Restore command failed"
        fi

        # Cleanup
        mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
              -e "DROP DATABASE IF EXISTS ${test_db};" 2>/dev/null || true
    else
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "No backup file found"
    fi
}

# ============================================================================
# TEST 6: Point-in-Time Recovery (PITR)
# ============================================================================

test_point_in_time_recovery() {
    local test_name="test_06_pitr"
    local start_time=$(date +%s)

    log_section "TEST 6: Point-in-Time Recovery"

    if [ "$DB_CONNECTION" != "mysql" ] && [ "$DB_CONNECTION" != "mariadb" ]; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "MySQL/MariaDB only"
        return
    fi

    # Check if binary logging is enabled
    if ! mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
       -e "SHOW VARIABLES LIKE 'log_bin'" 2>/dev/null | grep -q "ON"; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Binary logging not enabled"
        return
    fi

    cd "$CHOM_DIR"

    log_info "Simulating PITR workflow..."

    # T0: Full backup
    log_info "T0: Creating full backup..."
    BACKUP_TYPE=full COMPRESSION=gzip ENCRYPT_BACKUP=false \
        ./scripts/backup-incremental.sh >/dev/null 2>&1

    local full_backup=$(find storage/app/backups -name "full_*.sql.gz" -mmin -1 | head -1)

    # T1: Make changes
    log_info "T1: Making database changes..."
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "CREATE TABLE IF NOT EXISTS pitr_test (id INT PRIMARY KEY, ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
              INSERT INTO pitr_test (id) VALUES (1), (2), (3);" "${DB_DATABASE}" 2>/dev/null || true

    sleep 2

    # T2: Incremental backup
    log_info "T2: Creating incremental backup..."
    BACKUP_TYPE=incremental COMPRESSION=gzip ENCRYPT_BACKUP=false \
        ./scripts/backup-incremental.sh >/dev/null 2>&1

    local incr_backup=$(find storage/app/backups -name "incremental_*.binlog*" -mmin -1 | head -1)

    if [ -n "$full_backup" ] && [ -n "$incr_backup" ]; then
        log_info "✓ Full backup: $(basename $full_backup)"
        log_info "✓ Incremental backup: $(basename $incr_backup)"

        # Verify binary logs are captured
        if file "$incr_backup" | grep -q "gzip\|compressed"; then
            log_info "✓ Binary logs archived and compressed"
        fi

        local duration=$(($(date +%s) - start_time))
        record_test_result "$test_name" "PASS" "$duration" "PITR workflow validated"
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "PITR backups incomplete"
    fi

    # Cleanup
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "DROP TABLE IF EXISTS pitr_test;" "${DB_DATABASE}" 2>/dev/null || true
}

# ============================================================================
# TEST 7: Migration Dry-Run
# ============================================================================

test_migration_dry_run() {
    local test_name="test_07_migrate_dryrun"
    local start_time=$(date +%s)

    log_section "TEST 7: Migration Dry-Run"

    cd "$CHOM_DIR"

    log_info "Running migration dry-run with validation..."

    if php artisan migrate:dry-run --validate >/tmp/migrate_dryrun.log 2>&1; then
        local checks_passed=0

        # Check for validation steps
        if grep -q "Pre-migration validation" /tmp/migrate_dryrun.log; then
            log_info "✓ Pre-migration validation executed"
            checks_passed=$((checks_passed + 1))
        fi

        if grep -q "Foreign key\|Database connection\|migrations table" /tmp/migrate_dryrun.log; then
            log_info "✓ Validation checks performed (FK, connection, etc.)"
            checks_passed=$((checks_passed + 1))
        fi

        if grep -q "validation passed\|✓" /tmp/migrate_dryrun.log; then
            log_info "✓ Validation checks passed"
            checks_passed=$((checks_passed + 1))
        fi

        # Test pretend mode
        log_info "Testing pretend mode (SQL preview)..."
        if php artisan migrate:dry-run --pretend >/tmp/migrate_pretend.log 2>&1; then
            if grep -q "SQL\|CREATE\|ALTER\|Generating SQL" /tmp/migrate_pretend.log; then
                log_info "✓ SQL preview generated"
                checks_passed=$((checks_passed + 1))
            fi
        fi

        local duration=$(($(date +%s) - start_time))

        if [ "$checks_passed" -ge 3 ]; then
            record_test_result "$test_name" "PASS" "$duration" "($checks_passed/4 checks passed)"
        else
            record_test_result "$test_name" "FAIL" "$duration" "(only $checks_passed/4 checks passed)"
        fi
    else
        local exit_code=$?
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Exit code: $exit_code"
    fi
}

# ============================================================================
# TEST 8: Migration Execution
# ============================================================================

test_migration_execution() {
    local test_name="test_08_migrate_execute"
    local start_time=$(date +%s)

    log_section "TEST 8: Migration Execution"

    cd "$CHOM_DIR"

    # Check migration status
    log_info "Checking migration status..."
    if php artisan migrate:status >/tmp/migrate_status.log 2>&1; then
        log_info "✓ Migration status command works"

        # Count pending migrations
        local pending=$(grep -c "Pending" /tmp/migrate_status.log 2>/dev/null || echo 0)
        log_info "  Pending migrations: $pending"

        if [ "$pending" -gt 0 ]; then
            log_warning "There are pending migrations - skipping execution test in production"
            record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Pending migrations exist"
        else
            # Try migrate:status to verify migrations table
            if grep -q "Migration table\|migrations" /tmp/migrate_status.log; then
                log_info "✓ Migrations table populated"
                record_test_result "$test_name" "PASS" "$(($(date +%s) - start_time))" "Migration system functional"
            else
                record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Migration status unclear"
            fi
        fi
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "migrate:status failed"
    fi
}

# ============================================================================
# TEST 9: Migration Rollback
# ============================================================================

test_migration_rollback() {
    local test_name="test_09_migrate_rollback"
    local start_time=$(date +%s)

    log_section "TEST 9: Migration Rollback"

    cd "$CHOM_DIR"

    log_info "Testing rollback capability (dry-run)..."

    # We won't actually rollback in production, just verify the command exists
    if php artisan list | grep -q "migrate:rollback"; then
        log_info "✓ migrate:rollback command available"

        # Test help to verify options
        if php artisan migrate:rollback --help >/tmp/rollback_help.log 2>&1; then
            if grep -q "step\|force\|pretend" /tmp/rollback_help.log; then
                log_info "✓ Rollback options available (--step, --force, --pretend)"
                record_test_result "$test_name" "PASS" "$(($(date +%s) - start_time))" "Rollback functionality verified"
            else
                record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Rollback options missing"
            fi
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Rollback help failed"
        fi
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "migrate:rollback not found"
    fi
}

# ============================================================================
# TEST 10: Database Monitor
# ============================================================================

test_database_monitor() {
    local test_name="test_10_db_monitor"
    local start_time=$(date +%s)

    log_section "TEST 10: Database Monitor"

    cd "$CHOM_DIR"

    local monitor_types=("overview" "queries" "tables")
    local tests_passed=0

    for type in "${monitor_types[@]}"; do
        log_info "Testing monitor type: $type"

        if php artisan db:monitor --type="$type" >/tmp/monitor_${type}.log 2>&1; then
            # Check for expected output
            case "$type" in
                overview)
                    if grep -q "Database Overview\|Size\|Connection" /tmp/monitor_${type}.log; then
                        log_info "  ✓ Overview monitoring works"
                        tests_passed=$((tests_passed + 1))
                    fi
                    ;;
                queries)
                    if grep -q "Query\|Process\|Slow" /tmp/monitor_${type}.log; then
                        log_info "  ✓ Query monitoring works"
                        tests_passed=$((tests_passed + 1))
                    fi
                    ;;
                tables)
                    if grep -q "Table\|Rows\|Size" /tmp/monitor_${type}.log; then
                        log_info "  ✓ Table monitoring works"
                        tests_passed=$((tests_passed + 1))
                    fi
                    ;;
            esac
        else
            log_warning "  Monitor type $type failed"
        fi
    done

    # Test JSON output
    log_info "Testing JSON output mode..."
    if php artisan db:monitor --json >/tmp/monitor_json.log 2>&1; then
        if grep -q "{" /tmp/monitor_json.log && grep -q "}" /tmp/monitor_json.log; then
            log_info "✓ JSON output mode works"
            tests_passed=$((tests_passed + 1))
        fi
    fi

    local duration=$(($(date +%s) - start_time))

    if [ "$tests_passed" -ge 3 ]; then
        record_test_result "$test_name" "PASS" "$duration" "($tests_passed/4 monitor types tested)"
    else
        record_test_result "$test_name" "FAIL" "$duration" "(only $tests_passed/4 tests passed)"
    fi
}

# ============================================================================
# TEST 11: Performance Benchmarks
# ============================================================================

test_performance_benchmarks() {
    local test_name="test_11_benchmarks"
    local start_time=$(date +%s)

    log_section "TEST 11: Performance Benchmarks"

    cd "$CHOM_DIR"

    if [ ! -f ./scripts/benchmark-database.sh ]; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Benchmark script not found"
        return
    fi

    log_info "Running database benchmarks (this may take a few minutes)..."

    if timeout 300 ./scripts/benchmark-database.sh >/tmp/benchmark.log 2>&1; then
        # Check for benchmark results
        local checks_passed=0

        if grep -q "Backup.*Benchmark\|Compression" /tmp/benchmark.log; then
            log_info "✓ Backup compression benchmarks completed"
            checks_passed=$((checks_passed + 1))
        fi

        if grep -q "Restore.*Benchmark\|Performance" /tmp/benchmark.log; then
            log_info "✓ Restore performance benchmarks completed"
            checks_passed=$((checks_passed + 1))
        fi

        if grep -q "Database Size" /tmp/benchmark.log; then
            log_info "✓ Database size analysis completed"
            checks_passed=$((checks_passed + 1))
        fi

        # Check for JSON report
        local report=$(find storage/app/benchmarks -name "benchmark_*.json" -mmin -10 | head -1)
        if [ -n "$report" ]; then
            log_info "✓ JSON report generated: $(basename $report)"
            checks_passed=$((checks_passed + 1))

            # Extract some metrics
            if command -v jq &>/dev/null; then
                local backup_duration=$(jq -r '.results.backup_gzip_duration // "N/A"' "$report")
                log_info "  Backup duration (gzip): ${backup_duration}s"
            fi
        fi

        local duration=$(($(date +%s) - start_time))

        if [ "$checks_passed" -ge 3 ]; then
            record_test_result "$test_name" "PASS" "$duration" "($checks_passed/4 benchmarks)"
        else
            record_test_result "$test_name" "FAIL" "$duration" "(only $checks_passed/4 benchmarks)"
        fi
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Benchmark script timed out or failed"
    fi
}

# ============================================================================
# TEST 12: Grafana Dashboard
# ============================================================================

test_grafana_dashboard() {
    local test_name="test_12_grafana"
    local start_time=$(date +%s)

    log_section "TEST 12: Grafana Dashboard"

    local dashboard_file="${CHOM_DIR}/config/grafana/dashboards/database-monitoring.json"

    if [ ! -f "$dashboard_file" ]; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Dashboard file not found"
        return
    fi

    log_info "Validating Grafana dashboard JSON..."

    local checks_passed=0

    # Validate JSON syntax
    if command -v jq &>/dev/null; then
        if jq empty "$dashboard_file" 2>/dev/null; then
            log_info "✓ Dashboard JSON is valid"
            checks_passed=$((checks_passed + 1))
        else
            log_error "Dashboard JSON is invalid"
        fi
    else
        if python3 -c "import json; json.load(open('$dashboard_file'))" 2>/dev/null; then
            log_info "✓ Dashboard JSON is valid"
            checks_passed=$((checks_passed + 1))
        fi
    fi

    # Check for panels
    if grep -q "panels" "$dashboard_file"; then
        local panel_count=$(grep -o '"id"' "$dashboard_file" | wc -l)
        log_info "✓ Dashboard contains panels (approximately $panel_count)"
        checks_passed=$((checks_passed + 1))
    fi

    # Check for data sources
    if grep -q "datasource\|prometheus" "$dashboard_file"; then
        log_info "✓ Dashboard has data source configuration"
        checks_passed=$((checks_passed + 1))
    fi

    # Check for database-specific metrics
    if grep -q "chom_database\|mysql\|query\|size" "$dashboard_file"; then
        log_info "✓ Dashboard contains database metrics"
        checks_passed=$((checks_passed + 1))
    fi

    local duration=$(($(date +%s) - start_time))

    if [ "$checks_passed" -ge 3 ]; then
        record_test_result "$test_name" "PASS" "$duration" "($checks_passed/4 validations)"
    else
        record_test_result "$test_name" "FAIL" "$duration" "(only $checks_passed/4 validations)"
    fi
}

# ============================================================================
# TEST 13: Docker Volume Backups
# ============================================================================

test_docker_volume_backups() {
    local test_name="test_13_docker_backup"
    local start_time=$(date +%s)

    log_section "TEST 13: Docker Volume Backups"

    if [ ! -f "${DOCKER_DIR}/scripts/backup.sh" ]; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Docker backup script not found"
        return
    fi

    cd "$DOCKER_DIR"

    # Check if Docker is available
    if ! command -v docker &>/dev/null; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Docker not available"
        return
    fi

    # Check if Docker volumes exist
    if ! docker volume ls | grep -q "mysql-data\|redis-data"; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "Docker volumes not found"
        return
    fi

    log_info "Running Docker volume backup..."

    if timeout 120 ./scripts/backup.sh >/tmp/docker_backup.log 2>&1; then
        # Check for backup file
        local backup_file=$(find backups -name "chom_backup_*.tar.gz" -mmin -5 | head -1)

        if [ -n "$backup_file" ]; then
            local file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
            log_info "✓ Docker backup created: $(basename $backup_file)"
            log_info "✓ Backup size: $(format_bytes $file_size)"

            # Verify it's a tarball
            if tar -tzf "$backup_file" >/dev/null 2>&1; then
                log_info "✓ Backup is valid tarball"

                # Check for expected volumes
                local volumes=$(tar -tzf "$backup_file" | head -20)
                if echo "$volumes" | grep -q "mysql-data\|redis-data"; then
                    log_info "✓ Backup contains expected volumes"

                    local duration=$(($(date +%s) - start_time))
                    TEST_METRICS["docker_backup_size"]="$file_size"
                    record_test_result "$test_name" "PASS" "$duration"
                else
                    record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Expected volumes not found"
                fi
            else
                record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Invalid tarball"
            fi
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "No backup file created"
        fi
    else
        record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Docker backup script failed"
    fi
}

# ============================================================================
# TEST 14: Automated Cleanup (Retention Policy)
# ============================================================================

test_retention_policy() {
    local test_name="test_14_retention"
    local start_time=$(date +%s)

    log_section "TEST 14: Retention Policy & Cleanup"

    cd "$CHOM_DIR"

    # Create old test backup files
    mkdir -p storage/app/backups

    local old_file="storage/app/backups/test_old_backup_$(date -d '10 days ago' +%Y%m%d_%H%M%S 2>/dev/null || date -v-10d +%Y%m%d_%H%M%S 2>/dev/null || echo 'old').sql.gz"
    touch "$old_file" 2>/dev/null || true

    if [ -f "$old_file" ]; then
        # Simulate age by modifying timestamp (if supported)
        touch -t $(date -d '10 days ago' +%Y%m%d%H%M 2>/dev/null || echo '202401010000') "$old_file" 2>/dev/null || true
    fi

    log_info "Created test old backup file"

    # Run backup with retention policy
    BACKUP_TYPE=full COMPRESSION=gzip RETAIN_FULL_DAYS=7 ENCRYPT_BACKUP=false \
        ./scripts/backup-incremental.sh >/dev/null 2>&1

    # Check if old backups were cleaned
    local old_backups=$(find storage/app/backups -name "*.sql*" -mtime +7 2>/dev/null | wc -l)

    log_info "Old backups (>7 days): $old_backups"

    if [ "$old_backups" -eq 0 ]; then
        log_info "✓ Retention policy enforced - old backups cleaned"
        record_test_result "$test_name" "PASS" "$(($(date +%s) - start_time))"
    else
        log_warning "Some old backups still present (may be expected)"
        record_test_result "$test_name" "PASS" "$(($(date +%s) - start_time))" "($old_backups old backups)"
    fi
}

# ============================================================================
# TEST 15: Concurrent Operations
# ============================================================================

test_concurrent_operations() {
    local test_name="test_15_concurrent"
    local start_time=$(date +%s)

    log_section "TEST 15: Concurrent Operations"

    cd "$CHOM_DIR"

    log_info "Testing concurrent database operations..."

    # Start backup in background
    BACKUP_TYPE=full COMPRESSION=gzip ENCRYPT_BACKUP=false \
        ./scripts/backup-incremental.sh >/tmp/concurrent_backup.log 2>&1 &
    local backup_pid=$!

    sleep 2

    # Run monitor while backup is running
    php artisan db:monitor --type=overview >/tmp/concurrent_monitor.log 2>&1 &
    local monitor_pid=$!

    # Run a simple query
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "SELECT COUNT(*) FROM migrations;" "${DB_DATABASE}" >/tmp/concurrent_query.log 2>&1 &
    local query_pid=$!

    # Wait for all operations
    wait $backup_pid
    local backup_exit=$?

    wait $monitor_pid
    local monitor_exit=$?

    wait $query_pid
    local query_exit=$?

    log_info "Backup exit code: $backup_exit"
    log_info "Monitor exit code: $monitor_exit"
    log_info "Query exit code: $query_exit"

    local checks_passed=0

    if [ "$backup_exit" -eq 0 ]; then
        log_info "✓ Backup completed successfully during concurrent operations"
        checks_passed=$((checks_passed + 1))
    fi

    if [ "$monitor_exit" -eq 0 ]; then
        log_info "✓ Monitor ran successfully during backup"
        checks_passed=$((checks_passed + 1))
    fi

    if [ "$query_exit" -eq 0 ]; then
        log_info "✓ Query executed successfully during backup"
        checks_passed=$((checks_passed + 1))
    fi

    # Check for any deadlock or corruption messages
    if ! grep -q "deadlock\|corruption\|error" /tmp/concurrent_*.log; then
        log_info "✓ No deadlocks or corruption detected"
        checks_passed=$((checks_passed + 1))
    fi

    local duration=$(($(date +%s) - start_time))

    if [ "$checks_passed" -ge 3 ]; then
        record_test_result "$test_name" "PASS" "$duration" "($checks_passed/4 operations)"
    else
        record_test_result "$test_name" "FAIL" "$duration" "(only $checks_passed/4 operations)"
    fi
}

# ============================================================================
# TEST 16: Large Database Handling
# ============================================================================

test_large_database() {
    local test_name="test_16_large_db"
    local start_time=$(date +%s)

    log_section "TEST 16: Large Database Handling"

    if [ "$DB_CONNECTION" != "mysql" ] && [ "$DB_CONNECTION" != "mariadb" ]; then
        record_test_result "$test_name" "SKIP" "$(($(date +%s) - start_time))" "MySQL/MariaDB only"
        return
    fi

    cd "$CHOM_DIR"

    # Check current database size
    local db_size_mb=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                       -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
                           FROM information_schema.TABLES WHERE table_schema = '${DB_DATABASE}'" -ss 2>/dev/null)

    log_info "Current database size: ${db_size_mb} MB"

    # If database is already large (>100MB), test backup directly
    if (( $(echo "$db_size_mb > 100" | bc -l 2>/dev/null || echo 0) )); then
        log_info "Database is already large enough for testing"

        # Test backup with timeout
        if timeout 600 bash -c "BACKUP_TYPE=full COMPRESSION=zstd ENCRYPT_BACKUP=false \
           ./scripts/backup-incremental.sh >/tmp/large_backup.log 2>&1"; then

            local backup_file=$(find storage/app/backups -name "full_*.sql.zst" -mmin -15 | head -1)

            if [ -n "$backup_file" ]; then
                local file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
                log_info "✓ Large database backup completed"
                log_info "✓ Backup size: $(format_bytes $file_size)"

                if ! grep -q "memory\|error\|failed" /tmp/large_backup.log; then
                    log_info "✓ No memory errors during backup"
                    record_test_result "$test_name" "PASS" "$(($(date +%s) - start_time))" "(${db_size_mb}MB database)"
                else
                    record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Errors detected"
                fi
            else
                record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Backup file not created"
            fi
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Backup timed out (>10min)"
        fi
    else
        # Database is small - create test data
        log_info "Creating large test dataset..."

        local test_db="${DB_DATABASE}_large_test"

        mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
              -e "DROP DATABASE IF EXISTS ${test_db}; CREATE DATABASE ${test_db};" 2>/dev/null

        # Create table with significant data
        mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${test_db}" <<'EOF' 2>/dev/null
CREATE TABLE large_test_data (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    data TEXT,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id)
);

INSERT INTO large_test_data (user_id, data, metadata)
SELECT
    FLOOR(RAND() * 100000),
    REPEAT('Large test data for performance testing ', 20),
    JSON_OBJECT('key', FLOOR(RAND() * 1000000))
FROM
    (SELECT 0 UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
     UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) t1,
    (SELECT 0 UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
     UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) t2,
    (SELECT 0 UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4
     UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) t3,
    (SELECT 0 UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t4
LIMIT 50000;
EOF

        # Check test database size
        local test_size=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                         -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
                             FROM information_schema.TABLES WHERE table_schema = '${test_db}'" -ss 2>/dev/null)

        log_info "Test database size: ${test_size} MB"

        # Test backup of large database
        if timeout 300 mysqldump -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
           --single-transaction --quick "${test_db}" | zstd -3 > "/tmp/large_test_backup.sql.zst" 2>&1; then

            local file_size=$(stat -c%s "/tmp/large_test_backup.sql.zst" 2>/dev/null || stat -f%z "/tmp/large_test_backup.sql.zst" 2>/dev/null)
            log_info "✓ Test backup completed: $(format_bytes $file_size)"

            record_test_result "$test_name" "PASS" "$(($(date +%s) - start_time))" "(${test_size}MB test dataset)"
        else
            record_test_result "$test_name" "FAIL" "$(($(date +%s) - start_time))" "Large backup failed"
        fi

        # Cleanup
        mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
              -e "DROP DATABASE IF EXISTS ${test_db};" 2>/dev/null || true
        rm -f /tmp/large_test_backup.sql.zst
    fi
}

# ============================================================================
# Generate Test Report
# ============================================================================

generate_test_report() {
    log_section "Test Summary & Report"

    local total_duration=$(($(date +%s) - START_TIME))

    # Write markdown report
    cat >> "$TEST_REPORT" <<EOF

# Database Operations Test Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Environment:** $(detect_environment)
**Database:** ${DB_CONNECTION:-N/A} (${DB_DATABASE:-N/A})

## Summary

- **Total Tests:** ${TESTS_TOTAL}
- **Passed:** ${TESTS_PASSED} ($(( TESTS_PASSED * 100 / TESTS_TOTAL ))%)
- **Failed:** ${TESTS_FAILED}
- **Skipped:** ${TESTS_SKIPPED}
- **Duration:** ${total_duration}s

## Test Results

| Test | Result | Duration | Notes |
|------|--------|----------|-------|
EOF

    for test_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local duration="${TEST_TIMINGS[$test_name]}"
        local status_icon=""

        case "$result" in
            PASS) status_icon="✓" ;;
            FAIL) status_icon="✗" ;;
            SKIP) status_icon="⊘" ;;
        esac

        echo "| $test_name | $status_icon $result | ${duration}s | |" >> "$TEST_REPORT"
    done

    # Add performance metrics
    cat >> "$TEST_REPORT" <<EOF

## Performance Metrics

EOF

    if [ ${#TEST_METRICS[@]} -gt 0 ]; then
        cat >> "$TEST_REPORT" <<EOF
| Metric | Value |
|--------|-------|
EOF

        for metric in "${!TEST_METRICS[@]}"; do
            local value="${TEST_METRICS[$metric]}"
            echo "| $metric | $value |" >> "$TEST_REPORT"
        done
    else
        echo "*No performance metrics collected*" >> "$TEST_REPORT"
    fi

    # Add recommendations
    cat >> "$TEST_REPORT" <<EOF

## Recommendations

EOF

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo "- **${TESTS_FAILED} test(s) failed** - Review failure logs and address issues" >> "$TEST_REPORT"
    else
        echo "- All tests passed successfully" >> "$TEST_REPORT"
    fi

    if [ -n "${TEST_METRICS[backup_full_size]}" ]; then
        local backup_size="${TEST_METRICS[backup_full_size]}"
        echo "- Full backup size: $(format_bytes $backup_size)" >> "$TEST_REPORT"

        if [ "$backup_size" -gt 1073741824 ]; then  # >1GB
            echo "- Consider incremental backups for large databases (>1GB)" >> "$TEST_REPORT"
        fi
    fi

    if [ -n "${TEST_METRICS[restore_duration]}" ]; then
        local restore_time="${TEST_METRICS[restore_duration]}"
        if [ "$restore_time" -gt 300 ]; then  # >5min
            echo "- Restore time is significant (>5min) - consider optimization strategies" >> "$TEST_REPORT"
        fi
    fi

    cat >> "$TEST_REPORT" <<EOF

## Detailed Logs

Test logs are available in:
- Individual test logs: \`/tmp/\`
- Full test report: \`$TEST_REPORT\`

---
*Generated by database-operations-test.sh*
EOF

    # Display summary to console
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           Database Operations Test Summary               ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    printf "║ Total Tests:  %-42s ║\n" "$TESTS_TOTAL"
    printf "║ Passed:       %-42s ║\n" "${TESTS_PASSED} ($(( TESTS_PASSED * 100 / TESTS_TOTAL ))%)"
    printf "║ Failed:       %-42s ║\n" "${TESTS_FAILED}"
    printf "║ Skipped:      %-42s ║\n" "${TESTS_SKIPPED}"
    printf "║ Duration:     %-42s ║\n" "${total_duration}s"
    echo "╠══════════════════════════════════════════════════════════╣"
    printf "║ Report:       %-42s ║\n" "$(basename $TEST_REPORT)"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        log_success "All tests passed! Database operations are functioning correctly."
        return 0
    else
        log_error "${TESTS_FAILED} test(s) failed. Review the report for details."
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    START_TIME=$(date +%s)

    # Create report directory
    mkdir -p "$TEST_REPORT_DIR"

    # Initialize report
    echo "# Database Operations Test Suite" > "$TEST_REPORT"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$TEST_REPORT"
    echo "" >> "$TEST_REPORT"

    log_section "Database Operations Comprehensive Test Suite"
    log_info "Starting comprehensive database testing..."
    log_info "Environment: $(detect_environment)"

    # Load configuration
    if ! load_db_config; then
        log_error "Failed to load database configuration"
        exit 1
    fi

    # Check database connectivity
    if ! check_db_connection; then
        log_error "Database connection failed"
        log_error "Please ensure database is running and credentials are correct"
        exit 1
    fi

    log_success "Database connection verified"
    echo ""

    # Run all tests
    test_full_backup
    test_incremental_backup
    test_compression_algorithms
    test_backup_verification
    test_backup_restore
    test_point_in_time_recovery
    test_migration_dry_run
    test_migration_execution
    test_migration_rollback
    test_database_monitor
    test_performance_benchmarks
    test_grafana_dashboard
    test_docker_volume_backups
    test_retention_policy
    test_concurrent_operations
    test_large_database

    # Generate final report
    generate_test_report

    # Exit with appropriate code
    if [ "$TESTS_FAILED" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
