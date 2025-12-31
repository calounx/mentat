# Critical Fixes Quick Reference

**For:** Immediate deployment system debugging
**Priority:** Address these 8 critical issues FIRST

---

## 1. SSH TIMEOUT - Prevent Infinite Hangs

**File:** `deploy-enhanced.sh:1008-1044`

**Problem:** SSH connections hang forever if network drops

**Quick Fix:**
```bash
# In remote_exec() function, add these SSH options:
ssh -o ConnectTimeout=10 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$key_path" \
    -p "$port" \
    "${user}@${host}" \
    -- "$cmd"

# Wrap entire call with timeout
timeout 300 ssh [options...]  # 5 minute max per command
```

**Test:**
```bash
# Simulate network drop during deployment
sudo iptables -A OUTPUT -p tcp --dport 22 -j DROP
# Script should fail within 30 seconds, not hang forever
```

---

## 2. DOWNLOAD CORRUPTION - Verify File Integrity

**File:** `scripts/setup-observability-vps.sh:193-246`

**Problem:** Partial downloads not detected, corrupt binaries installed

**Quick Fix:**
```bash
# Add checksum verification after each download
download_and_verify() {
    local url="$1"
    local filename="$2"
    local expected_sha256="$3"

    # Remove any partial downloads first
    rm -f "/tmp/${filename}" "/tmp/${filename}.partial"

    # Download to temp file
    if ! wget --timeout=60 --tries=3 -O "/tmp/${filename}.partial" "$url"; then
        log_error "Download failed: $url"
        rm -f "/tmp/${filename}.partial"
        return 1
    fi

    # Verify checksum
    local actual_sha256=$(sha256sum "/tmp/${filename}.partial" | awk '{print $1}')
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        log_error "Checksum mismatch for $filename"
        log_error "Expected: $expected_sha256"
        log_error "Got:      $actual_sha256"
        rm -f "/tmp/${filename}.partial"
        return 1
    fi

    # Atomic rename
    mv "/tmp/${filename}.partial" "/tmp/${filename}"
    log_success "Downloaded and verified: $filename"
}
```

**Get checksums:**
```bash
# Add to version detection
curl -s "https://github.com/prometheus/prometheus/releases/download/v2.54.1/sha256sums.txt"
```

---

## 3. COMMAND INJECTION - Fix eval() Security Hole

**File:** `deploy-enhanced.sh:1140,1159`

**Problem:** `eval "$command_to_retry"` allows command injection

**Quick Fix:**
```bash
# BEFORE (DANGEROUS):
retry_with_healing() {
    if eval "$command_to_retry"; then  # ← VULNERABLE!
        return 0
    fi
}

# AFTER (SAFE):
retry_with_healing() {
    local operation_name="$1"
    local command_func="$2"  # Function name, NOT string
    local autofix_func="${3:-}"

    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        # Call function directly - no eval!
        if "$command_func"; then
            return 0
        fi

        # Auto-fix
        if [[ -n "$autofix_func" ]]; then
            "$autofix_func"  # Direct call, no eval
        fi

        ((attempt++))
    done
}

# Usage:
# OLD: retry_with_healing "test" "remote_exec '$host' '$cmd'"
# NEW: retry_with_healing "test" test_connection_func
```

---

## 4. CONCURRENT DEPLOYMENT - Fix Race Condition

**File:** `deploy-enhanced.sh:268-287`

**Problem:** Two deployments can run simultaneously (lock race condition)

**Quick Fix:**
```bash
# Use flock instead of PID file
acquire_lock() {
    LOCK_FILE="${STATE_DIR}/deploy.lock"
    mkdir -p "$STATE_DIR"

    # Open lock file on FD 200
    exec 200>"$LOCK_FILE"

    # Try to acquire exclusive lock (non-blocking)
    if ! flock -n 200; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        log_error "Another deployment is running (PID: $pid)"
        log_error "Remove $LOCK_FILE if deployment is not actually running"
        exit 1
    fi

    # Write our PID (we have exclusive lock)
    echo $$ >&200
    log_success "Acquired deployment lock"
}

release_lock() {
    flock -u 200 2>/dev/null || true
    exec 200>&- 2>/dev/null || true
}

# Add to trap
trap 'release_lock; cleanup' EXIT
```

**Test:**
```bash
# Start two deployments simultaneously
./deploy-enhanced.sh all &
./deploy-enhanced.sh all &
# Second should fail immediately with lock error
```

---

## 5. DISK SPACE - Check Before Downloads

**File:** `scripts/setup-observability-vps.sh:182-189`

**Problem:** Only checks /tmp, not total space needed

**Quick Fix:**
```bash
check_disk_space_comprehensive() {
    log_info "Checking disk space..."

    # Requirements (MB)
    local downloads=200      # All downloads
    local extraction=500     # Peak extraction
    local installation=1000  # Final install
    local buffer=500         # Safety margin
    local required=$((downloads + extraction + buffer))

    # Check /tmp
    local tmp_free=$(df -BM /tmp | tail -1 | awk '{print $4}' | sed 's/M//')
    if [[ $tmp_free -lt $required ]]; then
        log_error "Insufficient /tmp space: ${tmp_free}MB (need ${required}MB)"

        # Try cleanup
        log_info "Cleaning old downloads..."
        sudo rm -rf /tmp/prometheus-* /tmp/loki-* /tmp/node_exporter-* /tmp/alertmanager-*
        tmp_free=$(df -BM /tmp | tail -1 | awk '{print $4}' | sed 's/M//')

        if [[ $tmp_free -lt $required ]]; then
            log_error "Still insufficient after cleanup: ${tmp_free}MB"
            return 1
        fi
    fi

    # Check /opt
    local opt_free=$(df -BM /opt | tail -1 | awk '{print $4}' | sed 's/M//')
    if [[ $opt_free -lt $installation ]]; then
        log_error "Insufficient /opt space: ${opt_free}MB (need ${installation}MB)"
        return 1
    fi

    log_success "Disk space OK: /tmp=${tmp_free}MB /opt=${opt_free}MB"
}

# Call BEFORE any downloads
check_disk_space_comprehensive
```

---

## 6. PORT 22 PROTECTION - Never Kill SSH

**File:** `lib/deploy-common.sh:264-297`

**Problem:** cleanup_port_conflicts() kills ANY process, including SSH

**Quick Fix:**
```bash
cleanup_port_conflicts() {
    local ports=("$@")

    # NEVER touch these ports
    local protected_ports=(22 25 465 587)

    for port in "${ports[@]}"; do
        # Check if protected
        if [[ " ${protected_ports[@]} " =~ " ${port} " ]]; then
            log_error "Port $port is protected (critical service)"
            log_error "Cannot automatically free this port"
            return 1
        fi

        local pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)

        if [[ -n "$pids" ]]; then
            # Show what will be killed
            log_warn "Port $port used by:"
            sudo lsof -i ":$port" | tail -n +2

            # Confirm in interactive mode
            if [[ "$AUTO_APPROVE" != "true" ]]; then
                read -p "Kill these processes? (y/N) " confirm
                [[ "$confirm" != "y" ]] && return 1
            fi

            # Kill
            echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
            sleep 2

            # Force kill if needed
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            [[ -n "$pids" ]] && echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
        fi
    done
}
```

---

## 7. MARIADB PASSWORD - Secure Temp Files

**File:** `scripts/setup-vpsmanager-vps.sh:463-468`

**Problem:** Password written to temp file with wrong permissions

**Quick Fix:**
```bash
# WRONG - password exposed during write:
cat > "$MYSQL_CNF_FILE" << EOF
[client]
password=${MYSQL_ROOT_PASSWORD}
EOF

# RIGHT - secure before writing:
MYSQL_CNF_FILE=$(mktemp)
chmod 600 "$MYSQL_CNF_FILE"  # Secure BEFORE writing

cat > "$MYSQL_CNF_FILE" << EOF
[client]
password=${MYSQL_ROOT_PASSWORD}
EOF

# Even better - use umask:
(
    umask 077  # Files created with 600 permissions
    cat > "$MYSQL_CNF_FILE" << EOF
[client]
password=${MYSQL_ROOT_PASSWORD}
EOF
)

# CRITICAL: Always shred after use
shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"
```

---

## 8. NETWORK RETRY - GitHub API Failures

**File:** `lib/deploy-common.sh:141-183`

**Problem:** No retry on transient network failures

**Quick Fix:**
```bash
get_github_version() {
    local component="$1"
    local repo="$2"
    local fallback="$3"
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        local response
        local http_code

        # Get both response and HTTP status
        response=$(curl -w "\n%{http_code}" \
                       --connect-timeout 10 \
                       --max-time 30 \
                       -s \
                       "https://api.github.com/repos/${repo}/releases/latest")

        http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n-1)

        case "$http_code" in
            200)
                local version=$(echo "$body" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
                if [[ -n "$version" ]]; then
                    echo "$version"
                    return 0
                fi
                ;;
            403)
                log_warn "GitHub API rate limit (attempt $((retry+1))/$max_retries)"
                ;;
            404)
                log_error "Repository not found: $repo"
                break
                ;;
            *)
                log_warn "GitHub API error: HTTP $http_code (attempt $((retry+1))/$max_retries)"
                ;;
        esac

        ((retry++))
        [[ $retry -lt $max_retries ]] && sleep $((retry * 2))
    done

    log_warn "Using fallback version: $fallback"
    echo "$fallback"
}
```

---

## Verification Checklist

After applying fixes:

- [ ] SSH timeout: Test with `iptables -A OUTPUT -p tcp --dport 22 -j DROP`
- [ ] Download integrity: Corrupt a download file manually, verify detection
- [ ] Command injection: Test with malicious inventory.yaml
- [ ] Concurrent lock: Start two deployments simultaneously
- [ ] Disk space: Fill /tmp to 90%, verify error before download
- [ ] Port protection: Configure port 22 in cleanup, verify rejection
- [ ] Password security: Check file permissions during deployment
- [ ] Network retry: Disconnect network during GitHub API call

---

## Emergency Rollback

If deployment fails mid-way:

```bash
# Stop all services
sudo systemctl stop prometheus loki grafana alertmanager nginx

# Remove lock file
rm -f /home/calounx/repositories/mentat/chom/deploy/.deploy-state/deploy.lock

# Clean temporary files
sudo rm -rf /tmp/prometheus-* /tmp/loki-* /tmp/node_exporter-*

# Reset state
rm -f /home/calounx/repositories/mentat/chom/deploy/.deploy-state/deployment.state

# Try again
./deploy-enhanced.sh --validate
./deploy-enhanced.sh all
```

---

## Debug Commands

```bash
# Check deployment state
cat /home/calounx/repositories/mentat/chom/deploy/.deploy-state/deployment.state | jq .

# Check lock status
cat /home/calounx/repositories/mentat/chom/deploy/.deploy-state/deploy.lock

# Check active SSH connections
ss -tnp | grep :22

# Check disk space
df -h /tmp /opt

# Check running processes
ps aux | grep -E 'prometheus|loki|grafana'

# Check port conflicts
sudo lsof -i :80 -i :443 -i :3000 -i :9090

# Check logs
journalctl -u prometheus -u grafana -n 50 --no-pager

# Validate SSH connection
ssh -v -i ./keys/chom_deploy_key -p 22 deploy@YOUR_IP "echo 'SSH OK'"
```

---

## Priority Order

Fix in this order for maximum impact:

1. **SSH Timeout** (prevents hangs - critical for reliability)
2. **Concurrent Lock** (prevents dual deployments - critical for safety)
3. **Command Injection** (security vulnerability - critical for security)
4. **Disk Space** (prevents partial installs - high impact)
5. **Download Integrity** (prevents corrupt binaries - high impact)
6. **Port Protection** (prevents SSH lockout - high impact)
7. **Network Retry** (improves reliability - medium impact)
8. **Password Security** (security hardening - medium impact)

Estimated time: 4-6 hours for all 8 fixes + testing
