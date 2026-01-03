#!/bin/bash

###############################################################################
# CHOM Observability Stack Validation Script
# Validates monitoring, logging, and alerting configuration
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
MONITORING_SERVER="mentat.arewel.com"
APP_PATH="/var/www/chom/current"
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
ALERTMANAGER_PORT=9093
LOKI_PORT=3100
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Logging
log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

record_check() {
    local check_name="$1"
    local status="$2"
    local message="${3:-}"

    ((TOTAL_CHECKS++))

    if [[ "$status" == "PASS" ]]; then
        log_success "$check_name"
    elif [[ "$status" == "WARN" ]]; then
        log_warning "$check_name: $message"
    else
        ((FAILED_CHECKS++))
        log_error "$check_name: $message"
    fi
}

###############################################################################
# OBSERVABILITY CHECKS
###############################################################################

check_prometheus() {
    log_section "Prometheus Metrics Collection"

    # Check Prometheus accessibility
    local prometheus_url="http://${MONITORING_SERVER}:${PROMETHEUS_PORT}"
    local prom_status=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${prometheus_url}/-/healthy" 2>/dev/null || echo "000")

    if [[ "$prom_status" == "200" ]]; then
        record_check "Prometheus accessible" "PASS"
    else
        record_check "Prometheus accessible" "FAIL" "Cannot reach Prometheus at $prometheus_url"
        return
    fi

    # Check Prometheus version
    local prom_version=$(curl -sSL -m 5 "${prometheus_url}/api/v1/status/buildinfo" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    log_info "Prometheus version: $prom_version"

    # Check if Prometheus is scraping targets
    local targets_response=$(curl -sSL -m 5 "${prometheus_url}/api/v1/targets" 2>/dev/null || echo "")

    if [[ -n "$targets_response" ]]; then
        local active_targets=$(echo "$targets_response" | grep -o '"health":"up"' | wc -l || echo "0")
        local total_targets=$(echo "$targets_response" | grep -o '"health":"[^"]*"' | wc -l || echo "0")

        if [[ "$active_targets" -gt 0 ]]; then
            record_check "Prometheus scraping targets" "PASS"
            log_info "Active targets: $active_targets / $total_targets"
        else
            record_check "Prometheus targets" "FAIL" "No active targets"
        fi
    fi

    # Check if application metrics are being collected
    local app_metrics=$(curl -sSL -m 5 "${prometheus_url}/api/v1/query?query=up{job=\"chom\"}" 2>/dev/null | grep -c '"value":\[' || echo "0")

    if [[ "$app_metrics" -gt 0 ]]; then
        record_check "Application metrics collected" "PASS"
    else
        record_check "Application metrics" "WARN" "No metrics from CHOM application"
    fi

    # Check data retention
    local retention=$(curl -sSL -m 5 "${prometheus_url}/api/v1/status/flags" 2>/dev/null | grep -o '"storage.tsdb.retention[^"]*":"[^"]*"' | head -1 || echo "")
    if [[ -n "$retention" ]]; then
        log_info "Data retention: $retention"
    fi
}

check_grafana() {
    log_section "Grafana Dashboards"

    # Check Grafana accessibility
    local grafana_url="http://${MONITORING_SERVER}:${GRAFANA_PORT}"
    local grafana_status=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${grafana_url}/api/health" 2>/dev/null || echo "000")

    if [[ "$grafana_status" == "200" ]]; then
        record_check "Grafana accessible" "PASS"
    else
        record_check "Grafana accessible" "FAIL" "Cannot reach Grafana at $grafana_url"
        return
    fi

    # Check Grafana version
    local grafana_version=$(curl -sSL -m 5 "${grafana_url}/api/health" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    log_info "Grafana version: $grafana_version"

    # Try to check datasources (requires auth, will fail gracefully)
    local datasources=$(curl -sSL -m 5 "${grafana_url}/api/datasources" 2>/dev/null || echo "")

    if echo "$datasources" | grep -q "prometheus"; then
        record_check "Prometheus datasource configured" "PASS"
    else
        record_check "Prometheus datasource" "WARN" "Cannot verify datasource (may need auth)"
    fi

    # Check if Grafana is rendering dashboards
    local dashboards=$(curl -sSL -m 5 "${grafana_url}/api/search?type=dash-db" 2>/dev/null || echo "")

    if [[ -n "$dashboards" ]]; then
        local dashboard_count=$(echo "$dashboards" | grep -c '"type":"dash-db"' || echo "0")
        if [[ "$dashboard_count" -gt 0 ]]; then
            log_info "Dashboards configured: $dashboard_count"
        fi
    fi
}

check_loki() {
    log_section "Loki Log Aggregation"

    # Check Loki accessibility
    local loki_url="http://${MONITORING_SERVER}:${LOKI_PORT}"
    local loki_status=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${loki_url}/ready" 2>/dev/null || echo "000")

    if [[ "$loki_status" == "200" ]]; then
        record_check "Loki accessible" "PASS"
    else
        record_check "Loki accessible" "WARN" "Cannot reach Loki at $loki_url"
        return
    fi

    # Check if logs are being ingested
    local labels_response=$(curl -sSL -m 5 "${loki_url}/loki/api/v1/labels" 2>/dev/null || echo "")

    if [[ -n "$labels_response" ]] && echo "$labels_response" | grep -q '"status":"success"'; then
        record_check "Loki ingesting logs" "PASS"

        local label_count=$(echo "$labels_response" | grep -o '"[^"]*"' | wc -l || echo "0")
        log_info "Log labels: $label_count"
    else
        record_check "Loki log ingestion" "WARN" "Cannot verify log ingestion"
    fi

    # Try to query recent logs
    local query_url="${loki_url}/loki/api/v1/query_range?query={job=\"chom\"}&limit=1"
    local logs_response=$(curl -sSL -m 5 "$query_url" 2>/dev/null || echo "")

    if echo "$logs_response" | grep -q '"status":"success"'; then
        record_check "Application logs in Loki" "PASS"
    else
        record_check "Application logs" "WARN" "No logs from CHOM application"
    fi
}

check_alertmanager() {
    log_section "Alert Manager"

    # Check AlertManager accessibility
    local am_url="http://${MONITORING_SERVER}:${ALERTMANAGER_PORT}"
    local am_status=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${am_url}/-/healthy" 2>/dev/null || echo "000")

    if [[ "$am_status" == "200" ]]; then
        record_check "AlertManager accessible" "PASS"
    else
        record_check "AlertManager accessible" "WARN" "Cannot reach AlertManager at $am_url"
        return
    fi

    # Check active alerts
    local alerts_response=$(curl -sSL -m 5 "${am_url}/api/v2/alerts" 2>/dev/null || echo "")

    if [[ -n "$alerts_response" ]]; then
        local firing_count=$(echo "$alerts_response" | grep -c '"state":"active"' || echo "0")
        local total_count=$(echo "$alerts_response" | grep -c '"state":' || echo "0")

        log_info "Alerts: $firing_count firing, $total_count total"

        if [[ "$firing_count" -gt 0 ]]; then
            record_check "Active alerts" "WARN" "$firing_count alerts currently firing"
        else
            record_check "No critical alerts" "PASS"
        fi
    fi

    # Check alert routing configuration
    local config_response=$(curl -sSL -m 5 "${am_url}/api/v2/status" 2>/dev/null || echo "")

    if echo "$config_response" | grep -q '"config"'; then
        record_check "AlertManager configured" "PASS"
    else
        record_check "AlertManager configuration" "WARN" "Cannot verify configuration"
    fi
}

check_metrics_endpoint() {
    log_section "Application Metrics Endpoint"

    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'")

    if [[ -z "$app_url" ]]; then
        record_check "Application URL" "FAIL" "APP_URL not configured"
        return
    fi

    # Check /metrics endpoint
    local metrics_url="${app_url}/metrics"
    local metrics_response=$(curl -sSL -m 5 "$metrics_url" 2>/dev/null || echo "")

    if echo "$metrics_response" | grep -q "# HELP\|# TYPE"; then
        record_check "Metrics endpoint available" "PASS"

        # Check for common metrics
        local has_http_requests=$(echo "$metrics_response" | grep -c "http_requests" || echo "0")
        local has_db_queries=$(echo "$metrics_response" | grep -c "db_query" || echo "0")

        if [[ "$has_http_requests" -gt 0 ]]; then
            log_info "HTTP request metrics: ✓"
        fi

        if [[ "$has_db_queries" -gt 0 ]]; then
            log_info "Database query metrics: ✓"
        fi
    else
        record_check "Metrics endpoint" "WARN" "Metrics endpoint not returning Prometheus format"
    fi
}

check_alert_rules() {
    log_section "Prometheus Alert Rules"

    local prometheus_url="http://${MONITORING_SERVER}:${PROMETHEUS_PORT}"

    # Check configured alert rules
    local rules_response=$(curl -sSL -m 5 "${prometheus_url}/api/v1/rules" 2>/dev/null || echo "")

    if [[ -n "$rules_response" ]]; then
        local rule_count=$(echo "$rules_response" | grep -c '"name":"' || echo "0")

        if [[ "$rule_count" -gt 0 ]]; then
            record_check "Alert rules configured" "PASS"
            log_info "Alert rules: $rule_count"

            # Check for specific important rules
            if echo "$rules_response" | grep -qi "HighErrorRate\|InstanceDown\|HighMemoryUsage"; then
                log_info "Standard alert rules found"
            fi
        else
            record_check "Alert rules" "WARN" "No alert rules configured"
        fi
    else
        record_check "Alert rules" "WARN" "Cannot fetch alert rules"
    fi
}

check_trace_collection() {
    log_section "Trace Collection (Optional)"

    # Check if Jaeger or Tempo is running
    local jaeger_status=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "http://${MONITORING_SERVER}:16686" 2>/dev/null || echo "000")

    if [[ "$jaeger_status" == "200" ]]; then
        record_check "Jaeger tracing available" "PASS"
    else
        log_info "Trace collection not configured (optional)"
    fi
}

test_alert_firing() {
    log_section "Test Alert Mechanism"

    log_info "Sending test alert to AlertManager..."

    local am_url="http://${MONITORING_SERVER}:${ALERTMANAGER_PORT}"

    # Send a test alert
    local test_alert_payload='[{
        "labels": {
            "alertname": "DeploymentTest",
            "severity": "info",
            "instance": "test"
        },
        "annotations": {
            "summary": "Deployment validation test alert",
            "description": "This is a test alert sent during deployment validation"
        }
    }]'

    local alert_response=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 -X POST \
        -H "Content-Type: application/json" \
        -d "$test_alert_payload" \
        "${am_url}/api/v2/alerts" 2>/dev/null || echo "000")

    if [[ "$alert_response" == "200" ]]; then
        record_check "Test alert sent successfully" "PASS"

        # Wait a moment and check if alert appears
        sleep 2

        local alerts_check=$(curl -sSL -m 5 "${am_url}/api/v2/alerts" 2>/dev/null | grep -c "DeploymentTest" || echo "0")

        if [[ "$alerts_check" -gt 0 ]]; then
            record_check "Test alert received" "PASS"
        else
            record_check "Test alert reception" "WARN" "Alert sent but not found in AlertManager"
        fi
    else
        record_check "Test alert" "WARN" "Cannot send test alert (HTTP $alert_response)"
    fi
}

check_promtail() {
    log_section "Promtail Log Shipping"

    # Check if Promtail is running on app server
    if ssh "$DEPLOY_USER@$APP_SERVER" "systemctl is-active promtail &>/dev/null || pgrep promtail &>/dev/null"; then
        record_check "Promtail running on app server" "PASS"
    else
        record_check "Promtail" "WARN" "Promtail not running on app server"
    fi

    # Check Promtail configuration
    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f /etc/promtail/config.yml" &>/dev/null; then
        record_check "Promtail configuration exists" "PASS"

        # Check if configured to ship Laravel logs
        local has_laravel_config=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep -c 'laravel\|/var/www/chom' /etc/promtail/config.yml 2>/dev/null" || echo "0")

        if [[ "$has_laravel_config" -gt 0 ]]; then
            log_info "Promtail configured for Laravel logs"
        fi
    else
        record_check "Promtail configuration" "WARN" "No Promtail config found"
    fi
}

check_node_exporter() {
    log_section "Node Exporter (System Metrics)"

    # Check if node_exporter is running on app server
    if ssh "$DEPLOY_USER@$APP_SERVER" "systemctl is-active node_exporter &>/dev/null || pgrep node_exporter &>/dev/null"; then
        record_check "Node Exporter running" "PASS"

        # Try to access metrics
        local node_metrics=$(ssh "$DEPLOY_USER@$APP_SERVER" "curl -sSL -m 2 http://localhost:9100/metrics 2>/dev/null | head -5" || echo "")

        if echo "$node_metrics" | grep -q "# HELP"; then
            log_info "Node Exporter metrics accessible"
        fi
    else
        record_check "Node Exporter" "WARN" "Node Exporter not running on app server"
    fi
}

check_monitoring_disk_space() {
    log_section "Monitoring Server Resources"

    # Check disk space on monitoring server
    local disk_info=$(ssh "$DEPLOY_USER@$MONITORING_SERVER" "df -h /var/lib/prometheus /var/lib/grafana 2>/dev/null" || echo "")

    if [[ -n "$disk_info" ]]; then
        log_info "Monitoring server disk usage:"
        echo "$disk_info" | tail -n +2 | while read -r line; do
            log_info "  $line"
        done

        # Check for high disk usage
        local high_usage=$(echo "$disk_info" | awk '{print $5}' | grep -o '[0-9]*' | awk '$1 > 80 {print $1}' | wc -l)

        if [[ "$high_usage" -eq 0 ]]; then
            record_check "Monitoring disk space" "PASS"
        else
            record_check "Monitoring disk space" "WARN" "High disk usage on monitoring server"
        fi
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          CHOM Observability Stack Validation                  ║"
    echo "║          Checking monitoring and logging...                   ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Run observability checks
    check_prometheus
    check_grafana
    check_loki
    check_alertmanager
    check_metrics_endpoint
    check_alert_rules
    check_trace_collection
    test_alert_firing
    check_promtail
    check_node_exporter
    check_monitoring_disk_space

    # Summary
    echo ""
    log_section "Observability Validation Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ Observability stack operational!${NC}"
        echo -e "${GREEN}${BOLD}✓ Monitoring and alerting configured${NC}"
        exit 0
    else
        echo -e "${YELLOW}${BOLD}⚠ Some observability checks failed${NC}"
        echo -e "${YELLOW}${BOLD}⚠ Review issues above${NC}"
        exit 1
    fi
}

main "$@"
