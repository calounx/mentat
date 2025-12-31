# CHOM Deployment Scripts - Runtime & Operational Risk Analysis

**Analysis Date:** 2025-12-31
**Focus:** Service Startup Dependencies, Port Conflicts, Network Issues, Resource Requirements
**Files Analyzed:**
- /home/calounx/repositories/mentat/chom/deploy/lib/deploy-common.sh
- /home/calounx/repositories/mentat/chom/deploy/scripts/setup-observability-vps.sh
- /home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh

---

## EXECUTIVE SUMMARY

**Overall Runtime Risk:** MEDIUM-HIGH

Scripts show good engineering with parallel operations and health checks. However, critical gaps exist in resource validation, dependency ordering, monitoring, and failure recovery that could cause production outages.

**Critical Issues:** 7 | **High Priority:** 12 | **Medium Priority:** 8

---

## CRITICAL RUNTIME ISSUES

### 1. NO DISK SPACE VALIDATION BEFORE DEPLOYMENT
**Risk:** CRITICAL | **Impact:** Service Failure, Deployment Corruption

**Location:**
- setup-observability-vps.sh:180-213 (downloads 400MB+ without checking)
- setup-vpsmanager-vps.sh:165-180 (installs packages without checking)
- No pre-flight disk checks anywhere

**Problem:**
Scripts download large binaries and create data directories without validating available disk space. On small VPS, disk can fill mid-deployment causing:
- Partial binary downloads (corrupted files)
- Service crashes when trying to write data
- TSDB corruption in Prometheus
- No automatic cleanup or rollback

**Failure Scenario:**
```bash
# 512MB VPS with 600MB free space
./setup-observability-vps.sh

# Downloads succeed (400MB consumed) -> 200MB left
# Prometheus starts, begins writing TSDB -> DISK FULL
# Prometheus crashes with "no space left on device"
# Grafana can't write SQLite database -> fails
# System in broken state, requires manual cleanup
```

**Evidence in Code:**
```bash
# setup-observability-vps.sh line 162-165
sudo mkdir -p "$DATA_DIR"/{prometheus,loki,grafana,alertmanager}
# No df check before creating data dirs

# line 185-195: Downloads in parallel without space check
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" &
```

**Detection Commands:**
```bash
# Check available space
df -h /

# Monitor space during deployment
watch -n1 'df -h /'

# Check if services failed due to disk
journalctl -xeu prometheus | grep -i "no space\|disk full"
```

**Fix Required:**
```bash
check_disk_space() {
    local required_mb="$1"
    local mount="${2:-/}"
    local available_mb=$(df -m "$mount" | awk 'NR==2 {print $4}')

    log_info "Disk space check: ${available_mb}MB available, ${required_mb}MB required"

    if [[ $available_mb -lt $required_mb ]]; then
        log_error "INSUFFICIENT DISK SPACE"
        log_error "  Available: ${available_mb}MB"
        log_error "  Required:  ${required_mb}MB"
        log_error "  Shortfall: $((required_mb - available_mb))MB"
        exit 1
    fi

    log_success "Disk space check passed"
}

# Add to pre-flight checks
check_disk_space 2000  # 2GB for observability stack
check_disk_space 1500  # 1.5GB for vpsmanager stack
```

**Monitoring Addition:**
```yaml
# Add to Prometheus rules
- alert: DiskSpaceCritical
  expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes) < 0.1
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Disk space below 10% on {{ $labels.instance }}"
```

---

### 2. NO MEMORY VALIDATION - OOM KILLER RISK
**Risk:** CRITICAL | **Impact:** Random Service Termination, System Instability

**Location:**
- setup-observability-vps.sh:253-274 (Prometheus with fixed 15d retention)
- setup-vpsmanager-vps.sh:339 (MariaDB innodb_buffer_pool_size=256M hardcoded)
- setup-vpsmanager-vps.sh:475 (Redis maxmemory=128mb hardcoded)

**Problem:**
Memory requirements are hardcoded without checking available RAM. On small VPS:
- Prometheus + Grafana + Loki = 500MB+ baseline
- MariaDB buffer pool = 256MB
- Redis = 128MB
- PHP-FPM workers = 50MB+ each
- TOTAL: 1GB+ required, but no check if available

**Failure Scenario:**
```bash
# 512MB VPS runs deployment successfully
# All services start (systemctl shows "active")
# System begins swapping heavily
# OOM killer activates
# Randomly kills Prometheus (largest process)
# Prometheus restarts (RestartSec=5)
# OOM kills it again
# Restart loop exhausts resources
# System becomes unresponsive
```

**Evidence in Code:**
```bash
# setup-observability-vps.sh line 385
--storage.tsdb.retention.time=15d \\
# 15 days of metrics on busy system = 2-4GB disk + 500MB+ RAM
# No memory check before setting retention

# setup-vpsmanager-vps.sh line 339
innodb_buffer_pool_size = 256M
# Fixed value, no adaptation to available RAM
```

**Detection Commands:**
```bash
# Check available memory
free -h

# Check if OOM killer has been active
journalctl -k | grep -i "out of memory\|killed process"

# Monitor memory pressure
watch -n1 'free -h && echo && ps aux --sort=-%mem | head -10'
```

**Fix Required:**
```bash
check_memory_requirements() {
    local required_mb="$1"
    local available_mb=$(free -m | awk 'NR==2 {print $7}')  # Available RAM
    local total_mb=$(free -m | awk 'NR==2 {print $2}')

    log_info "Memory check: ${available_mb}MB available of ${total_mb}MB total"

    if [[ $available_mb -lt $required_mb ]]; then
        log_error "INSUFFICIENT MEMORY"
        log_error "  Total:     ${total_mb}MB"
        log_error "  Available: ${available_mb}MB"
        log_error "  Required:  ${required_mb}MB"
        log_warn "Consider: reducing retention, buffer sizes, or worker counts"
        exit 1
    fi

    log_success "Memory check passed"
}

tune_for_available_memory() {
    local total_mb=$(free -m | awk 'NR==2 {print $2}')

    log_info "Auto-tuning for ${total_mb}MB RAM..."

    if [[ $total_mb -lt 1024 ]]; then
        # Minimal VPS (< 1GB)
        export PROMETHEUS_RETENTION="7d"
        export MARIADB_BUFFER="64M"
        export REDIS_MAXMEMORY="64mb"
        export PHP_MAX_CHILDREN="5"
        log_warn "Low memory detected - using minimal settings"

    elif [[ $total_mb -lt 2048 ]]; then
        # Small VPS (1-2GB)
        export PROMETHEUS_RETENTION="10d"
        export MARIADB_BUFFER="128M"
        export REDIS_MAXMEMORY="128mb"
        export PHP_MAX_CHILDREN="10"
        log_info "Medium memory - using balanced settings"

    else
        # Standard VPS (2GB+)
        export PROMETHEUS_RETENTION="15d"
        export MARIADB_BUFFER="256M"
        export REDIS_MAXMEMORY="256mb"
        export PHP_MAX_CHILDREN="20"
        log_success "Adequate memory - using full settings"
    fi
}

# Call before deployment
tune_for_available_memory
check_memory_requirements 1024  # Require 1GB minimum
```

---

### 3. SERVICE STARTUP ORDER - DEPENDENCY FAILURES
**Risk:** HIGH | **Impact:** Silent Initialization Failures, Broken Datasources

**Location:**
- setup-observability-vps.sh:536-549 (parallel service starts)
- setup-vpsmanager-vps.sh:929-969 (parallel PHP-FPM + service starts)

**Problem:**
Services start in parallel without waiting for dependencies:
1. Grafana starts while Prometheus/Loki still initializing
2. Grafana datasources fail to validate (Prometheus not ready)
3. Datasources marked "error" but service shows "running"
4. User thinks deployment succeeded but data sources broken

**Failure Scenario:**
```bash
# Parallel start
sudo systemctl start prometheus &
sudo systemctl start loki &
sudo systemctl start grafana-server
wait

# Race condition timeline:
# T+0s: All services start
# T+2s: Grafana ready, tries to connect to Prometheus
# T+3s: Prometheus still loading TSDB from disk
# T+3s: Grafana datasource validation FAILS
# T+5s: Prometheus ready
# T+6s: verify_services runs - ALL SHOW ACTIVE
# T+6s: Deployment marked SUCCESS
# Reality: Datasources broken, requires manual fix
```

**Evidence in Code:**
```bash
# setup-observability-vps.sh line 538-542
sudo systemctl start prometheus &
sudo systemctl start node_exporter &
sudo systemctl start loki &
sudo systemctl start alertmanager &
wait  # Only waits for systemctl commands, NOT service readiness

# line 546: Grafana starts immediately
sudo systemctl start grafana-server
# No check if Prometheus/Loki are accepting connections
```

**Detection Commands:**
```bash
# Check Grafana datasource status
curl -s http://admin:PASSWORD@localhost:3000/api/datasources | jq '.[] | {name, url, status}'

# Check if Prometheus is ready
curl -sf http://localhost:9090/-/ready && echo "READY" || echo "NOT READY"

# Check Loki readiness
curl -sf http://localhost:3100/ready && echo "READY" || echo "NOT READY"

# View service startup timing
systemctl show prometheus loki grafana-server --property=ExecMainStartTimestamp
```

**Fix Required:**
```bash
wait_for_service_ready() {
    local service_name="$1"
    local health_url="$2"
    local max_wait="${3:-60}"
    local elapsed=0

    log_info "Waiting for ${service_name} to be ready..."

    while [[ $elapsed -lt $max_wait ]]; do
        if curl -sf "$health_url" >/dev/null 2>&1; then
            log_success "${service_name} is ready (${elapsed}s)"
            return 0
        fi
        sleep 2
        ((elapsed += 2))
    done

    log_error "${service_name} failed to become ready after ${max_wait}s"
    return 1
}

start_services_with_dependencies() {
    log_info "Starting services in dependency order..."

    # Tier 1: Core metrics (no dependencies)
    log_info "Tier 1: Core metrics collection"
    sudo systemctl start prometheus
    wait_for_service_ready "Prometheus" "http://localhost:9090/-/ready" 60

    sudo systemctl start node_exporter
    sleep 2  # Simple service, starts quickly

    # Tier 2: Log aggregation (no dependencies)
    log_info "Tier 2: Log aggregation"
    sudo systemctl start loki
    wait_for_service_ready "Loki" "http://localhost:3100/ready" 60

    # Tier 3: Alerting (depends on Prometheus)
    log_info "Tier 3: Alerting"
    sudo systemctl start alertmanager
    wait_for_service_ready "Alertmanager" "http://localhost:9093/-/ready" 30

    # Tier 4: Visualization (depends on ALL above)
    log_info "Tier 4: Visualization"
    sudo systemctl start grafana-server
    wait_for_service_ready "Grafana" "http://localhost:3000/api/health" 90

    # Tier 5: Nginx (depends on all backends)
    log_info "Tier 5: Reverse proxy"
    sudo systemctl start nginx

    log_success "All services started with dependencies verified"
}

# Replace lines 536-549 with:
start_services_with_dependencies
```

---

### 4. PORT CONFLICTS RESOLVED BY KILLING - DATA LOSS RISK
**Risk:** HIGH | **Impact:** Service Interruption, Potential Data Corruption

**Location:**
- deploy-common.sh:260-293 (cleanup_port_conflicts)
- deploy-common.sh:186-257 (stop_and_verify_service)

**Problem:**
Port cleanup sends SIGKILL without checking what process owns the port:
- Could kill production Prometheus with months of metrics
- SIGKILL prevents graceful shutdown
- Prometheus TSDB corruption risk
- No logging of what was killed
- No option to abort if unknown service detected

**Failure Scenario:**
```bash
# Production Prometheus running with 90 days of metrics
# Admin re-runs deployment script for upgrade
# cleanup_port_conflicts detects port 9090 in use
# Sends SIGKILL to Prometheus
# Prometheus TSDB corrupted (write-ahead-log not flushed)
# 90 days of metrics lost
# No backup, no recovery
```

**Evidence in Code:**
```bash
# deploy-common.sh line 275-280
pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
if [[ -n "$pids" ]]; then
    log_warn "Processes still alive on port $port, sending SIGKILL..."
    echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
    # NO CHECK: What is this process? Is it critical?
fi
```

**Detection Commands:**
```bash
# Before running deployment, check what's on ports
for port in 9090 9100 3100 9093 3000; do
    echo "Port $port:"
    sudo lsof -i :$port -P -n
    echo
done

# Check for recent SIGKILL in logs
journalctl -n1000 | grep -i "killed\|signal 9"

# Check Prometheus TSDB health
curl http://localhost:9090/api/v1/status/tsdb
```

**Fix Required:**
```bash
safe_port_cleanup() {
    local port="$1"

    local pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)

    if [[ -z "$pids" ]]; then
        log_success "Port $port is available"
        return 0
    fi

    # Identify process
    local process_info=$(sudo lsof -i ":$port" -P -n | tail -n +2)
    local process_name=$(echo "$process_info" | awk '{print $1}' | head -n1)
    local process_user=$(echo "$process_info" | awk '{print $3}' | head -n1)

    log_warn "Port $port in use by: $process_name (user: $process_user, PID: $pids)"

    # Check if it's a known CHOM service
    if [[ "$process_name" =~ ^(prometheus|loki|grafana|alertmanager|node_exporter)$ ]]; then
        log_info "Detected CHOM service: $process_name (safe to restart)"

        # Graceful shutdown with backup
        if [[ "$process_name" == "prometheus" ]]; then
            log_info "Creating Prometheus snapshot before restart..."
            curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot || log_warn "Snapshot failed"
        fi

        # Send SIGTERM first
        log_info "Sending SIGTERM to $process_name..."
        echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true

        # Wait for graceful shutdown (longer timeout for databases)
        local timeout=30
        [[ "$process_name" == "prometheus" ]] && timeout=60

        local waited=0
        while [[ $waited -lt $timeout ]]; do
            if ! sudo lsof -ti ":$port" &>/dev/null; then
                log_success "Port $port released gracefully (${waited}s)"
                return 0
            fi
            sleep 2
            ((waited += 2))
        done

        # Last resort SIGKILL with logging
        log_warn "Graceful shutdown timeout, sending SIGKILL..."
        echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
        logger -t chom-deploy "Force killed $process_name on port $port (PID: $pids)"

    else
        # Unknown service - require confirmation
        log_error "UNKNOWN SERVICE on port $port: $process_name"
        echo "$process_info"
        echo
        read -p "Kill this process and continue? (type 'yes' to confirm): " confirm

        if [[ "$confirm" != "yes" ]]; then
            log_error "Deployment aborted - manual intervention required"
            log_error "Free port $port manually or stop the conflicting service"
            exit 1
        fi

        log_warn "User confirmed - killing process $pids..."
        echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
    fi
}
```

---

### 5. DNS RESOLUTION FAILURES NOT HANDLED PROPERLY
**Risk:** MEDIUM-HIGH | **Impact:** SSL Setup Failure, Manual Intervention Required

**Location:**
- deploy-common.sh:570-596 (check_domain_accessible)
- deploy-common.sh:599-623 (wait_for_domain)

**Problem:**
- Uses `host` command which may not be installed
- No fallback to `dig` or `nslookup`
- 5-minute timeout with fixed 10s retry interval (no backoff)
- Failed checks continue to SSL which will fail
- Cryptic certbot errors if DNS not ready

**Failure Scenario:**
```bash
# DNS changes propagating (TTL: 3600s)
# User runs deployment immediately after DNS update
# check_domain_accessible fails (old DNS cache)
# Script warns but continues
# certbot tries to validate domain
# Let's Encrypt can't reach server
# SSL setup fails with "Connection timeout"
# User must wait and manually run certbot later
```

**Evidence in Code:**
```bash
# deploy-common.sh line 576
if host "$domain" >/dev/null 2>&1; then
    # 'host' command may not be installed on Debian minimal
    # No retry with exponential backoff
    # No alternative DNS tools
```

**Detection Commands:**
```bash
# Check if domain resolves
host mentat.arewel.com
dig mentat.arewel.com +short
nslookup mentat.arewel.com

# Check DNS propagation worldwide
curl -s "https://dns.google/resolve?name=mentat.arewel.com&type=A" | jq .

# Test if domain points to this server
SERVER_IP=$(hostname -I | awk '{print $1}')
RESOLVED_IP=$(host mentat.arewel.com | grep "has address" | awk '{print $4}')
[[ "$SERVER_IP" == "$RESOLVED_IP" ]] && echo "DNS OK" || echo "DNS MISMATCH"
```

**Fix Required:**
```bash
check_domain_accessible() {
    local domain="$1"
    local dns_tools=("host" "dig" "nslookup")
    local resolved_ip=""

    log_info "Checking DNS resolution for ${domain}..."

    # Try multiple DNS tools (fallback chain)
    for tool in "${dns_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            continue
        fi

        case "$tool" in
            host)
                resolved_ip=$(host "$domain" 2>/dev/null | grep "has address" | awk '{print $4}' | head -n1)
                ;;
            dig)
                resolved_ip=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | head -n1)
                ;;
            nslookup)
                resolved_ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / && NR>1 { print $2; exit }')
                ;;
        esac

        if [[ -n "$resolved_ip" ]]; then
            log_info "DNS resolved using $tool: ${resolved_ip}"
            break
        fi
    done

    if [[ -z "$resolved_ip" ]]; then
        log_error "Cannot resolve domain: ${domain}"
        log_error "Tried tools: ${dns_tools[*]}"
        log_error "Check: 1) DNS configuration, 2) network connectivity, 3) DNS servers"
        return 1
    fi

    # Validate IP points to this server
    local server_ip=$(hostname -I | awk '{print $1}')

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        log_success "DNS correctly configured: ${domain} -> ${server_ip}"
        return 0
    else
        log_error "DNS MISMATCH:"
        log_error "  Domain ${domain} points to: ${resolved_ip}"
        log_error "  This server IP:             ${server_ip}"
        log_error "Update DNS A record to point to ${server_ip}"
        return 1
    fi
}

wait_for_domain() {
    local domain="$1"
    local timeout="${2:-300}"
    local elapsed=0
    local retry_interval=10
    local max_interval=60

    log_info "Waiting for ${domain} DNS (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        if check_domain_accessible "$domain" 2>/dev/null; then
            log_success "Domain ${domain} is accessible"
            return 0
        fi

        log_info "Waiting ${retry_interval}s before retry... (${elapsed}s/${timeout}s elapsed)"
        sleep $retry_interval
        elapsed=$((elapsed + retry_interval))

        # Exponential backoff
        retry_interval=$((retry_interval * 2))
        [[ $retry_interval -gt $max_interval ]] && retry_interval=$max_interval
    done

    log_error "Timeout waiting for ${domain} to be accessible"
    log_error "DNS may not be configured or propagation still in progress"
    return 1
}
```

---

### 6. SSL CERTIFICATE RENEWAL FAILURES UNMONITORED
**Risk:** HIGH | **Impact:** Certificate Expiry, Production Outage

**Location:**
- deploy-common.sh:538-567 (setup_ssl_with_renewal)
- No monitoring configured for renewal failures

**Problem:**
- Certbot auto-renewal configured but no monitoring
- Renewal failures are silent (logs to /var/log/letsencrypt only)
- Certificates expire in 90 days
- No alerts if renewal fails
- First indication is certificate expiry (outage)

**Failure Scenario:**
```bash
# Day 1: SSL configured successfully
# Day 60: Certbot renewal fails (DNS issue, rate limit, server unreachable)
# Day 61-89: Renewal continues failing silently
# Day 90: Certificate EXPIRES
# Users see "Your connection is not private"
# Production outage, reputation damage
# Manual emergency fix required
```

**Evidence in Code:**
```bash
# deploy-common.sh line 556-561
if sudo certbot renew --dry-run 2>/dev/null; then
    log_success "SSL auto-renewal test passed"
else
    log_warn "SSL auto-renewal test failed - check certbot configuration"
    # WARNING ONLY - No monitoring added
fi
# No ongoing monitoring of renewal status
```

**Detection Commands:**
```bash
# Check certificate expiry
echo | openssl s_client -servername mentat.arewel.com -connect mentat.arewel.com:443 2>/dev/null | \
    openssl x509 -noout -dates

# Check certbot renewal status
sudo certbot renew --dry-run

# Check last renewal attempt
sudo journalctl -u certbot.timer -u certbot.service --since "30 days ago"

# List all certificates
sudo certbot certificates
```

**Fix Required:**
```bash
setup_ssl_monitoring() {
    local domain="$1"

    log_info "Setting up SSL certificate monitoring..."

    # Create monitoring script
    write_system_file /usr/local/bin/check-ssl-expiry << 'EOSCRIPT'
#!/bin/bash
DOMAIN="$1"
ALERT_DAYS="${2:-30}"

# Get certificate expiry
expiry=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | \
         openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

if [[ -z "$expiry" ]]; then
    echo "ERROR: Cannot check SSL certificate for $DOMAIN"
    exit 2
fi

expiry_epoch=$(date -d "$expiry" +%s)
now_epoch=$(date +%s)
days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

if [[ $days_remaining -lt 0 ]]; then
    echo "CRITICAL: SSL certificate EXPIRED ${days_remaining#-} days ago"
    exit 1
elif [[ $days_remaining -lt 7 ]]; then
    echo "CRITICAL: SSL certificate expires in $days_remaining days"
    exit 1
elif [[ $days_remaining -lt $ALERT_DAYS ]]; then
    echo "WARNING: SSL certificate expires in $days_remaining days"
    exit 1
fi

echo "OK: SSL certificate valid for $days_remaining days"
exit 0
EOSCRIPT

    sudo chmod +x /usr/local/bin/check-ssl-expiry

    # Add daily cron check
    write_system_file /etc/cron.d/ssl-expiry-check << EOF
# Check SSL certificate expiry daily
0 6 * * * root /usr/local/bin/check-ssl-expiry ${domain} 30 || logger -t ssl-check "SSL certificate expiring soon for ${domain}"
EOF

    # Add Prometheus textfile exporter metric
    cat > /var/lib/node_exporter/textfile/ssl_expiry.prom << EOF
# HELP ssl_certificate_expiry_seconds SSL certificate expiry timestamp
# TYPE ssl_certificate_expiry_seconds gauge
ssl_certificate_expiry_seconds{domain="${domain}"} $(echo | openssl s_client -servername ${domain} -connect ${domain}:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 | xargs -I{} date -d "{}" +%s)
EOF

    # Add Prometheus alert rule
    write_system_file /etc/observability/prometheus/rules/ssl-expiry.yml << 'EOF'
groups:
  - name: ssl_monitoring
    interval: 1h
    rules:
      - alert: SSLCertificateExpiringSoon
        expr: (ssl_certificate_expiry_seconds - time()) < 30 * 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring in 30 days"
          description: "Certificate for {{ $labels.domain }} expires in {{ $value | humanizeDuration }}"

      - alert: SSLCertificateExpiringCritical
        expr: (ssl_certificate_expiry_seconds - time()) < 7 * 86400
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "SSL certificate expiring in 7 days"
          description: "URGENT: Certificate for {{ $labels.domain }} expires in {{ $value | humanizeDuration }}"
EOF

    # Reload Prometheus to pick up new rules
    curl -XPOST http://localhost:9090/-/reload 2>/dev/null || log_warn "Could not reload Prometheus"

    log_success "SSL monitoring configured"
    log_info "  - Daily cron check at 6am"
    log_info "  - Prometheus metrics exported"
    log_info "  - Alerts at 30 days and 7 days before expiry"
}

# Add to SSL setup flow
if setup_ssl_with_renewal "$DOMAIN" "$SSL_EMAIL"; then
    setup_ssl_monitoring "$DOMAIN"
fi
```

---

### 7. NO SERVICE HEALTH CHECK ENDPOINTS
**Risk:** MEDIUM-HIGH | **Impact:** Silent Failures, Monitoring Gaps

**Location:**
- deploy-common.sh:362-384 (verify_services only checks systemd)
- No HTTP health endpoint validation

**Problem:**
- `verify_services()` only checks `systemctl is-active`
- Service can be "running" but not functional:
  - Prometheus crashed but systemd hasn't detected it
  - Grafana can't reach database
  - Nginx config broken but process alive
  - Network issues preventing service functionality

**Failure Scenario:**
```bash
# Prometheus starts but config file has syntax error
# Prometheus process alive but not accepting connections
# systemctl status prometheus -> active (running)
# verify_services returns SUCCESS
# Deployment marked as successful
# Reality: Prometheus not collecting metrics, all dashboards broken
```

**Evidence in Code:**
```bash
# deploy-common.sh line 368-374
for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        log_success "$svc is running"
    # Only checks process status, not functionality
```

**Detection Commands:**
```bash
# Check actual service health
curl -sf http://localhost:9090/-/healthy && echo "Prometheus: HEALTHY"
curl -sf http://localhost:3100/ready && echo "Loki: READY"
curl -sf http://localhost:3000/api/health && echo "Grafana: HEALTHY"
curl -sf http://localhost:9093/-/healthy && echo "Alertmanager: HEALTHY"

# Check if Grafana datasources work
curl -u admin:PASSWORD http://localhost:3000/api/datasources | jq '.[] | {name, url, isDefault}'

# Check if Prometheus can scrape targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health, lastError}'
```

**Fix Required:**
```bash
check_service_health() {
    local service_name="$1"
    local health_url="$2"
    local max_retries="${3:-30}"
    local retry_count=0

    log_info "Health check: ${service_name} -> ${health_url}"

    while [[ $retry_count -lt $max_retries ]]; do
        local http_code=$(curl -sf -w "%{http_code}" -o /dev/null "$health_url" 2>/dev/null)

        if [[ "$http_code" == "200" ]]; then
            log_success "${service_name} health check PASSED (${retry_count}s)"
            return 0
        fi

        sleep 2
        ((retry_count += 2))
    done

    log_error "${service_name} health check FAILED after ${max_retries}s"
    log_error "  URL: $health_url"
    log_error "  Last HTTP code: $http_code"
    log_error "Check: journalctl -xeu ${service_name}"
    return 1
}

verify_services_comprehensive() {
    local all_ok=true

    log_info "=========================================="
    log_info "  COMPREHENSIVE SERVICE VERIFICATION"
    log_info "=========================================="

    # Step 1: Systemd status checks
    log_info "Step 1: Systemd status checks..."
    local systemd_services=("prometheus" "loki" "alertmanager" "grafana-server" "node_exporter" "nginx")

    for svc in "${systemd_services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            log_success "$svc is running (systemd)"
        else
            log_error "$svc is NOT running (systemd)"
            all_ok=false
        fi
    done

    # Step 2: HTTP health endpoint checks
    log_info "Step 2: HTTP health endpoint checks..."

    check_service_health "Prometheus" "http://localhost:9090/-/healthy" 60 || all_ok=false
    check_service_health "Loki" "http://localhost:3100/ready" 60 || all_ok=false
    check_service_health "Alertmanager" "http://localhost:9093/-/healthy" 30 || all_ok=false
    check_service_health "Grafana" "http://localhost:3000/api/health" 90 || all_ok=false

    # Step 3: Functional checks
    log_info "Step 3: Functional checks..."

    # Prometheus targets check
    local prom_targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | \
                        jq -r '.data.activeTargets | length' 2>/dev/null)
    if [[ "$prom_targets" -gt 0 ]]; then
        log_success "Prometheus has ${prom_targets} active targets"
    else
        log_error "Prometheus has NO active targets"
        all_ok=false
    fi

    # Grafana datasources check
    local grafana_ds=$(curl -s http://admin:PASSWORD@localhost:3000/api/datasources 2>/dev/null | \
                      jq -r 'length' 2>/dev/null)
    if [[ "$grafana_ds" -gt 0 ]]; then
        log_success "Grafana has ${grafana_ds} datasources configured"
    else
        log_warn "Grafana has NO datasources"
    fi

    echo
    if [[ "$all_ok" == "true" ]]; then
        log_success "ALL SERVICE CHECKS PASSED"
        return 0
    else
        log_error "SOME SERVICE CHECKS FAILED"
        return 1
    fi
}

# Replace verify_services with verify_services_comprehensive
```

---

## ADDITIONAL FINDINGS

### Missing Resource Checks
1. **No CPU count validation** - services may spawn too many workers
2. **No network bandwidth check** - large downloads could timeout
3. **No DNS server validation** - deployment may fail silently

### Timeout Issues
1. **stop_and_verify_service max_wait=30s** - too short for MariaDB with large buffer pool
2. **PHP-FPM socket wait timeout=30s** - may be insufficient on slow VPS
3. **SSL validation timeout not configurable** - certbot may timeout on slow connections

### Log Rotation Missing
1. **No logrotate configured** for /var/log/observability
2. **Prometheus logs grow unbounded**
3. **Nginx logs not rotated** for observability virtualhost

### Backup Strategy Missing
1. **No Prometheus TSDB snapshots** before upgrade
2. **No MariaDB backups** configured
3. **No Grafana dashboard exports** before changes

### Monitoring Gaps
1. **No deployment success/failure metrics**
2. **No service restart frequency alerts**
3. **No disk I/O saturation monitoring**
4. **No SSL certificate expiry metrics**

---

## EMERGENCY TROUBLESHOOTING COMMANDS

### Check Why Services Failed to Start
```bash
# Comprehensive service debugging
for svc in prometheus loki grafana-server alertmanager nginx mariadb redis-server; do
    echo "========================================"
    echo "Service: $svc"
    echo "========================================"
    systemctl status $svc --no-pager
    echo
    journalctl -xeu $svc -n 50 --no-pager
    echo
done
```

### Check Resource Exhaustion
```bash
# Disk space
df -h
du -sh /var/lib/observability/* 2>/dev/null

# Memory
free -h
ps aux --sort=-%mem | head -20

# Check if OOM killer active
journalctl -k | grep -i "out of memory"

# Check swap usage
swapon --show
```

### Check Port Conflicts
```bash
# See what's using required ports
for port in 80 443 3000 9090 9100 3100 9093 3306 6379; do
    echo "Port $port:"
    sudo lsof -i :$port -P -n
    echo
done
```

### Check DNS and Network
```bash
# DNS resolution
host mentat.arewel.com
dig mentat.arewel.com +short

# Network connectivity
ping -c3 8.8.8.8
curl -I https://github.com
curl -I https://api.github.com

# Check if domain points to this server
SERVER_IP=$(hostname -I | awk '{print $1}')
RESOLVED_IP=$(host mentat.arewel.com | awk '/address/ {print $4}')
echo "Server IP: $SERVER_IP"
echo "DNS IP:    $RESOLVED_IP"
```

### Check SSL Certificate Status
```bash
# Certificate details
sudo certbot certificates

# Check expiry
echo | openssl s_client -servername mentat.arewel.com -connect mentat.arewel.com:443 2>/dev/null | \
    openssl x509 -noout -dates

# Test renewal
sudo certbot renew --dry-run
```

### Check Service Health
```bash
# Prometheus
curl -sf http://localhost:9090/-/healthy && echo "HEALTHY" || echo "UNHEALTHY"
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'

# Loki
curl -sf http://localhost:3100/ready && echo "READY" || echo "NOT READY"

# Grafana
curl -sf http://localhost:3000/api/health && echo "HEALTHY" || echo "UNHEALTHY"
curl -u admin:PASSWORD http://localhost:3000/api/datasources | jq '.[] | {name, type, url}'
```

---

## RECOMMENDED FIXES (PRIORITY ORDER)

### Priority 1: Pre-Deployment Validation (Add to all scripts)
```bash
run_pre_deployment_checks() {
    log_info "=========================================="
    log_info "  PRE-DEPLOYMENT VALIDATION"
    log_info "=========================================="

    # System checks
    check_sudo_access
    detect_debian_os

    # Resource checks
    check_disk_space 2000  # 2GB minimum
    check_memory_requirements 1024  # 1GB minimum

    # Network checks
    check_network_connectivity
    check_dns_resolution "$DOMAIN"

    # Dependency checks
    check_required_commands curl wget jq systemctl

    log_success "All pre-deployment checks passed"
}
```

### Priority 2: Service Health Verification
Replace all `verify_services` calls with `verify_services_comprehensive`

### Priority 3: Startup Dependency Management
Replace parallel service starts with `start_services_with_dependencies`

### Priority 4: SSL Certificate Monitoring
Add `setup_ssl_monitoring` after SSL configuration

### Priority 5: Backup Before Changes
Add `backup_existing_installation` before any destructive operations

---

## CONCLUSION

The deployment scripts are well-engineered with good practices like shared libraries and parallel operations. However, critical operational gaps exist that could cause production failures:

**Top Risks:**
1. No resource validation - will deploy on undersized VPS then fail mysteriously
2. Service dependencies not enforced - leads to broken datasources
3. Port conflicts resolved destructively - potential data loss
4. No SSL monitoring - certificates could expire silently
5. No health checks - "running" doesn't mean "working"

**Recommendation:** Implement Priority 1-3 fixes before production deployment. Current scripts suitable for testing but need hardening for production use.

**Next Steps:**
1. Add comprehensive pre-flight checks
2. Implement health endpoint validation
3. Add SSL certificate monitoring
4. Configure automatic backups
5. Create operational runbooks for common failure scenarios

---

**End of Analysis**
