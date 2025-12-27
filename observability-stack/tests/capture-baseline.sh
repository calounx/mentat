#!/bin/bash
#===============================================================================
# Baseline Metrics Capture Script
# Captures current state before upgrade for comparison
#===============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASELINE_DIR="/tmp/observability-baseline-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BASELINE_DIR"

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "  Baseline Metrics Capture"
echo "=========================================="
echo ""

log_info "Capturing baseline to: $BASELINE_DIR"
echo ""

#===============================================================================
# Component Versions
#===============================================================================
log_info "Capturing component versions..."

{
    echo "=== Component Versions ==="
    node_exporter --version 2>&1 || echo "node_exporter: not installed"
    nginx_exporter --version 2>&1 || echo "nginx_exporter: not installed"
    mysqld_exporter --version 2>&1 || echo "mysqld_exporter: not installed"
    phpfpm_exporter --version 2>&1 || echo "phpfpm_exporter: not installed"
    fail2ban_exporter --version 2>&1 || echo "fail2ban_exporter: not installed"
    promtail --version 2>&1 || echo "promtail: not installed"
    prometheus --version 2>&1 || echo "prometheus: not installed"
    loki --version 2>&1 || echo "loki: not installed"
    grafana-server --version 2>&1 || echo "grafana: not installed"
    alertmanager --version 2>&1 || echo "alertmanager: not installed"
} > "$BASELINE_DIR/versions.txt"

log_success "Versions captured"

#===============================================================================
# Service Status
#===============================================================================
log_info "Capturing service status..."

{
    echo "=== Service Status ==="
    systemctl status node_exporter --no-pager || true
    systemctl status nginx_exporter --no-pager || true
    systemctl status mysqld_exporter --no-pager || true
    systemctl status phpfpm_exporter --no-pager || true
    systemctl status fail2ban_exporter --no-pager || true
    systemctl status promtail --no-pager || true
    systemctl status prometheus --no-pager || true
    systemctl status loki --no-pager || true
    systemctl status grafana-server --no-pager || true
    systemctl status alertmanager --no-pager || true
} > "$BASELINE_DIR/service-status.txt"

log_success "Service status captured"

#===============================================================================
# Prometheus Targets
#===============================================================================
log_info "Capturing Prometheus targets..."

curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.' > "$BASELINE_DIR/prometheus-targets.json" || log_error "Failed to capture Prometheus targets"

TARGETS_UP=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' | wc -l)
echo "Targets up: $TARGETS_UP" > "$BASELINE_DIR/prometheus-targets-summary.txt"

log_success "Prometheus targets captured ($TARGETS_UP up)"

#===============================================================================
# Alert Rules
#===============================================================================
log_info "Capturing alert rules..."

curl -s http://localhost:9090/api/v1/rules 2>/dev/null | jq '.' > "$BASELINE_DIR/prometheus-rules.json" || log_error "Failed to capture alert rules"

RULES_COUNT=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null | jq '[.data.groups[].rules[]] | length')
echo "Total rules: $RULES_COUNT" > "$BASELINE_DIR/prometheus-rules-summary.txt"

log_success "Alert rules captured ($RULES_COUNT rules)"

#===============================================================================
# Metrics Endpoint Tests
#===============================================================================
log_info "Testing metrics endpoints..."

{
    echo "=== Metrics Endpoints ==="
    for endpoint in "9100:node_exporter" "9113:nginx_exporter" "9104:mysqld_exporter" "9253:phpfpm_exporter" "9191:fail2ban_exporter"; do
        PORT="${endpoint%%:*}"
        NAME="${endpoint##*:}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/metrics 2>/dev/null || echo "000")
        echo "$NAME (port $PORT): HTTP $HTTP_CODE"
    done
} > "$BASELINE_DIR/metrics-endpoints.txt"

log_success "Metrics endpoints tested"

#===============================================================================
# Performance Metrics
#===============================================================================
log_info "Capturing performance metrics..."

{
    echo "=== Performance Baseline ==="

    # Prometheus query latency
    echo "Prometheus Query Latency:"
    time curl -s 'http://localhost:9090/api/v1/query?query=up' > /dev/null 2>&1

    # Process memory usage
    echo ""
    echo "Memory Usage:"
    ps aux | grep -E "prometheus|loki|grafana" | grep -v grep

    # Scrape duration
    echo ""
    echo "Scrape Duration:"
    curl -s 'http://localhost:9090/api/v1/query?query=scrape_duration_seconds' 2>/dev/null | jq -r '.data.result[] | "\(.metric.job): \(.value[1])s"'

    # Loki query latency
    echo ""
    echo "Loki Query Latency:"
    time curl -s 'http://localhost:3100/loki/api/v1/query?query={job="varlogs"}&limit=10' > /dev/null 2>&1

} > "$BASELINE_DIR/performance.txt" 2>&1

log_success "Performance metrics captured"

#===============================================================================
# Storage Usage
#===============================================================================
log_info "Capturing storage usage..."

{
    echo "=== Storage Usage ==="
    df -h | grep -E "/$|/var"
    echo ""
    echo "Prometheus data:"
    du -sh /var/lib/prometheus/ 2>/dev/null || echo "Not accessible"
    echo ""
    echo "Loki data:"
    du -sh /var/lib/loki/ 2>/dev/null || echo "Not accessible"
    echo ""
    echo "Grafana data:"
    du -sh /var/lib/grafana/ 2>/dev/null || echo "Not accessible"
} > "$BASELINE_DIR/storage.txt"

log_success "Storage usage captured"

#===============================================================================
# Grafana Dashboards
#===============================================================================
log_info "Capturing Grafana dashboards..."

curl -s -u admin:admin http://localhost:3000/api/search?query=& 2>/dev/null | jq '.' > "$BASELINE_DIR/grafana-dashboards.json" || log_error "Failed to capture Grafana dashboards"

DASH_COUNT=$(curl -s -u admin:admin http://localhost:3000/api/search?query=& 2>/dev/null | jq '. | length')
echo "Dashboard count: $DASH_COUNT" > "$BASELINE_DIR/grafana-dashboards-summary.txt"

log_success "Grafana dashboards captured ($DASH_COUNT dashboards)"

#===============================================================================
# Loki Status
#===============================================================================
log_info "Capturing Loki status..."

{
    echo "=== Loki Status ==="
    curl -s http://localhost:3100/ready 2>/dev/null && echo "Loki: ready"

    echo ""
    echo "Loki labels:"
    curl -s 'http://localhost:3100/loki/api/v1/labels' 2>/dev/null | jq -r '.data[]'

    echo ""
    echo "Promtail metrics:"
    curl -s http://localhost:9080/metrics 2>/dev/null | grep "promtail_" | grep -E "_total|_active"
} > "$BASELINE_DIR/loki-status.txt"

log_success "Loki status captured"

#===============================================================================
# System Resources
#===============================================================================
log_info "Capturing system resources..."

{
    echo "=== System Resources ==="
    echo "CPU:"
    top -bn1 | head -20
    echo ""
    echo "Memory:"
    free -h
    echo ""
    echo "Load Average:"
    uptime
    echo ""
    echo "Network:"
    ss -tlnp | grep -E ":9090|:9100|:3000|:3100"
} > "$BASELINE_DIR/system-resources.txt"

log_success "System resources captured"

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "=========================================="
echo "  Baseline Capture Complete"
echo "=========================================="
echo ""
echo "Baseline saved to: $BASELINE_DIR"
echo ""
echo "Files created:"
ls -lh "$BASELINE_DIR"
echo ""

# Create summary report
{
    echo "BASELINE CAPTURE SUMMARY"
    echo "========================"
    echo "Date: $(date)"
    echo "Location: $BASELINE_DIR"
    echo ""
    echo "Component Status:"
    grep -E "Active:|active" "$BASELINE_DIR/service-status.txt" | grep -v "inactive" | wc -l
    echo ""
    echo "Prometheus Targets Up: $TARGETS_UP"
    echo "Alert Rules Loaded: $RULES_COUNT"
    echo "Grafana Dashboards: $DASH_COUNT"
    echo ""
    echo "Storage:"
    grep "prometheus" "$BASELINE_DIR/storage.txt" || echo "N/A"
    grep "loki" "$BASELINE_DIR/storage.txt" || echo "N/A"
} > "$BASELINE_DIR/SUMMARY.txt"

cat "$BASELINE_DIR/SUMMARY.txt"

log_success "Baseline capture complete!"
echo ""
echo "Use this baseline for comparison after upgrade."
echo "Location: $BASELINE_DIR"
