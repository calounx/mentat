#!/bin/bash

###############################################################################
# CHOM Smoke Test Suite
# Quick validation of critical application paths
# Target: Complete in under 60 seconds
# Exit 0: All critical paths functional
# Exit 1: Critical functionality broken
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
TIMEOUT=5
FAILED_TESTS=0
TOTAL_TESTS=0
START_TIME=$(date +%s)

# Logging
log_test() {
    local test_name="$1"
    local status="$2"
    local duration="${3:-0}"

    ((TOTAL_TESTS++))

    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}[✓]${NC} $test_name ${BLUE}(${duration}ms)${NC}"
    else
        echo -e "${RED}[✗]${NC} $test_name ${RED}FAILED${NC}"
        ((FAILED_TESTS++))
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

###############################################################################
# SMOKE TESTS
###############################################################################

test_homepage_loads() {
    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        log_test "Homepage loads" "FAIL"
        return
    fi

    local start=$(date +%s%N)
    local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m $TIMEOUT "$app_url" 2>/dev/null || echo "000")
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "302" ]]; then
        log_test "Homepage loads" "PASS" "$duration"
    else
        log_test "Homepage loads (HTTP $http_code)" "FAIL" "$duration"
    fi
}

test_login_page() {
    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        log_test "Login page" "FAIL"
        return
    fi

    local start=$(date +%s%N)
    local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m $TIMEOUT "${app_url}/login" 2>/dev/null || echo "000")
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$http_code" == "200" ]]; then
        log_test "Login page" "PASS" "$duration"
    else
        log_test "Login page" "FAIL" "$duration"
    fi
}

test_api_endpoint() {
    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        log_test "API endpoint" "FAIL"
        return
    fi

    local start=$(date +%s%N)
    local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m $TIMEOUT "${app_url}/api/health" 2>/dev/null || echo "000")
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$http_code" == "200" ]]; then
        log_test "API endpoint" "PASS" "$duration"
    else
        log_test "API endpoint" "FAIL" "$duration"
    fi
}

test_database_query() {
    local result=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php artisan tinker --execute='echo \"OK\";' 2>/dev/null" || echo "FAIL")

    local start=$(date +%s%N)
    local query_result=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php -r \"
        require 'vendor/autoload.php';
        \\\$app = require_once 'bootstrap/app.php';
        \\\$app->make('Illuminate\\\\Contracts\\\\Console\\\\Kernel')->bootstrap();
        try {
            \\\$result = DB::select('SELECT 1 as test');
            echo 'OK';
        } catch (Exception \\\$e) {
            echo 'FAIL';
        }
    \" 2>/dev/null" || echo "FAIL")
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$query_result" == "OK" ]]; then
        log_test "Database query" "PASS" "$duration"
    else
        log_test "Database query" "FAIL" "$duration"
    fi
}

test_cache_operations() {
    local test_key="smoke_test_$(date +%s)"
    local test_value="test_$(date +%s%N)"

    local start=$(date +%s%N)

    # Write to cache
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php artisan cache:put '$test_key' '$test_value' 60 2>/dev/null" || {
        log_test "Cache write/read" "FAIL"
        return
    }

    # Read from cache
    local cached=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php artisan cache:get '$test_key' 2>/dev/null" || echo "")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    # Cleanup
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan cache:forget '$test_key' 2>/dev/null" &

    if [[ "$cached" == "$test_value" ]]; then
        log_test "Cache write/read" "PASS" "$duration"
    else
        log_test "Cache write/read" "FAIL" "$duration"
    fi
}

test_queue_connection() {
    local start=$(date +%s%N)

    # Check queue connection
    local queue_result=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php -r \"
        require 'vendor/autoload.php';
        \\\$app = require_once 'bootstrap/app.php';
        \\\$app->make('Illuminate\\\\Contracts\\\\Console\\\\Kernel')->bootstrap();
        try {
            Queue::size();
            echo 'OK';
        } catch (Exception \\\$e) {
            echo 'FAIL';
        }
    \" 2>/dev/null" || echo "FAIL")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$queue_result" == "OK" ]]; then
        log_test "Queue connection" "PASS" "$duration"
    else
        log_test "Queue connection" "FAIL" "$duration"
    fi
}

test_file_storage() {
    local test_file="storage/app/smoke_test_$(date +%s).txt"
    local test_content="smoke test content"

    local start=$(date +%s%N)

    # Write file
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && echo '$test_content' > $test_file 2>/dev/null" || {
        log_test "File write/read" "FAIL"
        return
    }

    # Read file
    local file_content=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && cat $test_file 2>/dev/null" || echo "")

    # Delete file
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && rm -f $test_file 2>/dev/null" &

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$file_content" == "$test_content" ]]; then
        log_test "File write/read" "PASS" "$duration"
    else
        log_test "File write/read" "FAIL" "$duration"
    fi
}

test_artisan_commands() {
    local start=$(date +%s%N)

    local artisan_result=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php artisan list 2>/dev/null | head -1" || echo "")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ -n "$artisan_result" ]]; then
        log_test "Artisan commands" "PASS" "$duration"
    else
        log_test "Artisan commands" "FAIL" "$duration"
    fi
}

test_env_configuration() {
    local start=$(date +%s%N)

    local app_key=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_KEY=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" || echo "")
    local app_env=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_ENV=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" || echo "")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ -n "$app_key" && -n "$app_env" ]]; then
        log_test "Environment config" "PASS" "$duration"
    else
        log_test "Environment config" "FAIL" "$duration"
    fi
}

test_composer_autoload() {
    local start=$(date +%s%N)

    local autoload_result=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && timeout $TIMEOUT php -r \"require 'vendor/autoload.php'; echo 'OK';\" 2>/dev/null" || echo "FAIL")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$autoload_result" == "OK" ]]; then
        log_test "Composer autoload" "PASS" "$duration"
    else
        log_test "Composer autoload" "FAIL" "$duration"
    fi
}

test_routes_cached() {
    local start=$(date +%s%N)

    local routes_cached=$(ssh "$DEPLOY_USER@$APP_SERVER" "test -f $APP_PATH/bootstrap/cache/routes-v7.php && echo 'YES' || echo 'NO'" || echo "NO")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$routes_cached" == "YES" ]]; then
        log_test "Routes cached" "PASS" "$duration"
    else
        log_test "Routes cached" "FAIL" "$duration"
    fi
}

test_config_cached() {
    local start=$(date +%s%N)

    local config_cached=$(ssh "$DEPLOY_USER@$APP_SERVER" "test -f $APP_PATH/bootstrap/cache/config.php && echo 'YES' || echo 'NO'" || echo "NO")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$config_cached" == "YES" ]]; then
        log_test "Config cached" "PASS" "$duration"
    else
        log_test "Config cached" "FAIL" "$duration"
    fi
}

test_logs_writable() {
    local start=$(date +%s%N)

    local log_writable=$(ssh "$DEPLOY_USER@$APP_SERVER" "test -w $APP_PATH/storage/logs && echo 'YES' || echo 'NO'" || echo "NO")

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))

    if [[ "$log_writable" == "YES" ]]; then
        log_test "Logs writable" "PASS" "$duration"
    else
        log_test "Logs writable" "FAIL" "$duration"
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║               CHOM Smoke Test Suite                           ║"
    echo "║               Target: <60 seconds                             ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    log_info "Running critical path smoke tests..."
    echo ""

    # Run all smoke tests
    test_homepage_loads
    test_login_page
    test_api_endpoint
    test_database_query
    test_cache_operations
    test_queue_connection
    test_file_storage
    test_artisan_commands
    test_env_configuration
    test_composer_autoload
    test_routes_cached
    test_config_cached
    test_logs_writable

    # Calculate total time
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))

    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Smoke Test Results${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local passed=$((TOTAL_TESTS - FAILED_TESTS))

    echo -e "Total tests: ${BOLD}$TOTAL_TESTS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_TESTS${NC}"
    echo -e "Duration: ${BLUE}${BOLD}${total_time}s${NC}"

    if [[ "$total_time" -gt 60 ]]; then
        echo -e "Performance: ${YELLOW}⚠ Exceeded 60s target${NC}"
    else
        echo -e "Performance: ${GREEN}✓ Within 60s target${NC}"
    fi

    echo ""

    if [[ "$FAILED_TESTS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All smoke tests passed!${NC}"
        echo -e "${GREEN}${BOLD}✓ Critical functionality operational${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ Smoke tests failed!${NC}"
        echo -e "${RED}${BOLD}✗ Critical functionality broken${NC}"
        exit 1
    fi
}

main "$@"
