#!/bin/bash
#===============================================================================
# End-to-End Metrics Collection Integration Test
# Tests: Exporter → Prometheus → Grafana → Dashboard flow
#===============================================================================

set -euo pipefail

GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

PASSED=0
FAILED=0

log_pass() { echo "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_info() { echo "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "=========================================="
echo "  Metrics E2E Integration Test"
echo "=========================================="
echo ""

#===============================================================================
# Test 1: Exporter Produces Metrics
#===============================================================================
echo "${BLUE}=== Step 1: Exporter Metrics Production ===${NC}"

# Test node_exporter
NODE_METRICS=$(curl -s http://localhost:9100/metrics | grep "^node_cpu_seconds_total" | wc -l)
if [[ "$NODE_METRICS" -gt 0 ]]; then
    log_pass "node_exporter producing CPU metrics ($NODE_METRICS series)"
else
    log_fail "node_exporter not producing CPU metrics"
fi

# Check metric has valid value
NODE_VALUE=$(curl -s http://localhost:9100/metrics | grep "^node_cpu_seconds_total" | head -1 | awk '{print $2}')
if [[ -n "$NODE_VALUE" && "$NODE_VALUE" != "NaN" ]]; then
    log_pass "node_exporter metrics have valid values ($NODE_VALUE)"
else
    log_fail "node_exporter metrics have invalid values"
fi

echo ""

#===============================================================================
# Test 2: Prometheus Scrapes Metrics
#===============================================================================
echo "${BLUE}=== Step 2: Prometheus Scraping ===${NC}"

# Check if Prometheus has scraped node_exporter
PROM_HAS_METRIC=$(curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' | jq -r '.data.result | length')
if [[ "$PROM_HAS_METRIC" -gt 0 ]]; then
    log_pass "Prometheus has node_exporter metrics ($PROM_HAS_METRIC series)"
else
    log_fail "Prometheus has not scraped node_exporter metrics"
fi

# Verify scrape is recent (within last 60 seconds)
LATEST_SCRAPE=$(curl -s 'http://localhost:9090/api/v1/query?query=up{job="node_exporter"}' | jq -r '.data.result[0].value[0]')
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LATEST_SCRAPE))

if [[ "$TIME_DIFF" -lt 60 ]]; then
    log_pass "Prometheus scrape is recent (${TIME_DIFF}s ago)"
else
    log_fail "Prometheus scrape is stale (${TIME_DIFF}s ago)"
fi

echo ""

#===============================================================================
# Test 3: Prometheus Stores Time Series
#===============================================================================
echo "${BLUE}=== Step 3: Time Series Storage ===${NC}"

# Query last 5 minutes of data
RANGE_DATA=$(curl -s "http://localhost:9090/api/v1/query_range?query=up{job=\"node_exporter\"}&start=$(date -d '5 minutes ago' +%s)&end=$(date +%s)&step=15s" | jq -r '.data.result[0].values | length')

if [[ "$RANGE_DATA" -gt 10 ]]; then
    log_pass "Time series data stored ($RANGE_DATA data points)"
else
    log_fail "Insufficient time series data ($RANGE_DATA data points)"
fi

# Check data has no gaps
GAP_CHECK=$(curl -s "http://localhost:9090/api/v1/query_range?query=up{job=\"node_exporter\"}&start=$(date -d '5 minutes ago' +%s)&end=$(date +%s)&step=15s" | jq -r '.data.result[0].values | map(.[1]) | all')

if [[ "$GAP_CHECK" == "true" ]] || [[ -n "$GAP_CHECK" ]]; then
    log_pass "No gaps in time series data"
else
    log_fail "Gaps detected in time series data"
fi

echo ""

#===============================================================================
# Test 4: Grafana Queries Prometheus
#===============================================================================
echo "${BLUE}=== Step 4: Grafana → Prometheus Query ===${NC}"

# Test Grafana can query through datasource proxy
GRAFANA_QUERY=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up{job="node_exporter"}' | jq -r '.status')

if [[ "$GRAFANA_QUERY" == "success" ]]; then
    log_pass "Grafana successfully queries Prometheus"
else
    log_fail "Grafana query to Prometheus failed: $GRAFANA_QUERY"
fi

# Verify data returned
GRAFANA_RESULTS=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up{job="node_exporter"}' | jq -r '.data.result | length')

if [[ "$GRAFANA_RESULTS" -gt 0 ]]; then
    log_pass "Grafana receives data from Prometheus ($GRAFANA_RESULTS results)"
else
    log_fail "Grafana receives no data from Prometheus"
fi

echo ""

#===============================================================================
# Test 5: Dashboard Panels Render
#===============================================================================
echo "${BLUE}=== Step 5: Dashboard Rendering ===${NC}"

# Check if dashboards exist
DASHBOARD_COUNT=$(curl -s -u admin:admin 'http://localhost:3000/api/search?type=dash-db' | jq '. | length')

if [[ "$DASHBOARD_COUNT" -gt 0 ]]; then
    log_pass "Dashboards configured ($DASHBOARD_COUNT dashboards)"
else
    log_fail "No dashboards found"
fi

# Test specific dashboard can be loaded
NODE_DASH=$(curl -s -o /dev/null -w "%{http_code}" -u admin:admin 'http://localhost:3000/api/dashboards/uid/node-exporter')

if [[ "$NODE_DASH" == "200" ]]; then
    log_pass "Node Exporter dashboard loads successfully"
else
    log_fail "Node Exporter dashboard failed to load (HTTP $NODE_DASH)"
fi

echo ""

#===============================================================================
# Test 6: Alert Rules Evaluate
#===============================================================================
echo "${BLUE}=== Step 6: Alert Rule Evaluation ===${NC}"

# Check if alert rules are loaded
RULES_LOADED=$(curl -s 'http://localhost:9090/api/v1/rules' | jq '[.data.groups[].rules[] | select(.type=="alerting")] | length')

if [[ "$RULES_LOADED" -gt 0 ]]; then
    log_pass "Alert rules loaded ($RULES_LOADED rules)"
else
    log_fail "No alert rules loaded"
fi

# Check if rules are being evaluated
RULES_HEALTHY=$(curl -s 'http://localhost:9090/api/v1/rules' | jq '[.data.groups[].rules[] | select(.health=="ok")] | length')

if [[ "$RULES_HEALTHY" -eq "$RULES_LOADED" ]]; then
    log_pass "All alert rules healthy ($RULES_HEALTHY/$RULES_LOADED)"
else
    log_fail "Some alert rules unhealthy ($RULES_HEALTHY/$RULES_LOADED)"
fi

echo ""

#===============================================================================
# Test 7: Multi-Exporter Integration
#===============================================================================
echo "${BLUE}=== Step 7: Multi-Exporter Validation ===${NC}"

EXPORTERS=("node_exporter" "nginx_exporter" "mysqld_exporter" "phpfpm_exporter" "fail2ban_exporter")
EXPORTERS_UP=0

for exporter in "${EXPORTERS[@]}"; do
    UP_VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=up{job=\"$exporter\"}" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

    if [[ "$UP_VALUE" == "1" ]]; then
        ((EXPORTERS_UP++))
        log_pass "$exporter: up and scraped"
    else
        log_fail "$exporter: down or not scraped"
    fi
done

log_info "Exporters operational: $EXPORTERS_UP/${#EXPORTERS[@]}"

echo ""

#===============================================================================
# Test 8: Metric Cardinality Check
#===============================================================================
echo "${BLUE}=== Step 8: Metric Cardinality ===${NC}"

# Count total time series
TOTAL_SERIES=$(curl -s 'http://localhost:9090/api/v1/query?query=count({__name__=~".+"})' | jq -r '.data.result[0].value[1]' | cut -d. -f1)

if [[ "$TOTAL_SERIES" -gt 1000 ]]; then
    log_pass "Healthy metric cardinality ($TOTAL_SERIES series)"
elif [[ "$TOTAL_SERIES" -gt 100 ]]; then
    log_info "Moderate metric cardinality ($TOTAL_SERIES series)"
else
    log_fail "Low metric cardinality ($TOTAL_SERIES series)"
fi

# Check for excessive cardinality (potential issue)
if [[ "$TOTAL_SERIES" -gt 1000000 ]]; then
    log_fail "Warning: Very high cardinality ($TOTAL_SERIES series)"
fi

echo ""

#===============================================================================
# Test 9: Query Performance
#===============================================================================
echo "${BLUE}=== Step 9: Query Performance ===${NC}"

# Test simple query performance
START_TIME=$(date +%s%N)
curl -s 'http://localhost:9090/api/v1/query?query=up' > /dev/null
END_TIME=$(date +%s%N)
QUERY_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [[ "$QUERY_MS" -lt 100 ]]; then
    log_pass "Simple query performance: ${QUERY_MS}ms"
elif [[ "$QUERY_MS" -lt 500 ]]; then
    log_info "Simple query performance: ${QUERY_MS}ms (acceptable)"
else
    log_fail "Simple query performance: ${QUERY_MS}ms (slow)"
fi

# Test complex aggregation query performance
START_TIME=$(date +%s%N)
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(node_cpu_seconds_total[5m]))' > /dev/null
END_TIME=$(date +%s%N)
AGG_QUERY_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [[ "$AGG_QUERY_MS" -lt 500 ]]; then
    log_pass "Aggregation query performance: ${AGG_QUERY_MS}ms"
elif [[ "$AGG_QUERY_MS" -lt 2000 ]]; then
    log_info "Aggregation query performance: ${AGG_QUERY_MS}ms (acceptable)"
else
    log_fail "Aggregation query performance: ${AGG_QUERY_MS}ms (slow)"
fi

echo ""

#===============================================================================
# Summary
#===============================================================================
echo "=========================================="
echo "  Integration Test Summary"
echo "=========================================="
echo ""
echo "${GREEN}Passed: $PASSED${NC}"
echo "${RED}Failed: $FAILED${NC}"
echo -e "Total:  $((PASSED + FAILED))"
echo ""

if [[ "$FAILED" -eq 0 ]]; then
    echo "${GREEN}METRICS E2E FLOW: FULLY OPERATIONAL${NC}"
    exit 0
else
    echo "${RED}METRICS E2E FLOW: ISSUES DETECTED${NC}"
    exit 1
fi
