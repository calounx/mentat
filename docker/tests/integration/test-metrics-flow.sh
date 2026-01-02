#!/usr/bin/env bash
# ============================================================================
# Metrics Integration Tests
# ============================================================================
# Tests that Prometheus on mentat_tst successfully scrapes metrics from
# landsraad_tst and all configured exporters.
#
# Usage:
#   ./test-metrics-flow.sh
#
# Environment variables:
#   MENTAT_IP          - IP of observability host (default: 10.10.100.10)
#   LANDSRAAD_IP       - IP of application host (default: 10.10.100.20)
#   PROMETHEUS_PORT    - Prometheus port (default: 9090)
#   SKIP_OPTIONAL      - Skip optional exporter tests (default: false)
# ============================================================================

set -euo pipefail

# Source test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-lib.sh"

# Initialize
init_test_lib

# ============================================================================
# Test Configuration
# ============================================================================

# Job names as configured in Prometheus targets (vpsmanager naming convention)
NODE_EXPORTER_JOB="vpsmanager-node"
NGINX_EXPORTER_JOB="vpsmanager-nginx"
MYSQL_EXPORTER_JOB="vpsmanager-mysql"
PHPFPM_EXPORTER_JOB="vpsmanager-phpfpm"

# Instance patterns (using host label from file_sd targets)
# Note: instance label contains IP:port (e.g., 10.10.100.20:9100)
# Use host label which contains the hostname (landsraad_tst)
WEB_HOST_LABEL="landsraad_tst"
WEB_INSTANCE_PATTERN="10.10.100.20"

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    log_section "Checking Prerequisites"

    log_test "Prometheus is accessible"
    if check_http "http://${MENTAT_IP}:${PROMETHEUS_PORT}/-/healthy"; then
        test_pass "prometheus_accessible"
    else
        test_fail "prometheus_accessible" "Cannot reach Prometheus at ${MENTAT_IP}:${PROMETHEUS_PORT}"
        log_error "Prometheus must be running to continue tests"
        exit 1
    fi

    log_test "Prometheus API is functional"
    local result
    result=$(prometheus_query "up")
    if echo "$result" | jq -e '.status == "success"' >/dev/null 2>&1; then
        test_pass "prometheus_api"
    else
        test_fail "prometheus_api" "Prometheus API not responding correctly"
        exit 1
    fi
}

# ============================================================================
# Target Configuration Tests
# ============================================================================

test_target_configuration() {
    log_section "Testing Target Configuration"

    log_test "Prometheus has landsraad targets configured"
    local targets
    targets=$(prometheus_targets)

    # Check for vpsmanager-* jobs (node, nginx, mysql, phpfpm exporters)
    if echo "$targets" | jq -e ".data.activeTargets[] | select(.labels.job | test(\"vpsmanager-\"))" >/dev/null 2>&1; then
        local count
        count=$(echo "$targets" | jq '[.data.activeTargets[] | select(.labels.job | test("vpsmanager-"))] | length')
        test_pass "targets_configured" "${count} vpsmanager targets found"
    else
        test_fail "targets_configured" "No vpsmanager targets found in Prometheus"
    fi

    log_test "Node exporter target is UP"
    if prometheus_target_up "$NODE_EXPORTER_JOB" "$WEB_INSTANCE_PATTERN"; then
        test_pass "node_exporter_up"
    else
        # Check if target exists but is down
        if echo "$targets" | jq -e ".data.activeTargets[] | select(.labels.job == \"$NODE_EXPORTER_JOB\")" >/dev/null 2>&1; then
            local health
            health=$(echo "$targets" | jq -r ".data.activeTargets[] | select(.labels.job == \"$NODE_EXPORTER_JOB\") | .health")
            test_fail "node_exporter_up" "Target exists but health is: ${health}"
        else
            test_fail "node_exporter_up" "Node exporter target not found"
        fi
    fi
}

# ============================================================================
# Node Metrics Tests
# ============================================================================

test_node_metrics() {
    log_section "Testing Node Metrics"

    # CPU metrics
    log_test "Can query landsraad CPU metrics"
    if prometheus_has_data "node_cpu_seconds_total{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        local cpu_modes
        cpu_modes=$(prometheus_query "count(node_cpu_seconds_total{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}) by (mode)" | jq '.data.result | length')
        test_pass "cpu_metrics" "${cpu_modes} CPU modes"
    else
        test_fail "cpu_metrics" "No CPU metrics found"
    fi

    # Memory metrics
    log_test "Can query landsraad memory metrics"
    if prometheus_has_data "node_memory_MemTotal_bytes{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        local mem_total
        mem_total=$(prometheus_query "node_memory_MemTotal_bytes{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}" | jq -r '.data.result[0].value[1] // "0"')
        local mem_gb
        mem_gb=$(echo "scale=2; ${mem_total} / 1073741824" | bc 2>/dev/null || echo "unknown")
        test_pass "memory_metrics" "${mem_gb} GB total"
    else
        test_fail "memory_metrics" "No memory metrics found"
    fi

    # Memory available
    log_test "Can query memory available metrics"
    if prometheus_has_data "node_memory_MemAvailable_bytes{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        test_pass "memory_available_metrics"
    else
        test_fail "memory_available_metrics" "No memory available metrics"
    fi

    # Disk metrics
    log_test "Can query landsraad disk metrics"
    if prometheus_has_data "node_filesystem_size_bytes{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        local fs_count
        fs_count=$(prometheus_query "count(node_filesystem_size_bytes{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}) by (mountpoint)" | jq '.data.result | length')
        test_pass "disk_metrics" "${fs_count} filesystems"
    else
        test_fail "disk_metrics" "No disk metrics found"
    fi

    # Disk available
    log_test "Can query disk available metrics"
    if prometheus_has_data "node_filesystem_avail_bytes{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        test_pass "disk_available_metrics"
    else
        test_fail "disk_available_metrics" "No disk available metrics"
    fi

    # Network metrics
    log_test "Can query landsraad network metrics"
    if prometheus_has_data "node_network_receive_bytes_total{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        local iface_count
        iface_count=$(prometheus_query "count(node_network_receive_bytes_total{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}) by (device)" | jq '.data.result | length')
        test_pass "network_metrics" "${iface_count} interfaces"
    else
        test_fail "network_metrics" "No network metrics found"
    fi

    # Network transmit
    log_test "Can query network transmit metrics"
    if prometheus_has_data "node_network_transmit_bytes_total{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        test_pass "network_transmit_metrics"
    else
        test_fail "network_transmit_metrics" "No network transmit metrics"
    fi

    # Load average
    log_test "Can query load average metrics"
    if prometheus_has_data "node_load1{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}"; then
        local load
        load=$(prometheus_query "node_load1{instance=~\".*${WEB_INSTANCE_PATTERN}.*\"}" | jq -r '.data.result[0].value[1] // "unknown"')
        test_pass "load_metrics" "load1=${load}"
    else
        test_fail "load_metrics" "No load average metrics"
    fi
}

# ============================================================================
# Application Exporter Tests
# ============================================================================

test_nginx_exporter() {
    log_section "Testing Nginx Exporter Metrics"

    log_test "Nginx exporter target is UP"
    if prometheus_target_up "$NGINX_EXPORTER_JOB" "$WEB_INSTANCE_PATTERN"; then
        test_pass "nginx_exporter_up"

        log_test "Nginx connections metric available"
        if prometheus_has_data "nginx_connections_active"; then
            local connections
            connections=$(prometheus_query "nginx_connections_active" | jq -r '.data.result[0].value[1] // "0"')
            test_pass "nginx_connections" "${connections} active"
        else
            test_fail "nginx_connections" "No connection metrics"
        fi

        log_test "Nginx requests metric available"
        if prometheus_has_data "nginx_http_requests_total"; then
            test_pass "nginx_requests"
        else
            test_fail "nginx_requests" "No request metrics"
        fi

        log_test "Nginx up metric available"
        if prometheus_has_data "nginx_up"; then
            local up
            up=$(prometheus_query "nginx_up" | jq -r '.data.result[0].value[1] // "0"')
            if [[ "$up" == "1" ]]; then
                test_pass "nginx_up_metric" "nginx is up"
            else
                test_fail "nginx_up_metric" "nginx_up is ${up}"
            fi
        else
            test_fail "nginx_up_metric" "No nginx_up metric"
        fi
    else
        if [[ "${SKIP_OPTIONAL:-false}" == "true" ]]; then
            test_skip "nginx_exporter_up" "Optional exporter not installed"
        else
            test_fail "nginx_exporter_up" "Nginx exporter not running"
        fi
    fi
}

test_mysql_exporter() {
    log_section "Testing MySQL Exporter Metrics"

    log_test "MySQL exporter target is UP"
    if prometheus_target_up "$MYSQL_EXPORTER_JOB" "$WEB_INSTANCE_PATTERN"; then
        test_pass "mysql_exporter_up"

        log_test "MySQL up metric available"
        if prometheus_has_data "mysql_up"; then
            local up
            up=$(prometheus_query "mysql_up" | jq -r '.data.result[0].value[1] // "0"')
            if [[ "$up" == "1" ]]; then
                test_pass "mysql_up_metric" "MySQL is up"
            else
                test_fail "mysql_up_metric" "mysql_up is ${up}"
            fi
        else
            test_fail "mysql_up_metric" "No mysql_up metric"
        fi

        log_test "MySQL connections metric available"
        if prometheus_has_data "mysql_global_status_threads_connected"; then
            local threads
            threads=$(prometheus_query "mysql_global_status_threads_connected" | jq -r '.data.result[0].value[1] // "0"')
            test_pass "mysql_connections" "${threads} connected"
        else
            test_fail "mysql_connections" "No connection metrics"
        fi

        log_test "MySQL queries metric available"
        if prometheus_has_data "mysql_global_status_queries"; then
            test_pass "mysql_queries"
        else
            test_fail "mysql_queries" "No query metrics"
        fi
    else
        if [[ "${SKIP_OPTIONAL:-false}" == "true" ]]; then
            test_skip "mysql_exporter_up" "Optional exporter not installed"
        else
            test_fail "mysql_exporter_up" "MySQL exporter not running"
        fi
    fi
}

test_phpfpm_exporter() {
    log_section "Testing PHP-FPM Exporter Metrics"

    log_test "PHP-FPM exporter target is UP"
    if prometheus_target_up "$PHPFPM_EXPORTER_JOB" "$WEB_INSTANCE_PATTERN"; then
        test_pass "phpfpm_exporter_up"

        log_test "PHP-FPM up metric available"
        if prometheus_has_data "phpfpm_up"; then
            local up
            up=$(prometheus_query "phpfpm_up" | jq -r '.data.result[0].value[1] // "0"')
            if [[ "$up" == "1" ]]; then
                test_pass "phpfpm_up_metric" "PHP-FPM is up"
            else
                test_fail "phpfpm_up_metric" "phpfpm_up is ${up}"
            fi
        else
            test_fail "phpfpm_up_metric" "No phpfpm_up metric"
        fi

        log_test "PHP-FPM active processes metric available"
        if prometheus_has_data "phpfpm_active_processes"; then
            local active
            active=$(prometheus_query "phpfpm_active_processes" | jq -r '.data.result[0].value[1] // "0"')
            test_pass "phpfpm_active" "${active} active"
        else
            test_fail "phpfpm_active" "No active processes metric"
        fi

        log_test "PHP-FPM accepted connections metric available"
        if prometheus_has_data "phpfpm_accepted_connections"; then
            test_pass "phpfpm_connections"
        else
            test_fail "phpfpm_connections" "No connection metrics"
        fi
    else
        if [[ "${SKIP_OPTIONAL:-false}" == "true" ]]; then
            test_skip "phpfpm_exporter_up" "Optional exporter not installed"
        else
            test_fail "phpfpm_exporter_up" "PHP-FPM exporter not running"
        fi
    fi
}

# ============================================================================
# Label Tests
# ============================================================================

test_metric_labels() {
    log_section "Testing Metric Labels"

    log_test "Metrics have job label"
    if prometheus_has_data "up{job!=\"\"}"; then
        local job_count
        job_count=$(prometheus_query "count(up) by (job)" | jq '.data.result | length')
        test_pass "job_label" "${job_count} unique jobs"
    else
        test_fail "job_label" "No metrics with job label"
    fi

    log_test "Metrics have instance label"
    if prometheus_has_data "up{instance!=\"\"}"; then
        local instance_count
        instance_count=$(prometheus_query "count(up) by (instance)" | jq '.data.result | length')
        test_pass "instance_label" "${instance_count} unique instances"
    else
        test_fail "instance_label" "No metrics with instance label"
    fi

    log_test "Node exporter metrics have correct job label"
    if prometheus_has_data "node_cpu_seconds_total{job=\"${NODE_EXPORTER_JOB}\"}"; then
        test_pass "node_job_label"
    else
        test_fail "node_job_label" "Expected job=${NODE_EXPORTER_JOB}"
    fi

    log_test "Metrics have service label"
    if prometheus_has_data "up{service!=\"\"}"; then
        test_pass "service_label"
    else
        test_skip "service_label" "Service label not configured"
    fi

    log_test "Metrics have tier label"
    if prometheus_has_data "up{tier!=\"\"}"; then
        local tier_values
        tier_values=$(prometheus_query "count(up) by (tier)" | jq -r '[.data.result[].metric.tier] | join(", ")')
        test_pass "tier_label" "tiers: ${tier_values}"
    else
        test_skip "tier_label" "Tier label not configured"
    fi
}

# ============================================================================
# Scrape Configuration Tests
# ============================================================================

test_scrape_configuration() {
    log_section "Testing Scrape Configuration"

    log_test "Scrape interval is being tracked"
    if prometheus_has_data "prometheus_target_interval_length_seconds"; then
        test_pass "scrape_interval_tracked"
    else
        test_fail "scrape_interval_tracked" "No scrape interval metrics"
    fi

    log_test "Scrape duration is reasonable"
    local max_duration
    max_duration=$(prometheus_query "max(prometheus_target_sync_length_seconds{quantile=\"0.99\"})" | jq -r '.data.result[0].value[1] // "unknown"')
    if [[ "$max_duration" != "unknown" ]]; then
        # Check if duration is less than 10 seconds
        if (( $(echo "${max_duration} < 10" | bc -l 2>/dev/null || echo 0) )); then
            test_pass "scrape_duration" "${max_duration}s max"
        else
            test_fail "scrape_duration" "Max scrape duration ${max_duration}s exceeds 10s threshold"
        fi
    else
        test_skip "scrape_duration" "Cannot determine scrape duration"
    fi

    log_test "No scrape errors"
    local scrape_errors
    scrape_errors=$(prometheus_query "sum(increase(prometheus_target_scrapes_exceeded_sample_limit_total[5m]))" | jq -r '.data.result[0].value[1] // "0"')
    if [[ "$scrape_errors" == "0" ]] || [[ -z "$scrape_errors" ]]; then
        test_pass "no_scrape_errors"
    else
        test_fail "no_scrape_errors" "${scrape_errors} sample limit errors"
    fi

    log_test "All configured targets are being scraped"
    local targets_total
    local targets_up
    targets_total=$(prometheus_query "count(up)" | jq -r '.data.result[0].value[1] // "0"')
    targets_up=$(prometheus_query "count(up == 1)" | jq -r '.data.result[0].value[1] // "0"')
    if [[ "$targets_total" == "$targets_up" ]]; then
        test_pass "all_targets_scraped" "${targets_up}/${targets_total} up"
    else
        local targets_down=$((targets_total - targets_up))
        test_fail "all_targets_scraped" "${targets_down} of ${targets_total} targets are down"
    fi
}

# ============================================================================
# Advanced Metric Tests
# ============================================================================

test_rate_calculations() {
    log_section "Testing Rate Calculations"

    log_test "CPU rate calculation works"
    if prometheus_has_data "rate(node_cpu_seconds_total{mode=\"idle\"}[5m])"; then
        test_pass "cpu_rate"
    else
        test_skip "cpu_rate" "Need more data for rate calculation"
    fi

    log_test "Network rate calculation works"
    if prometheus_has_data "rate(node_network_receive_bytes_total[5m])"; then
        test_pass "network_rate"
    else
        test_skip "network_rate" "Need more data for rate calculation"
    fi

    log_test "Disk I/O rate calculation works"
    if prometheus_has_data "rate(node_disk_read_bytes_total[5m])"; then
        test_pass "disk_io_rate"
    else
        test_skip "disk_io_rate" "Need more data for rate calculation"
    fi
}

test_aggregations() {
    log_section "Testing Metric Aggregations"

    log_test "Can aggregate by instance"
    if prometheus_has_data "sum by (instance) (node_cpu_seconds_total)"; then
        test_pass "aggregate_by_instance"
    else
        test_fail "aggregate_by_instance" "Aggregation failed"
    fi

    log_test "Can aggregate by job"
    if prometheus_has_data "sum by (job) (up)"; then
        test_pass "aggregate_by_job"
    else
        test_fail "aggregate_by_job" "Aggregation failed"
    fi

    log_test "Can calculate percentages"
    local mem_pct
    mem_pct=$(prometheus_query "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100" | jq -r '.data.result[0].value[1] // "unknown"')
    if [[ "$mem_pct" != "unknown" ]]; then
        test_pass "percentage_calc" "Memory at ${mem_pct}%"
    else
        test_skip "percentage_calc" "Cannot calculate percentage"
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
    log_header "Metrics Integration Tests"
    log_info "Testing Prometheus metrics flow from landsraad_tst to mentat_tst"
    log_info "Observability Host: ${MENTAT_IP}:${PROMETHEUS_PORT}"
    log_info "Application Host: ${LANDSRAAD_IP}"
    echo ""

    # Run test suites
    check_prerequisites
    test_target_configuration
    test_node_metrics
    test_nginx_exporter
    test_mysql_exporter
    test_phpfpm_exporter
    test_metric_labels
    test_scrape_configuration
    test_rate_calculations
    test_aggregations

    # Print summary
    print_summary "Metrics Integration Tests"
}

# Run main function
main "$@"
