#!/bin/bash

# ============================================================================
# Quick Test Runner for Database Operations
# ============================================================================
# Usage:
#   ./run-database-tests.sh              # Run all tests
#   ./run-database-tests.sh --quick      # Run quick validation only
#   ./run-database-tests.sh --backup     # Test backups only
#   ./run-database-tests.sh --help       # Show help
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/database-operations-test.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    cat << EOF
Database Operations Test Runner

Usage: $0 [OPTIONS]

OPTIONS:
  --quick       Run quick validation only (Tests 1, 7, 10)
  --backup      Test backup functionality (Tests 1-6)
  --migration   Test migration system (Tests 7-9)
  --monitoring  Test monitoring (Test 10)
  --performance Run performance benchmarks (Test 11)
  --all         Run all tests (default)
  --help        Show this help message

EXAMPLES:
  $0                    # Run all tests
  $0 --quick            # Quick validation
  $0 --backup           # Backup tests only

ENVIRONMENT VARIABLES:
  COMPRESSION           Backup compression (gzip, bzip2, xz, zstd)
  ENCRYPT_BACKUP        Enable encryption (true/false)
  VERIFICATION          Verification level (none, basic, full)

For detailed documentation, see:
  ${SCRIPT_DIR}/DATABASE-TESTING-GUIDE.md
EOF
}

run_quick_validation() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Quick Validation Test${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    cd /home/calounx/repositories/mentat/chom

    # Test 1: Database connectivity
    echo -e "${BLUE}[1/3] Testing database connection...${NC}"
    if php artisan db:monitor --type=overview >/tmp/quick_test_db.log 2>&1; then
        echo -e "${GREEN}✓ Database connection OK${NC}"
    else
        echo -e "${YELLOW}⚠ Database connection issue - check logs${NC}"
        exit 1
    fi

    # Test 2: Backup system
    echo -e "${BLUE}[2/3] Testing backup system...${NC}"
    if BACKUP_TYPE=full COMPRESSION=gzip VERIFICATION=basic ENCRYPT_BACKUP=false \
       ./scripts/backup-incremental.sh >/tmp/quick_test_backup.log 2>&1; then
        local backup=$(find storage/app/backups -name "full_*.sql.gz" -mmin -2 | head -1)
        if [ -n "$backup" ]; then
            local size=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null)
            echo -e "${GREEN}✓ Backup system OK ($(( size / 1024 ))KB)${NC}"
        else
            echo -e "${YELLOW}⚠ Backup file not found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Backup system issue - check logs${NC}"
    fi

    # Test 3: Migration system
    echo -e "${BLUE}[3/3] Testing migration system...${NC}"
    if php artisan migrate:dry-run --validate >/tmp/quick_test_migrate.log 2>&1; then
        echo -e "${GREEN}✓ Migration system OK${NC}"
    else
        echo -e "${YELLOW}⚠ Migration validation issue - check logs${NC}"
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Quick validation complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Detailed logs available in /tmp/quick_test_*.log"
}

run_backup_tests() {
    echo -e "${BLUE}Running backup tests (Tests 1-6)...${NC}"
    cd /home/calounx/repositories/mentat/chom

    # Test compression algorithms
    for algo in gzip zstd; do
        echo -e "${BLUE}Testing $algo compression...${NC}"
        BACKUP_TYPE=full COMPRESSION="$algo" VERIFICATION=basic ENCRYPT_BACKUP=false \
            ./scripts/backup-incremental.sh >/dev/null 2>&1
        echo -e "${GREEN}✓ $algo backup completed${NC}"
    done

    # Test incremental backup
    if mysql -h"${DB_HOST:-127.0.0.1}" -e "SHOW VARIABLES LIKE 'log_bin'" 2>/dev/null | grep -q "ON"; then
        echo -e "${BLUE}Testing incremental backup...${NC}"
        BACKUP_TYPE=incremental COMPRESSION=gzip ENCRYPT_BACKUP=false \
            ./scripts/backup-incremental.sh >/dev/null 2>&1
        echo -e "${GREEN}✓ Incremental backup completed${NC}"
    else
        echo -e "${YELLOW}⊘ Incremental backup skipped (binary logging not enabled)${NC}"
    fi

    echo -e "${GREEN}Backup tests complete!${NC}"
}

run_migration_tests() {
    echo -e "${BLUE}Running migration tests (Tests 7-9)...${NC}"
    cd /home/calounx/repositories/mentat/chom

    # Dry-run validation
    echo -e "${BLUE}Testing migration dry-run...${NC}"
    php artisan migrate:dry-run --validate

    # Migration status
    echo -e "${BLUE}Checking migration status...${NC}"
    php artisan migrate:status

    echo -e "${GREEN}Migration tests complete!${NC}"
}

run_monitoring_tests() {
    echo -e "${BLUE}Running monitoring tests (Test 10)...${NC}"
    cd /home/calounx/repositories/mentat/chom

    # Test different monitor types
    for type in overview queries tables; do
        echo -e "${BLUE}Testing monitor: $type${NC}"
        php artisan db:monitor --type="$type" >/dev/null 2>&1
        echo -e "${GREEN}✓ Monitor $type OK${NC}"
    done

    # Test JSON output
    echo -e "${BLUE}Testing JSON output...${NC}"
    php artisan db:monitor --json >/dev/null 2>&1
    echo -e "${GREEN}✓ JSON output OK${NC}"

    echo -e "${GREEN}Monitoring tests complete!${NC}"
}

run_performance_tests() {
    echo -e "${BLUE}Running performance benchmarks (Test 11)...${NC}"
    cd /home/calounx/repositories/mentat/chom

    if [ -f ./scripts/benchmark-database.sh ]; then
        ./scripts/benchmark-database.sh
        echo -e "${GREEN}Performance benchmarks complete!${NC}"
    else
        echo -e "${YELLOW}Benchmark script not found${NC}"
    fi
}

# Parse arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --quick)
        run_quick_validation
        exit 0
        ;;
    --backup)
        run_backup_tests
        exit 0
        ;;
    --migration)
        run_migration_tests
        exit 0
        ;;
    --monitoring)
        run_monitoring_tests
        exit 0
        ;;
    --performance)
        run_performance_tests
        exit 0
        ;;
    --all|"")
        # Run full test suite
        echo -e "${BLUE}Running full database operations test suite...${NC}"
        echo ""
        exec "$TEST_SCRIPT"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run '$0 --help' for usage information"
        exit 1
        ;;
esac
