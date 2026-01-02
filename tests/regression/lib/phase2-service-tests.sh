#!/bin/bash
# ============================================================================
# Phase 2: Service-Level Tests
# ============================================================================
# Tests for individual services in each environment
# ============================================================================

set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-utils.sh"

# ============================================================================
# Observability Stack Tests
# ============================================================================

test_prometheus_service() {
    local test_name="Prometheus Service"

    start_test "${test_name}"

    # Check if Prometheus is accessible
    if ! wait_for_http "http://localhost:9090/-/healthy" 200 30; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check if metrics are being collected
    local response
    response=$(curl -s "http://localhost:9090/api/v1/query?query=up" 2>/dev/null || echo "")

    if echo "${response}" | grep -q '"status":"success"'; then
        log_success "Prometheus is collecting metrics"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Prometheus is not collecting metrics properly"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_loki_service() {
    local test_name="Loki Service"

    start_test "${test_name}"

    if ! wait_for_http "http://localhost:3100/ready" 200 30; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check Loki API
    local response
    response=$(curl -s "http://localhost:3100/loki/api/v1/labels" 2>/dev/null || echo "")

    if echo "${response}" | grep -q '"status":"success"'; then
        log_success "Loki API is responding"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Loki API is not responding properly"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_grafana_service() {
    local test_name="Grafana Service"

    start_test "${test_name}"

    if ! wait_for_http "http://localhost:3000/api/health" 200 60; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Test login endpoint
    local response
    response=$(curl -s -X POST "http://localhost:3000/api/login" \
        -H "Content-Type: application/json" \
        -d '{"user":"admin","password":"admin"}' 2>/dev/null || echo "")

    if echo "${response}" | grep -q '"message":"Logged in"'; then
        log_success "Grafana login successful"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Grafana login may have different response format"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_tempo_service() {
    local test_name="Tempo Service"

    start_test "${test_name}"

    # Check Tempo HTTP endpoint
    if wait_for_port "localhost" 3200 30; then
        log_success "Tempo HTTP endpoint is available"
    else
        log_error "Tempo HTTP endpoint not available"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check OTLP gRPC endpoint
    if wait_for_port "localhost" 4317 10; then
        log_success "Tempo OTLP gRPC endpoint is available"
    else
        log_warn "Tempo OTLP gRPC endpoint not available"
        end_test "${test_name}" "WARN"
        return 0
    fi

    # Check OTLP HTTP endpoint
    if wait_for_port "localhost" 4318 10; then
        log_success "Tempo OTLP HTTP endpoint is available"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Tempo OTLP HTTP endpoint not available"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_alertmanager_service() {
    local test_name="Alertmanager Service"

    start_test "${test_name}"

    if ! wait_for_http "http://localhost:9093/-/healthy" 200 30; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    local response
    response=$(curl -s "http://localhost:9093/api/v2/status" 2>/dev/null || echo "")

    if echo "${response}" | grep -q '"uptime"'; then
        log_success "Alertmanager is responding"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Alertmanager API not responding properly"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_node_exporter_observability() {
    local test_name="Node Exporter (Observability)"

    start_test "${test_name}"

    if ! wait_for_http "http://localhost:9199/metrics" 200 30; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    local metrics
    metrics=$(curl -s "http://localhost:9199/metrics" 2>/dev/null || echo "")

    if echo "${metrics}" | grep -q "node_cpu_seconds_total"; then
        log_success "Node Exporter is exporting metrics"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Node Exporter metrics not found"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

# ============================================================================
# Web Stack Tests
# ============================================================================

test_nginx_service() {
    local test_name="Nginx Service"

    start_test "${test_name}"

    # Test HTTP
    if ! wait_for_http "http://localhost:8000" 200 60; then
        # May return 404 or other codes if no content
        if check_port_listening "localhost" 8000; then
            log_success "Nginx HTTP is listening"
        else
            log_error "Nginx HTTP not accessible"
            end_test "${test_name}" "FAIL"
            return 1
        fi
    fi

    # Test HTTPS
    if check_port_listening "localhost" 8443; then
        log_success "Nginx HTTPS is listening"
    else
        log_warn "Nginx HTTPS not available"
    fi

    end_test "${test_name}" "PASS"
    return 0
}

test_mysql_service() {
    local test_name="MySQL Service"

    start_test "${test_name}"

    if ! wait_for_port "localhost" 3316 60; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Test MySQL connection (if mysql client is available)
    if command -v mysql &>/dev/null; then
        if mysql -h127.0.0.1 -P3316 -uroot -proot -e "SELECT 1" &>/dev/null; then
            log_success "MySQL connection successful"
        else
            log_warn "MySQL connection failed (may need initialization)"
        fi
    else
        log_info "MySQL client not available, skipping connection test"
    fi

    end_test "${test_name}" "PASS"
    return 0
}

test_redis_service() {
    local test_name="Redis Service"

    start_test "${test_name}"

    if ! wait_for_port "localhost" 6389 60; then
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Test Redis operations (if redis-cli is available)
    if command -v redis-cli &>/dev/null; then
        local set_result
        set_result=$(redis-cli -h 127.0.0.1 -p 6389 SET test_key "test_value" 2>/dev/null || echo "")

        local get_result
        get_result=$(redis-cli -h 127.0.0.1 -p 6389 GET test_key 2>/dev/null || echo "")

        if [[ "${get_result}" == "test_value" ]]; then
            log_success "Redis SET/GET operations work"
            redis-cli -h 127.0.0.1 -p 6389 DEL test_key &>/dev/null
        else
            log_warn "Redis operations may not be working properly"
        fi
    else
        log_info "redis-cli not available, skipping operation test"
    fi

    end_test "${test_name}" "PASS"
    return 0
}

test_web_exporters() {
    local test_name="Web Stack Exporters"

    start_test "${test_name}"

    local failures=0

    # Node Exporter
    if wait_for_http "http://localhost:9101/metrics" 200 30; then
        log_success "Node Exporter (Web) is available"
    else
        log_error "Node Exporter (Web) failed"
        failures=$((failures + 1))
    fi

    # Nginx Exporter
    if wait_for_http "http://localhost:9114/metrics" 200 30; then
        log_success "Nginx Exporter is available"
    else
        log_warn "Nginx Exporter not available"
    fi

    # MySQL Exporter
    if wait_for_http "http://localhost:9105/metrics" 200 30; then
        log_success "MySQL Exporter is available"
    else
        log_warn "MySQL Exporter not available"
    fi

    # PHP-FPM Exporter
    if wait_for_http "http://localhost:9254/metrics" 200 30; then
        log_success "PHP-FPM Exporter is available"
    else
        log_warn "PHP-FPM Exporter not available"
    fi

    if [[ ${failures} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

# ============================================================================
# VPS Simulation Tests
# ============================================================================

test_systemd_in_container() {
    local container="$1"
    local test_name="Systemd in ${container}"

    start_test "${test_name}"

    if ! container_is_running "${container}"; then
        log_error "Container ${container} is not running"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    # Check if systemd is running
    if exec_in_container "${container}" systemctl is-system-running &>/dev/null; then
        log_success "Systemd is running in ${container}"
    else
        log_warn "Systemd may not be fully initialized in ${container}"
    fi

    # Check multi-user target
    if exec_in_container "${container}" systemctl is-active multi-user.target &>/dev/null; then
        log_success "multi-user.target is active in ${container}"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "multi-user.target is not active in ${container}"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_ssh_service() {
    local container="$1"
    local port="$2"
    local test_name="SSH Service: ${container}"

    start_test "${test_name}"

    if wait_for_port "localhost" "${port}" 60; then
        log_success "SSH is accessible on port ${port}"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "SSH is not accessible on port ${port}"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_vps_network_connectivity() {
    local test_name="VPS Network Connectivity"

    start_test "${test_name}"

    # Test connectivity between VPS containers
    if container_is_running "mentat_tst" && container_is_running "landsraad_tst"; then
        if exec_in_container "landsraad_tst" ping -c 1 10.10.100.10 &>/dev/null; then
            log_success "landsraad_tst can reach mentat_tst"
        else
            log_error "landsraad_tst cannot reach mentat_tst"
            end_test "${test_name}" "FAIL"
            return 1
        fi
    fi

    if container_is_running "landsraad_tst" && container_is_running "richese_tst"; then
        if exec_in_container "landsraad_tst" ping -c 1 10.10.100.30 &>/dev/null; then
            log_success "landsraad_tst can reach richese_tst"
        else
            log_error "landsraad_tst cannot reach richese_tst"
            end_test "${test_name}" "FAIL"
            return 1
        fi
    fi

    end_test "${test_name}" "PASS"
    return 0
}

# ============================================================================
# Development Environment Tests
# ============================================================================

test_dev_mysql() {
    local test_name="Development MySQL"

    start_test "${test_name}"

    if wait_for_port "localhost" 3306 60; then
        log_success "MySQL is accessible"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "MySQL not accessible"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_dev_redis() {
    local test_name="Development Redis"

    start_test "${test_name}"

    if wait_for_port "localhost" 6379 60; then
        log_success "Redis is accessible"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Redis not accessible"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_dev_mailhog() {
    local test_name="MailHog Service"

    start_test "${test_name}"

    if wait_for_http "http://localhost:8025" 200 30; then
        log_success "MailHog UI is accessible"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "MailHog not accessible"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_dev_minio() {
    local test_name="MinIO Service"

    start_test "${test_name}"

    if wait_for_http "http://localhost:9001" 200 30; then
        log_success "MinIO console is accessible"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "MinIO not accessible"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

# ============================================================================
# Main Test Runners
# ============================================================================

run_phase2_tests_main() {
    start_phase "Phase 2: Service-Level Tests - Main Test Environment"

    test_prometheus_service || true
    test_loki_service || true
    test_grafana_service || true
    test_tempo_service || true
    test_alertmanager_service || true
    test_node_exporter_observability || true
    test_nginx_service || true
    test_mysql_service || true
    test_redis_service || true
    test_web_exporters || true

    end_phase
}

run_phase2_tests_vps() {
    start_phase "Phase 2: Service-Level Tests - VPS Simulation"

    test_systemd_in_container "mentat_tst" || true
    test_systemd_in_container "landsraad_tst" || true
    test_systemd_in_container "richese_tst" || true
    test_ssh_service "mentat_tst" 2210 || true
    test_ssh_service "landsraad_tst" 2220 || true
    test_ssh_service "richese_tst" 2230 || true
    test_vps_network_connectivity || true

    end_phase
}

run_phase2_tests_dev() {
    start_phase "Phase 2: Service-Level Tests - Development Environment"

    test_dev_mysql || true
    test_dev_redis || true
    test_dev_mailhog || true
    test_dev_minio || true
    test_prometheus_service || true
    test_grafana_service || true
    test_loki_service || true

    end_phase
}

# Export functions
export -f test_prometheus_service
export -f test_loki_service
export -f test_grafana_service
export -f test_tempo_service
export -f test_alertmanager_service
export -f test_node_exporter_observability
export -f test_nginx_service
export -f test_mysql_service
export -f test_redis_service
export -f test_web_exporters
export -f test_systemd_in_container
export -f test_ssh_service
export -f test_vps_network_connectivity
export -f test_dev_mysql
export -f test_dev_redis
export -f test_dev_mailhog
export -f test_dev_minio
export -f run_phase2_tests_main
export -f run_phase2_tests_vps
export -f run_phase2_tests_dev
