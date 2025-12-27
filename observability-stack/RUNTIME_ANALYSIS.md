# Runtime Error Detection and Edge Case Analysis

**Date:** 2025-12-27
**Scope:** All scripts in observability-stack
**Focus:** Runtime behavior, error conditions, edge cases, and fail-safe mechanisms

---

## Executive Summary

**Overall Reliability Score: 78/100**

**Production Readiness: CONDITIONAL SAFE** ⚠️

The observability stack demonstrates **good architectural fundamentals** with comprehensive error handling libraries, transaction support, and security features. However, **critical runtime gaps** exist in edge case handling, resource exhaustion scenarios, and concurrent execution protection that could lead to production failures.

### Key Findings

✅ **Strengths:**
- Comprehensive error handling framework (`errors.sh`)
- Transaction/rollback support (`transaction.sh`)
- Good retry logic with circuit breaker patterns (`retry.sh`)
- Input validation and sanitization
- Secrets management infrastructure
- Lock-based concurrency protection (`lock-utils.sh`)

❌ **Critical Issues:**
- Inadequate disk space checking before large operations
- Missing resource exhaustion detection (memory, file descriptors)
- Incomplete cleanup on partial failures in some scripts
- Race conditions in concurrent module installations
- Network timeout handling inconsistencies
- Missing atomic operation guarantees in critical paths

---

## 1. Error Handling Completeness

### Score: 75/100

#### ✅ Strengths

1. **Comprehensive Error Library** (`errors.sh`)
   - Error code definitions with descriptions
   - Stack trace capture
   - Error aggregation for batch operations
   - Recovery hooks system
   - Structured error context tracking

2. **Consistent Error Reporting**
   - All major scripts use `log_error`, `log_fatal`
   - Exit codes properly defined and used
   - Error messages are descriptive and actionable

3. **Command Error Checking**
   ```bash
   # Good pattern seen throughout:
   if ! wget ... "$url" -O "$output"; then
       log_error "Failed to download $description from $url"
       return 1
   fi
   ```

#### ❌ Weaknesses

1. **Silent Failures in Background Operations**
   ```bash
   # In common.sh line 58
   gzip "${OBSERVABILITY_LOG_FILE}.${timestamp}" 2>/dev/null || true
   # ISSUE: Compression failure is silently ignored
   ```

2. **Incomplete Error Propagation**
   ```bash
   # In setup-observability.sh line 922-923
   if ! cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/ 2>/dev/null; then
       log_error "Failed to copy Prometheus alert rules..."
       return 1  # BUT: Already failed, should exit immediately
   fi
   ```

3. **Missing Error Context in Nested Functions**
   - Many utility functions don't preserve original error context
   - Error messages don't always indicate which operation failed in complex workflows

4. **Inconsistent Error Handling in Pipes**
   ```bash
   # Some scripts use pipefail, others don't
   set -euo pipefail  # Good - in most scripts
   # But some utility functions don't inherit this
   ```

#### 🔧 Recommendations

1. **Add error context preservation:**
   ```bash
   operation_with_context() {
       error_push_context "Installing $module"
       if ! install_binary "$module"; then
           error_report "Binary installation failed: $module" "$E_INSTALL_FAILED"
           return 1
       fi
       error_pop_context
   }
   ```

2. **Never silently ignore critical operations:**
   ```bash
   # Replace this:
   gzip "$file" 2>/dev/null || true

   # With this:
   if ! gzip "$file" 2>/dev/null; then
       log_warn "Failed to compress $file (non-fatal)"
   fi
   ```

3. **Add fail-fast validation at script start:**
   ```bash
   preflight_checks() {
       local errors=()
       [[ -w "/var/lib" ]] || errors+=("Cannot write to /var/lib")
       command -v wget >/dev/null || errors+=("wget not installed")

       if [[ ${#errors[@]} -gt 0 ]]; then
           log_error "Preflight checks failed:"
           printf '  - %s\n' "${errors[@]}"
           exit 1
       fi
   }
   ```

---

## 2. Edge Cases Analysis

### Score: 68/100

### 2.1 Empty File/Directory Handling

#### ❌ Issues Found

1. **Empty Directory Iteration**
   ```bash
   # In module-loader.sh line 29-35
   for module_dir in "$dir"/*/; do
       if [[ -f "${module_dir}module.yaml" ]]; then
           modules+=("$(basename "$module_dir")")
       fi
   done
   # ISSUE: If $dir doesn't exist, glob fails silently
   # ISSUE: If no directories exist, loop still executes once with literal "*/"
   ```

2. **Empty Config File**
   ```bash
   # In setup-observability.sh line 889-904
   while IFS= read -r line; do
       if [[ "$line" =~ ip:\ *\"?([0-9.]+)\"? ]]; then
           IP="${BASH_REMATCH[1]}"
           # ... processing ...
       fi
   done < "$CONFIG_FILE"
   # ISSUE: Empty config file causes no warnings, silent failure
   ```

3. **Empty Array Handling**
   ```bash
   # In common.sh line 817-822
   for file in "${_CLEANUP_TEMP_FILES[@]}"; do
       if [[ -f "$file" ]]; then
           rm -f "$file" 2>/dev/null || true
       fi
   done
   # ISSUE: If array is unset (not just empty), this fails in bash < 4.4
   # BETTER: for file in "${_CLEANUP_TEMP_FILES[@]+"${_CLEANUP_TEMP_FILES[@]}"}"; do
   ```

#### 🔧 Fixes Required

```bash
# Safe directory iteration
for module_dir in "$dir"/*/; do
    # Skip if glob didn't match (literal */returned)
    [[ -d "$module_dir" ]] || continue
    [[ -f "${module_dir}module.yaml" ]] || continue
    modules+=("$(basename "$module_dir")")
done

# Config file validation
if [[ ! -s "$CONFIG_FILE" ]]; then
    log_error "Config file is empty or missing: $CONFIG_FILE"
    exit 1
fi

# Safe array iteration
for file in "${_CLEANUP_TEMP_FILES[@]+"${_CLEANUP_TEMP_FILES[@]}"}"; do
    [[ -f "$file" ]] && rm -f "$file" 2>/dev/null || true
done
```

### 2.2 Missing Configuration Files

#### ✅ Good Handling

```bash
# In setup-observability.sh line 665-668
check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
    fi
}
```

#### ❌ Incomplete Handling

1. **Missing Module Manifests**
   ```bash
   # In module-loader.sh line 122
   manifest=$(get_module_manifest "$module_name") || return 1
   yaml_get "$manifest" "$key"
   # ISSUE: yaml_get doesn't validate file exists, reads from empty string
   ```

2. **Missing Template Files**
   ```bash
   # In setup-observability.sh line 913
   prometheus_config=$(sed ... "${BASE_DIR}/prometheus/prometheus.yml.template")
   # ISSUE: If template doesn't exist, sed fails silently with empty output
   ```

#### 🔧 Fix

```bash
# Always validate file existence before processing
if [[ ! -f "$template_file" ]]; then
    log_error "Required template not found: $template_file"
    return 1
fi
config=$(sed ... "$template_file")
```

### 2.3 Network Unavailable Scenarios

#### ✅ Good: Retry Logic

```bash
# In download-utils.sh and retry.sh
safe_download() {
    local timeout="${3:-30}"
    local retries="${4:-3}"
    wget --timeout="$timeout" --tries="$retries" ...
}
```

#### ❌ Issues

1. **No Network Connectivity Check**
   ```bash
   # No preflight network connectivity test before downloads
   # Should check if DNS resolution works before attempting downloads
   ```

2. **Hardcoded Timeout Values**
   ```bash
   # In common.sh line 710
   timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
   # ISSUE: bash may not have /dev/tcp compiled in (Debian default does, but not guaranteed)
   ```

3. **Missing Offline Mode**
   - No way to use locally cached binaries when network is unavailable
   - No checksum verification of cached files

#### 🔧 Recommendations

```bash
# Add network preflight check
check_network() {
    local test_urls=(
        "https://github.com"
        "https://apt.grafana.com"
    )

    for url in "${test_urls[@]}"; do
        if curl -s --head --connect-timeout 5 "$url" >/dev/null 2>&1; then
            return 0
        fi
    done

    log_error "Network connectivity check failed"
    log_error "Tested URLs: ${test_urls[*]}"
    return 1
}

# Add offline mode support
if [[ -f "$CACHE_DIR/$binary" ]] && verify_checksum "$CACHE_DIR/$binary"; then
    log_info "Using cached binary: $binary"
    cp "$CACHE_DIR/$binary" "$target"
else
    check_network || return 1
    download_binary "$url" "$target"
    cp "$target" "$CACHE_DIR/$binary"  # Cache for future
fi
```

### 2.4 Disk Full Scenarios

#### ❌ Critical Issue: No Disk Space Checks

**None of the installation scripts check available disk space before:**
- Downloading large binaries (Prometheus, Grafana, Loki)
- Creating database directories
- Writing log files
- Extracting archives

**Potential Failure Scenario:**
```bash
# User runs setup-observability.sh with 100MB free space
# Downloads 500MB of binaries -> fills disk
# System becomes unresponsive
# Partial installation state, difficult to recover
```

#### 🔧 Critical Fix Required

```bash
# Add to all installation scripts
check_disk_space() {
    local required_mb="${1:-1000}"  # Default 1GB
    local target_dir="${2:-/var/lib}"

    # Get available space in MB
    local available
    available=$(df -BM "$target_dir" | awk 'NR==2 {print $4}' | tr -d 'M')

    if [[ $available -lt $required_mb ]]; then
        log_error "Insufficient disk space on $target_dir"
        log_error "Required: ${required_mb}MB, Available: ${available}MB"
        log_error "Free up space and try again"
        return 1
    fi

    log_info "Disk space check passed: ${available}MB available on $target_dir"
    return 0
}

# Call before major operations
check_disk_space 2000 "/var/lib" || exit 1
```

### 2.5 Permission Denied Scenarios

#### ✅ Good: Root Check

```bash
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This script must be run as root" "$E_PERMISSION_DENIED"
    fi
}
```

#### ❌ Incomplete

1. **No write permission checks before operations**
   ```bash
   # Should check write permissions before creating directories
   mkdir -p /etc/prometheus || log_fatal "Cannot create /etc/prometheus"
   ```

2. **No directory existence validation**
   ```bash
   # In ensure_dir (common.sh line 639-652)
   ensure_dir() {
       if [[ ! -d "$path" ]]; then
           mkdir -p "$path"  # ISSUE: No error check
       fi
       chown "$owner:$group" "$path"  # ISSUE: Fails if mkdir failed
   }
   ```

#### 🔧 Fix

```bash
ensure_dir() {
    local path="$1"
    local owner="${2:-root}"
    local group="${3:-root}"
    local mode="${4:-0755}"

    if [[ ! -d "$path" ]]; then
        if ! mkdir -p "$path"; then
            log_error "Failed to create directory: $path"
            return 1
        fi
        log_debug "Created directory: $path"
    fi

    # Verify we can actually write to it
    if [[ ! -w "$path" ]]; then
        log_error "Directory not writable: $path"
        return 1
    fi

    chown "$owner:$group" "$path" || {
        log_error "Failed to set ownership on $path"
        return 1
    }
    chmod "$mode" "$path" || {
        log_error "Failed to set permissions on $path"
        return 1
    }

    return 0
}
```

### 2.6 Invalid User Input

#### ✅ Good: Input Validation Functions

```bash
# common.sh has validate_ip, validate_port, validate_hostname, validate_email
```

#### ❌ Issues

1. **Validation not consistently applied**
   ```bash
   # In add-monitored-host.sh line 132-134
   if ! is_valid_ip "$HOST_IP"; then
       log_error "Invalid IP address: '$HOST_IP'..."
   fi
   # GOOD - But this isn't done in all scripts that accept IP input
   ```

2. **No maximum length checks**
   ```bash
   # validate_hostname doesn't check max length (253 chars for FQDN)
   # Large inputs could cause buffer issues in external tools
   ```

3. **Missing validation on file paths**
   ```bash
   # User could provide "../../../etc/passwd" as a config path
   # The validate_path function exists but isn't used everywhere
   ```

#### 🔧 Recommendations

```bash
# Wrapper to enforce validation
safe_read_input() {
    local prompt="$1"
    local validator="$2"
    local value

    while true; do
        read -r -p "$prompt: " value
        if $validator "$value"; then
            echo "$value"
            return 0
        else
            log_error "Invalid input. Please try again."
        fi
    done
}

# Usage
HOST_IP=$(safe_read_input "Enter IP address" validate_ip)
```

### 2.7 Malformed Data Files

#### ❌ Critical: No YAML Validation

**The scripts use custom YAML parsing** (awk-based) which **doesn't validate YAML syntax**:

```bash
# In common.sh yaml_get
yaml_get() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 1  # Good - checks file exists
    fi

    # ISSUE: No validation that file is valid YAML
    # ISSUE: No error handling for malformed YAML
    grep -E "^${key}:" "$file" ...
}
```

**Potential Failure:**
- User edits YAML with syntax errors
- Scripts parse garbage values
- Silent failures or undefined behavior

#### 🔧 Fix

```bash
# Add YAML validation
validate_yaml() {
    local file="$1"

    # Check if yq or python is available for validation
    if command -v yq >/dev/null 2>&1; then
        yq eval '.' "$file" >/dev/null 2>&1
        return $?
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null
        return $?
    else
        # Fallback: basic syntax check
        if grep -q $'^\t' "$file"; then
            log_error "YAML file contains tabs: $file (use spaces)"
            return 1
        fi
        # Additional basic checks...
        return 0
    fi
}

# Use before parsing
yaml_get() {
    local file="$1"
    local key="$2"

    [[ -f "$file" ]] || return 1
    validate_yaml "$file" || {
        log_error "Invalid YAML file: $file"
        return 1
    }

    # ... rest of function
}
```

---

## 3. Race Conditions

### Score: 72/100

### 3.1 Concurrent Script Execution

#### ✅ Good: File Locking

```bash
# lock-utils.sh provides acquire_lock/release_lock
acquire_lock() {
    if command -v flock &>/dev/null; then
        exec 200>"$lock_file"
        if flock -n 200; then
            # Lock acquired
        fi
    fi
}
```

#### ❌ Issues

1. **Lock Not Used Consistently**
   ```bash
   # setup-observability.sh doesn't use locking
   # Multiple concurrent runs could interfere:
   # - Both download same files to /tmp
   # - Both try to create same systemd services
   # - Race in systemctl daemon-reload
   ```

2. **No Lock Cleanup on Crash**
   ```bash
   # In lock-utils.sh line 82-86
   if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
       log_warn "Stale lock found..."
       rm -f "$lock_file"
   fi
   # GOOD - but only happens if another process tries to acquire
   # Crashed process leaves stale lock until next run
   ```

3. **Trap Not Set in All Scripts**
   ```bash
   # lock-utils.sh line 56, 74
   trap 'release_lock' EXIT INT TERM
   # GOOD - but only in acquire_lock
   # If script doesn't source lock-utils.sh, no cleanup
   ```

#### 🔧 Recommendations

```bash
# Add to all major installation scripts
main() {
    acquire_lock "/var/lock/observability-setup.lock" 300 || {
        log_error "Another setup is running. Wait or check for stale locks."
        exit 1
    }

    # ... rest of script ...
}

# Auto-cleanup on script exit
setup_cleanup_traps
register_cleanup_function release_lock
```

### 3.2 File Locking Edge Cases

#### ❌ Issues

1. **Lock File Creation Race**
   ```bash
   # In lock-utils.sh line 38-41
   mkdir -p "$(dirname "$lock_file")" 2>/dev/null || {
       log_error "Failed to create lock directory..."
   }
   # RACE: Two processes could both create directory
   # RACE: Both could create lock file simultaneously
   ```

2. **flock vs noclobber Inconsistency**
   ```bash
   # Uses flock if available, else falls back to noclobber
   # Different behavior could cause issues
   ```

#### 🔧 Fix

```bash
acquire_lock() {
    # ... existing code ...

    # Always use flock if available for consistency
    if ! command -v flock &>/dev/null; then
        log_warn "flock not available, locking may be unreliable"
        # Consider making this fatal for production
    fi

    # ... rest of function
}
```

### 3.3 State File Corruption Scenarios

#### ❌ Critical Issue: No Atomic Writes in All Cases

```bash
# In common.sh atomic_write - GOOD
atomic_write() {
    temp_file=$(mktemp "${target_dir}/.tmp.XXXXXX")
    printf '%s\n' "$content" > "$temp_file"
    mv "$temp_file" "$target_file"  # Atomic on same filesystem
}

# BUT: Not used everywhere
# setup-observability.sh line 252
printf '%s\n' "$content" > "$file_path"
# ISSUE: Direct write, not atomic. Crash mid-write = corrupt file
```

#### 🔧 Fix

```bash
# Use atomic_write everywhere for important config files
write_config_with_check() {
    # ... existing validation ...

    # Replace direct write with atomic write
    atomic_write "$file_path" "$content" || {
        log_error "Failed to write config: $file_path"
        return 1
    }
}
```

### 3.4 Interrupt Handling (SIGINT, SIGTERM)

#### ✅ Good: Cleanup Traps

```bash
# common.sh line 834
setup_cleanup_traps() {
    trap _cleanup_on_exit EXIT INT TERM ERR
}
```

#### ❌ Issues

1. **Not enabled by default**
   - Scripts must explicitly call `setup_cleanup_traps`
   - Many scripts don't use it

2. **No protection for critical sections**
   ```bash
   # During binary installation, SIGINT could leave system in bad state:
   systemctl stop prometheus
   rm /usr/local/bin/prometheus  # <-- INTERRUPT HERE
   cp new_binary /usr/local/bin/prometheus
   systemctl start prometheus
   # Result: No prometheus binary, service fails to start
   ```

#### 🔧 Fix

```bash
# Critical section protection
critical_section() {
    trap '' INT TERM  # Ignore signals during critical section

    systemctl stop prometheus
    rm /usr/local/bin/prometheus
    cp new_binary /usr/local/bin/prometheus
    systemctl start prometheus

    trap - INT TERM  # Restore signal handling
}
```

### 3.5 Partial Operation Completion

#### ✅ Good: Transaction Support

```bash
# transaction.sh provides BEGIN/COMMIT/ROLLBACK semantics
tx_begin "install_nginx_exporter"
tx_create_file "/etc/systemd/system/nginx_exporter.service" "$SERVICE_CONTENT"
tx_service_enable "nginx_exporter"
tx_service_start "nginx_exporter"
tx_commit
```

#### ❌ Issues

1. **Transaction system not used in main scripts**
   ```bash
   # setup-observability.sh doesn't use transactions
   # Partial installation on error leaves system in inconsistent state
   ```

2. **No automatic rollback on script failure**
   - Scripts should use transactions for all state-changing operations
   - Currently manual cleanup only

#### 🔧 Recommendation

```bash
# Wrap entire installation in transaction
main() {
    tx_begin "observability_setup_$(date +%s)"

    prepare_system || { tx_rollback "System preparation failed"; exit 1; }
    install_prometheus || { tx_rollback "Prometheus install failed"; exit 1; }
    # ... etc

    tx_commit
    log_success "Installation complete"
}
```

---

## 4. Resource Exhaustion

### Score: 55/100 ⚠️

### 4.1 Disk Space Checks

#### ❌ Critical: Completely Missing

**No scripts check disk space before:**
- Large downloads (100MB+ binaries)
- Database creation (/var/lib/prometheus, /var/lib/loki)
- Log file writes
- Archive extraction

**See Section 2.4 for detailed fix**

### 4.2 Memory Usage Bounded

#### ❌ Issues

1. **No memory limits on processes**
   ```bash
   # Systemd services don't have MemoryLimit
   [Service]
   ExecStart=/usr/local/bin/prometheus ...
   # ISSUE: Prometheus could consume all system memory
   ```

2. **No memory checks before operations**
   ```bash
   # Large file operations don't check available memory
   # Loading entire config into memory without size check
   config=$(cat large_file.yaml)
   ```

#### 🔧 Fix

```bash
# Add to systemd service files
[Service]
MemoryLimit=2G
MemoryMax=4G
MemoryHigh=3G

# Add memory checks
check_available_memory() {
    local required_mb="${1:-512}"
    local available
    available=$(free -m | awk 'NR==2 {print $7}')

    if [[ $available -lt $required_mb ]]; then
        log_error "Insufficient memory: ${available}MB available, ${required_mb}MB required"
        return 1
    fi
    return 0
}
```

### 4.3 File Descriptor Leaks

#### ⚠️ Potential Issues

1. **File descriptor 200 not always closed**
   ```bash
   # lock-utils.sh line 125-126
   if command -v flock &>/dev/null; then
       exec 200>&-  # Close FD 200
   fi
   # ISSUE: Only closed if flock is available
   # If lock acquired with noclobber, FD never opened, but command tries to close it
   ```

2. **No ulimit checks**
   ```bash
   # Scripts don't verify ulimit -n is sufficient for workload
   # Prometheus with many targets could exhaust file descriptors
   ```

#### 🔧 Fix

```bash
# Check file descriptor limits
check_fd_limits() {
    local current_limit
    current_limit=$(ulimit -n)
    local required=8192

    if [[ $current_limit -lt $required ]]; then
        log_warn "File descriptor limit too low: $current_limit (recommended: $required)"
        log_info "Increase with: ulimit -n $required"
    fi
}

# Fix FD leak
release_lock() {
    # ... existing code ...

    # Only close FD if it was opened
    if [[ "$LOCK_ACQUIRED" == "true" ]] && command -v flock &>/dev/null; then
        exec 200>&- 2>/dev/null || true
    fi
}
```

### 4.4 Process Cleanup Thorough

#### ✅ Good: pkill After Stop

```bash
# setup-observability.sh line 831
systemctl stop prometheus 2>/dev/null || true
sleep 1
pkill -f "/usr/local/bin/prometheus" 2>/dev/null || true
```

#### ❌ Issues

1. **Fixed sleep duration**
   ```bash
   sleep 1
   # ISSUE: May not be enough for process to fully stop
   # Should wait for process to actually exit
   ```

2. **No verification that process actually stopped**
   ```bash
   # Should check that no process remains before continuing
   ```

#### 🔧 Fix

```bash
safe_stop_process() {
    local service="$1"
    local binary="$2"
    local max_wait="${3:-10}"

    # Stop service
    systemctl stop "$service" 2>/dev/null || true

    # Wait for process to exit
    local elapsed=0
    while pgrep -f "$binary" >/dev/null 2>&1; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_warn "Process didn't stop gracefully, force killing"
            pkill -9 -f "$binary" 2>/dev/null || true
            break
        fi
        sleep 1
        ((elapsed++))
    done

    if ! pgrep -f "$binary" >/dev/null 2>&1; then
        log_debug "Process stopped successfully: $service"
        return 0
    else
        log_error "Failed to stop process: $service"
        return 1
    fi
}
```

### 4.5 Temporary File Cleanup

#### ✅ Good: Cleanup Infrastructure

```bash
# common.sh line 771-825
register_temp_file() { _CLEANUP_TEMP_FILES+=("$file"); }
setup_cleanup_traps() { trap _cleanup_on_exit EXIT INT TERM ERR; }
```

#### ❌ Issues

1. **Not used consistently**
   ```bash
   # Many scripts create temp files without registering them
   temp=$(mktemp)
   # ... use temp ...
   # ISSUE: If script crashes, temp file leaks
   ```

2. **No cleanup of /tmp on disk full**
   ```bash
   # If /tmp fills up, scripts fail
   # No automatic cleanup of old temp files
   ```

#### 🔧 Fix

```bash
# Wrapper function to ensure cleanup
safe_mktemp() {
    local temp
    temp=$(mktemp "$@") || {
        log_error "Failed to create temporary file"
        return 1
    }

    register_temp_file "$temp"
    echo "$temp"
}

# Usage
temp=$(safe_mktemp)  # Automatically cleaned up on exit
```

---

## 5. Boundary Conditions

### Score: 70/100

### 5.1 Maximum File Sizes Handled

#### ❌ Issues

1. **No size checks before file operations**
   ```bash
   # config=$(<"$file")  # Loads entire file into memory
   # What if file is 1GB? Script crashes with OOM
   ```

2. **Log rotation size check uses stat differently on systems**
   ```bash
   # common.sh line 52-53
   size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
   # FRAGILE: Different stat implementations
   # Better: Use du or check file size programmatically
   ```

#### 🔧 Fix

```bash
get_file_size() {
    local file="$1"

    if [[ -f "$file" ]]; then
        # Use du for portability
        du -b "$file" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

safe_read_file() {
    local file="$1"
    local max_size="${2:-10485760}"  # 10MB default

    local size
    size=$(get_file_size "$file")

    if [[ $size -gt $max_size ]]; then
        log_error "File too large: $file ($size bytes, max $max_size)"
        return 1
    fi

    cat "$file"
}
```

### 5.2 Maximum Number of Hosts

#### ⚠️ Potential Issues

1. **No limit on monitored hosts**
   ```bash
   # Prometheus config generation loops through all hosts
   # With 1000+ hosts, config could become unmanageable
   ```

2. **Linear config generation**
   ```bash
   # In setup-observability.sh line 889-904
   # O(n) loop to build targets
   # With many hosts, this is slow and memory-intensive
   ```

#### 🔧 Recommendation

```bash
# Add validation
MAX_HOSTS=100
host_count=$(grep -c "name:" "$CONFIG_FILE")
if [[ $host_count -gt $MAX_HOSTS ]]; then
    log_warn "Large number of hosts detected: $host_count"
    log_warn "Consider using Prometheus service discovery instead"
fi
```

### 5.3 Maximum Number of Modules

#### ✅ Good: No hard limit, flexible design

- Module system is well-architected for extensibility
- No performance issues observed

### 5.4 Maximum Configuration Complexity

#### ⚠️ Potential Issues

1. **Deep YAML nesting**
   ```bash
   # yaml_get_deep only supports 3 levels
   yaml_get_deep() {
       local level1="$2"
       local level2="$3"
       local level3="$4"
       # ... no support for level4+
   }
   ```

2. **No validation of config complexity**

#### 🔧 Recommendation

```bash
# Add complexity validation
validate_config_complexity() {
    local file="$1"

    # Check nesting depth
    local max_indent
    max_indent=$(grep -E '^ +' "$file" | awk '{print length($0) - length(ltrim($0))}' | sort -rn | head -1)

    if [[ $max_indent -gt 12 ]]; then  # 3 levels * 4 spaces
        log_warn "Config file has deep nesting (${max_indent} spaces max)"
    fi
}
```

### 5.5 Network Timeout Handling

#### ✅ Good: Timeouts defined

```bash
# download-utils.sh has timeout parameters
safe_download() {
    local timeout="${3:-30}"
    wget --timeout="$timeout" ...
}
```

#### ❌ Inconsistencies

1. **Different timeout values across scripts**
   ```bash
   # common.sh line 1010-1018: timeout=30
   # download-utils.sh line 29: timeout=30 (default)
   # retry.sh line 29: timeout=300 (5 minutes)
   # Inconsistent defaults
   ```

2. **DNS timeout separate from connect timeout**
   ```bash
   # common.sh line 1016
   --dns-timeout=10 \
   --connect-timeout=10 \
   --read-timeout=30
   # GOOD - but not used everywhere
   ```

#### 🔧 Recommendation

```bash
# Standardize timeouts in common.sh
readonly TIMEOUT_DNS=10
readonly TIMEOUT_CONNECT=10
readonly TIMEOUT_READ=30
readonly TIMEOUT_TOTAL=60

# Use consistently
safe_download() {
    wget \
        --dns-timeout="$TIMEOUT_DNS" \
        --connect-timeout="$TIMEOUT_CONNECT" \
        --read-timeout="$TIMEOUT_READ" \
        --timeout="$TIMEOUT_TOTAL" \
        ...
}
```

---

## 6. Fail-Safe Mechanisms

### Score: 80/100

### 6.1 Rollback on Partial Failure

#### ✅ Good: Transaction Infrastructure

```bash
# transaction.sh provides comprehensive rollback
tx_rollback() {
    # Executes custom rollback hooks in reverse order
    # Restores files from backup
    # Reverts service state changes
}
```

#### ❌ Not Used in Main Scripts

```bash
# setup-observability.sh doesn't use transactions
# On failure, system left in partial state
# Manual cleanup required
```

#### 🔧 Critical Recommendation

**Wrap all major installation scripts in transactions:**

```bash
# Modify setup-observability.sh main()
main() {
    # Start transaction
    tx_begin "observability_setup_$(date +%s)"

    # Register rollback hooks
    tx_register_rollback "systemctl stop prometheus 2>/dev/null || true"

    # Run installations with rollback on failure
    prepare_system || { tx_rollback "prepare_system failed"; exit 1; }
    install_prometheus || { tx_rollback "install_prometheus failed"; exit 1; }
    # ... etc

    # Commit only if everything succeeded
    tx_commit
}
```

### 6.2 State Recovery Possible

#### ✅ Good: Backup System

```bash
# setup-observability.sh line 290-323
create_backup() {
    init_backup
    backup_file "/etc/prometheus/prometheus.yml"
    # ... backs up all configs before changes
}
```

#### ❌ Issues

1. **No automatic recovery**
   - Backup created, but manual restore required
   - No `--restore-from-backup` option

2. **Backup naming not versioned**
   ```bash
   # Timestamp-based: ${BACKUP_TIMESTAMP}
   # Hard to identify which backup corresponds to which operation
   ```

#### 🔧 Recommendation

```bash
# Add restore functionality
restore_from_backup() {
    local backup_dir="$1"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        return 1
    fi

    log_warn "Restoring from backup: $backup_dir"

    # Transaction for restore
    tx_begin "restore_backup"

    # Restore each file
    for backup_file in "$backup_dir"/*; do
        local original="${backup_file##*/}"
        # ... restore logic ...
    done

    tx_commit
}

# Add to CLI
./setup-observability.sh --restore-from-backup /var/backups/observability-stack/20251227_120000
```

### 6.3 Data Corruption Prevention

#### ✅ Good: Atomic Writes

```bash
# common.sh atomic_write() uses temp file + mv
atomic_write() {
    temp_file=$(mktemp "${target_dir}/.tmp.XXXXXX")
    printf '%s\n' "$content" > "$temp_file"
    mv "$temp_file" "$target_file"  # Atomic
}
```

#### ❌ Not Used Consistently

- Many direct writes: `echo "content" > file`
- Should use atomic_write everywhere

### 6.4 Atomic Operations Verified

#### ⚠️ Partial

1. **File operations - Good**
   - `mv` is atomic on same filesystem
   - Used in atomic_write()

2. **Service operations - Not Atomic**
   ```bash
   systemctl stop service
   rm /usr/local/bin/binary  # <-- Not atomic with stop
   cp new_binary /usr/local/bin/binary
   systemctl start service
   # ISSUE: Crash between operations = inconsistent state
   ```

#### 🔧 Fix

```bash
atomic_service_update() {
    local service="$1"
    local old_binary="$2"
    local new_binary="$3"

    # Prepare new binary first (while service running)
    local temp_binary="${old_binary}.new"
    cp "$new_binary" "$temp_binary"
    chmod +x "$temp_binary"

    # Atomic swap
    systemctl stop "$service"
    mv "$temp_binary" "$old_binary"  # Atomic mv
    systemctl start "$service"
}
```

### 6.5 Transaction Boundaries Clear

#### ✅ Good: Well-Defined in transaction.sh

```bash
tx_begin "operation_name")
# ... operations ...
tx_commit  # or tx_rollback
```

#### ❌ Not Used in Practice

- Main installation scripts don't use transactions
- Need to refactor to use transaction boundaries

---

## 7. Logging & Debugging

### Score: 82/100

### 7.1 Enough Logging for Debugging

#### ✅ Strengths

1. **Multiple log levels**
   ```bash
   log_debug()   # Only if DEBUG=true
   log_info()
   log_warn()
   log_error()
   log_fatal()
   ```

2. **Structured logging**
   ```bash
   # common.sh line 64-83
   _log_to_file() {
       local level="$1"
       local message="$2"
       local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
       printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message"
   }
   ```

3. **Log rotation**
   ```bash
   _rotate_log_if_needed() {
       if [[ "$size" -gt "$OBSERVABILITY_LOG_MAX_SIZE" ]]; then
           mv "$OBSERVABILITY_LOG_FILE" "${OBSERVABILITY_LOG_FILE}.${timestamp}"
           gzip "${OBSERVABILITY_LOG_FILE}.${timestamp}"
       fi
   }
   ```

#### ❌ Issues

1. **Insufficient debug logging**
   ```bash
   # Many operations don't have debug logs
   # Hard to trace execution flow without verbose mode
   ```

2. **No correlation IDs**
   ```bash
   # Multiple concurrent scripts logging to same file
   # Hard to separate interleaved logs
   ```

#### 🔧 Recommendations

```bash
# Add correlation ID
export LOG_CORRELATION_ID="${LOG_CORRELATION_ID:-$(date +%s)_$$}"

_log_to_file() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%s] [%s] %s\n' "$timestamp" "$LOG_CORRELATION_ID" "$level" "$message"
}

# Add trace logging
log_trace() {
    if [[ "${TRACE:-false}" == "true" ]]; then
        local caller="${FUNCNAME[1]}"
        local line="${BASH_LINENO[0]}"
        log_debug "TRACE: $caller:$line - $1"
    fi
}
```

### 7.2 Log Levels Appropriate

#### ✅ Good: Well-balanced

- DEBUG for detailed tracing
- INFO for normal operations
- WARN for non-fatal issues
- ERROR for failures
- FATAL for unrecoverable errors

#### ⚠️ Some Inconsistencies

```bash
# Some warnings should be errors
log_warn "Failed to download"  # Should be ERROR if critical

# Some info should be debug
log_info "Entering function X"  # Should be DEBUG
```

### 7.3 Sensitive Data Not Logged

#### ✅ Excellent Security

```bash
# common.sh line 1619
log_debug "Resolved secret '$secret_name' from file ($(wc -c < "$secret_file") bytes)"
# GOOD: Logs secret exists and size, but NOT the value
```

#### ✅ Password handling

```bash
# Passwords never logged in plain text
# Good practices throughout codebase
```

### 7.4 Debug Mode Available

#### ✅ Yes

```bash
DEBUG=true ./setup-observability.sh
```

#### ⚠️ Limited

- Debug mode only enables log_debug output
- Doesn't provide execution tracing
- No set -x equivalent for step-by-step execution

#### 🔧 Enhancement

```bash
# Add trace mode
if [[ "${TRACE:-false}" == "true" ]]; then
    set -x  # Enable bash tracing
    PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
fi

# Usage
TRACE=true DEBUG=true ./setup-observability.sh
```

### 7.5 Verbose Mode Useful

#### ✅ Good: Combined with DEBUG

```bash
if [[ "${DEBUG:-false}" == "true" ]]; then
    # Verbose logging enabled
fi
```

#### 🔧 Suggestion

```bash
# Separate DEBUG and VERBOSE
VERBOSE=true  # Show what's happening
DEBUG=true    # Show why it's happening
TRACE=true    # Show how it's happening (bash -x)

log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]] || [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}
```

---

## 8. Critical Runtime Issues Summary

### Priority 1 - Must Fix Before Production

1. **❌ No disk space checks** (Section 2.4, 4.1)
   - Risk: Script fills disk, system becomes unresponsive
   - Fix: Add check_disk_space() before all large operations

2. **❌ No transaction usage in main scripts** (Section 6.1)
   - Risk: Partial installation on failure, difficult recovery
   - Fix: Wrap all installations in tx_begin/tx_commit

3. **❌ No atomic operations for service updates** (Section 6.4)
   - Risk: Crash during update leaves system broken
   - Fix: Use atomic_service_update() pattern

4. **❌ Race conditions in concurrent execution** (Section 3.1)
   - Risk: Multiple installations interfere with each other
   - Fix: Use acquire_lock() in all main scripts

5. **❌ No YAML validation** (Section 2.7)
   - Risk: Malformed config causes unpredictable failures
   - Fix: Add validate_yaml() before parsing

### Priority 2 - Should Fix

6. **⚠️ Incomplete error propagation** (Section 1)
   - Risk: Silent failures, unclear error messages
   - Fix: Use error_push_context/error_pop_context everywhere

7. **⚠️ Memory limits not set** (Section 4.2)
   - Risk: Prometheus/Loki consume all system memory
   - Fix: Add MemoryLimit to systemd services

8. **⚠️ Inconsistent input validation** (Section 2.6)
   - Risk: Malicious or malformed input causes failures
   - Fix: Apply validation functions consistently

9. **⚠️ No cleanup on disk full** (Section 4.5)
   - Risk: Leaked temp files fill filesystem
   - Fix: Use safe_mktemp() wrapper everywhere

10. **⚠️ No network connectivity preflight** (Section 2.3)
    - Risk: Failures during download leave partial state
    - Fix: Add check_network() before operations

### Priority 3 - Nice to Have

11. **📝 Insufficient debug logging** (Section 7.1)
12. **📝 No automatic backup restore** (Section 6.2)
13. **📝 File descriptor limit checks** (Section 4.3)
14. **📝 Timeout value standardization** (Section 5.5)
15. **📝 Correlation IDs for logging** (Section 7.1)

---

## 9. Production Readiness Assessment

### Overall: CONDITIONAL SAFE ⚠️

The observability stack is **production-ready with critical fixes applied**. The codebase demonstrates solid engineering practices and security awareness, but several runtime gaps must be addressed before deployment to production.

### Required Actions Before Production

#### ✅ Must Complete

1. **Add disk space checks to all installation scripts**
   ```bash
   check_disk_space 2000 "/var/lib" || exit 1
   ```

2. **Wrap installations in transactions**
   ```bash
   tx_begin "installation"
   # ... operations ...
   tx_commit || tx_rollback
   ```

3. **Add file locking to prevent concurrent runs**
   ```bash
   acquire_lock "/var/lock/observability.lock" || exit 1
   ```

4. **Validate YAML before parsing**
   ```bash
   validate_yaml "$CONFIG_FILE" || exit 1
   ```

5. **Use atomic operations for critical updates**
   ```bash
   atomic_service_update "prometheus" "/usr/local/bin/prometheus" "$new_binary"
   ```

#### 📋 Should Complete

6. Set memory limits in systemd services
7. Add network connectivity checks
8. Standardize error handling with context
9. Improve cleanup on interrupts
10. Add correlation IDs to logs

#### 🎯 Recommended

11. Implement automatic backup restore
12. Add trace mode for debugging
13. Improve test coverage
14. Add resource monitoring
15. Create runbook for common failures

### Risk Assessment

| Category | Current Score | With Fixes | Risk Level |
|----------|---------------|------------|------------|
| Error Handling | 75/100 | 90/100 | LOW ✅ |
| Edge Cases | 68/100 | 85/100 | MEDIUM ⚠️ |
| Race Conditions | 72/100 | 88/100 | LOW ✅ |
| Resource Exhaustion | 55/100 | 85/100 | HIGH ❌ → MEDIUM ⚠️ |
| Boundary Conditions | 70/100 | 82/100 | MEDIUM ⚠️ |
| Fail-Safe | 80/100 | 92/100 | LOW ✅ |
| Logging | 82/100 | 88/100 | LOW ✅ |

**Overall Risk After Fixes: MEDIUM-LOW** ⚠️→✅

---

## 10. Recommendations

### Immediate Actions (Week 1)

1. **Add disk space checks** - 4 hours
2. **Implement file locking** - 3 hours
3. **Add YAML validation** - 2 hours
4. **Fix atomic operations** - 4 hours
5. **Add transaction wrappers** - 8 hours

**Total effort: ~21 hours (2-3 days)**

### Short Term (Weeks 2-4)

1. Add memory limits to services
2. Standardize error handling
3. Improve network handling
4. Add resource monitoring
5. Create recovery documentation

### Long Term (Months 1-3)

1. Automated testing framework
2. Chaos testing
3. Performance optimization
4. Monitoring dashboard
5. SLA/SLO definitions

### Code Quality Improvements

1. **Shellcheck Integration**
   - Run shellcheck on all scripts in CI
   - Fix all warnings and errors

2. **Test Coverage**
   - Unit tests for critical functions
   - Integration tests for workflows
   - Chaos testing for failure scenarios

3. **Documentation**
   - Runbook for common failures
   - Recovery procedures
   - Troubleshooting guide

---

## Conclusion

The observability stack is **well-architected with strong foundations**, but requires **targeted runtime improvements** before production deployment. The identified issues are **fixable within a reasonable timeframe**, and the codebase demonstrates good practices that make fixes straightforward.

**Recommended Path Forward:**

1. **Apply Priority 1 fixes** (disk space, transactions, locking, YAML validation)
2. **Test thoroughly** with chaos engineering
3. **Deploy to staging** for extended testing
4. **Address Priority 2 fixes** based on staging results
5. **Deploy to production** with monitoring and runbooks

**Estimated Timeline to Production Ready: 2-4 weeks**

The codebase shows **mature engineering practices** and with the critical runtime issues addressed, will be **robust and production-ready**.

---

**Report Generated:** 2025-12-27
**Analyst:** Claude Sonnet 4.5
**Methodology:** Static analysis, code review, edge case enumeration, failure scenario simulation
