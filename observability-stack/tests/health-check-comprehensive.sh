#!/bin/bash
#===============================================================================
# Comprehensive Health Check Script
# Validates all components of the observability stack
#===============================================================================

set -euo pipefail

# Colors
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

log_pass() {
    echo "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

log_fail() {
    echo "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNING++))
}

log_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

echo ""
echo "=========================================="
echo "  Comprehensive Health Check"
echo "=========================================="
echo ""

#===============================================================================
# Service Status Checks
#===============================================================================
echo "${BLUE}=== Service Status ===${NC}"

SERVICES=(
    "node_exporter"
    "nginx_exporter"
    "mysqld_exporter"
    "phpfpm_exporter"
    "fail2ban_exporter"
    "promtail"
    "prometheus"
    "loki"
    "grafana-server"
    "alertmanager"
    "nginx"
)

for svc in "${SERVICES[@]}"; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "active" ]]; then
        log_pass "$svc: $STATUS"
    elif [[ "$STATUS" == "unknown" ]]; then
        log_warn "$svc: not installed"
    else
        log_fail "$svc: $STATUS"
    fi
done

echo ""

#===============================================================================
# Metrics Endpoint Checks
#===============================================================================
echo "${BLUE}=== Metrics Endpoints ===${NC}"

check_endpoint() {
    local name="$1"
    local url="$2"
    local expected_code="${3:-200}"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" == "$expected_code" ]]; then
        log_pass "$name: HTTP $HTTP_CODE"
        return 0
    elif [[ "$HTTP_CODE" == "000" ]]; then
        log_fail "$name: unreachable (timeout)"
        return 1
    else
        log_fail "$name: HTTP $HTTP_CODE (expected $expected_code)"
        return 1
    fi
}

# Exporters
check_endpoint "node_exporter (9100)" "http://localhost:9100/metrics"
check_endpoint "nginx_exporter (9113)" "http://localhost:9113/metrics"
check_endpoint "mysqld_exporter (9104)" "http://localhost:9104/metrics"
check_endpoint "phpfpm_exporter (9253)" "http://localhost:9253/metrics"
check_endpoint "fail2ban_exporter (9191)" "http://localhost:9191/metrics"

# Core services
check_endpoint "prometheus ready (9090)" "http://localhost:9090/-/ready"
check_endpoint "loki ready (3100)" "http://localhost:3100/ready"
check_endpoint "grafana health (3000)" "http://localhost:3000/api/health"
check_endpoint "alertmanager healthy (9093)" "http://localhost:9093/alertmanager/-/healthy"

echo ""

#===============================================================================
# Prometheus Target Checks
#===============================================================================
echo "${BLUE}=== Prometheus Targets ===${NC}"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    TARGETS_JSON=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null)

    TARGETS_UP=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' | wc -l)
    TARGETS_DOWN=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="down") | .labels.job' | wc -l)
    TARGETS_UNKNOWN=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="unknown") | .labels.job' | wc -l)

    if [[ "$TARGETS_UP" -gt 0 && "$TARGETS_DOWN" -eq 0 ]]; then
        log_pass "Targets: $TARGETS_UP up, $TARGETS_DOWN down, $TARGETS_UNKNOWN unknown"
    elif [[ "$TARGETS_DOWN" -gt 0 ]]; then
        log_fail "Targets: $TARGETS_UP up, $TARGETS_DOWN down, $TARGETS_UNKNOWN unknown"
        echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.health=="down") | "  DOWN: \(.labels.job) - \(.lastError)"'
    else
        log_warn "Targets: $TARGETS_UP up, $TARGETS_DOWN down, $TARGETS_UNKNOWN unknown"
    fi

    # List all targets
    log_info "Active targets:"
    echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | "  - \(.labels.job): \(.health)"'
else
    log_fail "Prometheus not responding, cannot check targets"
fi

echo ""

#===============================================================================
# Alert Rules Checks
#===============================================================================
echo "${BLUE}=== Alert Rules ===${NC}"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    RULES_JSON=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null)

    RULES_TOTAL=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[]] | length')
    RULES_FIRING=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[] | select(.state=="firing")] | length')
    RULES_PENDING=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[] | select(.state=="pending")] | length')
    RULES_INACTIVE=$(echo "$RULES_JSON" | jq '[.data.groups[].rules[] | select(.state=="inactive")] | length')

    if [[ "$RULES_TOTAL" -gt 0 ]]; then
        log_pass "Rules loaded: $RULES_TOTAL (firing: $RULES_FIRING, pending: $RULES_PENDING, inactive: $RULES_INACTIVE)"

        if [[ "$RULES_FIRING" -gt 0 ]]; then
            log_warn "Currently firing alerts:"
            echo "$RULES_JSON" | jq -r '.data.groups[].rules[] | select(.state=="firing") | "  - \(.name): \(.alerts[0].labels.severity // "unknown")"'
        fi
    else
        log_warn "No alert rules loaded"
    fi
else
    log_fail "Prometheus not responding, cannot check rules"
fi

echo ""

#===============================================================================
# Prometheus Query Functionality
#===============================================================================
echo "${BLUE}=== Prometheus Queries ===${NC}"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    # Test simple query
    QUERY_RESULT=$(curl -s 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | jq -r '.status')
    if [[ "$QUERY_RESULT" == "success" ]]; then
        log_pass "Simple query (up): success"
    else
        log_fail "Simple query (up): $QUERY_RESULT"
    fi

    # Test aggregation query
    AGG_RESULT=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(up)' 2>/dev/null | jq -r '.status')
    if [[ "$AGG_RESULT" == "success" ]]; then
        UP_COUNT=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(up)' 2>/dev/null | jq -r '.data.result[0].value[1]')
        log_pass "Aggregation query: success (up count: $UP_COUNT)"
    else
        log_fail "Aggregation query: $AGG_RESULT"
    fi

    # Test range query
    RANGE_RESULT=$(curl -s 'http://localhost:9090/api/v1/query_range?query=up&start='$(date -d '10 minutes ago' +%s)'&end='$(date +%s)'&step=60s' 2>/dev/null | jq -r '.status')
    if [[ "$RANGE_RESULT" == "success" ]]; then
        log_pass "Range query: success"
    else
        log_fail "Range query: $RANGE_RESULT"
    fi
else
    log_fail "Prometheus not responding, cannot test queries"
fi

echo ""

#===============================================================================
# Loki Query Functionality
#===============================================================================
echo "${BLUE}=== Loki Queries ===${NC}"

if curl -s http://localhost:3100/ready &>/dev/null; then
    # Test label query
    LABEL_RESULT=$(curl -s 'http://localhost:3100/loki/api/v1/labels' 2>/dev/null | jq -r '.status')
    if [[ "$LABEL_RESULT" == "success" ]]; then
        LABEL_COUNT=$(curl -s 'http://localhost:3100/loki/api/v1/labels' 2>/dev/null | jq '.data | length')
        log_pass "Label query: success ($LABEL_COUNT labels)"
    else
        log_fail "Label query: $LABEL_RESULT"
    fi

    # Test log query
    LOG_RESULT=$(curl -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}&limit=10' 2>/dev/null | jq -r '.status')
    if [[ "$LOG_RESULT" == "success" ]]; then
        LOG_COUNT=$(curl -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}&limit=10' 2>/dev/null | jq '.data.result | length')
        log_pass "Log query: success ($LOG_COUNT streams)"
    else
        log_fail "Log query: $LOG_RESULT"
    fi

    # Check Promtail sending logs
    PROMTAIL_SENT=$(curl -s http://localhost:9080/metrics 2>/dev/null | grep "promtail_sent_entries_total" | awk '{print $2}')
    if [[ -n "$PROMTAIL_SENT" && "$PROMTAIL_SENT" -gt 0 ]]; then
        log_pass "Promtail sending logs: $PROMTAIL_SENT entries sent"
    else
        log_fail "Promtail not sending logs"
    fi
else
    log_fail "Loki not responding, cannot test queries"
fi

echo ""

#===============================================================================
# Grafana Connectivity
#===============================================================================
echo "${BLUE}=== Grafana Connectivity ===${NC}"

if curl -s http://localhost:3000/api/health &>/dev/null; then
    # Check data sources
    DATASOURCES=$(curl -s -u admin:admin http://localhost:3000/api/datasources 2>/dev/null | jq '. | length')
    if [[ "$DATASOURCES" -ge 2 ]]; then
        log_pass "Grafana data sources: $DATASOURCES configured"

        # Test Prometheus data source
        PROM_DS=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up' 2>/dev/null | jq -r '.status')
        if [[ "$PROM_DS" == "success" ]]; then
            log_pass "Prometheus data source: connected"
        else
            log_fail "Prometheus data source: error"
        fi

        # Test Loki data source
        LOKI_DS=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/2/loki/api/v1/labels' 2>/dev/null | jq -r '.status')
        if [[ "$LOKI_DS" == "success" ]]; then
            log_pass "Loki data source: connected"
        else
            log_fail "Loki data source: error"
        fi
    else
        log_fail "Grafana data sources: $DATASOURCES (expected >= 2)"
    fi

    # Check dashboards
    DASHBOARDS=$(curl -s -u admin:admin http://localhost:3000/api/search?query=& 2>/dev/null | jq '. | length')
    if [[ "$DASHBOARDS" -gt 0 ]]; then
        log_pass "Grafana dashboards: $DASHBOARDS loaded"
    else
        log_warn "Grafana dashboards: none found"
    fi
else
    log_fail "Grafana not responding, cannot check connectivity"
fi

echo ""

#===============================================================================
# Storage Checks
#===============================================================================
echo "${BLUE}=== Storage ===${NC}"

# Check disk space
ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ "$ROOT_USAGE" -lt 80 ]]; then
    log_pass "Root disk usage: ${ROOT_USAGE}%"
elif [[ "$ROOT_USAGE" -lt 90 ]]; then
    log_warn "Root disk usage: ${ROOT_USAGE}% (getting high)"
else
    log_fail "Root disk usage: ${ROOT_USAGE}% (critical)"
fi

# Check Prometheus data
if [[ -d /var/lib/prometheus ]]; then
    PROM_SIZE=$(du -sh /var/lib/prometheus 2>/dev/null | awk '{print $1}')
    log_pass "Prometheus data: $PROM_SIZE"
else
    log_warn "Prometheus data directory not found"
fi

# Check Loki data
if [[ -d /var/lib/loki ]]; then
    LOKI_SIZE=$(du -sh /var/lib/loki 2>/dev/null | awk '{print $1}')
    log_pass "Loki data: $LOKI_SIZE"
else
    log_warn "Loki data directory not found"
fi

echo ""

#===============================================================================
# Error Log Checks
#===============================================================================
echo "${BLUE}=== Recent Errors ===${NC}"

ERROR_COUNT=0

for svc in prometheus loki grafana-server alertmanager; do
    ERRORS=$(journalctl -u "$svc" -n 100 --no-pager --since "10 minutes ago" 2>/dev/null | grep -i "error" | wc -l)
    if [[ "$ERRORS" -eq 0 ]]; then
        log_pass "$svc: no errors in last 10 minutes"
    elif [[ "$ERRORS" -lt 5 ]]; then
        log_warn "$svc: $ERRORS errors in last 10 minutes"
        ERROR_COUNT=$((ERROR_COUNT + ERRORS))
    else
        log_fail "$svc: $ERRORS errors in last 10 minutes"
        ERROR_COUNT=$((ERROR_COUNT + ERRORS))
    fi
done

echo ""

#===============================================================================
# Performance Checks
#===============================================================================
echo "${BLUE}=== Performance ===${NC}"

# Prometheus query latency
if curl -s http://localhost:9090/-/ready &>/dev/null; then
    QUERY_TIME=$(curl -w "@-" -o /dev/null -s 'http://localhost:9090/api/v1/query?query=up' <<'EOF'
    time_total:  %{time_total}\n
EOF
)
    QUERY_MS=$(echo "$QUERY_TIME" | awk '{print $2 * 1000}')
    if (( $(echo "$QUERY_MS < 100" | bc -l) )); then
        log_pass "Prometheus query latency: ${QUERY_MS}ms"
    elif (( $(echo "$QUERY_MS < 500" | bc -l) )); then
        log_warn "Prometheus query latency: ${QUERY_MS}ms (slow)"
    else
        log_fail "Prometheus query latency: ${QUERY_MS}ms (very slow)"
    fi
fi

# Memory usage
PROM_MEM=$(ps aux | grep "prometheus" | grep -v grep | awk '{print $6}' | head -1)
if [[ -n "$PROM_MEM" ]]; then
    PROM_MEM_MB=$((PROM_MEM / 1024))
    if [[ "$PROM_MEM_MB" -lt 2048 ]]; then
        log_pass "Prometheus memory: ${PROM_MEM_MB}MB"
    elif [[ "$PROM_MEM_MB" -lt 4096 ]]; then
        log_warn "Prometheus memory: ${PROM_MEM_MB}MB (high)"
    else
        log_fail "Prometheus memory: ${PROM_MEM_MB}MB (very high)"
    fi
fi

echo ""

#===============================================================================
# Summary
#===============================================================================
echo "=========================================="
echo "  Health Check Summary"
echo "=========================================="
echo ""
echo "${GREEN}Passed:  $CHECKS_PASSED${NC}"
echo "${YELLOW}Warnings: $CHECKS_WARNING${NC}"
echo "${RED}Failed:  $CHECKS_FAILED${NC}"
echo -e "Total:   $((CHECKS_PASSED + CHECKS_WARNING + CHECKS_FAILED))"
echo ""

if [[ "$CHECKS_FAILED" -eq 0 ]]; then
    echo "${GREEN}Overall Status: HEALTHY${NC}"
    exit 0
elif [[ "$CHECKS_FAILED" -le 2 ]]; then
    echo "${YELLOW}Overall Status: DEGRADED${NC}"
    exit 1
else
    echo "${RED}Overall Status: UNHEALTHY${NC}"
    exit 2
fi
