#!/bin/bash

# Enhanced Health Check Script for CHOM
# Comprehensive health monitoring for production deployments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
APP_URL="${APP_URL:-http://localhost}"
TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
PROMETHEUS_PUSHGATEWAY="${PROMETHEUS_PUSHGATEWAY:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"  # text, json, prometheus
RUN_EXPORTER_SCAN="${RUN_EXPORTER_SCAN:-false}"  # Enable exporter detection
AUTO_REMEDIATE="${AUTO_REMEDIATE:-false}"  # Auto-fix exporter issues

# Thresholds
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-85}"
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"
RESPONSE_TIME_THRESHOLD="${RESPONSE_TIME_THRESHOLD:-2000}"  # ms
ERROR_RATE_THRESHOLD="${ERROR_RATE_THRESHOLD:-5}"  # percent

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Health check results
declare -A CHECKS
OVERALL_STATUS="healthy"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# JSON output buffer
JSON_OUTPUT='{"timestamp":"'$(date -Iseconds)'","checks":{'

log() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo "$1"
    fi
}

log_success() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

log_error() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${RED}✗${NC} $1"
    fi
}

log_warning() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

# Record check result
record_check() {
    local name=$1
    local status=$2  # pass, fail, warn
    local message=$3
    local value=${4:-""}

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    case "$status" in
        pass)
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            log_success "$message"
            ;;
        fail)
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            OVERALL_STATUS="unhealthy"
            log_error "$message"
            ;;
        warn)
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            if [ "$OVERALL_STATUS" = "healthy" ]; then
                OVERALL_STATUS="degraded"
            fi
            log_warning "$message"
            ;;
    esac

    CHECKS[$name]="$status|$message|$value"

    # Add to JSON output
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        JSON_OUTPUT+='"'$name'":{"status":"'$status'","message":"'$message'","value":"'$value'"},'
    fi
}

# System resource checks
check_cpu() {
    log "Checking CPU usage..."

    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    cpu_usage=${cpu_usage%.*}  # Remove decimal

    if [ "$cpu_usage" -lt "$CPU_THRESHOLD" ]; then
        record_check "cpu" "pass" "CPU usage: ${cpu_usage}%" "$cpu_usage"
    else
        record_check "cpu" "warn" "CPU usage high: ${cpu_usage}%" "$cpu_usage"
    fi
}

check_memory() {
    log "Checking memory usage..."

    local mem_info=$(free | grep Mem)
    local total=$(echo $mem_info | awk '{print $2}')
    local used=$(echo $mem_info | awk '{print $3}')
    local mem_percent=$((used * 100 / total))

    if [ "$mem_percent" -lt "$MEMORY_THRESHOLD" ]; then
        record_check "memory" "pass" "Memory usage: ${mem_percent}%" "$mem_percent"
    else
        record_check "memory" "warn" "Memory usage high: ${mem_percent}%" "$mem_percent"
    fi
}

check_disk() {
    log "Checking disk space..."

    local disk_usage=$(df -h "$PROJECT_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [ "$disk_usage" -lt "$DISK_THRESHOLD" ]; then
        record_check "disk" "pass" "Disk usage: ${disk_usage}%" "$disk_usage"
    elif [ "$disk_usage" -lt 95 ]; then
        record_check "disk" "warn" "Disk usage high: ${disk_usage}%" "$disk_usage"
    else
        record_check "disk" "fail" "Disk usage critical: ${disk_usage}%" "$disk_usage"
    fi
}

# Service checks
check_nginx() {
    log "Checking Nginx..."

    if systemctl is-active --quiet nginx; then
        record_check "nginx" "pass" "Nginx is running" "active"
    else
        record_check "nginx" "fail" "Nginx is not running" "inactive"
    fi
}

check_php_fpm() {
    log "Checking PHP-FPM..."

    if systemctl is-active --quiet php8.2-fpm || systemctl is-active --quiet php-fpm; then
        record_check "php_fpm" "pass" "PHP-FPM is running" "active"
    else
        record_check "php_fpm" "fail" "PHP-FPM is not running" "inactive"
    fi
}

check_mysql() {
    log "Checking MySQL..."

    if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
        record_check "mysql" "pass" "MySQL is running" "active"

        # Check connection
        cd "$PROJECT_ROOT"
        if php artisan db:show > /dev/null 2>&1; then
            record_check "mysql_connection" "pass" "MySQL connection successful" "connected"
        else
            record_check "mysql_connection" "fail" "Cannot connect to MySQL" "disconnected"
        fi
    else
        record_check "mysql" "fail" "MySQL is not running" "inactive"
    fi
}

check_redis() {
    log "Checking Redis..."

    if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
        record_check "redis" "pass" "Redis is running" "active"

        # Check connection
        cd "$PROJECT_ROOT"
        if php artisan tinker --execute="Redis::ping();" 2>/dev/null | grep -q "PONG"; then
            record_check "redis_connection" "pass" "Redis connection successful" "connected"
        else
            record_check "redis_connection" "fail" "Cannot connect to Redis" "disconnected"
        fi
    else
        record_check "redis" "fail" "Redis is not running" "inactive"
    fi
}

# Application checks
check_http_endpoint() {
    log "Checking HTTP endpoints..."

    # Main health endpoint
    local start_time=$(date +%s%N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "${APP_URL}/health" || echo "000")
    local end_time=$(date +%s%N)
    local response_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds

    if [ "$http_code" = "200" ]; then
        if [ "$response_time" -lt "$RESPONSE_TIME_THRESHOLD" ]; then
            record_check "http_health" "pass" "Health endpoint: HTTP ${http_code} (${response_time}ms)" "$response_time"
        else
            record_check "http_health" "warn" "Health endpoint slow: ${response_time}ms" "$response_time"
        fi
    else
        record_check "http_health" "fail" "Health endpoint failed: HTTP ${http_code}" "$http_code"
    fi

    # Readiness endpoint
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "${APP_URL}/health/ready" || echo "000")
    if [ "$http_code" = "200" ]; then
        record_check "http_ready" "pass" "Readiness check passed" "ready"
    else
        record_check "http_ready" "fail" "Application not ready: HTTP ${http_code}" "not_ready"
    fi
}

check_database_health() {
    log "Checking database health..."

    cd "$PROJECT_ROOT"

    # Check migrations
    if php artisan migrate:status > /dev/null 2>&1; then
        record_check "migrations" "pass" "Database migrations current" "current"
    else
        record_check "migrations" "warn" "Migration status check failed" "unknown"
    fi

    # Check table count
    local table_count=$(php artisan tinker --execute="DB::select('SHOW TABLES');" 2>/dev/null | grep -c '>' || echo "0")
    if [ "$table_count" -gt 0 ]; then
        record_check "db_tables" "pass" "Database has ${table_count} tables" "$table_count"
    else
        record_check "db_tables" "fail" "No database tables found" "0"
    fi
}

check_cache_health() {
    log "Checking cache health..."

    cd "$PROJECT_ROOT"

    # Test cache write/read
    local test_key="health_check_$(date +%s)"
    local test_value="health_$(date +%s)"

    php artisan tinker --execute="Cache::put('${test_key}', '${test_value}', 60);" > /dev/null 2>&1
    local cached_value=$(php artisan tinker --execute="echo Cache::get('${test_key}');" 2>/dev/null | grep -v "^>" | tail -1)

    if [ "$cached_value" = "$test_value" ]; then
        record_check "cache" "pass" "Cache read/write working" "functional"
        php artisan tinker --execute="Cache::forget('${test_key}');" > /dev/null 2>&1
    else
        record_check "cache" "fail" "Cache not working" "failed"
    fi
}

check_queue_workers() {
    log "Checking queue workers..."

    local worker_count=$(pgrep -f "artisan queue:work" | wc -l)

    if [ "$worker_count" -gt 0 ]; then
        record_check "queue_workers" "pass" "${worker_count} queue worker(s) running" "$worker_count"
    else
        record_check "queue_workers" "warn" "No queue workers running" "0"
    fi
}

check_storage_permissions() {
    log "Checking storage permissions..."

    local test_file="${PROJECT_ROOT}/storage/app/health_check_$(date +%s).tmp"

    if touch "$test_file" 2>/dev/null; then
        record_check "storage_write" "pass" "Storage is writable" "writable"
        rm -f "$test_file"
    else
        record_check "storage_write" "fail" "Storage is not writable" "read_only"
    fi
}

check_log_files() {
    log "Checking log files..."

    local log_file="${PROJECT_ROOT}/storage/logs/laravel.log"

    if [ -f "$log_file" ]; then
        local log_size=$(du -h "$log_file" | cut -f1)
        local recent_errors=$(tail -100 "$log_file" | grep -c "ERROR" || echo "0")

        if [ "$recent_errors" -eq 0 ]; then
            record_check "logs" "pass" "No recent errors (log: ${log_size})" "0"
        else
            record_check "logs" "warn" "${recent_errors} recent error(s) in log" "$recent_errors"
        fi
    else
        record_check "logs" "warn" "Log file not found" "missing"
    fi
}

# SSL certificate check
check_ssl_certificate() {
    log "Checking SSL certificate..."

    if [[ "$APP_URL" == https://* ]]; then
        local domain=$(echo "$APP_URL" | sed 's|https://||' | cut -d/ -f1)
        local cert_expiry=$(echo | openssl s_client -servername "$domain" -connect "${domain}:443" 2>/dev/null | \
            openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

        if [ -n "$cert_expiry" ]; then
            local expiry_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$cert_expiry" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [ "$days_until_expiry" -gt 30 ]; then
                record_check "ssl_cert" "pass" "SSL certificate valid for ${days_until_expiry} days" "$days_until_expiry"
            elif [ "$days_until_expiry" -gt 0 ]; then
                record_check "ssl_cert" "warn" "SSL certificate expires in ${days_until_expiry} days" "$days_until_expiry"
            else
                record_check "ssl_cert" "fail" "SSL certificate expired" "0"
            fi
        else
            record_check "ssl_cert" "warn" "Could not verify SSL certificate" "unknown"
        fi
    else
        record_check "ssl_cert" "pass" "SSL not configured (HTTP)" "n/a"
    fi
}

# Observability checks
check_exporters() {
    log "Checking Prometheus exporters..."

    local exporter_script="${PROJECT_ROOT}/../../scripts/observability/detect-exporters.sh"

    if [ ! -f "$exporter_script" ]; then
        record_check "exporters" "warn" "Exporter detection script not found" "missing"
        return
    fi

    # Run exporter detection
    local exporter_output
    exporter_output=$("$exporter_script" --format json 2>/dev/null || echo "{}")

    # Parse JSON output
    local services_detected=$(echo "$exporter_output" | jq -r '.summary.services_detected // 0' 2>/dev/null || echo "0")
    local exporters_running=$(echo "$exporter_output" | jq -r '.summary.exporters_running // 0' 2>/dev/null || echo "0")
    local missing_exporters=$(echo "$exporter_output" | jq -r '.summary.missing_exporters // 0' 2>/dev/null || echo "0")

    if [ "$missing_exporters" -eq 0 ]; then
        record_check "exporters" "pass" "All exporters configured (${exporters_running}/${services_detected} services)" "$exporters_running"
    elif [ "$missing_exporters" -lt 3 ]; then
        record_check "exporters" "warn" "${missing_exporters} exporter(s) missing" "$missing_exporters"

        # Auto-remediate if enabled
        if [ "$AUTO_REMEDIATE" = "true" ]; then
            log "Auto-remediation enabled, attempting to install missing exporters..."
            "$exporter_script" --install 2>&1 | head -10
        fi
    else
        record_check "exporters" "fail" "Multiple exporters missing (${missing_exporters})" "$missing_exporters"
    fi
}

check_node_exporter() {
    log "Checking node_exporter..."

    # Check if node_exporter is running
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        # Check metrics endpoint
        if curl -sf http://localhost:9100/metrics >/dev/null 2>&1; then
            record_check "node_exporter" "pass" "Node exporter running and accessible" "active"
        else
            record_check "node_exporter" "warn" "Node exporter running but metrics not accessible" "no_metrics"
        fi
    else
        record_check "node_exporter" "warn" "Node exporter not running" "inactive"
    fi
}

# Output results
output_results() {
    case "$OUTPUT_FORMAT" in
        text)
            echo ""
            echo "========================================="
            echo "  HEALTH CHECK SUMMARY"
            echo "========================================="
            echo "Overall Status: $OVERALL_STATUS"
            echo "Total Checks: $TOTAL_CHECKS"
            echo "Passed: $PASSED_CHECKS"
            echo "Failed: $FAILED_CHECKS"
            echo "Warnings: $WARNING_CHECKS"
            echo "========================================="
            ;;
        json)
            # Close JSON
            JSON_OUTPUT=${JSON_OUTPUT%,}  # Remove trailing comma
            JSON_OUTPUT+='},"summary":{"status":"'$OVERALL_STATUS'","total":'$TOTAL_CHECKS',"passed":'$PASSED_CHECKS',"failed":'$FAILED_CHECKS',"warnings":'$WARNING_CHECKS'}}'
            echo "$JSON_OUTPUT" | jq '.' 2>/dev/null || echo "$JSON_OUTPUT"
            ;;
        prometheus)
            # Output Prometheus metrics
            echo "# HELP health_check_status Overall health status (1=healthy, 0=unhealthy)"
            echo "# TYPE health_check_status gauge"
            [ "$OVERALL_STATUS" = "healthy" ] && echo "health_check_status 1" || echo "health_check_status 0"

            echo "# HELP health_checks_total Total number of health checks"
            echo "# TYPE health_checks_total counter"
            echo "health_checks_total $TOTAL_CHECKS"

            echo "# HELP health_checks_passed Number of passed checks"
            echo "# TYPE health_checks_passed counter"
            echo "health_checks_passed $PASSED_CHECKS"

            echo "# HELP health_checks_failed Number of failed checks"
            echo "# TYPE health_checks_failed counter"
            echo "health_checks_failed $FAILED_CHECKS"

            # Individual check metrics
            for check_name in "${!CHECKS[@]}"; do
                IFS='|' read -r status message value <<< "${CHECKS[$check_name]}"
                local status_value=0
                [ "$status" = "pass" ] && status_value=1

                echo "# HELP health_check_${check_name} Status of ${check_name} check"
                echo "# TYPE health_check_${check_name} gauge"
                echo "health_check_${check_name} $status_value"
            done
            ;;
    esac
}

# Push metrics to Prometheus Pushgateway
push_to_prometheus() {
    if [ -n "$PROMETHEUS_PUSHGATEWAY" ]; then
        log "Pushing metrics to Prometheus Pushgateway..."

        local metrics=$(OUTPUT_FORMAT=prometheus bash "$0")

        echo "$metrics" | curl -s --data-binary @- \
            "${PROMETHEUS_PUSHGATEWAY}/metrics/job/health_check/instance/$(hostname)" \
            >/dev/null 2>&1 || log_warning "Failed to push metrics to Prometheus"
    fi
}

# Main execution
main() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo "========================================="
        echo "  CHOM HEALTH CHECK"
        echo "========================================="
        echo "Timestamp: $(date)"
        echo ""
    fi

    # Run all checks
    check_cpu
    check_memory
    check_disk
    check_nginx
    check_php_fpm
    check_mysql
    check_redis
    check_http_endpoint
    check_database_health
    check_cache_health
    check_queue_workers
    check_storage_permissions
    check_log_files
    check_ssl_certificate

    # Optional exporter checks
    if [ "$RUN_EXPORTER_SCAN" = "true" ]; then
        check_node_exporter
        check_exporters
    fi

    # Output results
    output_results

    # Push to Prometheus if configured
    if [ "$OUTPUT_FORMAT" != "prometheus" ]; then
        push_to_prometheus
    fi

    # Exit with appropriate code
    if [ "$OVERALL_STATUS" = "healthy" ]; then
        exit 0
    elif [ "$OVERALL_STATUS" = "degraded" ]; then
        exit 1
    else
        exit 2
    fi
}

# Run main
main
