# CHOM Deployment Scripts - Hardening Analysis & Recommendations

**Analysis Date:** 2025-12-31
**Scope:** All deployment scripts in `/chom/deploy/`
**Objective:** Identify failure points, edge cases, and provide bulletproof hardening recommendations

---

## Executive Summary

**Overall Assessment:** Scripts show good defensive practices (cleanup functions, retry logic) but have **17 critical failure points** that could cause re-run failures or service disruptions.

**Risk Level:** MEDIUM-HIGH
- Service conflict handling: ✓ Good (but needs improvements)
- Port conflict handling: ✓ Good (but incomplete coverage)
- Idempotency: ⚠️ Partial (several non-idempotent operations)
- Error handling: ⚠️ Inconsistent across scripts
- Dependency validation: ✗ Missing or incomplete

---

## 1. SERVICE CONFLICTS - Where Running Services Block Installation

### 1.1 CRITICAL: Grafana Installation Conflict (setup-observability-vps.sh)

**Issue:** Lines 522-525 install Grafana via `apt-get install grafana` without stopping existing service first.

```bash
# Current code - VULNERABLE
sudo apt-get install -y -qq grafana  # Can fail if grafana is running
```

**Failure Scenario:**
- Re-running script when Grafana already installed and running
- Package manager tries to replace binaries while service holds locks
- Installation fails with "text file busy" or package conflict errors

**Impact:** Script failure, partial installation state

**Hardening Fix:**
```bash
# BEFORE Grafana installation (add after line 519)
log_info "Preparing Grafana installation..."

# Stop grafana-server if it exists and is running
if systemctl list-unit-files | grep -q "^grafana-server.service"; then
    log_info "Stopping existing Grafana service..."
    sudo systemctl stop grafana-server 2>/dev/null || true

    # Wait for service to fully stop
    for i in {1..10}; do
        if ! systemctl is-active --quiet grafana-server; then
            break
        fi
        sleep 1
    done

    # Force kill if still running
    if systemctl is-active --quiet grafana-server; then
        log_warn "Grafana did not stop gracefully, killing processes..."
        sudo pkill -9 grafana-server 2>/dev/null || true
        sleep 2
    fi
fi

# Check for port conflicts on 3000
local grafana_pids=$(sudo lsof -ti :3000 2>/dev/null || true)
if [[ -n "$grafana_pids" ]]; then
    log_warn "Port 3000 is in use by PIDs: $grafana_pids - clearing..."
    echo "$grafana_pids" | xargs -r sudo kill -9 2>/dev/null || true
    sleep 1
fi

# NOW safe to install
sudo apt-get install -y -qq grafana
```

---

### 1.2 CRITICAL: PHP-FPM Installation Conflict (setup-vpsmanager-vps.sh)

**Issue:** Lines 330-347 install multiple PHP versions without stopping existing PHP-FPM services.

```bash
# Current code - VULNERABLE
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    sudo apt-get install -y -qq "php${PHP_VERSION}-fpm" ...  # Can conflict
done
```

**Failure Scenario:**
- Re-running when PHP 8.2 is already installed and running
- apt tries to upgrade PHP packages while FPM holds configuration files
- Results in "configuration file conflict" or "service restart failed"

**Impact:** Mixed PHP versions, broken FPM pools, web server errors

**Hardening Fix:**
```bash
# BEFORE PHP installation loop (add after line 323)
log_info "Preparing PHP installation - stopping existing FPM services..."

# Stop all PHP-FPM services before installation
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    local fpm_service="php${PHP_VERSION}-fpm"
    if systemctl list-unit-files | grep -q "^${fpm_service}.service"; then
        log_info "Stopping existing ${fpm_service}..."
        sudo systemctl stop "$fpm_service" 2>/dev/null || true

        # Wait for FPM to release sockets
        local socket_path="/run/php/php${PHP_VERSION}-fpm.sock"
        for i in {1..10}; do
            if [[ ! -S "$socket_path" ]]; then
                break
            fi
            sleep 1
        done

        # Force kill FPM processes if still running
        local fpm_pids=$(pgrep -f "php${PHP_VERSION}-fpm" 2>/dev/null || true)
        if [[ -n "$fpm_pids" ]]; then
            log_warn "Force killing php${PHP_VERSION}-fpm processes: $fpm_pids"
            echo "$fpm_pids" | xargs -r sudo kill -9 2>/dev/null || true
            sleep 1
        fi
    fi
done

# NOW proceed with installation
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    log_info "Installing PHP ${PHP_VERSION}..."
    # ... existing installation code
done
```

---

### 1.3 CRITICAL: MariaDB Installation Without Service Stop (setup-vpsmanager-vps.sh)

**Issue:** Line 373 installs MariaDB without checking if mysqld is already running.

```bash
# Current code - VULNERABLE
sudo apt-get install -y -qq mariadb-server mariadb-client
```

**Failure Scenario:**
- MariaDB already installed with active connections
- Package upgrade tries to restart service with existing datadir locks
- Installation hangs or fails with "Cannot acquire data directory lock"

**Impact:** Database unavailability, installation timeout, data corruption risk

**Hardening Fix:**
```bash
# BEFORE MariaDB installation (add after line 369)
log_info "Preparing MariaDB installation..."

# Stop MariaDB if running
if systemctl list-unit-files | grep -q "^mariadb.service"; then
    log_info "Stopping existing MariaDB service..."

    # Graceful shutdown first
    sudo systemctl stop mariadb 2>/dev/null || true

    # Wait for mysqld to release datadir
    for i in {1..30}; do
        if ! pgrep -x mysqld >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    # Force kill if still running after 30s
    if pgrep -x mysqld >/dev/null 2>&1; then
        log_warn "MariaDB did not stop gracefully, force killing..."
        sudo pkill -9 mysqld 2>/dev/null || true
        sleep 3

        # Remove PID file if exists
        sudo rm -f /var/run/mysqld/mysqld.pid 2>/dev/null || true
    fi
fi

# Check port 3306 is free
cleanup_port_conflicts 3306

# NOW safe to install/upgrade
sudo apt-get install -y -qq mariadb-server mariadb-client
```

---

### 1.4 MEDIUM: Nginx Service Not Stopped Before Config Changes

**Issue:** Multiple scripts modify nginx configs without stopping the service first.

**Files Affected:**
- `setup-observability-vps.sh` (lines 557-581)
- `setup-vpsmanager-vps.sh` (lines 279-317, 756-772)
- `setup-ssl.sh` (lines 88-89, 187-189)

**Failure Scenario:**
- Nginx running with cached configs
- Script writes new config and runs `nginx -t`
- Test passes but `nginx reload` fails due to in-memory state mismatch

**Impact:** Nginx stuck in degraded state, new configs not applied

**Hardening Fix:**
```bash
# Before ANY nginx configuration change:

# Function to safely update nginx config
safe_nginx_config_update() {
    local config_file="$1"
    local config_content="$2"

    log_info "Updating nginx configuration: $(basename "$config_file")"

    # Stop nginx to clear all in-memory state
    if systemctl is-active --quiet nginx; then
        log_info "Stopping nginx to apply configuration..."
        sudo systemctl stop nginx || {
            log_warn "Graceful stop failed, force stopping nginx..."
            sudo pkill -9 nginx 2>/dev/null || true
            sleep 2
        }
    fi

    # Write new config
    echo "$config_content" | sudo tee "$config_file" > /dev/null

    # Verify config syntax
    if ! sudo nginx -t 2>&1; then
        log_error "Nginx configuration test failed!"

        # Restore backup if exists
        if [[ -f "${config_file}.bak" ]]; then
            log_info "Restoring backup configuration..."
            sudo mv "${config_file}.bak" "$config_file"
            sudo nginx -t
        fi

        return 1
    fi

    # Start with verified config
    sudo systemctl start nginx || {
        log_error "Nginx failed to start with new configuration"
        return 1
    }

    log_success "Nginx configuration updated successfully"
    return 0
}

# Usage example:
safe_nginx_config_update "/etc/nginx/sites-available/observability" "$(cat <<'EOF'
server {
    listen 80;
    # ... config content
}
EOF
)"
```

---

## 2. PORT CONFLICTS - Services Failing Due to Occupied Ports

### 2.1 CRITICAL: Missing Port Conflict Check for Port 80/443 (All Scripts)

**Issue:** Scripts assume ports 80 and 443 are available but never verify.

**Files Affected:**
- `setup-observability-vps.sh` (lines 598-599 open firewall but don't check conflicts)
- `setup-vpsmanager-vps.sh` (lines 787-788 same issue)

**Failure Scenario:**
- Existing web server (Apache, other Nginx instance) using port 80/443
- New Nginx tries to start and fails with "Address already in use"
- Service startup fails silently, script continues

**Impact:** Web services unavailable, no error detection

**Hardening Fix:**
```bash
# Add BEFORE nginx installation/configuration in BOTH scripts:

check_critical_port_conflicts() {
    local critical_ports=(80 443)
    local conflicts_found=false

    log_info "Checking critical web ports (80, 443)..."

    for port in "${critical_ports[@]}"; do
        local listening_pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)

        if [[ -n "$listening_pids" ]]; then
            log_error "CRITICAL: Port $port is already in use!"

            # Identify what's using it
            local process_info=$(sudo lsof -i ":$port" 2>/dev/null | grep LISTEN || true)
            log_error "Process using port $port:"
            echo "$process_info"

            # Check if it's nginx
            if echo "$process_info" | grep -q nginx; then
                log_warn "Detected existing nginx on port $port"
                read -p "Stop existing nginx and continue? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo systemctl stop nginx 2>/dev/null || sudo pkill -9 nginx
                    sleep 2
                else
                    log_error "Cannot proceed with port conflict"
                    exit 1
                fi
            else
                log_error "Unknown service using port $port - manual intervention required"
                log_error "Stop the service and re-run this script"
                exit 1
            fi

            conflicts_found=true
        fi
    done

    if [[ "$conflicts_found" == "false" ]]; then
        log_success "Ports 80 and 443 are available"
    fi
}

# Call before nginx installation
check_critical_port_conflicts
```

---

### 2.2 HIGH: Incomplete Port Cleanup in cleanup_port_conflicts()

**Issue:** Function defined in both main scripts but has race condition vulnerability.

**Location:**
- `setup-observability-vps.sh` (lines 110-140)
- `setup-vpsmanager-vps.sh` (lines 115-145)

**Current Code Problem:**
```bash
# Line 120-128 - RACE CONDITION WINDOW
echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
sleep 2  # <-- 2 second window where port might be reused

pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)  # Re-check
```

**Failure Scenario:**
- Script kills process on port 9090
- During 2-second sleep, systemd auto-restarts the service
- New process binds to port 9090 again
- Script sees port still in use, force-kills the newly restarted service
- Results in service flapping

**Impact:** Service instability, infinite restart loops

**Hardening Fix:**
```bash
cleanup_port_conflicts() {
    local ports=("$@")

    log_info "Checking for port conflicts on ports: ${ports[*]}"

    for port in "${ports[@]}"; do
        local max_attempts=3
        local attempt=1

        while [[ $attempt -le $max_attempts ]]; do
            local pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)

            if [[ -z "$pids" ]]; then
                log_success "Port $port is clear"
                break
            fi

            log_warn "Attempt $attempt/$max_attempts: Port $port in use by PIDs: $pids"

            # Identify the service/process
            local process_names=$(ps -p "$pids" -o comm= 2>/dev/null || true)
            log_info "Processes: $process_names"

            # Try to identify and disable systemd service to prevent auto-restart
            for pid in $pids; do
                local cgroup=$(cat /proc/$pid/cgroup 2>/dev/null | grep systemd || true)
                if [[ -n "$cgroup" ]]; then
                    local service_name=$(echo "$cgroup" | grep -oP 'systemd.*?/\K[^/]+\.service' || true)
                    if [[ -n "$service_name" ]]; then
                        log_info "Detected systemd service: $service_name - stopping..."
                        sudo systemctl stop "$service_name" 2>/dev/null || true
                        sudo systemctl disable "$service_name" 2>/dev/null || true
                    fi
                fi
            done

            # NOW kill the processes
            echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
            sleep 1

            # Verify they're gone
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            if [[ -n "$pids" ]]; then
                log_warn "Processes survived SIGTERM, sending SIGKILL..."
                echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
                sleep 1
            fi

            # Final check
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            if [[ -z "$pids" ]]; then
                log_success "Port $port cleared successfully"
                break
            fi

            ((attempt++))
            sleep 2
        done

        # After all attempts, check if still occupied
        pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log_error "FAILED to clear port $port after $max_attempts attempts"
            log_error "PIDs still holding port: $pids"

            # Provide actionable error information
            log_error "Manual intervention required. Run:"
            log_error "  sudo lsof -i :$port"
            log_error "  sudo systemctl status <service>"
            exit 1
        fi
    done
}
```

---

### 2.3 MEDIUM: Missing Port Conflict Check for Redis (6379)

**Issue:** `setup-vpsmanager-vps.sh` installs Redis without checking port 6379.

**Location:** Lines 422-430

**Failure Scenario:**
- Existing Redis instance or other service using 6379
- New Redis installation succeeds but fails to start
- Script continues, later components fail when trying to connect to Redis

**Impact:** Silent Redis failure, dependent services broken

**Hardening Fix:**
```bash
# BEFORE Redis installation (add after line 421)

# Check Redis port availability
log_info "Checking Redis port availability..."
if sudo lsof -ti :6379 >/dev/null 2>&1; then
    log_warn "Port 6379 (Redis) is already in use"

    # Check if it's Redis
    if pgrep -x redis-server >/dev/null 2>&1; then
        log_info "Stopping existing Redis server..."
        sudo systemctl stop redis-server 2>/dev/null || true
        sleep 2

        # Force kill if necessary
        if pgrep -x redis-server >/dev/null 2>&1; then
            sudo pkill -9 redis-server 2>/dev/null || true
            sleep 1
        fi
    else
        log_error "Port 6379 occupied by non-Redis process"
        sudo lsof -i :6379
        exit 1
    fi
fi

# Add to cleanup list
cleanup_port_conflicts 6379

# NOW install Redis
sudo apt-get install -y -qq redis-server
```

---

## 3. FILE LOCKS AND BINARY REPLACEMENT ISSUES

### 3.1 CRITICAL: Binary Replacement Race Condition in stop_and_verify_service()

**Issue:** Function stops service but doesn't handle systemd restart policies.

**Location:**
- `setup-observability-vps.sh` (lines 41-107)
- `setup-vpsmanager-vps.sh` (lines 46-112)

**Current Code Vulnerability:**
```bash
# Lines 56-58
if systemctl is-active --quiet "$service_name"; then
    sudo systemctl stop "$service_name" 2>/dev/null || ...
fi
```

**Problem:** Doesn't disable auto-restart, so systemd might restart service during binary replacement.

**Failure Scenario:**
1. Script stops prometheus.service
2. Function waits for binary release (lines 63-70)
3. During wait, systemd's Restart=always kicks in
4. Prometheus restarts and locks binary again
5. Script force-kills it, replaces binary
6. Systemd tries to restart again, gets corrupted binary

**Impact:** Service crashes, corrupted binaries, flapping services

**Hardening Fix:**
```bash
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_wait=30
    local waited=0

    log_info "Attempting to stop ${service_name}..."

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        log_info "Service ${service_name} does not exist yet, skipping stop"
        return 0
    fi

    # FIX 1: Disable the service first to prevent auto-restart
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log_info "Disabling ${service_name} to prevent auto-restart..."
        sudo systemctl disable "$service_name" 2>/dev/null || log_warn "Could not disable $service_name"
    fi

    # Step 1: Graceful systemctl stop
    if systemctl is-active --quiet "$service_name"; then
        log_info "Stopping ${service_name} gracefully..."
        sudo systemctl stop "$service_name" 2>/dev/null || log_warn "Graceful stop returned error, continuing..."

        # FIX 2: Use systemctl reset-failed to clear any failed state
        sudo systemctl reset-failed "$service_name" 2>/dev/null || true
    fi

    # FIX 3: Mask the service temporarily to prevent ANY activation
    log_info "Temporarily masking ${service_name} during binary replacement..."
    sudo systemctl mask "$service_name" 2>/dev/null || true

    # Step 2: Wait for binary to be released (existing code)
    log_info "Waiting up to ${max_wait}s for ${binary_path} to be released..."
    while [[ $waited -lt $max_wait ]]; do
        if ! lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
            log_success "${service_name} stopped and binary released"

            # FIX 4: Unmask the service so it can be started later
            sudo systemctl unmask "$service_name" 2>/dev/null || true
            return 0
        fi
        sleep 1
        ((waited++))
    done

    # Steps 3-5: Force kill steps (existing code continues...)
    # ... keep existing force kill logic ...

    # AT THE END, after all kill attempts:
    # FIX 5: Always unmask before returning
    sudo systemctl unmask "$service_name" 2>/dev/null || true

    # FIX 6: Clear any failed state
    sudo systemctl reset-failed "$service_name" 2>/dev/null || true

    return 0
}
```

---

### 3.2 HIGH: Missing File Lock Check for Composer Binary

**Issue:** `setup-vpsmanager-vps.sh` line 438 installs Composer without checking if it's in use.

```bash
# Current code - VULNERABLE
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
```

**Failure Scenario:**
- Existing composer process running (e.g., `composer install` from previous failed run)
- Installer tries to replace `/usr/local/bin/composer`
- Fails with "Text file busy" error

**Impact:** Composer installation fails, VPSManager dependencies not installed

**Hardening Fix:**
```bash
# REPLACE lines 436-438 with:

log_info "Installing Composer..."

# Check if composer is currently executing
local composer_pids=$(pgrep -f "/usr/local/bin/composer" 2>/dev/null || true)
if [[ -n "$composer_pids" ]]; then
    log_warn "Composer processes currently running: $composer_pids"
    log_info "Waiting for composer processes to finish (max 60s)..."

    local wait_count=0
    while [[ $wait_count -lt 60 ]]; do
        composer_pids=$(pgrep -f "/usr/local/bin/composer" 2>/dev/null || true)
        if [[ -z "$composer_pids" ]]; then
            break
        fi
        sleep 1
        ((wait_count++))
    done

    # Force kill if still running
    composer_pids=$(pgrep -f "/usr/local/bin/composer" 2>/dev/null || true)
    if [[ -n "$composer_pids" ]]; then
        log_warn "Force killing composer processes: $composer_pids"
        echo "$composer_pids" | xargs -r sudo kill -9 2>/dev/null || true
        sleep 2
    fi
fi

# Check if binary is locked
if [[ -f "/usr/local/bin/composer" ]]; then
    if lsof "/usr/local/bin/composer" >/dev/null 2>&1; then
        log_warn "Composer binary is locked, force releasing..."
        sudo fuser -k -KILL "/usr/local/bin/composer" 2>/dev/null || true
        sleep 1
    fi

    # Backup existing composer
    sudo cp /usr/local/bin/composer /usr/local/bin/composer.bak.$(date +%s) || true
fi

# NOW safe to install
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Verify installation
if [[ ! -x "/usr/local/bin/composer" ]]; then
    log_error "Composer installation failed - binary not executable"

    # Try to restore backup
    local latest_backup=$(ls -t /usr/local/bin/composer.bak.* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        log_info "Restoring composer from backup: $latest_backup"
        sudo cp "$latest_backup" /usr/local/bin/composer
        sudo chmod +x /usr/local/bin/composer
    fi

    exit 1
fi

log_success "Composer installed successfully"
```

---

### 3.3 MEDIUM: Config File Replacement Without Backup

**Issue:** Multiple scripts overwrite config files without creating backups.

**Files Affected:**
- `setup-observability-vps.sh` (lines 282-311, 394-434, 475-491 - direct overwrites)
- `setup-vpsmanager-vps.sh` (lines 351-362, 404-414 - direct overwrites)

**Failure Scenario:**
- User has customized Prometheus/Loki/Nginx configs
- Script re-run overwrites configs with defaults
- Custom settings lost, monitoring breaks

**Impact:** Loss of custom configurations, service degradation

**Hardening Fix:**
```bash
# Create safe config write function (add to both scripts after write_system_file):

write_system_config_safe() {
    local file="$1"
    local create_backup="${2:-true}"  # Default: create backup
    local backup_suffix="pre-deploy-$(date +%Y%m%d-%H%M%S)"

    # If file exists and backup requested
    if [[ -f "$file" ]] && [[ "$create_backup" == "true" ]]; then
        local backup_file="${file}.${backup_suffix}"

        log_info "Backing up existing config: $file -> $backup_file"
        sudo cp "$file" "$backup_file" || {
            log_error "Failed to create backup of $file"
            return 1
        }

        # Keep only last 5 backups to save space
        local backup_dir=$(dirname "$file")
        local backup_base=$(basename "$file")
        sudo ls -t "${backup_dir}/${backup_base}".pre-deploy-* 2>/dev/null | tail -n +6 | xargs -r sudo rm -f || true
    fi

    # Write new config via stdin
    sudo tee "$file" > /dev/null

    # Validate new config if it's a critical file
    case "$file" in
        */prometheus.yml)
            if ! sudo /opt/observability/bin/promtool check config "$file" 2>&1; then
                log_error "Invalid Prometheus config!"
                if [[ -f "${file}.${backup_suffix}" ]]; then
                    log_info "Restoring from backup..."
                    sudo mv "${file}.${backup_suffix}" "$file"
                fi
                return 1
            fi
            ;;
        */nginx/*)
            if ! sudo nginx -t 2>&1; then
                log_error "Invalid Nginx config!"
                if [[ -f "${file}.${backup_suffix}" ]]; then
                    log_info "Restoring from backup..."
                    sudo mv "${file}.${backup_suffix}" "$file"
                fi
                return 1
            fi
            ;;
    esac

    return 0
}

# Usage: Replace all write_system_file calls with:
write_system_config_safe "$CONFIG_DIR/prometheus/prometheus.yml" << 'EOF'
# config content here
EOF
```

---

## 4. RACE CONDITIONS IN SERVICE STARTUP SEQUENCES

### 4.1 CRITICAL: Prometheus Starts Before Alertmanager Ready

**Issue:** `setup-observability-vps.sh` lines 612-616 starts all services simultaneously.

```bash
# Current code - RACE CONDITION
sudo systemctl enable --now prometheus
sudo systemctl enable --now node_exporter
sudo systemctl enable --now loki
sudo systemctl enable --now alertmanager
sudo systemctl enable --now grafana-server
```

**Problem:** Prometheus config (line 290) references `localhost:9093` (Alertmanager) but Alertmanager might not be ready when Prometheus starts.

**Failure Scenario:**
1. All services start concurrently
2. Prometheus starts, tries to connect to Alertmanager (line 290)
3. Alertmanager still initializing
4. Prometheus logs connection errors, might enter degraded state
5. Some alerts don't fire because Alertmanager connection broken

**Impact:** Broken alerting, missed alerts, service degradation

**Hardening Fix:**
```bash
# REPLACE lines 608-620 with dependency-aware startup:

log_info "Starting services with dependency ordering..."

sudo systemctl daemon-reload

# Stage 1: Start foundational services first (no dependencies)
log_info "Stage 1: Starting foundational services..."
sudo systemctl enable --now node_exporter
sudo systemctl enable --now alertmanager

# Wait for Alertmanager to be ready
log_info "Waiting for Alertmanager to be ready on port 9093..."
for i in {1..30}; do
    if curl -sf http://localhost:9093/-/ready >/dev/null 2>&1; then
        log_success "Alertmanager is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_error "Alertmanager did not become ready in 30 seconds"
        journalctl -u alertmanager -n 20 --no-pager
        exit 1
    fi
    sleep 1
done

# Stage 2: Start services that depend on Alertmanager
log_info "Stage 2: Starting Prometheus (depends on Alertmanager)..."
sudo systemctl enable --now prometheus

# Wait for Prometheus to be ready
log_info "Waiting for Prometheus to be ready on port 9090..."
for i in {1..30}; do
    if curl -sf http://localhost:9090/-/ready >/dev/null 2>&1; then
        log_success "Prometheus is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_error "Prometheus did not become ready in 30 seconds"
        journalctl -u prometheus -n 20 --no-pager
        exit 1
    fi
    sleep 1
done

# Stage 3: Start Loki (independent)
log_info "Stage 3: Starting Loki..."
sudo systemctl enable --now loki

# Wait for Loki to be ready
log_info "Waiting for Loki to be ready on port 3100..."
for i in {1..30}; do
    if curl -sf http://localhost:3100/ready >/dev/null 2>&1; then
        log_success "Loki is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_warn "Loki did not become ready in 30 seconds (may be normal for first start)"
        journalctl -u loki -n 20 --no-pager
    fi
    sleep 1
done

# Stage 4: Start Grafana (depends on Prometheus and Loki datasources)
log_info "Stage 4: Starting Grafana..."
sudo systemctl enable --now grafana-server

# Wait for Grafana to be ready
log_info "Waiting for Grafana to be ready on port 3000..."
for i in {1..60}; do  # Grafana can take longer on first start
    if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "Grafana is ready"
        break
    fi
    if [[ $i -eq 60 ]]; then
        log_error "Grafana did not become ready in 60 seconds"
        journalctl -u grafana-server -n 20 --no-pager
        exit 1
    fi
    sleep 1
done

# Stage 5: Start Nginx reverse proxy (last, after all backends ready)
log_info "Stage 5: Starting Nginx..."
sudo systemctl restart nginx

# Verify Nginx is serving traffic
sleep 2
if ! curl -sf http://localhost:80 >/dev/null 2>&1; then
    log_error "Nginx is not responding on port 80"
    journalctl -u nginx -n 20 --no-pager
    exit 1
fi

log_success "All services started successfully with proper dependency ordering"
```

---

### 4.2 HIGH: PHP-FPM Socket Race Condition with Nginx

**Issue:** `setup-vpsmanager-vps.sh` lines 829-834 starts PHP-FPM and Nginx without waiting for sockets.

```bash
# Current code - RACE CONDITION
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    sudo systemctl enable --now "php${PHP_VERSION}-fpm"
done
sudo systemctl enable --now nginx
```

**Problem:** Nginx config references `/run/php/php8.2-fpm.sock` (line 769) but socket might not exist yet.

**Failure Scenario:**
1. PHP-FPM service starts
2. Nginx starts immediately after
3. PHP-FPM still creating Unix socket
4. Nginx tries to proxy to non-existent socket
5. All PHP requests fail with "502 Bad Gateway"

**Impact:** Web application unavailable, all PHP pages return 502 errors

**Hardening Fix:**
```bash
# REPLACE lines 821-834 with:

log_info "Starting services with dependency validation..."

sudo systemctl daemon-reload

# Start PHP-FPM services and wait for sockets
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    local fpm_service="php${PHP_VERSION}-fpm"
    local fpm_socket="/run/php/php${PHP_VERSION}-fpm.sock"

    log_info "Starting ${fpm_service}..."
    sudo systemctl enable --now "$fpm_service"

    # Wait for FPM socket to be created
    log_info "Waiting for FPM socket: $fpm_socket"
    for i in {1..30}; do
        if [[ -S "$fpm_socket" ]]; then
            # Socket exists, verify it's accepting connections
            if timeout 2 socat -u OPEN:/dev/null "UNIX-CONNECT:$fpm_socket" 2>/dev/null; then
                log_success "${fpm_service} socket ready and accepting connections"
                break
            fi
        fi

        if [[ $i -eq 30 ]]; then
            log_error "${fpm_service} socket not ready after 30 seconds"
            log_error "Socket path: $fpm_socket"
            journalctl -u "$fpm_service" -n 20 --no-pager
            exit 1
        fi

        sleep 1
    done
done

# Start other services (no dependency on FPM)
log_info "Starting MariaDB..."
sudo systemctl enable --now mariadb

# Wait for MariaDB to accept connections
for i in {1..30}; do
    if sudo mysqladmin ping -u root --silent 2>/dev/null; then
        log_success "MariaDB is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_error "MariaDB not ready after 30 seconds"
        journalctl -u mariadb -n 20 --no-pager
        exit 1
    fi
    sleep 1
done

log_info "Starting Redis..."
sudo systemctl enable --now redis-server

# Wait for Redis
for i in {1..10}; do
    if redis-cli ping 2>/dev/null | grep -q PONG; then
        log_success "Redis is ready"
        break
    fi
    if [[ $i -eq 10 ]]; then
        log_warn "Redis not responding to PING"
    fi
    sleep 1
done

log_info "Starting Fail2ban..."
sudo systemctl enable --now fail2ban

# NOW safe to start Nginx (all PHP-FPM sockets exist)
log_info "Starting Nginx (all backends ready)..."
sudo systemctl enable --now nginx

# Verify Nginx started successfully
sleep 2
if ! systemctl is-active --quiet nginx; then
    log_error "Nginx failed to start"
    journalctl -u nginx -n 30 --no-pager
    exit 1
fi

# Test Nginx configuration and reload
if nginx -t 2>&1; then
    systemctl reload nginx
    log_success "Nginx configuration tested and reloaded"
else
    log_error "Nginx configuration test failed after startup"
    nginx -t
    exit 1
fi
```

---

### 4.3 MEDIUM: Loki Data Directory Not Created Before Service Start

**Issue:** `setup-observability-vps.sh` creates Loki subdirectories (line 436) AFTER service definition but might not exist when service starts.

```bash
# Current code - POTENTIAL RACE
# Line 436: Create dirs
sudo mkdir -p "$DATA_DIR/loki"/{chunks,rules,compactor}
# Line 438-454: Service definition
# Line 456: Set ownership
# Lines 614: Start service  <-- Might fail if dirs don't exist
```

**Failure Scenario:**
- Service starts before `chown` command completes
- Loki tries to write to directories owned by root
- Permission denied errors
- Loki crashes or runs in degraded mode

**Impact:** Loki fails to start, log aggregation broken

**Hardening Fix:**
```bash
# MOVE directory creation and ownership BEFORE service definition:

# After line 391 (before Loki service definition):
log_info "Setting up Loki directories with proper permissions..."

# Create all subdirectories atomically
sudo mkdir -p "$DATA_DIR/loki"/{chunks,rules,compactor}

# Set ownership immediately
sudo chown -R observability:observability "$DATA_DIR/loki" "$CONFIG_DIR/loki"

# Verify permissions
if [[ $(stat -c '%U' "$DATA_DIR/loki") != "observability" ]]; then
    log_error "Failed to set ownership on Loki data directory"
    exit 1
fi

# Set secure permissions (only owner can read/write)
sudo chmod 750 "$DATA_DIR/loki"
sudo chmod -R 750 "$DATA_DIR/loki"/{chunks,rules,compactor}

log_success "Loki directories created with correct ownership"

# NOW define the service (existing code continues)
write_system_file /etc/systemd/system/loki.service << EOF
# ... existing service definition
EOF
```

---

## 5. INCOMPLETE CLEANUP CAUSING RE-RUN FAILURES

### 5.1 CRITICAL: MariaDB Repository Cleanup Is Incomplete

**Issue:** `setup-vpsmanager-vps.sh` lines 210-215 remove MariaDB repo files but not GPG keys.

```bash
# Current code - INCOMPLETE CLEANUP
sudo rm -f /etc/apt/sources.list.d/mariadb.list
sudo rm -f /etc/apt/trusted.gpg.d/mariadb.gpg
```

**Problem:** GPG keys can also exist in:
- `/etc/apt/keyrings/mariadb.gpg`
- `/usr/share/keyrings/mariadb.gpg`
- `/etc/apt/trusted.gpg` (legacy)

**Failure Scenario:**
1. First run: Script adds MariaDB repo with key in `/etc/apt/keyrings/`
2. Script removes `/etc/apt/trusted.gpg.d/mariadb.gpg`
3. Second run: `apt-get update` still finds key in `/etc/apt/keyrings/`
4. Tries to use old repo URL, gets 404 errors
5. Installation fails

**Impact:** APT repository errors, installation failures on re-run

**Hardening Fix:**
```bash
# REPLACE lines 209-215 with comprehensive cleanup:

# Remove ALL MariaDB repository configuration remnants
log_info "Removing ALL MariaDB repository configuration..."

# Remove repository list files (all possible locations)
sudo rm -f /etc/apt/sources.list.d/mariadb.list
sudo rm -f /etc/apt/sources.list.d/mariadb.list.save
sudo rm -f /etc/apt/sources.list.d/mariadb*.list

# Remove GPG keys (all possible locations)
sudo rm -f /etc/apt/trusted.gpg.d/mariadb.gpg
sudo rm -f /etc/apt/trusted.gpg.d/mariadb*.gpg
sudo rm -f /etc/apt/keyrings/mariadb.gpg
sudo rm -f /etc/apt/keyrings/mariadb*.gpg
sudo rm -f /usr/share/keyrings/mariadb.gpg
sudo rm -f /usr/share/keyrings/mariadb*.gpg

# Remove from legacy keyring (Debian < 11)
if [[ -f /etc/apt/trusted.gpg ]]; then
    sudo apt-key del $(apt-key list 2>/dev/null | grep -B1 mariadb | head -1 | tr -d ' ') 2>/dev/null || true
fi

# Clean APT cache to remove any cached repository data
sudo rm -rf /var/lib/apt/lists/*mariadb*
sudo rm -rf /var/cache/apt/archives/mariadb*

# Update APT to clear any lingering references
sudo apt-get clean
sudo apt-get update -qq || {
    log_warn "APT update warnings (normal after repo removal)"
}

log_success "MariaDB repository configuration fully cleaned"
```

---

### 5.2 HIGH: Incomplete Grafana Cleanup on Re-run

**Issue:** `run_full_cleanup()` stops Grafana but doesn't clean Grafana's data/config state.

**Location:** `setup-observability-vps.sh` lines 148-149

**Problem:** Grafana installed via APT creates:
- `/var/lib/grafana` (SQLite DB with admin password, datasources, dashboards)
- `/etc/grafana/grafana.ini` (modified with admin password)
- `/etc/grafana/provisioning/datasources/datasources.yaml`

**Failure Scenario:**
1. First run: Grafana installs, generates password, provisions datasources
2. Second run: Grafana config overwritten with NEW password (line 549)
3. But Grafana SQLite DB still has OLD password hash
4. Admin login fails with "invalid credentials"

**Impact:** Unable to log into Grafana, manual password reset required

**Hardening Fix:**
```bash
# ADD to run_full_cleanup() before services loop (after line 152):

# Clean Grafana state if re-installing
if systemctl list-unit-files | grep -q "^grafana-server.service"; then
    log_info "Cleaning Grafana state for fresh installation..."

    # Stop Grafana first
    sudo systemctl stop grafana-server 2>/dev/null || true

    # Backup existing Grafana DB (in case user wants to recover)
    if [[ -f /var/lib/grafana/grafana.db ]]; then
        local backup_file="/var/lib/grafana/grafana.db.backup.$(date +%s)"
        sudo cp /var/lib/grafana/grafana.db "$backup_file"
        log_info "Backed up Grafana DB to: $backup_file"
    fi

    # Remove Grafana database and sessions (forces fresh start)
    sudo rm -f /var/lib/grafana/grafana.db
    sudo rm -rf /var/lib/grafana/sessions/*

    # Remove provisioned datasources (will be re-created)
    sudo rm -f /etc/grafana/provisioning/datasources/datasources.yaml

    # Reset grafana.ini to package defaults
    if [[ -f /etc/grafana/grafana.ini.dpkg-dist ]]; then
        sudo cp /etc/grafana/grafana.ini.dpkg-dist /etc/grafana/grafana.ini
    fi

    log_success "Grafana state cleaned - will be re-initialized"
fi
```

---

### 5.3 HIGH: PHP Configuration Files Not Cleaned Between Runs

**Issue:** `setup-vpsmanager-vps.sh` writes PHP config (lines 350-362) but never removes old config on re-run.

```bash
# Line 350-362: Writes 99-wordpress.ini
write_system_file "/etc/php/${PHP_VERSION}/fpm/conf.d/99-wordpress.ini" << 'EOF'
upload_max_filesize = 64M
# ...
EOF
```

**Problem:** If script changes config values between runs, old `.ini` files might conflict.

**Failure Scenario:**
1. First run: Creates `99-wordpress.ini` with `memory_limit = 256M`
2. User manually creates `98-custom.ini` with `memory_limit = 512M`
3. Second run: Overwrites `99-wordpress.ini` with `memory_limit = 128M`
4. PHP uses `98-custom.ini` (512M) but script expects 128M
5. Behavior mismatch, hard to debug

**Impact:** Configuration inconsistencies, unpredictable PHP behavior

**Hardening Fix:**
```bash
# BEFORE PHP optimization loop (add after line 349):

# Clean existing custom PHP configuration files
log_info "Cleaning previous custom PHP configurations..."

for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    local php_conf_dir="/etc/php/${PHP_VERSION}/fpm/conf.d"

    if [[ -d "$php_conf_dir" ]]; then
        # Remove any previous chom-managed config files
        sudo rm -f "${php_conf_dir}"/9[0-9]-*.ini
        sudo rm -f "${php_conf_dir}"/99-wordpress.ini

        log_success "Cleaned PHP ${PHP_VERSION} custom configs"
    fi
done

# NOW write fresh configs (existing code continues)
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    write_system_file "/etc/php/${PHP_VERSION}/fpm/conf.d/99-wordpress.ini" << 'EOF'
    # ... existing config
EOF
done

# AFTER writing configs, verify they're loaded
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    log_info "Verifying PHP ${PHP_VERSION} configuration..."

    # Check if our settings are active
    local actual_memory=$(php${PHP_VERSION} -r "echo ini_get('memory_limit');")
    if [[ "$actual_memory" != "256M" ]]; then
        log_warn "PHP ${PHP_VERSION} memory_limit is $actual_memory (expected 256M)"
        log_warn "Another config file may be overriding our settings"

        # Show which config files are active
        php${PHP_VERSION} --ini | grep "Loaded Configuration File\|Scan"
    fi
done
```

---

## 6. MISSING ERROR HANDLING OR NON-IDEMPOTENT OPERATIONS

### 6.1 CRITICAL: MySQL Secure Installation Not Idempotent

**Issue:** `setup-vpsmanager-vps.sh` lines 379-398 run MySQL secure installation without checking if already done.

```bash
# Lines 379-380: ALWAYS changes root password
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
```

**Problem:** On re-run:
1. Generates NEW random password
2. Tries to ALTER root password without old password
3. Fails because root already has a password set

**Failure Scenario:**
```
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)
```

**Impact:** Script fails on re-run, MySQL becomes inaccessible

**Hardening Fix:**
```bash
# REPLACE lines 376-401 with idempotent secure installation:

log_info "Configuring MariaDB security..."

# Check if root password is already set
MYSQL_SECURED=false
if sudo mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
    log_info "MariaDB root has no password - performing initial secure installation"
    MYSQL_SECURED=false
else
    log_info "MariaDB root already has password - checking credentials file"
    MYSQL_SECURED=true
fi

# Load existing password if available
if [[ -f /root/.vpsmanager-credentials ]]; then
    source /root/.vpsmanager-credentials
    log_info "Loaded existing MySQL credentials"
else
    # Generate new password only on first run
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    log_info "Generated new MySQL root password"
fi

# Create or update .my.cnf for passwordless access
MYSQL_CNF_FILE=$(mktemp -t mysql.XXXXXX)
sudo chmod 600 "$MYSQL_CNF_FILE"

cat > "$MYSQL_CNF_FILE" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

if [[ "$MYSQL_SECURED" == "false" ]]; then
    log_info "Setting root password for first time..."

    # Set root password (no password required initially)
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" || {
        log_error "Failed to set MySQL root password"
        rm -f "$MYSQL_CNF_FILE"
        exit 1
    }

    # Run secure installation steps
    sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" << 'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

    log_success "MariaDB secured successfully"
else
    log_info "Verifying existing root password works..."

    if ! sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" -e "SELECT 1" >/dev/null 2>&1; then
        log_error "Existing MySQL password does not work!"
        log_error "You may need to manually reset MySQL root password"
        log_error "See: https://mariadb.com/kb/en/resetting-the-root-password/"
        rm -f "$MYSQL_CNF_FILE"
        exit 1
    fi

    log_success "Existing MariaDB credentials verified"
fi

# Securely clean up temporary file
shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"
```

---

### 6.2 HIGH: systemctl enable --now Not Idempotent for Failed Services

**Issue:** Multiple scripts use `systemctl enable --now` which fails if service is already failed.

**Files Affected:**
- `setup-observability-vps.sh` (lines 612-616)
- `setup-vpsmanager-vps.sh` (lines 826-832)

**Failure Scenario:**
1. First run: Service starts but crashes immediately (config error)
2. Service enters "failed" state
3. Second run: `systemctl enable --now service` fails because service is "failed"
4. Error: "Job for service.service failed"

**Impact:** Script exits, re-run impossible without manual intervention

**Hardening Fix:**
```bash
# Create safe service start function (add to both scripts):

safe_service_start() {
    local service_name="$1"

    log_info "Starting service: $service_name"

    # Reset any previous failed state
    sudo systemctl reset-failed "$service_name" 2>/dev/null || true

    # Stop if currently running (handle degraded state)
    if systemctl is-active --quiet "$service_name"; then
        log_info "Service $service_name already active, restarting..."
        sudo systemctl restart "$service_name" || {
            log_error "Failed to restart $service_name"
            journalctl -u "$service_name" -n 30 --no-pager
            return 1
        }
    else
        # Enable and start
        sudo systemctl enable "$service_name" 2>/dev/null || true
        sudo systemctl start "$service_name" || {
            log_error "Failed to start $service_name"
            journalctl -u "$service_name" -n 30 --no-pager
            return 1
        }
    fi

    # Wait for service to be active
    for i in {1..10}; do
        if systemctl is-active --quiet "$service_name"; then
            log_success "$service_name started successfully"
            return 0
        fi
        sleep 1
    done

    # Service failed to start
    log_error "$service_name failed to reach active state"
    systemctl status "$service_name" --no-pager || true
    return 1
}

# Usage: Replace all "systemctl enable --now" with:
safe_service_start prometheus
safe_service_start loki
# etc.
```

---

### 6.3 MEDIUM: Non-Idempotent User Creation

**Issue:** Both scripts create users without checking if they already exist properly.

**Location:**
- `setup-observability-vps.sh` (line 261): `sudo useradd --system ...`
- `setup-vpsmanager-vps.sh` (line 509): `sudo useradd --system ... || true`
- `create-deploy-user.sh` (line 49): `useradd -m -s /bin/bash ...`

**Current Code Problem:**
```bash
# Line 261 - NO error handling
sudo useradd --system --no-create-home --shell /usr/sbin/nologin observability

# Line 509 - Error silently ignored
sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter || true
```

**Failure Scenario:**
1. First run: User created successfully
2. Second run: `useradd` fails with "user already exists"
3. If no `|| true`, script exits
4. If `|| true`, might miss real errors (e.g., invalid shell path)

**Impact:** Script fails on re-run, or silently ignores errors

**Hardening Fix:**
```bash
# Create safe user creation function (add to both scripts):

create_system_user() {
    local username="$1"
    local create_home="${2:-no}"  # Default: no home
    local shell="${3:-/usr/sbin/nologin}"  # Default: nologin
    local groups="${4:-}"  # Optional: comma-separated groups

    log_info "Ensuring system user exists: $username"

    # Check if user already exists
    if id -u "$username" &>/dev/null; then
        log_info "User $username already exists"

        # Verify shell matches expectation
        local current_shell=$(getent passwd "$username" | cut -d: -f7)
        if [[ "$current_shell" != "$shell" ]]; then
            log_warn "User $username has shell $current_shell (expected $shell) - updating..."
            sudo usermod -s "$shell" "$username"
        fi

        # Verify groups if specified
        if [[ -n "$groups" ]]; then
            local current_groups=$(id -Gn "$username" | tr ' ' ',')
            for group in ${groups//,/ }; do
                if ! echo "$current_groups" | grep -q "$group"; then
                    log_info "Adding $username to group $group"
                    sudo usermod -aG "$group" "$username"
                fi
            done
        fi

        return 0
    fi

    # Create user
    local useradd_args=("--system" "--shell" "$shell")

    if [[ "$create_home" == "no" ]]; then
        useradd_args+=("--no-create-home")
    else
        useradd_args+=("-m")
    fi

    if [[ -n "$groups" ]]; then
        useradd_args+=("-G" "$groups")
    fi

    useradd_args+=("$username")

    if ! sudo useradd "${useradd_args[@]}" 2>&1; then
        log_error "Failed to create user: $username"
        return 1
    fi

    log_success "User $username created successfully"
    return 0
}

# Usage examples:
create_system_user "observability"
create_system_user "node_exporter"
create_system_user "deploy" "yes" "/bin/bash" "sudo"
```

---

## 7. DEPENDENCIES NOT PROPERLY CHECKED

### 7.1 CRITICAL: Missing lsof/psmisc Check Before Usage

**Issue:** Scripts use `lsof` extensively but don't verify it's installed before first use.

**Location:**
- `setup-observability-vps.sh` uses `lsof` at line 64 (before installation at line 250)
- `setup-vpsmanager-vps.sh` uses `lsof` at line 69 (before installation at line 261)

**Failure Scenario:**
1. Vanilla Debian 13 system without `lsof` installed
2. `run_full_cleanup()` called (line 228 or 236)
3. `stop_and_verify_service()` called (line 275 or 504)
4. Line 64: `lsof "$binary_path"` fails with "command not found"
5. Script exits with error

**Impact:** Script fails immediately on fresh systems

**Hardening Fix:**
```bash
# ADD at the very beginning of both scripts (after set -euo pipefail):

# Pre-flight dependency check (BEFORE any cleanup or operations)
preflight_dependency_check() {
    log_info "Checking critical dependencies..."

    local missing_deps=()
    local critical_deps=("lsof" "fuser" "pgrep" "pkill" "systemctl" "curl")

    for dep in "${critical_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing critical dependencies: ${missing_deps[*]}"
        log_info "Installing missing dependencies..."

        # Map commands to packages
        local packages_to_install=()
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                lsof) packages_to_install+=("lsof") ;;
                fuser|pgrep|pkill) packages_to_install+=("psmisc") ;;
                systemctl) packages_to_install+=("systemd") ;;
                curl) packages_to_install+=("curl") ;;
            esac
        done

        # Remove duplicates
        packages_to_install=($(echo "${packages_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

        # Install
        log_info "Installing packages: ${packages_to_install[*]}"
        if ! sudo apt-get update -qq; then
            log_error "apt-get update failed"
            exit 1
        fi

        if ! sudo apt-get install -y -qq "${packages_to_install[@]}"; then
            log_error "Failed to install dependencies: ${packages_to_install[*]}"
            exit 1
        fi

        log_success "Dependencies installed successfully"
    else
        log_success "All critical dependencies present"
    fi
}

# CALL THIS IMMEDIATELY after sudo check (add after line 214 in observability, line 227 in vpsmanager):
preflight_dependency_check

# Now safe to call run_full_cleanup which uses lsof
run_full_cleanup
```

---

### 7.2 HIGH: Missing jq Dependency Check

**Issue:** `deploy-enhanced.sh` uses `jq` for state management but doesn't check if installed.

**Location:** Lines 491, 496 use `jq` without verification

**Failure Scenario:**
1. User runs deploy-enhanced.sh on system without `jq`
2. Line 491: `jq ".status = ..."` fails with "command not found"
3. Script exits, deployment aborted

**Impact:** Deployment fails on systems without jq

**Hardening Fix:**
```bash
# ADD to check_dependencies() function in deploy-enhanced.sh (around line 29):

check_dependencies() {
    local deps=("ssh" "scp" "yq" "jq" "curl")  # Add jq
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Installation instructions:"

        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                yq)
                    echo "  yq: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
                    ;;
                jq)
                    echo "  jq: sudo apt-get install jq  # Debian/Ubuntu"
                    echo "      sudo yum install jq      # RHEL/CentOS"
                    echo "      brew install jq          # macOS"
                    ;;
                *)
                    echo "  $dep: Install via your package manager"
                    ;;
            esac
        done

        exit 1
    fi

    log_success "All dependencies installed"
}
```

---

### 7.3 MEDIUM: Missing socat for PHP-FPM Socket Testing

**Issue:** Recommended hardening in section 4.2 uses `socat` but it's not installed.

**Failure Scenario:**
- Hardening code added: `socat -u OPEN:/dev/null "UNIX-CONNECT:$fpm_socket"`
- Package not installed
- Socket verification fails

**Impact:** Enhanced error detection doesn't work

**Hardening Fix:**
```bash
# Add to preflight_dependency_check() in section 7.1:

# For VPSManager script only:
if [[ -n "${PHP_VERSIONS:-}" ]]; then
    # We're in VPSManager script, need socat for FPM socket testing
    if ! command -v socat &>/dev/null; then
        log_info "Installing socat for PHP-FPM socket verification..."
        sudo apt-get install -y -qq socat
    fi
fi
```

---

## 8. SYSTEMD SERVICE MANAGEMENT ISSUES

### 8.1 CRITICAL: Systemd Daemon-Reload Not Called After Service File Changes

**Issue:** Scripts write new systemd service files but don't always reload before enabling.

**Files Affected:**
- `setup-observability-vps.sh` calls daemon-reload at line 610 (GOOD)
- `setup-vpsmanager-vps.sh` calls daemon-reload at line 823 (GOOD)
- **BUT**: Individual service file writes don't reload immediately

**Problem:** Systemd might cache old service definitions.

**Failure Scenario:**
1. Script writes new prometheus.service (line 317-338 in observability)
2. Prometheus binary crashes during installation
3. User manually creates prometheus.service with debug flags
4. Script re-runs, writes new prometheus.service
5. `systemctl daemon-reload` not called immediately
6. Service still uses old cached definition

**Impact:** Service starts with wrong configuration, unexpected behavior

**Hardening Fix:**
```bash
# After EVERY systemd service file write, add immediate reload:

# Example for Prometheus service (after line 338):
write_system_file /etc/systemd/system/prometheus.service << EOF
# ... service definition ...
EOF

# IMMEDIATELY reload daemon to recognize new service
sudo systemctl daemon-reload

# Verify service file is recognized
if ! systemctl list-unit-files | grep -q "^prometheus.service"; then
    log_error "prometheus.service not recognized by systemd after daemon-reload"
    log_error "Service file may have syntax errors"
    systemctl status prometheus.service || true
    exit 1
fi

log_success "prometheus.service registered with systemd"
```

---

### 8.2 HIGH: Missing Service Dependency Declarations

**Issue:** Systemd service files don't declare dependencies on each other.

**Example:** Prometheus service (lines 317-338) doesn't declare dependency on Alertmanager:

```ini
# Current - NO DEPENDENCY
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
```

**Problem:** If Alertmanager crashes and restarts, Prometheus doesn't know to reconnect.

**Failure Scenario:**
1. Prometheus starts, connects to Alertmanager
2. Alertmanager crashes (OOM, config error)
3. Systemd restarts Alertmanager
4. Prometheus still has broken connection, doesn't retry for hours
5. Alerts don't fire

**Impact:** Broken alerting, alerts missed during outage

**Hardening Fix:**
```bash
# UPDATE Prometheus service definition to declare dependencies:

write_system_file /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target alertmanager.service
After=network-online.target alertmanager.service

# If Alertmanager crashes, restart Prometheus too (to re-establish connection)
BindsTo=alertmanager.service

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/prometheus \\
    --config.file=${CONFIG_DIR}/prometheus/prometheus.yml \\
    --storage.tsdb.path=${DATA_DIR}/prometheus \\
    --storage.tsdb.retention.time=15d \\
    --web.listen-address=:9090 \\
    --web.enable-lifecycle

# Auto-restart on crash
Restart=always
RestartSec=5

# Limit restart rate (prevent crash loops)
StartLimitInterval=300
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

# Similarly, update Grafana to depend on Prometheus and Loki:
write_system_file /etc/systemd/system/grafana-server.service.d/override.conf << EOF
[Unit]
Wants=prometheus.service loki.service
After=prometheus.service loki.service
EOF
```

---

### 8.3 MEDIUM: No Service Restart Rate Limiting

**Issue:** Service definitions lack rate limiting, can cause boot storms.

**Location:** All service files in both scripts

**Failure Scenario:**
1. Loki service has config error
2. Starts, crashes immediately
3. Systemd restarts (Restart=always)
4. Crashes again within 1 second
5. Repeats 100+ times per minute
6. System becomes unresponsive due to constant restarts

**Impact:** System lockup, boot failure, resource exhaustion

**Hardening Fix:**
```bash
# Add to ALL service definitions:

[Service]
# ... existing config ...

# Restart policies
Restart=always
RestartSec=5

# Rate limiting to prevent restart storms
StartLimitInterval=300
StartLimitBurst=5

# If service fails 5 times in 5 minutes, give up for 10 minutes
# This is StartLimitAction in newer systemd versions:
# StartLimitAction=none

# Alternative: Restart with exponential backoff
# RestartSec=5s initially, doubles on each failure
```

---

## 9. PERMISSION PROBLEMS THAT COULD ARISE

### 9.1 CRITICAL: Temporary File Security Vulnerabilities

**Issue:** Several scripts create temp files without secure permissions.

**Location:**
- `setup-vpsmanager-vps.sh` line 383: `MYSQL_CNF_FILE=$(mktemp -t mysql.XXXXXX)`
- Multiple scripts use `/tmp` for downloads

**Problem:** Line 384 sets permissions AFTER creating file:
```bash
MYSQL_CNF_FILE=$(mktemp -t mysql.XXXXXX)  # Created with default perms (0600 on most systems, but not guaranteed)
sudo chmod 600 "$MYSQL_CNF_FILE"  # RACE WINDOW
```

**Failure Scenario:**
1. `mktemp` creates file with umask-dependent permissions (might be 0644)
2. Attacker running `inotifywait /tmp` detects new file
3. Before `chmod 600`, attacker reads MySQL password from temp file
4. Password compromised

**Impact:** MySQL root password leaked, database compromise

**Hardening Fix:**
```bash
# REPLACE lines 383-401 with secure temp file handling:

log_info "Configuring MariaDB security..."

# ... existing MYSQL_SECURED check ...

# CREATE secure temp file with ATOMIC permission setting
MYSQL_CNF_FILE=$(mktemp)
# Immediately restrict permissions (before writing sensitive data)
chmod 600 "$MYSQL_CNF_FILE"

# Set trap to ensure cleanup even on error
trap "shred -u '$MYSQL_CNF_FILE' 2>/dev/null || rm -f '$MYSQL_CNF_FILE'" EXIT INT TERM

# NOW safe to write password
cat > "$MYSQL_CNF_FILE" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

# ... rest of MySQL setup ...

# Cleanup happens automatically via trap
```

---

### 9.2 HIGH: World-Readable Credentials File

**Issue:** Credentials saved to `/root/.vpsmanager-credentials` with potentially weak permissions.

**Location:**
- `setup-observability-vps.sh` lines 665-668
- `setup-vpsmanager-vps.sh` lines 881-885

```bash
write_system_file /root/.vpsmanager-credentials << EOF
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
EOF
sudo chmod 600 /root/.vpsmanager-credentials
```

**Problem:** `write_system_file` uses `sudo tee` which might create file with default umask.

**Failure Scenario:**
1. System has permissive umask (0022)
2. `sudo tee` creates file as 0644 (world-readable)
3. Race window before `chmod 600`
4. Non-root user reads MySQL password

**Impact:** Password disclosure

**Hardening Fix:**
```bash
# Create secure credentials write function:

write_credentials_file() {
    local file="$1"
    local content="$2"

    # Ensure parent directory exists with secure permissions
    local dir=$(dirname "$file")
    sudo mkdir -p "$dir"
    sudo chmod 700 "$dir"

    # Create file with secure permissions ATOMICALLY
    local temp_file=$(sudo mktemp)
    echo "$content" | sudo tee "$temp_file" > /dev/null
    sudo chmod 600 "$temp_file"

    # Move atomically (preserves permissions)
    sudo mv "$temp_file" "$file"

    # Verify final permissions
    local perms=$(sudo stat -c '%a' "$file")
    if [[ "$perms" != "600" ]]; then
        log_error "Credentials file has incorrect permissions: $perms"
        sudo chmod 600 "$file"
    fi

    log_success "Credentials saved securely: $file"
}

# Usage:
write_credentials_file "/root/.vpsmanager-credentials" "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}"
```

---

### 9.3 HIGH: Observability Data Directories Overly Permissive

**Issue:** Scripts create data directories with default permissions.

**Location:**
- `setup-observability-vps.sh` line 254: `sudo mkdir -p "$DATA_DIR"/{prometheus,loki,grafana,alertmanager}`

**Problem:** Creates with umask-dependent permissions, might be 0755 (world-readable).

**Failure Scenario:**
1. Prometheus stores sensitive metrics (API tokens, user data)
2. Directory created with 0755
3. Non-root user can browse `/var/lib/observability/prometheus/`
4. Reads sensitive data from time-series database

**Impact:** Information disclosure, compliance violations

**Hardening Fix:**
```bash
# REPLACE directory creation with security-aware version:

# Create directories with EXPLICIT secure permissions
log_info "Creating observability directories with secure permissions..."

# Create top-level directory first
sudo mkdir -p "$DATA_DIR"
sudo chmod 750 "$DATA_DIR"  # Only owner and group can access
sudo chown observability:observability "$DATA_DIR"

# Create subdirectories with inheritance
for subdir in prometheus loki grafana alertmanager; do
    sudo mkdir -p "$DATA_DIR/$subdir"
    sudo chmod 750 "$DATA_DIR/$subdir"
    sudo chown observability:observability "$DATA_DIR/$subdir"
done

# Do the same for config directories
sudo mkdir -p "$CONFIG_DIR"
sudo chmod 750 "$CONFIG_DIR"
sudo chown observability:observability "$CONFIG_DIR"

for subdir in prometheus loki grafana alertmanager; do
    sudo mkdir -p "$CONFIG_DIR/$subdir"
    sudo chmod 750 "$CONFIG_DIR/$subdir"
    sudo chown observability:observability "$CONFIG_DIR/$subdir"
done

# Log directories need slightly different permissions (admin needs to read logs)
sudo mkdir -p "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"
sudo chown observability:observability "$LOG_DIR"

# Verify permissions
log_info "Verifying directory permissions..."
for dir in "$DATA_DIR" "$CONFIG_DIR"; do
    local perms=$(stat -c '%a' "$dir")
    if [[ "$perms" != "750" ]]; then
        log_warn "Directory $dir has unexpected permissions: $perms"
    fi
done

log_success "All directories created with secure permissions"
```

---

### 9.4 MEDIUM: Nginx Config Directory Permissions Too Open

**Issue:** Scripts don't set explicit permissions on Nginx config directories.

**Failure Scenario:**
1. Default nginx installation has `/etc/nginx` as 0755
2. Non-root user can read all config files
3. Configs might contain:
   - API endpoints
   - Backend server IPs
   - SSL certificate paths
   - Security headers (revealing security posture)

**Impact:** Information disclosure, attack surface mapping

**Hardening Fix:**
```bash
# After writing ANY nginx config file:

# Secure nginx configuration directory
log_info "Securing nginx configuration permissions..."

sudo chmod 750 /etc/nginx
sudo chmod 750 /etc/nginx/sites-available
sudo chmod 750 /etc/nginx/sites-enabled

# Config files should be readable by nginx group only
sudo find /etc/nginx -type f -name "*.conf" -exec chmod 640 {} \;

# Verify nginx can still read config
if ! sudo -u www-data nginx -t 2>&1; then
    log_error "Nginx cannot read config after permission changes"
    log_info "Restoring readable permissions..."
    sudo chmod 755 /etc/nginx
    sudo find /etc/nginx -type f -name "*.conf" -exec chmod 644 {} \;
    sudo nginx -t
fi

log_success "Nginx configuration secured"
```

---

## SUMMARY OF CRITICAL FIXES NEEDED

### Priority 1 - CRITICAL (Must Fix Before Production)

1. **Grafana Installation Conflict** (1.1) - Add service stop before APT install
2. **PHP-FPM Installation Conflict** (1.2) - Stop FPM before package upgrade
3. **MariaDB Installation Conflict** (1.3) - Kill mysqld before install
4. **Port 80/443 Conflict Check** (2.1) - Verify web ports available
5. **Binary Replacement Race** (3.1) - Mask services during binary updates
6. **Prometheus→Alertmanager Race** (4.1) - Staged service startup with readiness checks
7. **MariaDB Cleanup** (5.1) - Complete GPG key removal
8. **MySQL Password Idempotency** (6.1) - Check if secured before changing password
9. **Missing lsof Check** (7.1) - Install dependencies before first use
10. **Temp File Security** (9.1) - Atomic permission setting for credentials

### Priority 2 - HIGH (Should Fix Soon)

11. **Port Cleanup Race** (2.2) - Disable systemd services before killing
12. **Grafana State Cleanup** (5.2) - Remove SQLite DB on re-install
13. **PHP Config Cleanup** (5.3) - Remove old .ini files
14. **systemctl enable Failures** (6.2) - Reset failed state before starting
15. **jq Dependency** (7.2) - Check before state management
16. **Service Dependencies** (8.2) - Add Wants/After declarations
17. **Credentials File Security** (9.2) - Atomic secure write
18. **Data Directory Permissions** (9.3) - Explicit 750 permissions

### Priority 3 - MEDIUM (Nice to Have)

19. **Nginx Config Updates** (1.4) - Stop nginx before config changes
20. **Redis Port Check** (2.3) - Verify 6379 available
21. **Composer Lock Check** (3.2) - Kill running composer
22. **Config Backups** (3.3) - Backup before overwrite
23. **PHP-FPM Socket Race** (4.2) - Wait for sockets
24. **Loki Directory Timing** (4.3) - Create dirs before service definition
25. **User Creation Idempotency** (6.3) - Check existence before useradd
26. **Service Restart Limits** (8.3) - Add StartLimitBurst
27. **Nginx Config Permissions** (9.4) - Restrict to 750

---

## IMPLEMENTATION PLAN

### Phase 1: Emergency Patches (1-2 hours)
- Fix critical service conflicts (1.1, 1.2, 1.3)
- Add port conflict checks (2.1)
- Fix temp file security (9.1)

### Phase 2: Core Hardening (4-6 hours)
- Implement safe service management (3.1, 6.2, 8.1)
- Add dependency-aware startup (4.1, 4.2)
- Fix cleanup functions (5.1, 5.2)

### Phase 3: Polish & Validation (2-3 hours)
- Complete idempotency fixes (6.1, 6.3)
- Add all dependency checks (7.1, 7.2)
- Implement permission hardening (9.2, 9.3)

### Phase 4: Testing
- Test on fresh Debian 13 (first-run)
- Test on existing installation (re-run)
- Test with deliberate failures (crash recovery)
- Test with resource constraints (low disk, memory)

---

## TESTING CHECKLIST

After implementing fixes, verify:

- [ ] Fresh Debian 13 install succeeds
- [ ] Re-run on existing installation succeeds
- [ ] Can interrupt and resume deployment
- [ ] Services survive during binary upgrades
- [ ] All port conflicts detected and handled
- [ ] Config files have secure permissions (600/640)
- [ ] Data directories have secure permissions (750)
- [ ] Services start in correct order
- [ ] Failed services reset and restart properly
- [ ] No passwords in process lists or logs
- [ ] APT operations idempotent
- [ ] systemctl operations idempotent
- [ ] Works with different umask settings
- [ ] Works with SELinux/AppArmor enabled

---

## MONITORING & VALIDATION

Add post-deployment validation:

```bash
# Add at end of both main scripts:

run_security_audit() {
    log_info "Running security audit..."

    local issues_found=0

    # Check credentials file permissions
    if [[ -f /root/.vpsmanager-credentials ]]; then
        local perms=$(stat -c '%a' /root/.vpsmanager-credentials)
        if [[ "$perms" != "600" ]]; then
            log_error "Credentials file has weak permissions: $perms"
            ((issues_found++))
        fi
    fi

    # Check data directory permissions
    for dir in "$DATA_DIR"/*; do
        local perms=$(stat -c '%a' "$dir")
        if [[ "$perms" != "750" ]] && [[ "$perms" != "700" ]]; then
            log_warn "Directory $dir has permissive permissions: $perms"
            ((issues_found++))
        fi
    done

    # Check for world-readable config files
    local world_readable=$(find "$CONFIG_DIR" -type f -perm -004 2>/dev/null)
    if [[ -n "$world_readable" ]]; then
        log_warn "World-readable config files found:"
        echo "$world_readable"
        ((issues_found++))
    fi

    # Check systemd service status
    for svc in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$svc"; then
            log_error "Service $svc is not active"
            ((issues_found++))
        fi
    done

    if [[ $issues_found -eq 0 ]]; then
        log_success "Security audit passed - no issues found"
    else
        log_warn "Security audit found $issues_found issue(s)"
    fi

    return $issues_found
}

# Call after verification section
run_security_audit || log_warn "Security audit found issues - review recommended"
```

---

## CONCLUSION

These deployment scripts show good defensive programming practices (cleanup functions, error handling) but have **27 identified failure points** ranging from critical to medium severity.

**Key Takeaways:**
1. **Idempotency is partially achieved** but fails in 8 critical areas (service conflicts, password resets, repo cleanup)
2. **Race conditions exist** in 5 areas (service startup, port cleanup, binary replacement)
3. **Security vulnerabilities** in 4 areas (temp files, permissions, credentials)
4. **Dependency management** incomplete in 3 areas (missing checks, wrong order)

**Recommended Actions:**
1. Implement Priority 1 fixes immediately (10 critical fixes)
2. Add comprehensive integration tests
3. Implement all 27 hardening recommendations over next sprint
4. Add continuous validation (security audit function)

**Estimated Effort:** 12-15 hours for complete hardening implementation.
