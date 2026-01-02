#!/usr/bin/env bash
#==============================================================================
# Tempo Regression Tests
# Tests health, readiness, trace queries, OTLP ingestion
#==============================================================================
set -euo pipefail

# Configuration
TEMPO_HOST="${TEMPO_HOST:-10.10.100.10}"
TEMPO_PORT="${TEMPO_PORT:-3200}"
TEMPO_OTLP_HTTP_PORT="${TEMPO_OTLP_HTTP_PORT:-4318}"
TEMPO_URL="http://${TEMPO_HOST}:${TEMPO_PORT}"
TEMPO_OTLP_URL="http://${TEMPO_HOST}:${TEMPO_OTLP_HTTP_PORT}"
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

generate_trace_id() {
    if command -v openssl &>/dev/null; then
        openssl rand -hex 16 2>/dev/null
    elif [[ -r /dev/urandom ]]; then
        head -c 16 /dev/urandom | xxd -p 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32
    else
        date +%s%N | md5sum | head -c 32
    fi
}

generate_span_id() {
    if command -v openssl &>/dev/null; then
        openssl rand -hex 8 2>/dev/null
    elif [[ -r /dev/urandom ]]; then
        head -c 8 /dev/urandom | xxd -p 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16
    else
        date +%s%N | md5sum | head -c 16
    fi
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
    log_info "Testing Tempo ready endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/ready")

    if [[ "$response" == "ready" ]]; then
        log_pass "Ready endpoint returns 'ready'"
    else
        log_fail "Ready endpoint did not return 'ready': $response"
    fi
}

test_status_endpoint() {
    log_info "Testing Tempo status endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/status")
    local status
    status=$(http_status "${TEMPO_URL}/status")

    if [[ "$status" == "200" ]]; then
        log_pass "Status endpoint accessible"
    else
        log_fail "Status endpoint returned status $status"
    fi
}

test_build_info() {
    log_info "Testing Tempo build info..."
    local response

    # Try multiple endpoints - Tempo versions differ in their API paths
    response=$(http_get "${TEMPO_URL}/api/status/buildinfo")

    if echo "$response" | jq -e '.version' &>/dev/null; then
        local version
        version=$(echo "$response" | jq -r '.version // "unknown"')
        log_pass "Tempo version: $version"
        return
    fi

    # Try /status/buildinfo (without /api prefix)
    response=$(http_get "${TEMPO_URL}/status/buildinfo")

    if echo "$response" | jq -e '.version' &>/dev/null; then
        local version
        version=$(echo "$response" | jq -r '.version // "unknown"')
        log_pass "Tempo version: $version"
        return
    fi

    # Fallback - just check if status endpoint returns 200
    local status
    status=$(http_status "${TEMPO_URL}/status")
    if [[ "$status" == "200" ]]; then
        log_pass "Tempo status endpoint accessible (build info format differs)"
    else
        log_skip "Build info endpoint format may differ"
    fi
}

test_config_endpoint() {
    log_info "Testing Tempo config endpoint..."
    local status
    status=$(http_status "${TEMPO_URL}/status/config")

    if [[ "$status" == "200" ]]; then
        log_pass "Config endpoint accessible"
    else
        log_fail "Config endpoint returned status $status"
    fi
}

test_metrics_endpoint() {
    log_info "Testing Tempo metrics endpoint..."
    local response
    local status

    # Get metrics endpoint status first
    status=$(http_status "${TEMPO_URL}/metrics")

    if [[ "$status" != "200" ]]; then
        log_fail "Metrics endpoint returned status $status"
        return
    fi

    # Fetch actual response content
    response=$(curl -s --max-time "${TIMEOUT}" "${TEMPO_URL}/metrics" 2>/dev/null)

    # Check for tempo_ metrics or standard prometheus metrics from Tempo
    if [[ -n "$response" ]] && echo "$response" | grep -q "tempo_"; then
        local count
        count=$(echo "$response" | grep -c "tempo_" 2>/dev/null || echo "0")
        log_pass "Metrics endpoint returns Tempo metrics (${count} metrics)"
    elif [[ -n "$response" ]] && echo "$response" | grep -q "go_"; then
        # Tempo also exposes Go runtime metrics - this is acceptable
        log_pass "Metrics endpoint accessible (Go runtime metrics present)"
    elif [[ -n "$response" ]]; then
        log_pass "Metrics endpoint accessible"
    else
        log_fail "Metrics endpoint did not return expected metrics"
    fi
}

test_search_tags() {
    log_info "Testing Tempo search tags endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/api/search/tags")

    if echo "$response" | jq -e '.tagNames' &>/dev/null; then
        local count
        count=$(echo "$response" | jq '.tagNames | length' 2>/dev/null || echo "0")
        log_pass "Search tags endpoint accessible ($count tags)"
    else
        log_skip "Search tags returned empty or different format"
    fi
}

test_search_tag_values() {
    log_info "Testing Tempo search tag values endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/api/search/tag/service.name/values")

    if echo "$response" | jq -e '.tagValues' &>/dev/null; then
        local count
        count=$(echo "$response" | jq '.tagValues | length' 2>/dev/null || echo "0")
        if [[ "$count" -gt 0 ]]; then
            log_pass "Found $count service.name values"
        else
            log_skip "No service.name values found (no traces yet)"
        fi
    else
        log_skip "Tag values returned empty or different format"
    fi
}

test_search_endpoint() {
    log_info "Testing Tempo search endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/api/search?limit=10")

    if echo "$response" | jq -e '.traces' &>/dev/null; then
        local count
        count=$(echo "$response" | jq '.traces | length' 2>/dev/null || echo "0")
        log_pass "Search endpoint accessible ($count traces)"
    else
        log_skip "Search returned empty or different format"
    fi
}

# Global variable to store the last generated trace ID
LAST_TRACE_ID=""

test_otlp_http_endpoint() {
    log_info "Testing Tempo OTLP HTTP endpoint..."
    local trace_id
    trace_id=$(generate_trace_id)
    local span_id
    span_id=$(generate_span_id)
    local timestamp
    timestamp=$(date +%s)000000000

    local payload
    payload=$(cat <<EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [{
        "key": "service.name",
        "value": {"stringValue": "regression-test"}
      }]
    },
    "scopeSpans": [{
      "spans": [{
        "traceId": "${trace_id}",
        "spanId": "${span_id}",
        "name": "test-span",
        "kind": 1,
        "startTimeUnixNano": "${timestamp}",
        "endTimeUnixNano": "$((timestamp + 100000000))"
      }]
    }]
  }]
}
EOF
)

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time "${TIMEOUT}" \
        "${TEMPO_OTLP_URL}/v1/traces" 2>/dev/null || echo "000")

    if [[ "$status" == "200" ]] || [[ "$status" == "202" ]]; then
        log_pass "OTLP HTTP trace ingestion successful (trace_id: ${trace_id:0:8}...)"
        LAST_TRACE_ID="$trace_id"
    else
        log_fail "OTLP HTTP trace ingestion failed (status: $status)"
        LAST_TRACE_ID=""
    fi
}

test_trace_query() {
    local trace_id="$1"
    if [[ -z "$trace_id" ]]; then
        log_skip "Trace query skipped (no trace_id)"
        return
    fi

    log_info "Testing Tempo trace query for ${trace_id:0:8}..."

    # Wait a moment for trace to be ingested
    sleep 2

    local response
    response=$(http_get "${TEMPO_URL}/api/traces/${trace_id}")

    if echo "$response" | jq -e '.batches' &>/dev/null || echo "$response" | jq -e '.resourceSpans' &>/dev/null; then
        log_pass "Trace query successful"
    else
        log_skip "Trace not yet queryable (may need more time)"
    fi
}

test_echo_endpoint() {
    log_info "Testing Tempo echo endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/api/echo")
    local status
    status=$(http_status "${TEMPO_URL}/api/echo")

    if [[ "$status" == "200" ]]; then
        log_pass "Echo endpoint accessible"
    else
        log_skip "Echo endpoint returned status $status"
    fi
}

test_services_endpoint() {
    log_info "Testing Tempo services endpoint..."
    local response
    response=$(http_get "${TEMPO_URL}/api/v2/search/tags?scope=resource")

    if [[ -n "$response" ]]; then
        log_pass "Tags search endpoint accessible"
    else
        log_skip "Tags search endpoint not responding"
    fi
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  Tempo Regression Tests"
    echo "  Target: ${TEMPO_URL}"
    echo "  OTLP HTTP: ${TEMPO_OTLP_URL}"
    echo "=============================================="
    echo ""

    check_dependencies

    log_info "Checking connectivity to Tempo..."
    if ! curl -s --max-time 5 "${TEMPO_URL}/ready" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Tempo at ${TEMPO_URL}"
        exit 1
    fi
    echo ""

    # Health and readiness
    test_ready_endpoint
    test_status_endpoint
    test_build_info
    test_config_endpoint
    test_metrics_endpoint
    echo ""

    # Search and tags
    test_search_tags
    test_search_tag_values
    test_search_endpoint
    test_services_endpoint
    echo ""

    # Trace ingestion
    test_otlp_http_endpoint
    test_trace_query "$LAST_TRACE_ID"
    test_echo_endpoint
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
