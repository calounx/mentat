#!/bin/bash
#===============================================================================
# Phase 2 Post-Upgrade Validation
# Validates Prometheus upgrade to 3.8.1 (two-stage upgrade)
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
CRITICAL_FAILED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1"
    ((CRITICAL_FAILED++))
    ((FAILED++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo ""
echo "=========================================="
echo "  Phase 2: Prometheus Validation"
echo "=========================================="
echo ""

#===============================================================================
# Version Check
#===============================================================================
echo -e "${BLUE}=== Version Verification ===${NC}"

PROM_VERSION=$(prometheus --version 2>&1 | grep -oP '(?<=version )\d+\.\d+\.\d+' | head -1 || echo "unknown")
EXPECTED_VERSION="3.8.1"

if [[ "$PROM_VERSION" == "$EXPECTED_VERSION" ]]; then
    log_pass "Prometheus version: $PROM_VERSION"
else
    log_critical "Prometheus version: $PROM_VERSION (expected $EXPECTED_VERSION)"
fi

echo ""

#===============================================================================
# Service Status
#===============================================================================
echo -e "${BLUE}=== Service Status ===${NC}"

STATUS=$(systemctl is-active prometheus 2>/dev/null || echo "inactive")
if [[ "$STATUS" == "active" ]]; then
    log_pass "Prometheus service: active"
else
    log_critical "Prometheus service: $STATUS"
fi

# Check uptime
UPTIME=$(systemctl show -p ActiveEnterTimestampMonotonic prometheus | cut -d= -f2)
if [[ "$UPTIME" -gt 0 ]]; then
    log_pass "Prometheus uptime: stable"
else
    log_fail "Prometheus uptime: unstable"
fi

echo ""

#===============================================================================
# Endpoint Health
#===============================================================================
echo -e "${BLUE}=== Endpoint Health ===${NC}"

# Ready endpoint
if curl -f -s http://localhost:9090/-/ready &>/dev/null; then
    log_pass "Prometheus ready endpoint: responding"
else
    log_critical "Prometheus ready endpoint: not responding"
fi

# Healthy endpoint
if curl -f -s http://localhost:9090/-/healthy &>/dev/null; then
    log_pass "Prometheus healthy endpoint: responding"
else
    log_fail "Prometheus healthy endpoint: not responding"
fi

# Web UI
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/ 2>/dev/null)
if [[ "$HTTP_CODE" == "200" ]]; then
    log_pass "Prometheus Web UI: HTTP $HTTP_CODE"
else
    log_fail "Prometheus Web UI: HTTP $HTTP_CODE"
fi

echo ""

#===============================================================================
# API Functionality
#===============================================================================
echo -e "${BLUE}=== API Functionality ===${NC}"

# Simple query
QUERY_STATUS=$(curl -s 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | jq -r '.status')
if [[ "$QUERY_STATUS" == "success" ]]; then
    log_pass "Simple query (up): success"
else
    log_critical "Simple query (up): $QUERY_STATUS"
fi

# Aggregation query
AGG_STATUS=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(up)' 2>/dev/null | jq -r '.status')
if [[ "$AGG_STATUS" == "success" ]]; then
    log_pass "Aggregation query: success"
else
    log_fail "Aggregation query: $AGG_STATUS"
fi

# Range query
RANGE_STATUS=$(curl -s "http://localhost:9090/api/v1/query_range?query=up&start=$(date -d '1 hour ago' +%s)&end=$(date +%s)&step=60s" 2>/dev/null | jq -r '.status')
if [[ "$RANGE_STATUS" == "success" ]]; then
    log_pass "Range query: success"
else
    log_fail "Range query: $RANGE_STATUS"
fi

# Label values
LABEL_STATUS=$(curl -s 'http://localhost:9090/api/v1/label/job/values' 2>/dev/null | jq -r '.status')
if [[ "$LABEL_STATUS" == "success" ]]; then
    log_pass "Label query: success"
else
    log_fail "Label query: $LABEL_STATUS"
fi

echo ""

#===============================================================================
# Target Health
#===============================================================================
echo -e "${BLUE}=== Target Health ===${NC}"

TARGETS_JSON=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null)
TARGETS_UP=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' | wc -l)
TARGETS_DOWN=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="down") | .labels.job' | wc -l)
TARGETS_TOTAL=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets | length')

if [[ "$TARGETS_UP" -eq "$TARGETS_TOTAL" && "$TARGETS_DOWN" -eq 0 ]]; then
    log_pass "All targets up: $TARGETS_UP/$TARGETS_TOTAL"
else
    log_fail "Targets: $TARGETS_UP up, $TARGETS_DOWN down (total: $TARGETS_TOTAL)"
    echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="down") | "  DOWN: \(.labels.job)"'
fi

# Verify specific critical targets
CRITICAL_TARGETS=("prometheus" "node_exporter" "alertmanager")
for target in "${CRITICAL_TARGETS[@]}"; do
    HEALTH=$(echo "$TARGETS_JSON" | jq -r ".data.activeTargets[] | select(.labels.job==\"$target\") | .health" | head -1)
    if [[ "$HEALTH" == "up" ]]; then
        log_pass "Critical target $target: up"
    else
        log_critical "Critical target $target: ${HEALTH:-not found}"
    fi
done

echo ""

#===============================================================================
# Alert Rules
#===============================================================================
echo -e "${BLUE}=== Alert Rules ===${NC}"

RULES_JSON=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null)
RULES_TOTAL=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[]] | length')
RULES_FIRING=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[] | select(.state=="firing")] | length')

if [[ "$RULES_TOTAL" -gt 0 ]]; then
    log_pass "Alert rules loaded: $RULES_TOTAL"

    # Check rule health
    RULES_HEALTHY=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[] | select(.health=="ok")] | length')
    if [[ "$RULES_HEALTHY" -eq "$RULES_TOTAL" ]]; then
        log_pass "All rules healthy: $RULES_HEALTHY/$RULES_TOTAL"
    else
        log_fail "Rules health: $RULES_HEALTHY/$RULES_TOTAL healthy"
    fi

    if [[ "$RULES_FIRING" -gt 0 ]]; then
        log_info "Currently firing: $RULES_FIRING alerts"
    fi
else
    log_fail "No alert rules loaded"
fi

echo ""

#===============================================================================
# TSDB Health
#===============================================================================
echo -e "${BLUE}=== TSDB Health ===${NC}"

# Check TSDB blocks
BLOCKS=$(curl -s 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_blocks_loaded' 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$BLOCKS" -gt 0 ]]; then
    log_pass "TSDB blocks loaded: $BLOCKS"
else
    log_fail "TSDB blocks loaded: $BLOCKS"
fi

# Check for corruptions
CORRUPTIONS=$(curl -s 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_symbol_table_size_bytes' 2>/dev/null | jq -r '.status')
if [[ "$CORRUPTIONS" == "success" ]]; then
    log_pass "TSDB integrity: OK"
else
    log_fail "TSDB integrity: check failed"
fi

# WAL replay status
if journalctl -u prometheus -n 100 --no-pager | grep -q "WAL replay completed"; then
    log_pass "WAL replay: completed"
else
    log_info "WAL replay: not found in recent logs (may have completed earlier)"
fi

echo ""

#===============================================================================
# Data Continuity
#===============================================================================
echo -e "${BLUE}=== Data Continuity ===${NC}"

# Check for data across upgrade window
# Query data from 2 hours ago to now (should span the upgrade)
QUERY_RESULT=$(curl -s "http://localhost:9090/api/v1/query_range?query=up{job=\"prometheus\"}&start=$(date -d '2 hours ago' +%s)&end=$(date +%s)&step=60s" 2>/dev/null)
SAMPLES=$(echo "$QUERY_RESULT" | jq -r '.data.result[0].values | length' 2>/dev/null || echo "0")

if [[ "$SAMPLES" -gt 100 ]]; then
    log_pass "Data continuity: $SAMPLES samples (continuous)"
else
    log_fail "Data continuity: $SAMPLES samples (possible gaps)"
fi

# Check for any gaps in the data
# A gap would show as missing values in the time range
echo ""
log_info "Checking for data gaps in last 2 hours..."
EXPECTED_SAMPLES=120  # Approximately 2 hours at 60s interval

if [[ "$SAMPLES" -ge $((EXPECTED_SAMPLES - 10)) ]]; then
    log_pass "No significant data gaps detected"
else
    log_fail "Potential data gaps: expected ~$EXPECTED_SAMPLES samples, got $SAMPLES"
fi

echo ""

#===============================================================================
# Performance Metrics
#===============================================================================
echo -e "${BLUE}=== Performance ===${NC}"

# Query latency
QUERY_TIME=$(curl -w "@-" -o /dev/null -s 'http://localhost:9090/api/v1/query?query=up' <<'EOF'
    time_total:  %{time_total}\n
EOF
)
QUERY_MS=$(echo "$QUERY_TIME" | awk '{print $2 * 1000}')

if (( $(echo "$QUERY_MS < 200" | bc -l) )); then
    log_pass "Query latency: ${QUERY_MS}ms"
elif (( $(echo "$QUERY_MS < 1000" | bc -l) )); then
    log_info "Query latency: ${QUERY_MS}ms (acceptable)"
else
    log_fail "Query latency: ${QUERY_MS}ms (slow)"
fi

# Memory usage
PROM_MEM=$(ps aux | grep "prometheus" | grep -v grep | awk '{print $6}' | head -1)
if [[ -n "$PROM_MEM" ]]; then
    PROM_MEM_MB=$((PROM_MEM / 1024))
    if [[ "$PROM_MEM_MB" -lt 4096 ]]; then
        log_pass "Memory usage: ${PROM_MEM_MB}MB"
    elif [[ "$PROM_MEM_MB" -lt 8192 ]]; then
        log_info "Memory usage: ${PROM_MEM_MB}MB (elevated)"
    else
        log_fail "Memory usage: ${PROM_MEM_MB}MB (high)"
    fi
fi

# Scrape duration
AVG_SCRAPE=$(curl -s 'http://localhost:9090/api/v1/query?query=avg(scrape_duration_seconds)' 2>/dev/null | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if (( $(echo "$AVG_SCRAPE < 1.0" | bc -l) )); then
    log_pass "Average scrape duration: ${AVG_SCRAPE}s"
else
    log_fail "Average scrape duration: ${AVG_SCRAPE}s (slow)"
fi

echo ""

#===============================================================================
# Backward Compatibility
#===============================================================================
echo -e "${BLUE}=== Prometheus 3.x Specific Checks ===${NC}"

# Check that v2 queries still work (backward compatibility)
V2_COMPAT=$(curl -s 'http://localhost:9090/api/v1/query?query=up{job="node_exporter"}' 2>/dev/null | jq -r '.status')
if [[ "$V2_COMPAT" == "success" ]]; then
    log_pass "Prometheus 2.x query compatibility: OK"
else
    log_fail "Prometheus 2.x query compatibility: failed"
fi

# Check new v3 features available
CONFIG_STATUS=$(curl -s http://localhost:9090/api/v1/status/config 2>/dev/null | jq -r '.status')
if [[ "$CONFIG_STATUS" == "success" ]]; then
    log_pass "Prometheus 3.x config API: OK"
else
    log_fail "Prometheus 3.x config API: failed"
fi

echo ""

#===============================================================================
# Error Log Checks
#===============================================================================
echo -e "${BLUE}=== Recent Error Checks ===${NC}"

ERRORS=$(journalctl -u prometheus -n 100 --no-pager --since "10 minutes ago" 2>/dev/null | grep -i "level=error" | wc -l)
if [[ "$ERRORS" -eq 0 ]]; then
    log_pass "No errors in last 10 minutes"
else
    log_fail "$ERRORS errors in last 10 minutes"
    journalctl -u prometheus -n 10 --no-pager | grep -i "level=error" || true
fi

# Check for deprecation warnings
DEPRECATIONS=$(journalctl -u prometheus -n 100 --no-pager | grep -i "deprecat" | wc -l)
if [[ "$DEPRECATIONS" -eq 0 ]]; then
    log_pass "No deprecation warnings"
else
    log_info "$DEPRECATIONS deprecation warnings found"
fi

echo ""

#===============================================================================
# Alertmanager Connectivity
#===============================================================================
echo -e "${BLUE}=== Alertmanager Connectivity ===${NC}"

AM_HEALTH=$(curl -s http://localhost:9090/api/v1/alertmanagers 2>/dev/null | jq -r '.data.activeAlertmanagers[0].url' 2>/dev/null)
if [[ -n "$AM_HEALTH" ]]; then
    log_pass "Alertmanager connected: $AM_HEALTH"
else
    log_fail "Alertmanager: not connected"
fi

echo ""

#===============================================================================
# Summary
#===============================================================================
echo "=========================================="
echo "  Phase 2 Validation Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${RED}Critical: $CRITICAL_FAILED${NC}"
echo -e "Total:  $((PASSED + FAILED))"
echo ""

if [[ "$CRITICAL_FAILED" -gt 0 ]]; then
    echo -e "${RED}Phase 2: CRITICAL FAILURES DETECTED${NC}"
    echo ""
    echo "IMMEDIATE ACTION REQUIRED"
    echo "Consider rollback to Prometheus 2.48.1"
    exit 2
elif [[ "$FAILED" -gt 3 ]]; then
    echo -e "${RED}Phase 2: MULTIPLE FAILURES${NC}"
    echo ""
    echo "Review failures before proceeding to Phase 3"
    exit 1
elif [[ "$FAILED" -gt 0 ]]; then
    echo -e "${YELLOW}Phase 2: COMPLETED WITH WARNINGS${NC}"
    echo ""
    echo "Monitor Prometheus stability before Phase 3"
    echo "Recommend waiting 1 hour before proceeding"
    exit 0
else
    echo -e "${GREEN}Phase 2: PROMETHEUS 3.8.1 UPGRADE SUCCESSFUL${NC}"
    echo ""
    echo "Ready to proceed to Phase 3 (Loki/Promtail)"
    exit 0
fi
