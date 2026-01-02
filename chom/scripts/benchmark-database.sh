#!/bin/bash

# ============================================================================
# Database Backup & Restore Performance Benchmark
# ============================================================================
# Benchmarks:
# - Backup performance across different compression algorithms
# - Restore performance optimization techniques
# - Migration execution time
# - Database warm-up effectiveness
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BENCHMARK_DIR="${PROJECT_ROOT}/storage/app/benchmarks"
RESULTS_FILE="${BENCHMARK_DIR}/benchmark_${TIMESTAMP}.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Benchmark results
declare -A RESULTS

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ $1${NC}"
}

format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# ============================================================================
# Database Configuration
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

    DB_PORT="${DB_PORT:-3306}"
}

# ============================================================================
# Backup Performance Benchmark
# ============================================================================

benchmark_backup_compression() {
    log_info "=========================================="
    log_info "  Backup Compression Benchmark"
    log_info "=========================================="

    local test_db="${DB_DATABASE}_benchmark"
    local algorithms=("none" "gzip" "bzip2" "xz" "zstd")

    # Create test database with sample data
    log_info "Creating test database..."
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "DROP DATABASE IF EXISTS ${test_db}; CREATE DATABASE ${test_db};" 2>/dev/null

    # Populate with test data
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" "${test_db}" <<EOF
CREATE TABLE benchmark_data (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id)
);

INSERT INTO benchmark_data (user_id, data)
SELECT
    FLOOR(RAND() * 10000),
    REPEAT('Sample data for benchmarking ', 10)
FROM
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t1,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t2,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t3,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t4,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t5,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4) t6;
EOF

    log_success "Test database created with sample data"

    # Benchmark each compression algorithm
    for algo in "${algorithms[@]}"; do
        log_info "Testing compression: $algo"

        local backup_file="${BENCHMARK_DIR}/backup_${algo}.sql"
        local start_time=$(date +%s.%N)

        # Perform backup
        case "$algo" in
            none)
                mysqldump -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                    --single-transaction --quick "${test_db}" > "$backup_file" 2>/dev/null
                ;;
            gzip)
                mysqldump -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                    --single-transaction --quick "${test_db}" | gzip -6 > "${backup_file}.gz" 2>/dev/null
                backup_file="${backup_file}.gz"
                ;;
            bzip2)
                mysqldump -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                    --single-transaction --quick "${test_db}" | bzip2 -9 > "${backup_file}.bz2" 2>/dev/null
                backup_file="${backup_file}.bz2"
                ;;
            xz)
                mysqldump -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                    --single-transaction --quick "${test_db}" | xz -6 > "${backup_file}.xz" 2>/dev/null
                backup_file="${backup_file}.xz"
                ;;
            zstd)
                if command -v zstd &> /dev/null; then
                    mysqldump -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
                        --single-transaction --quick "${test_db}" | zstd -3 > "${backup_file}.zst" 2>/dev/null
                    backup_file="${backup_file}.zst"
                else
                    log_info "zstd not available, skipping"
                    continue
                fi
                ;;
        esac

        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
        local throughput=$(echo "scale=2; $file_size / $duration / 1024 / 1024" | bc)

        RESULTS["backup_${algo}_duration"]="$duration"
        RESULTS["backup_${algo}_size"]="$file_size"
        RESULTS["backup_${algo}_throughput"]="$throughput"

        log_success "Compression: $algo | Duration: ${duration}s | Size: $(format_bytes $file_size) | Throughput: ${throughput} MB/s"
    done

    # Cleanup
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "DROP DATABASE IF EXISTS ${test_db};" 2>/dev/null

    log_success "Backup compression benchmark completed"
}

# ============================================================================
# Restore Performance Benchmark
# ============================================================================

benchmark_restore_performance() {
    log_info "=========================================="
    log_info "  Restore Performance Benchmark"
    log_info "=========================================="

    local backup_file="${BENCHMARK_DIR}/backup_gzip.sql.gz"

    if [ ! -f "$backup_file" ]; then
        log_error "No backup file found for restore benchmark"
        return 1
    fi

    # Test 1: Standard restore
    log_info "Test 1: Standard restore (baseline)"
    local test_db="${DB_DATABASE}_restore_test"

    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "DROP DATABASE IF EXISTS ${test_db}; CREATE DATABASE ${test_db};" 2>/dev/null

    local start_time=$(date +%s.%N)
    gunzip -c "$backup_file" | mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" \
        -p"${DB_PASSWORD}" "${test_db}" 2>/dev/null
    local end_time=$(date +%s.%N)
    local standard_duration=$(echo "$end_time - $start_time" | bc)

    RESULTS["restore_standard_duration"]="$standard_duration"
    log_success "Standard restore: ${standard_duration}s"

    # Test 2: Optimized restore (foreign keys disabled)
    log_info "Test 2: Optimized restore (FK disabled)"

    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "DROP DATABASE IF EXISTS ${test_db}; CREATE DATABASE ${test_db};" 2>/dev/null

    start_time=$(date +%s.%N)
    gunzip -c "$backup_file" | mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" \
        -p"${DB_PASSWORD}" "${test_db}" -e "SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET AUTOCOMMIT=0;" 2>/dev/null
    end_time=$(date +%s.%N)
    local optimized_duration=$(echo "$end_time - $start_time" | bc)

    RESULTS["restore_optimized_duration"]="$optimized_duration"
    local speedup=$(echo "scale=2; $standard_duration / $optimized_duration" | bc)
    log_success "Optimized restore: ${optimized_duration}s (${speedup}x faster)"

    # Cleanup
    mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
          -e "DROP DATABASE IF EXISTS ${test_db};" 2>/dev/null

    log_success "Restore performance benchmark completed"
}

# ============================================================================
# Migration Performance Benchmark
# ============================================================================

benchmark_migration_performance() {
    log_info "=========================================="
    log_info "  Migration Performance Benchmark"
    log_info "=========================================="

    cd "$PROJECT_ROOT"

    # Test dry-run migration
    log_info "Running migration dry-run..."
    local start_time=$(date +%s.%N)

    php artisan migrate:dry-run --validate 2>&1 | grep -E "(✓|✗|⚠)" || true

    local end_time=$(date +%s.%N)
    local validation_duration=$(echo "$end_time - $start_time" | bc)

    RESULTS["migration_validation_duration"]="$validation_duration"
    log_success "Migration validation: ${validation_duration}s"

    # Count pending migrations
    local pending_migrations=$(php artisan migrate:status 2>/dev/null | grep -c "Pending" || echo 0)
    RESULTS["migration_pending_count"]="$pending_migrations"
    log_info "Pending migrations: $pending_migrations"

    log_success "Migration performance benchmark completed"
}

# ============================================================================
# Database Size Benchmark
# ============================================================================

benchmark_database_size() {
    log_info "=========================================="
    log_info "  Database Size Analysis"
    log_info "=========================================="

    if [ "$DB_CONNECTION" = "mysql" ] || [ "$DB_CONNECTION" = "mariadb" ]; then
        local size_query="
            SELECT
                ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_mb,
                ROUND(SUM(data_length) / 1024 / 1024, 2) AS data_mb,
                ROUND(SUM(index_length) / 1024 / 1024, 2) AS index_mb,
                COUNT(*) AS table_count
            FROM information_schema.TABLES
            WHERE table_schema = '${DB_DATABASE}'
        "

        local result=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" \
                      -p"${DB_PASSWORD}" -e "$size_query" -ss 2>/dev/null)

        local total_mb=$(echo "$result" | awk '{print $1}')
        local data_mb=$(echo "$result" | awk '{print $2}')
        local index_mb=$(echo "$result" | awk '{print $3}')
        local table_count=$(echo "$result" | awk '{print $4}')

        RESULTS["db_size_total_mb"]="$total_mb"
        RESULTS["db_size_data_mb"]="$data_mb"
        RESULTS["db_size_index_mb"]="$index_mb"
        RESULTS["db_table_count"]="$table_count"

        log_info "Total Size: ${total_mb} MB"
        log_info "Data Size: ${data_mb} MB"
        log_info "Index Size: ${index_mb} MB"
        log_info "Table Count: $table_count"

        # Largest tables
        log_info "Largest tables:"
        mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USERNAME}" -p"${DB_PASSWORD}" \
              -e "SELECT TABLE_NAME, ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb
                  FROM information_schema.TABLES
                  WHERE TABLE_SCHEMA = '${DB_DATABASE}'
                  ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
                  LIMIT 5" 2>/dev/null | tail -n +2 | while read table size; do
            log_info "  - $table: ${size} MB"
        done
    fi

    log_success "Database size analysis completed"
}

# ============================================================================
# Generate Report
# ============================================================================

generate_report() {
    log_info "=========================================="
    log_info "  Benchmark Report"
    log_info "=========================================="

    # Create JSON report
    cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "database": "${DB_CONNECTION}",
  "results": {
EOF

    local first=true
    for key in "${!RESULTS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$RESULTS_FILE"
        fi
        echo -n "    \"${key}\": \"${RESULTS[$key]}\"" >> "$RESULTS_FILE"
    done

    cat >> "$RESULTS_FILE" <<EOF

  }
}
EOF

    log_success "Benchmark results saved to: $RESULTS_FILE"

    # Display summary
    echo ""
    log_info "Benchmark Summary:"
    echo ""
    echo "Database Size:"
    echo "  Total: ${RESULTS[db_size_total_mb]:-N/A} MB"
    echo "  Tables: ${RESULTS[db_table_count]:-N/A}"
    echo ""
    echo "Backup Performance (gzip):"
    echo "  Duration: ${RESULTS[backup_gzip_duration]:-N/A}s"
    echo "  Size: $(format_bytes ${RESULTS[backup_gzip_size]:-0})"
    echo "  Throughput: ${RESULTS[backup_gzip_throughput]:-N/A} MB/s"
    echo ""
    echo "Restore Performance:"
    echo "  Standard: ${RESULTS[restore_standard_duration]:-N/A}s"
    echo "  Optimized: ${RESULTS[restore_optimized_duration]:-N/A}s"
    echo ""
    echo "Migration:"
    echo "  Validation: ${RESULTS[migration_validation_duration]:-N/A}s"
    echo "  Pending: ${RESULTS[migration_pending_count]:-0}"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  Database Performance Benchmark"
    log_info "=========================================="
    log_info "Timestamp: $TIMESTAMP"
    log_info ""

    # Create benchmark directory
    mkdir -p "$BENCHMARK_DIR"

    # Load database configuration
    load_db_config

    # Run benchmarks
    benchmark_database_size
    echo ""

    benchmark_backup_compression
    echo ""

    benchmark_restore_performance
    echo ""

    benchmark_migration_performance
    echo ""

    # Generate report
    generate_report

    log_success "All benchmarks completed!"
}

# Run main function
main "$@"
