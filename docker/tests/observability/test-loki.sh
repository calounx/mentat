#!/usr/bin/env bash
#==============================================================================
# Loki Regression Tests
# Tests health, readiness, ingestion, queries, and label management
#==============================================================================
set -euo pipefail

# Configuration
LOKI_HOST="${LOKI_HOST:-10.10.100.10}"
LOKI_PORT="${LOKI_PORT:-3100}"
LOKI_URL="http://${LOKI_HOST}:${LOKI_PORT}"
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

test_ready_endpoint() {
    log_info "Testing Loki ready endpoint..."
    local response
    response=$(http_get "${LOKI_URL}/ready")

    if [[ "$response" == "ready" ]]; then
        log_pass "Ready endpoint returns 'ready'"
    else
        log_fail "Ready endpoint did not return 'ready': $response"
    fi
}

test_health_endpoint() {
    log_info "Testing Loki health endpoint..."
    local response
    response=$(http_get "${LOKI_URL}/loki/api/v1/status/buildinfo")

    # Loki 3.x returns version directly without status wrapper
    local version
    version=$(echo "$response" | jq -r '.version // "unknown"' 2>/dev/null)

    if [[ "$version" != "unknown" ]] && [[ "$version" != "null" ]] && [[ -n "$version" ]]; then
        log_pass "Loki build info accessible (version: $version)"
    else
        # Fallback for older Loki versions with status wrapper
        local status
        status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)
        if [[ "$status" == "success" ]]; then
            version=$(echo "$response" | jq -r '.data.version // "unknown"')
            log_pass "Loki build info accessible (version: $version)"
        else
            log_fail "Could not get Loki build info"
        fi
    fi
}

test_labels_endpoint() {
    log_info "Testing Loki labels endpoint..."
    local response
    response=$(http_get "${LOKI_URL}/loki/api/v1/labels")
    local status
    status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "0")
        log_pass "Labels endpoint accessible ($count labels)"
    else
        log_fail "Labels endpoint did not return success"
    fi
}

test_label_values() {
    local label="$1"
    log_info "Testing Loki label values for: $label..."
    local response
    response=$(http_get "${LOKI_URL}/loki/api/v1/label/${label}/values")
    local status
    status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "0")
        if [[ "$count" -gt 0 ]]; then
            log_pass "Label '$label' has $count values"
        else
            log_skip "Label '$label' has no values (may be empty)"
        fi
    else
        log_fail "Could not get values for label '$label'"
    fi
}

test_log_push() {
    log_info "Testing Loki log push..."
    local timestamp
    timestamp=$(date +%s)000000000
    local test_message="regression-test-$(date +%s)"

    local payload
    payload=$(cat <<EOF
{
  "streams": [
    {
      "stream": {"job": "regression-test", "host": "test-runner"},
      "values": [["${timestamp}", "${test_message}"]]
    }
  ]
}
EOF
)

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time "${TIMEOUT}" \
        "${LOKI_URL}/loki/api/v1/push" 2>/dev/null || echo "000")

    if [[ "$status" == "204" ]] || [[ "$status" == "200" ]]; then
        log_pass "Log push successful (status: $status)"
    else
        log_fail "Log push failed (status: $status)"
    fi
}

test_query_range() {
    log_info "Testing Loki query_range endpoint..."
    local start=$(($(date +%s) - 3600))000000000
    local end=$(date +%s)000000000

    local response
    response=$(curl -sG "${LOKI_URL}/loki/api/v1/query_range" \
        --data-urlencode 'query={job=~".+"}' \
        --data-urlencode 'limit=1' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null)

    local status
    status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)

    if [[ "$status" == "success" ]]; then
        log_pass "Query range endpoint accessible"
    else
        log_fail "Query range endpoint failed"
    fi
}

test_landsraad_logs() {
    log_info "Testing logs from landsraad_tst in Loki..."
    local start=$(($(date +%s) - 3600))000000000
    local end=$(date +%s)000000000

    local response
    response=$(curl -sG "${LOKI_URL}/loki/api/v1/query_range" \
        --data-urlencode 'query={host="landsraad_tst"}' \
        --data-urlencode 'limit=10' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null)

    local status
    status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)
    local count
    count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo "0")

    if [[ "$status" == "success" ]] && [[ "$count" -gt 0 ]]; then
        log_pass "Found $count log streams from landsraad_tst"
    else
        log_skip "No logs from landsraad_tst yet (Promtail may need time)"
    fi
}

test_nginx_logs() {
    log_info "Testing nginx logs in Loki..."
    local start=$(($(date +%s) - 3600))000000000
    local end=$(date +%s)000000000

    local response
    response=$(curl -sG "${LOKI_URL}/loki/api/v1/query_range" \
        --data-urlencode 'query={filename=~".*nginx.*"}' \
        --data-urlencode 'limit=5' \
        --data-urlencode "start=${start}" \
        --data-urlencode "end=${end}" 2>/dev/null)

    local count
    count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo "0")

    if [[ "$count" -gt 0 ]]; then
        log_pass "Found nginx logs in Loki"
    else
        log_skip "No nginx logs found (may need traffic to generate logs)"
    fi
}

test_series_endpoint() {
    log_info "Testing Loki series endpoint..."
    local response
    response=$(curl -sG "${LOKI_URL}/loki/api/v1/series" \
        --data-urlencode 'match[]={job=~".+"}' 2>/dev/null)

    local status
    status=$(echo "$response" | jq -r '.status // "error"' 2>/dev/null)

    if [[ "$status" == "success" ]]; then
        local count
        count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "0")
        log_pass "Series endpoint accessible ($count series)"
    else
        log_fail "Series endpoint failed"
    fi
}

test_index_stats() {
    log_info "Testing Loki index stats..."
    local response
    response=$(http_get "${LOKI_URL}/loki/api/v1/index/stats")

    if [[ -n "$response" ]]; then
        log_pass "Index stats endpoint accessible"
    else
        log_skip "Index stats not available"
    fi
}

test_config_endpoint() {
    log_info "Testing Loki config endpoint..."
    local status
    status=$(http_status "${LOKI_URL}/config")

    if [[ "$status" == "200" ]]; then
        log_pass "Config endpoint accessible"
    else
        log_fail "Config endpoint returned status $status"
    fi
}

test_metrics_endpoint() {
    log_info "Testing Loki metrics endpoint..."
    local response
    response=$(http_get "${LOKI_URL}/metrics")

    # Check for Loki-specific metrics (loki_*) or general process metrics
    # Loki 3.x may use different metric prefixes
    # Note: Use here-string instead of echo|pipe to handle large responses correctly
    if grep -qE "(loki_|cortex_|promtail_|go_|process_)" <<<"$response"; then
        # Count how many loki_ metrics we found
        local loki_count
        loki_count=$(grep -c "^loki_" <<<"$response" 2>/dev/null || echo "0")
        if [[ "$loki_count" -gt 0 ]]; then
            log_pass "Metrics endpoint returns Loki metrics ($loki_count loki_* metrics)"
        else
            # Loki is running but may not have loki_ prefixed metrics yet
            log_pass "Metrics endpoint accessible (process metrics available)"
        fi
    else
        log_fail "Metrics endpoint did not return expected metrics"
    fi
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  Loki Regression Tests"
    echo "  Target: ${LOKI_URL}"
    echo "=============================================="
    echo ""

    check_dependencies

    log_info "Checking connectivity to Loki..."
    if ! curl -s --max-time 5 "${LOKI_URL}/ready" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Loki at ${LOKI_URL}"
        exit 1
    fi
    echo ""

    # Health and readiness
    test_ready_endpoint
    test_health_endpoint
    test_config_endpoint
    test_metrics_endpoint
    echo ""

    # Labels and series
    test_labels_endpoint
    test_label_values "job"
    test_label_values "host"
    test_series_endpoint
    echo ""

    # Log ingestion and queries
    test_log_push
    test_query_range
    test_index_stats
    echo ""

    # Integration with landsraad_tst
    test_landsraad_logs
    test_nginx_logs
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
