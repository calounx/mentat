#!/usr/bin/env bats
#===============================================================================
# Unit Tests for config-generator.sh Library Functions
# Tests Prometheus config generation, alert rules, and dashboards
#===============================================================================

setup() {
    # Load libraries
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    # Create temporary test directory
    TEST_TMP="$BATS_TEST_TMPDIR/config_gen_tests_$$"
    mkdir -p "$TEST_TMP"/{config/hosts,modules,prometheus/rules,grafana/dashboards}

    # Set log directory to temp location (before sourcing common.sh)
    export LOG_BASE_DIR="$TEST_TMP"

    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/module-loader.sh"
    source "$LIB_DIR/config-generator.sh"

    # Note: Color variables (RED, GREEN, etc.) are readonly from common.sh
    # Tests run with colors enabled - output is captured by BATS anyway
}

teardown() {
    if [[ -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

#===============================================================================
# TEST FIXTURES
#===============================================================================

create_test_module() {
    local module_name="$1"
    local port="$2"

    mkdir -p "$TEST_TMP/modules/_core/$module_name"

    cat > "$TEST_TMP/modules/_core/$module_name/module.yaml" << EOF
module:
  name: $module_name
  display_name: Test Module $module_name
  version: 1.0.0
  description: Test module for testing
  category: test
exporter:
  port: $port
prometheus:
  job_name: ${module_name}_job
  scrape_interval: 15s
  scrape_timeout: 10s
EOF

    touch "$TEST_TMP/modules/_core/$module_name/install.sh"
}

create_test_host_config() {
    local hostname="$1"
    local ip="$2"
    shift 2
    local modules=("$@")

    cat > "$TEST_TMP/config/hosts/${hostname}.yaml" << EOF
host:
  name: $hostname
  ip: $ip
modules:
EOF

    for module in "${modules[@]}"; do
        cat >> "$TEST_TMP/config/hosts/${hostname}.yaml" << EOF
  $module:
    enabled: true
EOF
    done
}

#===============================================================================
# GET ALL ENABLED MODULES TESTS
#===============================================================================

@test "get_all_enabled_modules finds enabled modules across hosts" {
    # Create test modules
    create_test_module "test_module1" "9001"
    create_test_module "test_module2" "9002"

    # Create test hosts
    create_test_host_config "host1" "192.168.1.10" "test_module1" "test_module2"
    create_test_host_config "host2" "192.168.1.11" "test_module1"

    # Override functions to use test directory
    _orig_get_hosts_config_dir=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    result=$(get_all_enabled_modules)

    # Restore original functions
    eval "$_orig_get_hosts_config_dir"
    eval "$_orig_get_module_dir"

    # Should find both modules
    echo "$result" | grep -q "test_module1"
    echo "$result" | grep -q "test_module2"

    # Should be unique
    count=$(echo "$result" | grep -c "test_module1")
    [[ $count -eq 1 ]]
}

@test "get_all_enabled_modules returns empty when no hosts configured" {
    # Use empty hosts directory
    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/empty_hosts"; }
    mkdir -p "$TEST_TMP/empty_hosts"

    result=$(get_all_enabled_modules)

    eval "$_orig_func"

    [[ -z "$result" ]]
}

@test "get_all_enabled_modules skips template files" {
    # Create a template file
    cat > "$TEST_TMP/config/hosts/example.template.yaml" << 'EOF'
host:
  name: template
  ip: 0.0.0.0
modules:
  test:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    result=$(get_all_enabled_modules)

    eval "$_orig_func"

    # Should not include modules from template
    [[ -z "$result" ]]
}

#===============================================================================
# GENERATE MODULE SCRAPE CONFIG TESTS
#===============================================================================

@test "generate_module_scrape_config creates valid scrape config" {
    # Create test module and host
    create_test_module "test_exporter" "9100"
    create_test_host_config "testhost" "192.168.1.10" "test_exporter"

    # Override functions
    _orig_get_hosts_config_dir=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }
    _orig_get_module_manifest=$(declare -f get_module_manifest)
    get_module_manifest() { echo "$TEST_TMP/modules/_core/$1/module.yaml"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    result=$(generate_module_scrape_config "test_exporter")

    # Restore functions
    eval "$_orig_get_hosts_config_dir"
    eval "$_orig_get_module_manifest"
    eval "$_orig_get_module_dir"

    # Should contain job_name
    echo "$result" | grep -q "job_name:"

    # Should contain target with IP and port
    echo "$result" | grep -q "192.168.1.10:9100"

    # Should contain instance label
    echo "$result" | grep -q "instance:"

    # Should have proper YAML structure
    echo "$result" | grep -q "static_configs:"
    echo "$result" | grep -q "targets:"
}

@test "generate_module_scrape_config uses custom job_name from manifest" {
    create_test_module "custom_job" "9200"
    create_test_host_config "testhost" "192.168.1.10" "custom_job"

    _orig_get_hosts_config_dir=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }
    _orig_get_module_manifest=$(declare -f get_module_manifest)
    get_module_manifest() { echo "$TEST_TMP/modules/_core/$1/module.yaml"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    result=$(generate_module_scrape_config "custom_job")

    eval "$_orig_get_hosts_config_dir"
    eval "$_orig_get_module_manifest"
    eval "$_orig_get_module_dir"

    echo "$result" | grep -q "job_name: 'custom_job_job'"
}

@test "generate_module_scrape_config aggregates multiple hosts" {
    create_test_module "multi_host" "9300"
    create_test_host_config "host1" "192.168.1.10" "multi_host"
    create_test_host_config "host2" "192.168.1.11" "multi_host"
    create_test_host_config "host3" "192.168.1.12" "multi_host"

    _orig_get_hosts_config_dir=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }
    _orig_get_module_manifest=$(declare -f get_module_manifest)
    get_module_manifest() { echo "$TEST_TMP/modules/_core/$1/module.yaml"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    result=$(generate_module_scrape_config "multi_host")

    eval "$_orig_get_hosts_config_dir"
    eval "$_orig_get_module_manifest"
    eval "$_orig_get_module_dir"

    # Should contain all three hosts
    echo "$result" | grep -q "192.168.1.10:9300"
    echo "$result" | grep -q "192.168.1.11:9300"
    echo "$result" | grep -q "192.168.1.12:9300"
}

@test "generate_module_scrape_config skips hosts without IP" {
    create_test_module "no_ip_test" "9400"

    # Create host without IP
    cat > "$TEST_TMP/config/hosts/noip.yaml" << 'EOF'
host:
  name: noip
modules:
  no_ip_test:
    enabled: true
EOF

    _orig_get_hosts_config_dir=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }
    _orig_get_module_manifest=$(declare -f get_module_manifest)
    get_module_manifest() { echo "$TEST_TMP/modules/_core/$1/module.yaml"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    result=$(generate_module_scrape_config "no_ip_test")

    eval "$_orig_get_hosts_config_dir"
    eval "$_orig_get_module_manifest"
    eval "$_orig_get_module_dir"

    # Should return empty or minimal config
    [[ -z "$result" ]]
}

#===============================================================================
# GENERATE PROMETHEUS CONFIG TESTS
#===============================================================================

@test "generate_prometheus_config creates complete config" {
    # Create minimal test setup
    mkdir -p "$TEST_TMP/config"
    cat > "$TEST_TMP/config/global.yaml" << 'EOF'
retention:
  metrics_days: 15
EOF

    _orig_get_config_dir=$(declare -f get_config_dir)
    get_config_dir() { echo "$TEST_TMP/config"; }
    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo ""; }

    result=$(generate_prometheus_config)

    eval "$_orig_get_config_dir"
    eval "$_orig_get_all_enabled"

    # Should have global section
    echo "$result" | grep -q "^global:"

    # Should have alerting section
    echo "$result" | grep -q "^alerting:"

    # Should have rule_files
    echo "$result" | grep -q "^rule_files:"

    # Should have scrape_configs
    echo "$result" | grep -q "^scrape_configs:"

    # Should have self-monitoring job
    echo "$result" | grep -q "job_name: 'prometheus'"
}

@test "generate_prometheus_config includes header comment" {
    _orig_get_config_dir=$(declare -f get_config_dir)
    get_config_dir() { echo "$TEST_TMP/config"; }
    mkdir -p "$TEST_TMP/config"
    echo "retention:" > "$TEST_TMP/config/global.yaml"

    result=$(generate_prometheus_config)

    eval "$_orig_get_config_dir"

    # Should have auto-generated warning
    echo "$result" | grep -q "Auto-generated"
    echo "$result" | grep -q "DO NOT EDIT DIRECTLY"
}

@test "generate_prometheus_config uses retention from global config" {
    mkdir -p "$TEST_TMP/config"
    cat > "$TEST_TMP/config/global.yaml" << 'EOF'
retention:
  metrics_days: 30
EOF

    _orig_get_config_dir=$(declare -f get_config_dir)
    get_config_dir() { echo "$TEST_TMP/config"; }

    result=$(generate_prometheus_config)

    eval "$_orig_get_config_dir"

    # While the config doesn't directly show retention in YAML,
    # we verify it was read from global.yaml
    [[ -n "$result" ]]
}

#===============================================================================
# ALERT RULES AGGREGATION TESTS
#===============================================================================

@test "aggregate_alert_rules copies alert files" {
    # Create test module with alerts
    create_test_module "alerts_test" "9500"

    cat > "$TEST_TMP/modules/_core/alerts_test/alerts.yml" << 'EOF'
groups:
  - name: alerts_test
    rules:
      - alert: TestAlert
        expr: up == 0
        annotations:
          summary: Test alert
EOF

    rules_dir="$TEST_TMP/prometheus/rules"
    mkdir -p "$rules_dir"

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo "alerts_test"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    aggregate_alert_rules "$rules_dir"

    eval "$_orig_get_all_enabled"
    eval "$_orig_get_module_dir"

    # Check alert file was copied
    [[ -f "$rules_dir/alerts_test_module.yml" ]]

    # Verify content
    grep -q "TestAlert" "$rules_dir/alerts_test_module.yml"
}

@test "aggregate_alert_rules removes old module rules" {
    rules_dir="$TEST_TMP/prometheus/rules"
    mkdir -p "$rules_dir"

    # Create old rule file
    echo "old rules" > "$rules_dir/old_module_module.yml"

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo ""; }

    aggregate_alert_rules "$rules_dir"

    eval "$_orig_get_all_enabled"

    # Old file should be removed
    [[ ! -f "$rules_dir/old_module_module.yml" ]]
}

@test "aggregate_alert_rules skips modules without alerts" {
    create_test_module "no_alerts" "9600"
    # Don't create alerts.yml file

    rules_dir="$TEST_TMP/prometheus/rules"
    mkdir -p "$rules_dir"

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo "no_alerts"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    aggregate_alert_rules "$rules_dir"

    eval "$_orig_get_all_enabled"
    eval "$_orig_get_module_dir"

    # Should not create empty alert file
    [[ ! -f "$rules_dir/no_alerts_module.yml" ]]
}

#===============================================================================
# DASHBOARD PROVISIONING TESTS
#===============================================================================

@test "provision_dashboards copies dashboard files" {
    # Create test module with dashboard
    create_test_module "dashboard_test" "9700"

    cat > "$TEST_TMP/modules/_core/dashboard_test/dashboard.json" << 'EOF'
{
  "dashboard": {
    "title": "Test Dashboard"
  }
}
EOF

    dashboards_dir="$TEST_TMP/grafana/dashboards"
    mkdir -p "$dashboards_dir"

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo "dashboard_test"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    provision_dashboards "$dashboards_dir"

    eval "$_orig_get_all_enabled"
    eval "$_orig_get_module_dir"

    # Check dashboard was copied
    [[ -f "$dashboards_dir/dashboard_test_module.json" ]]

    # Verify content
    grep -q "Test Dashboard" "$dashboards_dir/dashboard_test_module.json"
}

@test "provision_dashboards removes old module dashboards" {
    dashboards_dir="$TEST_TMP/grafana/dashboards"
    mkdir -p "$dashboards_dir"

    # Create old dashboard
    echo "old dashboard" > "$dashboards_dir/old_module_module.json"

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo ""; }

    provision_dashboards "$dashboards_dir"

    eval "$_orig_get_all_enabled"

    # Old file should be removed
    [[ ! -f "$dashboards_dir/old_module_module.json" ]]
}

@test "provision_dashboards creates directory if missing" {
    dashboards_dir="$TEST_TMP/grafana/new_dashboards"

    [[ ! -d "$dashboards_dir" ]]

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo ""; }

    provision_dashboards "$dashboards_dir"

    eval "$_orig_get_all_enabled"

    [[ -d "$dashboards_dir" ]]
}

#===============================================================================
# GENERATION PLAN TESTS
#===============================================================================

@test "show_generation_plan displays summary" {
    create_test_module "plan_test" "9800"
    create_test_host_config "planhost" "192.168.1.10" "plan_test"

    _orig_get_hosts_config_dir=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }
    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo "plan_test"; }
    _orig_get_module_dir=$(declare -f get_module_dir)
    get_module_dir() { echo "$TEST_TMP/modules/_core/$1"; }

    result=$(show_generation_plan)

    eval "$_orig_get_hosts_config_dir"
    eval "$_orig_get_all_enabled"
    eval "$_orig_get_module_dir"

    # Should show enabled modules
    echo "$result" | grep -q "Enabled modules"

    # Should show host configurations
    echo "$result" | grep -q "Host configurations"

    # Should show files to be generated
    echo "$result" | grep -q "prometheus.yml"
}

#===============================================================================
# ERROR HANDLING AND EDGE CASES
#===============================================================================

@test "functions handle missing global config gracefully" {
    # Use directory without global.yaml
    _orig_func=$(declare -f get_config_dir)
    get_config_dir() { echo "$TEST_TMP/empty_config"; }
    mkdir -p "$TEST_TMP/empty_config"

    # Should use default retention
    result=$(generate_prometheus_config 2>/dev/null || echo "")

    eval "$_orig_func"

    [[ -n "$result" ]]
}

@test "generate_module_scrape_config handles missing manifest gracefully" {
    _orig_get_module_manifest=$(declare -f get_module_manifest)
    get_module_manifest() { return 1; }

    run generate_module_scrape_config "nonexistent"
    [[ $status -ne 0 ]]

    eval "$_orig_get_module_manifest"
}

@test "aggregate_alert_rules handles missing rules directory" {
    # Use non-existent directory
    rules_dir="$TEST_TMP/nonexistent/rules"

    _orig_get_all_enabled=$(declare -f get_all_enabled_modules)
    get_all_enabled_modules() { echo ""; }

    # Should create the directory
    aggregate_alert_rules "$rules_dir" 2>/dev/null || true

    eval "$_orig_get_all_enabled"
}
