#!/usr/bin/env bash
#==============================================================================
# Grafana Regression Tests
# Tests health, login, datasources, queries, and dashboards
#==============================================================================
set -euo pipefail

# Configuration
GRAFANA_HOST="${GRAFANA_HOST:-10.10.100.10}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_URL="http://${GRAFANA_HOST}:${GRAFANA_PORT}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
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

# Make authenticated HTTP request
http_get_auth() {
    local url="$1"
    curl -s --max-time "${TIMEOUT}" -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${url}" 2>/dev/null
}

# Make authenticated POST request
http_post_auth() {
    local url="$1"
    local data="$2"
    curl -s --max-time "${TIMEOUT}" -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -X POST -d "${data}" "${url}" 2>/dev/null
}

# Make HTTP request and return status code
http_status() {
    local url="$1"
    curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT}" "${url}" 2>/dev/null || echo "000"
}

# Make authenticated HTTP request and return status code
http_status_auth() {
    local url="$1"
    curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT}" \
        -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" "${url}" 2>/dev/null || echo "000"
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
    log_info "Testing Grafana health endpoint..."
    local response
    response=$(http_get "${GRAFANA_URL}/api/health")
    local database
    database=$(echo "$response" | jq -r '.database // "error"')

    if [[ "$database" == "ok" ]]; then
        log_pass "Health endpoint reports database OK"
    else
        log_fail "Health endpoint did not report database OK: $response"
    fi
}

test_api_health() {
    log_info "Testing Grafana API health..."
    local status
    status=$(http_status "${GRAFANA_URL}/api/health")

    if [[ "$status" == "200" ]]; then
        log_pass "API health returns 200 OK"
    else
        log_fail "API health returned status $status (expected 200)"
    fi
}

test_login_page() {
    log_info "Testing Grafana login page accessible..."
    local status
    status=$(http_status "${GRAFANA_URL}/login")

    if [[ "$status" == "200" ]]; then
        log_pass "Login page accessible (200 OK)"
    else
        log_fail "Login page returned status $status"
    fi
}

test_admin_login() {
    log_info "Testing admin login with credentials..."
    local response
    response=$(http_post_auth "${GRAFANA_URL}/api/login/ping" "{}")
    local status
    status=$(http_status_auth "${GRAFANA_URL}/api/login/ping")

    # Grafana returns 401 for invalid creds, 200 for valid
    if [[ "$status" == "200" ]]; then
        log_pass "Admin login successful"
    elif [[ "$status" == "401" ]]; then
        log_fail "Admin login failed - invalid credentials"
    else
        log_fail "Admin login returned unexpected status $status"
    fi
}

test_current_user() {
    log_info "Testing current user API..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/user")
    local login
    login=$(echo "$response" | jq -r '.login // "error"')

    if [[ "$login" == "${GRAFANA_USER}" ]]; then
        log_pass "Current user API returns correct user: $login"
    elif [[ "$login" == "error" ]]; then
        log_fail "Could not get current user info"
    else
        log_pass "Current user API accessible (logged in as: $login)"
    fi
}

test_datasources_configured() {
    log_info "Testing datasources are configured..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        if [[ "$count" -gt 0 ]]; then
            log_pass "Found $count datasource(s) configured"
        else
            log_fail "No datasources configured"
        fi
    else
        log_fail "Could not retrieve datasources: $response"
    fi
}

test_prometheus_datasource() {
    log_info "Testing Prometheus datasource..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    if echo "$response" | jq -e '.[] | select(.type == "prometheus")' &>/dev/null; then
        local name
        name=$(echo "$response" | jq -r '.[] | select(.type == "prometheus") | .name' | head -1)
        log_pass "Prometheus datasource found: $name"
    else
        log_fail "No Prometheus datasource configured"
    fi
}

test_loki_datasource() {
    log_info "Testing Loki datasource..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    if echo "$response" | jq -e '.[] | select(.type == "loki")' &>/dev/null; then
        local name
        name=$(echo "$response" | jq -r '.[] | select(.type == "loki") | .name' | head -1)
        log_pass "Loki datasource found: $name"
    else
        log_skip "No Loki datasource configured"
    fi
}

test_tempo_datasource() {
    log_info "Testing Tempo datasource..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    if echo "$response" | jq -e '.[] | select(.type == "tempo")' &>/dev/null; then
        local name
        name=$(echo "$response" | jq -r '.[] | select(.type == "tempo") | .name' | head -1)
        log_pass "Tempo datasource found: $name"
    else
        log_skip "No Tempo datasource configured"
    fi
}

test_alertmanager_datasource() {
    log_info "Testing Alertmanager datasource..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    if echo "$response" | jq -e '.[] | select(.type == "alertmanager")' &>/dev/null; then
        local name
        name=$(echo "$response" | jq -r '.[] | select(.type == "alertmanager") | .name' | head -1)
        log_pass "Alertmanager datasource found: $name"
    else
        log_skip "No Alertmanager datasource configured"
    fi
}

test_prometheus_datasource_health() {
    log_info "Testing Prometheus datasource health check..."
    local datasources
    datasources=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    local ds_uid
    ds_uid=$(echo "$datasources" | jq -r '.[] | select(.type == "prometheus") | .uid' | head -1)

    if [[ -n "$ds_uid" && "$ds_uid" != "null" ]]; then
        local health
        health=$(http_get_auth "${GRAFANA_URL}/api/datasources/uid/${ds_uid}/health")
        local status
        status=$(echo "$health" | jq -r '.status // "error"')

        if [[ "$status" == "OK" ]]; then
            log_pass "Prometheus datasource health check passed"
        else
            log_fail "Prometheus datasource health check failed: $status"
        fi
    else
        log_skip "Cannot test Prometheus datasource health - datasource not found"
    fi
}

test_loki_datasource_health() {
    log_info "Testing Loki datasource health check..."
    local datasources
    datasources=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    local ds_uid
    ds_uid=$(echo "$datasources" | jq -r '.[] | select(.type == "loki") | .uid' | head -1)

    if [[ -n "$ds_uid" && "$ds_uid" != "null" ]]; then
        local health
        health=$(http_get_auth "${GRAFANA_URL}/api/datasources/uid/${ds_uid}/health")
        local status
        status=$(echo "$health" | jq -r '.status // "error"')

        if [[ "$status" == "OK" ]]; then
            log_pass "Loki datasource health check passed"
        else
            log_fail "Loki datasource health check failed: $status"
        fi
    else
        log_skip "Cannot test Loki datasource health - datasource not found"
    fi
}

test_query_prometheus_via_grafana() {
    log_info "Testing Prometheus query via Grafana..."
    local datasources
    datasources=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    local ds_uid
    ds_uid=$(echo "$datasources" | jq -r '.[] | select(.type == "prometheus") | .uid' | head -1)

    if [[ -n "$ds_uid" && "$ds_uid" != "null" ]]; then
        local query_data
        query_data=$(cat <<EOF
{
    "queries": [
        {
            "refId": "A",
            "datasource": {"uid": "${ds_uid}", "type": "prometheus"},
            "expr": "up",
            "instant": true
        }
    ],
    "from": "now-5m",
    "to": "now"
}
EOF
)
        local result
        result=$(http_post_auth "${GRAFANA_URL}/api/ds/query" "$query_data")
        local status
        status=$(echo "$result" | jq -r '.results.A.status // "error"')

        if [[ "$status" == "200" ]] || echo "$result" | jq -e '.results.A.frames' &>/dev/null; then
            log_pass "Prometheus query via Grafana successful"
        else
            log_fail "Prometheus query via Grafana failed"
        fi
    else
        log_skip "Cannot query Prometheus via Grafana - datasource not found"
    fi
}

test_query_loki_via_grafana() {
    log_info "Testing Loki query via Grafana..."
    local datasources
    datasources=$(http_get_auth "${GRAFANA_URL}/api/datasources")

    local ds_uid
    ds_uid=$(echo "$datasources" | jq -r '.[] | select(.type == "loki") | .uid' | head -1)

    if [[ -n "$ds_uid" && "$ds_uid" != "null" ]]; then
        local query_data
        query_data=$(cat <<EOF
{
    "queries": [
        {
            "refId": "A",
            "datasource": {"uid": "${ds_uid}", "type": "loki"},
            "expr": "{job=~\".+\"}",
            "queryType": "range"
        }
    ],
    "from": "now-1h",
    "to": "now"
}
EOF
)
        local result
        result=$(http_post_auth "${GRAFANA_URL}/api/ds/query" "$query_data")

        # Loki query may return empty results but should not error
        if echo "$result" | jq -e '.results.A' &>/dev/null; then
            log_pass "Loki query via Grafana successful"
        else
            log_fail "Loki query via Grafana failed"
        fi
    else
        log_skip "Cannot query Loki via Grafana - datasource not found"
    fi
}

test_dashboards_accessible() {
    log_info "Testing dashboards are accessible..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/search?type=dash-db")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        if [[ "$count" -gt 0 ]]; then
            log_pass "Found $count dashboard(s)"
        else
            log_skip "No dashboards found (may not be provisioned yet)"
        fi
    else
        log_fail "Could not retrieve dashboards: $response"
    fi
}

test_dashboard_home() {
    log_info "Testing home dashboard..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/dashboards/home")
    local id
    id=$(echo "$response" | jq -r '.dashboard.id // "null"')

    if [[ "$id" != "null" ]]; then
        log_pass "Home dashboard accessible"
    else
        log_skip "No home dashboard configured"
    fi
}

test_folders_accessible() {
    log_info "Testing folders API..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/folders")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        log_pass "Folders API accessible, found $count folder(s)"
    else
        log_fail "Could not retrieve folders"
    fi
}

test_org_info() {
    log_info "Testing organization info..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/org")
    local name
    name=$(echo "$response" | jq -r '.name // "error"')

    if [[ "$name" != "error" ]]; then
        log_pass "Organization info accessible: $name"
    else
        log_fail "Could not retrieve organization info"
    fi
}

test_frontend_settings() {
    log_info "Testing frontend settings..."
    local response
    # Frontend settings requires authentication in newer Grafana versions
    response=$(http_get_auth "${GRAFANA_URL}/api/frontend/settings")

    if echo "$response" | jq -e '.buildInfo' &>/dev/null; then
        local version
        version=$(echo "$response" | jq -r '.buildInfo.version // "unknown"')
        log_pass "Frontend settings accessible (Grafana version: $version)"
    else
        log_fail "Could not retrieve frontend settings"
    fi
}

test_alerting_rules() {
    log_info "Testing Grafana alerting rules..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/v1/provisioning/alert-rules")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        log_pass "Alerting rules API accessible, found $count rule(s)"
    else
        # Grafana 8+ uses different endpoint
        local status
        status=$(http_status_auth "${GRAFANA_URL}/api/v1/provisioning/alert-rules")
        if [[ "$status" == "200" ]]; then
            log_pass "Alerting rules API accessible"
        else
            log_skip "Alerting rules API not available (may be older Grafana version)"
        fi
    fi
}

test_annotations() {
    log_info "Testing annotations API..."
    local response
    response=$(http_get_auth "${GRAFANA_URL}/api/annotations?from=now-1h&to=now")

    if echo "$response" | jq -e 'type == "array"' &>/dev/null; then
        local count
        count=$(echo "$response" | jq 'length')
        log_pass "Annotations API accessible, found $count annotation(s)"
    else
        log_fail "Could not retrieve annotations"
    fi
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo "  Grafana Regression Tests"
    echo "  Target: ${GRAFANA_URL}"
    echo "=============================================="
    echo ""

    check_dependencies

    # Connectivity check
    log_info "Checking connectivity to Grafana..."
    if ! curl -s --max-time 5 "${GRAFANA_URL}/api/health" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Cannot connect to Grafana at ${GRAFANA_URL}"
        echo "Make sure Grafana is running and accessible."
        exit 1
    fi
    echo ""

    # Health and API
    test_health_endpoint
    test_api_health
    test_frontend_settings
    echo ""

    # Authentication
    test_login_page
    test_admin_login
    test_current_user
    test_org_info
    echo ""

    # Datasources
    test_datasources_configured
    test_prometheus_datasource
    test_loki_datasource
    test_tempo_datasource
    test_alertmanager_datasource
    echo ""

    # Datasource health
    test_prometheus_datasource_health
    test_loki_datasource_health
    echo ""

    # Queries
    test_query_prometheus_via_grafana
    test_query_loki_via_grafana
    echo ""

    # Dashboards
    test_dashboards_accessible
    test_dashboard_home
    test_folders_accessible
    echo ""

    # Alerting
    test_alerting_rules
    test_annotations
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
