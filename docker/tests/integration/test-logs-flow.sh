#!/usr/bin/env bash
#==============================================================================
# Logs Flow Integration Tests
# Tests end-to-end log shipping from landsraad_tst to Loki on mentat_tst
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-lib.sh"

# Configuration
MENTAT_CONTAINER="${MENTAT_CONTAINER:-mentat_tst}"
LANDSRAAD_CONTAINER="${LANDSRAAD_CONTAINER:-landsraad_tst}"
LOKI_URL="http://${MENTAT_IP}:${LOKI_PORT}"

#------------------------------------------------------------------------------
# Test Functions
#------------------------------------------------------------------------------

test_promtail_running() {
    log_test "Promtail service running on landsraad_tst"

    local status
    status=$(docker exec "${LANDSRAAD_CONTAINER}" systemctl is-active promtail 2>/dev/null || echo "inactive")

    if [[ "$status" == "active" ]]; then
        test_pass "promtail_running"
    else
        test_fail "promtail_running" "Promtail service is $status"
    fi
}

test_promtail_targets_ready() {
    log_test "Promtail targets are ready"

    local response
    response=$(docker exec "${LANDSRAAD_CONTAINER}" curl -s "http://localhost:9080/ready" 2>/dev/null || echo "")

    if [[ "$response" == "Ready" ]]; then
        test_pass "promtail_targets_ready"
    else
        test_fail "promtail_targets_ready" "Promtail not ready: $response"
    fi
}

test_promtail_reading_bytes() {
    log_test "Promtail is reading log files"

    local metrics
    metrics=$(docker exec "${LANDSRAAD_CONTAINER}" curl -s "http://localhost:9080/metrics" 2>/dev/null || echo "")

    local bytes_read
    bytes_read=$(echo "$metrics" | grep "promtail_read_bytes_total" | awk '{sum += $2} END {print sum+0}')

    if [[ "$bytes_read" -gt 0 ]]; then
        test_pass "promtail_reading_bytes" "${bytes_read} bytes read"
    else
        test_fail "promtail_reading_bytes" "No bytes read by Promtail"
    fi
}

test_promtail_sending_entries() {
    log_test "Promtail is sending entries to Loki"

    local metrics
    metrics=$(docker exec "${LANDSRAAD_CONTAINER}" curl -s "http://localhost:9080/metrics" 2>/dev/null || echo "")

    local entries_sent
    entries_sent=$(echo "$metrics" | grep "promtail_sent_entries_total" | awk '{sum += $2} END {print sum+0}')

    if [[ "$entries_sent" -gt 0 ]]; then
        test_pass "promtail_sending_entries" "${entries_sent} entries sent"
    else
        test_skip "promtail_sending_entries" "No entries sent yet (may need log activity)"
    fi
}

test_loki_ready() {
    log_test "Loki is ready to receive logs"

    local response
    response=$(docker exec "${MENTAT_CONTAINER}" curl -s "http://localhost:3100/ready" 2>/dev/null || echo "")

    if [[ "$response" == "ready" ]]; then
        test_pass "loki_ready"
    else
        test_fail "loki_ready" "Loki not ready: $response"
    fi
}

test_loki_has_landsraad_logs() {
    log_test "Loki has logs from landsraad_tst"

    local start=$(($(date +%s) - 7200))000000000
    local end=$(date +%s)000000000

    local response
    response=$(docker exec "${MENTAT_CONTAINER}" curl -sG "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={host="landsraad_tst"}' \
        --data-urlencode 'limit=5' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null || echo "{}")

    local count
    count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        test_pass "loki_has_landsraad_logs" "$count stream(s) found"
    else
        test_skip "loki_has_landsraad_logs" "No logs from landsraad_tst yet"
    fi
}

test_nginx_log_flow() {
    log_test "Nginx access logs flowing to Loki"

    # Generate nginx log entry by making a request
    docker exec "${LANDSRAAD_CONTAINER}" curl -s "http://localhost/health" >/dev/null 2>&1 || true

    # Wait for log to be processed
    sleep 3

    local start=$(($(date +%s) - 300))000000000
    local end=$(date +%s)000000000

    local response
    response=$(docker exec "${MENTAT_CONTAINER}" curl -sG "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={filename=~".*nginx.*access.*"}' \
        --data-urlencode 'limit=5' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null || echo "{}")

    local count
    count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        test_pass "nginx_log_flow" "Nginx logs present"
    else
        test_skip "nginx_log_flow" "Nginx logs not yet in Loki"
    fi
}

test_laravel_log_flow() {
    log_test "Laravel application logs flowing to Loki"

    local start=$(($(date +%s) - 3600))000000000
    local end=$(date +%s)000000000

    local response
    response=$(docker exec "${MENTAT_CONTAINER}" curl -sG "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={app="chom"}' \
        --data-urlencode 'limit=5' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null || echo "{}")

    local count
    count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        test_pass "laravel_log_flow" "Laravel logs present"
    else
        test_skip "laravel_log_flow" "Laravel logs not yet in Loki"
    fi
}

test_log_labels_present() {
    log_test "Required log labels present in Loki"

    local response
    response=$(docker exec "${MENTAT_CONTAINER}" curl -s "http://localhost:3100/loki/api/v1/labels" 2>/dev/null || echo "{}")

    local status
    status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)

    if [[ "$status" == "success" ]]; then
        local labels
        labels=$(echo "$response" | jq -r '.data[]' 2>/dev/null | tr '\n' ',')

        local has_job=false
        local has_host=false

        if echo "$labels" | grep -q "job"; then has_job=true; fi
        if echo "$labels" | grep -q "host"; then has_host=true; fi

        if [[ "$has_job" == true ]] && [[ "$has_host" == true ]]; then
            test_pass "log_labels_present" "job and host labels present"
        else
            test_skip "log_labels_present" "Some labels missing (job: $has_job, host: $has_host)"
        fi
    else
        test_fail "log_labels_present" "Could not query labels"
    fi
}

test_end_to_end_log_push() {
    log_test "End-to-end log push test"

    local test_marker="REGRESSION_TEST_$(date +%s)_$$"

    # Write test log entry
    docker exec "${LANDSRAAD_CONTAINER}" bash -c "echo '[$test_marker] Test log entry' >> /var/log/nginx/access.log" 2>/dev/null

    # Wait for Promtail to pick up and send
    sleep 5

    # Query Loki for the test marker
    local start=$(($(date +%s) - 120))000000000
    local end=$(date +%s)000000000

    local response
    response=$(docker exec "${MENTAT_CONTAINER}" curl -sG "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode "query={host=\"landsraad_tst\"} |= \"$test_marker\"" \
        --data-urlencode 'limit=5' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null || echo "{}")

    local count
    count=$(echo "$response" | jq '[.data.result[].values[]] | length' 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        test_pass "end_to_end_log_push" "Test log entry found in Loki"
    else
        test_fail "end_to_end_log_push" "Test log entry not found in Loki"
    fi
}

test_promtail_loki_connectivity() {
    log_test "Promtail can reach Loki"

    local response
    response=$(docker exec "${LANDSRAAD_CONTAINER}" curl -s "http://${MENTAT_IP}:3100/ready" 2>/dev/null || echo "")

    if [[ "$response" == "ready" ]]; then
        test_pass "promtail_loki_connectivity"
    else
        test_fail "promtail_loki_connectivity" "Cannot reach Loki from landsraad_tst"
    fi
}

test_no_promtail_errors() {
    log_test "No critical errors in Promtail logs"

    local errors
    errors=$(docker exec "${LANDSRAAD_CONTAINER}" journalctl -u promtail --no-pager -n 50 2>/dev/null | grep -i "error" | grep -v "level=info" | head -5 || echo "")

    if [[ -z "$errors" ]]; then
        test_pass "no_promtail_errors"
    else
        test_skip "no_promtail_errors" "Found some error messages in logs"
    fi
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    init_test_lib

    log_header "Logs Flow Integration Tests"
    echo "  landsraad_tst (Promtail) -> mentat_tst (Loki)"
    echo ""

    log_section "Promtail Status (landsraad_tst)"
    test_promtail_running
    test_promtail_targets_ready
    test_promtail_reading_bytes
    test_promtail_sending_entries
    test_no_promtail_errors

    log_section "Loki Status (mentat_tst)"
    test_loki_ready
    test_log_labels_present

    log_section "Network Connectivity"
    test_promtail_loki_connectivity

    log_section "Log Flow Verification"
    test_loki_has_landsraad_logs
    test_nginx_log_flow
    test_laravel_log_flow

    log_section "End-to-End Test"
    test_end_to_end_log_push

    print_summary "Logs Flow Integration Tests"
}

main "$@"
