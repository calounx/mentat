#!/bin/bash
#===============================================================================
# Configuration Generator Library
# Generates Prometheus, alert rules, and dashboards from enabled modules
#===============================================================================

# Source dependencies (only if not already loaded)
_CONFIG_GEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    source "$_CONFIG_GEN_DIR/common.sh"
fi
if [[ -z "${MODULE_LOADER_LOADED:-}" ]]; then
    source "$_CONFIG_GEN_DIR/module-loader.sh"
fi

#===============================================================================
# PROMETHEUS CONFIGURATION GENERATION
#===============================================================================

# Get all unique enabled modules across all hosts
get_all_enabled_modules() {
    local modules=()

    for host_config in "$(get_hosts_config_dir)"/*.yaml; do
        [[ -f "$host_config" ]] || continue
        [[ "$host_config" == *".template"* ]] && continue

        while IFS= read -r module; do
            [[ -n "$module" ]] && modules+=("$module")
        done < <(get_host_enabled_modules "$(basename "$host_config" .yaml)")
    done

    printf '%s\n' "${modules[@]}" | sort -u
}

# Generate Prometheus scrape configuration for a module
generate_module_scrape_config() {
    local module="$1"
    local manifest
    local job_name
    local scrape_interval
    local port

    manifest=$(get_module_manifest "$module") || return 1
    job_name=$(yaml_get_nested "$manifest" "prometheus" "job_name")
    scrape_interval=$(yaml_get_nested "$manifest" "prometheus" "scrape_interval")
    port=$(module_port "$module")

    [[ -z "$job_name" ]] && job_name="$module"
    [[ -z "$scrape_interval" ]] && scrape_interval="15s"

    # Collect targets from all hosts with this module enabled
    local target_configs=""

    for host_config in "$(get_hosts_config_dir)"/*.yaml; do
        [[ -f "$host_config" ]] || continue
        [[ "$host_config" == *".template"* ]] && continue

        local hostname
        hostname=$(basename "$host_config" .yaml)

        if module_enabled_for_host "$module" "$hostname"; then
            local host_ip host_name

            host_ip=$(yaml_get_nested "$host_config" "host" "ip")
            host_name=$(yaml_get_nested "$host_config" "host" "name")
            host_name="${host_name:-$hostname}"

            # Skip if no IP configured
            [[ -z "$host_ip" ]] && continue

            # Build target config
            target_configs+="      - targets: ['${host_ip}:${port}']
        labels:
          instance: '${host_name}'
"
        fi
    done

    # Skip if no targets
    [[ -z "$target_configs" ]] && return 0

    # Output scrape config
    cat << EOF

  - job_name: '${job_name}'
    scrape_interval: ${scrape_interval}
    static_configs:
${target_configs}
EOF
}

# Write file atomically using temp file and validation
# Usage: atomic_write "target_file" "content" ["validation_command"]
atomic_write() {
    local target="$1"
    local content="$2"
    local validation_cmd="${3:-}"

    # Create temp file in same directory as target for atomic mv
    local target_dir
    target_dir=$(dirname "$target")
    local temp_file
    temp_file=$(mktemp "${target_dir}/.tmp.XXXXXXXXXX") || {
        log_error "Failed to create temp file in $target_dir"
        return 1
    }

    # Write content to temp file
    printf '%s\n' "$content" > "$temp_file" || {
        log_error "Failed to write to temp file $temp_file"
        rm -f "$temp_file"
        return 1
    }

    # Validate if validation command provided
    if [[ -n "$validation_cmd" ]]; then
        if ! $validation_cmd "$temp_file" >/dev/null 2>&1; then
            log_error "Validation failed for $target"
            log_info "Validation command: $validation_cmd $temp_file"
            $validation_cmd "$temp_file" || true
            rm -f "$temp_file"
            return 1
        fi
        log_debug "Validation passed for $target"
    fi

    # Atomic move (replace)
    mv -f "$temp_file" "$target" || {
        log_error "Failed to move $temp_file to $target"
        rm -f "$temp_file"
        return 1
    }

    log_debug "Atomically wrote $target"
    return 0
}

# Generate complete Prometheus configuration
generate_prometheus_config() {
    local global_config
    global_config=$(get_config_dir)/global.yaml

    local retention_days
    retention_days=$(yaml_get_nested "$global_config" "retention" "metrics_days")
    retention_days="${retention_days:-15}"

    cat << 'EOF'
# Prometheus Configuration
# Auto-generated from module registry - DO NOT EDIT DIRECTLY
# Regenerate with: ./scripts/module-manager.sh generate-config

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'observability-stack'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  # Self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'observability-vps'
EOF

    # Generate scrape configs for each enabled module
    while IFS= read -r module; do
        generate_module_scrape_config "$module"
    done < <(get_all_enabled_modules)
}

#===============================================================================
# ALERT RULES AGGREGATION
#===============================================================================

# Copy alert rules from enabled modules to prometheus rules directory
aggregate_alert_rules() {
    local rules_dir="${1:-/etc/prometheus/rules}"
    local module_rules_suffix="_module"

    log_info "Aggregating alert rules to $rules_dir..."

    # Ensure rules directory exists
    mkdir -p "$rules_dir" || {
        log_error "Failed to create rules directory: $rules_dir"
        return 1
    }

    # Remove old module-generated rules
    rm -f "$rules_dir"/*${module_rules_suffix}.yml || {
        log_error "Failed to remove old rule files from $rules_dir"
        return 1
    }

    # Copy rules from each enabled module using atomic operations
    local error_count=0
    while IFS= read -r module; do
        local module_dir alerts_file output_file

        module_dir=$(get_module_dir "$module") || {
            log_warn "Failed to get module dir for $module"
            ((error_count++))
            continue
        }

        alerts_file="$module_dir/alerts.yml"
        output_file="$rules_dir/${module}${module_rules_suffix}.yml"

        if [[ -f "$alerts_file" ]] && [[ -s "$alerts_file" ]]; then
            # Read content and write atomically
            local content
            content=$(cat "$alerts_file") || {
                log_error "Failed to read alerts file: $alerts_file"
                ((error_count++))
                continue
            }

            if atomic_write "$output_file" "$content"; then
                log_debug "Copied alerts for $module"
            else
                log_error "Failed to write alerts for $module"
                ((error_count++))
            fi
        fi
    done < <(get_all_enabled_modules)

    if [[ $error_count -gt 0 ]]; then
        log_warn "Alert rules aggregated with $error_count errors"
        return 1
    fi

    log_success "Alert rules aggregated"
    return 0
}

#===============================================================================
# DASHBOARD PROVISIONING
#===============================================================================

# Copy dashboards from enabled modules to Grafana dashboards directory
provision_dashboards() {
    local dashboards_dir="${1:-/var/lib/grafana/dashboards}"
    local module_dashboard_suffix="_module"

    log_info "Provisioning dashboards to $dashboards_dir..."

    # Ensure directory exists
    mkdir -p "$dashboards_dir" || {
        log_error "Failed to create dashboards directory: $dashboards_dir"
        return 1
    }

    # Remove old module-generated dashboards
    rm -f "$dashboards_dir"/*${module_dashboard_suffix}.json || {
        log_error "Failed to remove old dashboard files from $dashboards_dir"
        return 1
    }

    # Copy dashboards from each enabled module using atomic operations
    local error_count=0
    while IFS= read -r module; do
        local module_dir dashboard_file output_file

        module_dir=$(get_module_dir "$module") || {
            log_warn "Failed to get module dir for $module"
            ((error_count++))
            continue
        }

        dashboard_file="$module_dir/dashboard.json"
        output_file="$dashboards_dir/${module}${module_dashboard_suffix}.json"

        if [[ -f "$dashboard_file" ]] && [[ -s "$dashboard_file" ]]; then
            # Read content and write atomically
            local content
            content=$(cat "$dashboard_file") || {
                log_error "Failed to read dashboard file: $dashboard_file"
                ((error_count++))
                continue
            }

            if atomic_write "$output_file" "$content"; then
                log_debug "Copied dashboard for $module"
            else
                log_error "Failed to write dashboard for $module"
                ((error_count++))
            fi
        fi
    done < <(get_all_enabled_modules)

    if [[ $error_count -gt 0 ]]; then
        log_warn "Dashboards provisioned with $error_count errors"
        return 1
    fi

    log_success "Dashboards provisioned"
    return 0
}

#===============================================================================
# COMPLETE GENERATION
#===============================================================================

# Generate all configurations
generate_all_configs() {
    local prometheus_config="${1:-/etc/prometheus/prometheus.yml}"
    local rules_dir="${2:-/etc/prometheus/rules}"
    local dashboards_dir="${3:-/var/lib/grafana/dashboards}"

    log_info "Generating all configurations from modules..."
    echo ""

    # Generate Prometheus config
    log_info "Generating Prometheus configuration..."
    local prom_config
    prom_config=$(generate_prometheus_config) || {
        log_error "Failed to generate Prometheus configuration"
        return 1
    }

    # Use atomic write with validation
    local validation_cmd=""
    if command -v promtool &>/dev/null; then
        validation_cmd="promtool check config"
    fi

    if [[ -n "$validation_cmd" ]]; then
        if atomic_write "$prometheus_config" "$prom_config" "$validation_cmd"; then
            log_success "Prometheus configuration generated: $prometheus_config"
        else
            log_error "Failed to write Prometheus config (validation failed or write error)"
            return 1
        fi
    else
        log_warn "promtool not found, config not validated"
        if atomic_write "$prometheus_config" "$prom_config"; then
            log_success "Prometheus configuration generated: $prometheus_config"
        else
            log_error "Failed to write Prometheus config"
            return 1
        fi
    fi

    # Aggregate alert rules
    if ! aggregate_alert_rules "$rules_dir"; then
        log_error "Failed to aggregate alert rules"
        return 1
    fi

    # Provision dashboards
    if ! provision_dashboards "$dashboards_dir"; then
        log_error "Failed to provision dashboards"
        return 1
    fi

    echo ""
    log_success "All configurations generated successfully"
    return 0
}

# Show what would be generated (dry run)
show_generation_plan() {
    echo ""
    echo "Configuration Generation Plan"
    echo "=============================="
    echo ""

    echo "Enabled modules across all hosts:"
    while IFS= read -r module; do
        local display_name
        display_name=$(module_display_name "$module")
        echo "  - ${display_name:-$module}"
    done < <(get_all_enabled_modules)

    echo ""
    echo "Host configurations:"
    for host_config in "$(get_hosts_config_dir)"/*.yaml; do
        [[ -f "$host_config" ]] || continue
        [[ "$host_config" == *".template"* ]] && continue

        local hostname
        hostname=$(basename "$host_config" .yaml)
        local enabled_count=0

        while IFS= read -r module; do
            ((enabled_count++))
        done < <(get_host_enabled_modules "$hostname")

        echo "  - $hostname: $enabled_count modules enabled"
    done

    echo ""
    echo "Files that would be generated:"
    echo "  - /etc/prometheus/prometheus.yml"
    echo "  - /etc/prometheus/rules/*_module.yml"
    echo "  - /var/lib/grafana/dashboards/*_module.json"
    echo ""
}
