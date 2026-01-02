#!/usr/bin/env bash
# ============================================================================
# Disaster Recovery Testing Script
# ============================================================================
# Automated DR testing and validation
# Performs regular recovery drills to ensure procedures work
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test Configuration
TEST_TYPE="${1:-quick}"  # quick, full, database, volumes
TEST_ENV_PREFIX="dr_test_"
TEST_NETWORK="${TEST_ENV_PREFIX}network"
TEST_RESULTS_DIR="${PROJECT_ROOT}/reports/dr-tests"

# S3 Configuration
CONFIG_FILE="${BACKUP_CONFIG_FILE:-${SCRIPT_DIR}/backup-config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Metrics Configuration
METRICS_ENABLED="${METRICS_ENABLED:-true}"
METRICS_PUSHGATEWAY="${METRICS_PUSHGATEWAY:-http://localhost:9091}"

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
TEST_REPORT="${TEST_RESULTS_DIR}/dr_test_${TIMESTAMP}.txt"
TEST_START_TIME=$(date +%s)
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Logging Functions
# ============================================================================

mkdir -p "$TEST_RESULTS_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$TEST_REPORT"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "$TEST_REPORT"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] PASS: $*${NC}" | tee -a "$TEST_REPORT"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: $*${NC}" | tee -a "$TEST_REPORT"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*${NC}" | tee -a "$TEST_REPORT"
}

# ============================================================================
# Test Environment Functions
# ============================================================================

setup_test_environment() {
    log_info "Setting up test environment..."

    # Create test network
    if ! docker network inspect "$TEST_NETWORK" > /dev/null 2>&1; then
        docker network create "$TEST_NETWORK"
    fi

    log_success "Test environment ready"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."

    # Stop and remove all test containers
    docker ps -a --filter "name=${TEST_ENV_PREFIX}" --format '{{.Names}}' | while read -r container; do
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    done

    # Remove test volumes
    docker volume ls --filter "name=${TEST_ENV_PREFIX}" --format '{{.Name}}' | while read -r volume; do
        docker volume rm "$volume" 2>/dev/null || true
    done

    # Remove test network
    docker network rm "$TEST_NETWORK" 2>/dev/null || true

    log_success "Test environment cleaned up"
}

# ============================================================================
# Test Functions - Database Recovery
# ============================================================================

test_database_backup_restore() {
    log_info "========================================="
    log_info "TEST: Database Backup & Restore"
    log_info "========================================="

    local test_start
    test_start=$(date +%s)

    # Step 1: Find latest backup
    log_info "Step 1: Locating latest database backup..."
    local backup_file
    backup_file=$(find "${PROJECT_ROOT}/chom/storage/app/backups" -name "backup_*.sql" -o -name "backup_*.sql.gz" 2>/dev/null | sort -r | head -1)

    if [[ -z "$backup_file" ]]; then
        # Try downloading from S3
        if [[ -n "$S3_BUCKET" ]]; then
            log_info "No local backup found. Attempting S3 download..."
            local today
            today=$(date +%Y-%m-%d)

            local s3_file
            s3_file=$(aws s3 ls "s3://${S3_BUCKET}/mysql/${today}/" | tail -1 | awk '{print $4}')

            if [[ -n "$s3_file" ]]; then
                backup_file="/tmp/${s3_file}"
                aws s3 cp "s3://${S3_BUCKET}/mysql/${today}/${s3_file}" "$backup_file"

                # Decrypt if needed
                if [[ "$s3_file" == *.gpg ]]; then
                    gpg --decrypt "$backup_file" > "${backup_file%.gpg}"
                    backup_file="${backup_file%.gpg}"
                fi
            fi
        fi
    fi

    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        log_error "No database backup found"
        return 1
    fi

    log_success "Found backup: $(basename "$backup_file")"

    # Step 2: Start test MySQL container
    log_info "Step 2: Starting test MySQL container..."
    local test_mysql="${TEST_ENV_PREFIX}mysql"

    docker run -d \
        --name "$test_mysql" \
        --network "$TEST_NETWORK" \
        -e MYSQL_ROOT_PASSWORD=test_root_password \
        -e MYSQL_DATABASE=test_db \
        -e MYSQL_USER=test_user \
        -e MYSQL_PASSWORD=test_password \
        mysql:8.0 > /dev/null 2>&1

    # Wait for MySQL to be ready
    log_info "Waiting for MySQL to be ready..."
    local max_wait=60
    local waited=0
    while ! docker exec "$test_mysql" mysqladmin ping -h localhost -ptest_root_password > /dev/null 2>&1; do
        sleep 2
        ((waited+=2))
        if [[ $waited -ge $max_wait ]]; then
            log_error "MySQL did not start in time"
            return 1
        fi
    done

    log_success "MySQL container ready"

    # Step 3: Restore backup
    log_info "Step 3: Restoring backup..."
    local temp_sql="/tmp/test_restore_$$.sql"

    if [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" > "$temp_sql"
    else
        cp "$backup_file" "$temp_sql"
    fi

    local restore_start
    restore_start=$(date +%s)

    if docker exec -i "$test_mysql" mysql -u root -ptest_root_password test_db < "$temp_sql" 2>/dev/null; then
        local restore_duration=$(($(date +%s) - restore_start))
        log_success "Database restored in ${restore_duration}s"
    else
        log_error "Database restore failed"
        rm -f "$temp_sql"
        return 1
    fi

    rm -f "$temp_sql"

    # Step 4: Verify restored data
    log_info "Step 4: Verifying restored data..."

    # Check table count
    local table_count
    table_count=$(docker exec "$test_mysql" mysql -u root -ptest_root_password -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='test_db';" -s -N 2>/dev/null || echo "0")

    if [[ $table_count -gt 0 ]]; then
        log_success "Restored database contains $table_count tables"
    else
        log_error "Restored database is empty"
        return 1
    fi

    # Check for users table (common in Laravel apps)
    if docker exec "$test_mysql" mysql -u root -ptest_root_password -e \
        "SHOW TABLES LIKE 'users';" test_db 2>/dev/null | grep -q "users"; then
        local user_count
        user_count=$(docker exec "$test_mysql" mysql -u root -ptest_root_password -e \
            "SELECT COUNT(*) FROM users;" test_db -s -N 2>/dev/null || echo "0")
        log_success "Users table found with $user_count records"
    else
        log_warning "Users table not found (may be expected)"
    fi

    # Step 5: Test database functionality
    log_info "Step 5: Testing database operations..."

    # Test write operation
    if docker exec "$test_mysql" mysql -u root -ptest_root_password test_db -e \
        "CREATE TABLE IF NOT EXISTS dr_test (id INT PRIMARY KEY, test_data VARCHAR(255));" 2>/dev/null; then
        log_success "CREATE TABLE operation successful"
    else
        log_error "CREATE TABLE operation failed"
        return 1
    fi

    # Test insert operation
    if docker exec "$test_mysql" mysql -u root -ptest_root_password test_db -e \
        "INSERT INTO dr_test (id, test_data) VALUES (1, 'DR Test');" 2>/dev/null; then
        log_success "INSERT operation successful"
    else
        log_error "INSERT operation failed"
        return 1
    fi

    # Test select operation
    local test_data
    test_data=$(docker exec "$test_mysql" mysql -u root -ptest_root_password test_db -e \
        "SELECT test_data FROM dr_test WHERE id=1;" -s -N 2>/dev/null || echo "")

    if [[ "$test_data" == "DR Test" ]]; then
        log_success "SELECT operation successful"
    else
        log_error "SELECT operation failed"
        return 1
    fi

    # Calculate RTO
    local test_duration=$(($(date +%s) - test_start))
    log_info "Total database recovery time: ${test_duration}s"

    # Check against RTO target (2 hours = 7200s)
    if [[ $test_duration -lt 7200 ]]; then
        log_success "Database recovery RTO met (target: 2h, actual: ${test_duration}s)"
    else
        log_error "Database recovery RTO exceeded (target: 2h, actual: ${test_duration}s)"
        return 1
    fi

    return 0
}

# ============================================================================
# Test Functions - Volume Recovery
# ============================================================================

test_volume_backup_restore() {
    log_info "========================================="
    log_info "TEST: Docker Volume Backup & Restore"
    log_info "========================================="

    local test_start
    test_start=$(date +%s)

    # Step 1: Find latest volume backup
    log_info "Step 1: Locating latest volume backup..."
    local backup_file
    backup_file=$(find "${PROJECT_ROOT}/docker/backups" -name "*_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        log_error "No volume backup found"
        return 1
    fi

    log_success "Found backup: $(basename "$backup_file")"

    # Step 2: Create test volume
    log_info "Step 2: Creating test volume..."
    local test_volume="${TEST_ENV_PREFIX}volume"

    docker volume create "$test_volume" > /dev/null 2>&1
    log_success "Test volume created"

    # Step 3: Restore backup to volume
    log_info "Step 3: Restoring backup to volume..."

    local restore_start
    restore_start=$(date +%s)

    if docker run --rm \
        -v "${test_volume}:/data" \
        -v "$(dirname "$backup_file"):/backup" \
        debian:12-slim \
        tar xzf "/backup/$(basename "$backup_file")" -C /data 2>/dev/null; then

        local restore_duration=$(($(date +%s) - restore_start))
        log_success "Volume restored in ${restore_duration}s"
    else
        log_error "Volume restore failed"
        return 1
    fi

    # Step 4: Verify restored content
    log_info "Step 4: Verifying restored content..."

    local file_count
    file_count=$(docker run --rm -v "${test_volume}:/data" debian:12-slim find /data -type f | wc -l)

    if [[ $file_count -gt 0 ]]; then
        log_success "Restored volume contains $file_count files"
    else
        log_error "Restored volume is empty"
        return 1
    fi

    # Step 5: Test volume accessibility
    log_info "Step 5: Testing volume accessibility..."

    local test_container="${TEST_ENV_PREFIX}volume_test"

    if docker run -d \
        --name "$test_container" \
        --network "$TEST_NETWORK" \
        -v "${test_volume}:/data" \
        debian:12-slim \
        sleep 3600 > /dev/null 2>&1; then

        # Try to read a file
        if docker exec "$test_container" ls -la /data > /dev/null 2>&1; then
            log_success "Volume is accessible from container"
        else
            log_error "Volume is not accessible from container"
            return 1
        fi

        # Try to write a file
        if docker exec "$test_container" touch /data/dr_test_file 2>/dev/null; then
            log_success "Volume is writable"
        else
            log_warning "Volume is not writable (may be expected if read-only)"
        fi
    else
        log_error "Failed to start test container"
        return 1
    fi

    local test_duration=$(($(date +%s) - test_start))
    log_info "Total volume recovery time: ${test_duration}s"

    return 0
}

# ============================================================================
# Test Functions - Configuration Recovery
# ============================================================================

test_configuration_backup_restore() {
    log_info "========================================="
    log_info "TEST: Configuration Backup & Restore"
    log_info "========================================="

    # Step 1: Verify critical configuration files exist
    log_info "Step 1: Checking critical configuration files..."

    local critical_files=(
        "${PROJECT_ROOT}/chom/.env"
        "${PROJECT_ROOT}/docker-compose.yml"
        "${PROJECT_ROOT}/chom/docker-compose.production.yml"
    )

    local missing_files=0

    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "Found: $file"
        else
            log_error "Missing: $file"
            ((missing_files++))
        fi
    done

    if [[ $missing_files -gt 0 ]]; then
        log_error "$missing_files critical configuration file(s) missing"
        return 1
    fi

    # Step 2: Test configuration backup from S3
    if [[ -n "$S3_BUCKET" ]]; then
        log_info "Step 2: Testing configuration restore from S3..."

        local today
        today=$(date +%Y-%m-%d)

        local config_backup
        config_backup=$(aws s3 ls "s3://${S3_BUCKET}/config/${today}/" 2>/dev/null | tail -1 | awk '{print $4}' || echo "")

        if [[ -n "$config_backup" ]]; then
            log_success "Configuration backup found in S3: $config_backup"

            # Test download
            local temp_config="/tmp/config_test_$$.tar.gz"
            if aws s3 cp "s3://${S3_BUCKET}/config/${today}/${config_backup}" "$temp_config" 2>/dev/null; then
                log_success "Configuration download successful"

                # Test decryption (if encrypted)
                if [[ "$config_backup" == *.gpg ]]; then
                    if gpg --decrypt "$temp_config" > "${temp_config%.gpg}" 2>/dev/null; then
                        log_success "Configuration decryption successful"
                        temp_config="${temp_config%.gpg}"
                    else
                        log_error "Configuration decryption failed"
                        rm -f "$temp_config"
                        return 1
                    fi
                fi

                # Test extraction
                local temp_extract="/tmp/config_extract_$$"
                mkdir -p "$temp_extract"

                if tar -xzf "$temp_config" -C "$temp_extract" 2>/dev/null; then
                    log_success "Configuration extraction successful"

                    # Verify key files present
                    if [[ -f "$temp_extract/.env" ]]; then
                        log_success ".env file present in backup"
                    else
                        log_warning ".env file not found in backup"
                    fi
                else
                    log_error "Configuration extraction failed"
                    rm -rf "$temp_config" "$temp_extract"
                    return 1
                fi

                # Cleanup
                rm -rf "$temp_config" "$temp_extract"
            else
                log_error "Configuration download failed"
                return 1
            fi
        else
            log_warning "No configuration backup found in S3 for today"
        fi
    else
        log_warning "S3 not configured, skipping offsite configuration test"
    fi

    return 0
}

# ============================================================================
# Test Functions - Full Application Recovery
# ============================================================================

test_full_application_recovery() {
    log_info "========================================="
    log_info "TEST: Full Application Recovery"
    log_info "========================================="

    log_info "This test simulates a complete application recovery from backups"

    # Run all component tests
    local failed_tests=0

    if ! test_database_backup_restore; then
        ((failed_tests++))
    fi

    if ! test_volume_backup_restore; then
        ((failed_tests++))
    fi

    if ! test_configuration_backup_restore; then
        ((failed_tests++))
    fi

    if [[ $failed_tests -eq 0 ]]; then
        log_success "Full application recovery test passed"
        return 0
    else
        log_error "Full application recovery test failed ($failed_tests component failures)"
        return 1
    fi
}

# ============================================================================
# Reporting Functions
# ============================================================================

generate_test_report() {
    local test_duration=$(($(date +%s) - TEST_START_TIME))

    log_info "========================================="
    log_info "  DR Test Summary"
    log_info "========================================="
    log_info "Test Type: $TEST_TYPE"
    log_info "Duration: ${test_duration}s"
    log_success "Tests Passed: $TESTS_PASSED"
    log_error "Tests Failed: $TESTS_FAILED"
    log_info "========================================="

    # Determine overall status
    local overall_status="PASS"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        overall_status="FAIL"
    fi

    echo ""
    echo "Overall Status: $overall_status"
    echo "Report saved to: $TEST_REPORT"

    # Push metrics
    if [[ "$METRICS_ENABLED" == "true" ]]; then
        push_metric "dr_test_passed" "$TESTS_PASSED"
        push_metric "dr_test_failed" "$TESTS_FAILED"
        push_metric "dr_test_duration_seconds" "$test_duration"
        push_metric "dr_last_test_timestamp" "$(date +%s)"
        push_metric "dr_test_status" "$([[ $overall_status == "PASS" ]] && echo 1 || echo 0)"
    fi

    return $([[ $overall_status == "PASS" ]] && echo 0 || echo 1)
}

push_metric() {
    local metric_name="$1"
    local metric_value="$2"

    cat <<EOF | curl -s --data-binary @- "${METRICS_PUSHGATEWAY}/metrics/job/dr_testing/instance/$(hostname)" || true
# TYPE ${metric_name} gauge
${metric_name} ${metric_value}
EOF
}

# ============================================================================
# Main Execution
# ============================================================================

usage() {
    cat <<EOF
Disaster Recovery Testing Script

Usage: $0 [TEST_TYPE]

Test Types:
  quick       - Quick verification tests (default)
  database    - Database backup/restore test only
  volumes     - Volume backup/restore test only
  config      - Configuration backup/restore test only
  full        - Complete application recovery simulation

Examples:
  $0                    # Run quick tests
  $0 database          # Test database recovery only
  $0 full              # Full recovery simulation

EOF
    exit 0
}

main() {
    log_info "========================================="
    log_info "  Disaster Recovery Test Started"
    log_info "========================================="
    log_info "Test Type: $TEST_TYPE"
    log_info "Timestamp: $TIMESTAMP"

    # Setup test environment
    setup_test_environment

    # Run tests based on type
    case "$TEST_TYPE" in
        quick|database)
            test_database_backup_restore
            ;;
        volumes)
            test_volume_backup_restore
            ;;
        config)
            test_configuration_backup_restore
            ;;
        full)
            test_full_application_recovery
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown test type: $TEST_TYPE"
            usage
            ;;
    esac

    # Cleanup
    cleanup_test_environment

    # Generate report
    generate_test_report

    # Exit with appropriate code
    exit $?
}

# Trap errors
trap 'log_error "DR test failed at line $LINENO"; cleanup_test_environment; exit 1' ERR

# Run main function
main "$@"
