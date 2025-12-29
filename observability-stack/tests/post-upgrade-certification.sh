#!/bin/bash
#===============================================================================
# Post-Upgrade Certification Validation Script
# Comprehensive validation of all upgrade phases and components
#===============================================================================

set -euo pipefail

# Colors
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Certification data
CERT_DATA_FILE="/tmp/upgrade-cert-data-$(date +%Y%m%d-%H%M%S).json"

# Initialize certification data structure
cat > "$CERT_DATA_FILE" <<EOF
{
  "certification_date": "$(date -Iseconds)",
  "certification_type": "post_upgrade_validation",
  "overall_status": "pending",
  "components": {},
  "health_checks": {},
  "metrics_validation": {},
  "issues": [],
  "recommendations": []
}
EOF

log_pass() {
    echo "${GREEN}[PASS]${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_fail() {
    echo "${RED}[FAIL]${NC} $1"
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
    # Record failure in certification data
    jq ".issues += [\"$1\"]" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
    ((WARNING_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo ""
    echo "${CYAN}========================================${NC}"
    echo "${CYAN}  $1${NC}"
    echo "${CYAN}========================================${NC}"
}

#===============================================================================
# Banner
#===============================================================================
clear
echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                                                                    ║"
echo "║         POST-UPGRADE CERTIFICATION VALIDATION                      ║"
echo "║         Observability Stack v3.0.0                                 ║"
echo "║                                                                    ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Certification Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Certification ID: CERT-$(date +%Y%m%d-%H%M%S)"
echo "Validation Mode: COMPREHENSIVE"
echo ""

#===============================================================================
# 1. COMPONENT VERSION VERIFICATION
#===============================================================================
log_section "1. Component Version Verification"

# Expected versions (targets from upgrade)
declare -A EXPECTED_VERSIONS=(
    ["node_exporter"]="1.9.1"
    ["nginx_exporter"]="1.5.1"
    ["mysqld_exporter"]="0.18.0"
    ["phpfpm_exporter"]="2.3.0"
    ["fail2ban_exporter"]="0.5.0"
    ["prometheus"]="2.48.1"
    ["loki"]="2.9.3"
    ["grafana-server"]="10.2.3"
    ["alertmanager"]="0.26.0"
)

echo "Checking installed versions against targets..."
echo ""

for component in "${!EXPECTED_VERSIONS[@]}"; do
    expected="${EXPECTED_VERSIONS[$component]}"

    case "$component" in
        prometheus)
            actual=$(prometheus --version 2>&1 | grep -oP 'prometheus, version \K[\d.]+' | head -1 || echo "unknown")
            ;;
        loki)
            actual=$(loki --version 2>&1 | grep -oP 'loki, version \K[\d.]+' | head -1 || echo "unknown")
            ;;
        grafana-server)
            actual=$(grafana-server -v 2>&1 | grep -oP 'Version \K[\d.]+' | head -1 || echo "unknown")
            ;;
        alertmanager)
            actual=$(alertmanager --version 2>&1 | grep -oP 'alertmanager, version \K[\d.]+' | head -1 || echo "unknown")
            ;;
        *)
            actual=$($component --version 2>&1 | grep -oP '(?<=version |v)\d+\.\d+\.\d+' | head -1 || echo "unknown")
            ;;
    esac

    if [[ "$actual" == "$expected" ]]; then
        log_pass "$component: $actual (matches target)"
        jq ".components.\"$component\" = {\"version\": \"$actual\", \"status\": \"pass\"}" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"
    elif [[ "$actual" == "unknown" ]]; then
        log_warn "$component: version unknown (not installed or not in PATH)"
        jq ".components.\"$component\" = {\"version\": \"unknown\", \"status\": \"warn\"}" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"
    else
        log_fail "$component: $actual (expected $expected)"
        jq ".components.\"$component\" = {\"version\": \"$actual\", \"expected\": \"$expected\", \"status\": \"fail\"}" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"
    fi
done

#===============================================================================
# 2. SERVICE HEALTH CHECKS
#===============================================================================
log_section "2. Service Health Status"

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

echo "Checking systemd service status..."
echo ""

for service in "${SERVICES[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
    enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")

    if [[ "$status" == "active" ]]; then
        uptime=$(systemctl show "$service" -p ActiveEnterTimestamp --value)
        log_pass "$service: active (enabled: $enabled) - Up since: $uptime"
        jq ".health_checks.\"$service\" = {\"status\": \"active\", \"enabled\": \"$enabled\"}" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"
    elif [[ "$status" == "unknown" ]]; then
        log_warn "$service: not installed or not a service"
    else
        log_fail "$service: $status (enabled: $enabled)"
        jq ".health_checks.\"$service\" = {\"status\": \"$status\", \"enabled\": \"$enabled\"}" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"
    fi
done

#===============================================================================
# 3. METRICS ENDPOINT VALIDATION
#===============================================================================
log_section "3. Metrics Endpoint Validation"

declare -A ENDPOINTS=(
    ["node_exporter"]="http://localhost:9100/metrics"
    ["nginx_exporter"]="http://localhost:9113/metrics"
    ["mysqld_exporter"]="http://localhost:9104/metrics"
    ["phpfpm_exporter"]="http://localhost:9253/metrics"
    ["fail2ban_exporter"]="http://localhost:9191/metrics"
    ["promtail"]="http://localhost:9080/metrics"
    ["prometheus_ready"]="http://localhost:9090/-/ready"
    ["prometheus_healthy"]="http://localhost:9090/-/healthy"
    ["loki_ready"]="http://localhost:3100/ready"
    ["loki_metrics"]="http://localhost:3100/metrics"
    ["grafana_health"]="http://localhost:3000/api/health"
    ["alertmanager_healthy"]="http://localhost:9093/-/healthy"
)

echo "Testing HTTP endpoints..."
echo ""

for endpoint_name in "${!ENDPOINTS[@]}"; do
    url="${ENDPOINTS[$endpoint_name]}"

    response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" --max-time 5 "$url" 2>/dev/null || echo "000|0")
    http_code=$(echo "$response" | cut -d'|' -f1)
    time_total=$(echo "$response" | cut -d'|' -f2)

    if [[ "$http_code" == "200" ]]; then
        time_ms=$(echo "$time_total * 1000" | bc)
        log_pass "$endpoint_name: HTTP $http_code (${time_ms}ms)"
    elif [[ "$http_code" == "000" ]]; then
        log_fail "$endpoint_name: unreachable (timeout)"
    else
        log_fail "$endpoint_name: HTTP $http_code"
    fi
done

#===============================================================================
# 4. PROMETHEUS TARGET VALIDATION
#===============================================================================
log_section "4. Prometheus Target Health"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    echo "Querying Prometheus targets..."
    echo ""

    targets_json=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null)

    # Count targets by health status
    targets_up=$(echo "$targets_json" | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' | wc -l)
    targets_down=$(echo "$targets_json" | jq -r '.data.activeTargets[] | select(.health=="down") | .labels.job' | wc -l)
    targets_unknown=$(echo "$targets_json" | jq -r '.data.activeTargets[] | select(.health=="unknown") | .labels.job' | wc -l)

    echo "Target Summary:"
    echo "  Up: $targets_up"
    echo "  Down: $targets_down"
    echo "  Unknown: $targets_unknown"
    echo ""

    if [[ "$targets_up" -gt 0 && "$targets_down" -eq 0 ]]; then
        log_pass "All Prometheus targets are UP ($targets_up targets)"
    elif [[ "$targets_down" -gt 0 ]]; then
        log_fail "Some targets are DOWN ($targets_down/$((targets_up + targets_down)))"
        echo ""
        echo "Down targets:"
        echo "$targets_json" | jq -r '.data.activeTargets[] | select(.health=="down") | "  - \(.labels.job): \(.lastError)"'
    else
        log_warn "No targets found or all unknown"
    fi

    # List all targets
    echo ""
    echo "Active Targets by Job:"
    echo "$targets_json" | jq -r '.data.activeTargets[] | "  - \(.labels.job) (\(.labels.instance)): \(.health)"' | sort -u

else
    log_fail "Prometheus not responding - cannot check targets"
fi

#===============================================================================
# 5. METRICS GAP DETECTION
#===============================================================================
log_section "5. Metrics Data Continuity Check"

if curl -s http://localhost:9090/-/ready &>/dev/null; then
    echo "Checking for metrics gaps in last 30 minutes..."
    echo ""

    COMPONENTS=("node_exporter" "nginx_exporter" "mysqld_exporter" "phpfpm_exporter" "fail2ban_exporter" "prometheus" "loki")

    for component in "${COMPONENTS[@]}"; do
        # Query last 30 minutes with 15s intervals
        query="up{job=\"$component\"}"
        start=$(date -d '30 minutes ago' +%s)
        end=$(date +%s)

        result=$(curl -s "http://localhost:9090/api/v1/query_range?query=${query}&start=${start}&end=${end}&step=15s" 2>/dev/null)

        if [[ -n "$result" ]]; then
            # Count data points
            data_points=$(echo "$result" | jq -r '.data.result[0].values | length' 2>/dev/null || echo "0")
            expected_points=$((30 * 4)) # 30 min * 4 samples/min = 120

            if [[ "$data_points" -ge $((expected_points - 10)) ]]; then
                coverage=$(echo "scale=1; $data_points * 100 / $expected_points" | bc)
                log_pass "$component: ${data_points}/${expected_points} samples (${coverage}% coverage)"
            else
                coverage=$(echo "scale=1; $data_points * 100 / $expected_points" | bc)
                gap_seconds=$(echo "scale=0; (($expected_points - $data_points) * 15)" | bc)
                log_warn "$component: ${data_points}/${expected_points} samples (${coverage}% coverage, ~${gap_seconds}s gap)"
            fi
        else
            log_fail "$component: no data found in Prometheus"
        fi
    done
else
    log_fail "Prometheus not responding - cannot check metrics continuity"
fi

#===============================================================================
# 6. GRAFANA DASHBOARD VALIDATION
#===============================================================================
log_section "6. Grafana Dashboard Validation"

if curl -s http://localhost:3000/api/health &>/dev/null; then
    echo "Checking Grafana dashboards and data sources..."
    echo ""

    # Check data sources (use default admin:admin if no custom creds)
    datasources=$(curl -s -u admin:admin http://localhost:3000/api/datasources 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")

    if [[ "$datasources" -ge 2 ]]; then
        log_pass "Grafana data sources: $datasources configured"

        # Test Prometheus data source connectivity
        prom_test=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up' 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error")
        if [[ "$prom_test" == "success" ]]; then
            log_pass "Prometheus data source: connected and queryable"
        else
            log_fail "Prometheus data source: connection error"
        fi

        # Test Loki data source connectivity
        loki_test=$(curl -s -u admin:admin 'http://localhost:3000/api/datasources/proxy/2/loki/api/v1/labels' 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error")
        if [[ "$loki_test" == "success" ]]; then
            log_pass "Loki data source: connected and queryable"
        else
            log_warn "Loki data source: connection issue (may be expected if Loki has no data)"
        fi
    else
        log_fail "Grafana data sources: $datasources (expected at least 2)"
    fi

    # Check dashboards
    dashboards=$(curl -s -u admin:admin http://localhost:3000/api/search?query=& 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
    if [[ "$dashboards" -gt 0 ]]; then
        log_pass "Grafana dashboards: $dashboards loaded"
        echo ""
        echo "Available dashboards:"
        curl -s -u admin:admin http://localhost:3000/api/search?query=& 2>/dev/null | jq -r '.[] | "  - \(.title)"'
    else
        log_warn "Grafana dashboards: none found (may need provisioning)"
    fi
else
    log_fail "Grafana not responding - cannot validate dashboards"
fi

#===============================================================================
# 7. ALERT DELIVERY TEST
#===============================================================================
log_section "7. Alert Manager Validation"

if curl -s http://localhost:9093/-/healthy &>/dev/null; then
    echo "Checking Alertmanager configuration..."
    echo ""

    # Check alert rules loaded in Prometheus
    rules_json=$(curl -s http://localhost:9090/api/v1/rules 2>/dev/null)
    total_rules=$(echo "$rules_json" | jq '[.data.groups[].rules[]] | length' 2>/dev/null || echo "0")
    firing_alerts=$(echo "$rules_json" | jq '[.data.groups[].rules[] | select(.state=="firing")] | length' 2>/dev/null || echo "0")

    if [[ "$total_rules" -gt 0 ]]; then
        log_pass "Alert rules loaded: $total_rules rules configured"

        if [[ "$firing_alerts" -gt 0 ]]; then
            log_warn "Currently firing alerts: $firing_alerts"
            echo ""
            echo "Firing alerts:"
            echo "$rules_json" | jq -r '.data.groups[].rules[] | select(.state=="firing") | "  - \(.name): \(.alerts[0].labels.severity // "unknown")"'
        else
            log_pass "No alerts currently firing"
        fi
    else
        log_warn "No alert rules loaded in Prometheus"
    fi

    # Check Alertmanager status
    am_status=$(curl -s http://localhost:9093/api/v2/status 2>/dev/null | jq -r '.cluster.status' 2>/dev/null || echo "unknown")
    if [[ "$am_status" == "ready" ]]; then
        log_pass "Alertmanager cluster status: $am_status"
    else
        log_warn "Alertmanager status: $am_status"
    fi
else
    log_fail "Alertmanager not responding - cannot validate alerts"
fi

#===============================================================================
# 8. BACKUP VERIFICATION
#===============================================================================
log_section "8. Backup Verification"

echo "Checking for upgrade backups..."
echo ""

BACKUP_BASE="/var/backups/observability-stack"
UPGRADE_BACKUP_BASE="/var/lib/observability-upgrades/backups"

# Check standard backups
if [[ -d "$BACKUP_BASE" ]]; then
    backup_count=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "20*" | wc -l)
    if [[ "$backup_count" -gt 0 ]]; then
        latest_backup=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "20*" | sort -r | head -1)
        backup_size=$(du -sh "$latest_backup" 2>/dev/null | awk '{print $1}')
        log_pass "Standard backups found: $backup_count backups (latest: $(basename "$latest_backup"), size: $backup_size)"
    else
        log_warn "No standard backups found in $BACKUP_BASE"
    fi
else
    log_warn "Standard backup directory not found: $BACKUP_BASE"
fi

# Check upgrade backups
if [[ -d "$UPGRADE_BACKUP_BASE" ]]; then
    components_backed_up=$(find "$UPGRADE_BACKUP_BASE" -maxdepth 1 -type d ! -name "backups" | wc -l)
    if [[ "$components_backed_up" -gt 0 ]]; then
        log_pass "Upgrade backups found: $components_backed_up components have backups"
        echo ""
        echo "Components with upgrade backups:"
        for comp_dir in "$UPGRADE_BACKUP_BASE"/*; do
            if [[ -d "$comp_dir" && "$(basename "$comp_dir")" != "backups" ]]; then
                comp_name=$(basename "$comp_dir")
                backup_count=$(find "$comp_dir" -maxdepth 1 -type d -name "20*" | wc -l)
                echo "  - $comp_name: $backup_count backup(s)"
            fi
        done
    else
        log_warn "No upgrade backups found in $UPGRADE_BACKUP_BASE"
    fi
else
    log_warn "Upgrade backup directory not found: $UPGRADE_BACKUP_BASE"
fi

#===============================================================================
# 9. STORAGE AND PERFORMANCE CHECKS
#===============================================================================
log_section "9. Storage and Performance"

echo "Checking storage usage..."
echo ""

# Disk space
root_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ "$root_usage" -lt 80 ]]; then
    log_pass "Root filesystem usage: ${root_usage}%"
elif [[ "$root_usage" -lt 90 ]]; then
    log_warn "Root filesystem usage: ${root_usage}% (getting high)"
else
    log_fail "Root filesystem usage: ${root_usage}% (critical)"
fi

# Prometheus data
if [[ -d /var/lib/prometheus ]]; then
    prom_size=$(du -sh /var/lib/prometheus 2>/dev/null | awk '{print $1}')
    prom_files=$(find /var/lib/prometheus -type f | wc -l)
    log_pass "Prometheus data: $prom_size ($prom_files files)"
else
    log_warn "Prometheus data directory not found"
fi

# Loki data
if [[ -d /var/lib/loki ]]; then
    loki_size=$(du -sh /var/lib/loki 2>/dev/null | awk '{print $1}')
    log_pass "Loki data: $loki_size"
else
    log_warn "Loki data directory not found"
fi

# Grafana data
if [[ -d /var/lib/grafana ]]; then
    grafana_size=$(du -sh /var/lib/grafana 2>/dev/null | awk '{print $1}')
    log_pass "Grafana data: $grafana_size"
else
    log_warn "Grafana data directory not found"
fi

echo ""
echo "Checking query performance..."
echo ""

# Prometheus query performance
if curl -s http://localhost:9090/-/ready &>/dev/null; then
    query_time=$(curl -w "%{time_total}" -o /dev/null -s 'http://localhost:9090/api/v1/query?query=up')
    query_ms=$(echo "$query_time * 1000" | bc)

    if (( $(echo "$query_ms < 100" | bc -l) )); then
        log_pass "Prometheus query latency: ${query_ms}ms"
    elif (( $(echo "$query_ms < 500" | bc -l) )); then
        log_warn "Prometheus query latency: ${query_ms}ms (acceptable but slow)"
    else
        log_fail "Prometheus query latency: ${query_ms}ms (too slow)"
    fi
fi

#===============================================================================
# 10. ERROR LOG ANALYSIS
#===============================================================================
log_section "10. Recent Error Log Analysis"

echo "Checking for errors in service logs (last 10 minutes)..."
echo ""

CRITICAL_SERVICES=("prometheus" "loki" "grafana-server" "alertmanager")

for service in "${CRITICAL_SERVICES[@]}"; do
    error_count=$(journalctl -u "$service" --since "10 minutes ago" --no-pager 2>/dev/null | grep -i "error" | grep -v "level=error msg=\"No such file\"" | wc -l)

    if [[ "$error_count" -eq 0 ]]; then
        log_pass "$service: no errors in last 10 minutes"
    elif [[ "$error_count" -lt 5 ]]; then
        log_warn "$service: $error_count error(s) in last 10 minutes"
    else
        log_fail "$service: $error_count error(s) in last 10 minutes"
        echo "Recent errors:"
        journalctl -u "$service" --since "10 minutes ago" --no-pager | grep -i "error" | tail -3
    fi
done

#===============================================================================
# FINAL SUMMARY AND CERTIFICATION
#===============================================================================
log_section "CERTIFICATION SUMMARY"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│                   VALIDATION RESULTS                        │"
echo "├─────────────────────────────────────────────────────────────┤"
printf "│  %-30s %27s  │\n" "Total Checks:" "$TOTAL_CHECKS"
printf "│  ${GREEN}%-30s %27s${NC}  │\n" "Passed:" "$PASSED_CHECKS"
printf "│  ${YELLOW}%-30s %27s${NC}  │\n" "Warnings:" "$WARNING_CHECKS"
printf "│  ${RED}%-30s %27s${NC}  │\n" "Failed:" "$FAILED_CHECKS"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

# Calculate success rate
success_rate=$(echo "scale=1; $PASSED_CHECKS * 100 / $TOTAL_CHECKS" | bc)

# Determine certification status
if [[ "$FAILED_CHECKS" -eq 0 && "$WARNING_CHECKS" -eq 0 ]]; then
    cert_status="FULLY CERTIFIED"
    cert_color="$GREEN"
    overall_status="excellent"
elif [[ "$FAILED_CHECKS" -eq 0 && "$WARNING_CHECKS" -le 5 ]]; then
    cert_status="CERTIFIED WITH MINOR WARNINGS"
    cert_color="$YELLOW"
    overall_status="good"
elif [[ "$FAILED_CHECKS" -le 2 ]]; then
    cert_status="CONDITIONALLY CERTIFIED"
    cert_color="$YELLOW"
    overall_status="acceptable"
else
    cert_status="NOT CERTIFIED"
    cert_color="$RED"
    overall_status="failed"
fi

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                                                                    ║"
echo "║  CERTIFICATION STATUS: ${cert_color}${cert_status}${NC}$(printf '%*s' $((48 - ${#cert_status})) '')║"
echo "║                                                                    ║"
echo "║  Success Rate: ${success_rate}%                                              ║"
echo "║                                                                    ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# Update certification data with final status
jq ".overall_status = \"$overall_status\" | .success_rate = $success_rate | .total_checks = $TOTAL_CHECKS | .passed = $PASSED_CHECKS | .failed = $FAILED_CHECKS | .warnings = $WARNING_CHECKS" "$CERT_DATA_FILE" > "${CERT_DATA_FILE}.tmp" && mv "${CERT_DATA_FILE}.tmp" "$CERT_DATA_FILE"

echo "Certification data saved to: $CERT_DATA_FILE"
echo ""

# Recommendations
if [[ "$FAILED_CHECKS" -gt 0 ]]; then
    echo "${RED}CRITICAL ISSUES FOUND:${NC}"
    echo "The following issues must be resolved before production deployment:"
    echo ""
    jq -r '.issues[]' "$CERT_DATA_FILE" | sed 's/^/  - /'
    echo ""
fi

if [[ "$WARNING_CHECKS" -gt 0 ]]; then
    echo "${YELLOW}RECOMMENDATIONS:${NC}"
    echo "The following items should be reviewed:"
    echo "  - Review all warnings and address as needed"
    echo "  - Verify backup retention policies"
    echo "  - Monitor metrics continuity over next 24 hours"
    echo "  - Review and update alert rules if needed"
    echo ""
fi

# Exit code
if [[ "$FAILED_CHECKS" -eq 0 ]]; then
    echo "${GREEN}✓ Post-upgrade validation PASSED${NC}"
    echo ""
    exit 0
elif [[ "$FAILED_CHECKS" -le 2 ]]; then
    echo "${YELLOW}⚠ Post-upgrade validation PASSED with minor issues${NC}"
    echo ""
    exit 0
else
    echo "${RED}✗ Post-upgrade validation FAILED${NC}"
    echo ""
    exit 1
fi
