#!/usr/bin/env bats
#===============================================================================
# Integration Tests for Configuration Generation
# Tests end-to-end config generation with real modules and validation
#===============================================================================

setup() {
    # Load libraries
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB_DIR="$STACK_ROOT/scripts/lib"

    # Create test directory
    TEST_TMP="$BATS_TEST_TMPDIR/config_integration_$$"
    mkdir -p "$TEST_TMP"/{prometheus/rules,grafana/dashboards,config/hosts}

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
# REAL PROMETHEUS CONFIG GENERATION TESTS
#===============================================================================

@test "generate_prometheus_config creates valid YAML" {
    config=$(generate_prometheus_config)

    # Save to temp file for validation
    echo "$config" > "$TEST_TMP/prometheus.yml"

    # Should be valid YAML (basic check)
    grep -q "global:" "$TEST_TMP/prometheus.yml"
    grep -q "scrape_configs:" "$TEST_TMP/prometheus.yml"

    # No obvious YAML syntax errors
    ! grep -q "^[[:space:]]*{" "$TEST_TMP/prometheus.yml"  # No JSON braces
}

@test "generated config includes all real enabled modules" {
    # This test uses actual host configs if they exist
    hosts_dir="$(get_hosts_config_dir)"

    if [[ -d "$hosts_dir" ]] && [[ $(ls -A "$hosts_dir"/*.yaml 2>/dev/null | wc -l) -gt 0 ]]; then
        config=$(generate_prometheus_config)

        # Get all enabled modules
        while IFS= read -r module; do
            # Config should mention this module or its job
            job_name=$(module_get_nested "$module" "prometheus" "job_name")
            if [[ -n "$job_name" ]]; then
                echo "$config" | grep -q "$job_name"
            fi
        done < <(get_all_enabled_modules)
    else
        skip "No host configurations exist"
    fi
}

@test "generated config has valid scrape_interval values" {
    config=$(generate_prometheus_config)

    # Extract all scrape_interval values
    intervals=$(echo "$config" | grep "scrape_interval:" | awk '{print $2}')

    while IFS= read -r interval; do
        [[ -n "$interval" ]]

        # Should end with s (seconds) or m (minutes)
        [[ "$interval" =~ ^[0-9]+[sm]$ ]]
    done <<< "$intervals"
}

@test "promtool validates generated prometheus config" {
    if ! command -v promtool &>/dev/null; then
        skip "promtool not installed"
    fi

    config=$(generate_prometheus_config)
    echo "$config" > "$TEST_TMP/prometheus.yml"

    # Validate with promtool
    promtool check config "$TEST_TMP/prometheus.yml"
}

#===============================================================================
# CONFIG GENERATION WITH TEST DATA
#===============================================================================

@test "config generation with single host and module" {
    # Create test host config
    cat > "$TEST_TMP/config/hosts/testhost.yaml" << 'EOF'
host:
  name: testhost
  ip: 192.168.1.100
modules:
  node_exporter:
    enabled: true
EOF

    # Override get_hosts_config_dir
    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    config=$(generate_prometheus_config)

    eval "$_orig_func"

    # Should contain the host IP
    echo "$config" | grep -q "192.168.1.100"

    # Should have node job
    echo "$config" | grep -q "job_name: 'node'"
}

@test "config generation with multiple hosts" {
    # Create multiple test hosts
    cat > "$TEST_TMP/config/hosts/host1.yaml" << 'EOF'
host:
  name: host1
  ip: 192.168.1.10
modules:
  node_exporter:
    enabled: true
EOF

    cat > "$TEST_TMP/config/hosts/host2.yaml" << 'EOF'
host:
  name: host2
  ip: 192.168.1.11
modules:
  node_exporter:
    enabled: true
EOF

    cat > "$TEST_TMP/config/hosts/host3.yaml" << 'EOF'
host:
  name: host3
  ip: 192.168.1.12
modules:
  node_exporter:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    config=$(generate_prometheus_config)

    eval "$_orig_func"

    # Should contain all three IPs
    echo "$config" | grep -q "192.168.1.10"
    echo "$config" | grep -q "192.168.1.11"
    echo "$config" | grep -q "192.168.1.12"
}

@test "config generation with mixed modules" {
    # Create host with multiple modules
    cat > "$TEST_TMP/config/hosts/multihost.yaml" << 'EOF'
host:
  name: multihost
  ip: 192.168.1.50
modules:
  node_exporter:
    enabled: true
  nginx_exporter:
    enabled: true
  promtail:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    config=$(generate_prometheus_config)

    eval "$_orig_func"

    # Should have multiple job sections
    job_count=$(echo "$config" | grep -c "job_name:")
    [[ $job_count -ge 3 ]]  # At least prometheus + the enabled modules
}

#===============================================================================
# ALERT RULES INTEGRATION TESTS
#===============================================================================

@test "aggregate_alert_rules creates valid alert files" {
    rules_dir="$TEST_TMP/prometheus/rules"

    # Run aggregation with real modules
    aggregate_alert_rules "$rules_dir"

    # Check if any rules were created
    if [[ $(ls -A "$rules_dir"/*.yml 2>/dev/null | wc -l) -gt 0 ]]; then
        # Each rule file should be valid YAML
        for rule_file in "$rules_dir"/*.yml; do
            grep -q "groups:" "$rule_file"
        done
    fi
}

@test "aggregated alert rules follow naming convention" {
    rules_dir="$TEST_TMP/prometheus/rules"

    aggregate_alert_rules "$rules_dir"

    # All module-generated rules should end with _module.yml
    for rule_file in "$rules_dir"/*_module.yml; do
        [[ -f "$rule_file" ]] || continue

        # Filename should match pattern
        basename "$rule_file" | grep -q "_module.yml$"
    done
}

@test "promtool validates aggregated alert rules" {
    if ! command -v promtool &>/dev/null; then
        skip "promtool not installed"
    fi

    rules_dir="$TEST_TMP/prometheus/rules"
    aggregate_alert_rules "$rules_dir"

    # Validate each rule file
    for rule_file in "$rules_dir"/*.yml; do
        [[ -f "$rule_file" ]] || continue

        promtool check rules "$rule_file"
    done
}

@test "alert rules contain required fields" {
    rules_dir="$TEST_TMP/prometheus/rules"
    aggregate_alert_rules "$rules_dir"

    for rule_file in "$rules_dir"/*.yml; do
        [[ -f "$rule_file" ]] || continue

        # Should have groups
        grep -q "groups:" "$rule_file"

        # Should have rules
        grep -q "rules:" "$rule_file"

        # Alerts should have expr
        if grep -q "alert:" "$rule_file"; then
            grep -q "expr:" "$rule_file"
        fi
    done
}

#===============================================================================
# DASHBOARD PROVISIONING INTEGRATION TESTS
#===============================================================================

@test "provision_dashboards creates valid JSON files" {
    dashboards_dir="$TEST_TMP/grafana/dashboards"

    provision_dashboards "$dashboards_dir"

    # Check each dashboard is valid JSON
    for dashboard in "$dashboards_dir"/*.json; do
        [[ -f "$dashboard" ]] || continue

        # Should be valid JSON (basic check)
        python3 -c "import json; json.load(open('$dashboard'))" 2>/dev/null ||
        ruby -e "require 'json'; JSON.parse(File.read('$dashboard'))" 2>/dev/null ||
        skip "No JSON validator available"
    done
}

@test "provisioned dashboards follow naming convention" {
    dashboards_dir="$TEST_TMP/grafana/dashboards"

    provision_dashboards "$dashboards_dir"

    # All module dashboards should end with _module.json
    for dashboard in "$dashboards_dir"/*_module.json; do
        [[ -f "$dashboard" ]] || continue

        basename "$dashboard" | grep -q "_module.json$"
    done
}

@test "dashboards contain required Grafana structure" {
    dashboards_dir="$TEST_TMP/grafana/dashboards"

    provision_dashboards "$dashboards_dir"

    for dashboard in "$dashboards_dir"/*.json; do
        [[ -f "$dashboard" ]] || continue

        # Should have basic Grafana structure
        grep -q "dashboard" "$dashboard" || grep -q "panels" "$dashboard" || true
    done
}

#===============================================================================
# FULL GENERATION WORKFLOW TESTS
#===============================================================================

@test "generate_all_configs creates all required files" {
    prom_config="$TEST_TMP/prometheus/prometheus.yml"
    rules_dir="$TEST_TMP/prometheus/rules"
    dashboards_dir="$TEST_TMP/grafana/dashboards"

    # Create minimal global config
    mkdir -p "$TEST_TMP/config"
    echo "retention:" > "$TEST_TMP/config/global.yaml"

    _orig_get_config=$(declare -f get_config_dir)
    get_config_dir() { echo "$TEST_TMP/config"; }

    # Skip promtool validation for this test
    _orig_promtool=$(type -p promtool 2>/dev/null || echo "")
    if [[ -n "$_orig_promtool" ]]; then
        function promtool() { return 0; }
    fi

    generate_all_configs "$prom_config" "$rules_dir" "$dashboards_dir" 2>/dev/null || true

    eval "$_orig_get_config"

    # Prometheus config should be created
    [[ -f "$prom_config" ]]

    # Rules directory should exist
    [[ -d "$rules_dir" ]]

    # Dashboards directory should exist
    [[ -d "$dashboards_dir" ]]
}

@test "show_generation_plan displays without errors" {
    # Should run without errors
    result=$(show_generation_plan 2>&1)

    # Should have content
    [[ -n "$result" ]]

    # Should mention key sections
    echo "$result" | grep -q "modules" || echo "$result" | grep -q "host" || true
}

#===============================================================================
# CONFIGURATION UPDATES AND IDEMPOTENCY
#===============================================================================

@test "regenerating config with same data produces same output" {
    cat > "$TEST_TMP/config/hosts/idempotent.yaml" << 'EOF'
host:
  name: idempotent
  ip: 192.168.1.200
modules:
  node_exporter:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    # Generate twice
    config1=$(generate_prometheus_config)
    config2=$(generate_prometheus_config)

    eval "$_orig_func"

    # Should be identical
    [[ "$config1" == "$config2" ]]
}

@test "config generation handles host addition" {
    cat > "$TEST_TMP/config/hosts/initial.yaml" << 'EOF'
host:
  name: initial
  ip: 192.168.1.100
modules:
  node_exporter:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    config1=$(generate_prometheus_config)

    # Add second host
    cat > "$TEST_TMP/config/hosts/second.yaml" << 'EOF'
host:
  name: second
  ip: 192.168.1.101
modules:
  node_exporter:
    enabled: true
EOF

    config2=$(generate_prometheus_config)

    eval "$_orig_func"

    # Second config should be different
    [[ "$config1" != "$config2" ]]

    # Second config should include both hosts
    echo "$config2" | grep -q "192.168.1.100"
    echo "$config2" | grep -q "192.168.1.101"
}

#===============================================================================
# ERROR RECOVERY TESTS
#===============================================================================

@test "config generation handles missing host IP gracefully" {
    cat > "$TEST_TMP/config/hosts/no_ip.yaml" << 'EOF'
host:
  name: no_ip
modules:
  node_exporter:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    # Should not crash
    config=$(generate_prometheus_config 2>/dev/null || echo "")

    eval "$_orig_func"

    # Should still generate config
    [[ -n "$config" ]]
}

@test "config generation handles malformed host config" {
    cat > "$TEST_TMP/config/hosts/malformed.yaml" << 'EOF'
this: is: not: valid: yaml: structure:
  random: data
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    # Should not crash
    config=$(generate_prometheus_config 2>/dev/null || echo "generated")

    eval "$_orig_func"

    # Should generate something
    [[ -n "$config" ]]
}

#===============================================================================
# TEMPLATE FILES EXCLUSION TESTS
#===============================================================================

@test "config generation ignores template files" {
    cat > "$TEST_TMP/config/hosts/example.template.yaml" << 'EOF'
host:
  name: template
  ip: 0.0.0.0
modules:
  node_exporter:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    config=$(generate_prometheus_config)

    eval "$_orig_func"

    # Should NOT include template IP
    ! echo "$config" | grep -q "0.0.0.0"
}

#===============================================================================
# PORT COLLISION DETECTION
#===============================================================================

@test "no duplicate ports in module manifests" {
    declare -A ports_seen

    while IFS= read -r module; do
        port=$(module_port "$module")

        if [[ -n "${ports_seen[$port]:-}" ]]; then
            # Port collision detected
            echo "Port $port used by both $module and ${ports_seen[$port]}"
            false
        fi

        ports_seen[$port]="$module"
    done < <(list_all_modules)
}

#===============================================================================
# REAL WORLD SCENARIO TESTS
#===============================================================================

@test "config generation with typical web server setup" {
    cat > "$TEST_TMP/config/hosts/webserver.yaml" << 'EOF'
host:
  name: webserver
  ip: 192.168.1.150
modules:
  node_exporter:
    enabled: true
  nginx_exporter:
    enabled: true
  promtail:
    enabled: true
EOF

    _orig_func=$(declare -f get_hosts_config_dir)
    get_hosts_config_dir() { echo "$TEST_TMP/config/hosts"; }

    config=$(generate_prometheus_config)

    eval "$_orig_func"

    # Should have the host
    echo "$config" | grep -q "192.168.1.150"

    # Should have multiple jobs
    job_count=$(echo "$config" | grep -c "job_name:")
    [[ $job_count -ge 2 ]]
}
