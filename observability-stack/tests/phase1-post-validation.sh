#!/bin/bash
#===============================================================================
# Phase 1 Post-Upgrade Validation
# Validates all 5 exporter upgrades completed successfully
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
echo "  Phase 1: Exporter Validation"
echo "=========================================="
echo ""

#===============================================================================
# Expected Versions
#===============================================================================
declare -A EXPECTED_VERSIONS=(
    ["node_exporter"]="1.9.1"
    ["nginx_exporter"]="1.5.1"
    ["mysqld_exporter"]="0.18.0"
    ["phpfpm_exporter"]="2.3.0"
    ["fail2ban_exporter"]="0.5.0"
)

#===============================================================================
# Version Checks
#===============================================================================
echo -e "${BLUE}=== Version Verification ===${NC}"

for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    VERSION=$($exporter --version 2>&1 | grep -oP '(?<=version )\d+\.\d+\.\d+' | head -1 || echo "unknown")
    EXPECTED="${EXPECTED_VERSIONS[$exporter]}"

    if [[ "$VERSION" == "$EXPECTED" ]]; then
        log_pass "$exporter: $VERSION"
    else
        log_fail "$exporter: $VERSION (expected $EXPECTED)"
    fi
done

echo ""

#===============================================================================
# Service Status
#===============================================================================
echo -e "${BLUE}=== Service Status ===${NC}"

for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    STATUS=$(systemctl is-active "$exporter" 2>/dev/null || echo "inactive")

    if [[ "$STATUS" == "active" ]]; then
        log_pass "$exporter: active"
    else
        log_fail "$exporter: $STATUS"
    fi
done

echo ""

#===============================================================================
# Metrics Endpoints
#===============================================================================
echo -e "${BLUE}=== Metrics Endpoints ===${NC}"

declare -A EXPORTER_PORTS=(
    ["node_exporter"]="9100"
    ["nginx_exporter"]="9113"
    ["mysqld_exporter"]="9104"
    ["phpfpm_exporter"]="9253"
    ["fail2ban_exporter"]="9191"
)

for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    PORT="${EXPORTER_PORTS[$exporter]}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/metrics 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" == "200" ]]; then
        log_pass "$exporter (port $PORT): HTTP $HTTP_CODE"
    else
        log_fail "$exporter (port $PORT): HTTP $HTTP_CODE"
    fi
done

echo ""

#===============================================================================
# Prometheus Scraping
#===============================================================================
echo -e "${BLUE}=== Prometheus Target Health ===${NC}"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
        HEALTH=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | \
                 jq -r ".data.activeTargets[] | select(.labels.job==\"$exporter\") | .health" | head -1)

        if [[ "$HEALTH" == "up" ]]; then
            log_pass "$exporter target: $HEALTH"
        else
            log_fail "$exporter target: ${HEALTH:-not found}"
        fi
    done
else
    log_fail "Prometheus not responding, cannot check targets"
fi

echo ""

#===============================================================================
# Key Metrics Present
#===============================================================================
echo -e "${BLUE}=== Key Metrics Validation ===${NC}"

# Node exporter metrics
if curl -s http://localhost:9100/metrics | grep -q "node_cpu_seconds_total"; then
    log_pass "node_exporter: CPU metrics present"
else
    log_fail "node_exporter: CPU metrics missing"
fi

if curl -s http://localhost:9100/metrics | grep -q "node_memory_MemTotal_bytes"; then
    log_pass "node_exporter: Memory metrics present"
else
    log_fail "node_exporter: Memory metrics missing"
fi

# Nginx exporter metrics
if curl -s http://localhost:9113/metrics | grep -q "nginx_connections_active"; then
    log_pass "nginx_exporter: Connection metrics present"
else
    log_fail "nginx_exporter: Connection metrics missing"
fi

# MySQL exporter metrics
if curl -s http://localhost:9104/metrics | grep -q "mysql_up"; then
    MYSQL_UP=$(curl -s http://localhost:9104/metrics | grep "^mysql_up " | awk '{print $2}')
    if [[ "$MYSQL_UP" == "1" ]]; then
        log_pass "mysqld_exporter: MySQL connection up"
    else
        log_fail "mysqld_exporter: MySQL connection down"
    fi
else
    log_fail "mysqld_exporter: mysql_up metric missing"
fi

# PHP-FPM exporter metrics
if curl -s http://localhost:9253/metrics | grep -q "phpfpm_up"; then
    PHPFPM_UP=$(curl -s http://localhost:9253/metrics | grep "^phpfpm_up " | awk '{print $2}')
    if [[ "$PHPFPM_UP" == "1" ]]; then
        log_pass "phpfpm_exporter: PHP-FPM connection up"
    else
        log_fail "phpfpm_exporter: PHP-FPM connection down"
    fi
else
    log_fail "phpfpm_exporter: phpfpm_up metric missing"
fi

# Fail2ban exporter metrics
if curl -s http://localhost:9191/metrics | grep -q "fail2ban_up"; then
    log_pass "fail2ban_exporter: Metrics present"
else
    log_fail "fail2ban_exporter: Metrics missing"
fi

echo ""

#===============================================================================
# Error Log Checks
#===============================================================================
echo -e "${BLUE}=== Recent Error Checks ===${NC}"

for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    ERRORS=$(journalctl -u "$exporter" -n 20 --no-pager --since "5 minutes ago" 2>/dev/null | \
             grep -i "error" | grep -v "level=error msg=\"No such file\"" | wc -l)

    if [[ "$ERRORS" -eq 0 ]]; then
        log_pass "$exporter: no errors in logs"
    else
        log_fail "$exporter: $ERRORS errors in last 5 minutes"
        journalctl -u "$exporter" -n 5 --no-pager | grep -i "error" || true
    fi
done

echo ""

#===============================================================================
# Data Continuity Check
#===============================================================================
echo -e "${BLUE}=== Data Continuity ===${NC}"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    # Check if metrics from last 10 minutes are available
    for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
        SAMPLES=$(curl -s "http://localhost:9090/api/v1/query_range?query=up{job=\"$exporter\"}&start=$(date -d '10 minutes ago' +%s)&end=$(date +%s)&step=60s" 2>/dev/null | \
                  jq -r '.data.result[0].values | length' 2>/dev/null || echo "0")

        if [[ "$SAMPLES" -gt 5 ]]; then
            log_pass "$exporter: continuous data (${SAMPLES} samples)"
        else
            log_fail "$exporter: data gaps detected (${SAMPLES} samples)"
        fi
    done
else
    log_fail "Prometheus not responding, cannot check data continuity"
fi

echo ""

#===============================================================================
# Summary
#===============================================================================
echo "=========================================="
echo "  Phase 1 Validation Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "Total:  $((PASSED + FAILED))"
echo ""

if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${GREEN}Phase 1: ALL EXPORTERS UPGRADED SUCCESSFULLY${NC}"
    echo ""
    echo "Ready to proceed to Phase 2 (Prometheus)"
    exit 0
else
    echo -e "${RED}Phase 1: VALIDATION FAILED${NC}"
    echo ""
    echo "DO NOT PROCEED to Phase 2 until issues are resolved"
    exit 1
fi
