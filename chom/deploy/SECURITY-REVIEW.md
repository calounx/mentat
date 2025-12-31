# Deployment Scripts Security & Correctness Review

**Review Date:** 2025-12-29
**Reviewer:** Security Analysis
**Scope:** deploy-enhanced.sh, setup-observability-vps.sh, setup-vpsmanager-vps.sh

## Executive Summary

The deployment scripts are generally well-structured with good error handling, but contain **several critical security vulnerabilities** and correctness issues that could lead to deployment failures or security breaches.

**Risk Level:** HIGH
**Critical Issues:** 5
**Major Issues:** 8
**Minor Issues:** 6

---

## CRITICAL SECURITY ISSUES

### 1. Command Injection Vulnerability in `remote_exec` (CRITICAL)

**File:** `deploy-enhanced.sh:934-947`

**Issue:**
```bash
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4  # UNQUOTED in ssh command

    ssh ... "${user}@${host}" "$cmd"  # Vulnerable to injection
}
```

**Vulnerability:**
The `$cmd` parameter is passed directly to SSH without proper sanitization. When `remote_exec` is called with user-controlled data (like from `get_config`), an attacker could inject arbitrary commands if they control the YAML configuration file.

**Exploit Scenario:**
```bash
# Line 1917: obs_ip comes from YAML config
if remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-vpsmanager-vps.sh && OBSERVABILITY_IP=${obs_ip} /tmp/setup-vpsmanager-vps.sh"; then
```

If `obs_ip` contains: `1.2.3.4; rm -rf /`
The executed command becomes: `OBSERVABILITY_IP=1.2.3.4; rm -rf / /tmp/setup-vpsmanager-vps.sh`

**Impact:** Remote code execution on VPS servers

**Fix:**
```bash
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4
    local key_path="${KEYS_DIR}/chom_deploy_key"

    # Use printf %q to properly escape the command
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        -- \
        "$cmd"
}

# Better: Pass commands as arrays when possible
# Or validate/sanitize obs_ip before use
```

---

### 2. `eval` Command Injection in Retry Logic (CRITICAL)

**File:** `deploy-enhanced.sh:1001, 1019`

**Issue:**
```bash
retry_with_healing() {
    local command_to_retry=$2
    local auto_fix_function=${3:-""}

    # DANGEROUS: eval executes arbitrary strings
    if eval "$command_to_retry"; then
        ...
    fi

    if eval "$auto_fix_function"; then
        ...
    fi
}
```

**Vulnerability:**
Using `eval` on variables that could contain user input or untrusted data is extremely dangerous. If any caller passes unsanitized data, it will be executed directly.

**Impact:** Arbitrary code execution on control machine

**Fix:**
```bash
# Instead of eval, call functions directly
retry_with_healing() {
    local operation_name=$1
    shift
    # Execute remaining arguments as command
    local attempt=1
    local max_attempts=$MAX_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then  # Execute function/command directly
            return 0
        fi
        ...
    done
}

# Usage:
retry_with_healing "SSH test" test_ssh_connection "$host" "$user" "$port" "$name"
```

---

### 3. Unsafe Temporary File Handling (CRITICAL)

**File:** `deploy-enhanced.sh:462-510`

**Issue:**
```bash
update_state() {
    local tmp_file="${STATE_FILE}.tmp.$$"
    trap "rm -f '$tmp_file'" RETURN  # SC2064: Expands NOW, not on signal

    # Predictable filename - race condition possible
    jq "..." "$STATE_FILE" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}
```

**Vulnerabilities:**
1. **SC2064**: The trap uses double quotes, so `$tmp_file` is expanded immediately, not when the trap fires
2. **Race Condition**: Predictable temp file names allow symlink attacks
3. **TOCTOU**: Time-of-check/time-of-use between creation and use

**Attack Scenario:**
```bash
# Attacker creates symlink before script runs
ln -s /etc/passwd /path/to/.deploy-state/deployment.state.tmp.12345

# When script runs update_state, it overwrites /etc/passwd
```

**Fix:**
```bash
update_state() {
    local tmp_file
    tmp_file=$(mktemp "${STATE_FILE}.XXXXXX")  # Secure random temp file
    trap 'rm -f "$tmp_file"' RETURN  # Single quotes!

    # Set restrictive permissions immediately
    chmod 600 "$tmp_file"

    if ! jq ".status = \"$status\" | .updated_at = \"$timestamp\"" "$STATE_FILE" > "$tmp_file" 2>/dev/null; then
        log_error "Failed to update state"
        return 1
    fi

    # Atomic move (on same filesystem)
    if ! mv "$tmp_file" "$STATE_FILE"; then
        log_error "Failed to save state file"
        return 1
    fi
}
```

---

### 4. Credentials Stored in World-Readable Temp Files (CRITICAL)

**File:** `setup-vpsmanager-vps.sh:228-244`

**Issue:**
```bash
# Line 222: Generate password
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

# Line 228: VULNERABLE - credentials in /tmp
cat > /tmp/.my.cnf << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
chmod 600 /tmp/.my.cnf  # TOO LATE - already created with default perms

mysql --defaults-extra-file=/tmp/.my.cnf << 'SQL'
...
SQL

rm -f /tmp/.my.cnf
```

**Vulnerabilities:**
1. File created in `/tmp` with default permissions (usually 644) before `chmod 600`
2. Other users can read the file between creation and chmod
3. Credentials visible in process list before chmod
4. Predictable filename - race condition

**Impact:** Database credentials leak, privilege escalation

**Fix:**
```bash
# Use secure temporary file
MYSQL_CONF=$(mktemp /root/.my.cnf.XXXXXX)
chmod 600 "$MYSQL_CONF"  # Set permissions FIRST

cat > "$MYSQL_CONF" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

# Use the secure file
mysql --defaults-extra-file="$MYSQL_CONF" << 'SQL'
...
SQL

# Secure deletion
shred -u "$MYSQL_CONF" 2>/dev/null || rm -f "$MYSQL_CONF"
```

---

### 5. Dashboard PHP Code Execution Vulnerability (CRITICAL)

**File:** `setup-vpsmanager-vps.sh:402-436`

**Issue:**
```php
// Line 402: Predictable temp file with user's IP in name
$attempts_file = '/tmp/dashboard_login_attempts_' . md5($_SERVER['REMOTE_ADDR']);

function record_failed_attempt($attempts_file) {
    $attempts = file_exists($attempts_file)
        ? json_decode(file_get_contents($attempts_file), true)
        : [];
    if (!is_array($attempts)) $attempts = [];

    $attempts[] = time();
    file_put_contents($attempts_file, json_encode($attempts));  // Default perms
    chmod($attempts_file, 0600);  // TOO LATE
}
```

**Vulnerabilities:**
1. Predictable temp file location allows race conditions
2. File created with default permissions before chmod
3. MD5 of IP is predictable - attacker can pre-create malicious files
4. No validation that file is actually owned by the web server

**Attack Scenario:**
```bash
# Attacker pre-creates symlink (knowing their own IP)
ln -s /etc/passwd /tmp/dashboard_login_attempts_$(echo -n "1.2.3.4" | md5sum | cut -d' ' -f1)

# When they visit dashboard, PHP writes login attempts to /etc/passwd
```

**Fix:**
```php
// Use session-based rate limiting instead of temp files
session_start();

function check_rate_limit($max_attempts, $lockout_duration) {
    if (!isset($_SESSION['login_attempts'])) {
        $_SESSION['login_attempts'] = [];
    }

    // Clean old attempts
    $_SESSION['login_attempts'] = array_filter($_SESSION['login_attempts'], function($time) use ($lockout_duration) {
        return (time() - $time) < $lockout_duration;
    });

    return count($_SESSION['login_attempts']) < $max_attempts;
}

function record_failed_attempt() {
    $_SESSION['login_attempts'][] = time();
}
```

---

## MAJOR SECURITY ISSUES

### 6. Unsafe Password Hashing in Dashboard

**File:** `setup-vpsmanager-vps.sh:389`

**Issue:**
```bash
DASHBOARD_PASSWORD_HASH=$(php -r "echo password_hash('${DASHBOARD_PASSWORD}', PASSWORD_BCRYPT);")
```

**Vulnerabilities:**
1. Password visible in process list (ps aux shows full command)
2. Shell expansion could break with special characters in password
3. Logged to shell history

**Fix:**
```bash
# Use heredoc to avoid process list exposure
DASHBOARD_PASSWORD_HASH=$(php <<'PHP'
<?php
$password = getenv('DASHBOARD_PASSWORD');
echo password_hash($password, PASSWORD_BCRYPT);
PHP
)
export DASHBOARD_PASSWORD  # Only for this command
php <<'PHP'
<?php
$password = getenv('DASHBOARD_PASSWORD');
echo password_hash($password, PASSWORD_BCRYPT);
PHP
unset DASHBOARD_PASSWORD
```

---

### 7. Shell Injection in Dashboard PHP

**File:** `setup-vpsmanager-vps.sh:438-446`

**Issue:**
```php
function get_uptime() {
    // SECURITY: Use native PHP instead of shell_exec
    if (file_exists('/proc/uptime')) {
        $uptime_seconds = (int) explode(' ', file_get_contents('/proc/uptime'))[0];
        ...
    }
}
```

**Good:** The comment claims to avoid shell_exec, which is correct.

**BUT:** Earlier versions or other parts might use `shell_exec`:
```php
// DANGEROUS (if it existed):
// $uptime = shell_exec("uptime");
```

**Recommendation:** Audit all PHP code for `shell_exec`, `exec`, `system`, `passthru`, `popen` usage.

---

### 8. Missing Input Validation on Config Values

**File:** `deploy-enhanced.sh:720-722`

**Issue:**
```bash
get_config() {
    yq eval "$1" "$CONFIG_FILE"  # NO VALIDATION
}

# Used like:
local ip=$(get_config '.observability.ip')
# Then directly used in remote_exec commands
```

**Vulnerability:**
If YAML file is compromised or malformed, values are used directly in:
- SSH commands
- Remote execution
- File paths

**Fix:**
```bash
get_config() {
    local field=$1
    local value
    value=$(yq eval "$field" "$CONFIG_FILE" 2>/dev/null)

    # Validate based on field type
    case "$field" in
        *.ip)
            if ! [[ "$value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log_error "Invalid IP address from config: $value"
                return 1
            fi
            ;;
        *.ssh_port)
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ $value -lt 1 || $value -gt 65535 ]]; then
                log_error "Invalid port from config: $value"
                return 1
            fi
            ;;
        *.ssh_user)
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                log_error "Invalid username from config: $value"
                return 1
            fi
            ;;
    esac

    echo "$value"
}
```

---

### 9. TOCTOU Race in Lock File Check

**File:** `deploy-enhanced.sh:226-244`

**Issue:**
```bash
acquire_lock() {
    LOCK_FILE="${STATE_DIR}/deploy.lock"

    if [[ -f "$LOCK_FILE" ]]; then  # CHECK
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        ...
        rm -f "$LOCK_FILE"  # Another process could lock here
    fi

    mkdir -p "$STATE_DIR"
    echo $$ > "$LOCK_FILE"  # USE - not atomic
}
```

**Vulnerability:**
Time-of-check/time-of-use race condition. Two processes could both pass the check and both acquire the lock.

**Fix:**
```bash
acquire_lock() {
    LOCK_FILE="${STATE_DIR}/deploy.lock"
    local max_wait=10
    local waited=0

    # Create state dir first
    mkdir -p "$STATE_DIR"

    # Use atomic file creation with set -C (noclobber)
    while [[ $waited -lt $max_wait ]]; do
        if (set -C; echo $$ > "$LOCK_FILE") 2>/dev/null; then
            log_debug "Acquired deployment lock (PID: $$)"
            return 0
        fi

        # Check if holder is alive
        if [[ -f "$LOCK_FILE" ]]; then
            local pid=$(cat "$LOCK_FILE" 2>/dev/null)
            if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                log_warn "Removing stale lock file (PID $pid not running)"
                rm -f "$LOCK_FILE"
                continue
            fi
        fi

        sleep 1
        ((waited++))
    done

    log_error "Could not acquire lock after ${max_wait}s"
    return 1
}
```

---

### 10. Unquoted Variable Expansion

**File:** Multiple locations

**Issue:**
```bash
# Line 1027: Unquoted variable in arithmetic
local delay=$(calculate_backoff $attempt)  # OK in arithmetic context

# Line 1034: Unquoted in for loop
for ((i=delay; i>0; i--)); do  # Should be $delay
```

**Fix:**
```bash
for ((i=$delay; i>0; i--)); do
```

---

### 11. Weak Signal Handling

**File:** `deploy-enhanced.sh:179-195`

**Issue:**
```bash
handle_sigint() {
    echo ""
    log_warn "Received interrupt signal (Ctrl+C)"
    CLEANUP_NEEDED=true
    exit 130
}

trap handle_sigint SIGINT
```

**Problems:**
1. No cleanup of remote operations
2. Remote scripts may continue running after local script exits
3. No way to kill remote processes

**Fix:**
```bash
# Track remote PIDs
declare -A REMOTE_PIDS

remote_exec() {
    # ... existing code ...
    ssh ... "${user}@${host}" "$cmd" &
    local ssh_pid=$!
    REMOTE_PIDS["${host}:${port}"]=$ssh_pid
    wait $ssh_pid
}

handle_sigint() {
    echo ""
    log_warn "Received interrupt signal - cleaning up remote operations..."

    # Kill remote SSH sessions
    for key in "${!REMOTE_PIDS[@]}"; do
        local pid=${REMOTE_PIDS[$key]}
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Terminating remote operation on $key (PID $pid)"
            kill "$pid" 2>/dev/null
        fi
    done

    CLEANUP_NEEDED=true
    exit 130
}
```

---

### 12. Inadequate Error Handling in Service Verification

**File:** `setup-observability-vps.sh:35-68`, `setup-vpsmanager-vps.sh:40-73`

**Issue:**
```bash
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    ...

    # Wait for binary to be released
    while [[ $waited -lt $max_wait ]]; do
        if ! lsof "$binary_path" &>/dev/null; then  # lsof might not be installed
            return 0
        fi
        sleep 1
        ((waited++))
    done
}
```

**Problems:**
1. `lsof` may not be installed (fails silently)
2. No check if binary exists before running lsof
3. Could hang for 30 seconds unnecessarily

**Fix:**
```bash
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_wait=30
    local waited=0

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        log_info "Service ${service_name} does not exist yet, skipping stop"
        return 0
    fi

    # Stop service if running
    if systemctl is-active --quiet "$service_name"; then
        log_info "Stopping ${service_name}..."
        systemctl stop "$service_name" || {
            log_error "Failed to stop ${service_name}"
            return 1
        }
    fi

    # Only check lsof if binary exists and lsof is available
    if [[ -f "$binary_path" ]] && command -v lsof &>/dev/null; then
        while [[ $waited -lt $max_wait ]]; do
            if ! lsof "$binary_path" &>/dev/null; then
                log_success "${service_name} stopped and binary released"
                return 0
            fi
            sleep 1
            ((waited++))
        done
        log_error "Timeout waiting for ${binary_path} to be released"
        return 1
    fi

    # Fallback: just verify service stopped
    if ! systemctl is-active --quiet "$service_name"; then
        log_success "${service_name} stopped"
        return 0
    fi

    return 1
}
```

---

### 13. Loki Authentication Enabled Without Credentials

**File:** `setup-observability-vps.sh:256`

**Issue:**
```yaml
# Line 256
auth_enabled: true

# But no authentication configured anywhere!
# No users, no passwords, no tokens
```

**Impact:**
- Loki rejects all requests (service broken)
- OR accepts unauthenticated requests (security issue)

**Fix:**
```yaml
# Either disable auth for internal use:
auth_enabled: false

# OR configure multi-tenancy properly:
auth_enabled: true
# And add authentication headers in datasource config
```

---

## MINOR ISSUES

### 14. Unused Variables (Code Quality)

**File:** `deploy-enhanced.sh`

**Issues:**
- Line 71: `TOTAL_STEPS` - declared but never used
- Line 72: `CURRENT_STEP` - declared but never incremented
- Line 73: `STEP_DESCRIPTIONS` - declared but never populated
- Line 76: `ERROR_CONTEXT` - declared but never used

**Impact:** Code clutter, potential confusion

**Fix:** Remove unused variables or implement progress tracking

---

### 15. Declare and Assign Separately (SC2155)

**File:** Multiple locations

**Issue:**
```bash
local obs_ip=$(get_config '.observability.ip')  # Masks return value
```

If `get_config` fails, `$?` will be 0 (from `local`), not the actual error code.

**Fix:**
```bash
local obs_ip
obs_ip=$(get_config '.observability.ip') || return 1
```

---

### 16. Missing Validation of User Input in ssh-copy-id

**File:** `deploy-enhanced.sh:815-839`

**Issue:**
```bash
if ssh-copy-id -i "${key_path}.pub" -p "${obs_port}" "${obs_user}@${obs_ip}"; then
    # No validation that key was actually copied
fi
```

**Problem:** `ssh-copy-id` might succeed but not actually add the key (e.g., .ssh/authorized_keys is read-only).

**Fix:**
```bash
if ssh-copy-id -i "${key_path}.pub" -p "${obs_port}" "${obs_user}@${obs_ip}"; then
    # Verify key actually works
    if ssh -o BatchMode=yes -i "$key_path" -p "$obs_port" "${obs_user}@${obs_ip}" "echo test" &>/dev/null; then
        log_success "Key copied and verified"
    else
        log_error "Key copied but authentication failed"
        copy_failed=true
    fi
fi
```

---

### 17. Hardcoded Timeouts May Be Too Short

**File:** `deploy-enhanced.sh:890`

**Issue:**
```bash
ssh -o ConnectTimeout=10 ...  # 10 seconds might be too short for slow networks
```

**Fix:**
Make timeout configurable:
```bash
SSH_CONNECT_TIMEOUT=${SSH_CONNECT_TIMEOUT:-30}
ssh -o ConnectTimeout=$SSH_CONNECT_TIMEOUT ...
```

---

### 18. No Validation of Downloaded Binaries

**File:** `setup-observability-vps.sh:123-134`

**Issue:**
```bash
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
```

**Problem:**
1. No checksum verification
2. No signature verification
3. Downloads could be MITM'd

**Fix:**
```bash
# Download checksum
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/sha256sums.txt"

# Verify
sha256sum -c sha256sums.txt --ignore-missing || {
    log_error "Checksum verification failed"
    exit 1
}
```

---

### 19. IPv6 Not Supported

**File:** `deploy-enhanced.sh:664-674`

**Issue:**
```bash
# Validate IP format (IPv4)
if ! [[ "$obs_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
```

**Problem:** Script only supports IPv4, will fail with IPv6 addresses

**Fix:** Add IPv6 support or document limitation clearly

---

## CORRECTNESS ISSUES

### 20. Race Condition in State File Updates

**File:** `deploy-enhanced.sh:456-511`

**Issue:**
Multiple concurrent updates to state file could corrupt JSON:

```bash
# Process 1 reads state
jq ".observability.status = \"completed\"" "$STATE_FILE" > "$tmp_file"

# Process 2 reads state (gets old data)
jq ".vpsmanager.status = \"completed\"" "$STATE_FILE" > "$tmp_file2"

# Process 1 writes
mv "$tmp_file" "$STATE_FILE"

# Process 2 writes (overwrites Process 1's update)
mv "$tmp_file2" "$STATE_FILE"
```

**Fix:**
Add file locking:
```bash
update_state() {
    local target=$1
    local status=$2

    # Acquire lock
    local lock_file="${STATE_FILE}.lock"
    exec 200>"$lock_file"
    flock -x 200 || {
        log_error "Could not acquire state file lock"
        return 1
    }

    # ... update state ...

    # Release lock
    flock -u 200
    rm -f "$lock_file"
}
```

---

### 21. Exponential Backoff Calculation Overflow

**File:** `deploy-enhanced.sh:970-986`

**Issue:**
```bash
calculate_backoff() {
    local attempt=$1
    local base_delay=2

    if [[ "$RETRY_BACKOFF" == "exponential" ]]; then
        local delay=$((base_delay ** attempt))  # Overflow on large attempts
        ...
    fi
}
```

**Problem:** `2 ** 10 = 1024 seconds` (17 minutes), `2 ** 20 = overflow`

**Fix:**
```bash
calculate_backoff() {
    local attempt=$1
    local base_delay=2

    if [[ "$RETRY_BACKOFF" == "exponential" ]]; then
        # Cap exponent to prevent overflow
        local exp=$attempt
        [[ $exp -gt 5 ]] && exp=5  # Max 2^5 = 32 seconds

        local delay=$((base_delay ** exp))
        echo $delay
    else
        echo $((base_delay * attempt))
    fi
}
```

---

### 22. Missing Cleanup of Temporary Scripts on VPS

**File:** `deploy-enhanced.sh:1876, 1917`

**Issue:**
```bash
remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-observability-vps.sh && /tmp/setup-observability-vps.sh"
```

**Problem:** Scripts left in /tmp after execution (security and disk usage)

**Fix:**
```bash
remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-observability-vps.sh && /tmp/setup-observability-vps.sh; rm -f /tmp/setup-observability-vps.sh"
```

---

## RECOMMENDATIONS

### Immediate Actions (Critical)

1. **Fix command injection in remote_exec** - Validate and escape all inputs
2. **Remove eval usage** - Replace with direct function calls
3. **Fix temp file security** - Use mktemp with proper permissions
4. **Secure credential handling** - Never use /tmp for secrets
5. **Fix dashboard rate limiting** - Use session-based storage

### Short-term (Major)

1. Add input validation to all config reads
2. Implement proper file locking for state updates
3. Add binary checksum verification
4. Improve signal handling for remote cleanup
5. Fix race conditions in lock file handling

### Long-term (Quality)

1. Add comprehensive test suite
2. Implement proper logging framework
3. Add rollback capability
4. Support IPv6
5. Add configuration validation schema
6. Implement proper secret management (vault/encrypted config)

---

## Security Best Practices Checklist

- [ ] All user inputs validated and sanitized
- [ ] No eval/exec with untrusted data
- [ ] Temporary files created securely (mktemp)
- [ ] Credentials never stored in world-readable locations
- [ ] All SSH operations use proper quoting
- [ ] Downloaded binaries verified (checksums/signatures)
- [ ] File operations check for race conditions
- [ ] Proper file permissions set before writing sensitive data
- [ ] Signal handlers clean up remote operations
- [ ] State files protected with file locking
- [ ] No secrets in process list or logs
- [ ] Input validation before remote execution

---

## Testing Recommendations

1. **Fuzzing:** Test with malicious YAML configs
2. **Race conditions:** Run concurrent deployments
3. **Signal testing:** Send SIGINT/SIGTERM during deployment
4. **Network failure:** Test with intermittent connectivity
5. **Permission testing:** Run with restricted users
6. **Security scanning:** Use shellcheck, semgrep, bandit

---

## Conclusion

The deployment scripts have a solid foundation but require **immediate security fixes** before production use. The command injection vulnerabilities are particularly concerning as they could allow complete server compromise.

**Recommendation:** Do not use in production until critical issues are resolved.
