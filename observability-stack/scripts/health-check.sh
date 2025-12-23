#!/bin/bash
#===============================================================================
# Observability Stack Health Check
# Quick verification that all components are running
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_service() {
    local svc="$1"
    local status
    status=$(systemctl is-active "$svc" 2>/dev/null)
    if [[ "$status" == "active" ]]; then
        printf "  ${GREEN}✓${NC} %-20s ${GREEN}%s${NC}\n" "$svc" "$status"
        return 0
    elif [[ "$status" == "inactive" ]] || [[ "$status" == "failed" ]]; then
        printf "  ${RED}✗${NC} %-20s ${RED}%s${NC}\n" "$svc" "$status"
        return 1
    else
        printf "  ${YELLOW}-${NC} %-20s ${YELLOW}%s${NC}\n" "$svc" "not installed"
        return 2
    fi
}

check_endpoint() {
    local name="$1"
    local url="$2"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    if [[ "$code" == "200" ]]; then
        printf "  ${GREEN}✓${NC} %-20s ${GREEN}%s${NC}\n" "$name" "$code"
        return 0
    elif [[ "$code" == "000" ]]; then
        printf "  ${RED}✗${NC} %-20s ${RED}%s${NC}\n" "$name" "unreachable"
        return 1
    else
        printf "  ${YELLOW}!${NC} %-20s ${YELLOW}%s${NC}\n" "$name" "$code"
        return 1
    fi
}

echo ""
echo "=========================================="
echo "  Observability Stack Health Check"
echo "=========================================="

# Core Services
echo ""
echo "Core Services:"
check_service "prometheus"
check_service "grafana-server"
check_service "loki"
check_service "alertmanager"
check_service "nginx"

# Exporters
echo ""
echo "Exporters:"
check_service "node_exporter"
check_service "nginx_exporter"
check_service "mysqld_exporter"
check_service "phpfpm_exporter"
check_service "promtail"

# Endpoints
echo ""
echo "Endpoints (HTTP status):"
check_endpoint "Grafana (3000)" "http://localhost:3000/api/health"
check_endpoint "Prometheus (9090)" "http://localhost:9090/-/ready"
check_endpoint "Loki (3100)" "http://localhost:3100/ready"
check_endpoint "Alertmanager (9093)" "http://localhost:9093/api/v2/status"

# Exporter Metrics
echo ""
echo "Exporter Metrics:"
check_endpoint "Node (9100)" "http://localhost:9100/metrics"
check_endpoint "Nginx (9113)" "http://localhost:9113/metrics"
check_endpoint "MySQL (9104)" "http://localhost:9104/metrics"
check_endpoint "PHP-FPM (9253)" "http://localhost:9253/metrics"

# Prometheus Targets (if prometheus is up)
if curl -s "http://localhost:9090/-/ready" &>/dev/null; then
    echo ""
    echo "Prometheus Targets:"
    targets=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null)
    if [[ -n "$targets" ]]; then
        up=$(echo "$targets" | grep -o '"health":"up"' | wc -l)
        down=$(echo "$targets" | grep -o '"health":"down"' | wc -l)
        unknown=$(echo "$targets" | grep -o '"health":"unknown"' | wc -l)
        printf "  ${GREEN}✓${NC} Up: %d  " "$up"
        [[ "$down" -gt 0 ]] && printf "${RED}✗${NC} Down: %d  " "$down"
        [[ "$unknown" -gt 0 ]] && printf "${YELLOW}?${NC} Unknown: %d" "$unknown"
        echo ""
    fi
fi

echo ""
echo "=========================================="
echo ""
