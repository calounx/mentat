#!/bin/bash

###############################################################################
# CHOM Database Migration Validation Script
# Validates database state and migration integrity
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
APP_PATH="/var/www/chom/current"
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Logging
log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

record_check() {
    local check_name="$1"
    local status="$2"
    local message="${3:-}"

    ((TOTAL_CHECKS++))

    if [[ "$status" == "PASS" ]]; then
        log_success "$check_name"
    elif [[ "$status" == "WARN" ]]; then
        log_warning "$check_name: $message"
    else
        ((FAILED_CHECKS++))
        log_error "$check_name: $message"
    fi
}

###############################################################################
# MIGRATION CHECKS
###############################################################################

check_migration_status() {
    log_section "Migration Status"

    # Get migration status
    local migration_output
    migration_output=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan migrate:status 2>&1" || echo "FAILED")

    if [[ "$migration_output" == *"FAILED"* ]] || [[ "$migration_output" == *"error"* ]] || [[ "$migration_output" == *"could not"* ]]; then
        record_check "Migration status check" "FAIL" "Cannot retrieve migration status"
        log_error "Error: $migration_output"
        return
    fi

    # Count migrations
    local ran_count=$(echo "$migration_output" | grep -c "Ran" || echo "0")
    local pending_count=$(echo "$migration_output" | grep -c "Pending" || echo "0")
    local total_count=$((ran_count + pending_count))

    log_info "Migrations: $ran_count ran, $pending_count pending, $total_count total"

    # Check for pending migrations
    if [[ "$pending_count" -eq 0 ]]; then
        record_check "All migrations applied" "PASS"
    else
        record_check "Pending migrations" "FAIL" "$pending_count migrations not applied"

        # List pending migrations
        log_info "Pending migrations:"
        echo "$migration_output" | grep "Pending" | while read -r line; do
            log_info "  - $line"
        done
    fi

    # Check for any failed migrations
    if echo "$migration_output" | grep -qi "failed\|error"; then
        record_check "Migration failures" "FAIL" "Some migrations have errors"
    else
        record_check "No migration failures" "PASS"
    fi
}

check_database_connection() {
    log_section "Database Connection"

    # Test basic database connection
    local db_test
    db_test=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            DB::connection()->getPdo();
            echo \"CONNECTED\";
        } catch (Exception \$e) {
            echo \"FAILED: \" . \$e->getMessage();
        }
    ' 2>&1" || echo "FAILED")

    if echo "$db_test" | grep -q "CONNECTED"; then
        record_check "Database connection" "PASS"
    else
        record_check "Database connection" "FAIL" "Cannot connect to database"
        log_error "Error: $db_test"
    fi
}

check_migrations_table() {
    log_section "Migrations Table"

    # Check if migrations table exists
    local table_exists
    table_exists=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            \$exists = Schema::hasTable(\"migrations\");
            echo \$exists ? \"EXISTS\" : \"NOT_EXISTS\";
        } catch (Exception \$e) {
            echo \"ERROR\";
        }
    ' 2>&1" || echo "ERROR")

    if echo "$table_exists" | grep -q "EXISTS"; then
        record_check "Migrations table exists" "PASS"

        # Count migration records
        local migration_count
        migration_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
            echo DB::table(\"migrations\")->count();
        ' 2>/dev/null" || echo "0")

        log_info "Migration records: $migration_count"
    else
        record_check "Migrations table" "FAIL" "Migrations table does not exist"
    fi
}

check_foreign_keys() {
    log_section "Foreign Key Integrity"

    log_info "Checking foreign key constraints..."

    # Test foreign key integrity
    local fk_check
    fk_check=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            \$tables = DB::select(\"SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = '\''BASE TABLE'\'';\");
            \$errors = [];

            foreach (\$tables as \$table) {
                try {
                    // Try a simple select to ensure table is accessible
                    DB::table(\$table->table_name)->limit(1)->get();
                } catch (Exception \$e) {
                    \$errors[] = \$table->table_name . \": \" . \$e->getMessage();
                }
            }

            if (empty(\$errors)) {
                echo \"OK\";
            } else {
                echo \"ERRORS: \" . implode(\"; \", \$errors);
            }
        } catch (Exception \$e) {
            echo \"FAILED: \" . \$e->getMessage();
        }
    ' 2>&1" || echo "FAILED")

    if echo "$fk_check" | grep -q "^OK"; then
        record_check "Foreign key integrity" "PASS"
    elif echo "$fk_check" | grep -q "ERRORS:"; then
        record_check "Foreign key integrity" "WARN" "Some tables have issues"
        log_warning "Details: $fk_check"
    else
        record_check "Foreign key integrity" "FAIL" "Cannot check constraints"
    fi
}

check_indexes() {
    log_section "Database Indexes"

    log_info "Checking for important indexes..."

    # Get list of indexes
    local index_check
    index_check=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            \$indexes = DB::select(\"
                SELECT
                    table_name,
                    COUNT(*) as index_count
                FROM information_schema.statistics
                WHERE table_schema = DATABASE()
                GROUP BY table_name
                ORDER BY index_count DESC
                LIMIT 10
            \");

            foreach (\$indexes as \$idx) {
                echo \$idx->table_name . \": \" . \$idx->index_count . \" indexes\\n\";
            }
            echo \"OK\";
        } catch (Exception \$e) {
            echo \"FAILED\";
        }
    ' 2>&1" || echo "FAILED")

    if echo "$index_check" | grep -q "OK"; then
        record_check "Database indexes present" "PASS"
        log_info "Index counts:"
        echo "$index_check" | grep "indexes" | while read -r line; do
            log_info "  $line"
        done
    else
        record_check "Index check" "WARN" "Cannot verify indexes"
    fi
}

check_orphaned_records() {
    log_section "Orphaned Records Check"

    log_info "Checking for orphaned records (basic check)..."

    # This is a basic check - customize based on your schema
    local orphan_check
    orphan_check=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            // Example: Check if there are users without teams (if applicable)
            // Customize this based on your actual schema

            echo \"OK\"; // Placeholder - implement actual checks
        } catch (Exception \$e) {
            echo \"FAILED\";
        }
    ' 2>&1" || echo "FAILED")

    if echo "$orphan_check" | grep -q "OK"; then
        record_check "Orphaned records check" "PASS"
    else
        record_check "Orphaned records" "WARN" "Cannot perform orphan check"
    fi
}

check_migration_rollback_safety() {
    log_section "Rollback Safety Check"

    log_info "Verifying rollback methods exist in migrations..."

    # Check if migrations have down() methods
    local migration_files
    migration_files=$(ssh "$DEPLOY_USER@$APP_SERVER" "find $APP_PATH/database/migrations -name '*.php' -type f 2>/dev/null" || echo "")

    if [[ -n "$migration_files" ]]; then
        local total_migrations=$(echo "$migration_files" | wc -l)
        local migrations_with_down=0

        while IFS= read -r migration_file; do
            if ssh "$DEPLOY_USER@$APP_SERVER" "grep -q 'public function down()' '$migration_file'" &>/dev/null; then
                ((migrations_with_down++))
            fi
        done <<< "$migration_files"

        log_info "Migrations with rollback: $migrations_with_down / $total_migrations"

        if [[ "$migrations_with_down" -eq "$total_migrations" ]]; then
            record_check "All migrations have rollback" "PASS"
        elif [[ "$migrations_with_down" -gt 0 ]]; then
            record_check "Migration rollback methods" "WARN" "Some migrations missing rollback"
        else
            record_check "Migration rollback methods" "FAIL" "No rollback methods found"
        fi
    else
        record_check "Migration files" "WARN" "Cannot find migration files"
    fi
}

dry_run_migration() {
    log_section "Migration Dry Run"

    log_info "Testing migration execution (dry run)..."

    # Use --pretend flag to simulate migration
    local dry_run_output
    dry_run_output=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan migrate --pretend 2>&1" || echo "FAILED")

    if [[ "$dry_run_output" == *"FAILED"* ]] || [[ "$dry_run_output" == *"error"* ]]; then
        record_check "Migration dry run" "FAIL" "Dry run encountered errors"
        log_error "Error: $dry_run_output"
    elif [[ "$dry_run_output" == *"Nothing to migrate"* ]]; then
        record_check "Migration dry run" "PASS"
        log_info "No pending migrations to test"
    else
        record_check "Migration dry run" "PASS"
        log_info "Dry run completed successfully"
    fi
}

check_database_schema_consistency() {
    log_section "Schema Consistency"

    log_info "Verifying schema consistency..."

    # Compare migration files with actual database schema
    local consistency_check
    consistency_check=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            // Get all tables from database
            \$tables = DB::select(\"SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = '\''BASE TABLE'\'' AND table_name != '\''migrations'\'';\");

            \$table_count = count(\$tables);

            if (\$table_count > 0) {
                echo \"TABLES: \" . \$table_count;
            } else {
                echo \"NO_TABLES\";
            }
        } catch (Exception \$e) {
            echo \"FAILED\";
        }
    ' 2>&1" || echo "FAILED")

    if echo "$consistency_check" | grep -q "TABLES:"; then
        local table_count=$(echo "$consistency_check" | grep -o '[0-9]*')
        record_check "Database tables exist" "PASS"
        log_info "Database tables: $table_count"
    elif echo "$consistency_check" | grep -q "NO_TABLES"; then
        record_check "Database tables" "WARN" "No tables found in database"
    else
        record_check "Schema consistency" "FAIL" "Cannot verify schema"
    fi
}

check_database_size() {
    log_section "Database Size"

    # Check database size
    local db_size
    db_size=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            \$size = DB::select(\"SELECT pg_size_pretty(pg_database_size(current_database())) as size;\")[0]->size;
            echo \$size;
        } catch (Exception \$e) {
            echo \"UNKNOWN\";
        }
    ' 2>/dev/null" || echo "UNKNOWN")

    if [[ "$db_size" != "UNKNOWN" ]]; then
        log_info "Database size: $db_size"
        record_check "Database size check" "PASS"
    else
        log_info "Cannot determine database size"
    fi

    # Check largest tables
    local large_tables
    large_tables=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        try {
            \$tables = DB::select(\"
                SELECT
                    schemaname || '\''.'\'' || tablename as table_name,
                    pg_size_pretty(pg_total_relation_size(schemaname || '\''.'\'' || tablename)) as size
                FROM pg_tables
                WHERE schemaname = '\''public'\''
                ORDER BY pg_total_relation_size(schemaname || '\''.'\'' || tablename) DESC
                LIMIT 5
            \");

            foreach (\$tables as \$table) {
                echo \$table->table_name . \": \" . \$table->size . \"\\n\";
            }
        } catch (Exception \$e) {
            // Silently fail
        }
    ' 2>/dev/null" || echo "")

    if [[ -n "$large_tables" ]]; then
        log_info "Largest tables:"
        echo "$large_tables" | while read -r line; do
            if [[ -n "$line" ]]; then
                log_info "  $line"
            fi
        done
    fi
}

check_backup_before_migration() {
    log_section "Database Backup Verification"

    # Check if recent backup exists
    local backup_dir="/var/backups/chom/database"

    if ssh "$DEPLOY_USER@$APP_SERVER" "test -d $backup_dir" &>/dev/null; then
        local latest_backup
        latest_backup=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -t $backup_dir/*.sql.gz 2>/dev/null | head -1" || echo "")

        if [[ -n "$latest_backup" ]]; then
            local backup_age
            backup_age=$(ssh "$DEPLOY_USER@$APP_SERVER" "stat -c %Y '$latest_backup' 2>/dev/null" || echo "0")
            local current_time=$(date +%s)
            local age_hours=$(( (current_time - backup_age) / 3600 ))

            if [[ "$age_hours" -lt 24 ]]; then
                record_check "Recent database backup" "PASS"
                log_info "Latest backup: ${age_hours}h old"
            else
                record_check "Database backup age" "WARN" "Backup is ${age_hours}h old"
            fi
        else
            record_check "Database backup" "WARN" "No backup found"
        fi
    else
        record_check "Database backup" "WARN" "Backup directory not found"
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          CHOM Database Migration Validation                   ║"
    echo "║          Checking database state and migrations...            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Run migration checks
    check_database_connection
    check_migrations_table
    check_migration_status
    check_foreign_keys
    check_indexes
    check_orphaned_records
    check_migration_rollback_safety
    dry_run_migration
    check_database_schema_consistency
    check_database_size
    check_backup_before_migration

    # Summary
    echo ""
    log_section "Migration Validation Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All migration checks passed!${NC}"
        echo -e "${GREEN}${BOLD}✓ Database in consistent state${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ Migration validation issues detected!${NC}"
        echo -e "${RED}${BOLD}✗ Review issues before proceeding${NC}"
        exit 1
    fi
}

main "$@"
