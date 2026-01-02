#!/bin/bash
#
# CHOM/VPSManager Artisan Commands Regression Test Suite
# Generated: 2026-01-02
# Purpose: Comprehensive testing of all custom Laravel Artisan commands
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Log file
LOG_FILE="/tmp/artisan_regression_test_$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE="/tmp/artisan_test_results_$(date +%Y%m%d_%H%M%S).json"

# Base directory
CHOM_DIR="/home/calounx/repositories/mentat/chom"

# Initialize results
echo "{" > "$RESULTS_FILE"
echo "  \"test_run\": {" >> "$RESULTS_FILE"
echo "    \"timestamp\": \"$(date -Iseconds)\"," >> "$RESULTS_FILE"
echo "    \"environment\": \"local\"," >> "$RESULTS_FILE"
echo "    \"tests\": [" >> "$RESULTS_FILE"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1" | tee -a "$LOG_FILE"
}

# Test execution function
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_exit_code="${3:-0}"
    local description="$4"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log_info "Running: $test_name"
    log_info "Command: $command"
    log_info "Description: $description"

    local start_time=$(date +%s.%N)

    # Execute command
    cd "$CHOM_DIR"
    local output
    local exit_code

    if output=$(eval "$command" 2>&1); then
        exit_code=$?
    else
        exit_code=$?
    fi

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    # Evaluate result
    if [ "$exit_code" -eq "$expected_exit_code" ]; then
        log_success "$test_name - Exit code: $exit_code (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        local status="PASS"
    else
        log_error "$test_name - Expected exit code $expected_exit_code, got $exit_code"
        log_error "Output: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        local status="FAIL"
    fi

    # Append to results JSON
    cat >> "$RESULTS_FILE" <<EOF
      {
        "name": "$test_name",
        "command": "$command",
        "description": "$description",
        "status": "$status",
        "exit_code": $exit_code,
        "expected_exit_code": $expected_exit_code,
        "duration": $duration,
        "output_length": ${#output}
      },
EOF
}

# Skip test function
skip_test() {
    local test_name="$1"
    local reason="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))

    log_skip "$test_name - $reason"

    cat >> "$RESULTS_FILE" <<EOF
      {
        "name": "$test_name",
        "status": "SKIP",
        "reason": "$reason"
      },
EOF
}

# Header
echo ""
echo "=============================================="
echo " CHOM Artisan Commands Regression Test Suite"
echo "=============================================="
echo "Start Time: $(date)"
echo "Log File: $LOG_FILE"
echo "Results File: $RESULTS_FILE"
echo "=============================================="
echo ""

# PHASE 1: DATABASE COMMANDS
log_info "========== PHASE 1: DATABASE COMMANDS =========="

run_test \
    "db:monitor - Basic overview" \
    "php artisan db:monitor --type=overview" \
    0 \
    "Display database overview with size, connections, and performance metrics"

run_test \
    "db:monitor - JSON output" \
    "php artisan db:monitor --type=overview --json" \
    0 \
    "Output database metrics in JSON format"

run_test \
    "db:monitor - Query monitoring" \
    "php artisan db:monitor --type=queries" \
    0 \
    "Monitor running queries and slow query log status"

run_test \
    "db:monitor - Index statistics" \
    "php artisan db:monitor --type=indexes" \
    0 \
    "Display index usage and identify unused indexes"

run_test \
    "db:monitor - Table statistics" \
    "php artisan db:monitor --type=tables" \
    0 \
    "Show table sizes, row counts, and fragmentation"

run_test \
    "db:monitor - Lock monitoring" \
    "php artisan db:monitor --type=locks" \
    0 \
    "Check for table locks and lock contention"

run_test \
    "db:monitor - Backup status" \
    "php artisan db:monitor --type=backups" \
    0 \
    "Display backup file status and age"

run_test \
    "db:monitor - Help documentation" \
    "php artisan db:monitor --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "migrate:dry-run - Validation only" \
    "php artisan migrate:dry-run --validate" \
    0 \
    "Run pre-migration validation without executing migrations"

run_test \
    "migrate:dry-run - Pretend mode" \
    "php artisan migrate:dry-run --pretend" \
    0 \
    "Show SQL queries that would be executed without running them"

run_test \
    "migrate:dry-run - Help documentation" \
    "php artisan migrate:dry-run --help" \
    0 \
    "Verify help documentation is complete"

# PHASE 2: BACKUP COMMANDS
log_info "========== PHASE 2: BACKUP COMMANDS =========="

run_test \
    "backup:database - Basic backup" \
    "php artisan backup:database" \
    0 \
    "Create database backup without encryption"

run_test \
    "backup:database - Encrypted backup" \
    "php artisan backup:database --encrypt" \
    0 \
    "Create encrypted database backup"

run_test \
    "backup:database - Help documentation" \
    "php artisan backup:database --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "backup:clean - Dry run" \
    "php artisan backup:clean --dry-run" \
    0 \
    "Show which backups would be deleted without deleting"

run_test \
    "backup:clean - Help documentation" \
    "php artisan backup:clean --help" \
    0 \
    "Verify help documentation is complete"

# PHASE 3: DEBUG COMMANDS
log_info "========== PHASE 3: DEBUG COMMANDS =========="

skip_test \
    "debug:auth - Test with user email" \
    "Requires valid user email in database"

run_test \
    "debug:auth - Help documentation" \
    "php artisan debug:auth --help" \
    0 \
    "Verify help documentation is complete"

skip_test \
    "debug:tenant - Test with tenant ID" \
    "Requires valid tenant ID in database"

run_test \
    "debug:tenant - Help documentation" \
    "php artisan debug:tenant --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "debug:cache - Display cache info" \
    "php artisan debug:cache" \
    0 \
    "Display cache driver and statistics"

run_test \
    "debug:cache - Help documentation" \
    "php artisan debug:cache --help" \
    0 \
    "Verify help documentation is complete"

skip_test \
    "debug:performance - Test route profiling" \
    "Requires running web server for route profiling"

run_test \
    "debug:performance - Help documentation" \
    "php artisan debug:performance --help" \
    0 \
    "Verify help documentation is complete"

# PHASE 4: SECURITY & CONFIG COMMANDS
log_info "========== PHASE 4: SECURITY & CONFIG COMMANDS =========="

run_test \
    "security:scan - Basic scan" \
    "php artisan security:scan" \
    0 \
    "Run security scan without fixes"

run_test \
    "security:scan - Help documentation" \
    "php artisan security:scan --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "config:validate - Validate configuration" \
    "php artisan config:validate" \
    0 \
    "Validate all configuration files"

run_test \
    "config:validate - Help documentation" \
    "php artisan config:validate --help" \
    0 \
    "Verify help documentation is complete"

skip_test \
    "secrets:rotate - Rotate secrets" \
    "Requires production environment or force flag to test rotation"

run_test \
    "secrets:rotate - Help documentation" \
    "php artisan secrets:rotate --help" \
    0 \
    "Verify help documentation is complete"

# PHASE 5: CODE GENERATION COMMANDS
log_info "========== PHASE 5: CODE GENERATION COMMANDS =========="

run_test \
    "make:service - Create test service" \
    "php artisan make:service TestRegressionService" \
    0 \
    "Generate a new service class"

run_test \
    "make:service - Help documentation" \
    "php artisan make:service --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "make:repository - Create test repository" \
    "php artisan make:repository TestRegressionRepository" \
    0 \
    "Generate a new repository class"

run_test \
    "make:repository - Help documentation" \
    "php artisan make:repository --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "make:api-resource - Create test API resource" \
    "php artisan make:api-resource TestRegressionResource" \
    0 \
    "Generate a new API resource class"

run_test \
    "make:api-resource - Help documentation" \
    "php artisan make:api-resource --help" \
    0 \
    "Verify help documentation is complete"

run_test \
    "make:value-object - Create test value object" \
    "php artisan make:value-object TestRegressionValue" \
    0 \
    "Generate a new value object class"

run_test \
    "make:value-object - Help documentation" \
    "php artisan make:value-object --help" \
    0 \
    "Verify help documentation is complete"

# Clean up generated test files
log_info "Cleaning up generated test files..."
rm -f "$CHOM_DIR/app/Services/TestRegressionService.php" 2>/dev/null || true
rm -f "$CHOM_DIR/app/Repositories/TestRegressionRepository.php" 2>/dev/null || true
rm -f "$CHOM_DIR/app/Http/Resources/TestRegressionResource.php" 2>/dev/null || true
rm -f "$CHOM_DIR/app/ValueObjects/TestRegressionValue.php" 2>/dev/null || true

# Finalize results JSON
sed -i '$ s/,$//' "$RESULTS_FILE"  # Remove last comma
cat >> "$RESULTS_FILE" <<EOF
    ]
  },
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "pass_rate": $(echo "scale=2; ($PASSED_TESTS / $TOTAL_TESTS) * 100" | bc)
  }
}
EOF

# Summary
echo ""
echo "=============================================="
echo " TEST SUMMARY"
echo "=============================================="
echo "Total Tests:   $TOTAL_TESTS"
echo "Passed:        $PASSED_TESTS"
echo "Failed:        $FAILED_TESTS"
echo "Skipped:       $SKIPPED_TESTS"
echo "Pass Rate:     $(echo "scale=2; ($PASSED_TESTS / $TOTAL_TESTS) * 100" | bc)%"
echo "=============================================="
echo "End Time: $(date)"
echo "Log File: $LOG_FILE"
echo "Results: $RESULTS_FILE"
echo "=============================================="
echo ""

# Exit with appropriate code
if [ $FAILED_TESTS -gt 0 ]; then
    exit 1
else
    exit 0
fi
