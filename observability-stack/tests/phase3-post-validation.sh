#!/bin/bash
#===============================================================================
# Phase 3 Post-Upgrade Validation
# Validates Loki and Promtail upgrades to 3.6.3
#===============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo ""
echo "=========================================="
echo "  Phase 3: Loki/Promtail Validation"
echo "=========================================="
echo ""

#===============================================================================
# Version Checks
#===============================================================================
echo -e "${BLUE}=== Version Verification ===${NC}"

LOKI_VERSION=$(loki --version 2>&1 | grep -oP '(?<=version )\d+\.\d+\.\d+' | head -1 || echo "unknown")
PROMTAIL_VERSION=$(promtail --version 2>&1 | grep -oP '(?<=version )\d+\.\d+\.\d+' | head -1 || echo "unknown")
EXPECTED_VERSION="3.6.3"

if [[ "$LOKI_VERSION" == "$EXPECTED_VERSION" ]]; then
    log_pass "Loki version: $LOKI_VERSION"
else
    log_fail "Loki version: $LOKI_VERSION (expected $EXPECTED_VERSION)"
fi

if [[ "$PROMTAIL_VERSION" == "$EXPECTED_VERSION" ]]; then
    log_pass "Promtail version: $PROMTAIL_VERSION"
else
    log_fail "Promtail version: $PROMTAIL_VERSION (expected $EXPECTED_VERSION)"
fi

echo ""

#===============================================================================
# Service Status
#===============================================================================
echo -e "${BLUE}=== Service Status ===${NC}"

LOKI_STATUS=$(systemctl is-active loki 2>/dev/null || echo "inactive")
if [[ "$LOKI_STATUS" == "active" ]]; then
    log_pass "Loki service: active"
else
    log_fail "Loki service: $LOKI_STATUS"
fi

PROMTAIL_STATUS=$(systemctl is-active promtail 2>/dev/null || echo "inactive")
if [[ "$PROMTAIL_STATUS" == "active" ]]; then
    log_pass "Promtail service: active"
else
    log_fail "Promtail service: $PROMTAIL_STATUS"
fi

echo ""

#===============================================================================
# Endpoint Health
#===============================================================================
echo -e "${BLUE}=== Endpoint Health ===${NC}"

# Loki ready endpoint
if curl -f -s http://localhost:3100/ready &>/dev/null; then
    log_pass "Loki ready endpoint: responding"
else
    log_fail "Loki ready endpoint: not responding"
fi

# Loki metrics
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3100/metrics 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    log_pass "Loki metrics endpoint: HTTP $HTTP_CODE"
else
    log_fail "Loki metrics endpoint: HTTP $HTTP_CODE"
fi

# Promtail metrics
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/metrics 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    log_pass "Promtail metrics endpoint: HTTP $HTTP_CODE"
else
    log_fail "Promtail metrics endpoint: HTTP $HTTP_CODE"
fi

echo ""

#===============================================================================
# Loki API Functionality
#===============================================================================
echo -e "${BLUE}=== Loki API Functionality ===${NC}"

# Labels query
LABELS_STATUS=$(curl -s 'http://localhost:3100/loki/api/v1/labels' 2>/dev/null | jq -r '.status')
if [[ "$LABELS_STATUS" == "success" ]]; then
    LABEL_COUNT=$(curl -s 'http://localhost:3100/loki/api/v1/labels' 2>/dev/null | jq '.data | length')
    log_pass "Labels query: success ($LABEL_COUNT labels)"
else
    log_fail "Labels query: $LABELS_STATUS"
fi

# Log query
LOG_STATUS=$(curl -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}&limit=10' 2>/dev/null | jq -r '.status')
if [[ "$LOG_STATUS" == "success" ]]; then
    STREAM_COUNT=$(curl -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}&limit=10' 2>/dev/null | jq '.data.result | length')
    log_pass "Log query: success ($STREAM_COUNT streams)"
else
    log_fail "Log query: $LOG_STATUS"
fi

# Range query
RANGE_STATUS=$(curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"varlogs\"}&start=$(date -d '10 minutes ago' +%s)000000000&end=$(date +%s)000000000&limit=100" 2>/dev/null | jq -r '.status')
if [[ "$RANGE_STATUS" == "success" ]]; then
    log_pass "Range query: success"
else
    log_fail "Range query: $RANGE_STATUS"
fi

echo ""

#===============================================================================
# Log Ingestion
#===============================================================================
echo -e "${BLUE}=== Log Ingestion ===${NC}"

# Check Loki ingester streams
INGESTER_STREAMS=$(curl -s http://localhost:3100/metrics 2>/dev/null | grep "loki_ingester_streams{" | awk '{print $2}' | head -1)
if [[ -n "$INGESTER_STREAMS" && "$INGESTER_STREAMS" -gt 0 ]]; then
    log_pass "Loki ingester streams: $INGESTER_STREAMS active"
else
    log_fail "Loki ingester streams: ${INGESTER_STREAMS:-0}"
fi

# Check Promtail targets
PROMTAIL_TARGETS=$(curl -s http://localhost:9080/metrics 2>/dev/null | grep "promtail_targets_active_total" | awk '{print $2}')
if [[ -n "$PROMTAIL_TARGETS" && "$PROMTAIL_TARGETS" -gt 0 ]]; then
    log_pass "Promtail active targets: $PROMTAIL_TARGETS"
else
    log_fail "Promtail active targets: ${PROMTAIL_TARGETS:-0}"
fi

# Check Promtail sent entries
PROMTAIL_SENT=$(curl -s http://localhost:9080/metrics 2>/dev/null | grep "promtail_sent_entries_total" | grep -v "error" | awk '{sum+=$2} END {print sum}')
if [[ -n "$PROMTAIL_SENT" && "$PROMTAIL_SENT" -gt 0 ]]; then
    log_pass "Promtail sent entries: $PROMTAIL_SENT total"
else
    log_fail "Promtail sent entries: ${PROMTAIL_SENT:-0}"
fi

# Check for send errors
PROMTAIL_ERRORS=$(curl -s http://localhost:9080/metrics 2>/dev/null | grep "promtail_sent_entries_total.*error" | awk '{sum+=$2} END {print sum}')
if [[ -z "$PROMTAIL_ERRORS" || "$PROMTAIL_ERRORS" -eq 0 ]]; then
    log_pass "Promtail send errors: 0"
else
    log_fail "Promtail send errors: $PROMTAIL_ERRORS"
fi

echo ""

#===============================================================================
# End-to-End Log Flow Test
#===============================================================================
echo -e "${BLUE}=== End-to-End Log Flow ===${NC}"

# Generate a test log entry
TEST_MESSAGE="UPGRADE_TEST_$(date +%s)_PHASE3_VALIDATION"
echo "$TEST_MESSAGE" | sudo tee -a /var/log/syslog > /dev/null

log_info "Generated test log: $TEST_MESSAGE"
log_info "Waiting 15 seconds for log ingestion..."
sleep 15

# Query Loki for the test entry
TEST_FOUND=$(curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"varlogs\"}|~\"$TEST_MESSAGE\"&limit=10" 2>/dev/null | jq -r '.data.result | length')

if [[ "$TEST_FOUND" -gt 0 ]]; then
    log_pass "End-to-end log flow: test log found in Loki"
else
    log_fail "End-to-end log flow: test log not found (waited 15s)"
fi

echo ""

#===============================================================================
# Data Continuity
#===============================================================================
echo -e "${BLUE}=== Data Continuity ===${NC}"

# Check for logs in the last hour (should span the upgrade)
LOG_SAMPLES=$(curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"varlogs\"}&start=$(date -d '1 hour ago' +%s)000000000&end=$(date +%s)000000000&limit=1000" 2>/dev/null | jq -r '.data.result[0].values | length' 2>/dev/null || echo "0")

if [[ "$LOG_SAMPLES" -gt 100 ]]; then
    log_pass "Log continuity: $LOG_SAMPLES entries in last hour"
else
    log_fail "Log continuity: only $LOG_SAMPLES entries (possible gaps)"
fi

echo ""

#===============================================================================
# Grafana Integration
#===============================================================================
echo -e "${BLUE}=== Grafana Integration ===${NC}"

# Check if Grafana can query Loki
GRAFANA_LOKI=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/2/loki/api/v1/labels' 2>/dev/null | jq -r '.status')
if [[ "$GRAFANA_LOKI" == "success" ]]; then
    log_pass "Grafana → Loki connectivity: OK"
else
    log_fail "Grafana → Loki connectivity: failed"
fi

# Test Grafana Explore query
EXPLORE_QUERY=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/2/loki/api/v1/query?query={job="varlogs"}&limit=5' 2>/dev/null | jq -r '.status')
if [[ "$EXPLORE_QUERY" == "success" ]]; then
    log_pass "Grafana Explore query: OK"
else
    log_fail "Grafana Explore query: failed"
fi

echo ""

#===============================================================================
# Performance Checks
#===============================================================================
echo -e "${BLUE}=== Performance ===${NC}"

# Loki query latency
LOKI_QUERY_TIME=$(curl -w "@-" -o /dev/null -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}&limit=10' <<'EOF'
    time_total:  %{time_total}\n
EOF
)
LOKI_QUERY_MS=$(echo "$LOKI_QUERY_TIME" | awk '{print $2 * 1000}')

if (( $(echo "$LOKI_QUERY_MS < 500" | bc -l) )); then
    log_pass "Loki query latency: ${LOKI_QUERY_MS}ms"
elif (( $(echo "$LOKI_QUERY_MS < 2000" | bc -l) )); then
    log_info "Loki query latency: ${LOKI_QUERY_MS}ms (acceptable)"
else
    log_fail "Loki query latency: ${LOKI_QUERY_MS}ms (slow)"
fi

# Loki memory usage
LOKI_MEM=$(ps aux | grep "loki" | grep -v grep | awk '{print $6}' | head -1)
if [[ -n "$LOKI_MEM" ]]; then
    LOKI_MEM_MB=$((LOKI_MEM / 1024))
    if [[ "$LOKI_MEM_MB" -lt 2048 ]]; then
        log_pass "Loki memory usage: ${LOKI_MEM_MB}MB"
    elif [[ "$LOKI_MEM_MB" -lt 4096 ]]; then
        log_info "Loki memory usage: ${LOKI_MEM_MB}MB (elevated)"
    else
        log_fail "Loki memory usage: ${LOKI_MEM_MB}MB (high)"
    fi
fi

echo ""

#===============================================================================
# Error Log Checks
#===============================================================================
echo -e "${BLUE}=== Recent Error Checks ===${NC}"

LOKI_ERRORS=$(journalctl -u loki -n 50 --no-pager --since "10 minutes ago" 2>/dev/null | grep -i "level=error" | wc -l)
if [[ "$LOKI_ERRORS" -eq 0 ]]; then
    log_pass "Loki: no errors in last 10 minutes"
else
    log_fail "Loki: $LOKI_ERRORS errors in last 10 minutes"
    journalctl -u loki -n 5 --no-pager | grep -i "level=error" || true
fi

PROMTAIL_ERRORS=$(journalctl -u promtail -n 50 --no-pager --since "10 minutes ago" 2>/dev/null | grep -i "level=error" | wc -l)
if [[ "$PROMTAIL_ERRORS" -eq 0 ]]; then
    log_pass "Promtail: no errors in last 10 minutes"
else
    log_fail "Promtail: $PROMTAIL_ERRORS errors in last 10 minutes"
    journalctl -u promtail -n 5 --no-pager | grep -i "level=error" || true
fi

echo ""

#===============================================================================
# Loki 3.x Specific Checks
#===============================================================================
echo -e "${BLUE}=== Loki 3.x Specific Features ===${NC}"

# Check Loki config API (new in v3)
CONFIG_STATUS=$(curl -s http://localhost:3100/config 2>/dev/null | jq -r 'type')
if [[ "$CONFIG_STATUS" == "object" ]]; then
    log_pass "Loki 3.x config endpoint: OK"
else
    log_info "Loki 3.x config endpoint: response type $CONFIG_STATUS"
fi

# Check for deprecation warnings
LOKI_DEPRECATIONS=$(journalctl -u loki -n 100 --no-pager | grep -i "deprecat" | wc -l)
if [[ "$LOKI_DEPRECATIONS" -eq 0 ]]; then
    log_pass "No deprecation warnings in Loki"
else
    log_info "$LOKI_DEPRECATIONS deprecation warnings found in Loki logs"
fi

PROMTAIL_DEPRECATIONS=$(journalctl -u promtail -n 100 --no-pager | grep -i "deprecat" | wc -l)
if [[ "$PROMTAIL_DEPRECATIONS" -eq 0 ]]; then
    log_pass "No deprecation warnings in Promtail"
else
    log_info "$PROMTAIL_DEPRECATIONS deprecation warnings found in Promtail logs"
fi

echo ""

#===============================================================================
# Summary
#===============================================================================
echo "=========================================="
echo "  Phase 3 Validation Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "Total:  $((PASSED + FAILED))"
echo ""

if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${GREEN}Phase 3: LOKI/PROMTAIL UPGRADE SUCCESSFUL${NC}"
    echo ""
    echo "All phases completed! Observability stack fully upgraded."
    echo ""
    echo "Recommended next steps:"
    echo "  1. Monitor stability for 24 hours"
    echo "  2. Run integration tests"
    echo "  3. Verify all dashboards and alerts"
    echo "  4. Document any issues encountered"
    exit 0
elif [[ "$FAILED" -le 2 ]]; then
    echo -e "${YELLOW}Phase 3: COMPLETED WITH MINOR ISSUES${NC}"
    echo ""
    echo "Review failures and monitor log ingestion"
    exit 0
else
    echo -e "${RED}Phase 3: VALIDATION FAILED${NC}"
    echo ""
    echo "Multiple issues detected. Review logs and consider rollback."
    exit 1
fi
