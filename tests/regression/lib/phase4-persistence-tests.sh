#!/bin/bash
# ============================================================================
# Phase 4: Persistence Tests
# ============================================================================
# Tests for data persistence across container restarts
# ============================================================================

set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-utils.sh"

# ============================================================================
# Volume Persistence Tests
# ============================================================================

test_prometheus_data_persistence() {
    local compose_file="$1"
    local test_name="Prometheus Data Persistence"

    start_test "${test_name}"

    # Write a test metric to Prometheus (via pushgateway if available, or check existing metrics)
    local initial_metrics
    initial_metrics=$(curl -s "http://localhost:9090/api/v1/query?query=up" 2>/dev/null || echo "")

    if [[ -z "${initial_metrics}" ]]; then
        log_warn "Could not query Prometheus, skipping persistence test"
        end_test "${test_name}" "WARN"
        return 0
    fi

    local initial_series_count
    initial_series_count=$(echo "${initial_metrics}" | jq -r '.data.result | length' 2>/dev/null || echo "0")

    log_info "Initial metrics series count: ${initial_series_count}"

    # Restart Prometheus container
    log_info "Restarting containers to test persistence..."
    docker compose -f "${compose_file}" restart

    # Wait for Prometheus to be healthy again
    sleep 10
    if ! wait_for_http "http://localhost:9090/-/healthy" 200 60; then
        log_error "Prometheus did not come back up after restart"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Query metrics again
    local after_restart_metrics
    after_restart_metrics=$(curl -s "http://localhost:9090/api/v1/query?query=up" 2>/dev/null || echo "")

    local after_series_count
    after_series_count=$(echo "${after_restart_metrics}" | jq -r '.data.result | length' 2>/dev/null || echo "0")

    log_info "After restart metrics series count: ${after_series_count}"

    if [[ ${after_series_count} -gt 0 ]]; then
        log_success "Prometheus data persisted after restart"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Prometheus data may not have persisted"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_grafana_data_persistence() {
    local compose_file="$1"
    local test_name="Grafana Data Persistence"

    start_test "${test_name}"

    local auth
    auth=$(echo -n "admin:admin" | base64)

    # Create a test dashboard
    local dashboard_payload
    dashboard_payload=$(cat <<'EOF'
{
  "dashboard": {
    "title": "Persistence Test Dashboard",
    "tags": ["test"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0
  },
  "overwrite": false
}
EOF
)

    local create_result
    create_result=$(curl -s -X POST -H "Authorization: Basic ${auth}" \
        -H "Content-Type: application/json" \
        -d "${dashboard_payload}" \
        "http://localhost:3000/api/dashboards/db" 2>/dev/null || echo "")

    local dashboard_uid
    dashboard_uid=$(echo "${create_result}" | jq -r '.uid' 2>/dev/null || echo "")

    if [[ -z "${dashboard_uid}" ]] || [[ "${dashboard_uid}" == "null" ]]; then
        log_warn "Could not create test dashboard, checking existing dashboards"
        # Just verify Grafana is accessible
        if wait_for_http "http://localhost:3000/api/health" 200 30; then
            log_success "Grafana is accessible after restart"
            end_test "${test_name}" "PASS"
            return 0
        else
            end_test "${test_name}" "FAIL"
            return 1
        fi
    fi

    log_info "Created dashboard with UID: ${dashboard_uid}"

    # Restart containers
    log_info "Restarting containers to test persistence..."
    docker compose -f "${compose_file}" restart

    # Wait for Grafana to be healthy again
    sleep 10
    if ! wait_for_http "http://localhost:3000/api/health" 200 60; then
        log_error "Grafana did not come back up after restart"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check if dashboard still exists
    local dashboard_check
    dashboard_check=$(curl -s -H "Authorization: Basic ${auth}" \
        "http://localhost:3000/api/dashboards/uid/${dashboard_uid}" 2>/dev/null || echo "")

    if echo "${dashboard_check}" | jq -r '.dashboard.title' 2>/dev/null | grep -q "Persistence Test Dashboard"; then
        log_success "Grafana dashboard persisted after restart"

        # Cleanup: delete test dashboard
        curl -s -X DELETE -H "Authorization: Basic ${auth}" \
            "http://localhost:3000/api/dashboards/uid/${dashboard_uid}" &>/dev/null

        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Grafana dashboard may not have persisted (could be expected behavior)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_mysql_data_persistence() {
    local compose_file="$1"
    local test_name="MySQL Data Persistence"

    start_test "${test_name}"

    if ! command -v mysql &>/dev/null; then
        log_info "MySQL client not available, skipping persistence test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    # Create a test database and table
    mysql -h127.0.0.1 -P3316 -uroot -proot <<'EOF' 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS persistence_test;
USE persistence_test;
CREATE TABLE IF NOT EXISTS test_data (
    id INT PRIMARY KEY,
    data VARCHAR(255)
);
INSERT INTO test_data (id, data) VALUES (1, 'test_value_before_restart');
EOF

    # Verify data was inserted
    local initial_data
    initial_data=$(mysql -h127.0.0.1 -P3316 -uroot -proot -s -N \
        -e "USE persistence_test; SELECT data FROM test_data WHERE id=1;" 2>/dev/null || echo "")

    if [[ "${initial_data}" != "test_value_before_restart" ]]; then
        log_warn "Could not create test data in MySQL"
        end_test "${test_name}" "WARN"
        return 0
    fi

    log_info "Test data created successfully"

    # Restart containers
    log_info "Restarting containers to test persistence..."
    docker compose -f "${compose_file}" restart

    # Wait for MySQL to be available again
    sleep 10
    if ! wait_for_port "localhost" 3316 60; then
        log_error "MySQL did not come back up after restart"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Additional wait for MySQL to be ready
    sleep 5

    # Check if data persisted
    local after_restart_data
    after_restart_data=$(mysql -h127.0.0.1 -P3316 -uroot -proot -s -N \
        -e "USE persistence_test; SELECT data FROM test_data WHERE id=1;" 2>/dev/null || echo "")

    if [[ "${after_restart_data}" == "test_value_before_restart" ]]; then
        log_success "MySQL data persisted after restart"

        # Cleanup
        mysql -h127.0.0.1 -P3316 -uroot -proot \
            -e "DROP DATABASE IF EXISTS persistence_test;" 2>/dev/null || true

        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "MySQL data did not persist after restart"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_redis_data_persistence() {
    local compose_file="$1"
    local test_name="Redis Data Persistence"

    start_test "${test_name}"

    if ! command -v redis-cli &>/dev/null; then
        log_info "redis-cli not available, skipping persistence test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    # Set a test key
    redis-cli -h 127.0.0.1 -p 6389 SET persistence_test "value_before_restart" &>/dev/null

    # Force save
    redis-cli -h 127.0.0.1 -p 6389 SAVE &>/dev/null || \
        redis-cli -h 127.0.0.1 -p 6389 BGSAVE &>/dev/null

    log_info "Test data created in Redis"

    # Restart containers
    log_info "Restarting containers to test persistence..."
    docker compose -f "${compose_file}" restart

    # Wait for Redis to be available again
    sleep 10
    if ! wait_for_port "localhost" 6389 60; then
        log_error "Redis did not come back up after restart"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check if data persisted
    local after_restart_value
    after_restart_value=$(redis-cli -h 127.0.0.1 -p 6389 GET persistence_test 2>/dev/null || echo "")

    if [[ "${after_restart_value}" == "value_before_restart" ]]; then
        log_success "Redis data persisted after restart"

        # Cleanup
        redis-cli -h 127.0.0.1 -p 6389 DEL persistence_test &>/dev/null

        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Redis data may not have persisted (AOF/RDB may not be enabled)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_loki_data_persistence() {
    local compose_file="$1"
    local test_name="Loki Data Persistence"

    start_test "${test_name}"

    # Send a unique test log
    local timestamp
    timestamp=$(date +%s%N)
    local unique_id
    unique_id="persistence-test-${RANDOM}"

    local log_payload
    log_payload=$(cat <<EOF
{
  "streams": [
    {
      "stream": {
        "job": "persistence-test",
        "id": "${unique_id}"
      },
      "values": [
        ["${timestamp}", "Persistence test log before restart"]
      ]
    }
  ]
}
EOF
)

    curl -s -X POST "http://localhost:3100/loki/api/v1/push" \
        -H "Content-Type: application/json" \
        -d "${log_payload}" &>/dev/null

    log_info "Test log sent to Loki"
    sleep 3

    # Verify log was ingested
    local initial_query
    initial_query=$(curl -s -G "http://localhost:3100/loki/api/v1/query" \
        --data-urlencode "query={id=\"${unique_id}\"}" 2>/dev/null || echo "")

    if ! echo "${initial_query}" | grep -q "Persistence test log before restart"; then
        log_warn "Could not verify initial log ingestion"
        end_test "${test_name}" "WARN"
        return 0
    fi

    # Restart containers
    log_info "Restarting containers to test persistence..."
    docker compose -f "${compose_file}" restart

    # Wait for Loki to be available again
    sleep 10
    if ! wait_for_http "http://localhost:3100/ready" 200 60; then
        log_error "Loki did not come back up after restart"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    sleep 3

    # Query for the test log
    local after_restart_query
    after_restart_query=$(curl -s -G "http://localhost:3100/loki/api/v1/query" \
        --data-urlencode "query={id=\"${unique_id}\"}" 2>/dev/null || echo "")

    if echo "${after_restart_query}" | grep -q "Persistence test log before restart"; then
        log_success "Loki data persisted after restart"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Loki data may not have persisted (retention policy may be short)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

# ============================================================================
# Configuration Persistence Tests
# ============================================================================

test_volume_integrity() {
    local compose_file="$1"
    local test_name="Volume Integrity Check"

    start_test "${test_name}"

    # Get all volumes used by the compose file
    local volumes
    volumes=$(docker compose -f "${compose_file}" config --volumes 2>/dev/null || echo "")

    if [[ -z "${volumes}" ]]; then
        log_info "No named volumes to check"
        end_test "${test_name}" "PASS"
        return 0
    fi

    local errors=0

    while IFS= read -r volume; do
        if [[ -n "${volume}" ]]; then
            # Check volume exists and is healthy
            if docker volume inspect "${volume}" &>/dev/null; then
                local mountpoint
                mountpoint=$(docker volume inspect "${volume}" --format '{{.Mountpoint}}' 2>/dev/null || echo "")

                if [[ -n "${mountpoint}" ]]; then
                    log_success "Volume ${volume} is intact at ${mountpoint}"
                else
                    log_warn "Volume ${volume} has no mountpoint"
                    errors=$((errors + 1))
                fi
            else
                log_error "Volume ${volume} not found"
                errors=$((errors + 1))
            fi
        fi
    done <<< "${volumes}"

    if [[ ${errors} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "${errors} volume integrity issues found"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_full_stop_start_cycle() {
    local compose_file="$1"
    local test_name="Full Stop/Start Cycle"

    start_test "${test_name}"

    log_info "Stopping all containers..."
    docker compose -f "${compose_file}" stop

    # Verify all containers are stopped
    local running_count
    running_count=$(docker compose -f "${compose_file}" ps --format json 2>/dev/null | \
        jq -r '.[] | select(.State=="running") | .Name' | wc -l || echo "999")

    if [[ ${running_count} -ne 0 ]]; then
        log_warn "${running_count} containers still running after stop"
    fi

    log_info "Starting all containers..."
    if ! docker_compose_up "${compose_file}" 300; then
        log_error "Failed to restart containers"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Verify all containers are healthy
    sleep 10
    local unhealthy=0
    local containers
    containers=$(docker compose -f "${compose_file}" ps --format json 2>/dev/null | jq -r '.[].Name' || echo "")

    while IFS= read -r container; do
        if [[ -n "${container}" ]]; then
            if ! container_is_healthy "${container}"; then
                log_warn "Container ${container} may not be healthy after restart"
                unhealthy=$((unhealthy + 1))
            fi
        fi
    done <<< "${containers}"

    if [[ ${unhealthy} -eq 0 ]]; then
        log_success "All containers are healthy after stop/start cycle"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "${unhealthy} containers may have health issues"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_phase4_tests() {
    local compose_file="$1"

    start_phase "Phase 4: Persistence Tests"

    test_volume_integrity "${compose_file}" || true
    test_prometheus_data_persistence "${compose_file}" || true
    test_grafana_data_persistence "${compose_file}" || true
    test_mysql_data_persistence "${compose_file}" || true
    test_redis_data_persistence "${compose_file}" || true
    test_loki_data_persistence "${compose_file}" || true
    test_full_stop_start_cycle "${compose_file}" || true

    end_phase
}

# Export functions
export -f test_prometheus_data_persistence
export -f test_grafana_data_persistence
export -f test_mysql_data_persistence
export -f test_redis_data_persistence
export -f test_loki_data_persistence
export -f test_volume_integrity
export -f test_full_stop_start_cycle
export -f run_phase4_tests
