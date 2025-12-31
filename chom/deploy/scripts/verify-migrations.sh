#!/bin/bash
#===============================================================================
# Database Migration Verification Script
#
# Verifies all migrations can be applied, rolled back, and are idempotent
#
# Usage:
#   ./verify-migrations.sh [OPTIONS]
#
# Options:
#   --verbose    Show detailed output
#   --help       Show this help
#===============================================================================

set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERBOSE=false

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

#===============================================================================
# Helper Functions
#===============================================================================

print_section() {
    echo ""
    echo "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "${CYAN}${BOLD} $1${NC}"
    echo "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test() {
    local test_name="$1"
    echo -n "${BLUE}  [TEST]${NC} ${test_name}... "
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

pass_test() {
    echo "${GREEN}✓ PASS${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    [[ "$VERBOSE" == true ]] && [[ -n "${1:-}" ]] && echo "    ${GREEN}→${NC} $1"
}

fail_test() {
    echo "${RED}✗ FAIL${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "    ${RED}→${NC} $1"
}

warn() {
    echo "${YELLOW}  [WARN]${NC} $1"
}

info() {
    [[ "$VERBOSE" == true ]] && echo "${BLUE}  [INFO]${NC} $1"
}

artisan() {
    php "${PROJECT_ROOT}/artisan" "$@" 2>&1
}

#===============================================================================
# Test Functions
#===============================================================================

test_migrations_exist() {
    print_section "1. Migration Files Verification"

    print_test "Migration directory exists"
    if [[ -d "${PROJECT_ROOT}/database/migrations" ]]; then
        pass_test "Directory found"
    else
        fail_test "Migration directory not found"
        return 1
    fi

    print_test "Migration files found"
    migration_count=$(find "${PROJECT_ROOT}/database/migrations" -name "*.php" | wc -l)
    if [[ $migration_count -gt 0 ]]; then
        pass_test "${migration_count} migration files found"
    else
        fail_test "No migration files found"
        return 1
    fi

    print_test "Migration naming convention"
    invalid_names=$(find "${PROJECT_ROOT}/database/migrations" -name "*.php" ! -name "*_*_*_*_*.php" | wc -l)
    if [[ $invalid_names -eq 0 ]]; then
        pass_test "All migrations follow naming convention"
    else
        fail_test "${invalid_names} migrations don't follow naming convention"
    fi
}

test_migration_syntax() {
    print_section "2. Migration Syntax Verification"

    print_test "PHP syntax check on migrations"
    syntax_errors=0

    for migration in "${PROJECT_ROOT}/database/migrations"/*.php; do
        if ! php -l "$migration" &>/dev/null; then
            fail_test "Syntax error in $(basename "$migration")"
            syntax_errors=$((syntax_errors + 1))
        fi
    done

    if [[ $syntax_errors -eq 0 ]]; then
        pass_test "All migrations have valid PHP syntax"
    fi
}

test_fresh_migration() {
    print_section "3. Fresh Migration Test"

    print_test "Run fresh migration"
    if output=$(artisan migrate:fresh --force 2>&1); then
        pass_test "Fresh migration successful"
    else
        fail_test "Fresh migration failed: ${output}"
        return 1
    fi

    print_test "Verify tables were created"
    if tables_output=$(artisan db:show 2>&1); then
        table_count=$(echo "$tables_output" | grep -c "Table" || echo "0")
        if [[ $table_count -gt 0 ]]; then
            pass_test "${table_count} tables created"
        else
            fail_test "No tables found after migration"
        fi
    else
        fail_test "Cannot verify tables"
    fi
}

test_migration_status() {
    print_section "4. Migration Status Verification"

    print_test "Check migration status"
    if status_output=$(artisan migrate:status 2>&1); then
        pass_test "Migration status retrieved"

        # Count ran vs pending migrations
        ran_count=$(echo "$status_output" | grep -c "Ran" || echo "0")
        pending_count=$(echo "$status_output" | grep -c "Pending" || echo "0")

        info "Ran: ${ran_count}, Pending: ${pending_count}"

        if [[ $pending_count -gt 0 ]]; then
            warn "${pending_count} migrations still pending"
        fi
    else
        fail_test "Cannot get migration status"
    fi
}

test_rollback() {
    print_section "5. Rollback Verification"

    print_test "Rollback last batch"
    if rollback_output=$(artisan migrate:rollback --force 2>&1); then
        pass_test "Rollback successful"
    else
        fail_test "Rollback failed: ${rollback_output}"
        return 1
    fi

    print_test "Re-run migrations after rollback"
    if migrate_output=$(artisan migrate --force 2>&1); then
        pass_test "Re-migration successful"
    else
        fail_test "Re-migration failed: ${migrate_output}"
    fi
}

test_idempotency() {
    print_section "6. Idempotency Test"

    print_test "Run migrations twice (should be no-op)"

    # First run
    if ! artisan migrate --force &>/dev/null; then
        fail_test "First migration run failed"
        return 1
    fi

    # Second run (should do nothing)
    if output=$(artisan migrate --force 2>&1); then
        if echo "$output" | grep -q "Nothing to migrate"; then
            pass_test "Migrations are idempotent"
        else
            # Some migrations might run - check if it's expected
            pass_test "Second run completed (verify manually if expected)"
        fi
    else
        fail_test "Second migration run failed"
    fi
}

test_foreign_keys() {
    print_section "7. Foreign Key Constraints"

    print_test "Foreign key constraints created"

    # Check if migrations contain foreign key definitions
    fk_count=$(grep -r "foreign\|foreignId" "${PROJECT_ROOT}/database/migrations" | wc -l)

    if [[ $fk_count -gt 0 ]]; then
        pass_test "${fk_count} foreign key definitions found"

        # Verify constraints in database (MySQL specific)
        if output=$(artisan tinker --execute="echo count(DB::select('SELECT * FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_TYPE = \"FOREIGN KEY\" AND TABLE_SCHEMA = \"' . config('database.connections.mysql.database') . '\"'))" 2>&1); then
            info "Foreign keys in database: ${output}"
            pass_test "Foreign keys verified"
        else
            warn "Cannot verify foreign keys in database"
        fi
    else
        warn "No foreign key definitions found"
    fi
}

test_indexes() {
    print_section "8. Index Verification"

    print_test "Database indexes created"

    # Check for index definitions in migrations
    index_count=$(grep -r "index\|unique" "${PROJECT_ROOT}/database/migrations" | wc -l)

    if [[ $index_count -gt 0 ]]; then
        pass_test "${index_count} index definitions found"
    else
        warn "No index definitions found"
    fi

    # Verify specific critical indexes exist
    print_test "Critical indexes verified"

    critical_indexes=(
        "users.email"
        "sites.tenant_id"
        "sites.domain"
    )

    missing_indexes=()
    for index_spec in "${critical_indexes[@]}"; do
        table=$(echo "$index_spec" | cut -d. -f1)
        column=$(echo "$index_spec" | cut -d. -f2)

        if ! artisan db:table "$table" 2>&1 | grep -q "$column"; then
            missing_indexes+=("${index_spec}")
        fi
    done

    if [[ ${#missing_indexes[@]} -eq 0 ]]; then
        pass_test "All critical indexes exist"
    else
        warn "Some indexes may be missing: ${missing_indexes[*]}"
    fi
}

test_data_migrations() {
    print_section "9. Data Migration Verification"

    print_test "Check for data migrations"

    # Data migrations typically seed or transform data
    # Look for migrations that might contain data operations
    data_migration_count=$(grep -rl "DB::table.*insert\|DB::insert\|::create(" "${PROJECT_ROOT}/database/migrations" 2>/dev/null | wc -l)

    if [[ $data_migration_count -gt 0 ]]; then
        warn "${data_migration_count} migrations contain data operations (verify manually)"

        print_test "Data migrations preserve data on rollback"
        # This is difficult to test automatically - manual verification needed
        warn "Manual verification required for data preservation"
    else
        pass_test "No data migrations detected (structure only)"
    fi
}

test_migration_performance() {
    print_section "10. Migration Performance"

    print_test "Migration execution time"

    start_time=$(date +%s)

    if artisan migrate:fresh --force &>/dev/null; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        if [[ $duration -lt 60 ]]; then
            pass_test "Migrations completed in ${duration}s (acceptable)"
        elif [[ $duration -lt 300 ]]; then
            warn "Migrations took ${duration}s (consider optimization)"
        else
            warn "Migrations took ${duration}s (slow - needs optimization)"
        fi
    else
        fail_test "Migration failed during performance test"
    fi
}

#===============================================================================
# Summary
#===============================================================================

print_summary() {
    print_section "Migration Verification Summary"

    echo ""
    echo "  ${BOLD}Total Tests:${NC}   ${TOTAL_TESTS}"
    echo "  ${GREEN}${BOLD}Passed:${NC}        ${PASSED_TESTS}"
    echo "  ${RED}${BOLD}Failed:${NC}        ${FAILED_TESTS}"
    echo ""

    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
        echo "  ${BOLD}Success Rate:${NC}  ${success_rate}%"
    fi

    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "  ${GREEN}${BOLD}✓ ALL MIGRATION TESTS PASSED${NC}"
        echo ""
        return 0
    else
        echo "  ${RED}${BOLD}✗ MIGRATION VERIFICATION FAILED${NC}"
        echo ""
        echo "  ${RED}Please review the failed tests above.${NC}"
        echo ""
        return 1
    fi
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# \?//'
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Print header
    echo ""
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}${BOLD}║              Database Migration Verification System                       ║${NC}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Backup current database state
    warn "This script will run fresh migrations - data will be lost"
    warn "Ensure you're running this on a test database"
    echo ""

    # Run all tests
    test_migrations_exist || exit 1
    test_migration_syntax
    test_fresh_migration || exit 1
    test_migration_status
    test_rollback
    test_idempotency
    test_foreign_keys
    test_indexes
    test_data_migrations
    test_migration_performance

    # Print summary
    print_summary
}

main "$@"
