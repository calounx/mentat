# Observability Stack - Logic Flow and Error Handling Audit

**Date:** 2025-12-25
**Scope:** Critical scripts and module system
**Auditor:** Security and Logic Flow Analysis

---

## Executive Summary

This audit examined the observability-stack's logic flows, error handling, edge cases, idempotency, rollback procedures, and state management. The codebase demonstrates **good overall structure** with many best practices, but several **critical logic issues** and **error handling gaps** were identified that could lead to:

- State corruption during partial failures
- Silent failures in critical operations
- Race conditions in detection logic
- Incomplete cleanup on rollback
- Unvalidated assumptions about system state

**Risk Level: MEDIUM** - No immediate security issues, but operational reliability concerns exist.

---

## 1. CRITICAL ISSUES FOUND

### 1.1 Unchecked Return Codes (HIGH PRIORITY)

#### Location: `setup-observability.sh` lines 835, 1010, 1107, 1750
**Issue:** File operations without error checking after copying alert rules and dashboards
```bash
# Line 835 - No error handling
cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/

# Line 1010 - nginx -t success assumed
nginx -t && systemctl reload nginx
```

**Impact:** If source files are missing, `cp` fails silently. Prometheus could start with no alert rules.

**Recommendation:**
```bash
if ! cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/ 2>/dev/null; then
    log_error "Failed to copy alert rules from ${BASE_DIR}/prometheus/rules/"
    return 1
fi
```

---

#### Location: `config-generator.sh` lines 159, 194
**Issue:** File copy operations without validation
```bash
# Line 159 - No error check
cp "$alerts_file" "$output_file"

# Line 194 - No error check
cp "$dashboard_file" "$output_file"
```

**Impact:** Config generation may silently fail to install module configurations.

**Recommendation:**
```bash
if [[ -f "$alerts_file" ]] && [[ -s "$alerts_file" ]]; then
    if ! cp "$alerts_file" "$output_file"; then
        log_error "Failed to copy alerts for $module: $alerts_file"
        return 1
    fi
    log_debug "Copied alerts for $module"
fi
```

---

#### Location: `setup-observability.sh` lines 1656-1657
**Issue:** Dashboard provisioning has no error checking
```bash
# Line 1656-1657 - No error validation
cp "${BASE_DIR}/grafana/provisioning/dashboards/dashboards.yaml" /etc/grafana/provisioning/dashboards/
cp "${BASE_DIR}/grafana/dashboards/"*.json /var/lib/grafana/dashboards/
```

**Impact:** Grafana may start without dashboards, users won't see monitoring data.

**Recommendation:**
```bash
if ! cp "${BASE_DIR}/grafana/provisioning/dashboards/dashboards.yaml" /etc/grafana/provisioning/dashboards/; then
    log_error "Failed to copy dashboard provisioning config"
    return 1
fi

if ! cp "${BASE_DIR}/grafana/dashboards/"*.json /var/lib/grafana/dashboards/; then
    log_warn "Failed to copy some dashboard files"
fi
```

---

### 1.2 Race Conditions and Timing Issues

#### Location: `setup-observability.sh` lines 748-752, 894-898, 967-973
**Issue:** Inconsistent service stop timing and process cleanup
```bash
# Line 748-752 - Only 1 second wait, may not be enough
systemctl stop prometheus 2>/dev/null || true
sleep 1
pkill -f "/usr/local/bin/prometheus" 2>/dev/null || true
sleep 1
```

**Impact:** Binary replacement while process is still running could cause:
- File corruption ("Text file busy" errors)
- Incomplete shutdown
- Orphaned processes

**Recommendation:** Use `safe_stop_service` from common.sh (which already exists!) consistently:
```bash
safe_stop_service "prometheus"  # Already defined in common.sh line 372
```

---

#### Location: `module-loader.sh` lines 205-209
**Issue:** Detection runs commands with `eval` and no timeout
```bash
# Line 205-209 - No timeout on arbitrary commands
while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    ((total_checks++))
    if eval "$cmd" &>/dev/null; then  # DANGEROUS: No timeout, could hang
        ((matches++))
```

**Impact:** Malformed detection commands could hang the entire detection process indefinitely.

**Recommendation:**
```bash
if timeout 5 bash -c "$cmd" &>/dev/null; then
    ((matches++))
    log_debug "Module $module_name: command '$cmd' matched"
fi
```

---

### 1.3 State Corruption Risks

#### Location: `setup-observability.sh` lines 829-833
**Issue:** Config changes tracked but not atomic
```bash
# Line 829-833
local config_changed=false
if write_config_with_check "/etc/prometheus/prometheus.yml" "$prometheus_config" "Prometheus config (prometheus.yml)"; then
    config_changed=true
fi
# ... then config_changed is NEVER USED
```

**Impact:** The variable `config_changed` is set but never used to determine if Prometheus needs reload.

**Recommendation:**
```bash
local config_changed=false
if write_config_with_check "/etc/prometheus/prometheus.yml" "$prometheus_config" "Prometheus config"; then
    config_changed=true
fi

# ... later after all config changes
if [[ "$config_changed" == "true" ]]; then
    systemctl reload prometheus
fi
```

---

#### Location: `setup-monitored-host.sh` lines 243-246
**Issue:** Module installation loop doesn't handle partial failures
```bash
# Line 243-246 - If install_module fails, loop continues
install_module "$module" $([ "$FORCE_MODE" == "true" ] && echo "--force")
echo ""
done <<< "$modules"
```

**Impact:** If one module fails, others continue installing. Final state is unclear to user.

**Recommendation:**
```bash
local failed_modules=()
while IFS= read -r module; do
    [[ -z "$module" ]] && continue

    if ! install_module "$module" $([ "$FORCE_MODE" == "true" ] && echo "--force"); then
        failed_modules+=("$module")
        log_error "Failed to install $module, continuing..."
    fi
    echo ""
done <<< "$modules"

if [[ ${#failed_modules[@]} -gt 0 ]]; then
    log_error "The following modules failed to install: ${failed_modules[*]}"
    return 1
fi
```

---

### 1.4 Missing Validation and Edge Cases

#### Location: `setup-observability.sh` lines 802-817
**Issue:** Prometheus targets parsing doesn't validate IP addresses
```bash
# Line 802-817 - No IP validation
while IFS= read -r line; do
    if [[ "$line" =~ ip:\ *\"?([0-9.]+)\"? ]]; then
        IP="${BASH_REMATCH[1]}"
        if [[ -n "$IP" && "$IP" != "MONITORED_HOST"* ]]; then
            # ... builds targets with unvalidated IP
```

**Impact:** Malformed IPs in config could create invalid Prometheus scrape targets.

**Recommendation:**
```bash
# Add IP validation function to common.sh
is_valid_ip() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            ((octet > 255)) && return 1
        done
        return 0
    fi
    return 1
}

# Then use it:
if is_valid_ip "$IP"; then
    NODE_TARGETS="${NODE_TARGETS}..."
else
    log_warn "Invalid IP address in config: $IP"
fi
```

---

#### Location: `module-loader.sh` lines 419-421
**Issue:** Module enabled check doesn't handle missing YAML structure
```bash
# Line 419-421 - Returns false on any error
enabled=$(yaml_get_deep "$config" "modules" "$module_name" "enabled")
[[ "$enabled" == "true" ]]
```

**Impact:** Can't distinguish between "module exists but disabled" vs "module section missing" vs "file corrupt".

**Recommendation:**
```bash
if [[ ! -f "$config" ]]; then
    log_debug "Host config not found: $config"
    return 1
fi

local enabled
if ! enabled=$(yaml_get_deep "$config" "modules" "$module_name" "enabled" 2>/dev/null); then
    log_debug "Module $module_name not found in $hostname config"
    return 1
fi

[[ "$enabled" == "true" ]]
```

---

#### Location: `auto-detect.sh` lines 56, 205
**Issue:** Detection confidence calculation can overflow or divide by zero
```bash
# module-loader.sh lines 235-244
if [[ $total_checks -gt 0 ]]; then
    local base_confidence=$((matches * 100 / total_checks))
    # ... but what if matches > total_checks * max_confidence / 100?
```

**Impact:** Confidence scores could exceed 100% in edge cases.

**Recommendation:**
```bash
if [[ $total_checks -gt 0 ]]; then
    local base_confidence=$((matches * 100 / total_checks))
    local max_confidence
    max_confidence=$(yaml_get_nested "$manifest" "detection" "confidence")
    max_confidence=${max_confidence:-100}

    confidence=$((base_confidence * max_confidence / 100))

    # Cap at max_confidence
    [[ $confidence -gt $max_confidence ]] && confidence=$max_confidence

    if [[ $confidence -gt 0 ]]; then
        echo "$confidence"
        return 0
    fi
fi
```

---

### 1.5 Network and Service Availability Edge Cases

#### Location: `setup-observability.sh` lines 767, 908, 1080, 1184
**Issue:** wget downloads have no retry logic or checksum validation
```bash
# Line 767 - No retries, no checksum
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
```

**Impact:** Network failures cause installation to fail. Corrupted downloads could install malicious binaries.

**Recommendation:**
```bash
# Add to common.sh
safe_download() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if wget -q -O "$output" "$url"; then
            log_success "Downloaded: $url"
            return 0
        fi
        ((retry++))
        log_warn "Download failed (attempt $retry/$max_retries): $url"
        sleep 2
    done

    log_error "Failed to download after $max_retries attempts: $url"
    return 1
}

# Then use:
safe_download "https://github.com/.../prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
    "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" || return 1
```

---

#### Location: `node_exporter/install.sh` lines 182-189
**Issue:** Metrics verification doesn't wait for service startup
```bash
# Line 182-189 - Only 2 second wait, service may not be ready
sleep 2
if curl -sf "http://localhost:$MODULE_PORT/metrics" | grep -q "node_cpu_seconds_total"; then
    log_success "Metrics endpoint verified"
```

**Impact:** False negative - service may be starting but not yet serving metrics.

**Recommendation:**
```bash
verify_metrics() {
    log_info "Verifying metrics endpoint..."

    local max_attempts=10
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:$MODULE_PORT/metrics" 2>/dev/null | grep -q "node_cpu_seconds_total"; then
            log_success "Metrics endpoint verified"
            return 0
        fi
        log_debug "Waiting for metrics (attempt $attempt/$max_attempts)..."
        sleep 1
        ((attempt++))
    done

    log_warn "Could not verify metrics endpoint after ${max_attempts}s"
    return 1
}
```

---

### 1.6 Incomplete Rollback and Cleanup

#### Location: `setup-observability.sh` lines 293-312, 314-327, etc.
**Issue:** Uninstall functions don't restore previous state, only delete
```bash
# Line 293-312 - No backup restoration
uninstall_prometheus() {
    log_info "Uninstalling Prometheus..."
    systemctl stop prometheus 2>/dev/null || true
    systemctl disable prometheus 2>/dev/null || true
    rm -f /etc/systemd/system/prometheus.service
    rm -f /usr/local/bin/prometheus /usr/local/bin/promtool
    rm -rf /etc/prometheus
    # ... just deletes, doesn't offer to restore from backup
```

**Impact:** Users can't easily recover from a failed upgrade. Backups are created but never automatically restored.

**Recommendation:**
```bash
uninstall_prometheus() {
    log_info "Uninstalling Prometheus..."

    # Offer to restore from backup if available
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A $BACKUP_DIR 2>/dev/null)" ]]; then
        local latest_backup
        latest_backup=$(ls -t "$BACKUP_DIR" | head -1)
        log_info "Backup available: $BACKUP_DIR/$latest_backup"

        if [[ "$PURGE_DATA" != "true" ]]; then
            read -p "Restore from this backup? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                restore_prometheus_backup "$BACKUP_DIR/$latest_backup"
                return 0
            fi
        fi
    fi

    # ... then proceed with deletion
}
```

---

#### Location: `setup-monitored-host.sh` lines 100-109
**Issue:** Uninstall doesn't check if modules are still needed by other services
```bash
# Line 100-109 - Blindly uninstalls all modules
for module in promtail fail2ban_exporter phpfpm_exporter mysqld_exporter nginx_exporter node_exporter; do
    local module_dir
    if module_dir=$(get_module_dir "$module" 2>/dev/null); then
        local uninstall_script="$module_dir/uninstall.sh"
        if [[ -f "$uninstall_script" ]]; then
            log_info "Uninstalling $module..."
            bash "$uninstall_script" $([ "$PURGE_DATA" == "true" ] && echo "--purge")
        fi
    fi
done
```

**Impact:** If a monitoring host is also running its own services, uninstall could break them.

**Recommendation:**
```bash
for module in promtail fail2ban_exporter phpfpm_exporter mysqld_exporter nginx_exporter node_exporter; do
    # Check if service is used by other applications
    local service_name="$module"
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        read -p "Service $service_name is running. Uninstall anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_skip "Keeping $module"
            continue
        fi
    fi

    # ... proceed with uninstall
done
```

---

### 1.7 State Management Issues

#### Location: `config-generator.sh` lines 221-232
**Issue:** Prometheus config generation doesn't preserve custom scrape configs
```bash
# Line 221-232 - Overwrites entire prometheus.yml
if promtool check config "$temp_file" >/dev/null 2>&1; then
    cat "$temp_file" > "$prometheus_config"  # OVERWRITES EVERYTHING
    log_success "Prometheus configuration generated: $prometheus_config"
```

**Impact:** If users manually added custom scrape jobs to prometheus.yml, they'll be lost on next `generate-config` run.

**Recommendation:**
```bash
# Option 1: Warn user about custom configs
if [[ -f "$prometheus_config" ]]; then
    if grep -q "# CUSTOM CONFIG" "$prometheus_config"; then
        log_warn "Custom configurations detected in $prometheus_config"
        log_warn "They will be overwritten. Backup file before proceeding."
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
fi

# Option 2: Support include files
# Add to generated prometheus.yml:
# scrape_configs:
#   # ... module-generated configs ...
#
# # Include custom configs
# scrape_config_files:
#   - "/etc/prometheus/custom/*.yml"
```

---

#### Location: `module-manager.sh` lines 131-140
**Issue:** Module enable/disable doesn't update Prometheus config automatically
```bash
# Line 131-140 - Updates host config but doesn't regenerate prometheus.yml
if grep -q "^  ${module}:" "$host_config"; then
    sed -i "s/^\(  ${module}:\)/\1\n    enabled: true/" "$host_config"
    log_success "Enabled $module for $hostname"
else
    # ... adds module
    log_success "Added and enabled $module for $hostname"
fi
# No call to generate_all_configs() !
```

**Impact:** Enabling a module in host config doesn't add it to Prometheus scrape targets until manual regeneration.

**Recommendation:**
```bash
if grep -q "^  ${module}:" "$host_config"; then
    sed -i "s/^\(  ${module}:\)/\1\n    enabled: true/" "$host_config"
    log_success "Enabled $module for $hostname"
else
    # ... adds module
    log_success "Added and enabled $module for $hostname"
fi

# Automatically regenerate configs
log_info "Regenerating Prometheus configuration..."
generate_all_configs
log_success "Configuration updated. Reload Prometheus to apply changes:"
echo "  systemctl reload prometheus"
```

---

## 2. MEDIUM PRIORITY ISSUES

### 2.1 Error Handling Gaps

#### Location: `setup-observability.sh` lines 1759
**Issue:** SSL certificate failure only warns, doesn't fail
```bash
# Line 1759-1762
if ! certbot certonly $certbot_args; then
    log_warn "Failed to obtain SSL certificate. Continuing without HTTPS..."
    return  # Returns success even though cert failed!
fi
```

**Impact:** Script continues with HTTP-only nginx config, users may not notice.

**Recommendation:**
```bash
if ! certbot certonly $certbot_args; then
    log_error "Failed to obtain SSL certificate"
    log_warn "Services will be accessible via HTTP only (insecure!)"
    log_warn "Fix DNS and re-run: $0 --force"

    # Ask if user wants to continue without SSL
    read -p "Continue with HTTP-only setup? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
fi
```

---

#### Location: `common.sh` lines 335-341
**Issue:** `check_port` function has no error handling for timeout command
```bash
# Line 340
timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
```

**Impact:** If timeout command doesn't exist, function fails silently.

**Recommendation:**
```bash
check_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-2}"

    if command -v timeout &>/dev/null; then
        timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
    else
        # Fallback without timeout
        bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null &
        local pid=$!
        sleep "$timeout"
        if ps -p $pid > /dev/null 2>&1; then
            kill $pid 2>/dev/null
            return 1
        fi
        wait $pid 2>/dev/null
    fi
}
```

---

### 2.2 Idempotency Issues

#### Location: `module-manager.sh` lines 131-140
**Issue:** Enable command can create duplicate entries
```bash
# Line 131-140
if grep -q "^  ${module}:" "$host_config"; then
    sed -i "s/^\(  ${module}:\)/\1\n    enabled: true/" "$host_config"
    # This adds a NEW line "enabled: true" every time!
```

**Impact:** Running enable multiple times creates:
```yaml
  node_exporter:
    enabled: true
    enabled: true
    enabled: true
```

**Recommendation:**
```bash
if grep -q "^  ${module}:" "$host_config"; then
    # Check if enabled already set
    if grep -A1 "^  ${module}:" "$host_config" | grep -q "enabled:"; then
        # Update existing
        sed -i "/^  ${module}:/,/^  [a-z]/ s/enabled: false/enabled: true/" "$host_config"
    else
        # Add new enabled line
        sed -i "s/^\(  ${module}:\)/\1\n    enabled: true/" "$host_config"
    fi
    log_success "Enabled $module for $hostname"
fi
```

---

### 2.3 Silent Failures

#### Location: `promtail/install.sh` lines 78-81, 221
**Issue:** Promtail can install but not start, script succeeds anyway
```bash
# Line 78-81 - Config creation can fail silently
create_config() {
    if [[ -z "$LOKI_URL" ]]; then
        log_warn "LOKI_URL not provided, skipping config creation"
        return 1  # But main() doesn't check this!
    fi
```

Then at line 221:
```bash
create_config || true  # Ignores failure!
```

**Impact:** Promtail installs but never starts, logs not shipped.

**Recommendation:**
```bash
if ! create_config; then
    log_warn "Promtail installed but not configured"
    log_warn "To configure later, set LOKI_URL, LOKI_USER, LOKI_PASS and re-run"
    log_warn "Example:"
    log_warn "  export LOKI_URL=https://observability.example.com"
    log_warn "  export LOKI_USER=loki"
    log_warn "  export LOKI_PASS=secret"
    log_warn "  $0 --force"
    return 1  # Fail the installation
fi
```

---

## 3. LOW PRIORITY / IMPROVEMENTS

### 3.1 Security Concerns

#### Location: `module-loader.sh` line 205
**Issue:** `eval` of untrusted detection commands
```bash
if eval "$cmd" &>/dev/null; then
```

**Recommendation:** While this is from module manifests you control, it's still risky. Consider whitelisting allowed commands or using safer parsing.

---

### 3.2 Code Quality

#### Location: Multiple files
**Issue:** Inconsistent error checking patterns

Some places use:
```bash
if ! command; then
    log_error "..."
    return 1
fi
```

Others use:
```bash
command || log_warn "..."
```

**Recommendation:** Standardize on explicit error handling for readability.

---

## 4. POSITIVE FINDINGS

The following aspects are well-implemented:

1. **Logging System:** Consistent use of log_info, log_error, log_success throughout
2. **Idempotency:** Version checks prevent unnecessary reinstalls (lines 542-563 in setup-observability.sh)
3. **Backup System:** Automatic backups before changes (lines 218-278 in setup-observability.sh)
4. **Configuration Diff:** Shows changes before overwriting (lines 246-295 in common.sh)
5. **Service Management:** Proper systemd service creation and management
6. **Module System:** Clean separation of concerns with module manifests
7. **User Safety:** Force mode flag prevents accidental overwrites
8. **SSL Handling:** Proper Let's Encrypt integration with renewal

---

## 5. PRIORITY RECOMMENDATIONS

### Immediate Actions (Fix in Next Release)

1. **Add error handling to all file operations** (cp, wget, sed, etc.)
2. **Implement safe_download() with retries** for all network operations
3. **Fix module enable/disable to prevent duplicate entries**
4. **Add service availability checks before installation**
5. **Implement proper timeout on detection eval commands**

### Short Term (Within 2 Weeks)

1. **Add restore-from-backup functionality to uninstall**
2. **Implement IP address validation** in config parsing
3. **Add confidence score capping** in detection
4. **Create comprehensive test suite** for edge cases
5. **Add rollback-on-failure** to module installation loops

### Long Term (Future Enhancement)

1. **State tracking database** (SQLite) to track what's installed where
2. **Dry-run mode** for all installation scripts
3. **Health check API** that can be queried by monitoring
4. **Automated testing framework** with mock services
5. **Configuration validation** before applying (promtool-like for all configs)

---

## 6. TESTING RECOMMENDATIONS

Create test scenarios for:

1. **Network failures during installation**
   - wget fails mid-download
   - GitHub releases unavailable

2. **Partial installation recovery**
   - Service fails to start after binary install
   - Config file corruption mid-write

3. **Concurrent execution**
   - Two scripts run simultaneously
   - Module install during config generation

4. **Edge case hosts**
   - No nginx installed (nginx_exporter should skip)
   - No MySQL installed (mysqld_exporter should skip)
   - Firewall already configured

5. **Configuration errors**
   - Invalid YAML in global.yaml
   - Missing required fields
   - Malformed IP addresses

---

## 7. CONCLUSION

The observability stack shows **good engineering practices** with strong idempotency, logging, and modular design. However, **error handling and edge case management** need improvement to prevent operational issues in production.

**Priority Focus:**
1. Add error checking to file operations (HIGH)
2. Implement network retry logic (HIGH)
3. Fix state corruption risks in module enable/disable (HIGH)
4. Add rollback/restore capabilities (MEDIUM)
5. Improve service availability validation (MEDIUM)

**Overall Assessment:** The codebase is production-ready with the understanding that operators must manually monitor for failures. Implementing the HIGH priority recommendations will significantly improve reliability.
