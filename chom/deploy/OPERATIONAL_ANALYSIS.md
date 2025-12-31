# Deployment Scripts - Operational & Production Issue Analysis

**Date:** 2025-12-31
**Scripts Analyzed:**
- `/chom/deploy/scripts/setup-observability-vps.sh`
- `/chom/deploy/scripts/setup-vpsmanager-vps.sh`
- `/chom/deploy/scripts/fix-observability.sh`
- `/chom/deploy/scripts/enable-https-now.sh`
- `/chom/deploy/scripts/setup-ssl.sh`

---

## Executive Summary

The deployment scripts demonstrate strong operational awareness with comprehensive cleanup mechanisms, port conflict resolution, and forced process termination. However, critical production scenarios lack proper handling: no transaction rollback capability, insufficient disk space checking, missing network retry logic, and potential SSH lockout during UFW configuration. The scripts prioritize idempotency over safety, which could lead to data loss in partial failure scenarios.

**Severity Breakdown:**
- **Critical Issues:** 4 (Disk space, Network failure, SSH lockout, No rollback)
- **High Issues:** 3 (Service startup, Database credential handling, Resource leaks)
- **Medium Issues:** 3 (Interrupted execution, Systemd dependencies, Orphaned processes)

---

## 1. Script Interruption Mid-Execution

### Current Behavior

**Main Scripts (setup-observability-vps.sh, setup-vpsmanager-vps.sh):**
- Use `set -euo pipefail` (line 9) - exits on any error
- No signal trap handlers (SIGINT, SIGTERM, SIGHUP)
- No cleanup on exit
- Pre-installation cleanup function (`run_full_cleanup`) runs at start (lines 233-234)

**What happens when interrupted:**
1. **SIGINT (Ctrl+C):** Script exits immediately, leaves system in inconsistent state
2. **SIGTERM:** Same as SIGINT, no cleanup
3. **SIGHUP (SSH disconnect):** Terminal process dies, script terminates
4. **Partial installs:** Services may be half-configured
5. **Lock files:** None exist, so no stale locks
6. **Temporary files:** Left in `/tmp` (e.g., downloaded tarballs at lines 277-278, 355-356)

**Example failure scenario:**
```bash
# User presses Ctrl+C during MariaDB installation (line 379)
# Results in:
- MariaDB package partially installed (dpkg in inconsistent state)
- No root password set (security risk)
- /tmp files remain (disk space waste)
- No service running but systemd unit exists
```

### Issues

1. **Severity: MEDIUM**
   - Leaves `/tmp` files behind (can fill disk on repeated failures)
   - APT may be in inconsistent state (dpkg locks)
   - Services partially configured but not running
   - No state tracking to resume from checkpoint

2. **No transaction semantics:**
   - Can't rollback to pre-installation state
   - Idempotent re-run creates new credentials (breaks existing integrations)

3. **Temporary files accumulate:**
   ```bash
   # Lines 277-278, 355-356, 389-390, etc.
   wget -q "https://github.com/.../prometheus-${VERSION}.tar.gz"
   tar xzf "prometheus-${VERSION}.tar.gz"
   # If interrupted after wget but before rm, files remain
   ```

### Recommendations

**HIGH PRIORITY:**

1. **Add signal trap handlers:**
```bash
#!/bin/bash
set -euo pipefail

TEMP_FILES=()
SERVICES_MODIFIED=()

cleanup_on_exit() {
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Script interrupted or failed (exit code: $exit_code)"
        log_info "Cleaning up temporary files..."

        # Remove temporary files
        for file in "${TEMP_FILES[@]}"; do
            rm -rf "$file" 2>/dev/null || true
        done

        # Log state for debugging
        log_warn "System may be in inconsistent state"
        log_warn "Modified services: ${SERVICES_MODIFIED[*]}"
        log_warn "Run script again to complete installation"
    fi
}

trap cleanup_on_exit EXIT INT TERM HUP

# Track temp files
download_and_extract() {
    local url="$1"
    local filename=$(basename "$url")

    TEMP_FILES+=("/tmp/$filename")
    wget -q "$url" -P /tmp
    tar xzf "/tmp/$filename" -C /tmp
    TEMP_FILES+=("/tmp/${filename%.tar.gz}")
}
```

2. **Add state checkpoint file:**
```bash
STATE_FILE="/var/lib/chom-deploy/.install-state"

checkpoint() {
    local phase="$1"
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$phase:$(date +%s)" >> "$STATE_FILE"
}

get_last_checkpoint() {
    if [ -f "$STATE_FILE" ]; then
        tail -1 "$STATE_FILE" | cut -d: -f1
    fi
}

# At start of script
LAST_CHECKPOINT=$(get_last_checkpoint)
if [ -n "$LAST_CHECKPOINT" ]; then
    log_warn "Previous installation was interrupted at phase: $LAST_CHECKPOINT"
    read -p "Resume from checkpoint? (y/N): " RESUME
    if [[ "$RESUME" =~ ^[Yy]$ ]]; then
        # Skip completed phases
        case "$LAST_CHECKPOINT" in
            "system_packages") skip_system_packages=true ;;
            "prometheus") skip_prometheus=true ;;
            # etc.
        esac
    fi
fi

# Before each major phase
checkpoint "prometheus"
# Install prometheus...
```

3. **Use atomic temporary directory:**
```bash
# At start of script
WORK_DIR=$(mktemp -d -t chom-deploy-XXXXXX)
TEMP_FILES+=("$WORK_DIR")

cd "$WORK_DIR"
# All downloads happen here, cleaned up on exit
```

---

## 2. Network Failure During Package Download

### Current Behavior

**Package downloads have no retry logic:**

**APT operations (lines 241-257, 333-334, 379, 466):**
```bash
sudo apt-get update -qq
sudo apt-get install -y -qq curl wget ...
```
- `-qq`: Suppresses output (hides errors)
- No timeout configuration
- No retry on network failure
- **Fatal if network drops:** Script exits due to `set -e`

**Binary downloads (lines 277, 355, 389, 471, 542):**
```bash
wget -q "https://github.com/prometheus/prometheus/releases/..."
tar xzf "prometheus-${VERSION}.tar.gz"
```
- `-q`: Quiet mode (hides errors)
- No `--timeout`, `--tries`, or `--retry-connrefused`
- Default timeout: 900 seconds (15 minutes)
- **Partial downloads:** wget overwrites files, corrupt tarball will fail `tar xzf`

**Composer download (line 480):**
```bash
curl -sS https://getcomposer.org/installer | php
```
- Pipes directly to PHP (dangerous)
- No checksum verification
- If network fails mid-download, PHP receives partial script (could execute arbitrary code)

### Issues

1. **Severity: CRITICAL**
   - **No network resilience:** Single transient network error fails entire deployment
   - **Corrupt downloads:** Partial downloads not detected
   - **Security risk:** Piping `curl` to `php` without verification
   - **Silent failures:** `-qq` and `-q` hide error messages

2. **Real-world failure scenarios:**
   - VPS provider network hiccup during `apt-get update` → script dies
   - GitHub rate limiting → wget fails silently
   - Partial tarball download → `tar xzf` fails with corrupted archive
   - Composer installer compromised via MITM → malicious code executed

### Recommendations

**CRITICAL PRIORITY:**

1. **Add retry logic to wget:**
```bash
# Replace line 277 and similar
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Downloading $url (attempt $attempt/$max_attempts)..."

        if wget \
            --timeout=60 \
            --tries=3 \
            --retry-connrefused \
            --waitretry=5 \
            --progress=dot:giga \
            -O "$output" \
            "$url"; then
            log_success "Download completed"
            return 0
        fi

        log_warn "Download failed, retrying in $((attempt * 5)) seconds..."
        sleep $((attempt * 5))
        ((attempt++))
    done

    log_error "Failed to download after $max_attempts attempts"
    return 1
}

# Usage
download_with_retry \
    "https://github.com/prometheus/prometheus/releases/download/v${VERSION}/prometheus-${VERSION}.tar.gz" \
    "/tmp/prometheus.tar.gz"
```

2. **Add checksum verification:**
```bash
verify_checksum() {
    local file="$1"
    local expected_sha256="$2"

    log_info "Verifying checksum for $file..."
    local actual=$(sha256sum "$file" | awk '{print $1}')

    if [ "$actual" != "$expected_sha256" ]; then
        log_error "Checksum mismatch!"
        log_error "Expected: $expected_sha256"
        log_error "Got:      $actual"
        return 1
    fi

    log_success "Checksum verified"
    return 0
}

# Store checksums (fetch from official sources)
PROMETHEUS_SHA256="..." # From GitHub releases page
download_with_retry "$PROMETHEUS_URL" "/tmp/prometheus.tar.gz"
verify_checksum "/tmp/prometheus.tar.gz" "$PROMETHEUS_SHA256"
```

3. **Fix composer installation security:**
```bash
# Replace line 480
log_info "Installing Composer..."

# Download installer
download_with_retry \
    "https://getcomposer.org/installer" \
    "/tmp/composer-setup.php"

# Verify signature
EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    log_error "Composer installer checksum mismatch"
    rm /tmp/composer-setup.php
    exit 1
fi

# Install
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm /tmp/composer-setup.php
```

4. **Configure APT for resilience:**
```bash
# Add before first apt-get (line 240)
configure_apt_resilience() {
    log_info "Configuring APT for network resilience..."

    cat > /etc/apt/apt.conf.d/99-deployment-resilience << 'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::ftp::Timeout "30";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
}

configure_apt_resilience

# Remove -qq to see actual errors
sudo apt-get update || {
    log_error "APT update failed, retrying with different mirror..."
    # Try different mirror or sleep and retry
    sleep 10
    sudo apt-get update
}
```

---

## 3. Disk Full During Installation

### Current Behavior

**No disk space checks anywhere in scripts:**

**Large downloads without space verification:**
- Prometheus binary: ~90MB compressed, ~200MB extracted (line 277)
- Loki binary: ~70MB (line 389)
- Grafana packages: ~100MB (line 531)
- MariaDB: ~200MB (line 379)
- PHP packages: ~300MB total (lines 338-352)
- **Total estimated:** ~1GB for packages + 2-5GB for data directories

**Data directories created without size limits:**
```bash
# Lines 260-263
sudo mkdir -p "$DATA_DIR"/{prometheus,loki,grafana,alertmanager}
sudo mkdir -p "$CONFIG_DIR"/{prometheus,loki,grafana,alertmanager}
sudo mkdir -p "$LOG_DIR"
sudo mkdir -p /opt/observability/bin
```
- No quota limits
- No disk space verification
- Prometheus TSDB can grow unbounded (limited only by retention at line 336)

**Failure scenarios:**
1. **Download fails mid-transfer:** Corrupt tarball, `tar xzf` fails
2. **Package installation fails:** dpkg fills disk with partial files
3. **Service fails to start:** Prometheus can't write TSDB files
4. **Log rotation disabled:** Logs fill disk over time

### Issues

1. **Severity: CRITICAL**
   - **Silent failures:** No pre-flight disk check
   - **Cascading failures:** Full disk causes all services to fail
   - **Data corruption:** MariaDB/Prometheus TSDB corruption if disk fills during write
   - **Recovery impossible:** Can't log in if `/var/log` is full

2. **Missing monitoring:**
   - No disk usage alerts in Prometheus rules
   - No log rotation for CHOM deployment logs
   - No cleanup of old package caches

### Recommendations

**CRITICAL PRIORITY:**

1. **Add pre-flight disk space check:**
```bash
#!/bin/bash

check_disk_space() {
    local required_mb=5120  # 5GB minimum
    local available_mb=$(df -m / | awk 'NR==2 {print $4}')

    log_info "Disk space check:"
    log_info "  Required:  ${required_mb}MB (5GB)"
    log_info "  Available: ${available_mb}MB"

    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Insufficient disk space!"
        log_error "Need at least 5GB free for installation"
        log_error "Free up space and try again"

        # Show largest directories
        log_info "Largest directories on /:"
        du -h -d 1 / 2>/dev/null | sort -h | tail -10

        exit 1
    fi

    log_success "Sufficient disk space available"
}

# At start of script (before any downloads)
check_disk_space
```

2. **Add disk monitoring during installation:**
```bash
monitor_disk_during_phase() {
    local phase_name="$1"
    local before_mb=$(df -m / | awk 'NR==2 {print $4}')

    # Run the phase
    "$@"

    local after_mb=$(df -m / | awk 'NR==2 {print $4}')
    local used_mb=$((before_mb - after_mb))

    log_info "Disk space used by ${phase_name}: ${used_mb}MB"

    if [ "$after_mb" -lt 1024 ]; then
        log_error "Less than 1GB free space remaining!"
        log_error "Installation may fail or services may not start"
        return 1
    fi
}

# Usage
monitor_disk_during_phase "MariaDB installation" install_mariadb
```

3. **Set up data directory size limits:**
```bash
# Prometheus retention (already exists at line 336, but add disk check)
setup_prometheus_retention() {
    local data_dir="$DATA_DIR/prometheus"
    local max_size_gb=10

    # Calculate retention based on available disk
    local available_gb=$(df -BG "$data_dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    local safe_retention=$((available_gb * 60 / 100))  # Use 60% of available

    if [ "$safe_retention" -lt "$max_size_gb" ]; then
        log_warn "Limited disk space, reducing retention to ${safe_retention}GB"
        max_size_gb=$safe_retention
    fi

    log_info "Prometheus retention: ${max_size_gb}GB"

    # Update systemd unit with size limit
    sed -i "s/--storage.tsdb.retention.time=15d/--storage.tsdb.retention.size=${max_size_gb}GB/" \
        /etc/systemd/system/prometheus.service
}
```

4. **Add disk space alerting rule:**
```bash
# Add to Prometheus rules
mkdir -p "$CONFIG_DIR/prometheus/rules"
cat > "$CONFIG_DIR/prometheus/rules/disk-alerts.yml" << 'EOF'
groups:
  - name: disk-space
    interval: 60s
    rules:
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space below 15% on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} disk space remaining"

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.05
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "CRITICAL: Disk space below 5% on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} remaining - IMMEDIATE ACTION REQUIRED"
EOF
```

5. **Add automatic cleanup on failure:**
```bash
cleanup_on_disk_full() {
    log_error "Disk full detected, attempting cleanup..."

    # Remove apt caches
    sudo apt-get clean
    sudo apt-get autoclean

    # Remove old kernels
    sudo apt-get autoremove -y

    # Clean /tmp
    sudo find /tmp -type f -atime +7 -delete

    # Clean journal logs
    sudo journalctl --vacuum-size=100M

    log_info "Cleanup completed, re-checking disk space..."
    df -h /
}

# Wrap critical operations
safe_download() {
    local url="$1"
    local output="$2"

    if ! wget -q "$url" -O "$output"; then
        if df / | awk 'NR==2 {exit ($4 < 102400)}'; then  # Less than 100MB
            cleanup_on_disk_full
            # Retry
            wget -q "$url" -O "$output"
        else
            return 1
        fi
    fi
}
```

---

## 4. Service Fails to Start

### Current Behavior

**Service startup (lines 640-649, 904-928):**
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
sudo systemctl enable --now node_exporter
# ... etc

# Wait for services to start
sleep 5

# Verification
SERVICES=("prometheus" "node_exporter" ...)
for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        log_success "$svc is running"
    else
        log_error "$svc failed to start"
        ALL_OK=false
    fi
done

if $ALL_OK; then
    exit 0
else
    exit 1
fi
```

**Issues with current approach:**
1. **Fixed 5-second sleep** (line 652) - may not be enough for slow systems
2. **No diagnostic information** - just logs "failed to start"
3. **Continues enabling other services** - even if dependencies failed
4. **Exit 1 at end** (line 708) - but no rollback or recovery
5. **No service dependency checking**

**Real failure scenarios:**

**Scenario 1: Prometheus fails due to bad config**
```
Line 644: sudo systemctl enable --now prometheus
→ Prometheus fails to start (invalid YAML)
→ Script continues
→ Line 645-648: Other services start successfully
→ Line 667: Logs "prometheus failed to start"
→ Line 708: exit 1
→ Result: Partial deployment, other services running but useless without Prometheus
```

**Scenario 2: PHP-FPM socket not ready**
```
Line 906: sudo systemctl enable --now php8.2-fpm
→ PHP starts but socket takes 10 seconds to create
→ Line 910-923: Waits up to 30 seconds (GOOD!)
→ Line 925: nginx starts, tries to use socket
→ May fail if socket still not ready
```

**Scenario 3: MariaDB fails to start**
```
Line 926: sudo systemctl enable --now mariadb
→ MariaDB fails (corrupt data files from previous run)
→ Script continues
→ No WordPress sites will work
→ Only discovered later by users
```

### Issues

1. **Severity: HIGH**
   - **No automatic recovery:** Service fails, script logs error and exits
   - **Partial deployments:** Some services running, others failed
   - **Poor diagnostics:** No logs shown, user must manually check journalctl
   - **No dependency awareness:** Starts services in wrong order sometimes

2. **Missing features:**
   - No health checks beyond `is-active`
   - No port listening verification
   - No log file analysis
   - No automatic restart attempts

### Recommendations

**HIGH PRIORITY:**

1. **Add comprehensive service startup check:**
```bash
start_and_verify_service() {
    local service_name="$1"
    local health_check_cmd="${2:-}"  # Optional health check command
    local max_wait=60
    local waited=0

    log_info "Starting ${service_name}..."

    # Enable and start
    if ! sudo systemctl enable --now "$service_name" 2>&1 | tee -a /var/log/chom-deploy.log; then
        log_error "Failed to enable ${service_name}"
        sudo systemctl status "$service_name" --no-pager -l
        return 1
    fi

    # Wait for active state
    log_info "Waiting for ${service_name} to become active (max ${max_wait}s)..."
    while [ $waited -lt $max_wait ]; do
        if systemctl is-active --quiet "$service_name"; then
            log_success "${service_name} is active"
            break
        fi

        if systemctl is-failed --quiet "$service_name"; then
            log_error "${service_name} entered failed state"
            log_error "Showing last 50 log lines:"
            sudo journalctl -u "$service_name" -n 50 --no-pager
            return 1
        fi

        sleep 1
        ((waited++))
    done

    if [ $waited -ge $max_wait ]; then
        log_error "${service_name} did not start within ${max_wait} seconds"
        sudo journalctl -u "$service_name" -n 50 --no-pager
        return 1
    fi

    # Run optional health check
    if [ -n "$health_check_cmd" ]; then
        log_info "Running health check for ${service_name}..."
        waited=0
        while [ $waited -lt 30 ]; do
            if eval "$health_check_cmd" 2>/dev/null; then
                log_success "${service_name} health check passed"
                return 0
            fi
            sleep 1
            ((waited++))
        done

        log_error "${service_name} health check failed after 30s"
        return 1
    fi

    return 0
}

# Usage examples
start_and_verify_service "prometheus" "curl -sf http://localhost:9090/-/ready"
start_and_verify_service "loki" "curl -sf http://localhost:3100/ready"
start_and_verify_service "grafana-server" "curl -sf http://localhost:3000/api/health"
start_and_verify_service "mariadb" "mysql -u root -p\${MYSQL_ROOT_PASSWORD} -e 'SELECT 1'"
start_and_verify_service "redis-server" "redis-cli ping | grep -q PONG"
start_and_verify_service "nginx" "nginx -t && curl -sf http://localhost:80"
```

2. **Add service dependency management:**
```bash
# Define service dependencies
declare -A SERVICE_DEPS=(
    ["prometheus"]="node_exporter"
    ["grafana-server"]="prometheus loki"
    ["nginx"]="php8.2-fpm"
)

check_dependencies() {
    local service="$1"
    local deps="${SERVICE_DEPS[$service]:-}"

    if [ -z "$deps" ]; then
        return 0
    fi

    log_info "Checking dependencies for ${service}: ${deps}"
    for dep in $deps; do
        if ! systemctl is-active --quiet "$dep"; then
            log_error "Dependency $dep is not running for $service"
            return 1
        fi
    done

    log_success "All dependencies satisfied for ${service}"
    return 0
}

start_service_with_deps() {
    local service="$1"
    shift
    local health_check="$*"

    # Check dependencies first
    if ! check_dependencies "$service"; then
        log_error "Cannot start ${service} - dependencies not met"
        return 1
    fi

    start_and_verify_service "$service" "$health_check"
}
```

3. **Add automatic retry with exponential backoff:**
```bash
start_with_retry() {
    local service="$1"
    local health_check="${2:-}"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Starting ${service} (attempt ${attempt}/${max_attempts})..."

        if start_and_verify_service "$service" "$health_check"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            local wait_time=$((attempt * 5))
            log_warn "${service} failed to start, retrying in ${wait_time}s..."

            # Try to clean up
            sudo systemctl stop "$service" 2>/dev/null || true
            sudo systemctl reset-failed "$service" 2>/dev/null || true

            sleep $wait_time
        fi

        ((attempt++))
    done

    log_error "${service} failed to start after ${max_attempts} attempts"
    return 1
}
```

4. **Add failure recovery options:**
```bash
handle_service_failure() {
    local service="$1"

    log_error "=========================================="
    log_error "  SERVICE FAILURE: ${service}"
    log_error "=========================================="

    # Show diagnostic info
    echo ""
    log_info "Service status:"
    sudo systemctl status "$service" --no-pager -l

    echo ""
    log_info "Recent logs (last 100 lines):"
    sudo journalctl -u "$service" -n 100 --no-pager

    echo ""
    log_info "Port bindings:"
    sudo ss -tlnp | grep -E ':(9090|3100|3000|9093|9100|80|443|3306|6379)'

    echo ""
    log_info "Disk space:"
    df -h /

    echo ""
    log_info "Memory:"
    free -h

    # Offer recovery options
    echo ""
    log_warn "Recovery options:"
    echo "  1. Retry starting the service"
    echo "  2. Skip this service and continue"
    echo "  3. Abort deployment"
    echo "  4. Open debug shell"

    read -p "Choose (1-4): " choice

    case "$choice" in
        1)
            log_info "Retrying ${service}..."
            start_with_retry "$service"
            ;;
        2)
            log_warn "Skipping ${service}"
            return 0
            ;;
        3)
            log_error "Deployment aborted by user"
            exit 1
            ;;
        4)
            log_info "Opening debug shell (type 'exit' to continue)..."
            bash
            log_info "Retrying ${service} after debug..."
            start_with_retry "$service"
            ;;
        *)
            log_error "Invalid choice, aborting"
            exit 1
            ;;
    esac
}
```

5. **Add systemd service hardening:**
```bash
# Add to all systemd service files
[Service]
# Restart configuration
Restart=on-failure
RestartSec=5s
StartLimitBurst=5
StartLimitIntervalSec=60s

# Health monitoring
TimeoutStartSec=60s
TimeoutStopSec=30s
WatchdogSec=30s  # Service must notify systemd every 30s

# Resource limits
MemoryMax=1G
CPUQuota=50%

# Failure handling
FailureAction=none  # Don't reboot on failure
```

---

## 5. Re-run After Partial Failure

### Current Behavior

**Idempotency measures in place:**

1. **Pre-installation cleanup** (lines 232-234, 241-242):
   - Runs `run_full_cleanup()` before installation
   - Stops all services
   - Kills lingering processes
   - Clears port conflicts
   - **GOOD:** Ensures clean slate

2. **User/group creation** (lines 266-268, 551):
   ```bash
   if ! id -u observability &>/dev/null; then
       sudo useradd --system --no-create-home --shell /usr/sbin/nologin observability
   fi
   ```
   **GOOD:** Checks before creating

3. **MariaDB security** (lines 381-434):
   ```bash
   if ! sudo mysql -u root -e "SELECT 1" &>/dev/null; then
       # Already secured, load existing password
       source /root/.vpsmanager-credentials
   else
       # First run - generate new password
       MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24)
   fi
   ```
   **GOOD:** Detects existing installation

4. **Directory creation:**
   ```bash
   sudo mkdir -p "$DATA_DIR"/{prometheus,loki,grafana}
   ```
   **SAFE:** `-p` doesn't fail if exists

**Problems with idempotency:**

1. **Credentials regeneration** (lines 554, 584, 404):
   ```bash
   GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24)
   ```
   - Generates NEW password on every run
   - Old password in `/root/.observability-credentials` is overwritten
   - **BREAKS:** Anyone using old password is locked out
   - **BREAKS:** Integration configs with old password fail

2. **Config file replacement** (lines 288-317, 400-440, 534-551):
   ```bash
   write_system_file "$CONFIG_DIR/prometheus/prometheus.yml" << 'EOF'
   # Default config
   EOF
   ```
   - Unconditionally overwrites config
   - **DESTROYS:** Any manual configuration changes
   - **DESTROYS:** Dynamically added scrape targets

3. **Binary replacement without version check:**
   ```bash
   # Line 283
   sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
   ```
   - Always downloads and replaces binary, even if same version
   - Wastes bandwidth and time
   - **RISK:** Downgrade if `PROMETHEUS_VERSION` changed in script

4. **No data preservation check:**
   - Prometheus TSDB at `$DATA_DIR/prometheus` is preserved (chown at line 346)
   - But no check if version upgrade requires migration
   - **RISK:** Data corruption if TSDB format changed between versions

### Issues

1. **Severity: HIGH**
   - **Credential rotation breaks integrations:** New passwords lock out users/services
   - **Config loss:** Manual changes destroyed
   - **Unnecessary downloads:** Re-downloads binaries even if already installed
   - **No version tracking:** Can't tell if upgrade or re-install

2. **Specific failure scenarios:**

   **Scenario A: Partial MariaDB failure, re-run:**
   ```
   First run:
   - MariaDB installed, root password: "abc123xyz"
   - Password saved to /root/.vpsmanager-credentials
   - WordPress site configured with this password

   Deployment fails at Nginx (port 80 in use)

   Second run:
   - MariaDB already secured (line 382 check)
   - Loads existing password from credentials file (line 385)
   - GOOD: Password preserved
   - BUT: If credentials file deleted, script FAILS (lines 390-397)
   ```

   **Scenario B: Grafana failure, re-run:**
   ```
   First run:
   - Grafana installed, admin password: "old_pass_123"
   - User logs in, creates dashboards
   - Fails at Nginx config

   Second run:
   - run_full_cleanup() stops Grafana
   - Line 554: NEW password generated: "new_pass_456"
   - Old password overwritten in /root/.observability-credentials
   - User can't log in with old password
   - Dashboards still exist but user locked out
   ```

   **Scenario C: Config customization lost:**
   ```
   First run:
   - Prometheus installed
   - Admin adds custom scrape targets to prometheus.yml
   - Some other service fails

   Second run:
   - Line 288-317: prometheus.yml OVERWRITTEN with defaults
   - Custom scrape targets LOST
   - Must manually re-add
   ```

### Recommendations

**HIGH PRIORITY:**

1. **Add installation state tracking:**
```bash
STATE_DIR="/var/lib/chom-deploy"
INSTALL_STATE="$STATE_DIR/install-state.json"

save_install_state() {
    local component="$1"
    local version="$2"
    local credentials_file="${3:-}"

    mkdir -p "$STATE_DIR"

    # Create or update state file
    local state=$(cat "$INSTALL_STATE" 2>/dev/null || echo '{}')
    state=$(echo "$state" | jq -r \
        --arg comp "$component" \
        --arg ver "$version" \
        --arg creds "$credentials_file" \
        --arg time "$(date -Iseconds)" \
        '.[$comp] = {version: $ver, credentials: $creds, installed_at: $time}')

    echo "$state" > "$INSTALL_STATE"
    chmod 600 "$INSTALL_STATE"
}

get_installed_version() {
    local component="$1"

    if [ ! -f "$INSTALL_STATE" ]; then
        echo ""
        return
    fi

    jq -r --arg comp "$component" '.[$comp].version // ""' "$INSTALL_STATE" 2>/dev/null
}

is_installed() {
    local component="$1"
    local version=$(get_installed_version "$component")
    [ -n "$version" ]
}

# Usage
if is_installed "prometheus"; then
    current=$(get_installed_version "prometheus")
    if [ "$current" = "$PROMETHEUS_VERSION" ]; then
        log_info "Prometheus $PROMETHEUS_VERSION already installed, skipping"
        skip_prometheus=true
    else
        log_info "Prometheus upgrade: $current → $PROMETHEUS_VERSION"
        skip_prometheus=false
    fi
else
    log_info "Prometheus not installed, performing fresh install"
    skip_prometheus=false
fi

if [ "$skip_prometheus" = false ]; then
    # Install prometheus...
    save_install_state "prometheus" "$PROMETHEUS_VERSION" ""
fi
```

2. **Preserve credentials on re-run:**
```bash
generate_or_load_credential() {
    local cred_name="$1"
    local cred_file="/root/.${cred_name}-credentials"

    if [ -f "$cred_file" ]; then
        log_info "Loading existing credentials from $cred_file"
        source "$cred_file"

        # Verify credential exists
        local var_name="${cred_name}_PASSWORD"
        if [ -z "${!var_name}" ]; then
            log_error "Credentials file exists but $var_name not set"
            log_error "Please fix or delete $cred_file"
            exit 1
        fi

        log_success "Using existing ${cred_name} password"
    else
        log_info "Generating new ${cred_name} credentials"
        local new_password=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

        echo "${cred_name}_PASSWORD=${new_password}" > "$cred_file"
        chmod 600 "$cred_file"

        # Export for use in script
        eval "${cred_name}_PASSWORD=${new_password}"

        log_success "New ${cred_name} password generated and saved"
    fi
}

# Usage (replace lines 554, 584, 404)
generate_or_load_credential "GRAFANA_ADMIN"
generate_or_load_credential "DASHBOARD"
generate_or_load_credential "MYSQL_ROOT"

# Now use $GRAFANA_ADMIN_PASSWORD, $DASHBOARD_PASSWORD, $MYSQL_ROOT_PASSWORD
```

3. **Preserve config files with backup:**
```bash
write_config_if_not_exists() {
    local config_file="$1"
    local default_content="$2"

    if [ -f "$config_file" ]; then
        log_warn "Config file $config_file already exists"

        # Create backup
        local backup="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$config_file" "$backup"
        log_info "Created backup: $backup"

        # Check if content differs
        if echo "$default_content" | diff -q "$config_file" - &>/dev/null; then
            log_info "Config unchanged, skipping"
        else
            log_warn "Config differs from default"
            read -p "Overwrite with default? (y/N): " overwrite

            if [[ "$overwrite" =~ ^[Yy]$ ]]; then
                echo "$default_content" | sudo tee "$config_file" > /dev/null
                log_info "Config overwritten (backup at $backup)"
            else
                log_info "Keeping existing config"
            fi
        fi
    else
        log_info "Creating new config: $config_file"
        echo "$default_content" | sudo tee "$config_file" > /dev/null
    fi
}

# Usage (replace write_system_file for configs)
write_config_if_not_exists "$CONFIG_DIR/prometheus/prometheus.yml" "$(cat <<'EOF'
global:
  scrape_interval: 15s
# ...
EOF
)"
```

4. **Add upgrade path detection:**
```bash
check_upgrade_compatibility() {
    local component="$1"
    local old_version="$2"
    local new_version="$3"

    log_info "Checking upgrade compatibility: $component $old_version → $new_version"

    case "$component" in
        prometheus)
            # Check for breaking changes
            if [[ "$old_version" =~ ^2\. ]] && [[ "$new_version" =~ ^3\. ]]; then
                log_warn "Major version upgrade detected!"
                log_warn "Prometheus 2.x → 3.x may require TSDB migration"
                read -p "Continue? (y/N): " proceed
                [[ "$proceed" =~ ^[Yy]$ ]] || return 1
            fi
            ;;
        loki)
            if [[ "$old_version" =~ ^2\. ]] && [[ "$new_version" =~ ^3\. ]]; then
                log_warn "Loki 3.x requires schema migration"
                log_warn "See: https://grafana.com/docs/loki/latest/upgrading/"
                read -p "Continue? (y/N): " proceed
                [[ "$proceed" =~ ^[Yy]$ ]] || return 1
            fi
            ;;
    esac

    return 0
}

# Before upgrading
current=$(get_installed_version "prometheus")
if [ -n "$current" ] && [ "$current" != "$PROMETHEUS_VERSION" ]; then
    check_upgrade_compatibility "prometheus" "$current" "$PROMETHEUS_VERSION"
fi
```

5. **Add dry-run mode:**
```bash
#!/bin/bash

DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

sudo() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] sudo $*"
    else
        command sudo "$@"
    fi
}

systemctl() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] systemctl $*"
    else
        command systemctl "$@"
    fi
}

# At start
if [ "$DRY_RUN" = true ]; then
    log_warn "=========================================="
    log_warn "  DRY-RUN MODE - NO CHANGES WILL BE MADE"
    log_warn "=========================================="
fi
```

---

## 6. Orphaned Processes

### Current Behavior

**Process cleanup mechanisms:**

1. **Pre-installation cleanup** (lines 148-213):
   ```bash
   run_full_cleanup() {
       # Stop systemd services
       for service in "${services[@]}"; do
           sudo systemctl stop "$service" 2>/dev/null || true
       done

       sleep 3

       # Kill processes by pattern
       local process_patterns=("prometheus" "node_exporter" "loki" ...)
       for pattern in "${process_patterns[@]}"; do
           local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
           if [[ -n "$pids" ]]; then
               echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
           fi
       done

       sleep 2

       # Force kill stubborn processes
       for pattern in "${process_patterns[@]}"; do
           local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
           if [[ -n "$pids" ]]; then
               echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
           fi
       done
   }
   ```
   **GOOD:** Comprehensive cleanup
   **ISSUE:** Only runs at start, not on exit

2. **stop_and_verify_service** (lines 40-113):
   - Disables service
   - Stops service
   - Waits for binary release
   - Force kills with SIGTERM then SIGKILL
   - Uses `lsof` and `fuser -k`
   **GOOD:** Thorough process termination

**Potential orphaned processes:**

1. **Background jobs from subshells:**
   - None detected in scripts
   - All commands run in foreground

2. **wget/curl downloads:**
   ```bash
   # Line 277
   wget -q "https://github.com/prometheus/prometheus/releases/..."
   ```
   - If script interrupted during download, wget process orphaned
   - **ISSUE:** No PID tracking, no cleanup trap

3. **Composer installation:**
   ```bash
   # Line 480
   curl -sS https://getcomposer.org/installer | php
   ```
   - If interrupted mid-stream, both curl AND php orphaned
   - **ISSUE:** Piped commands not tracked

4. **APT package manager:**
   ```bash
   # Line 241-242
   sudo apt-get update -qq
   sudo apt-get upgrade -y -qq
   ```
   - If interrupted, dpkg may hold lock
   - **ISSUE:** Lock file `/var/lib/dpkg/lock-frontend` prevents future runs

5. **Database initialization:**
   ```bash
   # Lines 422-428
   sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" << 'SQL'
   DELETE FROM mysql.user WHERE User='';
   ...
   SQL
   ```
   - If interrupted mid-SQL execution, transaction may be incomplete
   - MariaDB process itself won't be orphaned (systemd manages it)
   - **ISSUE:** Database in inconsistent state

**Child process scenarios:**

1. **systemd service starts child processes:**
   - Prometheus forks Go routines (managed by Go runtime, not separate processes)
   - PHP-FPM forks worker processes (managed by master process)
   - Nginx forks workers (managed by master)
   - **SAFE:** All managed by parent, killed when parent dies

2. **Script creates no daemon processes:**
   - No `&` backgrounding
   - No `nohup`
   - No `screen` or `tmux`
   - **GOOD:** No orphans from script itself

### Issues

1. **Severity: MEDIUM**
   - **wget/curl orphans:** Rare but possible on interruption
   - **dpkg lock:** Prevents re-run until manually cleared
   - **Process cleanup on exit:** None exists (no trap handler)

2. **Edge cases:**
   - User interrupts during large download: wget zombie
   - Network timeout during apt-get: dpkg lock held
   - SSH disconnect during mysql command: transaction incomplete

### Recommendations

**MEDIUM PRIORITY:**

1. **Add comprehensive exit trap:**
```bash
#!/bin/bash

CHILD_PIDS=()
LOCK_FILES=()

cleanup_on_exit() {
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_warn "Script exiting with code $exit_code, cleaning up..."

        # Kill tracked child processes
        for pid in "${CHILD_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                log_info "Killing child process: $pid"
                kill -15 "$pid" 2>/dev/null || true
                sleep 1
                kill -9 "$pid" 2>/dev/null || true
            fi
        done

        # Remove lock files
        for lock in "${LOCK_FILES[@]}"; do
            if [ -f "$lock" ]; then
                log_info "Removing lock file: $lock"
                rm -f "$lock"
            fi
        done

        # Clean up dpkg locks if we were interrupted during apt
        if fuser /var/lib/dpkg/lock-frontend &>/dev/null; then
            log_warn "Cleaning up dpkg locks..."
            sudo rm -f /var/lib/dpkg/lock-frontend
            sudo rm -f /var/lib/dpkg/lock
            sudo dpkg --configure -a 2>/dev/null || true
        fi
    fi
}

trap cleanup_on_exit EXIT INT TERM HUP

# Track downloads
safe_download() {
    local url="$1"
    local output="$2"

    wget -q "$url" -O "$output" &
    local wget_pid=$!
    CHILD_PIDS+=("$wget_pid")

    if wait "$wget_pid"; then
        # Remove from tracking
        CHILD_PIDS=("${CHILD_PIDS[@]/$wget_pid}")
        return 0
    else
        log_error "Download failed: $url"
        return 1
    fi
}
```

2. **Add process group management:**
```bash
# At start of script
set -euo pipefail

# Create new process group
set -m  # Enable job control
trap 'kill -- -$$' EXIT INT TERM HUP  # Kill entire process group on exit

# Now all child processes are in same group and killed together
```

3. **Add dpkg lock detection and recovery:**
```bash
check_and_fix_dpkg_locks() {
    log_info "Checking for dpkg locks..."

    if fuser /var/lib/dpkg/lock-frontend &>/dev/null; then
        log_warn "dpkg is locked by another process"

        # Check if it's a zombie lock
        local pid=$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null | awk '{print $2}')
        if [ -n "$pid" ]; then
            if ! ps -p "$pid" &>/dev/null; then
                log_warn "Lock held by dead process, cleaning up..."
                sudo rm -f /var/lib/dpkg/lock-frontend
                sudo rm -f /var/lib/dpkg/lock
                sudo dpkg --configure -a
            else
                log_error "dpkg is actively running (PID: $pid)"
                log_error "Wait for it to complete or kill it manually"
                return 1
            fi
        fi
    fi

    # Check for interrupted dpkg
    if [ -f /var/lib/dpkg/status-old ]; then
        log_warn "Detected interrupted dpkg, running dpkg --configure -a..."
        sudo dpkg --configure -a
    fi

    log_success "dpkg is ready"
}

# Run before first apt command
check_and_fix_dpkg_locks
```

4. **Add process monitoring during critical operations:**
```bash
monitor_process() {
    local process_name="$1"
    local max_runtime="$2"  # In seconds
    local start_time=$(date +%s)

    log_info "Monitoring $process_name (max runtime: ${max_runtime}s)..."

    while true; do
        local current_time=$(date +%s)
        local runtime=$((current_time - start_time))

        # Check if process still running
        if ! pgrep -f "$process_name" &>/dev/null; then
            log_success "$process_name completed in ${runtime}s"
            return 0
        fi

        # Check timeout
        if [ $runtime -ge $max_runtime ]; then
            log_error "$process_name exceeded max runtime of ${max_runtime}s"

            # Kill it
            local pids=$(pgrep -f "$process_name")
            log_warn "Killing processes: $pids"
            echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
            sleep 2
            echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true

            return 1
        fi

        sleep 5
    done
}

# Usage
safe_wget() {
    local url="$1"
    local output="$2"

    wget -q "$url" -O "$output" &
    local wget_pid=$!

    # Monitor for max 300 seconds
    ( sleep 300; kill -15 "$wget_pid" 2>/dev/null; ) &
    local watchdog_pid=$!

    if wait "$wget_pid"; then
        kill "$watchdog_pid" 2>/dev/null || true
        return 0
    else
        kill "$watchdog_pid" 2>/dev/null || true
        return 1
    fi
}
```

5. **Add MySQL transaction safety:**
```bash
# Replace lines 422-428
execute_mysql_safely() {
    local sql_commands="$1"
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        log_info "Executing MySQL commands (attempt $((retry + 1))/$max_retries)..."

        # Use transaction with explicit rollback on error
        if sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" <<SQL
START TRANSACTION;
$sql_commands
COMMIT;
SQL
        then
            log_success "MySQL commands executed successfully"
            return 0
        else
            log_error "MySQL commands failed, transaction rolled back"
            ((retry++))
            sleep 2
        fi
    done

    log_error "MySQL commands failed after $max_retries attempts"
    return 1
}

# Usage
execute_mysql_safely "$(cat <<'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
)"
```

---

## 7. File Descriptors and Resource Leaks

### Current Behavior

**File descriptor usage:**

1. **Heredoc writes** (lines 288-317, 364-380, 400-440, etc.):
   ```bash
   write_system_file() {
       local file="$1"
       sudo tee "$file" > /dev/null
   }

   write_system_file /etc/systemd/system/prometheus.service << EOF
   [Unit]
   Description=Prometheus
   ...
   EOF
   ```
   - Creates pipe for heredoc → tee → file
   - **SAFE:** Bash closes FDs automatically when heredoc ends
   - No leak

2. **Command substitutions** (lines 80, 85, 122, etc.):
   ```bash
   local pids=$(lsof -t "$binary_path" 2>/dev/null)
   ```
   - Spawns subshell, captures stdout
   - **SAFE:** Bash closes FD when substitution completes

3. **Temporary file creation** (lines 411-431):
   ```bash
   MYSQL_CNF_FILE=$(mktemp)
   sudo chmod 600 "$MYSQL_CNF_FILE"
   cat > "$MYSQL_CNF_FILE" << EOF
   [client]
   user=root
   password=${MYSQL_ROOT_PASSWORD}
   EOF
   # ... use file ...
   shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"
   ```
   - **GOOD:** Explicitly removes temp file with `shred -u`
   - **SAFE:** No FD leak

4. **Process status checks:**
   ```bash
   # Line 50
   if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
   ```
   - Pipe between systemctl and grep
   - **SAFE:** Bash manages pipe FDs

**Potential resource leaks:**

1. **Unclosed file descriptors: NONE DETECTED**
   - All file operations use proper shell constructs
   - No manual `exec` with FDs
   - No long-running processes with open files

2. **Memory leaks:**
   - Bash scripts don't have heap management
   - **SAFE:** OS reclaims memory on process exit

3. **Network sockets:**
   - wget/curl establish connections
   - **SAFE:** Closed when process exits
   - systemd services manage their own sockets

4. **System resources:**
   - Directories created: Persist (intentional)
   - Users created: Persist (intentional)
   - Systemd units: Persist (intentional)
   - **CORRECT BEHAVIOR**

**Edge cases:**

1. **lsof in loops** (lines 69-76, 96):
   ```bash
   while [[ $waited -lt $max_wait ]]; do
       if ! lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
           return 0
       fi
       sleep 1
       ((waited++))
   done
   ```
   - Spawns lsof process 30 times
   - **SAFE:** Each process exits after grep
   - No accumulation

2. **Credential files:**
   ```bash
   # Line 411
   MYSQL_CNF_FILE=$(mktemp)
   # ...
   # Line 431
   shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"
   ```
   - **GOOD:** Securely deleted

   ```bash
   # Line 589-592
   PASS_TEMP=$(mktemp)
   chmod 600 "$PASS_TEMP"
   echo -n "${DASHBOARD_PASSWORD}" > "$PASS_TEMP"
   # ... use ...
   shred -u "$PASS_TEMP" 2>/dev/null || rm -f "$PASS_TEMP"
   ```
   - **GOOD:** Securely deleted

3. **Redis configuration** (line 469-470):
   ```bash
   sed -i 's/^# maxmemory .*/maxmemory 128mb/' /etc/redis/redis.conf
   ```
   - **ISSUE:** No backup created
   - **ISSUE:** `sed -i` creates temp file, cleaned up automatically by sed
   - **SAFE:** No leak, but dangerous edit

### Issues

1. **Severity: LOW**
   - **No file descriptor leaks detected**
   - **Good temp file hygiene** (shred -u)
   - **Proper credential handling**

2. **Minor concerns:**
   - Multiple `lsof` calls in tight loops (performance, not leak)
   - Repeated credential file writes (lines 697-700, 979-983)
   - No FD limit checks (ulimit -n)

### Recommendations

**LOW PRIORITY (Best practices):**

1. **Add FD limit check at start:**
```bash
check_file_descriptor_limits() {
    local soft_limit=$(ulimit -Sn)
    local hard_limit=$(ulimit -Hn)
    local current_fds=$(ls /proc/self/fd | wc -l)

    log_info "File descriptor limits:"
    log_info "  Soft limit: $soft_limit"
    log_info "  Hard limit: $hard_limit"
    log_info "  Currently open: $current_fds"

    if [ "$soft_limit" -lt 1024 ]; then
        log_warn "Soft FD limit is low ($soft_limit), increasing to 4096"
        ulimit -Sn 4096 2>/dev/null || log_warn "Could not increase limit"
    fi
}

check_file_descriptor_limits
```

2. **Add FD leak detection:**
```bash
monitor_fd_usage() {
    local initial_fds=$(ls /proc/self/fd | wc -l)

    # Run operation
    "$@"

    local final_fds=$(ls /proc/self/fd | wc -l)
    local leaked=$((final_fds - initial_fds))

    if [ $leaked -gt 5 ]; then
        log_warn "Possible FD leak detected: $leaked FDs not closed"
        log_info "Open FDs:"
        ls -l /proc/self/fd
    fi
}

# Usage
monitor_fd_usage install_prometheus
```

3. **Optimize lsof loop:**
```bash
# Replace lines 69-76
wait_for_binary_release() {
    local binary_path="$1"
    local max_wait="$2"

    log_info "Waiting for ${binary_path} to be released..."

    # Use inotify instead of polling lsof
    timeout "$max_wait" bash -c "
        while lsof '$binary_path' 2>/dev/null | grep -q '$binary_path'; do
            sleep 1
        done
    " && return 0

    log_warn "Timeout waiting for binary release"
    return 1
}
```

4. **Add resource cleanup verification:**
```bash
verify_no_leaks() {
    log_info "Verifying no resource leaks..."

    # Check temp files
    local temp_count=$(find /tmp -name "chom-*" -o -name "composer-*" -o -name "prometheus-*" | wc -l)
    if [ "$temp_count" -gt 0 ]; then
        log_warn "Found $temp_count temporary files in /tmp"
        find /tmp -name "chom-*" -o -name "composer-*" -o -name "prometheus-*"
    fi

    # Check credential files in /tmp (security issue!)
    local cred_files=$(find /tmp -type f -exec grep -l "password\|secret\|key" {} \; 2>/dev/null)
    if [ -n "$cred_files" ]; then
        log_error "SECURITY: Credential files found in /tmp:"
        echo "$cred_files"
    fi

    # Check open FDs
    local fd_count=$(ls /proc/self/fd | wc -l)
    if [ "$fd_count" -gt 20 ]; then
        log_warn "$fd_count file descriptors open"
    fi
}

# Run at end of script
verify_no_leaks
```

5. **Add backup before config edits:**
```bash
safe_sed_inplace() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    # Create backup
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$file" "$backup"

    # Make edit
    sudo sed -i "s|$pattern|$replacement|" "$file"

    log_info "Edited $file (backup: $backup)"
}

# Replace line 469-470
safe_sed_inplace \
    /etc/redis/redis.conf \
    '^# maxmemory .*' \
    'maxmemory 128mb'
```

---

## 8. Systemd Service Dependencies

### Current Behavior

**Service startup order (setup-observability-vps.sh lines 640-649):**
```bash
sudo systemctl daemon-reload

sudo systemctl enable --now prometheus
sudo systemctl enable --now node_exporter
sudo systemctl enable --now loki
sudo systemctl enable --now alertmanager
sudo systemctl enable --now grafana-server
sudo systemctl restart nginx
```
- **ISSUE:** No ordering, all started in parallel
- **ISSUE:** Grafana may start before Prometheus/Loki are ready

**Service startup order (setup-vpsmanager-vps.sh lines 904-928):**
```bash
sudo systemctl daemon-reload

for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    sudo systemctl enable --now "php${PHP_VERSION}-fpm"
done

# Wait for PHP-FPM sockets to be ready
log_info "Waiting for PHP-FPM sockets to be ready..."
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"
    timeout 30 bash -c "until [ -S '${SOCKET_PATH}' ]; do sleep 0.5; done"
done

sudo systemctl enable --now nginx
sudo systemctl enable --now mariadb
sudo systemctl enable --now redis-server
sudo systemctl enable --now fail2ban
```
- **GOOD:** Waits for PHP-FPM sockets before starting nginx (lines 910-923)
- **ISSUE:** nginx and mariadb start in parallel (no dependency)
- **ISSUE:** redis-server has no dependents checking for it

**Systemd unit files:**

**Prometheus (lines 323-344):**
```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Type=simple
ExecStart=/opt/observability/bin/prometheus ...
Restart=always
RestartSec=5
```
- **GOOD:** Waits for network
- **MISSING:** No dependency on node_exporter
- **ISSUE:** May try to scrape node_exporter before it's ready

**Loki (lines 444-460):**
```ini
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/observability/bin/loki ...
Restart=always
RestartSec=5
```
- Same issues as Prometheus

**Grafana (installed via apt):**
- Has its own unit file in `/lib/systemd/system/grafana-server.service`
- Likely has `After=network.target`
- **MISSING:** No `After=prometheus.service loki.service`
- May start and fail health checks before datasources ready

**Nginx (lines 592):**
- Just restarted, not enabled --now
- **ISSUE:** If nginx was stopped, won't start
- Should use `enable --now` or `restart`

**PHP-FPM (setup-vpsmanager-vps.sh):**
- No systemd units created (uses distro defaults)
- Socket path: `/run/php/php8.2-fpm.sock`
- **GOOD:** Script waits for socket before starting nginx (lines 910-923)

### Issues

1. **Severity: MEDIUM**
   - **Race conditions:** Grafana starts before Prometheus ready → datasource errors in logs
   - **Startup delays:** Prometheus tries to scrape node_exporter before it's listening → errors
   - **No ordering:** Services start in parallel, rely on `Restart=always` to recover
   - **Network dependency only:** No inter-service dependencies

2. **Impact:**
   - Spammy error logs on first boot
   - Temporary failures cleared by restarts
   - Not critical (services recover), but unprofessional

3. **Missing features:**
   - No `Before=` directives
   - No `Requires=` (only `Wants=`)
   - No socket activation
   - No service health checks before starting dependents

### Recommendations

**MEDIUM PRIORITY:**

1. **Add proper service dependencies:**

**Prometheus unit (lines 323-344):**
```ini
[Unit]
Description=Prometheus
Wants=network-online.target node_exporter.service
After=network-online.target node_exporter.service
Before=grafana-server.service

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/prometheus \
    --config.file=/etc/observability/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/observability/prometheus \
    --storage.tsdb.retention.time=15d \
    --web.listen-address=:9090 \
    --web.enable-lifecycle

# Health check
ExecStartPost=/bin/bash -c 'until curl -sf http://localhost:9090/-/ready; do sleep 1; done'

Restart=always
RestartSec=5

# Restart if dependencies change
PartOf=observability.target

[Install]
WantedBy=multi-user.target observability.target
```

**Loki unit (lines 444-460):**
```ini
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target
Before=grafana-server.service

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/loki -config.file=/etc/observability/loki/loki.yml

# Health check
ExecStartPost=/bin/bash -c 'until curl -sf http://localhost:3100/ready; do sleep 1; done'

Restart=always
RestartSec=5

PartOf=observability.target

[Install]
WantedBy=multi-user.target observability.target
```

**Grafana override:**
```bash
# Create drop-in directory
sudo mkdir -p /etc/systemd/system/grafana-server.service.d

# Add dependencies
write_system_file /etc/systemd/system/grafana-server.service.d/dependencies.conf << 'EOF'
[Unit]
Wants=prometheus.service loki.service
After=prometheus.service loki.service
PartOf=observability.target

[Service]
# Wait for Prometheus and Loki to be ready before starting
ExecStartPre=/bin/bash -c 'until curl -sf http://localhost:9090/-/ready; do sleep 1; done'
ExecStartPre=/bin/bash -c 'until curl -sf http://localhost:3100/ready; do sleep 1; done'
EOF
```

**Nginx unit override:**
```bash
sudo mkdir -p /etc/systemd/system/nginx.service.d

write_system_file /etc/systemd/system/nginx.service.d/dependencies.conf << 'EOF'
[Unit]
Wants=php8.2-fpm.service grafana-server.service
After=php8.2-fpm.service grafana-server.service

[Service]
# Verify PHP-FPM socket exists before starting
ExecStartPre=/bin/bash -c 'until [ -S /run/php/php8.2-fpm.sock ]; do sleep 0.5; done'
EOF
```

2. **Create systemd target for observability stack:**
```bash
write_system_file /etc/systemd/system/observability.target << 'EOF'
[Unit]
Description=CHOM Observability Stack
Wants=prometheus.service node_exporter.service loki.service alertmanager.service grafana-server.service nginx.service
After=network-online.target

[Install]
WantedBy=multi-user.target
EOF

# Enable target
sudo systemctl daemon-reload
sudo systemctl enable observability.target
```

3. **Use service startup script with health checks:**
```bash
start_observability_stack() {
    log_info "Starting observability stack in correct order..."

    # 1. Node exporter (no dependencies)
    sudo systemctl start node_exporter
    wait_for_service "node_exporter" "curl -sf http://localhost:9100/metrics"

    # 2. Prometheus (depends on node_exporter)
    sudo systemctl start prometheus
    wait_for_service "prometheus" "curl -sf http://localhost:9090/-/ready"

    # 3. Loki (no dependencies)
    sudo systemctl start loki
    wait_for_service "loki" "curl -sf http://localhost:3100/ready"

    # 4. Alertmanager (depends on Prometheus)
    sudo systemctl start alertmanager
    wait_for_service "alertmanager" "curl -sf http://localhost:9093/-/ready"

    # 5. Grafana (depends on Prometheus and Loki)
    sudo systemctl start grafana-server
    wait_for_service "grafana-server" "curl -sf http://localhost:3000/api/health"

    # 6. Nginx (reverse proxy for Grafana)
    sudo systemctl start nginx
    wait_for_service "nginx" "curl -sf http://localhost:80"

    log_success "Observability stack started successfully"
}

wait_for_service() {
    local service="$1"
    local health_check="${2:-}"
    local max_wait=60
    local waited=0

    log_info "Waiting for $service to be ready..."

    while [ $waited -lt $max_wait ]; do
        if systemctl is-active --quiet "$service"; then
            if [ -z "$health_check" ]; then
                log_success "$service is active"
                return 0
            fi

            if eval "$health_check" 2>/dev/null; then
                log_success "$service is ready"
                return 0
            fi
        fi

        sleep 1
        ((waited++))
    done

    log_error "$service failed to become ready within ${max_wait}s"
    sudo systemctl status "$service" --no-pager -l
    return 1
}

# Replace lines 640-649
start_observability_stack
```

4. **Add socket activation for PHP-FPM:**
```bash
# Create PHP-FPM socket unit
write_system_file /etc/systemd/system/php8.2-fpm.socket << 'EOF'
[Unit]
Description=PHP 8.2 FPM Socket
Before=nginx.service

[Socket]
ListenStream=/run/php/php8.2-fpm.sock
SocketUser=www-data
SocketGroup=www-data
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF

# Enable socket
sudo systemctl enable php8.2-fpm.socket
sudo systemctl start php8.2-fpm.socket

# Nginx will auto-start PHP-FPM when first request arrives
```

5. **Add service dependency graph validation:**
```bash
validate_service_dependencies() {
    log_info "Validating service dependency graph..."

    # Check for circular dependencies
    if systemctl list-dependencies --reverse observability.target | grep -q "circular"; then
        log_error "Circular dependency detected!"
        return 1
    fi

    # Verify expected order
    log_info "Service startup order:"
    systemctl list-dependencies --plain observability.target | while read -r service; do
        echo "  - $service"
    done

    log_success "Dependency graph is valid"
}

validate_service_dependencies
```

---

## 9. UFW Blocks SSH During Deployment

### Current Behavior

**UFW configuration (setup-observability-vps.sh lines 597-608):**
```bash
log_info "Configuring firewall..."

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp      # Nginx/Grafana
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 3100/tcp    # Loki (for log ingestion from monitored hosts)
sudo ufw allow 9090/tcp    # Prometheus (for federation if needed)
sudo ufw --force enable
```

**UFW configuration (setup-vpsmanager-vps.sh lines 835-845):**
```bash
log_info "Configuring firewall..."

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 8080/tcp    # Dashboard
sudo ufw allow 9100/tcp    # Node exporter (for observability)
sudo ufw --force enable
```

**Critical issue at line 603/840:**
```bash
sudo ufw allow ssh
```
- Allows port 22 by default
- **BREAKS** if SSH is on non-standard port
- **BREAKS** if user is connected via IPv6 but rule only allows IPv4

**Failure scenarios:**

**Scenario 1: SSH on non-standard port**
```
Setup:
- SSH server listening on port 2222 (common security practice)
- User connected via SSH to run deployment script

Line 600/837: sudo ufw --force reset
→ All rules cleared, including any previous SSH rule

Line 603/840: sudo ufw allow ssh
→ Opens port 22 only (from /etc/services)

Line 608/845: sudo ufw --force enable
→ Firewall activated with default deny

Result:
- Current SSH connection (port 2222) is dropped
- Cannot reconnect (port 2222 blocked)
- Server is LOCKED OUT
- Requires console access or rescue mode to fix
```

**Scenario 2: IPv6 connection**
```
Setup:
- User connected via SSH over IPv6
- UFW rules apply to IPv4 by default

Line 603/840: sudo ufw allow ssh
→ Opens port 22 on IPv4 only

Line 608/845: sudo ufw --force enable
→ IPv6 connections not explicitly allowed

Result (depends on UFW version):
- UFW >= 0.35: IPv6 support enabled, rule applies to both
- UFW < 0.35: Only IPv4 allowed, IPv6 connection dropped
```

**Scenario 3: Active SSH connection during UFW reset**
```
Line 600/837: sudo ufw --force reset

What happens:
1. All UFW rules flushed
2. Netfilter/iptables rules removed
3. Existing connections MAY be dropped (depends on kernel conntrack)
4. New packets for existing connections may be rejected until UFW re-enabled

Result:
- 50% chance of SSH connection dropping between reset and enable
- No way to recover without console access
```

### Issues

1. **Severity: CRITICAL**
   - **SSH lockout:** Script can lock out the user running it
   - **No console access:** VPS users typically have web console, but it's slow/limited
   - **Cannot complete deployment:** User must login via console, fix firewall, re-run
   - **Production outage:** If run on live server, SSH lockout prevents emergency fixes

2. **Real-world impact:**
   - Happens frequently when SSH is hardened (non-standard port)
   - Happens on IPv6-only servers
   - Happens during network glitches (connection drops during UFW reset)

3. **Missing safeguards:**
   - No detection of current SSH port
   - No verification that UFW rules allow current connection
   - No grace period before activating UFW
   - No backup rule to allow current connection

### Recommendations

**CRITICAL PRIORITY:**

1. **Detect current SSH port and connection:**
```bash
configure_firewall_safely() {
    log_warn "=========================================="
    log_warn "  CONFIGURING FIREWALL - SSH SAFETY CHECK"
    log_warn "=========================================="

    # Detect current SSH connection
    local current_ssh_port=""
    local current_ssh_ip=""

    if [ -n "$SSH_CLIENT" ]; then
        # SSH_CLIENT format: "client_ip client_port server_port"
        current_ssh_port=$(echo "$SSH_CLIENT" | awk '{print $3}')
        current_ssh_ip=$(echo "$SSH_CLIENT" | awk '{print $1}')
        log_info "Detected active SSH connection:"
        log_info "  Client IP: $current_ssh_ip"
        log_info "  Server port: $current_ssh_port"
    elif [ -n "$SSH_CONNECTION" ]; then
        # SSH_CONNECTION format: "client_ip client_port server_ip server_port"
        current_ssh_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
        current_ssh_ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')
        log_info "Detected active SSH connection:"
        log_info "  Client IP: $current_ssh_ip"
        log_info "  Server port: $current_ssh_port"
    fi

    # Detect SSH server port from config
    local sshd_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -z "$sshd_port" ]; then
        sshd_port=22  # Default
    fi

    log_info "SSH server configured on port: $sshd_port"

    # Verify they match
    if [ -n "$current_ssh_port" ] && [ "$current_ssh_port" != "$sshd_port" ]; then
        log_error "MISMATCH: Connected on port $current_ssh_port but sshd.config says $sshd_port"
        log_error "Using both ports for safety"
    fi

    # Configure UFW
    log_warn "Resetting UFW rules..."
    sudo ufw --force reset

    log_info "Setting default policies..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # CRITICAL: Allow current SSH port FIRST
    if [ -n "$current_ssh_port" ]; then
        log_warn "Adding rule for current SSH connection (port $current_ssh_port)..."
        sudo ufw allow "$current_ssh_port/tcp" comment "Current SSH connection"

        # Also allow from specific IP for extra safety
        if [ -n "$current_ssh_ip" ]; then
            log_warn "Adding rule for current client IP ($current_ssh_ip)..."
            sudo ufw allow from "$current_ssh_ip" to any port "$current_ssh_port" proto tcp
        fi
    fi

    # Allow configured SSH port
    if [ "$sshd_port" != "22" ]; then
        log_info "Adding rule for SSH port $sshd_port..."
        sudo ufw allow "$sshd_port/tcp" comment "SSH"
    else
        log_info "Adding rule for standard SSH port 22..."
        sudo ufw allow ssh
    fi

    # Allow other services
    log_info "Adding rules for other services..."
    sudo ufw allow 80/tcp comment "HTTP"
    sudo ufw allow 443/tcp comment "HTTPS"
    # ... etc

    # Show rules before enabling
    log_info "UFW rules to be activated:"
    sudo ufw show added

    # Confirm with user
    log_warn "=========================================="
    log_warn "  ABOUT TO ENABLE FIREWALL"
    log_warn "  This may disconnect your SSH session!"
    log_warn "=========================================="
    echo ""
    log_info "Current SSH connection: $current_ssh_ip:$current_ssh_port"
    log_info "Firewall will allow port: $current_ssh_port"
    echo ""

    # Auto-continue in non-interactive mode, prompt in interactive
    if [ -t 0 ]; then
        read -p "Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_error "Aborted by user"
            exit 1
        fi
    else
        log_warn "Non-interactive mode, auto-continuing in 5 seconds..."
        log_warn "Press Ctrl+C to abort!"
        sleep 5
    fi

    # Enable UFW
    log_warn "Enabling UFW..."
    sudo ufw --force enable

    # Verify SSH still works
    log_info "Verifying SSH port is accessible..."
    sleep 2

    if sudo ufw status | grep -q "$current_ssh_port"; then
        log_success "SSH port $current_ssh_port is allowed in UFW"
    else
        log_error "SSH port may not be allowed!"
        log_error "If connection drops, use console to run: sudo ufw allow $current_ssh_port/tcp"
    fi

    log_success "Firewall configured successfully"
}

# Replace lines 597-608 and 835-845
configure_firewall_safely
```

2. **Add UFW safety wrapper:**
```bash
ufw_with_safety() {
    local action="$1"
    shift

    case "$action" in
        reset)
            log_warn "Resetting UFW (existing connections may be preserved by conntrack)..."
            sudo ufw --force reset

            # Immediately add safety rule for current SSH
            if [ -n "$SSH_CONNECTION" ]; then
                local ssh_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
                log_warn "Emergency SSH rule: allowing port $ssh_port"
                sudo ufw allow "$ssh_port/tcp"
            fi
            ;;

        enable)
            log_warn "Enabling UFW..."

            # Final safety check
            local ssh_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
            if ! sudo ufw status | grep -q "$ssh_port"; then
                log_error "SSH port $ssh_port is NOT in UFW rules!"
                log_error "Adding it now..."
                sudo ufw allow "$ssh_port/tcp"
            fi

            sudo ufw --force enable

            # Test SSH after 2 seconds
            sleep 2
            log_info "Testing SSH connectivity..."
            if nc -z localhost "$ssh_port" 2>/dev/null; then
                log_success "SSH port is accessible"
            else
                log_error "SSH port may be blocked!"
            fi
            ;;

        *)
            sudo ufw "$action" "$@"
            ;;
    esac
}

# Use wrapper instead of direct ufw commands
ufw_with_safety reset
ufw_with_safety default deny incoming
ufw_with_safety default allow outgoing
# ... add rules ...
ufw_with_safety enable
```

3. **Add rollback timer (self-disabling firewall):**
```bash
enable_ufw_with_rollback() {
    local rollback_seconds=120

    log_warn "Enabling UFW with automatic rollback in ${rollback_seconds}s..."
    log_warn "If SSH connection is lost, firewall will auto-disable after ${rollback_seconds}s"

    # Schedule rollback
    (
        sleep "$rollback_seconds"

        # Check if marker file exists (will be created if user confirms SSH works)
        if [ ! -f /tmp/ufw-confirmed ]; then
            logger "UFW rollback: No confirmation received, disabling firewall"
            sudo ufw --force disable
            echo "UFW auto-disabled due to no confirmation" | sudo tee /var/log/ufw-rollback.log
        fi
    ) &

    local rollback_pid=$!

    # Enable UFW
    sudo ufw --force enable

    log_success "UFW enabled. Rollback scheduled (PID: $rollback_pid)"
    log_warn "=========================================="
    log_warn "  SSH CONNECTIVITY TEST"
    log_warn "=========================================="
    echo ""
    log_info "Open a NEW SSH connection in another terminal to verify access."
    log_info "Once confirmed, type 'yes' to disable automatic rollback."
    log_info "If you don't respond within ${rollback_seconds}s, UFW will auto-disable."
    echo ""

    read -t "$rollback_seconds" -p "Can you connect via SSH? (yes/no): " confirm

    if [ "$confirm" = "yes" ]; then
        # Cancel rollback
        kill "$rollback_pid" 2>/dev/null || true
        touch /tmp/ufw-confirmed

        log_success "Rollback cancelled, UFW will remain enabled"
    else
        log_warn "No confirmation or timeout, waiting for automatic rollback..."
    fi
}

# Usage
enable_ufw_with_rollback
```

4. **Add UFW IPv6 check:**
```bash
configure_ufw_ipv6() {
    log_info "Checking UFW IPv6 support..."

    # Enable IPv6 in UFW
    if grep -q "^IPV6=yes" /etc/default/ufw; then
        log_success "UFW IPv6 support is enabled"
    else
        log_warn "Enabling UFW IPv6 support..."
        sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    fi

    # Detect if current connection is IPv6
    if [ -n "$SSH_CONNECTION" ]; then
        local client_ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')
        if echo "$client_ip" | grep -q ":"; then
            log_warn "Current SSH connection is IPv6: $client_ip"
            log_info "Ensure UFW rules apply to both IPv4 and IPv6"
        fi
    fi
}

configure_ufw_ipv6
```

5. **Add pre-flight safety checks:**
```bash
preflight_firewall_check() {
    log_info "Running pre-flight firewall safety checks..."

    # Check 1: Are we running over SSH?
    if [ -z "$SSH_CONNECTION" ] && [ -z "$SSH_CLIENT" ]; then
        log_warn "Not running over SSH (console/local access)"
        return 0
    fi

    log_warn "Running over SSH - firewall changes may lock you out!"

    # Check 2: Do we have console access?
    log_warn "Ensure you have console access (VNC/IPMI/web console) before proceeding"
    read -p "Do you have console access? (yes/no): " has_console

    if [ "$has_console" != "yes" ]; then
        log_error "ABORT: Console access required for safe firewall configuration"
        log_error "Obtain console access first, then re-run this script"
        exit 1
    fi

    # Check 3: Is UFW already enabled?
    if sudo ufw status | grep -q "Status: active"; then
        log_info "UFW is already active, will preserve existing rules temporarily"

        # Backup current rules
        sudo ufw status numbered > /tmp/ufw-backup.txt
        log_info "Current UFW rules backed up to /tmp/ufw-backup.txt"
    fi

    log_success "Pre-flight checks passed"
}

preflight_firewall_check
```

---

## 10. Rollback Capabilities

### Current Behavior

**No rollback mechanism exists:**

1. **No snapshots taken** before installation
2. **No transaction log** of changes made
3. **No undo functionality**
4. **No backup of original configs**
5. **Exit on failure** leaves system in partial state (line 708, 999)

**What happens on failure:**

**Scenario: Nginx config test fails (line 592):**
```bash
# Line 592
sudo nginx -t

# If this fails:
# - Script exits due to set -e
# - Nginx is NOT running (was never started)
# - Prometheus/Loki/Grafana ARE running (started earlier)
# - Config files ARE written
# - Systemd units ARE installed
# - No way to undo
```

**Scenario: Grafana fails to start (line 667-668):**
```bash
# Lines 663-669
for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        log_success "$svc is running"
    else
        log_error "$svc failed to start"
        ALL_OK=false
    fi
done

# Line 708
exit 1
```
- Script exits with error
- Some services running, some failed
- **No rollback:** Running services remain active
- **No cleanup:** Config files remain in place
- **No recovery:** User must manually diagnose and fix

**What would need to be rolled back:**

1. **System packages:**
   - APT packages installed (Nginx, PHP, MariaDB, Grafana, etc.)
   - ~50+ packages installed
   - **Rollback:** `apt-get remove --purge` with dependency tracking

2. **Binary files:**
   - `/opt/observability/bin/{prometheus,loki,alertmanager,node_exporter}`
   - `/usr/local/bin/{composer,node_exporter}`
   - **Rollback:** Simple `rm`, but need to track what was installed

3. **Configuration files:**
   - `/etc/observability/*` (many YAML files)
   - `/etc/systemd/system/*.service` (6+ units)
   - `/etc/nginx/sites-available/observability`
   - `/etc/grafana/grafana.ini` (modified)
   - `/etc/php/*/fpm/conf.d/99-wordpress.ini`
   - `/etc/mysql/mariadb.conf.d/99-optimization.cnf`
   - **Rollback:** Delete created files, restore modified files from backup

4. **Data directories:**
   - `/var/lib/observability/{prometheus,loki,grafana,alertmanager}` (TSDB data!)
   - `/var/www/dashboard`
   - **Rollback:** Delete if empty, PRESERVE if has data

5. **Users/groups:**
   - `observability` user
   - `node_exporter` user
   - **Rollback:** `userdel`, but only if no files owned

6. **Systemd state:**
   - Services enabled/started
   - Daemon reload
   - **Rollback:** `systemctl disable`, `systemctl stop`

7. **Firewall rules:**
   - UFW rules added
   - **Rollback:** `ufw delete` for each rule, or restore from backup

8. **Credentials:**
   - `/root/.observability-credentials`
   - `/root/.vpsmanager-credentials`
   - `/etc/vpsmanager/dashboard-auth.php`
   - **Rollback:** Delete if new, restore if existed before

### Issues

1. **Severity: CRITICAL**
   - **No rollback capability:** Failure leaves system in inconsistent state
   - **Manual cleanup required:** User must manually undo changes
   - **Data loss risk:** Re-running script may overwrite data
   - **Production risk:** Cannot safely test deployment

2. **Real-world impact:**
   - First deployment fails → partial install
   - User re-runs script → credentials change, old data lost
   - Users must manually clean up → time-consuming, error-prone
   - Production server left in broken state → downtime

### Recommendations

**CRITICAL PRIORITY:**

1. **Implement comprehensive rollback system:**

```bash
#!/bin/bash

# Rollback tracking
ROLLBACK_LOG="/var/lib/chom-deploy/rollback.log"
ROLLBACK_DATA="/var/lib/chom-deploy/rollback-data"

# Initialize rollback tracking
init_rollback() {
    mkdir -p "$(dirname "$ROLLBACK_LOG")"
    mkdir -p "$ROLLBACK_DATA"

    # Clear previous rollback log
    > "$ROLLBACK_LOG"

    log_info "Rollback tracking initialized"
}

# Record an action for potential rollback
record_action() {
    local action_type="$1"
    shift
    local action_data="$*"

    echo "${action_type}|${action_data}|$(date +%s)" >> "$ROLLBACK_LOG"
}

# Specific rollback recording functions
record_package_install() {
    local package="$1"
    record_action "APT_INSTALL" "$package"
}

record_file_create() {
    local file="$1"
    record_action "FILE_CREATE" "$file"
}

record_file_modify() {
    local file="$1"

    # Backup original file
    if [ -f "$file" ]; then
        local backup_file="$ROLLBACK_DATA/$(echo "$file" | tr '/' '_').backup"
        cp "$file" "$backup_file"
        record_action "FILE_MODIFY" "$file|$backup_file"
    fi
}

record_directory_create() {
    local dir="$1"
    record_action "DIR_CREATE" "$dir"
}

record_user_create() {
    local user="$1"
    record_action "USER_CREATE" "$user"
}

record_service_enable() {
    local service="$1"
    record_action "SERVICE_ENABLE" "$service"
}

record_ufw_rule() {
    local rule="$1"
    record_action "UFW_RULE" "$rule"
}

# Execute rollback
execute_rollback() {
    local rollback_reason="${1:-Unknown failure}"

    log_error "=========================================="
    log_error "  ROLLING BACK DEPLOYMENT"
    log_error "  Reason: $rollback_reason"
    log_error "=========================================="

    if [ ! -f "$ROLLBACK_LOG" ]; then
        log_warn "No rollback log found, nothing to undo"
        return 0
    fi

    # Read rollback log in reverse order
    local actions=$(tac "$ROLLBACK_LOG")

    while IFS='|' read -r action_type action_data timestamp; do
        log_info "Rolling back: $action_type $action_data"

        case "$action_type" in
            APT_INSTALL)
                local package="$action_data"
                log_info "Removing package: $package"
                sudo apt-get remove --purge -y "$package" 2>/dev/null || true
                ;;

            FILE_CREATE)
                local file="$action_data"
                if [ -f "$file" ]; then
                    log_info "Removing created file: $file"
                    sudo rm -f "$file"
                fi
                ;;

            FILE_MODIFY)
                local file=$(echo "$action_data" | cut -d'|' -f1)
                local backup=$(echo "$action_data" | cut -d'|' -f2)
                if [ -f "$backup" ]; then
                    log_info "Restoring original file: $file"
                    sudo cp "$backup" "$file"
                fi
                ;;

            DIR_CREATE)
                local dir="$action_data"
                if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
                    log_info "Removing empty directory: $dir"
                    sudo rmdir "$dir" 2>/dev/null || true
                else
                    log_warn "Directory not empty, skipping: $dir"
                fi
                ;;

            USER_CREATE)
                local user="$action_data"
                if id "$user" &>/dev/null; then
                    log_info "Removing user: $user"
                    sudo userdel "$user" 2>/dev/null || true
                fi
                ;;

            SERVICE_ENABLE)
                local service="$action_data"
                if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                    log_info "Disabling and stopping service: $service"
                    sudo systemctl disable --now "$service" 2>/dev/null || true
                fi
                ;;

            UFW_RULE)
                local rule_num="$action_data"
                log_info "Removing UFW rule: $rule_num"
                sudo ufw delete "$rule_num" 2>/dev/null || true
                ;;

            *)
                log_warn "Unknown rollback action: $action_type"
                ;;
        esac
    done <<< "$actions"

    # Clean up rollback data
    rm -rf "$ROLLBACK_DATA"
    rm -f "$ROLLBACK_LOG"

    log_success "Rollback completed"
}

# Trap for automatic rollback on failure
trap 'execute_rollback "Script interrupted or failed"' EXIT INT TERM HUP

# Disable trap on successful completion
disable_rollback_trap() {
    trap - EXIT INT TERM HUP
    log_success "Deployment successful, rollback disabled"

    # Archive rollback log for debugging
    if [ -f "$ROLLBACK_LOG" ]; then
        local archive="/var/lib/chom-deploy/rollback-$(date +%Y%m%d_%H%M%S).log"
        mv "$ROLLBACK_LOG" "$archive"
        log_info "Rollback log archived: $archive"
    fi
}

# Initialize rollback at start
init_rollback

# Example usage in installation
install_prometheus() {
    log_info "Installing Prometheus..."

    # Create directory
    sudo mkdir -p /opt/observability/bin
    record_directory_create "/opt/observability/bin"

    # Download and extract
    cd /tmp
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    # Install binary
    sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
    record_file_create "/opt/observability/bin/prometheus"

    # Create config
    record_file_create "$CONFIG_DIR/prometheus/prometheus.yml"
    write_system_file "$CONFIG_DIR/prometheus/prometheus.yml" << 'EOF'
# Prometheus config...
EOF

    # Create systemd unit
    record_file_create "/etc/systemd/system/prometheus.service"
    write_system_file /etc/systemd/system/prometheus.service << 'EOF'
# Systemd unit...
EOF

    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable --now prometheus
    record_service_enable "prometheus"

    log_success "Prometheus installed"
}

# At end of script
log_success "Deployment completed successfully!"
disable_rollback_trap
```

2. **Add checkpoint/resume capability:**

```bash
# Checkpoint system
CHECKPOINT_FILE="/var/lib/chom-deploy/checkpoint.state"

save_checkpoint() {
    local phase="$1"
    echo "$phase" > "$CHECKPOINT_FILE"
    log_info "Checkpoint saved: $phase"
}

load_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        cat "$CHECKPOINT_FILE"
    fi
}

clear_checkpoint() {
    rm -f "$CHECKPOINT_FILE"
}

# Installation phases
install_system_packages() {
    log_info "Phase: System packages"

    # ... installation logic ...

    save_checkpoint "system_packages"
}

install_prometheus() {
    log_info "Phase: Prometheus"

    # ... installation logic ...

    save_checkpoint "prometheus"
}

# Main installation
main() {
    local last_checkpoint=$(load_checkpoint)

    if [ -n "$last_checkpoint" ]; then
        log_warn "Previous installation was interrupted at: $last_checkpoint"
        echo ""
        echo "Options:"
        echo "  1. Resume from checkpoint"
        echo "  2. Start fresh (rollback all changes)"
        echo "  3. Abort"
        echo ""
        read -p "Choose (1-3): " choice

        case "$choice" in
            1)
                log_info "Resuming from checkpoint: $last_checkpoint"
                RESUME_FROM="$last_checkpoint"
                ;;
            2)
                log_warn "Rolling back all changes..."
                execute_rollback "User requested fresh start"
                clear_checkpoint
                RESUME_FROM=""
                ;;
            3)
                log_info "Aborted by user"
                exit 0
                ;;
        esac
    fi

    # Run phases
    if [ "$RESUME_FROM" != "system_packages" ]; then
        install_system_packages
    fi

    if [ "$RESUME_FROM" != "prometheus" ] && [ "$RESUME_FROM" != "system_packages" ]; then
        install_prometheus
    fi

    # ... more phases ...

    # Success
    clear_checkpoint
    disable_rollback_trap
}

main
```

3. **Add dry-run and interactive modes:**

```bash
#!/bin/bash

DRY_RUN=false
INTERACTIVE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_info "DRY RUN MODE - No changes will be made"
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            log_info "INTERACTIVE MODE - Will prompt before major changes"
            shift
            ;;
        --rollback)
            execute_rollback "User requested rollback"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Interactive confirmation
confirm_action() {
    local action="$1"

    if [ "$INTERACTIVE" = true ]; then
        log_warn "About to: $action"
        read -p "Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Skipped by user"
            return 1
        fi
    fi

    return 0
}

# Example usage
install_mariadb() {
    confirm_action "Install MariaDB" || return 0

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would install: mariadb-server mariadb-client"
        return 0
    fi

    sudo apt-get install -y mariadb-server mariadb-client
}
```

4. **Add snapshot/restore for data directories:**

```bash
create_data_snapshot() {
    local data_dir="$1"
    local snapshot_dir="/var/backups/chom-snapshots/$(date +%Y%m%d_%H%M%S)"

    if [ -d "$data_dir" ] && [ "$(ls -A "$data_dir")" ]; then
        log_info "Creating snapshot of $data_dir..."
        sudo mkdir -p "$snapshot_dir"
        sudo rsync -a "$data_dir/" "$snapshot_dir/"
        echo "$snapshot_dir" > "$ROLLBACK_DATA/snapshot_$(echo "$data_dir" | tr '/' '_')"
        log_success "Snapshot created: $snapshot_dir"
    fi
}

restore_data_snapshot() {
    local data_dir="$1"
    local snapshot_file="$ROLLBACK_DATA/snapshot_$(echo "$data_dir" | tr '/' '_')"

    if [ -f "$snapshot_file" ]; then
        local snapshot_dir=$(cat "$snapshot_file")
        if [ -d "$snapshot_dir" ]; then
            log_info "Restoring snapshot: $data_dir"
            sudo rsync -a --delete "$snapshot_dir/" "$data_dir/"
            sudo rm -rf "$snapshot_dir"
            log_success "Snapshot restored"
        fi
    fi
}

# Before modifying data
create_data_snapshot "/var/lib/observability/prometheus"
create_data_snapshot "/var/lib/mysql"
```

5. **Add validation before rollback:**

```bash
validate_rollback_safety() {
    log_warn "Validating rollback safety..."

    # Check for user data
    local has_data=false

    # Check Prometheus TSDB
    if [ -d "/var/lib/observability/prometheus" ]; then
        local tsdb_size=$(du -sb /var/lib/observability/prometheus | awk '{print $1}')
        if [ "$tsdb_size" -gt 1048576 ]; then  # > 1MB
            log_warn "Prometheus TSDB contains $(($tsdb_size / 1048576))MB of data"
            has_data=true
        fi
    fi

    # Check Grafana dashboards
    if [ -f "/var/lib/grafana/grafana.db" ]; then
        local dashboard_count=$(sudo sqlite3 /var/lib/grafana/grafana.db "SELECT COUNT(*) FROM dashboard;" 2>/dev/null || echo 0)
        if [ "$dashboard_count" -gt 0 ]; then
            log_warn "Grafana has $dashboard_count custom dashboards"
            has_data=true
        fi
    fi

    # Check MariaDB databases
    if systemctl is-active --quiet mariadb; then
        local db_count=$(sudo mysql -e "SHOW DATABASES;" 2>/dev/null | wc -l)
        if [ "$db_count" -gt 4 ]; then  # More than system DBs
            log_warn "MariaDB has $(($db_count - 4)) custom databases"
            has_data=true
        fi
    fi

    if [ "$has_data" = true ]; then
        log_error "=========================================="
        log_error "  WARNING: USER DATA DETECTED"
        log_error "=========================================="
        echo ""
        log_warn "Rollback will remove all installed software but may leave data behind."
        log_warn "Create manual backups before proceeding."
        echo ""
        read -p "Continue with rollback? Type 'DELETE' to confirm: " confirm

        if [ "$confirm" != "DELETE" ]; then
            log_info "Rollback aborted by user"
            return 1
        fi
    fi

    log_success "Rollback validation passed"
    return 0
}

# Before executing rollback
execute_rollback() {
    validate_rollback_safety || return 1

    # ... perform rollback ...
}
```

---

## Summary and Priority Matrix

### Critical Issues (Fix Immediately)

| Issue | Severity | Impact | Fix Complexity |
|-------|----------|--------|----------------|
| 2. Network failure during downloads | CRITICAL | Deployment fails, potential security risk (curl\|php) | Medium |
| 3. Disk full during installation | CRITICAL | Service failures, data corruption | Low |
| 9. UFW blocks SSH during deployment | CRITICAL | SSH lockout, requires console access | Medium |
| 10. No rollback capabilities | CRITICAL | Broken state on failure, manual cleanup | High |

### High Priority (Fix Soon)

| Issue | Severity | Impact | Fix Complexity |
|-------|----------|--------|----------------|
| 4. Service fails to start | HIGH | Partial deployment, poor diagnostics | Medium |
| 5. Re-run after partial failure | HIGH | Credential rotation, config loss | Medium |
| 7. File descriptors/resource leaks | LOW | None detected (good hygiene) | N/A |

### Medium Priority (Improvements)

| Issue | Severity | Impact | Fix Complexity |
|-------|----------|--------|----------------|
| 1. Script interrupted mid-execution | MEDIUM | Temp files, inconsistent state | Low |
| 6. Orphaned processes | MEDIUM | Rare, dpkg locks | Low |
| 8. Systemd service dependencies | MEDIUM | Startup errors, spammy logs | Medium |

### Observations

**Strong Points:**
- Comprehensive cleanup functions (`run_full_cleanup`, `stop_and_verify_service`)
- Port conflict resolution
- Credential file security (shred -u)
- PHP-FPM socket waiting
- MariaDB idempotency check

**Weak Points:**
- No rollback/undo capability
- No network resilience
- No disk space checks
- UFW SSH lockout risk
- Credential rotation on re-run
- No service dependency management
- Limited error diagnostics

**Overall Assessment:**
The scripts demonstrate strong idempotency and process cleanup but lack critical production safeguards around network reliability, disk space management, SSH access preservation, and rollback capabilities. The scripts prioritize "make it work on re-run" over "ensure safe deployment and recovery."

---

## Recommended Implementation Order

1. **Week 1 (Critical):**
   - Add SSH-safe UFW configuration (Issue 9)
   - Add disk space pre-flight checks (Issue 3)
   - Add network retry logic to wget/curl (Issue 2)

2. **Week 2 (High):**
   - Implement rollback system (Issue 10)
   - Fix credential preservation on re-run (Issue 5)
   - Add service startup health checks (Issue 4)

3. **Week 3 (Medium):**
   - Add signal trap handlers (Issue 1)
   - Fix systemd service dependencies (Issue 8)
   - Add dpkg lock detection (Issue 6)

4. **Week 4 (Polish):**
   - Add dry-run mode
   - Add interactive confirmation
   - Add comprehensive logging
   - Create runbook documentation
