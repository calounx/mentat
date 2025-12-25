# Observability Stack - Required Fixes Summary

This document provides **specific code locations and fixes** for the critical issues found in the audit.

---

## CRITICAL FIXES (Implement Immediately)

### Fix 1: Add Error Handling to File Copy Operations

**Files to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/setup-observability.sh`
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/config-generator.sh`

**Changes:**

#### setup-observability.sh Line 835
```bash
# BEFORE (line 835):
cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/

# AFTER:
if ! cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/ 2>/dev/null; then
    log_warn "Failed to copy some alert rules (might be expected if no rules exist)"
fi
```

#### setup-observability.sh Lines 1656-1657
```bash
# BEFORE (lines 1656-1657):
cp "${BASE_DIR}/grafana/provisioning/dashboards/dashboards.yaml" /etc/grafana/provisioning/dashboards/
cp "${BASE_DIR}/grafana/dashboards/"*.json /var/lib/grafana/dashboards/

# AFTER:
if ! cp "${BASE_DIR}/grafana/provisioning/dashboards/dashboards.yaml" /etc/grafana/provisioning/dashboards/; then
    log_error "Failed to copy dashboard provisioning config"
    return 1
fi

if ! cp "${BASE_DIR}/grafana/dashboards/"*.json /var/lib/grafana/dashboards/ 2>/dev/null; then
    log_warn "Failed to copy dashboard files (might be expected if no dashboards exist)"
fi
```

#### config-generator.sh Lines 158-161
```bash
# BEFORE (lines 158-161):
if [[ -f "$alerts_file" ]] && [[ -s "$alerts_file" ]]; then
    cp "$alerts_file" "$output_file"
    log_debug "Copied alerts for $module"
fi

# AFTER:
if [[ -f "$alerts_file" ]] && [[ -s "$alerts_file" ]]; then
    if ! cp "$alerts_file" "$output_file"; then
        log_error "Failed to copy alerts for $module from $alerts_file"
        return 1
    fi
    log_debug "Copied alerts for $module"
fi
```

#### config-generator.sh Lines 191-195
```bash
# BEFORE (lines 191-195):
if [[ -f "$dashboard_file" ]] && [[ -s "$dashboard_file" ]]; then
    cp "$dashboard_file" "$output_file"
    log_debug "Copied dashboard for $module"
fi

# AFTER:
if [[ -f "$dashboard_file" ]] && [[ -s "$dashboard_file" ]]; then
    if ! cp "$dashboard_file" "$output_file"; then
        log_error "Failed to copy dashboard for $module from $dashboard_file"
        return 1
    fi
    log_debug "Copied dashboard for $module"
fi
```

---

### Fix 2: Implement Safe Download with Retry Logic

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/common.sh`

**Add this function after line 364:**

```bash
#===============================================================================
# DOWNLOAD UTILITIES
#===============================================================================

# Safe download with retry logic
# Usage: safe_download "url" "output_file" [max_retries]
safe_download() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-3}"
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if wget -q --show-progress -O "$output" "$url"; then
            if [[ -f "$output" ]] && [[ -s "$output" ]]; then
                log_success "Downloaded: $(basename $output)"
                return 0
            else
                log_warn "Download produced empty file: $url"
            fi
        fi

        ((retry++))
        if [[ $retry -lt $max_retries ]]; then
            log_warn "Download failed (attempt $retry/$max_retries), retrying in 2s..."
            rm -f "$output"
            sleep 2
        fi
    done

    log_error "Failed to download after $max_retries attempts: $url"
    return 1
}
```

**Then update all wget calls:**

#### setup-observability.sh Line 767
```bash
# BEFORE:
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

# AFTER:
safe_download \
    "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
    "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" || return 1
```

**Repeat for:**
- Line 908 (node_exporter download)
- Line 983 (nginx_exporter download)
- Line 1080 (phpfpm_exporter download)
- Line 1184 (promtail download)
- Line 1328 (alertmanager download)
- Line 1490 (loki download)

---

### Fix 3: Fix Detection Command Timeout

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/module-loader.sh`

**Line 205-209:**
```bash
# BEFORE:
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    ((total_checks++))
    if eval "$cmd" &>/dev/null; then
        ((matches++))
        log_debug "Module $module_name: command '$cmd' matched"
    fi
done < <(yaml_get_array "$manifest" "detection.commands" 2>/dev/null)

# AFTER:
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    ((total_checks++))

    # Run with timeout to prevent hanging
    if timeout 5 bash -c "$cmd" &>/dev/null; then
        ((matches++))
        log_debug "Module $module_name: command '$cmd' matched"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "Module $module_name: command '$cmd' timed out"
        fi
    fi
done < <(yaml_get_array "$manifest" "detection.commands" 2>/dev/null)
```

---

### Fix 4: Fix Module Enable/Disable Idempotency

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/module-manager.sh`

**Lines 131-140:**
```bash
# BEFORE:
if grep -q "^  ${module}:" "$host_config"; then
    sed -i "s/^\(  ${module}:\)/\1\n    enabled: true/" "$host_config"
    log_success "Enabled $module for $hostname"
else
    log_warn "Module $module not found in $hostname config. Adding..."
    echo "" >> "$host_config"
    echo "  ${module}:" >> "$host_config"
    echo "    enabled: true" >> "$host_config"
    log_success "Added and enabled $module for $hostname"
fi

# AFTER:
if grep -q "^  ${module}:" "$host_config"; then
    # Check if enabled line already exists
    if grep -A3 "^  ${module}:" "$host_config" | grep -q "^\s*enabled:"; then
        # Update existing enabled value
        sed -i "/^  ${module}:/,/^  [a-z_-]*:/ s/enabled: false/enabled: true/" "$host_config"
        log_success "Enabled $module for $hostname"
    else
        # Add enabled line
        sed -i "s/^\(  ${module}:\)/\1\n    enabled: true/" "$host_config"
        log_success "Enabled $module for $hostname (added enabled flag)"
    fi
else
    log_warn "Module $module not found in $hostname config. Adding..."
    echo "" >> "$host_config"
    echo "  ${module}:" >> "$host_config"
    echo "    enabled: true" >> "$host_config"
    log_success "Added and enabled $module for $hostname"
fi

# Regenerate configs
log_info "Regenerating Prometheus configuration..."
"$_MM_SCRIPT_DIR/lib/config-generator.sh" generate_all_configs 2>/dev/null || true
log_success "Run 'systemctl reload prometheus' to apply changes"
```

---

### Fix 5: Handle Partial Module Installation Failures

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/setup-monitored-host.sh`

**Lines 209-247:**
```bash
# BEFORE:
while IFS= read -r module; do
    [[ -z "$module" ]] && continue

    local display_name
    display_name=$(module_display_name "$module")
    log_info "Installing ${display_name:-$module}..."

    # Set environment variables for install script
    export MODULE_NAME="$module"
    export MODULE_VERSION
    MODULE_VERSION=$(module_version "$module")
    export MODULE_PORT
    MODULE_PORT=$(module_port "$module")
    export FORCE_MODE
    export OBSERVABILITY_IP

    # Special handling for promtail
    if [[ "$module" == "promtail" ]]; then
        export LOKI_URL
        export LOKI_USER
        export LOKI_PASS

        # Try to get from host config if not provided
        if [[ -z "$LOKI_URL" ]]; then
            LOKI_URL=$(get_host_module_config "$hostname" "promtail" "loki_url" 2>/dev/null || echo "")
        fi
        if [[ -z "$LOKI_USER" ]]; then
            LOKI_USER=$(get_host_module_config "$hostname" "promtail" "loki_user" 2>/dev/null || echo "")
        fi
        if [[ -z "$LOKI_PASS" ]]; then
            LOKI_PASS=$(get_host_module_config "$hostname" "promtail" "loki_password" 2>/dev/null || echo "")
        fi
    fi

    install_module "$module" $([ "$FORCE_MODE" == "true" ] && echo "--force")
    echo ""
done <<< "$modules"

# AFTER:
local failed_modules=()
local installed_modules=()

while IFS= read -r module; do
    [[ -z "$module" ]] && continue

    local display_name
    display_name=$(module_display_name "$module")
    log_info "Installing ${display_name:-$module}..."

    # Set environment variables for install script
    export MODULE_NAME="$module"
    export MODULE_VERSION
    MODULE_VERSION=$(module_version "$module")
    export MODULE_PORT
    MODULE_PORT=$(module_port "$module")
    export FORCE_MODE
    export OBSERVABILITY_IP

    # Special handling for promtail
    if [[ "$module" == "promtail" ]]; then
        export LOKI_URL
        export LOKI_USER
        export LOKI_PASS

        # Try to get from host config if not provided
        if [[ -z "$LOKI_URL" ]]; then
            LOKI_URL=$(get_host_module_config "$hostname" "promtail" "loki_url" 2>/dev/null || echo "")
        fi
        if [[ -z "$LOKI_USER" ]]; then
            LOKI_USER=$(get_host_module_config "$hostname" "promtail" "loki_user" 2>/dev/null || echo "")
        fi
        if [[ -z "$LOKI_PASS" ]]; then
            LOKI_PASS=$(get_host_module_config "$hostname" "promtail" "loki_password" 2>/dev/null || echo "")
        fi
    fi

    if install_module "$module" $([ "$FORCE_MODE" == "true" ] && echo "--force"); then
        installed_modules+=("$module")
        log_success "${display_name:-$module} installed successfully"
    else
        failed_modules+=("$module")
        log_error "Failed to install ${display_name:-$module}"
    fi
    echo ""
done <<< "$modules"

# Report results
if [[ ${#failed_modules[@]} -gt 0 ]]; then
    log_error "Installation completed with errors"
    echo ""
    echo "Failed modules:"
    for module in "${failed_modules[@]}"; do
        echo "  - $module"
    done
    echo ""

    if [[ ${#installed_modules[@]} -gt 0 ]]; then
        echo "Successfully installed modules:"
        for module in "${installed_modules[@]}"; do
            echo "  - $module"
        done
        echo ""
    fi

    return 1
fi
```

---

### Fix 6: Improve Service Verification with Retries

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/modules/_core/node_exporter/install.sh`

**Lines 182-189:**
```bash
# BEFORE:
verify_metrics() {
    log_info "Verifying metrics endpoint..."

    if curl -sf "http://localhost:$MODULE_PORT/metrics" | grep -q "node_cpu_seconds_total"; then
        log_success "Metrics endpoint verified"
    else
        log_warn "Could not verify metrics endpoint"
    fi
}

# AFTER:
verify_metrics() {
    log_info "Verifying metrics endpoint..."

    local max_attempts=10
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:$MODULE_PORT/metrics" 2>/dev/null | grep -q "node_cpu_seconds_total"; then
            log_success "Metrics endpoint verified"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_debug "Waiting for metrics endpoint (attempt $attempt/$max_attempts)..."
            sleep 1
        fi
        ((attempt++))
    done

    log_error "Metrics endpoint not responding after ${max_attempts}s"
    log_error "Service may have failed to start properly"
    systemctl status "$SERVICE_NAME" --no-pager --lines=10
    return 1
}
```

**Apply same pattern to:**
- `promtail/install.sh`
- `nginx_exporter/install.sh`
- `mysqld_exporter/install.sh`
- `phpfpm_exporter/install.sh`
- `fail2ban_exporter/install.sh`

---

### Fix 7: Add IP Validation

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/common.sh`

**Add after line 364:**

```bash
#===============================================================================
# VALIDATION UTILITIES
#===============================================================================

# Validate IPv4 address
# Usage: is_valid_ip "192.168.1.1"
is_valid_ip() {
    local ip="$1"

    # Check format
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Check octets are in range 0-255
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if ((octet < 0 || octet > 255)); then
            return 1
        fi
    done

    return 0
}
```

**Then in setup-observability.sh line 803:**
```bash
# BEFORE (line 803-815):
while IFS= read -r line; do
    if [[ "$line" =~ ip:\ *\"?([0-9.]+)\"? ]]; then
        IP="${BASH_REMATCH[1]}"
        if [[ -n "$IP" && "$IP" != "MONITORED_HOST"* ]]; then
            # Get the name from previous lines
            NAME=$(grep -B5 "ip: .*$IP" "$CONFIG_FILE" | grep "name:" | head -1 | sed 's/.*name: *//' | tr -d '"')
            if [[ -n "$NAME" ]]; then
                NODE_TARGETS="${NODE_TARGETS}      - targets: ['${IP}:9100']\n        labels:\n          instance: '${NAME}'\n"

# AFTER:
while IFS= read -r line; do
    if [[ "$line" =~ ip:\ *\"?([0-9.]+)\"? ]]; then
        IP="${BASH_REMATCH[1]}"

        # Validate IP address
        if ! is_valid_ip "$IP"; then
            log_warn "Invalid IP address in config: $IP (skipping)"
            continue
        fi

        if [[ -n "$IP" && "$IP" != "MONITORED_HOST"* ]]; then
            # Get the name from previous lines
            NAME=$(grep -B5 "ip: .*$IP" "$CONFIG_FILE" | grep "name:" | head -1 | sed 's/.*name: *//' | tr -d '"')
            if [[ -n "$NAME" ]]; then
                NODE_TARGETS="${NODE_TARGETS}      - targets: ['${IP}:9100']\n        labels:\n          instance: '${NAME}'\n"
```

---

### Fix 8: Cap Confidence Scores in Detection

**File to modify:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/module-loader.sh`

**Lines 234-250:**
```bash
# BEFORE:
if [[ $total_checks -gt 0 ]]; then
    # Base confidence from matches
    local base_confidence=$((matches * 100 / total_checks))

    # Get the module's max confidence from manifest
    local max_confidence
    max_confidence=$(yaml_get_nested "$manifest" "detection" "confidence")
    max_confidence=${max_confidence:-100}

    # Scale to max confidence
    confidence=$((base_confidence * max_confidence / 100))

    if [[ $confidence -gt 0 ]]; then
        echo "$confidence"
        return 0
    fi
fi

# AFTER:
if [[ $total_checks -gt 0 ]]; then
    # Base confidence from matches (cap at 100)
    local base_confidence=$((matches * 100 / total_checks))
    if [[ $base_confidence -gt 100 ]]; then
        base_confidence=100
    fi

    # Get the module's max confidence from manifest
    local max_confidence
    max_confidence=$(yaml_get_nested "$manifest" "detection" "confidence")
    max_confidence=${max_confidence:-100}

    # Validate max_confidence is reasonable
    if [[ ! "$max_confidence" =~ ^[0-9]+$ ]] || [[ $max_confidence -lt 0 ]] || [[ $max_confidence -gt 100 ]]; then
        log_warn "Module $module_name has invalid max_confidence: $max_confidence, using 100"
        max_confidence=100
    fi

    # Scale to max confidence
    confidence=$((base_confidence * max_confidence / 100))

    # Ensure we don't exceed max_confidence
    if [[ $confidence -gt $max_confidence ]]; then
        confidence=$max_confidence
    fi

    if [[ $confidence -gt 0 ]]; then
        echo "$confidence"
        return 0
    fi
fi
```

---

## TESTING CHECKLIST

After applying fixes, test:

- [ ] Download failure recovery (disconnect network during install)
- [ ] File copy error handling (make directory read-only)
- [ ] Module enable/disable idempotency (run enable twice)
- [ ] Partial installation failure (kill one module install mid-way)
- [ ] Detection timeout (create hung detection command)
- [ ] IP validation (add malformed IP to config)
- [ ] Confidence score edge cases (create manifest with weird values)
- [ ] Service startup verification (slow-starting service)
- [ ] Config regeneration (enable/disable modules, verify prometheus.yml)

---

## IMPLEMENTATION ORDER

1. **Day 1:** Add safe_download() and fix all wget calls
2. **Day 2:** Add error handling to all file copy operations
3. **Day 3:** Fix module enable/disable idempotency
4. **Day 4:** Add IP validation and detection timeout
5. **Day 5:** Improve service verification and partial failure handling
6. **Day 6:** Testing and validation
7. **Day 7:** Documentation updates

---

## FILES MODIFIED SUMMARY

1. `/home/calounx/repositories/mentat/observability-stack/scripts/lib/common.sh`
   - Add safe_download()
   - Add is_valid_ip()

2. `/home/calounx/repositories/mentat/observability-stack/scripts/setup-observability.sh`
   - Fix file copy error handling (6 locations)
   - Add IP validation
   - Use safe_download() (6 locations)

3. `/home/calounx/repositories/mentat/observability-stack/scripts/lib/config-generator.sh`
   - Fix file copy error handling (2 locations)

4. `/home/calounx/repositories/mentat/observability-stack/scripts/module-manager.sh`
   - Fix enable/disable idempotency
   - Add config regeneration trigger

5. `/home/calounx/repositories/mentat/observability-stack/scripts/setup-monitored-host.sh`
   - Add failure tracking and reporting

6. `/home/calounx/repositories/mentat/observability-stack/scripts/lib/module-loader.sh`
   - Add detection timeout
   - Cap confidence scores

7. All module install.sh scripts (6 files)
   - Improve service verification

---

**Estimated effort:** 2-3 days for implementation + 1-2 days for testing = **3-5 days total**
