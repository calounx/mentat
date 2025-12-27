# Observability Stack Upgrade Mechanism Design

## Executive Summary

This document describes the design of an idempotent, safe, and automated upgrade mechanism for the observability stack components. The system supports automatic version checking, safe upgrades with rollback capabilities, and production-ready safety controls.

---

## 1. Upgrade Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                       UPGRADE WORKFLOW                              │
└─────────────────────────────────────────────────────────────────────┘

[START]
   │
   ├─> Read current versions from state file
   │   (/var/lib/observability/versions.state)
   │
   ├─> Fetch available versions from upstream
   │   (GitHub releases, GitLab releases, etc.)
   │
   ├─> Compare versions and generate upgrade plan
   │   ┌─────────────────────────────────────┐
   │   │ Component   Current   Latest  Action│
   │   │ prometheus  2.48.1    2.49.0  Upgrade│
   │   │ loki        2.9.3     2.9.3   Skip  │
   │   │ node_exp    1.7.0     1.8.0   Upgrade│
   │   └─────────────────────────────────────┘
   │
   ├─> User approval (unless --auto mode)
   │   │
   │   ├─ Auto mode? ────> [Apply filters]
   │   │                   - Only patch versions
   │   │                   - Exclude blacklisted
   │   │                   - Check time window
   │   │
   │   └─ Interactive ───> [Show plan, prompt]
   │
   ├─> Pre-upgrade checks
   │   ├─ Sufficient disk space (2x binary size + data backup)
   │   ├─ Service health status (all components healthy)
   │   ├─ Compatibility matrix validation
   │   ├─ Config syntax validation
   │   └─ Backup prerequisites (backup location writable)
   │
   ├─> Create backup point
   │   ├─ Snapshot current binaries → /var/backups/observability/bin/{timestamp}/
   │   ├─ Snapshot configs → /var/backups/observability/config/{timestamp}/
   │   ├─ Save version state → /var/backups/observability/state/{timestamp}/
   │   └─ Log upgrade plan → /var/backups/observability/plans/{timestamp}.json
   │
   ├─> FOR EACH component in upgrade plan:
   │   │
   │   ├─> Download new binary to staging
   │   │   ├─ Download to /tmp/observability-upgrade/{component}/
   │   │   ├─ Verify checksum (SHA256)
   │   │   ├─ Verify GPG signature (if available)
   │   │   └─ Test binary execution (--version)
   │   │
   │   ├─> Stop service gracefully
   │   │   ├─ Send SIGTERM (graceful shutdown)
   │   │   ├─ Wait for clean shutdown (timeout: 30s)
   │   │   ├─ Force kill if needed (SIGKILL)
   │   │   └─ Verify process stopped
   │   │
   │   ├─> Replace binary atomically
   │   │   ├─ Copy new binary to /usr/local/bin/{component}.new
   │   │   ├─ Set permissions (0755, owner:group)
   │   │   ├─ Atomic rename: {component}.new → {component}
   │   │   └─ Sync filesystem
   │   │
   │   ├─> Start service
   │   │   ├─ systemctl start {service}
   │   │   └─ Wait for startup (timeout: 60s)
   │   │
   │   ├─> Health check
   │   │   ├─ HTTP endpoint check (metrics available)
   │   │   ├─ Service status check (systemd active)
   │   │   ├─ Log scan for errors (last 100 lines)
   │   │   └─ Functional test (scrape/query test)
   │   │
   │   ├─> Success? ─┬─ YES ──> Continue to next component
   │   │             │
   │   │             └─ NO ───> ROLLBACK PROCEDURE
   │   │                        ├─ Stop failed service
   │   │                        ├─ Restore old binary from backup
   │   │                        ├─ Restore old config (if changed)
   │   │                        ├─ Restart service
   │   │                        ├─ Verify rollback health
   │   │                        ├─ Mark component as failed
   │   │                        └─ Abort upgrade (or continue if --continue-on-failure)
   │   │
   │   └─> Update version state file
   │
   ├─> Post-upgrade tasks
   │   ├─ Reload Prometheus config (if targets changed)
   │   ├─ Rotate old backups (keep last N versions)
   │   ├─ Send notification (success/failure summary)
   │   ├─ Log to audit trail
   │   └─ Update upgrade history database
   │
   └─> [END]


┌─────────────────────────────────────────────────────────────────────┐
│                    ROLLBACK WORKFLOW                                │
└─────────────────────────────────────────────────────────────────────┘

[START: upgrade-rollback --to=<timestamp>]
   │
   ├─> Load backup metadata from timestamp
   │   (/var/backups/observability/plans/{timestamp}.json)
   │
   ├─> Validate backup exists and is complete
   │   ├─ Check binaries present
   │   ├─ Check configs present
   │   ├─ Check version state present
   │   └─ Verify integrity checksums
   │
   ├─> Display rollback plan
   │   ┌─────────────────────────────────────────┐
   │   │ Component   Current   Target   Action  │
   │   │ prometheus  2.49.0    2.48.1   Downgrade│
   │   │ node_exp    1.8.0     1.7.0    Downgrade│
   │   └─────────────────────────────────────────┘
   │
   ├─> User confirmation (unless --force)
   │
   ├─> FOR EACH component to rollback:
   │   │
   │   ├─> Stop service
   │   ├─> Restore binary from backup
   │   ├─> Restore config from backup
   │   ├─> Restore systemd unit (if changed)
   │   ├─> Reload systemd daemon
   │   ├─> Start service
   │   ├─> Verify health
   │   └─> Update version state
   │
   ├─> Log rollback completion
   │
   └─> [END]
```

---

## 2. Safety Checks Before Upgrade

### Pre-Flight Checks

```bash
check_upgrade_prerequisites() {
    local component="$1"
    local new_version="$2"

    # 1. Disk Space Check
    check_disk_space() {
        # Calculate required space:
        # - New binary size (estimate: 100MB per component)
        # - Backup space (current binary + configs)
        # - Data backup (if requested): current data dir size
        # - Safety margin: 20%

        local required_mb=$((100 + current_binary_size + config_size))
        local available_mb=$(df /var/lib/observability | awk 'NR==2 {print $4/1024}')

        if (( available_mb < required_mb * 1.2 )); then
            log_error "Insufficient disk space: need ${required_mb}MB, have ${available_mb}MB"
            return 1
        fi
    }

    # 2. Service Health Check
    check_service_health() {
        # All components must be healthy before upgrade
        if ! systemctl is-active --quiet "${component}"; then
            log_error "Service ${component} is not running - fix before upgrading"
            return 1
        fi

        # HTTP health check
        if ! curl -sf "${health_endpoint}" >/dev/null; then
            log_error "Service ${component} health check failed"
            return 1
        fi

        # Check for recent crashes
        if systemctl show "${component}" | grep -q "RestartCount=[1-9]"; then
            log_warn "Service ${component} has recent restarts - may be unstable"
            # Warning only, not fatal
        fi
    }

    # 3. Compatibility Matrix Check
    check_compatibility() {
        # Prometheus 2.49+ requires Alertmanager 0.26+
        # Loki 3.x requires Promtail 3.x (major version match)
        # Grafana 10.x compatible with Prometheus 2.x

        # Load compatibility rules from config
        local compat_file="/etc/observability/compatibility-matrix.yaml"

        # Example: Check if Prometheus 2.49 compatible with current Alertmanager
        if ! validate_version_compatibility "$component" "$new_version"; then
            log_error "Version $new_version incompatible with current stack"
            log_error "Check compatibility matrix: $compat_file"
            return 1
        fi
    }

    # 4. Config Syntax Validation
    check_config_syntax() {
        # Validate current config is valid
        case "$component" in
            prometheus)
                promtool check config /etc/prometheus/prometheus.yml || return 1
                promtool check rules /etc/prometheus/rules/*.yml || return 1
                ;;
            alertmanager)
                amtool check-config /etc/alertmanager/alertmanager.yml || return 1
                ;;
            loki)
                /usr/local/bin/loki -verify-config -config.file=/etc/loki/loki-config.yaml || return 1
                ;;
        esac
    }

    # 5. Backup Readiness Check
    check_backup_readiness() {
        local backup_dir="/var/backups/observability"

        # Check backup directory exists and is writable
        if [[ ! -d "$backup_dir" ]]; then
            mkdir -p "$backup_dir" || return 1
        fi

        if [[ ! -w "$backup_dir" ]]; then
            log_error "Backup directory not writable: $backup_dir"
            return 1
        fi

        # Check we can write test file
        local test_file="${backup_dir}/.write_test_$$"
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Cannot write to backup directory"
            return 1
        fi
        rm -f "$test_file"
    }

    # 6. Network Connectivity Check
    check_network() {
        # Can we reach GitHub for downloads?
        if ! curl -sf --max-time 5 https://api.github.com/rate_limit >/dev/null; then
            log_error "Cannot reach GitHub - check network connectivity"
            return 1
        fi
    }

    # 7. Lock File Check (prevent concurrent upgrades)
    check_lock() {
        local lock_file="/var/lock/observability-upgrade.lock"

        if [[ -f "$lock_file" ]]; then
            local lock_pid=$(cat "$lock_file")
            if kill -0 "$lock_pid" 2>/dev/null; then
                log_error "Another upgrade is in progress (PID: $lock_pid)"
                return 1
            else
                # Stale lock file
                log_warn "Removing stale lock file"
                rm -f "$lock_file"
            fi
        fi

        # Create lock
        echo $$ > "$lock_file"
    }

    # 8. Maintenance Window Check (if configured)
    check_maintenance_window() {
        local maint_config="/etc/observability/upgrade-policy.yaml"

        if [[ -f "$maint_config" ]]; then
            # Check if current time is within allowed window
            # Format: maintenance_windows: ["02:00-04:00", "14:00-16:00"]
            local current_hour=$(date +%H)
            local current_minute=$(date +%M)

            # Parse and validate against windows
            # (implementation details omitted)

            if ! in_maintenance_window; then
                log_error "Current time outside maintenance window"
                log_error "Allowed windows: $(get_maintenance_windows)"
                return 1
            fi
        fi
    }

    # Run all checks
    check_disk_space || return 1
    check_service_health || return 1
    check_compatibility || return 1
    check_config_syntax || return 1
    check_backup_readiness || return 1
    check_network || return 1
    check_lock || return 1
    check_maintenance_window || return 1

    return 0
}
```

### Download and Verification

```bash
download_and_verify() {
    local component="$1"
    local version="$2"
    local staging_dir="/tmp/observability-upgrade/${component}"

    mkdir -p "$staging_dir"
    cd "$staging_dir"

    # 1. Download binary
    local url=$(get_download_url "$component" "$version")
    log_info "Downloading ${component} ${version}..."

    if ! wget -q --timeout=60 --tries=3 "$url" -O archive; then
        log_error "Download failed: $url"
        return 1
    fi

    # 2. Download checksum
    local checksum_url=$(get_checksum_url "$component" "$version")
    if [[ -n "$checksum_url" ]]; then
        wget -q "$checksum_url" -O checksums.txt || {
            log_warn "Could not download checksums - skipping verification"
        }
    fi

    # 3. Verify checksum
    if [[ -f checksums.txt ]]; then
        local expected_sum=$(grep "$(basename "$url")" checksums.txt | awk '{print $1}')
        local actual_sum=$(sha256sum archive | awk '{print $1}')

        if [[ "$expected_sum" != "$actual_sum" ]]; then
            log_error "Checksum mismatch!"
            log_error "Expected: $expected_sum"
            log_error "Got:      $actual_sum"
            return 1
        fi
        log_success "Checksum verified"
    fi

    # 4. Extract binary
    extract_archive "archive" "$component"

    # 5. Test binary execution
    local binary_path=$(find . -name "$component" -type f -executable | head -1)

    if [[ ! -x "$binary_path" ]]; then
        log_error "Binary not found or not executable"
        return 1
    fi

    # Test execution
    if ! "$binary_path" --version &>/dev/null; then
        log_error "Binary execution test failed"
        return 1
    fi

    # Verify version string matches expected
    local actual_version=$("$binary_path" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ "$actual_version" != "$version" ]]; then
        log_error "Version mismatch: expected $version, got $actual_version"
        return 1
    fi

    log_success "Binary downloaded and verified: $binary_path"
    echo "$binary_path"
}
```

---

## 3. Rollback Procedure

### Automatic Rollback on Failure

```bash
rollback_component() {
    local component="$1"
    local backup_timestamp="$2"
    local backup_dir="/var/backups/observability/${backup_timestamp}"

    log_warn "Rolling back ${component} to backup from ${backup_timestamp}"

    # 1. Stop failed service
    systemctl stop "${component}" 2>/dev/null || true
    sleep 2
    pkill -9 -f "/usr/local/bin/${component}" 2>/dev/null || true

    # 2. Restore binary
    if [[ -f "${backup_dir}/bin/${component}" ]]; then
        cp "${backup_dir}/bin/${component}" "/usr/local/bin/${component}"
        chmod 755 "/usr/local/bin/${component}"
        log_info "Binary restored from backup"
    else
        log_error "Backup binary not found: ${backup_dir}/bin/${component}"
        return 1
    fi

    # 3. Restore config (if it was changed during upgrade)
    if [[ -d "${backup_dir}/config/${component}" ]]; then
        cp -r "${backup_dir}/config/${component}"/* "/etc/${component}/"
        log_info "Config restored from backup"
    fi

    # 4. Restore systemd unit (if changed)
    if [[ -f "${backup_dir}/systemd/${component}.service" ]]; then
        cp "${backup_dir}/systemd/${component}.service" "/etc/systemd/system/${component}.service"
        systemctl daemon-reload
        log_info "Systemd unit restored"
    fi

    # 5. Restart service
    systemctl start "${component}"
    sleep 3

    # 6. Verify rollback success
    if ! systemctl is-active --quiet "${component}"; then
        log_error "Rollback failed: service did not start"
        return 1
    fi

    # Health check
    local health_endpoint=$(get_health_endpoint "$component")
    if ! curl -sf "$health_endpoint" >/dev/null; then
        log_error "Rollback failed: health check failed"
        return 1
    fi

    # 7. Update version state
    update_version_state "$component" "$(get_version_from_backup "$backup_timestamp" "$component")"

    log_success "Rollback completed successfully for ${component}"
    return 0
}
```

### Manual Rollback Command

```bash
# Usage: upgrade-rollback --to=20241227_120000
#        upgrade-rollback --list
#        upgrade-rollback --to=20241227_120000 --component=prometheus

rollback_to_backup() {
    local backup_timestamp="$1"
    local specific_component="$2"  # optional

    local backup_dir="/var/backups/observability/${backup_timestamp}"
    local plan_file="${backup_dir}/upgrade-plan.json"

    # 1. Validate backup exists
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        list_available_backups
        return 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Backup plan file missing: $plan_file"
        return 1
    fi

    # 2. Load backup metadata
    local components=()
    if [[ -n "$specific_component" ]]; then
        components=("$specific_component")
    else
        # Get all components from backup
        components=($(ls "$backup_dir/bin/"))
    fi

    # 3. Display rollback plan
    echo "Rollback Plan:"
    echo "=============="
    echo "Backup: $backup_timestamp"
    echo ""
    printf "%-20s %-15s %-15s\n" "Component" "Current" "Target"
    echo "------------------------------------------------------"

    for comp in "${components[@]}"; do
        local current_ver=$(get_current_version "$comp")
        local target_ver=$(get_version_from_backup "$backup_timestamp" "$comp")
        printf "%-20s %-15s %-15s\n" "$comp" "$current_ver" "$target_ver"
    done
    echo ""

    # 4. Confirm
    if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Proceed with rollback? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rollback cancelled"
            return 0
        fi
    fi

    # 5. Execute rollback
    local failed=()
    for comp in "${components[@]}"; do
        if ! rollback_component "$comp" "$backup_timestamp"; then
            failed+=("$comp")
        fi
    done

    # 6. Report results
    if [[ ${#failed[@]} -eq 0 ]]; then
        log_success "Rollback completed successfully"
        send_notification "Rollback Success" "All components rolled back to $backup_timestamp"
    else
        log_error "Rollback failed for: ${failed[*]}"
        send_notification "Rollback Failed" "Failed components: ${failed[*]}"
        return 1
    fi
}
```

---

## 4. Testing and Validation Steps

### Component Health Tests

```bash
validate_component_health() {
    local component="$1"
    local timeout=60

    log_info "Validating ${component} health..."

    # 1. Service Status Check
    if ! systemctl is-active --quiet "${component}"; then
        log_error "Service is not active"
        return 1
    fi

    # 2. HTTP Endpoint Check
    local endpoint=$(get_health_endpoint "$component")
    local start_time=$SECONDS

    while (( SECONDS - start_time < timeout )); do
        if curl -sf "$endpoint" >/dev/null 2>&1; then
            log_success "HTTP endpoint responding"
            break
        fi
        sleep 2
    done

    if (( SECONDS - start_time >= timeout )); then
        log_error "HTTP endpoint not responding after ${timeout}s"
        return 1
    fi

    # 3. Expected Metric Check
    local expected_metric=$(get_expected_metric "$component")
    if [[ -n "$expected_metric" ]]; then
        if ! curl -sf "${endpoint}" | grep -q "^${expected_metric}"; then
            log_error "Expected metric not found: $expected_metric"
            return 1
        fi
        log_success "Expected metric present: $expected_metric"
    fi

    # 4. Log Error Scan
    local log_lines=$(journalctl -u "${component}" -n 50 --no-pager)
    local error_count=$(echo "$log_lines" | grep -ci "error\|fatal\|panic" || true)

    if (( error_count > 5 )); then
        log_warn "Found $error_count error messages in recent logs"
        echo "$log_lines" | grep -i "error\|fatal\|panic" | tail -5
    fi

    # 5. Component-Specific Tests
    case "$component" in
        prometheus)
            # Test query API
            if ! curl -sf "http://localhost:9090/api/v1/query?query=up" | grep -q '"status":"success"'; then
                log_error "Prometheus query API not working"
                return 1
            fi

            # Check targets are being scraped
            local targets_up=$(curl -sf "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets | map(select(.health=="up")) | length')
            if (( targets_up < 1 )); then
                log_error "No targets are up"
                return 1
            fi
            log_success "Prometheus: $targets_up targets up"
            ;;

        loki)
            # Test query API
            if ! curl -sf "http://localhost:3100/loki/api/v1/labels" | grep -q '"status":"success"'; then
                log_error "Loki query API not working"
                return 1
            fi
            log_success "Loki query API responding"
            ;;

        alertmanager)
            # Check can retrieve alerts
            if ! curl -sf "http://localhost:9093/api/v2/alerts" >/dev/null; then
                log_error "Alertmanager API not responding"
                return 1
            fi
            log_success "Alertmanager API responding"
            ;;

        grafana)
            # Check health endpoint
            if ! curl -sf "http://localhost:3000/api/health" | grep -q '"database":"ok"'; then
                log_error "Grafana database check failed"
                return 1
            fi
            log_success "Grafana health check passed"
            ;;
    esac

    # 6. Resource Usage Check
    local cpu_usage=$(ps -p $(systemctl show -p MainPID --value "${component}") -o %cpu= | awk '{print int($1)}')
    local mem_usage=$(ps -p $(systemctl show -p MainPID --value "${component}") -o %mem= | awk '{print int($1)}')

    log_info "Resource usage: CPU ${cpu_usage}%, MEM ${mem_usage}%"

    if (( cpu_usage > 90 )); then
        log_warn "High CPU usage detected"
    fi

    if (( mem_usage > 80 )); then
        log_warn "High memory usage detected"
    fi

    log_success "${component} validation passed"
    return 0
}
```

### Integration Tests

```bash
run_integration_tests() {
    log_info "Running integration tests..."

    # 1. Prometheus → Alertmanager
    test_prometheus_alertmanager() {
        log_info "Testing Prometheus → Alertmanager integration"

        # Check Prometheus can reach Alertmanager
        local am_status=$(curl -sf "http://localhost:9090/api/v1/alertmanagers" | jq -r '.data.activeAlertmanagers[0].url')

        if [[ -z "$am_status" ]]; then
            log_error "Prometheus not connected to Alertmanager"
            return 1
        fi
        log_success "Prometheus → Alertmanager: OK"
    }

    # 2. Promtail → Loki
    test_promtail_loki() {
        log_info "Testing Promtail → Loki integration"

        # Check recent logs in Loki
        local query='{job=~".+"}'
        local result=$(curl -sf "http://localhost:3100/loki/api/v1/query?query=${query}&limit=1")

        if ! echo "$result" | jq -e '.data.result[0]' >/dev/null; then
            log_error "No logs found in Loki"
            return 1
        fi
        log_success "Promtail → Loki: OK"
    }

    # 3. Grafana → Prometheus
    test_grafana_prometheus() {
        log_info "Testing Grafana → Prometheus datasource"

        # Use Grafana API to test datasource
        local ds_test=$(curl -sf -u "admin:${GRAFANA_ADMIN_PASS}" \
            "http://localhost:3000/api/datasources/name/Prometheus" | jq -r '.id')

        if [[ -z "$ds_test" ]] || [[ "$ds_test" == "null" ]]; then
            log_error "Grafana Prometheus datasource not configured"
            return 1
        fi

        # Test datasource health
        if ! curl -sf -u "admin:${GRAFANA_ADMIN_PASS}" \
            "http://localhost:3000/api/datasources/${ds_test}/health" | grep -q '"status":"OK"'; then
            log_error "Grafana cannot query Prometheus"
            return 1
        fi
        log_success "Grafana → Prometheus: OK"
    }

    # 4. Grafana → Loki
    test_grafana_loki() {
        log_info "Testing Grafana → Loki datasource"

        local ds_test=$(curl -sf -u "admin:${GRAFANA_ADMIN_PASS}" \
            "http://localhost:3000/api/datasources/name/Loki" | jq -r '.id')

        if [[ -z "$ds_test" ]] || [[ "$ds_test" == "null" ]]; then
            log_error "Grafana Loki datasource not configured"
            return 1
        fi
        log_success "Grafana → Loki: OK"
    }

    # Run all tests
    local tests=(
        test_prometheus_alertmanager
        test_promtail_loki
        test_grafana_prometheus
        test_grafana_loki
    )

    local failed=()
    for test in "${tests[@]}"; do
        if ! $test; then
            failed+=("$test")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_error "Integration tests failed: ${failed[*]}"
        return 1
    fi

    log_success "All integration tests passed"
    return 0
}
```

---

## 5. Service Restart Strategy (Minimize Downtime)

### Rolling Restart Strategy

```bash
# Strategy: Restart components in dependency order with health validation
# Minimize data loss and service interruption

restart_component_safely() {
    local component="$1"
    local strategy="${2:-graceful}"  # graceful|fast|reload

    log_info "Restarting ${component} (strategy: ${strategy})"

    case "$strategy" in
        graceful)
            # Graceful shutdown with SIGTERM, wait for clean exit
            systemctl stop "${component}"

            # Wait for process to exit (max 30s)
            local pid=$(systemctl show -p MainPID --value "${component}")
            local timeout=30
            local elapsed=0

            while kill -0 "$pid" 2>/dev/null && (( elapsed < timeout )); do
                sleep 1
                ((elapsed++))
            done

            if kill -0 "$pid" 2>/dev/null; then
                log_warn "Graceful shutdown timeout, forcing..."
                systemctl kill --signal=SIGKILL "${component}"
                sleep 2
            fi

            # Start service
            systemctl start "${component}"
            ;;

        fast)
            # Immediate restart
            systemctl restart "${component}"
            ;;

        reload)
            # Reload config without restart (if supported)
            case "$component" in
                prometheus)
                    # Prometheus supports reload via HTTP
                    curl -X POST http://localhost:9090/-/reload
                    ;;
                nginx)
                    systemctl reload nginx
                    ;;
                *)
                    # Fallback to graceful restart
                    restart_component_safely "$component" "graceful"
                    ;;
            esac
            ;;
    esac

    # Verify restart success
    sleep 3
    if ! validate_component_health "$component"; then
        log_error "Component failed health check after restart"
        return 1
    fi

    log_success "${component} restarted successfully"
    return 0
}

# Restart all components in correct dependency order
restart_all_components() {
    # Dependency order (bottom-up):
    # 1. Data stores: Prometheus, Loki
    # 2. Shippers: Promtail, exporters
    # 3. Alerting: Alertmanager
    # 4. UI: Grafana
    # 5. Proxy: Nginx

    local restart_order=(
        "prometheus"
        "loki"
        "promtail"
        "node_exporter"
        "nginx_exporter"
        "phpfpm_exporter"
        "fail2ban_exporter"
        "mysqld_exporter"
        "alertmanager"
        "grafana-server"
        "nginx"
    )

    local delay_between_restarts=5  # seconds

    for component in "${restart_order[@]}"; do
        if systemctl list-unit-files | grep -q "^${component}.service"; then
            if ! restart_component_safely "$component" "graceful"; then
                log_error "Failed to restart $component"
                return 1
            fi
            sleep $delay_between_restarts
        fi
    done

    # Final integration test
    if ! run_integration_tests; then
        log_error "Integration tests failed after restart"
        return 1
    fi

    log_success "All components restarted successfully"
}
```

### Zero-Downtime Strategy (Advanced)

```bash
# For production with HA setup, use blue-green deployment
# This requires HA configuration (multiple Prometheus/Loki instances)

zero_downtime_upgrade() {
    local component="$1"
    local new_version="$2"

    # Only applicable for components with HA support
    case "$component" in
        prometheus|loki|alertmanager)
            log_info "Performing zero-downtime upgrade for ${component}"

            # 1. Get list of instances (from consul/etcd/static config)
            local instances=($(get_ha_instances "$component"))

            if [[ ${#instances[@]} -lt 2 ]]; then
                log_warn "HA not configured, falling back to standard upgrade"
                return 1
            fi

            # 2. Upgrade instances one by one
            for instance in "${instances[@]}"; do
                log_info "Upgrading instance: $instance"

                # Remove from load balancer
                remove_from_lb "$component" "$instance"

                # Upgrade this instance
                upgrade_single_instance "$component" "$instance" "$new_version"

                # Verify health
                if ! validate_instance_health "$component" "$instance"; then
                    log_error "Instance $instance failed health check"
                    # Rollback this instance
                    rollback_single_instance "$component" "$instance"
                    add_to_lb "$component" "$instance"
                    return 1
                fi

                # Add back to load balancer
                add_to_lb "$component" "$instance"

                # Wait for instance to stabilize
                sleep 10
            done

            log_success "Zero-downtime upgrade completed for ${component}"
            return 0
            ;;
        *)
            log_warn "Zero-downtime not supported for ${component}"
            return 1
            ;;
    esac
}
```

---

## 6. Notification Mechanism Design

### Notification Channels

```yaml
# /etc/observability/notifications.yaml

channels:
  # Email notifications (via SMTP)
  - name: email
    enabled: true
    config:
      to:
        - ops@example.com
        - admin@example.com
      smtp_host: ${SMTP_HOST}
      smtp_port: ${SMTP_PORT}
      from: observability@example.com
    events:
      - upgrade_available
      - upgrade_started
      - upgrade_completed
      - upgrade_failed
      - rollback_required
      - rollback_completed

  # Slack notifications
  - name: slack
    enabled: true
    config:
      webhook_url: ${SECRET:slack-webhook}
      channel: "#ops-alerts"
      mention_on_failure: "@ops-team"
    events:
      - upgrade_started
      - upgrade_completed
      - upgrade_failed
      - rollback_required

  # Webhook for custom integrations
  - name: webhook
    enabled: false
    config:
      url: https://hooks.example.com/upgrades
      method: POST
      headers:
        Authorization: "Bearer ${SECRET:webhook-token}"
    events:
      - upgrade_completed
      - upgrade_failed

# Notification templates
templates:
  upgrade_available:
    subject: "[Observability] Updates Available"
    body: |
      New versions available for upgrade:

      {{range .Components}}
      - {{.Name}}: {{.CurrentVersion}} → {{.LatestVersion}}
      {{end}}

      Run 'observability-upgrade check' for details.
      Run 'observability-upgrade apply --auto' to auto-upgrade.

  upgrade_started:
    subject: "[Observability] Upgrade Started"
    body: |
      Upgrade started at {{.Timestamp}}

      Components to upgrade:
      {{range .Components}}
      - {{.Name}}: {{.OldVersion}} → {{.NewVersion}}
      {{end}}

      Expected duration: {{.EstimatedDuration}}

  upgrade_completed:
    subject: "[Observability] Upgrade Completed Successfully"
    body: |
      Upgrade completed at {{.Timestamp}}
      Duration: {{.ActualDuration}}

      Upgraded components:
      {{range .Components}}
      - {{.Name}}: {{.OldVersion}} → {{.NewVersion}} ✓
      {{end}}

      All health checks passed.

  upgrade_failed:
    subject: "[CRITICAL] Observability Upgrade Failed"
    body: |
      Upgrade FAILED at {{.Timestamp}}

      Failed component: {{.FailedComponent}}
      Error: {{.Error}}

      Automatic rollback: {{if .AutoRollback}}IN PROGRESS{{else}}DISABLED{{end}}

      Action required:
      1. Check logs: journalctl -u {{.FailedComponent}} -n 100
      2. Manual rollback: observability-upgrade rollback --to={{.BackupTimestamp}}
      3. Contact ops team if needed

  rollback_completed:
    subject: "[Observability] Rollback Completed"
    body: |
      Rollback completed at {{.Timestamp}}

      Components rolled back to {{.BackupTimestamp}}:
      {{range .Components}}
      - {{.Name}}: {{.CurrentVersion}} → {{.RolledBackVersion}}
      {{end}}

      System restored to previous state.
```

### Notification Implementation

```bash
send_notification() {
    local event="$1"
    local data_json="$2"

    local config_file="/etc/observability/notifications.yaml"

    # Parse enabled channels for this event
    local channels=($(yq eval ".channels[] | select(.enabled == true and (.events[] | select(. == \"$event\"))) | .name" "$config_file"))

    for channel in "${channels[@]}"; do
        case "$channel" in
            email)
                send_email_notification "$event" "$data_json"
                ;;
            slack)
                send_slack_notification "$event" "$data_json"
                ;;
            webhook)
                send_webhook_notification "$event" "$data_json"
                ;;
        esac
    done
}

send_email_notification() {
    local event="$1"
    local data_json="$2"

    # Render template
    local subject=$(render_template "$event" "subject" "$data_json")
    local body=$(render_template "$event" "body" "$data_json")

    # Get SMTP config
    local to_addresses=($(yq eval '.channels[] | select(.name == "email") | .config.to[]' /etc/observability/notifications.yaml))
    local smtp_host=$(yq eval '.channels[] | select(.name == "email") | .config.smtp_host' /etc/observability/notifications.yaml)
    local smtp_port=$(yq eval '.channels[] | select(.name == "email") | .config.smtp_port' /etc/observability/notifications.yaml)
    local from=$(yq eval '.channels[] | select(.name == "email") | .config.from' /etc/observability/notifications.yaml)

    # Send email
    for to in "${to_addresses[@]}"; do
        echo "$body" | mail -s "$subject" -a "From: $from" "$to"
    done
}

send_slack_notification() {
    local event="$1"
    local data_json="$2"

    local webhook_url=$(yq eval '.channels[] | select(.name == "slack") | .config.webhook_url' /etc/observability/notifications.yaml)
    local channel=$(yq eval '.channels[] | select(.name == "slack") | .config.channel' /etc/observability/notifications.yaml)

    # Render template
    local body=$(render_template "$event" "body" "$data_json")

    # Determine color based on event
    local color="good"
    case "$event" in
        *failed|*error) color="danger" ;;
        *warning) color="warning" ;;
    esac

    # Send to Slack
    curl -X POST "$webhook_url" \
        -H 'Content-Type: application/json' \
        -d "{
            \"channel\": \"$channel\",
            \"attachments\": [{
                \"color\": \"$color\",
                \"title\": \"$(render_template "$event" "subject" "$data_json")\",
                \"text\": \"$body\",
                \"footer\": \"Observability Upgrade System\",
                \"ts\": $(date +%s)
            }]
        }"
}
```

---

## 7. Version Management

### Version State File

```json
// /var/lib/observability/versions.state
{
  "last_updated": "2024-12-27T12:00:00Z",
  "components": {
    "prometheus": {
      "current_version": "2.48.1",
      "previous_version": "2.47.0",
      "installed_at": "2024-11-15T10:30:00Z",
      "upgraded_at": "2024-12-01T14:20:00Z",
      "checksum": "abc123...",
      "binary_path": "/usr/local/bin/prometheus",
      "backups": [
        {
          "version": "2.47.0",
          "timestamp": "20241201_142000",
          "path": "/var/backups/observability/20241201_142000"
        }
      ]
    },
    "loki": {
      "current_version": "2.9.3",
      "previous_version": "2.9.2",
      "installed_at": "2024-10-20T09:15:00Z",
      "upgraded_at": "2024-11-10T16:45:00Z",
      "checksum": "def456...",
      "binary_path": "/usr/local/bin/loki"
    }
  },
  "upgrade_history": [
    {
      "timestamp": "2024-12-01T14:20:00Z",
      "components_upgraded": ["prometheus"],
      "status": "success",
      "duration_seconds": 45,
      "triggered_by": "manual"
    }
  ]
}
```

### Upgrade History Database

```sql
-- /var/lib/observability/upgrade-history.db

CREATE TABLE upgrades (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL,
    component VARCHAR(50) NOT NULL,
    old_version VARCHAR(20),
    new_version VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL, -- success, failed, rolled_back
    error_message TEXT,
    duration_seconds INTEGER,
    triggered_by VARCHAR(50), -- manual, auto, scheduled
    backup_path VARCHAR(255),
    rollback_timestamp DATETIME,
    health_check_passed BOOLEAN,
    notification_sent BOOLEAN,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_component ON upgrades(component);
CREATE INDEX idx_timestamp ON upgrades(timestamp DESC);
CREATE INDEX idx_status ON upgrades(status);

-- Query examples:
-- Recent upgrades:
SELECT * FROM upgrades ORDER BY timestamp DESC LIMIT 10;

-- Failed upgrades:
SELECT * FROM upgrades WHERE status = 'failed' ORDER BY timestamp DESC;

-- Upgrade frequency per component:
SELECT component, COUNT(*) as upgrade_count,
       AVG(duration_seconds) as avg_duration
FROM upgrades
WHERE status = 'success'
GROUP BY component;
```

---

## 8. Compatibility Matrix

```yaml
# /etc/observability/compatibility-matrix.yaml

# Define compatibility rules between components
compatibility:
  prometheus:
    "2.49.x":
      alertmanager: ">=0.26.0"
      grafana: ">=9.0.0"
      node_exporter: ">=1.6.0"
    "2.48.x":
      alertmanager: ">=0.25.0"
      grafana: ">=8.5.0"
      node_exporter: ">=1.5.0"

  loki:
    "3.x.x":
      promtail: "3.x.x"  # Major version must match
      grafana: ">=10.0.0"
    "2.9.x":
      promtail: "2.9.x"
      grafana: ">=8.5.0"

  grafana:
    "10.x.x":
      prometheus: ">=2.40.0"
      loki: ">=2.8.0"
    "9.x.x":
      prometheus: ">=2.30.0"
      loki: ">=2.6.0"

# Version blacklist (known broken versions)
blacklist:
  - component: prometheus
    version: "2.48.0"
    reason: "Critical bug in TSDB compaction"
    reference: "https://github.com/prometheus/prometheus/issues/12345"

  - component: loki
    version: "2.9.0"
    reason: "Data corruption in chunk storage"
    reference: "https://github.com/grafana/loki/issues/67890"

# Auto-upgrade policies
auto_upgrade:
  # Only auto-upgrade patch versions by default
  default_policy: patch_only

  # Component-specific policies
  policies:
    prometheus:
      policy: minor  # Allow minor version auto-upgrades
      max_age_days: 30  # Upgrade if version is >30 days old

    node_exporter:
      policy: any  # Allow any version upgrades
      max_age_days: 60

    grafana:
      policy: none  # Never auto-upgrade (too risky)
      max_age_days: null

# Maintenance windows for auto-upgrades
maintenance_windows:
  - day: "saturday"
    start: "02:00"
    end: "06:00"
    timezone: "UTC"

  - day: "sunday"
    start: "02:00"
    end: "06:00"
    timezone: "UTC"
```

---

## 9. Implementation Files

The upgrade mechanism consists of the following scripts:

1. **/usr/local/bin/observability-upgrade** - Main upgrade command
2. **/usr/local/bin/observability-rollback** - Rollback command
3. **/usr/local/lib/observability/upgrade-lib.sh** - Shared functions
4. **/etc/observability/upgrade-policy.yaml** - Upgrade configuration
5. **/var/lib/observability/versions.state** - Version state tracking
6. **/etc/systemd/system/observability-upgrade.timer** - Scheduled checks
7. **/etc/systemd/system/observability-upgrade.service** - Upgrade service unit

---

## 10. Usage Examples

### Check for Updates

```bash
# Check what updates are available
observability-upgrade check

# Output:
# Updates Available:
# ==================
# Component         Current    Latest     Type     Release Date
# ---------------------------------------------------------------
# prometheus        2.48.1     2.49.0     minor    2024-12-15
# node_exporter     1.7.0      1.8.0      minor    2024-12-20
# loki              2.9.3      2.9.4      patch    2024-12-18
#
# Run 'observability-upgrade plan' to see upgrade plan
# Run 'observability-upgrade apply' to upgrade
```

### Plan Upgrade

```bash
# Generate upgrade plan
observability-upgrade plan

# Output:
# Upgrade Plan:
# =============
#
# Phase 1: Exporters (0:05 estimated)
#   - node_exporter: 1.7.0 → 1.8.0
#
# Phase 2: Data Stores (0:10 estimated)
#   - prometheus: 2.48.1 → 2.49.0
#   - loki: 2.9.3 → 2.9.4
#
# Phase 3: Alerting (0:03 estimated)
#   - (no upgrades)
#
# Phase 4: UI (0:02 estimated)
#   - (no upgrades)
#
# Total estimated duration: 20 minutes
# Total download size: 245 MB
#
# Pre-upgrade checks:
#   ✓ Sufficient disk space
#   ✓ All services healthy
#   ✓ Compatibility verified
#   ✓ Maintenance window: OK (02:00-06:00 UTC)
#
# Backups will be created at: /var/backups/observability/20241227_030000
```

### Apply Upgrade

```bash
# Interactive upgrade
observability-upgrade apply

# Auto-approve upgrade
observability-upgrade apply --yes

# Upgrade specific component
observability-upgrade apply --component=prometheus

# Dry-run (simulate upgrade)
observability-upgrade apply --dry-run

# Skip health checks (dangerous!)
observability-upgrade apply --skip-health-checks --force
```

### Rollback

```bash
# List available backups
observability-upgrade rollback --list

# Rollback to specific backup
observability-upgrade rollback --to=20241227_030000

# Rollback specific component only
observability-upgrade rollback --to=20241227_030000 --component=prometheus

# Quick rollback to previous version
observability-upgrade rollback --previous
```

### Auto-Upgrade Setup

```bash
# Enable automatic upgrades (patch versions only)
observability-upgrade auto-enable --policy=patch_only

# Enable automatic upgrades (minor versions)
observability-upgrade auto-enable --policy=minor

# Disable automatic upgrades
observability-upgrade auto-disable

# Check auto-upgrade status
observability-upgrade auto-status
```

---

## 11. Monitoring and Alerting

### Prometheus Metrics

Expose upgrade metrics for monitoring:

```prometheus
# Upgrade metrics exposed at http://localhost:9099/metrics

# Current version
observability_component_version{component="prometheus"} 2.48.1

# Last upgrade timestamp
observability_last_upgrade_timestamp{component="prometheus"} 1703674800

# Upgrade success/failure
observability_upgrade_status{component="prometheus",status="success"} 1

# Versions behind latest
observability_versions_behind{component="prometheus"} 1

# Auto-upgrade enabled
observability_auto_upgrade_enabled{component="prometheus"} 1
```

### Alerting Rules

```yaml
# /etc/prometheus/rules/upgrade-alerts.yml

groups:
  - name: upgrade_alerts
    interval: 1h
    rules:
      - alert: ComponentVersionOutdated
        expr: observability_versions_behind > 2
        for: 7d
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.component }} is 2+ versions behind"
          description: "Component {{ $labels.component }} is {{ $value }} versions behind latest"

      - alert: UpgradeFailed
        expr: observability_upgrade_status{status="failed"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Upgrade failed for {{ $labels.component }}"
          description: "Check logs and consider rollback"

      - alert: ComponentVersionVulnerable
        expr: observability_component_vulnerable == 1
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.component }} has known vulnerabilities"
          description: "Upgrade immediately: {{ $labels.cve }}"
```

---

## Summary

This upgrade mechanism provides:

- **Idempotent operations** - Safe to run multiple times
- **Safety-first approach** - Multiple validation layers
- **Production-ready** - Maintenance windows, notifications, audit trail
- **Rollback support** - Quick recovery from failures
- **Automation** - Scheduled checks and auto-upgrades
- **Visibility** - Metrics, logs, notifications

The system minimizes downtime through graceful restarts, health validation, and dependency-aware upgrade ordering. Production deployments with SLAs can use rolling upgrades or blue-green deployments for zero-downtime updates.
