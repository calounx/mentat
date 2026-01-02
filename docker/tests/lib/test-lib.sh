#!/usr/bin/env bash
# ============================================================================
# Integration Test Library
# ============================================================================
# Shared functions for CHOM integration tests
#
# Usage: source this file in test scripts
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-lib.sh"
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# Test environment configuration
export MENTAT_IP="${MENTAT_IP:-10.10.100.10}"
export LANDSRAAD_IP="${LANDSRAAD_IP:-10.10.100.20}"

# Service ports on mentat_tst (Observability)
export PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
export GRAFANA_PORT="${GRAFANA_PORT:-3000}"
export LOKI_PORT="${LOKI_PORT:-3100}"
export TEMPO_PORT="${TEMPO_PORT:-3200}"
export TEMPO_OTLP_GRPC_PORT="${TEMPO_OTLP_GRPC_PORT:-4317}"
export TEMPO_OTLP_HTTP_PORT="${TEMPO_OTLP_HTTP_PORT:-4318}"
export ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"

# Service ports on landsraad_tst (CHOM Application)
export NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-9100}"
export NGINX_EXPORTER_PORT="${NGINX_EXPORTER_PORT:-9113}"
export MYSQL_EXPORTER_PORT="${MYSQL_EXPORTER_PORT:-9104}"
export PHPFPM_EXPORTER_PORT="${PHPFPM_EXPORTER_PORT:-9253}"
export HTTP_PORT="${HTTP_PORT:-80}"

# Timeouts (in seconds)
export DEFAULT_TIMEOUT="${DEFAULT_TIMEOUT:-30}"
export LOG_WAIT_TIMEOUT="${LOG_WAIT_TIMEOUT:-60}"
export METRIC_WAIT_TIMEOUT="${METRIC_WAIT_TIMEOUT:-45}"
export ALERT_WAIT_TIMEOUT="${ALERT_WAIT_TIMEOUT:-120}"

# Test counters
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TESTS_SKIPPED=0
declare -g TEST_ERRORS=()

# ============================================================================
# Output Functions
# ============================================================================

log_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}${BOLD}${title}${NC}"
    echo -e "${BLUE}============================================================================${NC}"
    echo ""
}

log_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}--- ${title} ---${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

log_test() {
    echo -n -e "${BLUE}[TEST]${NC} $1... "
}

# ============================================================================
# Test Result Functions
# ============================================================================

test_pass() {
    local name="$1"
    local details="${2:-}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    if [[ -n "$details" ]]; then
        echo -e "${GREEN}PASS${NC} (${details})"
    else
        echo -e "${GREEN}PASS${NC}"
    fi
}

test_fail() {
    local name="$1"
    local reason="${2:-No details provided}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TEST_ERRORS+=("${name}: ${reason}")
    echo -e "${RED}FAIL${NC}"
    echo -e "       ${RED}Reason: ${reason}${NC}"
}

test_skip() {
    local name="$1"
    local reason="${2:-Not applicable}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}SKIP${NC} (${reason})"
}

# ============================================================================
# Summary Functions
# ============================================================================

print_summary() {
    local test_suite="${1:-Integration Tests}"
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo ""
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BOLD}${test_suite} Summary${NC}"
    echo -e "${BLUE}============================================================================${NC}"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  ${TESTS_PASSED}"
    echo -e "  ${RED}Failed:${NC}  ${TESTS_FAILED}"
    echo -e "  ${YELLOW}Skipped:${NC} ${TESTS_SKIPPED}"
    echo -e "  ${BLUE}Total:${NC}   ${total}"
    echo ""

    if [[ ${#TEST_ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}Failed Tests:${NC}"
        for error in "${TEST_ERRORS[@]}"; do
            echo -e "  - ${error}"
        done
        echo ""
    fi

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}${TESTS_FAILED} test(s) failed.${NC}"
        return 1
    fi
}

reset_counters() {
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
    TEST_ERRORS=()
}

# ============================================================================
# HTTP/API Functions
# ============================================================================

# Check if a URL is reachable with expected status code
check_http() {
    local url="$1"
    local expected_code="${2:-200}"
    local timeout="${3:-$DEFAULT_TIMEOUT}"

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null) || return 1

    if [[ "$response" == "$expected_code" ]] || [[ "$response" == "200" ]] || [[ "$response" == "302" ]]; then
        return 0
    fi
    return 1
}

# Get HTTP response body
http_get() {
    local url="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"

    curl -s --max-time "$timeout" "$url" 2>/dev/null
}

# POST JSON data
http_post_json() {
    local url="$1"
    local data="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"

    curl -s -X POST -H "Content-Type: application/json" -d "$data" --max-time "$timeout" "$url" 2>/dev/null
}

# ============================================================================
# Prometheus Functions
# ============================================================================

# Query Prometheus for a metric
prometheus_query() {
    local query="$1"
    local endpoint="${2:-http://${MENTAT_IP}:${PROMETHEUS_PORT}}"

    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$query'''))" 2>/dev/null || echo "$query")

    curl -s "${endpoint}/api/v1/query?query=${encoded_query}" 2>/dev/null
}

# Query Prometheus and check if result has data
prometheus_has_data() {
    local query="$1"
    local result

    result=$(prometheus_query "$query")

    if echo "$result" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get Prometheus targets
prometheus_targets() {
    local endpoint="${1:-http://${MENTAT_IP}:${PROMETHEUS_PORT}}"
    curl -s "${endpoint}/api/v1/targets" 2>/dev/null
}

# Check if a Prometheus target is up
prometheus_target_up() {
    local job_name="$1"
    local instance_pattern="${2:-.*}"

    local targets
    targets=$(prometheus_targets)

    echo "$targets" | jq -e ".data.activeTargets[] | select(.labels.job == \"$job_name\" and (.labels.instance | test(\"$instance_pattern\"))) | select(.health == \"up\")" >/dev/null 2>&1
}

# Get scrape interval for a job
prometheus_scrape_interval() {
    local job_name="$1"

    local result
    result=$(prometheus_query "prometheus_target_interval_length_seconds{job=\"$job_name\"}")

    echo "$result" | jq -r '.data.result[0].value[1] // "unknown"' 2>/dev/null
}

# ============================================================================
# Loki Functions
# ============================================================================

# Query Loki for logs
loki_query() {
    local query="$1"
    local limit="${2:-100}"
    local endpoint="${3:-http://${MENTAT_IP}:${LOKI_PORT}}"

    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$query'''))" 2>/dev/null || echo "$query")

    curl -s "${endpoint}/loki/api/v1/query_range?query=${encoded_query}&limit=${limit}" 2>/dev/null
}

# Check if Loki has logs matching a query
loki_has_logs() {
    local query="$1"
    local result

    result=$(loki_query "$query")

    if echo "$result" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Query Loki for a specific log message
loki_find_message() {
    local stream_selector="$1"
    local search_text="$2"
    local limit="${3:-100}"

    local query="${stream_selector} |= \"${search_text}\""
    loki_query "$query" "$limit"
}

# Push a test log entry to Loki
loki_push_test_log() {
    local message="$1"
    local labels="${2:-{job=\"test\"}}"
    local endpoint="${3:-http://${MENTAT_IP}:${LOKI_PORT}}"

    local timestamp
    timestamp=$(date +%s)000000000

    local payload
    payload=$(cat <<EOF
{
  "streams": [
    {
      "stream": ${labels},
      "values": [
        ["${timestamp}", "${message}"]
      ]
    }
  ]
}
EOF
)

    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "${endpoint}/loki/api/v1/push" 2>/dev/null
}

# Check Loki readiness
loki_ready() {
    local endpoint="${1:-http://${MENTAT_IP}:${LOKI_PORT}}"
    check_http "${endpoint}/ready"
}

# ============================================================================
# Tempo Functions
# ============================================================================

# Check Tempo readiness
tempo_ready() {
    local endpoint="${1:-http://${MENTAT_IP}:${TEMPO_PORT}}"
    check_http "${endpoint}/ready"
}

# Search for traces by service name
tempo_search_traces() {
    local service_name="$1"
    local endpoint="${2:-http://${MENTAT_IP}:${TEMPO_PORT}}"

    curl -s "${endpoint}/api/search?tags=service.name=${service_name}" 2>/dev/null
}

# Get a specific trace by ID
tempo_get_trace() {
    local trace_id="$1"
    local endpoint="${2:-http://${MENTAT_IP}:${TEMPO_PORT}}"

    curl -s "${endpoint}/api/traces/${trace_id}" 2>/dev/null
}

# Send a test trace via OTLP HTTP
tempo_send_test_trace() {
    local service_name="${1:-test-service}"
    local span_name="${2:-test-span}"
    local endpoint="${3:-http://${MENTAT_IP}:${TEMPO_OTLP_HTTP_PORT}}"

    # Generate random trace and span IDs
    local trace_id
    local span_id
    trace_id=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p | head -c 32)
    span_id=$(openssl rand -hex 8 2>/dev/null || head -c 16 /dev/urandom | xxd -p | head -c 16)

    local timestamp
    timestamp=$(date +%s)000000000

    local payload
    payload=$(cat <<EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [{
        "key": "service.name",
        "value": {"stringValue": "${service_name}"}
      }]
    },
    "scopeSpans": [{
      "spans": [{
        "traceId": "${trace_id}",
        "spanId": "${span_id}",
        "name": "${span_name}",
        "kind": 1,
        "startTimeUnixNano": "${timestamp}",
        "endTimeUnixNano": "$((timestamp + 100000000))"
      }]
    }]
  }]
}
EOF
)

    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "${endpoint}/v1/traces" 2>/dev/null
    echo "$trace_id"
}

# ============================================================================
# Alertmanager Functions
# ============================================================================

# Check Alertmanager readiness
alertmanager_ready() {
    local endpoint="${1:-http://${MENTAT_IP}:${ALERTMANAGER_PORT}}"
    check_http "${endpoint}/-/healthy"
}

# Get all alerts
alertmanager_alerts() {
    local endpoint="${1:-http://${MENTAT_IP}:${ALERTMANAGER_PORT}}"
    curl -s "${endpoint}/api/v2/alerts" 2>/dev/null
}

# Get alert groups
alertmanager_alert_groups() {
    local endpoint="${1:-http://${MENTAT_IP}:${ALERTMANAGER_PORT}}"
    curl -s "${endpoint}/api/v2/alerts/groups" 2>/dev/null
}

# Check if a specific alert is firing
alertmanager_alert_firing() {
    local alert_name="$1"
    local alerts

    alerts=$(alertmanager_alerts)
    echo "$alerts" | jq -e ".[] | select(.labels.alertname == \"$alert_name\" and .status.state == \"active\")" >/dev/null 2>&1
}

# Get silences
alertmanager_silences() {
    local endpoint="${1:-http://${MENTAT_IP}:${ALERTMANAGER_PORT}}"
    curl -s "${endpoint}/api/v2/silences" 2>/dev/null
}

# Create a silence
alertmanager_create_silence() {
    local alert_name="$1"
    local duration="${2:-1h}"
    local endpoint="${3:-http://${MENTAT_IP}:${ALERTMANAGER_PORT}}"

    local start_time
    local end_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    end_time=$(date -u -d "+${duration}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v "+${duration}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

    local payload
    payload=$(cat <<EOF
{
  "matchers": [
    {
      "name": "alertname",
      "value": "${alert_name}",
      "isRegex": false,
      "isEqual": true
    }
  ],
  "startsAt": "${start_time}",
  "endsAt": "${end_time}",
  "createdBy": "integration-test",
  "comment": "Test silence created by integration test"
}
EOF
)

    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "${endpoint}/api/v2/silences" 2>/dev/null
}

# Delete a silence
alertmanager_delete_silence() {
    local silence_id="$1"
    local endpoint="${2:-http://${MENTAT_IP}:${ALERTMANAGER_PORT}}"

    curl -s -X DELETE "${endpoint}/api/v2/silence/${silence_id}" 2>/dev/null
}

# ============================================================================
# Grafana Functions
# ============================================================================

# Check Grafana health
grafana_healthy() {
    local endpoint="${1:-http://${MENTAT_IP}:${GRAFANA_PORT}}"
    check_http "${endpoint}/api/health"
}

# Query Grafana datasource (requires auth)
grafana_query_datasource() {
    local datasource_uid="$1"
    local query="$2"
    local user="${3:-admin}"
    local password="${4:-admin}"
    local endpoint="${5:-http://${MENTAT_IP}:${GRAFANA_PORT}}"

    curl -s -u "${user}:${password}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$query" \
        "${endpoint}/api/ds/query" 2>/dev/null
}

# ============================================================================
# Container/Docker Functions
# ============================================================================

# Check if a container is running
container_running() {
    local container_name="$1"
    docker ps --filter "name=${container_name}" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "${container_name}"
}

# Execute command in container
container_exec() {
    local container_name="$1"
    shift
    docker exec "$container_name" "$@" 2>/dev/null
}

# Get container logs
container_logs() {
    local container_name="$1"
    local lines="${2:-100}"
    docker logs --tail "$lines" "$container_name" 2>&1
}

# ============================================================================
# Network Functions
# ============================================================================

# Check if a port is reachable
port_reachable() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null
    elif command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null
    else
        # Fallback to curl
        curl -s --max-time "$timeout" "http://${host}:${port}" >/dev/null 2>&1 || \
        curl -s --max-time "$timeout" "https://${host}:${port}" >/dev/null 2>&1
    fi
}

# Ping a host
ping_host() {
    local host="$1"
    local count="${2:-1}"

    ping -c "$count" -W 2 "$host" >/dev/null 2>&1
}

# ============================================================================
# Wait Functions
# ============================================================================

# Wait for a condition with timeout
wait_for() {
    local description="$1"
    local timeout="$2"
    shift 2
    local command=("$@")

    local start_time
    start_time=$(date +%s)

    while true; do
        if "${command[@]}" >/dev/null 2>&1; then
            return 0
        fi

        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi

        sleep 1
    done
}

# Wait for HTTP endpoint to be ready
wait_for_http() {
    local url="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"

    wait_for "HTTP $url" "$timeout" check_http "$url"
}

# Wait for Prometheus metric to appear
wait_for_metric() {
    local query="$1"
    local timeout="${2:-$METRIC_WAIT_TIMEOUT}"

    wait_for "metric $query" "$timeout" prometheus_has_data "$query"
}

# Wait for log in Loki
wait_for_log() {
    local query="$1"
    local timeout="${2:-$LOG_WAIT_TIMEOUT}"

    wait_for "log $query" "$timeout" loki_has_logs "$query"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# Array to store cleanup commands
declare -g -a CLEANUP_COMMANDS=()

# Register a cleanup command
register_cleanup() {
    CLEANUP_COMMANDS+=("$*")
}

# Run all registered cleanup commands
run_cleanup() {
    log_info "Running cleanup..."
    for cmd in "${CLEANUP_COMMANDS[@]}"; do
        eval "$cmd" >/dev/null 2>&1 || true
    done
    CLEANUP_COMMANDS=()
}

# Trap for cleanup on exit
trap_cleanup() {
    trap 'run_cleanup' EXIT INT TERM
}

# ============================================================================
# Utility Functions
# ============================================================================

# Generate a unique test ID
generate_test_id() {
    local prefix="${1:-test}"
    echo "${prefix}-$(date +%s)-$$"
}

# Check if jq is available
require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        exit 1
    fi
}

# Check if curl is available
require_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    require_curl
    require_jq
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize test library
init_test_lib() {
    check_dependencies
    reset_counters
    trap_cleanup
}
