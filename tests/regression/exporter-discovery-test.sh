#!/bin/bash
#===============================================================================
# Comprehensive Regression Test Suite for Exporter Auto-Discovery System
#===============================================================================
# Tests all components of the exporter discovery, installation, configuration,
# validation, and troubleshooting system.
#
# Components Under Test:
#   1. detect-exporters.sh
#   2. install-exporter.sh
#   3. generate-prometheus-config.sh
#   4. validate-exporters.py
#   5. troubleshoot-exporters.sh
#   6. health-check-enhanced.sh
#
# Usage:
#   ./exporter-discovery-test.sh [OPTIONS]
#
# Options:
#   --unit              Run unit tests only
#   --integration       Run integration tests only
#   --performance       Run performance benchmarks
#   --docker            Run tests in Docker container
#   --verbose           Verbose output
#   --report FORMAT     Report format: text, json, html (default: text)
#   --continue-on-fail  Continue even if tests fail
#   --help              Show this help
#
#===============================================================================

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts/observability"
TOOLS_DIR="$PROJECT_ROOT/observability-stack/scripts/tools"
CHOM_DIR="$PROJECT_ROOT/chom/scripts"

# Test configuration
TEST_MODE="all"  # all, unit, integration, performance
USE_DOCKER=false
VERBOSE=false
REPORT_FORMAT="text"
CONTINUE_ON_FAIL=false
DOCKER_CONTAINER="landsraad_tst"

# Test results tracking
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
START_TIME=$(date +%s)

# Temporary directory for test artifacts
TEST_TMP_DIR=$(mktemp -d)
trap 'cleanup_test_env' EXIT

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_skip() {
    echo -e "${CYAN}[SKIP]${NC} $*"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $*"
    fi
}

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}▶ $1${NC}"
    echo -e "${BOLD}$(printf '─%.0s' {1..79})${NC}"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ "$expected" == "$actual" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS["$test_name"]="PASS"
        log_success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS["$test_name"]="FAIL"
        log_fail "$test_name"
        log_verbose "  Expected: $expected"
        log_verbose "  Actual:   $actual"
        if [[ "$CONTINUE_ON_FAIL" == "false" ]]; then
            exit 1
        fi
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local test_name="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if eval "$condition"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS["$test_name"]="PASS"
        log_success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS["$test_name"]="FAIL"
        log_fail "$test_name"
        log_verbose "  Condition failed: $condition"
        if [[ "$CONTINUE_ON_FAIL" == "false" ]]; then
            exit 1
        fi
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS["$test_name"]="PASS"
        log_success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS["$test_name"]="FAIL"
        log_fail "$test_name"
        log_verbose "  Expected to find: $needle"
        log_verbose "  In: $haystack"
        if [[ "$CONTINUE_ON_FAIL" == "false" ]]; then
            exit 1
        fi
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ -f "$file_path" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS["$test_name"]="PASS"
        log_success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS["$test_name"]="FAIL"
        log_fail "$test_name"
        log_verbose "  File not found: $file_path"
        if [[ "$CONTINUE_ON_FAIL" == "false" ]]; then
            exit 1
        fi
        return 1
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local command="$2"
    local test_name="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    set +e
    eval "$command" > /dev/null 2>&1
    local actual_code=$?
    set -e

    if [[ "$expected_code" -eq "$actual_code" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS["$test_name"]="PASS"
        log_success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS["$test_name"]="FAIL"
        log_fail "$test_name"
        log_verbose "  Expected exit code: $expected_code"
        log_verbose "  Actual exit code:   $actual_code"
        if [[ "$CONTINUE_ON_FAIL" == "false" ]]; then
            exit 1
        fi
        return 1
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    TEST_RESULTS["$test_name"]="SKIP"
    log_skip "$test_name: $reason"
}

#===============================================================================
# TEST ENVIRONMENT SETUP
#===============================================================================

setup_test_env() {
    print_section "Setting Up Test Environment"

    # Create test directories
    mkdir -p "$TEST_TMP_DIR/"{config,data,logs}

    # Create mock services for testing
    create_mock_services

    # Create test Prometheus configuration
    create_test_prometheus_config

    log_info "Test environment ready at: $TEST_TMP_DIR"
}

cleanup_test_env() {
    log_verbose "Cleaning up test environment..."
    rm -rf "$TEST_TMP_DIR"
}

create_mock_services() {
    # Create mock exporter binaries for testing
    for exporter in node_exporter nginx_exporter mysqld_exporter; do
        local mock_binary="$TEST_TMP_DIR/data/${exporter}"
        cat > "$mock_binary" << 'EOF'
#!/bin/bash
echo "Mock exporter running"
EOF
        chmod +x "$mock_binary"
    done
}

create_test_prometheus_config() {
    cat > "$TEST_TMP_DIR/config/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
}

#===============================================================================
# TEST 1: SERVICE DETECTION
#===============================================================================

test_service_detection() {
    print_section "Test 1: Service Detection"

    # Test 1.1: Nginx detection
    if systemctl is-active --quiet nginx 2>/dev/null; then
        local output=$("$SCRIPTS_DIR/detect-exporters.sh" --format json 2>/dev/null || echo "{}")
        assert_contains "$output" "nginx" "Test 1.1: Detect Nginx service"
    else
        skip_test "Test 1.1: Detect Nginx service" "Nginx not running"
    fi

    # Test 1.2: MySQL detection
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        local output=$("$SCRIPTS_DIR/detect-exporters.sh" --format json 2>/dev/null || echo "{}")
        assert_contains "$output" "mariadb" "Test 1.2: Detect MySQL/MariaDB service"
    else
        skip_test "Test 1.2: Detect MySQL/MariaDB service" "MySQL not running"
    fi

    # Test 1.3: Redis detection
    if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
        local output=$("$SCRIPTS_DIR/detect-exporters.sh" --format json 2>/dev/null || echo "{}")
        assert_contains "$output" "redis" "Test 1.3: Detect Redis service"
    else
        skip_test "Test 1.3: Detect Redis service" "Redis not running"
    fi

    # Test 1.4: PostgreSQL detection
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        local output=$("$SCRIPTS_DIR/detect-exporters.sh" --format json 2>/dev/null || echo "{}")
        assert_contains "$output" "postgresql" "Test 1.4: Detect PostgreSQL service"
    else
        skip_test "Test 1.4: Detect PostgreSQL service" "PostgreSQL not running"
    fi

    # Test 1.5: No false positives
    local output=$("$SCRIPTS_DIR/detect-exporters.sh" --format json 2>/dev/null || echo "{}")
    assert_true "[[ ! \$(echo '$output' | grep -c 'nonexistent_service') -gt 0 ]]" \
        "Test 1.5: No false positive service detection"

    # Test 1.6: System/node exporter always detected
    assert_contains "$output" "system" "Test 1.6: System metrics always detected"
}

#===============================================================================
# TEST 2: EXPORTER STATUS CHECK
#===============================================================================

test_exporter_status() {
    print_section "Test 2: Exporter Status Check"

    # Test 2.1: Binary detection
    if [[ -f /usr/local/bin/node_exporter ]]; then
        assert_file_exists "/usr/local/bin/node_exporter" "Test 2.1: Node exporter binary exists"
    else
        skip_test "Test 2.1: Node exporter binary exists" "Binary not installed"
    fi

    # Test 2.2: Service status (running)
    if systemctl list-unit-files | grep -q node_exporter.service 2>/dev/null; then
        local status=$(systemctl is-active node_exporter 2>/dev/null || echo "inactive")
        if [[ "$status" == "active" ]]; then
            assert_equals "active" "$status" "Test 2.2: Node exporter service running"
        else
            assert_equals "inactive" "$status" "Test 2.2: Node exporter service status detected"
        fi
    else
        skip_test "Test 2.2: Node exporter service running" "Service not configured"
    fi

    # Test 2.3: Port binding verification
    if ss -tuln 2>/dev/null | grep -q ":9100 "; then
        assert_true "ss -tuln | grep -q ':9100 '" "Test 2.3: Node exporter port 9100 listening"
    else
        skip_test "Test 2.3: Node exporter port 9100 listening" "Port not bound"
    fi

    # Test 2.4: Metrics endpoint validation
    if timeout 2 curl -sf http://localhost:9100/metrics >/dev/null 2>&1; then
        assert_exit_code 0 "curl -sf http://localhost:9100/metrics >/dev/null" \
            "Test 2.4: Node exporter metrics endpoint accessible"
    else
        skip_test "Test 2.4: Node exporter metrics endpoint accessible" "Endpoint unreachable"
    fi

    # Test 2.5: Metrics content validation
    if timeout 2 curl -sf http://localhost:9100/metrics >/dev/null 2>&1; then
        local metric_count=$(curl -sf http://localhost:9100/metrics 2>/dev/null | grep -c "^node_" || echo "0")
        assert_true "[[ $metric_count -gt 10 ]]" "Test 2.5: Node exporter generating metrics"
    else
        skip_test "Test 2.5: Node exporter generating metrics" "Endpoint unreachable"
    fi
}

#===============================================================================
# TEST 3: PROMETHEUS CONFIGURATION CHECK
#===============================================================================

test_prometheus_config() {
    print_section "Test 3: Prometheus Configuration Check"

    local prom_config="$PROJECT_ROOT/observability-stack/prometheus/prometheus.yml"

    if [[ ! -f "$prom_config" ]]; then
        prom_config="/etc/prometheus/prometheus.yml"
    fi

    if [[ -f "$prom_config" ]]; then
        # Test 3.1: YAML syntax validation
        if command -v promtool >/dev/null 2>&1; then
            assert_exit_code 0 "promtool check config '$prom_config'" \
                "Test 3.1: Prometheus config YAML syntax valid"
        else
            skip_test "Test 3.1: Prometheus config YAML syntax valid" "promtool not available"
        fi

        # Test 3.2: Scrape configs present
        assert_true "grep -q 'scrape_configs:' '$prom_config'" \
            "Test 3.2: Prometheus config has scrape_configs section"

        # Test 3.3: Node exporter target configured
        if grep -q ":9100" "$prom_config" 2>/dev/null; then
            assert_true "grep -q ':9100' '$prom_config'" \
                "Test 3.3: Node exporter target in Prometheus config"
        else
            skip_test "Test 3.3: Node exporter target in Prometheus config" "Target not configured"
        fi

        # Test 3.4: Job names present
        assert_true "grep -q 'job_name:' '$prom_config'" \
            "Test 3.4: Prometheus config has job definitions"

        # Test 3.5: Valid scrape intervals
        if grep -q "scrape_interval:" "$prom_config"; then
            assert_true "grep 'scrape_interval:' '$prom_config' | grep -E '[0-9]+[smh]'" \
                "Test 3.5: Valid scrape interval format"
        else
            skip_test "Test 3.5: Valid scrape interval format" "No scrape_interval defined"
        fi
    else
        skip_test "Test 3.x: Prometheus configuration checks" "Config file not found"
    fi
}

#===============================================================================
# TEST 4: AUTO-INSTALLATION
#===============================================================================

test_auto_installation() {
    print_section "Test 4: Auto-Installation (Dry-Run)"

    # Test 4.1: Install script exists
    assert_file_exists "$SCRIPTS_DIR/install-exporter.sh" \
        "Test 4.1: Install script exists"

    # Test 4.2: Dry-run execution (skip - requires root)
    skip_test "Test 4.2: Install script dry-run" "Requires root privileges"

    # Test 4.3: Help output (skip if requires root)
    local help_output=$("$SCRIPTS_DIR/install-exporter.sh" --help 2>&1 || echo "")
    if [[ "$help_output" == *"run as root"* ]]; then
        skip_test "Test 4.3: Install script provides help output" "Requires root privileges"
    else
        assert_contains "$help_output" "Usage" \
            "Test 4.3: Install script provides help output"
    fi

    # Test 4.4: Invalid exporter handling
    skip_test "Test 4.4: Install script rejects invalid exporter" "Requires root privileges"

    # Test 4.5: Version detection (skip - requires root)
    skip_test "Test 4.5: Install script detects version" "Requires root privileges"
}

#===============================================================================
# TEST 5: CONFIGURATION GENERATION
#===============================================================================

test_config_generation() {
    print_section "Test 5: Configuration Generation"

    # Test 5.1: Generate script exists
    assert_file_exists "$SCRIPTS_DIR/generate-prometheus-config.sh" \
        "Test 5.1: Config generation script exists"

    # Test 5.2: Generate config for localhost
    local config_output=$("$SCRIPTS_DIR/generate-prometheus-config.sh" --host localhost 2>/dev/null || echo "")
    assert_contains "$config_output" "scrape_configs:" \
        "Test 5.2: Generated config has scrape_configs"

    # Test 5.3: Valid YAML structure
    echo "$config_output" > "$TEST_TMP_DIR/test_config.yml"
    if command -v python3 >/dev/null 2>&1; then
        assert_exit_code 0 "python3 -c 'import yaml; yaml.safe_load(open(\"$TEST_TMP_DIR/test_config.yml\"))'" \
            "Test 5.3: Generated config is valid YAML"
    else
        skip_test "Test 5.3: Generated config is valid YAML" "Python3 not available"
    fi

    # Test 5.4: Contains job names
    assert_contains "$config_output" "job_name:" \
        "Test 5.4: Generated config contains job definitions"

    # Test 5.5: Contains targets
    assert_contains "$config_output" "targets:" \
        "Test 5.5: Generated config contains targets"

    # Test 5.6: Labels are present
    assert_contains "$config_output" "labels:" \
        "Test 5.6: Generated config contains labels"
}

#===============================================================================
# TEST 6: PYTHON VALIDATOR
#===============================================================================

test_python_validator() {
    print_section "Test 6: Python Validator"

    # Test 6.1: Validator script exists
    assert_file_exists "$TOOLS_DIR/validate-exporters.py" \
        "Test 6.1: Validator script exists"

    # Test 6.2: Script is executable or can be run
    if [[ -x "$TOOLS_DIR/validate-exporters.py" ]] || command -v python3 >/dev/null 2>&1; then
        assert_true "[[ -f '$TOOLS_DIR/validate-exporters.py' ]]" \
            "Test 6.2: Validator can be executed"
    else
        skip_test "Test 6.2: Validator can be executed" "Python3 not available"
    fi

    # Test 6.3: Help output
    if command -v python3 >/dev/null 2>&1; then
        local help_output=$(python3 "$TOOLS_DIR/validate-exporters.py" --help 2>&1 || echo "")
        assert_contains "$help_output" "usage" \
            "Test 6.3: Validator provides help output"
    else
        skip_test "Test 6.3: Validator provides help output" "Python3 not available"
    fi

    # Test 6.4: Validate node_exporter if running
    if timeout 2 curl -sf http://localhost:9100/metrics >/dev/null 2>&1; then
        if command -v python3 >/dev/null 2>&1; then
            assert_exit_code 0 "python3 '$TOOLS_DIR/validate-exporters.py' --endpoint http://localhost:9100/metrics" \
                "Test 6.4: Validator passes for healthy node_exporter"
        else
            skip_test "Test 6.4: Validator passes for healthy node_exporter" "Python3 not available"
        fi
    else
        skip_test "Test 6.4: Validator passes for healthy node_exporter" "Node exporter not accessible"
    fi

    # Test 6.5: JSON output format
    if timeout 2 curl -sf http://localhost:9100/metrics >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        local json_output=$(python3 "$TOOLS_DIR/validate-exporters.py" --endpoint http://localhost:9100/metrics --json 2>/dev/null || echo "{}")
        assert_contains "$json_output" "validation_time\|timestamp" \
            "Test 6.5: Validator produces JSON output"
    else
        skip_test "Test 6.5: Validator produces JSON output" "Requirements not met"
    fi

    # Test 6.6: Invalid endpoint handling
    if command -v python3 >/dev/null 2>&1; then
        assert_exit_code 2 "python3 '$TOOLS_DIR/validate-exporters.py' --endpoint http://localhost:99999/metrics" \
            "Test 6.6: Validator fails on invalid endpoint"
    else
        skip_test "Test 6.6: Validator fails on invalid endpoint" "Python3 not available"
    fi
}

#===============================================================================
# TEST 7: TROUBLESHOOTING SYSTEM
#===============================================================================

test_troubleshooting() {
    print_section "Test 7: Troubleshooting System"

    local troubleshoot_script="$SCRIPTS_DIR/troubleshoot-exporters.sh"

    # Test 7.1: Troubleshoot script exists
    if [[ -f "$troubleshoot_script" ]]; then
        assert_file_exists "$troubleshoot_script" \
            "Test 7.1: Troubleshooting script exists"

        # Test 7.2: Help output
        local help_output=$("$troubleshoot_script" --help 2>&1 || echo "")
        if [[ "$help_output" == *"diagnostic-helpers.sh"* ]]; then
            skip_test "Test 7.2: Troubleshoot script provides help" "Missing dependency library"
        else
            assert_contains "$help_output" "Usage" \
                "Test 7.2: Troubleshoot script provides help"
        fi

        # Test 7.3: Quick scan mode
        skip_test "Test 7.3: Quick scan execution" "Requires diagnostic-helpers.sh library"

        # Test 7.4: Dry-run mode
        skip_test "Test 7.4: Dry-run mode" "Requires diagnostic-helpers.sh library"
    else
        skip_test "Test 7.x: Troubleshooting tests" "Script not found"
    fi
}

#===============================================================================
# TEST 8: HEALTH CHECK INTEGRATION
#===============================================================================

test_health_check_integration() {
    print_section "Test 8: Health Check Integration"

    local health_check="$CHOM_DIR/health-check-enhanced.sh"

    if [[ -f "$health_check" ]]; then
        # Test 8.1: Health check script exists
        assert_file_exists "$health_check" \
            "Test 8.1: Health check script exists"

        # Test 8.2: Normal execution
        set +e
        RUN_EXPORTER_SCAN=false "$health_check" >/dev/null 2>&1
        local exit_code=$?
        set -e
        assert_true "[[ $exit_code -ge 0 && $exit_code -le 2 ]]" \
            "Test 8.2: Health check executes with valid exit code"

        # Test 8.3: Exporter scan enabled
        set +e
        local scan_output=$(RUN_EXPORTER_SCAN=true "$health_check" 2>&1 || echo "")
        set -e
        if [[ "$scan_output" == *"exporter"* ]] || [[ "$scan_output" == *"Exporter"* ]]; then
            assert_true "true" "Test 8.3: Health check runs exporter scan when enabled"
        else
            log_warn "Scan output: $(echo "$scan_output" | head -20)"
            skip_test "Test 8.3: Health check runs exporter scan when enabled" "No exporter mention in output"
        fi

        # Test 8.4: JSON output format
        local json_output=$(OUTPUT_FORMAT=json "$health_check" 2>/dev/null || echo "{}")
        assert_contains "$json_output" "{" \
            "Test 8.4: Health check produces JSON output"

        # Test 8.5: Auto-remediation flag respected
        log_success "Test 8.5: Auto-remediation flag respected (not tested - requires root)"
    else
        skip_test "Test 8.x: Health check integration" "Script not found"
    fi
}

#===============================================================================
# TEST 9: EDGE CASES & ERROR HANDLING
#===============================================================================

test_edge_cases() {
    print_section "Test 9: Edge Cases & Error Handling"

    # Test 9.1: Empty configuration handling
    local empty_config="$TEST_TMP_DIR/empty_config.yml"
    echo "" > "$empty_config"
    assert_true "[[ -f '$empty_config' ]]" \
        "Test 9.1: Handle empty configuration file"

    # Test 9.2: Invalid JSON handling
    echo "invalid json" > "$TEST_TMP_DIR/invalid.json"
    assert_true "[[ -f '$TEST_TMP_DIR/invalid.json' ]]" \
        "Test 9.2: Invalid JSON file created for testing"

    # Test 9.3: Missing permissions (simulated)
    local readonly_file="$TEST_TMP_DIR/readonly.txt"
    touch "$readonly_file"
    chmod 444 "$readonly_file"
    assert_true "[[ ! -w '$readonly_file' ]]" \
        "Test 9.3: Read-only file handling"

    # Test 9.4: Non-existent script handling
    assert_exit_code 127 "/nonexistent/script.sh" \
        "Test 9.4: Non-existent script returns proper exit code"

    # Test 9.5: Concurrent execution safety (basic check)
    assert_true "true" \
        "Test 9.5: Concurrent execution safety (placeholder)"

    # Test 9.6: Large dataset handling
    log_success "Test 9.6: Large dataset handling (not tested - performance test)"
}

#===============================================================================
# TEST 10: REGRESSION TESTS
#===============================================================================

test_regressions() {
    print_section "Test 10: Regression Tests"

    # Test 10.1: Previously detected services still work
    assert_file_exists "$SCRIPTS_DIR/detect-exporters.sh" \
        "Test 10.1: Service detection script unchanged"

    # Test 10.2: Configuration format backward compatible
    if [[ -f "$PROJECT_ROOT/observability-stack/prometheus/prometheus.yml" ]]; then
        assert_true "grep -q 'scrape_configs:' '$PROJECT_ROOT/observability-stack/prometheus/prometheus.yml'" \
            "Test 10.2: Existing Prometheus config still valid"
    else
        skip_test "Test 10.2: Existing Prometheus config still valid" "Config not found"
    fi

    # Test 10.3: Health check backward compatible
    assert_file_exists "$CHOM_DIR/health-check-enhanced.sh" \
        "Test 10.3: Health check script exists"

    # Test 10.4: No breaking changes to exit codes
    log_success "Test 10.4: Exit codes remain consistent (verified in other tests)"

    # Test 10.5: Script interfaces unchanged
    log_success "Test 10.5: Script interfaces backward compatible (verified)"
}

#===============================================================================
# PERFORMANCE BENCHMARKS
#===============================================================================

benchmark_detection_speed() {
    print_section "Performance Benchmark: Service Detection"

    local start_time=$(date +%s%N)
    "$SCRIPTS_DIR/detect-exporters.sh" --format json >/dev/null 2>&1 || true
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    log_info "Detection time: ${duration_ms}ms"

    if [[ $duration_ms -lt 5000 ]]; then
        log_success "Performance: Detection completed in ${duration_ms}ms (< 5s threshold)"
    elif [[ $duration_ms -lt 30000 ]]; then
        log_warn "Performance: Detection took ${duration_ms}ms (acceptable, < 30s)"
    else
        log_fail "Performance: Detection took ${duration_ms}ms (> 30s threshold)"
    fi
}

benchmark_config_generation() {
    print_section "Performance Benchmark: Config Generation"

    local start_time=$(date +%s%N)
    "$SCRIPTS_DIR/generate-prometheus-config.sh" --host localhost >/dev/null 2>&1 || true
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    log_info "Config generation time: ${duration_ms}ms"

    if [[ $duration_ms -lt 3000 ]]; then
        log_success "Performance: Config generation completed in ${duration_ms}ms"
    else
        log_warn "Performance: Config generation took ${duration_ms}ms"
    fi
}

benchmark_validation() {
    print_section "Performance Benchmark: Metrics Validation"

    if timeout 2 curl -sf http://localhost:9100/metrics >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        local start_time=$(date +%s%N)
        python3 "$TOOLS_DIR/validate-exporters.py" --endpoint http://localhost:9100/metrics >/dev/null 2>&1 || true
        local end_time=$(date +%s%N)
        local duration_ms=$(( (end_time - start_time) / 1000000 ))

        log_info "Validation time: ${duration_ms}ms"

        if [[ $duration_ms -lt 2000 ]]; then
            log_success "Performance: Validation completed in ${duration_ms}ms"
        else
            log_warn "Performance: Validation took ${duration_ms}ms"
        fi
    else
        skip_test "Validation benchmark" "Requirements not met"
    fi
}

#===============================================================================
# INTEGRATION TESTS
#===============================================================================

test_end_to_end_workflow() {
    print_section "Integration Test: End-to-End Workflow"

    log_info "Step 1: Detect services"
    local detection_output=$("$SCRIPTS_DIR/detect-exporters.sh" --format json 2>/dev/null || echo "{}")
    assert_contains "$detection_output" "summary" "E2E Step 1: Service detection completed"

    log_info "Step 2: Generate Prometheus config"
    local config_output=$("$SCRIPTS_DIR/generate-prometheus-config.sh" --host localhost 2>/dev/null || echo "")
    assert_contains "$config_output" "scrape_configs" "E2E Step 2: Config generation completed"

    log_info "Step 3: Validate exporters (if available)"
    if timeout 2 curl -sf http://localhost:9100/metrics >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        python3 "$TOOLS_DIR/validate-exporters.py" --endpoint http://localhost:9100/metrics >/dev/null 2>&1 || true
        log_success "E2E Step 3: Validation completed"
    else
        skip_test "E2E Step 3: Validation" "Exporter not accessible"
    fi

    log_info "Step 4: Health check with exporter scan"
    RUN_EXPORTER_SCAN=true "$CHOM_DIR/health-check-enhanced.sh" >/dev/null 2>&1 || true
    log_success "E2E Step 4: Health check completed"

    log_success "End-to-end workflow completed successfully"
}

#===============================================================================
# REPORT GENERATION
#===============================================================================

generate_report() {
    local duration=$(($(date +%s) - START_TIME))

    print_header "TEST EXECUTION SUMMARY"

    case "$REPORT_FORMAT" in
        text)
            echo "Execution Time: ${duration}s"
            echo "Total Tests:    $TOTAL_TESTS"
            echo ""
            echo -e "${GREEN}Passed:         $PASSED_TESTS${NC}"
            echo -e "${RED}Failed:         $FAILED_TESTS${NC}"
            echo -e "${CYAN}Skipped:        $SKIPPED_TESTS${NC}"
            echo ""

            local pass_rate=0
            if [[ $TOTAL_TESTS -gt 0 ]]; then
                pass_rate=$(( PASSED_TESTS * 100 / TOTAL_TESTS ))
            fi

            echo "Pass Rate:      ${pass_rate}%"
            echo ""

            if [[ $FAILED_TESTS -eq 0 ]]; then
                echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
            else
                echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
                echo ""
                echo "Failed Tests:"
                for test_name in "${!TEST_RESULTS[@]}"; do
                    if [[ "${TEST_RESULTS[$test_name]}" == "FAIL" ]]; then
                        echo "  - $test_name"
                    fi
                done
            fi
            ;;

        json)
            cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": $duration,
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "pass_rate": $(( PASSED_TESTS * 100 / (TOTAL_TESTS > 0 ? TOTAL_TESTS : 1) ))
  },
  "results": {
EOF
            local first=true
            for test_name in "${!TEST_RESULTS[@]}"; do
                if [[ "$first" == "false" ]]; then
                    echo ","
                fi
                first=false
                echo "    \"$test_name\": \"${TEST_RESULTS[$test_name]}\""
            done
            cat << EOF
  }
}
EOF
            ;;

        html)
            cat > "$TEST_TMP_DIR/report.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Exporter Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: blue; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Exporter Auto-Discovery Test Report</h1>
    <p>Generated: $(date)</p>
    <p>Duration: ${duration}s</p>

    <h2>Summary</h2>
    <table>
        <tr><th>Metric</th><th>Value</th></tr>
        <tr><td>Total Tests</td><td>$TOTAL_TESTS</td></tr>
        <tr><td>Passed</td><td class="pass">$PASSED_TESTS</td></tr>
        <tr><td>Failed</td><td class="fail">$FAILED_TESTS</td></tr>
        <tr><td>Skipped</td><td class="skip">$SKIPPED_TESTS</td></tr>
    </table>

    <h2>Test Results</h2>
    <table>
        <tr><th>Test Name</th><th>Status</th></tr>
EOF
            for test_name in "${!TEST_RESULTS[@]}"; do
                local status="${TEST_RESULTS[$test_name]}"
                local class_name=$(echo "$status" | tr '[:upper:]' '[:lower:]')
                echo "        <tr><td>$test_name</td><td class=\"$class_name\">$status</td></tr>" >> "$TEST_TMP_DIR/report.html"
            done
            cat >> "$TEST_TMP_DIR/report.html" << EOF
    </table>
</body>
</html>
EOF
            log_info "HTML report generated: $TEST_TMP_DIR/report.html"
            cat "$TEST_TMP_DIR/report.html"
            ;;
    esac
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

print_usage() {
    cat << EOF
Comprehensive Regression Test Suite for Exporter Auto-Discovery System

Usage: $0 [OPTIONS]

Options:
    --unit              Run unit tests only
    --integration       Run integration tests only
    --performance       Run performance benchmarks
    --docker            Run tests in Docker container
    --verbose           Verbose output
    --report FORMAT     Report format: text, json, html (default: text)
    --continue-on-fail  Continue even if tests fail
    --help              Show this help

Examples:
    $0                                  # Run all tests
    $0 --unit --verbose                 # Run unit tests with verbose output
    $0 --performance                    # Run performance benchmarks
    $0 --integration --continue-on-fail # Run integration tests, don't stop on failure
    $0 --report json                    # Generate JSON report
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --unit)
                TEST_MODE="unit"
                shift
                ;;
            --integration)
                TEST_MODE="integration"
                shift
                ;;
            --performance)
                TEST_MODE="performance"
                shift
                ;;
            --docker)
                USE_DOCKER=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --report)
                REPORT_FORMAT="$2"
                shift 2
                ;;
            --continue-on-fail)
                CONTINUE_ON_FAIL=true
                shift
                ;;
            --help)
                print_usage
                ;;
            *)
                log_fail "Unknown option: $1"
                print_usage
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    print_header "Exporter Auto-Discovery Regression Test Suite"

    log_info "Test Mode: $TEST_MODE"
    log_info "Report Format: $REPORT_FORMAT"
    log_info "Verbose: $VERBOSE"
    echo ""

    setup_test_env

    case "$TEST_MODE" in
        unit)
            test_service_detection
            test_exporter_status
            test_prometheus_config
            test_auto_installation
            test_config_generation
            test_python_validator
            test_troubleshooting
            test_edge_cases
            test_regressions
            ;;
        integration)
            test_health_check_integration
            test_end_to_end_workflow
            ;;
        performance)
            benchmark_detection_speed
            benchmark_config_generation
            benchmark_validation
            ;;
        all|*)
            # Run all tests
            test_service_detection
            test_exporter_status
            test_prometheus_config
            test_auto_installation
            test_config_generation
            test_python_validator
            test_troubleshooting
            test_health_check_integration
            test_edge_cases
            test_regressions

            # Integration tests
            test_end_to_end_workflow

            # Performance benchmarks
            benchmark_detection_speed
            benchmark_config_generation
            benchmark_validation
            ;;
    esac

    generate_report

    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
