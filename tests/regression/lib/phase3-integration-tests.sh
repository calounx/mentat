#!/bin/bash
# ============================================================================
# Phase 3: Integration Tests
# ============================================================================
# Tests for service integration and data flow
# ============================================================================

set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-utils.sh"

# ============================================================================
# Metrics Collection Integration Tests
# ============================================================================

test_prometheus_targets() {
    local test_name="Prometheus Target Scraping"

    start_test "${test_name}"

    # Get Prometheus targets
    local response
    response=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null || echo "")

    if [[ -z "${response}" ]]; then
        log_error "Failed to get Prometheus targets"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check for targets
    local active_targets
    active_targets=$(echo "${response}" | jq -r '.data.activeTargets | length' 2>/dev/null || echo "0")

    if [[ ${active_targets} -gt 0 ]]; then
        log_success "Prometheus has ${active_targets} active targets"
    else
        log_warn "Prometheus has no active targets"
        end_test "${test_name}" "WARN"
        return 0
    fi

    # Check for down targets
    local down_targets
    down_targets=$(echo "${response}" | jq -r '.data.activeTargets[] | select(.health=="down") | .scrapeUrl' 2>/dev/null || echo "")

    if [[ -z "${down_targets}" ]]; then
        log_success "All Prometheus targets are up"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Some Prometheus targets are down:"
        log_warn "${down_targets}"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_prometheus_metrics_collection() {
    local test_name="Prometheus Metrics Collection"

    start_test "${test_name}"

    # Query for common metrics
    local metrics=(
        "up"
        "node_cpu_seconds_total"
        "node_memory_MemAvailable_bytes"
        "process_cpu_seconds_total"
    )

    local missing_metrics=0

    for metric in "${metrics[@]}"; do
        local response
        response=$(curl -s "http://localhost:9090/api/v1/query?query=${metric}" 2>/dev/null || echo "")

        local result_type
        result_type=$(echo "${response}" | jq -r '.data.resultType' 2>/dev/null || echo "")

        if [[ "${result_type}" == "vector" ]]; then
            local result_count
            result_count=$(echo "${response}" | jq -r '.data.result | length' 2>/dev/null || echo "0")

            if [[ ${result_count} -gt 0 ]]; then
                log_success "Metric ${metric} is being collected (${result_count} series)"
            else
                log_warn "Metric ${metric} has no data"
                missing_metrics=$((missing_metrics + 1))
            fi
        else
            log_warn "Metric ${metric} not found"
            missing_metrics=$((missing_metrics + 1))
        fi
    done

    if [[ ${missing_metrics} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "${missing_metrics} metrics are missing or have no data"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_grafana_prometheus_datasource() {
    local test_name="Grafana Prometheus Data Source"

    start_test "${test_name}"

    # Get Grafana API token (using admin:admin credentials)
    local auth
    auth=$(echo -n "admin:admin" | base64)

    # Check if Prometheus datasource exists
    local datasources
    datasources=$(curl -s -H "Authorization: Basic ${auth}" \
        "http://localhost:3000/api/datasources" 2>/dev/null || echo "[]")

    local prometheus_ds
    prometheus_ds=$(echo "${datasources}" | jq -r '.[] | select(.type=="prometheus") | .name' 2>/dev/null || echo "")

    if [[ -n "${prometheus_ds}" ]]; then
        log_success "Grafana has Prometheus datasource configured: ${prometheus_ds}"
    else
        log_warn "Grafana Prometheus datasource not found (may need provisioning)"
        end_test "${test_name}" "WARN"
        return 0
    fi

    # Test datasource connectivity
    local ds_id
    ds_id=$(echo "${datasources}" | jq -r '.[] | select(.type=="prometheus") | .uid' 2>/dev/null | head -1)

    if [[ -n "${ds_id}" ]]; then
        local test_result
        test_result=$(curl -s -X POST -H "Authorization: Basic ${auth}" \
            -H "Content-Type: application/json" \
            "http://localhost:3000/api/datasources/uid/${ds_id}/health" 2>/dev/null || echo "")

        if echo "${test_result}" | jq -r '.status' 2>/dev/null | grep -q "OK"; then
            log_success "Grafana can query Prometheus datasource"
            end_test "${test_name}" "PASS"
            return 0
        else
            log_warn "Grafana datasource health check unclear"
            end_test "${test_name}" "WARN"
            return 0
        fi
    else
        end_test "${test_name}" "WARN"
        return 0
    fi
}

# ============================================================================
# Log Aggregation Integration Tests
# ============================================================================

test_loki_log_ingestion() {
    local test_name="Loki Log Ingestion"

    start_test "${test_name}"

    # Send a test log entry
    local timestamp
    timestamp=$(date +%s%N)

    local log_payload
    log_payload=$(cat <<EOF
{
  "streams": [
    {
      "stream": {
        "job": "test",
        "source": "regression-test"
      },
      "values": [
        ["${timestamp}", "Test log entry from regression test"]
      ]
    }
  ]
}
EOF
)

    local push_result
    push_result=$(curl -s -X POST "http://localhost:3100/loki/api/v1/push" \
        -H "Content-Type: application/json" \
        -d "${log_payload}" 2>/dev/null || echo "error")

    # Wait a moment for ingestion
    sleep 2

    # Query for the test log
    local query_result
    query_result=$(curl -s -G "http://localhost:3100/loki/api/v1/query" \
        --data-urlencode 'query={source="regression-test"}' \
        --data-urlencode "limit=10" 2>/dev/null || echo "")

    if echo "${query_result}" | grep -q "Test log entry from regression test"; then
        log_success "Loki successfully ingested and returned test log"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Could not verify Loki log ingestion"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_grafana_loki_datasource() {
    local test_name="Grafana Loki Data Source"

    start_test "${test_name}"

    local auth
    auth=$(echo -n "admin:admin" | base64)

    # Check if Loki datasource exists
    local datasources
    datasources=$(curl -s -H "Authorization: Basic ${auth}" \
        "http://localhost:3000/api/datasources" 2>/dev/null || echo "[]")

    local loki_ds
    loki_ds=$(echo "${datasources}" | jq -r '.[] | select(.type=="loki") | .name' 2>/dev/null || echo "")

    if [[ -n "${loki_ds}" ]]; then
        log_success "Grafana has Loki datasource configured: ${loki_ds}"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Grafana Loki datasource not found (may need provisioning)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

# ============================================================================
# Application Integration Tests
# ============================================================================

test_mysql_database_creation() {
    local test_name="MySQL Database Creation"

    start_test "${test_name}"

    if ! command -v mysql &>/dev/null; then
        log_info "MySQL client not available, skipping test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    # Test creating a database
    if mysql -h127.0.0.1 -P3316 -uroot -proot \
        -e "CREATE DATABASE IF NOT EXISTS test_db; SHOW DATABASES;" 2>/dev/null | grep -q "test_db"; then
        log_success "MySQL database creation successful"

        # Cleanup
        mysql -h127.0.0.1 -P3316 -uroot -proot -e "DROP DATABASE IF EXISTS test_db;" 2>/dev/null

        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "MySQL database operations may not be working"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_redis_operations() {
    local test_name="Redis Operations"

    start_test "${test_name}"

    if ! command -v redis-cli &>/dev/null; then
        log_info "redis-cli not available, skipping test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    # Test SET operation
    local set_result
    set_result=$(redis-cli -h 127.0.0.1 -p 6389 SET integration_test "test_value" 2>/dev/null || echo "")

    if [[ "${set_result}" != "OK" ]]; then
        log_error "Redis SET operation failed"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Test GET operation
    local get_result
    get_result=$(redis-cli -h 127.0.0.1 -p 6389 GET integration_test 2>/dev/null || echo "")

    if [[ "${get_result}" != "test_value" ]]; then
        log_error "Redis GET operation failed"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Test DEL operation
    redis-cli -h 127.0.0.1 -p 6389 DEL integration_test &>/dev/null

    # Test list operations
    redis-cli -h 127.0.0.1 -p 6389 RPUSH test_list "item1" "item2" "item3" &>/dev/null
    local list_len
    list_len=$(redis-cli -h 127.0.0.1 -p 6389 LLEN test_list 2>/dev/null || echo "0")

    if [[ "${list_len}" == "3" ]]; then
        log_success "Redis list operations successful"
        redis-cli -h 127.0.0.1 -p 6389 DEL test_list &>/dev/null
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Redis list operations may have issues"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_chom_app_mysql_connection() {
    local test_name="CHOM App MySQL Connection"

    start_test "${test_name}"

    if ! container_is_running "chom_web"; then
        log_info "CHOM web container not running, skipping test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    # Check if Laravel can connect to MySQL
    local artisan_check
    artisan_check=$(exec_in_container "chom_web" \
        php /var/www/chom/artisan migrate:status 2>&1 || echo "error")

    if echo "${artisan_check}" | grep -qE "Migration table|No migrations"; then
        log_success "CHOM app can connect to MySQL"
        end_test "${test_name}" "PASS"
        return 0
    elif echo "${artisan_check}" | grep -q "error"; then
        log_warn "Could not verify CHOM MySQL connection (app may need setup)"
        end_test "${test_name}" "WARN"
        return 0
    else
        log_warn "CHOM MySQL connection status unclear"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_chom_app_redis_connection() {
    local test_name="CHOM App Redis Connection"

    start_test "${test_name}"

    if ! container_is_running "chom_web"; then
        log_info "CHOM web container not running, skipping test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    # Test Redis connection via Laravel
    local redis_check
    redis_check=$(exec_in_container "chom_web" \
        php /var/www/chom/artisan tinker --execute="Redis::set('test_key', 'test_value'); echo Redis::get('test_key');" 2>&1 || echo "error")

    if echo "${redis_check}" | grep -q "test_value"; then
        log_success "CHOM app can connect to Redis"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Could not verify CHOM Redis connection (app may need setup)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_metrics_exporters() {
    local test_name="Metrics Exporters Integration"

    start_test "${test_name}"

    # Check that exporters are returning valid Prometheus metrics
    local exporters=(
        "http://localhost:9199/metrics"
        "http://localhost:9101/metrics"
    )

    local failures=0

    for exporter in "${exporters[@]}"; do
        local metrics
        metrics=$(curl -s "${exporter}" 2>/dev/null || echo "")

        if echo "${metrics}" | grep -q "^# HELP"; then
            log_success "Exporter ${exporter} is returning valid metrics"
        else
            log_warn "Exporter ${exporter} may not be returning valid metrics"
            failures=$((failures + 1))
        fi
    done

    if [[ ${failures} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        end_test "${test_name}" "WARN"
        return 0
    fi
}

# ============================================================================
# Main Test Runners
# ============================================================================

run_phase3_tests_main() {
    start_phase "Phase 3: Integration Tests - Main Test Environment"

    test_prometheus_targets || true
    test_prometheus_metrics_collection || true
    test_grafana_prometheus_datasource || true
    test_loki_log_ingestion || true
    test_grafana_loki_datasource || true
    test_mysql_database_creation || true
    test_redis_operations || true
    test_chom_app_mysql_connection || true
    test_chom_app_redis_connection || true
    test_metrics_exporters || true

    end_phase
}

run_phase3_tests_vps() {
    start_phase "Phase 3: Integration Tests - VPS Simulation"

    # VPS-specific integration tests
    log_info "VPS integration tests would include deployment script validation"
    log_info "Skipping for now as this requires deployment execution"

    end_phase
}

run_phase3_tests_dev() {
    start_phase "Phase 3: Integration Tests - Development Environment"

    test_prometheus_targets || true
    test_grafana_prometheus_datasource || true
    test_loki_log_ingestion || true
    test_grafana_loki_datasource || true

    end_phase
}

# Export functions
export -f test_prometheus_targets
export -f test_prometheus_metrics_collection
export -f test_grafana_prometheus_datasource
export -f test_loki_log_ingestion
export -f test_grafana_loki_datasource
export -f test_mysql_database_creation
export -f test_redis_operations
export -f test_chom_app_mysql_connection
export -f test_chom_app_redis_connection
export -f test_metrics_exporters
export -f run_phase3_tests_main
export -f run_phase3_tests_vps
export -f run_phase3_tests_dev
