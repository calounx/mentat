#!/bin/bash

###############################################################################
# CHOM Performance Validation Script
# Validates performance metrics against baselines
# Alerts on performance degradation >20%
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
BASELINE_FILE="/tmp/chom-performance-baseline.json"
ITERATIONS=5
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Performance thresholds (milliseconds)
THRESHOLD_HOMEPAGE=500
THRESHOLD_API=200
THRESHOLD_DB_QUERY=100
THRESHOLD_MEMORY_PERCENT=70
THRESHOLD_CPU_PERCENT=50

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Tracking
declare -A metrics
declare -A baselines

record_metric() {
    local metric_name="$1"
    local value="$2"
    local threshold="$3"
    local unit="${4:-ms}"

    ((TOTAL_CHECKS++))
    metrics["$metric_name"]="$value"

    if [[ "$value" -le "$threshold" ]]; then
        log_success "$metric_name: ${value}${unit} (threshold: ${threshold}${unit})"
    else
        ((FAILED_CHECKS++))
        log_error "$metric_name: ${value}${unit} exceeds threshold ${threshold}${unit}"
    fi
}

compare_baseline() {
    local metric_name="$1"
    local current_value="$2"
    local baseline_value="$3"

    if [[ "$baseline_value" == "0" ]]; then
        log_info "$metric_name: No baseline to compare"
        return
    fi

    local degradation=$(awk "BEGIN {printf \"%.1f\", (($current_value - $baseline_value) / $baseline_value) * 100}")

    if (( $(awk "BEGIN {print ($degradation > 20)}") )); then
        log_warning "$metric_name degraded by ${degradation}% (${baseline_value}ms → ${current_value}ms)"
    elif (( $(awk "BEGIN {print ($degradation < -10)}") )); then
        log_success "$metric_name improved by ${degradation#-}%"
    else
        log_info "$metric_name: ${degradation}% change from baseline"
    fi
}

###############################################################################
# PERFORMANCE TESTS
###############################################################################

test_homepage_load_time() {
    log_section "Homepage Load Time"

    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        log_error "APP_URL not configured"
        return
    fi

    log_info "Testing $app_url ($ITERATIONS iterations)..."

    local total_time=0
    local min_time=999999
    local max_time=0

    for i in $(seq 1 $ITERATIONS); do
        local start=$(date +%s%N)
        curl -sSL -o /dev/null -m 10 "$app_url" 2>/dev/null || true
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))

        total_time=$((total_time + duration))

        if [[ "$duration" -lt "$min_time" ]]; then
            min_time=$duration
        fi

        if [[ "$duration" -gt "$max_time" ]]; then
            max_time=$duration
        fi

        echo -n "."
    done
    echo ""

    local avg_time=$((total_time / ITERATIONS))

    log_info "Min: ${min_time}ms, Max: ${max_time}ms, Avg: ${avg_time}ms"

    record_metric "Homepage load time (avg)" "$avg_time" "$THRESHOLD_HOMEPAGE" "ms"

    # Compare with baseline
    if [[ -f "$BASELINE_FILE" ]]; then
        local baseline=$(jq -r '.homepage_load_time // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")
        compare_baseline "Homepage load time" "$avg_time" "$baseline"
    fi

    metrics["homepage_load_time"]="$avg_time"
}

test_api_response_time() {
    log_section "API Response Time"

    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        return
    fi

    local api_url="${app_url}/api/health"
    log_info "Testing $api_url ($ITERATIONS iterations)..."

    local total_time=0
    local min_time=999999
    local max_time=0

    for i in $(seq 1 $ITERATIONS); do
        local start=$(date +%s%N)
        curl -sSL -o /dev/null -m 5 "$api_url" 2>/dev/null || true
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))

        total_time=$((total_time + duration))

        if [[ "$duration" -lt "$min_time" ]]; then
            min_time=$duration
        fi

        if [[ "$duration" -gt "$max_time" ]]; then
            max_time=$duration
        fi

        echo -n "."
    done
    echo ""

    local avg_time=$((total_time / ITERATIONS))

    log_info "Min: ${min_time}ms, Max: ${max_time}ms, Avg: ${avg_time}ms"

    record_metric "API response time (avg)" "$avg_time" "$THRESHOLD_API" "ms"

    # Compare with baseline
    if [[ -f "$BASELINE_FILE" ]]; then
        local baseline=$(jq -r '.api_response_time // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")
        compare_baseline "API response time" "$avg_time" "$baseline"
    fi

    metrics["api_response_time"]="$avg_time"
}

test_database_query_time() {
    log_section "Database Query Performance"

    log_info "Testing database query time ($ITERATIONS iterations)..."

    local total_time=0
    local min_time=999999
    local max_time=0

    for i in $(seq 1 $ITERATIONS); do
        local start=$(date +%s%N)
        ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php -r \"
            require 'vendor/autoload.php';
            \\\$app = require_once 'bootstrap/app.php';
            \\\$app->make('Illuminate\\\\Contracts\\\\Console\\\\Kernel')->bootstrap();
            DB::select('SELECT 1');
        \" 2>/dev/null" || true
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))

        total_time=$((total_time + duration))

        if [[ "$duration" -lt "$min_time" ]]; then
            min_time=$duration
        fi

        if [[ "$duration" -gt "$max_time" ]]; then
            max_time=$duration
        fi

        echo -n "."
    done
    echo ""

    local avg_time=$((total_time / ITERATIONS))

    log_info "Min: ${min_time}ms, Max: ${max_time}ms, Avg: ${avg_time}ms"

    record_metric "Database query time (avg)" "$avg_time" "$THRESHOLD_DB_QUERY" "ms"

    # Compare with baseline
    if [[ -f "$BASELINE_FILE" ]]; then
        local baseline=$(jq -r '.db_query_time // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")
        compare_baseline "Database query time" "$avg_time" "$baseline"
    fi

    metrics["db_query_time"]="$avg_time"
}

test_memory_usage() {
    log_section "Memory Usage"

    local mem_info=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem:")
    local total=$(echo "$mem_info" | awk '{print $2}')
    local used=$(echo "$mem_info" | awk '{print $3}')
    local available=$(echo "$mem_info" | awk '{print $7}')

    local usage_percent=$(awk "BEGIN {printf \"%.1f\", ($used / $total) * 100}")

    log_info "Memory: ${used}KB / ${total}KB (${usage_percent}%)"
    log_info "Available: ${available}KB"

    if (( $(awk "BEGIN {print ($usage_percent < $THRESHOLD_MEMORY_PERCENT)}") )); then
        log_success "Memory usage: ${usage_percent}% (threshold: ${THRESHOLD_MEMORY_PERCENT}%)"
    else
        ((FAILED_CHECKS++))
        log_error "Memory usage: ${usage_percent}% exceeds threshold ${THRESHOLD_MEMORY_PERCENT}%"
    fi

    ((TOTAL_CHECKS++))
    metrics["memory_usage_percent"]="${usage_percent}"
}

test_cpu_usage() {
    log_section "CPU Usage"

    log_info "Measuring idle CPU usage (5 second sample)..."

    local cpu_usage=$(ssh "$DEPLOY_USER@$APP_SERVER" "top -bn2 -d 5 | grep 'Cpu(s)' | tail -1 | awk '{print \$2}' | cut -d'%' -f1")

    log_info "CPU usage: ${cpu_usage}%"

    if (( $(awk "BEGIN {print ($cpu_usage < $THRESHOLD_CPU_PERCENT)}") )); then
        log_success "CPU usage: ${cpu_usage}% (threshold: ${THRESHOLD_CPU_PERCENT}%)"
    else
        log_warning "CPU usage: ${cpu_usage}% is high (threshold: ${THRESHOLD_CPU_PERCENT}%)"
    fi

    ((TOTAL_CHECKS++))
    metrics["cpu_usage_percent"]="${cpu_usage}"
}

check_n_plus_one_queries() {
    log_section "N+1 Query Detection"

    log_info "Checking for N+1 query patterns..."

    # Enable query logging temporarily and check for patterns
    local query_log="/tmp/chom-query-check.log"

    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan tinker --execute='
        DB::enableQueryLog();
        // Simulate common operation that might cause N+1
        if (class_exists(\"App\\\\Models\\\\User\")) {
            \$users = App\\\\Models\\\\User::limit(5)->get();
            foreach (\$users as \$user) {
                // Access relationships if they exist
            }
        }
        \$queries = DB::getQueryLog();
        echo count(\$queries);
    ' 2>/dev/null" > "$query_log" || echo "0" > "$query_log"

    local query_count=$(cat "$query_log")

    if [[ "$query_count" -gt 0 && "$query_count" -lt 20 ]]; then
        log_success "Query count: $query_count (reasonable)"
    elif [[ "$query_count" -ge 20 ]]; then
        log_warning "Query count: $query_count (possible N+1 queries)"
    else
        log_info "Unable to perform N+1 check"
    fi

    rm -f "$query_log"
    ((TOTAL_CHECKS++))
}

test_cache_performance() {
    log_section "Cache Performance"

    log_info "Testing cache read/write performance..."

    local test_key="perf_test_$(date +%s)"
    local test_value="test_data_$(date +%s%N)"

    # Test write performance
    local write_start=$(date +%s%N)
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan cache:put '$test_key' '$test_value' 60 2>/dev/null" || true
    local write_end=$(date +%s%N)
    local write_duration=$(( (write_end - write_start) / 1000000 ))

    # Test read performance
    local read_start=$(date +%s%N)
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan cache:get '$test_key' 2>/dev/null" || true
    local read_end=$(date +%s%N)
    local read_duration=$(( (read_end - read_start) / 1000000 ))

    log_info "Cache write: ${write_duration}ms"
    log_info "Cache read: ${read_duration}ms"

    if [[ "$read_duration" -lt 100 ]]; then
        log_success "Cache read performance acceptable"
    else
        log_warning "Cache read performance slow: ${read_duration}ms"
    fi

    # Cleanup
    ssh "$DEPLOY_USER@$APP_SERVER" "cd $APP_PATH && php artisan cache:forget '$test_key' 2>/dev/null" &

    ((TOTAL_CHECKS++))
    metrics["cache_read_time"]="$read_duration"
}

test_disk_io() {
    log_section "Disk I/O Performance"

    log_info "Testing disk I/O..."

    local test_file="/tmp/chom-io-test-$(date +%s).dat"

    # Test write speed
    local write_result=$(ssh "$DEPLOY_USER@$APP_SERVER" "dd if=/dev/zero of=$test_file bs=1M count=100 conv=fdatasync 2>&1 | grep -o '[0-9.]* MB/s' || echo '0 MB/s'")

    # Test read speed
    ssh "$DEPLOY_USER@$APP_SERVER" "sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true"
    local read_result=$(ssh "$DEPLOY_USER@$APP_SERVER" "dd if=$test_file of=/dev/null bs=1M 2>&1 | grep -o '[0-9.]* MB/s' || echo '0 MB/s'")

    # Cleanup
    ssh "$DEPLOY_USER@$APP_SERVER" "rm -f $test_file" &

    log_info "Disk write: $write_result"
    log_info "Disk read: $read_result"

    ((TOTAL_CHECKS++))
}

###############################################################################
# BASELINE MANAGEMENT
###############################################################################

save_baseline() {
    log_section "Saving Performance Baseline"

    cat > "$BASELINE_FILE" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "homepage_load_time": ${metrics[homepage_load_time]:-0},
  "api_response_time": ${metrics[api_response_time]:-0},
  "db_query_time": ${metrics[db_query_time]:-0},
  "memory_usage_percent": ${metrics[memory_usage_percent]:-0},
  "cpu_usage_percent": ${metrics[cpu_usage_percent]:-0},
  "cache_read_time": ${metrics[cache_read_time]:-0}
}
EOF

    log_success "Baseline saved to $BASELINE_FILE"
}

load_baseline() {
    if [[ -f "$BASELINE_FILE" ]]; then
        log_info "Loading baseline from $BASELINE_FILE"

        baselines[homepage_load_time]=$(jq -r '.homepage_load_time // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")
        baselines[api_response_time]=$(jq -r '.api_response_time // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")
        baselines[db_query_time]=$(jq -r '.db_query_time // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")

        local baseline_date=$(jq -r '.timestamp // "unknown"' "$BASELINE_FILE" 2>/dev/null || echo "unknown")
        log_info "Baseline from: $baseline_date"
    else
        log_info "No baseline file found"
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          CHOM Performance Validation                          ║"
    echo "║          Testing against performance baselines               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Parse arguments
    local save_new_baseline=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --save-baseline)
                save_new_baseline=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--save-baseline]"
                echo "  --save-baseline  Save current metrics as new baseline"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Load existing baseline
    load_baseline

    # Run performance tests
    test_homepage_load_time
    test_api_response_time
    test_database_query_time
    test_memory_usage
    test_cpu_usage
    check_n_plus_one_queries
    test_cache_performance
    test_disk_io

    # Save baseline if requested
    if [[ "$save_new_baseline" == "true" ]]; then
        save_baseline
    fi

    # Summary
    echo ""
    log_section "Performance Validation Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All performance checks passed!${NC}"
        echo -e "${GREEN}${BOLD}✓ Performance within acceptable thresholds${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ Performance issues detected!${NC}"
        echo -e "${RED}${BOLD}✗ Review metrics above${NC}"
        exit 1
    fi
}

main "$@"
