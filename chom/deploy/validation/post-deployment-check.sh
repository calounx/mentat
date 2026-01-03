#!/bin/bash

###############################################################################
# CHOM Post-Deployment Validation Script
# Comprehensive validation after deployment completes
# Exit 0: Deployment successful, all systems operational
# Exit 1: Deployment issues detected, investigation required
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
APP_PATH="/var/www/chom/current"
JSON_OUTPUT=false
QUIET_MODE=false
RUN_SYNTHETIC_TESTS=true
FAILED_CHECKS=0
TOTAL_CHECKS=0
HTTP_TIMEOUT=10

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --no-synthetic)
            RUN_SYNTHETIC_TESTS=false
            shift
            ;;
        --help)
            echo "Usage: $0 [--json] [--quiet] [--no-synthetic]"
            echo "  --json          Output results in JSON format"
            echo "  --quiet         Suppress progress output"
            echo "  --no-synthetic  Skip synthetic transaction tests"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${GREEN}[✓]${NC} $1"
    fi
}

log_warning() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${YELLOW}[⚠]${NC} $1"
    fi
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

log_section() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}$1${NC}"
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

# Progress indicator
show_progress() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Results tracking
declare -A check_results
declare -A check_messages
declare -A check_durations

record_check() {
    local check_name="$1"
    local status="$2"
    local message="${3:-}"
    local duration="${4:-0}"

    ((TOTAL_CHECKS++))
    check_results["$check_name"]="$status"
    check_messages["$check_name"]="$message"
    check_durations["$check_name"]="$duration"

    if [[ "$status" == "FAIL" ]]; then
        ((FAILED_CHECKS++))
        log_error "$check_name: $message"
    elif [[ "$status" == "PASS" ]]; then
        log_success "$check_name"
    elif [[ "$status" == "WARN" ]]; then
        log_warning "$check_name: $message"
    fi
}

###############################################################################
# CHECK FUNCTIONS
###############################################################################

check_http_response() {
    log_section "HTTP Response Validation"

    local app_url
    app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        record_check "HTTP URL" "FAIL" "APP_URL not configured"
        return
    fi

    log_info "Testing: $app_url"

    # Test HTTP response
    local start_time=$(date +%s%N)
    local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m $HTTP_TIMEOUT "$app_url" 2>/dev/null || echo "000")
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))

    if [[ "$http_code" == "200" ]]; then
        record_check "HTTP 200 response" "PASS" "Response time: ${duration}ms" "$duration"
    elif [[ "$http_code" == "302" ]] || [[ "$http_code" == "301" ]]; then
        record_check "HTTP response" "PASS" "Redirect (${http_code})" "$duration"
    else
        record_check "HTTP response" "FAIL" "Got HTTP $http_code" "$duration"
    fi

    # Test HTTPS if configured
    if [[ "$app_url" == https://* ]]; then
        local ssl_check=$(curl -sSL -w "%{ssl_verify_result}" -o /dev/null "$app_url" 2>/dev/null || echo "2")
        if [[ "$ssl_check" == "0" ]]; then
            record_check "SSL certificate" "PASS"
        else
            record_check "SSL certificate" "FAIL" "SSL verification failed"
        fi
    fi

    # Check response headers
    local headers=$(curl -sSL -I -m $HTTP_TIMEOUT "$app_url" 2>/dev/null || echo "")

    if echo "$headers" | grep -qi "X-Frame-Options"; then
        record_check "Security header: X-Frame-Options" "PASS"
    else
        record_check "Security header: X-Frame-Options" "WARN" "Header not set"
    fi

    if echo "$headers" | grep -qi "X-Content-Type-Options"; then
        record_check "Security header: X-Content-Type-Options" "PASS"
    else
        record_check "Security header: X-Content-Type-Options" "WARN" "Header not set"
    fi
}

check_database_migrations() {
    log_section "Database Migrations"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Get migration status
    log_info "Checking migration status..."
    local migration_output
    migration_output=$(ssh "$server" "cd $APP_PATH && php artisan migrate:status 2>&1" || echo "FAILED")

    if [[ "$migration_output" == *"FAILED"* ]] || [[ "$migration_output" == *"error"* ]]; then
        record_check "Migration status" "FAIL" "Cannot check migrations"
        return
    fi

    # Check for pending migrations
    if echo "$migration_output" | grep -q "Pending"; then
        local pending_count=$(echo "$migration_output" | grep -c "Pending" || echo "0")
        record_check "Pending migrations" "FAIL" "$pending_count migrations not applied"
    else
        record_check "All migrations applied" "PASS"
    fi

    # Check for failed migrations
    if echo "$migration_output" | grep -qi "failed"; then
        record_check "Migration failures" "FAIL" "Some migrations failed"
    else
        record_check "No migration failures" "PASS"
    fi
}

check_queue_workers() {
    log_section "Queue Workers"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check if queue workers are running
    local worker_count
    worker_count=$(ssh "$server" "ps aux | grep '[q]ueue:work' | wc -l" || echo "0")

    if [[ "$worker_count" -gt 0 ]]; then
        record_check "Queue workers running" "PASS" "$worker_count workers active"
    else
        record_check "Queue workers" "WARN" "No queue workers running"
    fi

    # Check supervisor status if available
    if ssh "$server" "command -v supervisorctl &>/dev/null"; then
        local supervisor_status
        supervisor_status=$(ssh "$server" "sudo supervisorctl status 2>/dev/null | grep -i queue || echo 'none'" || echo "none")

        if [[ "$supervisor_status" != "none" ]]; then
            if echo "$supervisor_status" | grep -q "RUNNING"; then
                record_check "Supervisor queue workers" "PASS"
            else
                record_check "Supervisor queue workers" "FAIL" "Workers not running in supervisor"
            fi
        fi
    fi

    # Check for failed jobs
    local failed_jobs
    failed_jobs=$(ssh "$server" "cd $APP_PATH && php artisan queue:failed 2>/dev/null | grep -c 'ID' || echo '0'" || echo "0")

    if [[ "$failed_jobs" -eq 0 ]]; then
        record_check "Failed queue jobs" "PASS"
    else
        record_check "Failed queue jobs" "WARN" "$failed_jobs failed jobs in queue"
    fi
}

check_cache() {
    log_section "Cache System"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Test cache write
    local test_key="deployment_test_$(date +%s)"
    local test_value="test_value_123"

    ssh "$server" "cd $APP_PATH && php artisan cache:put '$test_key' '$test_value' 60" &>/dev/null

    # Test cache read
    local cached_value
    cached_value=$(ssh "$server" "cd $APP_PATH && php artisan cache:get '$test_key' 2>/dev/null" || echo "")

    if [[ "$cached_value" == "$test_value" ]]; then
        record_check "Cache write/read" "PASS"
    else
        record_check "Cache write/read" "FAIL" "Cache not functioning correctly"
    fi

    # Clean up test key
    ssh "$server" "cd $APP_PATH && php artisan cache:forget '$test_key'" &>/dev/null

    # Check cache driver
    local cache_driver
    cache_driver=$(ssh "$server" "grep '^CACHE_DRIVER=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ -n "$cache_driver" ]]; then
        log_info "Cache driver: $cache_driver"
        record_check "Cache driver configured" "PASS"
    fi
}

check_session() {
    log_section "Session Storage"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check session driver
    local session_driver
    session_driver=$(ssh "$server" "grep '^SESSION_DRIVER=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ -n "$session_driver" ]]; then
        log_info "Session driver: $session_driver"
        record_check "Session driver configured" "PASS"
    else
        record_check "Session driver" "WARN" "SESSION_DRIVER not set"
    fi

    # Check session storage directory if file-based
    if [[ "$session_driver" == "file" ]]; then
        if ssh "$server" "test -d $APP_PATH/storage/framework/sessions && test -w $APP_PATH/storage/framework/sessions" &>/dev/null; then
            record_check "Session storage writable" "PASS"
        else
            record_check "Session storage writable" "FAIL" "Session directory not writable"
        fi
    fi
}

check_health_endpoint() {
    log_section "Health Check Endpoint"

    local app_url
    app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        record_check "Health endpoint" "FAIL" "APP_URL not configured"
        return
    fi

    # Test health endpoint
    local health_url="${app_url}/health"
    local health_response=$(curl -sSL -m 5 "$health_url" 2>/dev/null || echo "FAILED")

    if [[ "$health_response" != "FAILED" ]]; then
        if echo "$health_response" | grep -qi "ok\|healthy\|success"; then
            record_check "Health endpoint" "PASS"
        else
            record_check "Health endpoint" "WARN" "Endpoint exists but response unclear"
        fi
    else
        record_check "Health endpoint" "WARN" "Health endpoint not available"
    fi
}

check_metrics_endpoint() {
    log_section "Metrics Endpoint"

    local app_url
    app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        return
    fi

    # Test metrics endpoint
    local metrics_url="${app_url}/metrics"
    local metrics_response=$(curl -sSL -m 5 "$metrics_url" 2>/dev/null || echo "FAILED")

    if [[ "$metrics_response" != "FAILED" ]]; then
        if echo "$metrics_response" | grep -q "# HELP\|# TYPE"; then
            record_check "Prometheus metrics" "PASS"
        else
            record_check "Metrics endpoint" "WARN" "Endpoint exists but not Prometheus format"
        fi
    else
        record_check "Metrics endpoint" "WARN" "Metrics endpoint not available"
    fi
}

check_application_logs() {
    log_section "Application Logs"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check for PHP errors in last 5 minutes
    local log_file="$APP_PATH/storage/logs/laravel.log"

    if ssh "$server" "test -f $log_file" &>/dev/null; then
        local error_count
        error_count=$(ssh "$server" "grep -c 'ERROR\|Exception' $log_file 2>/dev/null | tail -100" || echo "0")

        if [[ "$error_count" -eq 0 ]]; then
            record_check "PHP errors (recent)" "PASS"
        else
            # Get last error
            local last_error
            last_error=$(ssh "$server" "grep 'ERROR\|Exception' $log_file 2>/dev/null | tail -1" || echo "")
            record_check "PHP errors (recent)" "WARN" "$error_count errors found"
            if [[ -n "$last_error" && "$QUIET_MODE" == "false" ]]; then
                log_info "Last error: ${last_error:0:100}..."
            fi
        fi

        # Check log file size
        local log_size
        log_size=$(ssh "$server" "du -h $log_file 2>/dev/null | cut -f1" || echo "0")
        log_info "Log file size: $log_size"

        # Warn if log file is too large
        local log_size_mb
        log_size_mb=$(ssh "$server" "du -m $log_file 2>/dev/null | cut -f1" || echo "0")
        if [[ "$log_size_mb" -gt 100 ]]; then
            record_check "Log file size" "WARN" "Log file is ${log_size} (consider rotation)"
        fi
    else
        record_check "Application log" "WARN" "Log file not found (fresh install)"
    fi
}

check_nginx_logs() {
    log_section "Nginx Logs"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check for Nginx errors
    local nginx_error_log="/var/log/nginx/error.log"

    if ssh "$server" "sudo test -f $nginx_error_log" &>/dev/null; then
        local nginx_errors
        nginx_errors=$(ssh "$server" "sudo tail -100 $nginx_error_log 2>/dev/null | grep -c 'error\|crit\|alert\|emerg' || echo '0'" || echo "0")

        if [[ "$nginx_errors" -eq 0 ]]; then
            record_check "Nginx errors (recent)" "PASS"
        else
            record_check "Nginx errors (recent)" "WARN" "$nginx_errors errors in last 100 lines"
        fi
    fi

    # Check Nginx access log for 5xx errors
    local nginx_access_log="/var/log/nginx/access.log"

    if ssh "$server" "sudo test -f $nginx_access_log" &>/dev/null; then
        local server_errors
        server_errors=$(ssh "$server" "sudo tail -1000 $nginx_access_log 2>/dev/null | grep -c ' 5[0-9][0-9] ' || echo '0'" || echo "0")

        if [[ "$server_errors" -eq 0 ]]; then
            record_check "HTTP 5xx errors (recent)" "PASS"
        else
            record_check "HTTP 5xx errors (recent)" "WARN" "$server_errors 5xx responses in last 1000 requests"
        fi
    fi
}

check_scheduled_tasks() {
    log_section "Scheduled Tasks (Cron)"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check if Laravel scheduler is configured in crontab
    local cron_entry
    cron_entry=$(ssh "$server" "crontab -l 2>/dev/null | grep -i 'artisan schedule:run' || echo ''" || echo "")

    if [[ -n "$cron_entry" ]]; then
        record_check "Laravel scheduler cron" "PASS"
        log_info "Cron entry: $cron_entry"
    else
        record_check "Laravel scheduler cron" "WARN" "Scheduler not configured in crontab"
    fi

    # Check last schedule run
    local schedule_log="$APP_PATH/storage/logs/scheduler.log"

    if ssh "$server" "test -f $schedule_log" &>/dev/null; then
        local last_run
        last_run=$(ssh "$server" "tail -1 $schedule_log 2>/dev/null" || echo "")

        if [[ -n "$last_run" ]]; then
            log_info "Last scheduler run logged"
            record_check "Scheduler execution" "PASS"
        fi
    fi
}

check_storage_permissions() {
    log_section "Storage Permissions"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check storage directories are writable
    local storage_dirs=("storage/app" "storage/framework" "storage/logs" "bootstrap/cache")

    for dir in "${storage_dirs[@]}"; do
        if ssh "$server" "test -d $APP_PATH/$dir && test -w $APP_PATH/$dir" &>/dev/null; then
            record_check "Writable: $dir" "PASS"
        else
            record_check "Writable: $dir" "FAIL" "Directory not writable"
        fi
    done
}

check_environment_configuration() {
    log_section "Environment Configuration"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check APP_ENV
    local app_env
    app_env=$(ssh "$server" "grep '^APP_ENV=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ "$app_env" == "production" ]]; then
        record_check "APP_ENV=production" "PASS"
    else
        record_check "APP_ENV" "WARN" "Set to: $app_env (expected: production)"
    fi

    # Check APP_DEBUG
    local app_debug
    app_debug=$(ssh "$server" "grep '^APP_DEBUG=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ "$app_debug" == "false" ]]; then
        record_check "APP_DEBUG=false" "PASS"
    else
        record_check "APP_DEBUG" "FAIL" "Debug mode enabled in production!"
    fi

    # Check APP_KEY
    local app_key
    app_key=$(ssh "$server" "grep '^APP_KEY=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d "'")

    if [[ -n "$app_key" && "$app_key" != "base64:" ]]; then
        record_check "APP_KEY configured" "PASS"
    else
        record_check "APP_KEY" "FAIL" "Application key not set"
    fi
}

run_synthetic_tests() {
    if [[ "$RUN_SYNTHETIC_TESTS" == "false" ]]; then
        return
    fi

    log_section "Synthetic Transaction Tests"

    local app_url
    app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        log_warning "Cannot run synthetic tests: APP_URL not configured"
        return
    fi

    # Test 1: Homepage renders
    log_info "Test: Homepage load..."
    local homepage_start=$(date +%s%N)
    local homepage_response=$(curl -sSL -w "%{http_code}" -o /dev/null -m $HTTP_TIMEOUT "$app_url" 2>/dev/null || echo "000")
    local homepage_end=$(date +%s%N)
    local homepage_duration=$(( (homepage_end - homepage_start) / 1000000 ))

    if [[ "$homepage_response" == "200" ]] || [[ "$homepage_response" == "302" ]]; then
        record_check "Synthetic: Homepage" "PASS" "${homepage_duration}ms" "$homepage_duration"
    else
        record_check "Synthetic: Homepage" "FAIL" "HTTP $homepage_response"
    fi

    # Test 2: Login page loads
    log_info "Test: Login page load..."
    local login_url="${app_url}/login"
    local login_response=$(curl -sSL -w "%{http_code}" -o /dev/null -m $HTTP_TIMEOUT "$login_url" 2>/dev/null || echo "000")

    if [[ "$login_response" == "200" ]]; then
        record_check "Synthetic: Login page" "PASS"
    else
        record_check "Synthetic: Login page" "WARN" "HTTP $login_response"
    fi

    # Test 3: API health
    log_info "Test: API endpoints..."
    local api_url="${app_url}/api/health"
    local api_response=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "$api_url" 2>/dev/null || echo "000")

    if [[ "$api_response" == "200" ]]; then
        record_check "Synthetic: API health" "PASS"
    else
        record_check "Synthetic: API health" "WARN" "API health endpoint returned $api_response"
    fi

    # Test 4: Static assets load
    log_info "Test: Static assets..."
    local css_url="${app_url}/css/app.css"
    local css_response=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "$css_url" 2>/dev/null || echo "000")

    if [[ "$css_response" == "200" ]]; then
        record_check "Synthetic: CSS assets" "PASS"
    else
        record_check "Synthetic: CSS assets" "WARN" "CSS not loading (${css_response})"
    fi
}

check_services_running() {
    log_section "Service Status"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check Nginx
    if ssh "$server" "sudo systemctl is-active nginx &>/dev/null"; then
        record_check "Nginx service" "PASS"
    else
        record_check "Nginx service" "FAIL" "Nginx not running"
    fi

    # Check PHP-FPM
    local php_fpm_service=$(ssh "$server" "systemctl list-units --type=service --all | grep -o 'php[0-9.]*-fpm.service' | head -1" || echo "")

    if [[ -n "$php_fpm_service" ]]; then
        if ssh "$server" "sudo systemctl is-active $php_fpm_service &>/dev/null"; then
            record_check "PHP-FPM service" "PASS"
        else
            record_check "PHP-FPM service" "FAIL" "PHP-FPM not running"
        fi
    fi

    # Check PostgreSQL
    if ssh "$server" "sudo systemctl is-active postgresql &>/dev/null"; then
        record_check "PostgreSQL service" "PASS"
    else
        record_check "PostgreSQL service" "WARN" "PostgreSQL service not active (may be remote)"
    fi

    # Check Redis
    if ssh "$server" "sudo systemctl is-active redis &>/dev/null || sudo systemctl is-active redis-server &>/dev/null"; then
        record_check "Redis service" "PASS"
    else
        record_check "Redis service" "WARN" "Redis service not active (may be remote)"
    fi
}

###############################################################################
# OUTPUT FUNCTIONS
###############################################################################

output_json() {
    local status="success"
    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
        status="failure"
    fi

    echo "{"
    echo "  \"status\": \"$status\","
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"total_checks\": $TOTAL_CHECKS,"
    echo "  \"failed_checks\": $FAILED_CHECKS,"
    echo "  \"checks\": {"

    local first=true
    for check_name in "${!check_results[@]}"; do
        if [[ "$first" == "false" ]]; then
            echo ","
        fi
        first=false

        local status="${check_results[$check_name]}"
        local message="${check_messages[$check_name]}"
        local duration="${check_durations[$check_name]}"

        echo -n "    \"$check_name\": {"
        echo -n "\"status\": \"$status\""
        if [[ -n "$message" ]]; then
            echo -n ", \"message\": \"$message\""
        fi
        if [[ "$duration" != "0" ]]; then
            echo -n ", \"duration_ms\": $duration"
        fi
        echo -n "}"
    done

    echo ""
    echo "  }"
    echo "}"
}

output_summary() {
    echo ""
    log_section "Post-Deployment Validation Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All post-deployment checks passed!${NC}"
        echo -e "${GREEN}${BOLD}✓ Application is operational${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ Post-deployment validation detected issues!${NC}"
        echo ""
        echo -e "${YELLOW}Failed checks:${NC}"
        for check_name in "${!check_results[@]}"; do
            if [[ "${check_results[$check_name]}" == "FAIL" ]]; then
                echo -e "  ${RED}✗${NC} $check_name: ${check_messages[$check_name]}"
            fi
        done
        echo ""
        echo -e "${YELLOW}Warnings:${NC}"
        for check_name in "${!check_results[@]}"; do
            if [[ "${check_results[$check_name]}" == "WARN" ]]; then
                echo -e "  ${YELLOW}⚠${NC} $check_name: ${check_messages[$check_name]}"
            fi
        done
        return 1
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${BOLD}${BLUE}"
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║        CHOM Post-Deployment Validation                        ║"
        echo "║        Validating deployment success...                       ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi

    # Run all checks
    check_services_running
    check_http_response
    check_database_migrations
    check_queue_workers
    check_cache
    check_session
    check_health_endpoint
    check_metrics_endpoint
    check_application_logs
    check_nginx_logs
    check_scheduled_tasks
    check_storage_permissions
    check_environment_configuration
    run_synthetic_tests

    # Output results
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
    else
        output_summary
    fi

    # Exit with appropriate code
    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
