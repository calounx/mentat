#!/usr/bin/env bash
#==============================================================================
# Alertmanager Regression Tests
# Tests health, API, alerts, silences, and receivers
#==============================================================================
set -euo pipefail

# Configuration
ALERTMANAGER_HOST="${ALERTMANAGER_HOST:-10.10.100.10}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
ALERTMANAGER_URL="http://${ALERTMANAGER_HOST}:${ALERTMANAGER_PORT}"
TIMEOUT="${TIMEOUT:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

http_get() {
    local url="$1"
    curl -s --max-time "${TIMEOUT}" "${url}" 2>/dev/null
}

http_status() {
    local url="$1"
    curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT}" "${url}" 2>/dev/null || echo "000"
}

check_dependencies() {
    if ! command -v curl &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} curl is required but not installed"
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} jq is required but not installed"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Test Functions
#------------------------------------------------------------------------------

test_healthy_endpoint() {
    log_info "Testing Alertmanager healthy endpoint..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/-/healthy")

    if [[ "$response" == *"OK"* ]] || [[ "$response" == *"Healthy"* ]]; then
        log_pass "Healthy endpoint responds correctly"
    else
        log_fail "Healthy endpoint did not respond as expected: $response"
    fi
}

test_ready_endpoint() {
    log_info "Testing Alertmanager ready endpoint..."
    local status
    status=$(http_status "${ALERTMANAGER_URL}/-/ready")

    if [[ "$status" == "200" ]]; then
        log_pass "Ready endpoint returns 200 OK"
    else
        log_fail "Ready endpoint returned status $status"
    fi
}

test_status_endpoint() {
    log_info "Testing Alertmanager status endpoint..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/api/v2/status")

    if echo "$response" | jq -e '.cluster' &>/dev/null; then
        local uptime
        uptime=$(echo "$response" | jq -r '.uptime // "unknown"')
        log_pass "Status endpoint accessible (uptime: $uptime)"
    else
        log_fail "Status endpoint did not return expected data"
    fi
}

test_alerts_api() {
    log_info "Testing Alertmanager alerts API..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/api/v2/alerts")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        log_pass "Alerts API accessible ($count active alerts)"
    else
        log_fail "Alerts API did not return expected format"
    fi
}

test_alert_groups_api() {
    log_info "Testing Alertmanager alert groups API..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/api/v2/alerts/groups")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        log_pass "Alert groups API accessible ($count groups)"
    else
        log_fail "Alert groups API did not return expected format"
    fi
}

test_silences_api() {
    log_info "Testing Alertmanager silences API..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/api/v2/silences")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        log_pass "Silences API accessible ($count silences)"
    else
        log_fail "Silences API did not return expected format"
    fi
}

test_receivers_api() {
    log_info "Testing Alertmanager receivers API..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/api/v2/receivers")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        if [[ "$count" -gt 0 ]]; then
            local receivers
            receivers=$(echo "$response" | jq -r '.[].name' | tr '\n' ', ' | sed 's/,$//')
            log_pass "Found $count receiver(s): $receivers"
        else
            log_skip "No receivers configured"
        fi
    else
        log_fail "Receivers API did not return expected format"
    fi
}

test_config_reload() {
    log_info "Testing Alertmanager config reload endpoint..."
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        --max-time "${TIMEOUT}" \
        "${ALERTMANAGER_URL}/-/reload" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]]; then
        log_pass "Config reload endpoint accessible"
    else
        log_skip "Config reload returned status $status (may be disabled)"
    fi
}

test_post_alert() {
    log_info "Testing Alertmanager alert posting..."
    local test_alert
    test_alert=$(cat <<EOF
[
  {
    "labels": {
      "alertname": "RegressionTestAlert",
      "severity": "test",
      "instance": "test-runner"
    },
    "annotations": {
      "summary": "Test alert from regression tests",
      "description": "This alert was created by the regression test suite"
    },
    "startsAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "endsAt": "$(date -u -d '+1 minute' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+1M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
]
EOF
)

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$test_alert" \
        --max-time "${TIMEOUT}" \
        "${ALERTMANAGER_URL}/api/v2/alerts" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]]; then
        log_pass "Alert posting successful"
    else
        log_fail "Alert posting failed (status: $status)"
    fi
}

test_silence_create_delete() {
    log_info "Testing Alertmanager silence create/delete..."

    local start_time
    local end_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    end_time=$(date -u -d '+5 minutes' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
               date -u -v+5M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
               date -u +"%Y-%m-%dT%H:%M:%SZ")

    local silence_payload
    silence_payload=$(cat <<EOF
{
  "matchers": [
    {
      "name": "alertname",
      "value": "RegressionTestSilence",
      "isRegex": false,
      "isEqual": true
    }
  ],
  "startsAt": "${start_time}",
  "endsAt": "${end_time}",
  "createdBy": "regression-test",
  "comment": "Test silence from regression test suite"
}
EOF
)

    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$silence_payload" \
        --max-time "${TIMEOUT}" \
        "${ALERTMANAGER_URL}/api/v2/silences" 2>/dev/null)

    local silence_id
    silence_id=$(echo "$response" | jq -r '.silenceID // ""' 2>/dev/null)

    if [[ -n "$silence_id" ]] && [[ "$silence_id" != "null" ]]; then
        log_pass "Silence created (ID: $silence_id)"

        # Now delete the silence
        local delete_status
        delete_status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
            --max-time "${TIMEOUT}" \
            "${ALERTMANAGER_URL}/api/v2/silence/${silence_id}" 2>/dev/null || echo "000")

        if [[ "$delete_status" == "200" ]]; then
            log_pass "Silence deleted successfully"
        else
            log_fail "Silence deletion failed (status: $delete_status)"
        fi
    else
        log_fail "Silence creation failed"
    fi
}

test_metrics_endpoint() {
    log_info "Testing Alertmanager metrics endpoint..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/metrics")

    if echo "$response" | grep -q "alertmanager_"; then
        log_pass "Metrics endpoint returns Alertmanager metrics"
    else
        log_fail "Metrics endpoint did not return expected metrics"
    fi
}

test_cluster_status() {
    log_info "Testing Alertmanager cluster status..."
    local response
    response=$(http_get "${ALERTMANAGER_URL}/api/v2/status")

    local cluster_status
    cluster_status=$(echo "$response" | jq -r '.cluster.status // "unknown"' 2>/dev/null)

    if [[ "$cluster_status" == "ready" ]] || [[ "$cluster_status" == "settling" ]]; then
        local peers
        peers=$(echo "$response" | jq '.cluster.peers | length' 2>/dev/null || echo "0")
        log_pass "Cluster status: $cluster_status ($peers peers)"
    elif [[ "$cluster_status" == "disabled" ]]; then
        log_skip "Clustering is disabled"
    else
        log_fail "Cluster status is: $cluster_status"
    fi
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  Alertmanager Regression Tests"
    echo "  Target: ${ALERTMANAGER_URL}"
    echo "=============================================="
    echo ""

    check_dependencies

    log_info "Checking connectivity to Alertmanager..."
    if ! curl -s --max-time 5 "${ALERTMANAGER_URL}/-/healthy" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Alertmanager at ${ALERTMANAGER_URL}"
        exit 1
    fi
    echo ""

    # Health and readiness
    test_healthy_endpoint
    test_ready_endpoint
    test_status_endpoint
    test_cluster_status
    echo ""

    # API endpoints
    test_alerts_api
    test_alert_groups_api
    test_silences_api
    test_receivers_api
    echo ""

    # Alert and silence operations
    test_post_alert
    test_silence_create_delete
    echo ""

    # Config and metrics
    test_config_reload
    test_metrics_endpoint
    echo ""

    # Summary
    echo "=============================================="
    echo "  Test Summary"
    echo "=============================================="
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo "=============================================="

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
