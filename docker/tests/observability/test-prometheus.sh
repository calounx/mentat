#!/usr/bin/env bash
#==============================================================================
# Prometheus Regression Tests
# Tests health, readiness, configuration, targets, queries, and alert rules
#==============================================================================
set -euo pipefail

# Configuration
PROMETHEUS_HOST="${PROMETHEUS_HOST:-10.10.100.10}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
PROMETHEUS_URL="http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}"
TIMEOUT="${TIMEOUT:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Make HTTP request with timeout
http_get() {
    local url="$1"
    curl -s --max-time "${TIMEOUT}" "${url}" 2>/dev/null
}

# Make HTTP request and return status code
http_status() {
    local url="$1"
    curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT}" "${url}" 2>/dev/null || echo "000"
}

# Query Prometheus
prometheus_query() {
    local query="$1"
    http_get "${PROMETHEUS_URL}/api/v1/query?query=$(echo -n "$query" | jq -sRr @uri)"
}

# Check if jq is available
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

test_health_endpoint() {
    log_info "Testing Prometheus health endpoint..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/-/healthy")

    if [[ "$response" == *"Prometheus Server is Healthy"* ]] || [[ "$response" == *"OK"* ]]; then
        log_pass "Health endpoint responds correctly"
    else
        log_fail "Health endpoint did not respond as expected: $response"
    fi
}

test_ready_endpoint() {
    log_info "Testing Prometheus ready endpoint..."
    local status
    status=$(http_status "${PROMETHEUS_URL}/-/ready")

    if [[ "$status" == "200" ]]; then
        log_pass "Ready endpoint returns 200 OK"
    else
        log_fail "Ready endpoint returned status $status (expected 200)"
    fi
}

test_configuration_valid() {
    log_info "Testing Prometheus configuration endpoint..."
    local status

    # Try the lifecycle endpoint first (requires --web.enable-lifecycle flag)
    status=$(http_status "${PROMETHEUS_URL}/-/config")

    if [[ "$status" == "200" ]]; then
        log_pass "Configuration endpoint accessible (/-/config)"
        return
    fi

    # Fallback to API v1 status/config endpoint
    status=$(http_status "${PROMETHEUS_URL}/api/v1/status/config")

    if [[ "$status" == "200" ]]; then
        log_pass "Configuration endpoint accessible (/api/v1/status/config)"
    else
        log_fail "Configuration endpoint returned status $status (tried both /-/config and /api/v1/status/config)"
    fi
}

test_config_reload_status() {
    log_info "Testing Prometheus config reload status..."
    local result
    result=$(prometheus_query "prometheus_config_last_reload_successful")

    if echo "$result" | jq -e '.data.result[0].value[1] == "1"' &>/dev/null; then
        log_pass "Configuration reload was successful"
    else
        log_fail "Configuration reload failed or metric not available"
    fi
}

test_targets_endpoint() {
    log_info "Testing Prometheus targets endpoint..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/api/v1/targets")
    local status
    status=$(echo "$response" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local active_targets
        active_targets=$(echo "$response" | jq '.data.activeTargets | length')
        log_pass "Targets endpoint accessible, found $active_targets active targets"
    else
        log_fail "Targets endpoint did not return success status"
    fi
}

test_scrape_target_up() {
    local job="$1"
    local expected_target="${2:-}"

    log_info "Testing scrape target: $job..."
    local result
    result=$(prometheus_query "up{job=\"$job\"}")
    local count
    count=$(echo "$result" | jq '.data.result | length')

    if [[ "$count" -gt 0 ]]; then
        local up_value
        up_value=$(echo "$result" | jq -r '.data.result[0].value[1]')
        if [[ "$up_value" == "1" ]]; then
            log_pass "Target $job is UP"
        else
            log_fail "Target $job is DOWN (up=0)"
        fi
    else
        log_fail "Target $job not found in scrape targets"
    fi
}

test_landsraad_exporters() {
    log_info "Testing landsraad_tst exporter targets..."

    # Node Exporter - job name: vpsmanager-node
    local result
    result=$(prometheus_query 'up{job="vpsmanager-node"}')
    local count
    count=$(echo "$result" | jq '.data.result | length')
    if [[ "$count" -gt 0 ]]; then
        local up_value
        up_value=$(echo "$result" | jq -r '.data.result[0].value[1]')
        if [[ "$up_value" == "1" ]]; then
            log_pass "Node Exporter target for landsraad_tst is UP"
        else
            log_fail "Node Exporter target for landsraad_tst is DOWN"
        fi
    else
        log_skip "Node Exporter target for landsraad_tst not found (may not be deployed)"
    fi

    # Nginx Exporter - job name: vpsmanager-nginx
    result=$(prometheus_query 'up{job="vpsmanager-nginx"}')
    count=$(echo "$result" | jq '.data.result | length')
    if [[ "$count" -gt 0 ]]; then
        local up_value
        up_value=$(echo "$result" | jq -r '.data.result[0].value[1]')
        if [[ "$up_value" == "1" ]]; then
            log_pass "Nginx Exporter target for landsraad_tst is UP"
        else
            log_fail "Nginx Exporter target for landsraad_tst is DOWN"
        fi
    else
        log_skip "Nginx Exporter target for landsraad_tst not found (may not be deployed)"
    fi

    # MySQL Exporter - job name: vpsmanager-mysql
    result=$(prometheus_query 'up{job="vpsmanager-mysql"}')
    count=$(echo "$result" | jq '.data.result | length')
    if [[ "$count" -gt 0 ]]; then
        local up_value
        up_value=$(echo "$result" | jq -r '.data.result[0].value[1]')
        if [[ "$up_value" == "1" ]]; then
            log_pass "MySQL Exporter target for landsraad_tst is UP"
        else
            log_fail "MySQL Exporter target for landsraad_tst is DOWN"
        fi
    else
        log_skip "MySQL Exporter target for landsraad_tst not found (may not be deployed)"
    fi

    # PHP-FPM Exporter - job name: vpsmanager-phpfpm
    result=$(prometheus_query 'up{job="vpsmanager-phpfpm"}')
    count=$(echo "$result" | jq '.data.result | length')
    if [[ "$count" -gt 0 ]]; then
        local up_value
        up_value=$(echo "$result" | jq -r '.data.result[0].value[1]')
        if [[ "$up_value" == "1" ]]; then
            log_pass "PHP-FPM Exporter target for landsraad_tst is UP"
        else
            log_fail "PHP-FPM Exporter target for landsraad_tst is DOWN"
        fi
    else
        log_skip "PHP-FPM Exporter target for landsraad_tst not found (may not be deployed)"
    fi
}

test_query_up_metric() {
    log_info "Testing query for 'up' metric..."
    local result
    result=$(prometheus_query "up")
    local status
    status=$(echo "$result" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$result" | jq '.data.result | length')
        if [[ "$count" -gt 0 ]]; then
            log_pass "Query for 'up' metric returned $count results"
        else
            log_fail "Query for 'up' metric returned no results"
        fi
    else
        log_fail "Query for 'up' metric failed"
    fi
}

test_query_node_metrics() {
    log_info "Testing query for node_* metrics..."
    local result
    result=$(prometheus_query 'count({__name__=~"node_.*"})')
    local status
    status=$(echo "$result" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$result" | jq -r '.data.result[0].value[1] // "0"')
        if [[ "$count" -gt 0 ]]; then
            log_pass "Found $count node_* metric series"
        else
            log_skip "No node_* metrics found (node_exporter may not be running)"
        fi
    else
        log_fail "Query for node_* metrics failed"
    fi
}

test_query_prometheus_metrics() {
    log_info "Testing query for prometheus_* metrics..."
    local result
    result=$(prometheus_query 'count({__name__=~"prometheus_.*"})')
    local status
    status=$(echo "$result" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$result" | jq -r '.data.result[0].value[1] // "0"')
        if [[ "$count" -gt 0 ]]; then
            log_pass "Found $count prometheus_* metric series"
        else
            log_fail "No prometheus_* metrics found"
        fi
    else
        log_fail "Query for prometheus_* metrics failed"
    fi
}

test_alert_rules_loaded() {
    log_info "Testing alert rules are loaded..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/api/v1/rules")
    local status
    status=$(echo "$response" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local groups
        groups=$(echo "$response" | jq '.data.groups | length')
        local rules
        rules=$(echo "$response" | jq '[.data.groups[].rules[]] | length')

        if [[ "$groups" -gt 0 ]]; then
            log_pass "Alert rules loaded: $groups groups, $rules total rules"
        else
            log_skip "No alert rule groups found (may be intentional)"
        fi
    else
        log_fail "Failed to query alert rules"
    fi
}

test_recording_rules() {
    log_info "Testing recording rules..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/api/v1/rules?type=record")
    local status
    status=$(echo "$response" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local rules
        rules=$(echo "$response" | jq '[.data.groups[].rules[] | select(.type == "recording")] | length')

        if [[ "$rules" -gt 0 ]]; then
            log_pass "Found $rules recording rules"
        else
            log_skip "No recording rules found (may be intentional)"
        fi
    else
        log_fail "Failed to query recording rules"
    fi
}

test_alert_rules_evaluation() {
    log_info "Testing alert rules evaluation metrics..."
    local result
    result=$(prometheus_query "prometheus_rule_evaluation_failures_total")
    local status
    status=$(echo "$result" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local failures
        failures=$(echo "$result" | jq -r '.data.result[0].value[1] // "0"')
        if [[ "$failures" == "0" ]]; then
            log_pass "No rule evaluation failures detected"
        else
            log_fail "Found $failures rule evaluation failures"
        fi
    else
        log_skip "Could not check rule evaluation failures"
    fi
}

test_tsdb_status() {
    log_info "Testing TSDB status endpoint..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/api/v1/status/tsdb")
    local status
    status=$(echo "$response" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local num_series
        num_series=$(echo "$response" | jq -r '.data.headStats.numSeries // "unknown"')
        log_pass "TSDB status accessible, $num_series active series"
    else
        log_fail "TSDB status endpoint failed"
    fi
}

test_build_info() {
    log_info "Testing Prometheus build info..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/api/v1/status/buildinfo")
    local status
    status=$(echo "$response" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local version
        version=$(echo "$response" | jq -r '.data.version // "unknown"')
        log_pass "Prometheus version: $version"
    else
        log_fail "Could not get Prometheus build info"
    fi
}

test_runtime_info() {
    log_info "Testing Prometheus runtime info..."
    local response
    response=$(http_get "${PROMETHEUS_URL}/api/v1/status/runtimeinfo")
    local status
    status=$(echo "$response" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local uptime
        uptime=$(echo "$response" | jq -r '.data.storageRetention // "unknown"')
        log_pass "Prometheus runtime info accessible (retention: $uptime)"
    else
        log_fail "Could not get Prometheus runtime info"
    fi
}

test_alertmanager_discovery() {
    log_info "Testing Alertmanager discovery..."
    local result
    result=$(prometheus_query "prometheus_notifications_alertmanagers_discovered")
    local status
    status=$(echo "$result" | jq -r '.status // "error"')

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$result" | jq -r '.data.result[0].value[1] // "0"')
        if [[ "$count" -gt 0 ]]; then
            log_pass "Discovered $count Alertmanager(s)"
        else
            log_skip "No Alertmanager discovered (may not be configured)"
        fi
    else
        log_skip "Could not check Alertmanager discovery"
    fi
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  Prometheus Regression Tests"
    echo "  Target: ${PROMETHEUS_URL}"
    echo "=============================================="
    echo ""

    check_dependencies

    # Connectivity check
    log_info "Checking connectivity to Prometheus..."
    if ! curl -s --max-time 5 "${PROMETHEUS_URL}/-/healthy" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Prometheus at ${PROMETHEUS_URL}"
        echo "Make sure Prometheus is running and accessible."
        exit 1
    fi
    echo ""

    # Health and readiness
    test_health_endpoint
    test_ready_endpoint
    echo ""

    # Configuration
    test_configuration_valid
    test_config_reload_status
    test_build_info
    test_runtime_info
    echo ""

    # Targets and scraping
    test_targets_endpoint
    test_scrape_target_up "prometheus"
    test_landsraad_exporters
    echo ""

    # Queries
    test_query_up_metric
    test_query_node_metrics
    test_query_prometheus_metrics
    test_tsdb_status
    echo ""

    # Alert and recording rules
    test_alert_rules_loaded
    test_recording_rules
    test_alert_rules_evaluation
    test_alertmanager_discovery
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
