# CHOM Deployment System - Operational Incident Analysis
## Critical Issues, Production Readiness Assessment, and Remediation Plan

**Analysis Date:** 2025-12-31
**Analyzed Components:**
- `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh` (2,617 lines)
- `/home/calounx/repositories/mentat/chom/deploy/lib/deploy-common.sh` (682 lines)
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-observability-vps.sh` (743 lines)
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh` (1,165 lines)
- `/home/calounx/repositories/mentat/chom/deploy/configs/inventory.yaml`

**Severity Levels:**
- **CRITICAL**: Blocks deployment or causes data loss
- **HIGH**: Causes deployment failures or silent errors
- **MEDIUM**: Operational friction or inconsistent behavior
- **LOW**: Documentation or UX issues

---

## EXECUTIVE SUMMARY

The CHOM deployment system is **NOT PRODUCTION READY** due to critical infrastructure management gaps:

### Deployment Flow Status: 🔴 CRITICAL ISSUES DETECTED

**Critical Blockers (3):**
1. **Hardware spec detection missing** - Static values in inventory.yaml never updated
2. **No rollback mechanism** - Failed deployments leave system in broken state
3. **Common library not copied to remote VPS** - Scripts fail when sourcing dependencies

**High-Risk Issues (5):**
1. Environment variable passing incomplete
2. No health checks between deployment stages
3. SSH key distribution assumes interactive mode
4. State management doesn't handle partial failures
5. Missing validation of transferred files

**Medium Issues (7):**
1. Domain configuration inconsistencies
2. No pre-deployment backup strategy
3. Firewall rules applied before service verification
4. Credentials saved in plaintext on remote servers
5. No deployment timeout controls
6. Missing dependency version locking
7. Inconsistent error recovery between orchestrator and remote scripts

---

## CRITICAL ISSUE #1: Hardware Spec Detection Never Happens

### Issue Description
The `inventory.yaml` contains static hardware specifications:

```yaml
observability:
  specs:
    cpu: 1           # STATIC - Never updated
    memory_mb: 2048  # STATIC - Never updated
    disk_gb: 20      # STATIC - Never updated

vpsmanager:
  specs:
    cpu: 2           # STATIC - Never updated
    memory_mb: 4096  # STATIC - Never updated
    disk_gb: 80      # STATIC - Never updated
```

**User Request:** "cpu, memory_mb, and disk_gb in inventory.yaml should be filled dynamically"

### Current Reality Check

**Where specs are READ:**
- `deploy-enhanced.sh` lines 1622-1642: Display only (inventory review)
- `deploy-enhanced.sh` lines 1649-1652: Display only (summary table)

**Where specs are VALIDATED:**
- `deploy-enhanced.sh` lines 1369-1401: Remote validation reads ACTUAL specs via SSH
  - CPU: `remote_exec ... "nproc"`
  - RAM: `remote_exec ... "free -m | awk '/^Mem:/ {print \$2}'"`
  - Disk: `remote_exec ... "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'"`

**Where specs are NEVER WRITTEN BACK:** ❌ NOWHERE

### Impact
- **Operational**: Inventory shows wrong specs after deployment
- **Planning**: Cannot track actual vs. requested resources
- **Monitoring**: No baseline for capacity planning
- **Compliance**: Inventory documentation is inaccurate

### Root Cause Analysis
The deployment flow is **one-way**:
1. Orchestrator reads static specs from `inventory.yaml`
2. Orchestrator displays specs to user (lines 1649-1665)
3. Orchestrator validates ACTUAL specs remotely (lines 1369-1401)
4. **MISSING**: Write actual specs back to inventory
5. Deployment proceeds with outdated static values

### Evidence - Code Flow

**deploy-enhanced.sh:1369-1401** - Remote validation (reads actual specs):
```bash
# Check disk space
log_info "Checking disk space..."
local disk_gb
disk_gb=$(remote_exec "$host" "$user" "$port" "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

# Check RAM
log_info "Checking RAM..."
local ram_mb
ram_mb=$(remote_exec "$host" "$user" "$port" "free -m | awk '/^Mem:/ {print \$2}'")

# Check CPU
log_info "Checking CPU count..."
local cpu_count
cpu_count=$(remote_exec "$host" "$user" "$port" "nproc")
```

**deploy-enhanced.sh:1622-1642** - Display (reads inventory.yaml):
```bash
local obs_cpu
obs_cpu=$(get_config '.observability.specs.cpu')
local obs_ram
obs_ram=$(get_config '.observability.specs.memory_mb')
local obs_disk
obs_disk=$(get_config '.observability.specs.disk_gb')
```

**MISSING CODE** - Should exist after validation:
```bash
# Update inventory with actual detected specs
yq eval ".observability.specs.cpu = $cpu_count" -i "$CONFIG_FILE"
yq eval ".observability.specs.memory_mb = $ram_mb" -i "$CONFIG_FILE"
yq eval ".observability.specs.disk_gb = $disk_gb" -i "$CONFIG_FILE"
```

### Recommended Solution

**Option 1: Post-Validation Update (Recommended)**
Update inventory.yaml immediately after remote validation:

```bash
# In validate_remote_vps() function after line 1401
update_inventory_specs() {
    local target=$1
    local cpu=$2
    local ram=$3
    local disk=$4

    log_info "Updating inventory with detected hardware specs..."

    # Atomic update using yq
    yq eval ".${target}.specs.cpu = ${cpu}" -i "$CONFIG_FILE"
    yq eval ".${target}.specs.memory_mb = ${ram}" -i "$CONFIG_FILE"
    yq eval ".${target}.specs.disk_gb = ${disk}" -i "$CONFIG_FILE"

    log_success "Inventory updated: ${cpu} vCPU, ${ram}MB RAM, ${disk}GB disk"
}

# Call after validation in validate_remote_vps()
update_inventory_specs "observability" "$cpu_count" "$ram_mb" "$disk_gb"
```

**Option 2: Pre-Deployment Detection**
Add a `--detect-specs` mode to update inventory before deployment:

```bash
detect_and_update_specs() {
    local target=$1

    log_step "Detecting hardware specs for $target..."

    local ip=$(get_config ".${target}.ip")
    local user=$(get_config ".${target}.ssh_user")
    local port=$(get_config ".${target}.ssh_port")

    # Detect specs
    local cpu=$(remote_exec "$ip" "$user" "$port" "nproc")
    local ram=$(remote_exec "$ip" "$user" "$port" "free -m | awk '/^Mem:/ {print \$2}'")
    local disk=$(remote_exec "$ip" "$user" "$port" "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

    # Update inventory
    update_inventory_specs "$target" "$cpu" "$ram" "$disk"
}

# Usage: ./deploy-enhanced.sh --detect-specs
```

**Option 3: Dynamic Inventory (Most Flexible)**
Replace static inventory.yaml with runtime detection:

```bash
# Store detected specs in state file instead of inventory
update_state_with_specs() {
    local target=$1
    local cpu=$2
    local ram=$3
    local disk=$4

    jq ".${target}.detected_specs = {\"cpu\": ${cpu}, \"memory_mb\": ${ram}, \"disk_gb\": ${disk}}" \
        "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Display detected specs from state (not inventory)
get_detected_specs() {
    local target=$1
    local field=$2
    jq -r ".${target}.detected_specs.${field}" "$STATE_FILE" 2>/dev/null || echo "unknown"
}
```

### Implementation Priority
**CRITICAL** - Implement Option 1 immediately. This ensures:
- Inventory accuracy after first deployment
- Proper capacity planning
- Audit trail for infrastructure changes

---

## CRITICAL ISSUE #2: No Rollback Mechanism

### Issue Description
When deployment fails, the system has **NO rollback capability**:
- Services may be half-installed
- Configuration files may be partially written
- Databases may be initialized but not secured
- Firewall rules may be applied incorrectly

### Evidence - Failure Scenarios

**Scenario 1: MariaDB Fails After Nginx Succeeds**
```bash
# setup-vpsmanager-vps.sh lines 208-324
sudo apt-get install -y -qq nginx          # ✓ Installs successfully
# ... 100 lines later ...
sudo apt-get install -y -qq mariadb-server # ✗ FAILS (disk full)

# Result: Nginx running, no MariaDB, no rollback
# System State: BROKEN - Cannot host PHP apps without database
```

**Scenario 2: Deployment Interrupted (Ctrl+C)**
```bash
# deploy-enhanced.sh lines 220-225 - Signal handler
handle_sigint() {
    echo ""
    log_warn "Received interrupt signal (Ctrl+C)"
    CLEANUP_NEEDED=true
    exit 130  # ❌ No service cleanup, no state restore
}
```

**Scenario 3: Network Failure Mid-Deployment**
```bash
# setup-observability-vps.sh lines 196-207 - Parallel downloads
wget $WGET_OPTS "https://github.com/prometheus/prometheus/releases/..." &
wget $WGET_OPTS "https://github.com/grafana/loki/releases/..." &
wget $WGET_OPTS "https://github.com/prometheus/alertmanager/releases/..." &

# If network fails:
# - Some binaries downloaded, some missing
# - No cleanup of partial downloads
# - No rollback to pre-deployment state
```

### Current State Management Limitations

**State file only tracks completion, not snapshots:**
```json
{
  "started_at": "2025-12-31T10:00:00Z",
  "status": "initialized",
  "observability": {
    "status": "failed",  // ❌ Marks as failed but doesn't restore
    "completed_at": null
  }
}
```

**Missing from state:**
- Pre-deployment service snapshot
- Backup of original configs
- List of installed packages
- Network/firewall rule backup

### Impact
- **Data Loss Risk**: Failed deployments may corrupt existing installations
- **Manual Recovery**: Operators must manually clean up failed deployments
- **Inconsistent State**: Re-running deployment may fail due to leftover artifacts
- **Production Risk**: Cannot safely retry deployments in production

### Root Cause Analysis
The deployment model is **imperative without transactions**:
1. Each step executes sequentially
2. No pre-deployment snapshot taken
3. No "undo" operations defined
4. State only tracks success/failure, not reversibility

### Recommended Solution

**Implement Deployment Checkpoints with Rollback**

```bash
# Add to deploy-common.sh

# Snapshot system state before deployment
create_deployment_snapshot() {
    local snapshot_id="snapshot-$(date +%s)"
    local snapshot_file="/tmp/chom-${snapshot_id}.tar.gz"

    log_info "Creating deployment snapshot..."

    # Backup critical paths
    sudo tar czf "$snapshot_file" \
        /etc/nginx/ \
        /etc/systemd/system/ \
        /var/www/ \
        /etc/observability/ \
        2>/dev/null || true

    # Store snapshot metadata
    echo "$snapshot_file" > "${STATE_DIR}/last_snapshot"

    log_success "Snapshot created: $snapshot_file"
}

# Rollback to last snapshot
rollback_deployment() {
    local snapshot_file
    snapshot_file=$(cat "${STATE_DIR}/last_snapshot" 2>/dev/null)

    if [[ ! -f "$snapshot_file" ]]; then
        log_error "No snapshot found - cannot rollback"
        return 1
    fi

    log_warn "Rolling back to snapshot: $snapshot_file"

    # Stop new services
    log_info "Stopping services..."
    sudo systemctl stop prometheus grafana-server nginx 2>/dev/null || true

    # Restore backup
    log_info "Restoring files..."
    sudo tar xzf "$snapshot_file" -C / 2>/dev/null || true

    # Reload systemd
    sudo systemctl daemon-reload

    # Restart original services
    log_info "Restarting original services..."
    sudo systemctl start nginx 2>/dev/null || true

    log_success "Rollback complete"
}

# Update deployment functions to use snapshots
deploy_with_snapshot() {
    local deploy_function=$1

    # Create snapshot
    create_deployment_snapshot || {
        log_error "Cannot create snapshot - aborting"
        return 1
    }

    # Try deployment
    if ! $deploy_function; then
        log_error "Deployment failed - initiating rollback"
        rollback_deployment
        return 1
    fi

    log_success "Deployment successful - snapshot retained for safety"
    return 0
}
```

**Add to deploy-enhanced.sh signal handlers:**
```bash
handle_sigint() {
    echo ""
    log_warn "Received interrupt signal (Ctrl+C)"
    log_warn "Initiating emergency rollback..."

    # Rollback on interrupt
    rollback_deployment

    CLEANUP_NEEDED=true
    exit 130
}
```

**Add manual rollback command:**
```bash
# Usage: ./deploy-enhanced.sh --rollback
if [[ "$1" == "--rollback" ]]; then
    rollback_deployment
    exit $?
fi
```

### Implementation Priority
**CRITICAL** - Implement for production deployments. Without rollback:
- Failed deployments require manual server rebuilds
- Cannot safely test deployment changes
- High risk of permanent system damage

---

## CRITICAL ISSUE #3: Common Library Not Transferred to Remote VPS

### Issue Description
Both remote setup scripts source `deploy-common.sh`, but this library **is never copied to the remote VPS**.

### Evidence - Dependency Chain

**setup-observability-vps.sh (lines 22-31):**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../lib/deploy-common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "ERROR: Cannot find common library at $COMMON_LIB"
    exit 1
fi

source "$COMMON_LIB"
```

**Expected Path on Remote VPS:**
```
/tmp/setup-observability-vps.sh              # ✓ Copied by deploy-enhanced.sh
/tmp/../lib/deploy-common.sh                 # ✗ NEVER COPIED
```

**Actual Transfer (deploy-enhanced.sh lines 2091-2093):**
```bash
# Copy setup script
log_info "Copying setup script..."
remote_copy "$ip" "$user" "$port" \
    "${SCRIPTS_DIR}/setup-observability-vps.sh" \
    "/tmp/setup-observability-vps.sh"

# ❌ MISSING: Copy common library
# Should be:
# remote_copy "$ip" "$user" "$port" \
#     "${SCRIPT_DIR}/lib/deploy-common.sh" \
#     "/tmp/lib/deploy-common.sh"
```

### Impact
**DEPLOYMENT WILL FAIL 100% OF THE TIME** when scripts try to source the library:

```bash
# Remote execution fails with:
ERROR: Cannot find common library at /tmp/../lib/deploy-common.sh
```

### Current Workaround Detection
This issue may be **hidden in production** if:
1. Scripts are edited to inline common functions (maintenance nightmare)
2. Common library happens to exist from previous deployment (not idempotent)
3. Scripts never actually run remotely (testing gap)

### Recommended Solution

**Option 1: Transfer Library Alongside Scripts (Simple)**
```bash
# In deploy-enhanced.sh deploy_observability() and deploy_vpsmanager()
deploy_observability() {
    # ... existing code ...

    # Copy common library FIRST
    log_info "Copying deployment libraries..."
    remote_exec "$ip" "$user" "$port" "mkdir -p /tmp/lib"
    remote_copy "$ip" "$user" "$port" \
        "${SCRIPT_DIR}/lib/deploy-common.sh" \
        "/tmp/lib/deploy-common.sh"

    # Then copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" \
        "${SCRIPTS_DIR}/setup-observability-vps.sh" \
        "/tmp/setup-observability-vps.sh"

    # ... rest of function ...
}
```

**Option 2: Bundle Scripts with Dependencies (Robust)**
```bash
# Create self-contained deployment package
create_deployment_bundle() {
    local target=$1
    local bundle_dir="/tmp/chom-deploy-$$"

    mkdir -p "$bundle_dir"/{lib,scripts}

    # Copy common library
    cp "${SCRIPT_DIR}/lib/deploy-common.sh" "$bundle_dir/lib/"

    # Copy target script
    cp "${SCRIPTS_DIR}/setup-${target}-vps.sh" "$bundle_dir/scripts/"

    # Create bundle tarball
    tar czf "/tmp/chom-${target}-bundle.tar.gz" -C "$bundle_dir" .

    echo "/tmp/chom-${target}-bundle.tar.gz"
}

# Transfer and extract bundle
deploy_observability() {
    local bundle=$(create_deployment_bundle "observability")

    log_info "Transferring deployment bundle..."
    remote_copy "$ip" "$user" "$port" "$bundle" "/tmp/chom-bundle.tar.gz"

    log_info "Extracting bundle on remote VPS..."
    remote_exec "$ip" "$user" "$port" "mkdir -p /tmp/chom && tar xzf /tmp/chom-bundle.tar.gz -C /tmp/chom"

    log_info "Executing deployment..."
    remote_exec "$ip" "$user" "$port" "cd /tmp/chom && chmod +x scripts/setup-observability-vps.sh && scripts/setup-observability-vps.sh"
}
```

**Option 3: Inline Common Functions (Not Recommended)**
- Duplicates code across scripts
- Maintenance nightmare
- Loses DRY principle

### Implementation Priority
**CRITICAL** - Fix immediately with Option 1. This is a **blocking deployment bug**.

---

## HIGH-RISK ISSUE #1: Incomplete Environment Variable Passing

### Issue Description
Configuration is passed via environment variables, but **inconsistently applied**:

**Observability Stack (setup-observability-vps.sh):**
```bash
# Lines 40-42 - Domain configuration
DOMAIN="${DOMAIN:-mentat.arewel.com}"      # ✓ Uses env var with fallback
SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}" # ✓ Uses env var with fallback
```

**VPSManager Stack (setup-vpsmanager-vps.sh):**
```bash
# Lines 34-36 - Domain configuration
DOMAIN="${DOMAIN:-landsraad.arewel.com}"   # ✓ Uses env var with fallback
SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}" # ✓ Uses env var with fallback
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"   # ⚠️ Defaults to empty string
```

**Orchestrator Passes Only 1 Variable (deploy-enhanced.sh line 2146):**
```bash
remote_exec "$ip" "$user" "$port" \
    "chmod +x /tmp/setup-vpsmanager-vps.sh && \
     OBSERVABILITY_IP=${obs_ip} /tmp/setup-vpsmanager-vps.sh"

# ❌ MISSING: DOMAIN, SSL_EMAIL, other config from inventory.yaml
```

### Impact
- Domains hardcoded to `mentat.arewel.com` and `landsraad.arewel.com`
- SSL email hardcoded to `admin@arewel.com`
- Cannot customize deployments without editing remote scripts
- Inventory.yaml domain config ignored

### Evidence - Config Mismatch

**inventory.yaml specifies:**
```yaml
observability:
  hostname: obs.example.com
  config:
    grafana_domain: grafana.example.com
    alertmanager_email: alerts@example.com
```

**But remote script uses:**
```bash
DOMAIN="mentat.arewel.com"  # Hardcoded, not from inventory
```

### Recommended Solution

**Pass All Config as Environment Variables:**
```bash
# In deploy-enhanced.sh deploy_observability()
deploy_observability() {
    # ... existing code ...

    # Get config from inventory
    local obs_domain=$(get_config '.observability.hostname')
    local grafana_domain=$(get_config '.observability.config.grafana_domain')
    local alert_email=$(get_config '.observability.config.alertmanager_email')

    # Execute with full environment
    log_info "Executing setup (this may take 5-10 minutes)..."
    remote_exec "$ip" "$user" "$port" \
        "chmod +x /tmp/setup-observability-vps.sh && \
         DOMAIN='${obs_domain}' \
         SSL_EMAIL='${alert_email}' \
         /tmp/setup-observability-vps.sh"
}

# Similar for deploy_vpsmanager()
deploy_vpsmanager() {
    # ... existing code ...

    local vps_domain=$(get_config '.vpsmanager.hostname')
    local ssl_email=$(get_config '.vpsmanager.config.ssl_email' 2>/dev/null || echo 'admin@example.com')

    remote_exec "$ip" "$user" "$port" \
        "chmod +x /tmp/setup-vpsmanager-vps.sh && \
         DOMAIN='${vps_domain}' \
         SSL_EMAIL='${ssl_email}' \
         OBSERVABILITY_IP='${obs_ip}' \
         /tmp/setup-vpsmanager-vps.sh"
}
```

**Alternative: Generate Config File**
```bash
# Create config file from inventory
create_remote_config() {
    local target=$1
    local config_file="/tmp/chom-${target}-config.env"

    cat > "$config_file" << EOF
DOMAIN=$(get_config ".${target}.hostname")
SSL_EMAIL=$(get_config ".${target}.config.ssl_email" 2>/dev/null || echo "admin@example.com")
OBSERVABILITY_IP=$(get_config '.observability.ip')
EOF

    echo "$config_file"
}

# Transfer and source config
deploy_observability() {
    local config_file=$(create_remote_config "observability")

    remote_copy "$ip" "$user" "$port" "$config_file" "/tmp/chom-config.env"

    remote_exec "$ip" "$user" "$port" \
        "chmod +x /tmp/setup-observability-vps.sh && \
         source /tmp/chom-config.env && \
         /tmp/setup-observability-vps.sh"
}
```

### Implementation Priority
**HIGH** - Prevents customization, causes confusion about actual configuration

---

## HIGH-RISK ISSUE #2: No Health Checks Between Deployment Stages

### Issue Description
The orchestrator deploys services sequentially but **never verifies they're actually healthy** before proceeding:

```bash
# deploy-enhanced.sh lines 2600-2604
deploy_with_healing "observability"  # Deploys Prometheus, Grafana, etc.
echo ""
deploy_with_healing "vpsmanager"     # ❌ Assumes observability is healthy
```

**What Could Go Wrong:**
1. Observability deployment "succeeds" but Prometheus fails to start
2. VPSManager deploys and tries to connect to Prometheus
3. Metrics collection silently fails
4. No alerts - monitoring is broken from day 1

### Evidence - False Success Reporting

**setup-observability-vps.sh (lines 2099-2111):**
```bash
if remote_exec "$ip" "$user" "$port" \
    "chmod +x /tmp/setup-observability-vps.sh && /tmp/setup-observability-vps.sh"; then
    echo ""
    log_success "Observability Stack deployed successfully!"  # ✓ Process exited 0
    update_state "observability" "completed"
    return 0
fi
```

**But remote script only checks service enable, not health:**
```bash
# setup-observability-vps.sh lines 574-608
sudo systemctl daemon-reload
sudo systemctl enable prometheus node_exporter loki alertmanager grafana-server nginx

# Start services in parallel
sudo systemctl start prometheus &
sudo systemctl start node_exporter &
# ...
wait

sleep 5  # ⚠️ Arbitrary wait, not health check

if verify_services "${SERVICES[@]}"; then  # Only checks systemctl is-active
    VERIFICATION_OK=true
fi
```

**verify_services() weakness (deploy-common.sh lines 366-388):**
```bash
verify_services() {
    local services=("$@")

    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then  # ✓ Process running
            log_success "$svc is running"
        else
            log_error "$svc failed to start"
            all_ok=false
        fi
    done

    # ❌ MISSING:
    # - HTTP health check (curl http://localhost:9090/-/healthy)
    # - Metric scrape validation
    # - Log ingestion test
}
```

### Impact
- **Silent Failures**: Services "running" but non-functional
- **Broken Monitoring**: VPSManager metrics never reach Prometheus
- **No Rollback**: Deployment completes despite broken services
- **Production Risk**: Looks successful but monitoring doesn't work

### Recommended Solution

**Add Comprehensive Health Checks:**

```bash
# Add to deploy-common.sh

# Health check for Prometheus
check_prometheus_health() {
    local host=$1
    local timeout=${2:-30}

    log_info "Waiting for Prometheus to be healthy..."

    for i in $(seq 1 $timeout); do
        if curl -sf "http://${host}:9090/-/healthy" >/dev/null 2>&1; then
            log_success "Prometheus is healthy"

            # Verify metrics are being scraped
            local targets=$(curl -s "http://${host}:9090/api/v1/targets" | \
                          jq -r '.data.activeTargets | length')

            if [[ "$targets" -gt 0 ]]; then
                log_success "Prometheus scraping $targets targets"
                return 0
            else
                log_warn "Prometheus healthy but no targets configured"
            fi
        fi

        sleep 1
    done

    log_error "Prometheus health check failed after ${timeout}s"
    return 1
}

# Health check for Grafana
check_grafana_health() {
    local host=$1
    local timeout=${2:-30}

    log_info "Waiting for Grafana to be healthy..."

    for i in $(seq 1 $timeout); do
        if curl -sf "http://${host}:3000/api/health" >/dev/null 2>&1; then
            log_success "Grafana is healthy"

            # Verify datasources are configured
            local datasources=$(curl -sf -u admin:admin \
                              "http://${host}:3000/api/datasources" | \
                              jq -r '. | length')

            if [[ "$datasources" -gt 0 ]]; then
                log_success "Grafana has $datasources datasources configured"
                return 0
            else
                log_warn "Grafana healthy but no datasources configured"
            fi
        fi

        sleep 1
    done

    log_error "Grafana health check failed after ${timeout}s"
    return 1
}

# Health check for Loki
check_loki_health() {
    local host=$1
    local timeout=${2:-30}

    log_info "Waiting for Loki to be healthy..."

    for i in $(seq 1 $timeout); do
        if curl -sf "http://${host}:3100/ready" >/dev/null 2>&1; then
            log_success "Loki is healthy"
            return 0
        fi

        sleep 1
    done

    log_error "Loki health check failed after ${timeout}s"
    return 1
}

# Comprehensive stack health check
verify_observability_stack_health() {
    local host=$1

    log_step "Verifying Observability Stack health..."

    local failures=0

    check_prometheus_health "$host" || ((failures++))
    check_grafana_health "$host" || ((failures++))
    check_loki_health "$host" || ((failures++))

    if [[ $failures -eq 0 ]]; then
        log_success "All Observability services are healthy"
        return 0
    else
        log_error "$failures health checks failed"
        return 1
    fi
}
```

**Update Orchestrator to Use Health Checks:**

```bash
# In deploy-enhanced.sh deploy_observability()
deploy_observability() {
    # ... existing deployment code ...

    if remote_exec "$ip" "$user" "$port" \
        "chmod +x /tmp/setup-observability-vps.sh && /tmp/setup-observability-vps.sh"; then
        echo ""
        log_success "Observability Stack installation complete"

        # ✓ ADD: Health check before marking complete
        log_info "Verifying stack health..."
        if retry_with_healing \
            "Observability health check" \
            "verify_observability_stack_health '$ip'" \
            "autofix_service_conflict '$ip' '$user' '$port' 'prometheus'"; then

            log_success "Observability Stack deployed and verified healthy!"
            update_state "observability" "completed"
            return 0
        else
            log_error "Observability Stack installed but health checks failed"
            log_warn "Check logs with: ssh ${user}@${ip} journalctl -xeu prometheus"
            update_state "observability" "failed"
            return 1
        fi
    fi
}
```

**Add Inter-Stack Health Check:**

```bash
# Before deploying VPSManager, verify Observability is reachable
deploy_vpsmanager() {
    # ... existing code ...

    # ✓ ADD: Verify observability stack is accessible from VPSManager VPS
    log_info "Verifying connectivity to Observability stack..."
    if ! remote_exec "$ip" "$user" "$port" \
        "curl -sf http://${obs_ip}:9090/-/healthy >/dev/null"; then

        log_error "Cannot reach Observability stack from VPSManager VPS"
        log_error "Check firewall rules and network connectivity"
        return 1
    fi

    log_success "Observability stack is reachable from VPSManager VPS"

    # ... continue with deployment ...
}
```

### Implementation Priority
**HIGH** - Critical for production reliability. Without health checks:
- Broken deployments appear successful
- Issues discovered weeks later when monitoring needed
- No early warning of misconfiguration

---

## HIGH-RISK ISSUE #3: SSH Key Distribution Assumes Interactive Mode

### Issue Description
The deployment heavily relies on **interactive SSH key copying** which breaks in CI/CD and automated environments.

### Evidence - Manual Intervention Required

**deploy-enhanced.sh (lines 866-942):**
```bash
if [[ "$DRY_RUN" != "true" && "$INTERACTIVE_MODE" != "true" ]]; then
    # Non-interactive mode: offer to run ssh-copy-id automatically
    log_info "Attempting to copy SSH keys automatically..."
    log_warn "You will be prompted for passwords..."  # ⚠️ Requires human input

    if ssh-copy-id -i "${key_path}.pub" -p "${obs_port}" "${obs_user}@${obs_ip}"; then
        log_success "Key copied to Observability VPS"
    else
        log_error "Failed to copy key to Observability VPS"
        copy_failed=true
    fi
}
```

**Problems:**
1. **CI/CD Blocker**: Cannot run in automated pipelines (requires password input)
2. **First-Time Only**: Only works on first deployment, not idempotent
3. **No Alternative**: If `ssh-copy-id` fails, deployment must be aborted
4. **Manual Recovery**: User must manually fix SSH before retrying

### Impact on Different Environments

| Environment | Impact |
|-------------|--------|
| **Local Developer** | Works (can enter password) |
| **CI/CD Pipeline** | FAILS (no interactive input) |
| **Terraform/Ansible** | FAILS (no TTY) |
| **Scheduled Deployments** | FAILS (no human present) |
| **Emergency Recovery** | BLOCKED (requires manual SSH setup first) |

### Current Workaround
Users must **manually** run these commands before deployment:
```bash
ssh-copy-id -i ./keys/chom_deploy_key.pub -p 22 deploy@obs.example.com
ssh-copy-id -i ./keys/chom_deploy_key.pub -p 22 deploy@wp.example.com
```

### Recommended Solution

**Option 1: Add Cloud-Init Support (Recommended for VPS providers)**

```bash
# Generate cloud-init config with embedded SSH key
generate_cloudinit_config() {
    local ssh_key_pub=$(cat "${KEYS_DIR}/chom_deploy_key.pub")

    cat > "/tmp/chom-cloudinit.yaml" << EOF
#cloud-config
users:
  - name: deploy
    groups: sudo
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_key_pub}

packages:
  - curl
  - wget
  - git

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
EOF

    log_success "Cloud-init config generated: /tmp/chom-cloudinit.yaml"
    log_info "Apply this when creating VPS instances"
}

# Usage: ./deploy-enhanced.sh --generate-cloudinit
```

**Option 2: Support SSH Key Injection via API (OVH, DigitalOcean, etc.)**

```bash
# Add to inventory.yaml
vps_provider:
  type: ovh  # or digitalocean, hetzner, vultr
  api_key: "${OVH_API_KEY}"

# Inject SSH key via provider API
inject_ssh_key_via_api() {
    local provider=$(get_config '.vps_provider.type')
    local api_key=$(get_config '.vps_provider.api_key')
    local vps_id=$(get_config ".${target}.vps_id")

    case "$provider" in
        ovh)
            # OVH API example
            ovh_inject_ssh_key "$vps_id" "$api_key" "${KEYS_DIR}/chom_deploy_key.pub"
            ;;
        digitalocean)
            # DigitalOcean API example
            doctl_inject_ssh_key "$vps_id" "${KEYS_DIR}/chom_deploy_key.pub"
            ;;
        *)
            log_error "Unsupported provider: $provider"
            return 1
            ;;
    esac
}
```

**Option 3: Fallback to Root Key + Sudo User Creation**

```bash
# If ssh-copy-id fails, try root key approach
copy_ssh_key_with_fallback() {
    local host=$1
    local user=$2
    local port=$3
    local root_password=$4  # Optional: from environment or prompt once

    log_info "Attempting to copy SSH key to ${user}@${host}..."

    # Try normal ssh-copy-id first
    if ssh-copy-id -i "${key_path}.pub" -p "$port" "${user}@${host}" 2>/dev/null; then
        log_success "SSH key copied successfully"
        return 0
    fi

    # Fallback: Use sshpass if available
    if command -v sshpass >/dev/null; then
        log_warn "Trying fallback method with sshpass..."

        if [[ -n "$root_password" ]]; then
            sshpass -p "$root_password" \
                ssh-copy-id -i "${key_path}.pub" -p "$port" "${user}@${host}"
            return $?
        fi
    fi

    # Final fallback: Generate setup script for manual execution
    log_error "Automatic SSH key copy failed"
    generate_manual_ssh_setup_script "$host" "$user" "$port"
    return 1
}

# Generate script for manual execution on VPS
generate_manual_ssh_setup_script() {
    local host=$1
    local user=$2
    local port=$3

    local ssh_key=$(cat "${KEYS_DIR}/chom_deploy_key.pub")

    cat > "/tmp/setup-ssh-${host}.sh" << EOF
#!/bin/bash
# Run this script ON the VPS as root to setup SSH access

# Create user if not exists
if ! id -u ${user} >/dev/null 2>&1; then
    useradd -m -s /bin/bash ${user}
    echo "${user}:$(openssl rand -base64 12)" | chpasswd
fi

# Setup sudo
echo "${user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${user}
chmod 0440 /etc/sudoers.d/${user}

# Setup SSH key
mkdir -p /home/${user}/.ssh
echo "${ssh_key}" >> /home/${user}/.ssh/authorized_keys
chmod 700 /home/${user}/.ssh
chmod 600 /home/${user}/.ssh/authorized_keys
chown -R ${user}:${user} /home/${user}/.ssh

echo "SSH setup complete for user: ${user}"
EOF

    chmod +x "/tmp/setup-ssh-${host}.sh"

    log_info "Manual setup script generated: /tmp/setup-ssh-${host}.sh"
    log_info "Copy and run this on the VPS as root:"
    log_info "  scp /tmp/setup-ssh-${host}.sh root@${host}:/tmp/"
    log_info "  ssh root@${host} 'bash /tmp/setup-ssh-${host}.sh'"
}
```

**Option 4: Add Terraform/Ansible Integration (Best for Infrastructure-as-Code)**

```bash
# Generate Terraform config
generate_terraform_config() {
    local ssh_key_pub=$(cat "${KEYS_DIR}/chom_deploy_key.pub")

    cat > "/tmp/chom-terraform.tf" << EOF
# CHOM Infrastructure as Code
variable "ovh_endpoint" {
  default = "ovh-eu"
}

variable "ovh_application_key" {}
variable "ovh_application_secret" {}
variable "ovh_consumer_key" {}

provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

resource "ovh_cloud_project_vps" "observability" {
  project_id   = var.project_id
  name         = "chom-observability"
  flavor       = "d2-2"  # 2 vCPU, 2GB RAM
  region       = "GRA11"
  image        = "Debian 13"

  ssh_keys = [
    "${ssh_key_pub}"
  ]

  user_data = <<-EOF
    #!/bin/bash
    useradd -m -s /bin/bash deploy
    echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
    chmod 0440 /etc/sudoers.d/deploy
  EOF
}

output "observability_ip" {
  value = ovh_cloud_project_vps.observability.ip_address
}
EOF

    log_success "Terraform config generated: /tmp/chom-terraform.tf"
    log_info "Run: cd /tmp && terraform init && terraform apply"
}
```

### Implementation Priority
**HIGH** - Blocks automation. Implement Option 1 (cloud-init) for immediate relief, then add Option 3 (fallback) for robustness.

---

## MEDIUM ISSUE #1: Domain Configuration Inconsistencies

### Issue Description
Domain configuration is spread across multiple sources with unclear precedence:

**Source 1: inventory.yaml**
```yaml
observability:
  hostname: obs.example.com
  config:
    grafana_domain: grafana.example.com
```

**Source 2: Environment variables in remote scripts**
```bash
# setup-observability-vps.sh line 41
DOMAIN="${DOMAIN:-mentat.arewel.com}"  # Hardcoded fallback
```

**Source 3: SSL email configuration**
```yaml
observability:
  config:
    alertmanager_email: alerts@example.com  # Different from SSL email
```

### Confusion Matrix

| Config Key | inventory.yaml | Remote Script Default | Used For | Actual Precedence |
|------------|----------------|----------------------|----------|-------------------|
| `hostname` | `obs.example.com` | N/A | Display only | Never used |
| `DOMAIN` | Not in inventory | `mentat.arewel.com` | Nginx config | **Script default wins** |
| `grafana_domain` | `grafana.example.com` | N/A | Intended for Grafana | Never passed |
| `alertmanager_email` | `alerts@example.com` | N/A | Alertmanager | Never passed |
| `SSL_EMAIL` | Not in inventory | `admin@arewel.com` | Certbot | **Script default wins** |

### Impact
- **User Confusion**: inventory.yaml appears configurable but is ignored
- **Hardcoded Domains**: Deployments use `mentat.arewel.com` regardless of config
- **SSL Mismatch**: Certificates issued to wrong domain
- **Documentation Gap**: No clear mapping between inventory fields and actual usage

### Recommended Solution

**Standardize Configuration Hierarchy:**

```yaml
# inventory.yaml - Single source of truth
observability:
  # Primary domain (used for all services)
  domain: obs.example.com

  # SSL configuration
  ssl:
    email: admin@example.com
    enabled: true

  # Service-specific overrides (optional)
  services:
    grafana:
      subdomain: grafana  # Creates grafana.obs.example.com
      port: 3000
    prometheus:
      subdomain: prometheus
      port: 9090
    loki:
      subdomain: loki
      port: 3100

  # Alert configuration
  alerts:
    email: alerts@example.com
    slack_webhook: https://hooks.slack.com/...
```

**Update Remote Scripts to Accept Structured Config:**

```bash
# setup-observability-vps.sh
# Remove hardcoded defaults, require env vars
if [[ -z "${CHOM_DOMAIN}" ]]; then
    echo "ERROR: CHOM_DOMAIN not set. This script must be called by deploy-enhanced.sh"
    exit 1
fi

DOMAIN="${CHOM_DOMAIN}"
SSL_EMAIL="${CHOM_SSL_EMAIL}"
GRAFANA_SUBDOMAIN="${CHOM_GRAFANA_SUBDOMAIN:-grafana}"

# Construct service URLs
GRAFANA_URL="${GRAFANA_SUBDOMAIN}.${DOMAIN}"
```

**Orchestrator Passes Full Config:**

```bash
# deploy-enhanced.sh
deploy_observability() {
    # Extract config from inventory
    local domain=$(get_config '.observability.domain')
    local ssl_email=$(get_config '.observability.ssl.email')
    local grafana_subdomain=$(get_config '.observability.services.grafana.subdomain' 2>/dev/null || echo 'grafana')

    # Validate required fields
    if [[ -z "$domain" || "$domain" == "null" ]]; then
        log_error "observability.domain is required in inventory.yaml"
        return 1
    fi

    # Execute with validated config
    remote_exec "$ip" "$user" "$port" \
        "chmod +x /tmp/setup-observability-vps.sh && \
         CHOM_DOMAIN='${domain}' \
         CHOM_SSL_EMAIL='${ssl_email}' \
         CHOM_GRAFANA_SUBDOMAIN='${grafana_subdomain}' \
         /tmp/setup-observability-vps.sh"
}
```

### Implementation Priority
**MEDIUM** - Causes confusion but has workaround (manual editing). Should be fixed before GA release.

---

## MEDIUM ISSUE #2: No Pre-Deployment Backup Strategy

### Issue Description
The deployment **overwrites existing installations** without backup:

```bash
# setup-observability-vps.sh lines 273-280
log_info "Installing binaries..."
sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /opt/observability/bin/

# ❌ No backup of existing binaries
# ❌ No check if previous version exists
# ❌ No rollback if new version fails
```

### Risk Scenarios

**Scenario 1: Re-deployment Fails**
```
1. v1.0 deployed successfully, Prometheus running
2. Deploy v1.1
3. Binary download succeeds
4. Service stop succeeds
5. Binary copy succeeds
6. Service start FAILS (bad config)
7. Result: No Prometheus (v1.0 gone, v1.1 broken)
```

**Scenario 2: Configuration Corruption**
```
1. Custom Grafana dashboards configured
2. Re-run deployment
3. /etc/observability/ wiped and replaced with defaults
4. Result: All custom dashboards lost
```

**Scenario 3: Database Overwrite**
```
1. MariaDB has production data
2. Re-run deployment
3. MariaDB reinstalled
4. Result: ❌ ALL DATA LOST (no backup taken)
```

### Current "Stop Before Replace" is Insufficient

```bash
# deploy-common.sh lines 190-261
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"

    # Stops service and kills processes
    sudo systemctl stop "$service_name"
    # ... force kill logic ...

    # ❌ MISSING: Backup binary before replacement
    # ❌ MISSING: Backup config before overwrite
    # ❌ MISSING: Snapshot data directories
}
```

### Recommended Solution

**Add Backup Before Destructive Operations:**

```bash
# Add to deploy-common.sh

# Backup file/directory with timestamp
backup_before_replace() {
    local path=$1
    local backup_dir="/var/backups/chom"
    local timestamp=$(date +%Y%m%d-%H%M%S)

    if [[ ! -e "$path" ]]; then
        log_debug "No existing file to backup: $path"
        return 0
    fi

    sudo mkdir -p "$backup_dir"

    local basename=$(basename "$path")
    local backup_path="${backup_dir}/${basename}.${timestamp}.backup"

    log_info "Backing up: $path -> $backup_path"

    if [[ -d "$path" ]]; then
        sudo cp -a "$path" "$backup_path"
    else
        sudo cp "$path" "$backup_path"
    fi

    log_success "Backup created: $backup_path"
    echo "$backup_path" > "${STATE_DIR}/last_backup_${basename}"
}

# Restore from last backup
restore_from_backup() {
    local target_basename=$1
    local backup_ref="${STATE_DIR}/last_backup_${target_basename}"

    if [[ ! -f "$backup_ref" ]]; then
        log_error "No backup reference found for: $target_basename"
        return 1
    fi

    local backup_path=$(cat "$backup_ref")

    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi

    local target_path=$(dirname "$backup_path" | sed 's|/var/backups/chom|/opt/observability/bin|')/$target_basename

    log_warn "Restoring from backup: $backup_path -> $target_path"

    if [[ -d "$backup_path" ]]; then
        sudo cp -a "$backup_path" "$target_path"
    else
        sudo cp "$backup_path" "$target_path"
    fi

    log_success "Restored: $target_path"
}

# Update stop_and_verify_service to include backup
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"

    # Backup before stopping
    backup_before_replace "$binary_path"

    # ... existing stop logic ...
}
```

**Add Backup to Remote Scripts:**

```bash
# In setup-observability-vps.sh before line 273
log_info "Backing up existing installation..."

# Backup binaries
if [[ -d /opt/observability/bin ]]; then
    backup_before_replace "/opt/observability/bin"
fi

# Backup configs
if [[ -d /etc/observability ]]; then
    backup_before_replace "/etc/observability"
fi

# Backup data (DO NOT backup if it's too large)
if [[ -d /var/lib/observability ]]; then
    local data_size=$(du -sm /var/lib/observability | awk '{print $1}')

    if [[ $data_size -lt 1000 ]]; then  # Less than 1GB
        backup_before_replace "/var/lib/observability"
    else
        log_warn "Data directory is ${data_size}MB - skipping backup (too large)"
        log_warn "Manual backup recommended before deployment"
    fi
fi

log_info "Installing binaries..."
# ... existing installation ...
```

**Add Retention Policy:**

```bash
# Clean old backups (keep last 5)
cleanup_old_backups() {
    local backup_dir="/var/backups/chom"
    local keep_count=5

    log_info "Cleaning old backups (keeping last ${keep_count})..."

    for pattern in "prometheus" "grafana" "nginx"; do
        local count=$(ls -1 "${backup_dir}/${pattern}."* 2>/dev/null | wc -l)

        if [[ $count -gt $keep_count ]]; then
            log_info "Removing old ${pattern} backups..."
            ls -1t "${backup_dir}/${pattern}."* | tail -n +$((keep_count + 1)) | xargs -r sudo rm -rf
        fi
    done

    log_success "Backup cleanup complete"
}
```

### Implementation Priority
**MEDIUM** - Essential for re-deployments and upgrades. Prevents data loss during updates.

---

## MEDIUM ISSUE #3: Firewall Rules Applied Before Service Verification

### Issue Description
UFW firewall rules are applied **before verifying services work**, potentially locking out access if deployment fails.

### Evidence - Risky Ordering

**setup-observability-vps.sh:**
```bash
# Line 553: Configure firewall BEFORE starting services
configure_firewall_base
log_info "Adding observability-specific firewall rules..."
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3100/tcp
sudo ufw allow 9090/tcp
sudo ufw --force enable

# Line 566: Validate ports AFTER firewall enabled
validate_ports_available 9090 9100 3100 9093 3000

# Line 574: Start services AFTER firewall enabled
sudo systemctl start prometheus
sudo systemctl start grafana-server
```

**Problem Flow:**
```
1. Firewall blocks all ports except SSH, 80, 443, 3100, 9090
2. Try to start Prometheus on port 9090
3. Prometheus fails to start (config error)
4. Port 9090 firewall rule is useless
5. If SSH also fails: LOCKED OUT
```

### Safer Ordering

```bash
# 1. Install packages (no network exposure yet)
install_packages

# 2. Write configurations
write_configs

# 3. Start services WITHOUT enabling firewall
start_services

# 4. Verify services are healthy
verify_services_health

# 5. ONLY THEN enable firewall
if all_services_healthy; then
    enable_firewall
else
    log_error "Services not healthy - NOT enabling firewall"
    log_error "Fix issues and run: sudo ufw enable"
fi
```

### Additional Risk: Default Deny

**deploy-common.sh line 318:**
```bash
configure_firewall_base() {
    sudo ufw --force reset
    sudo ufw default deny incoming  # ⚠️ Denies everything
    sudo ufw default allow outgoing
    sudo ufw allow ssh
}
```

**If SSH port is non-standard:**
```yaml
observability:
  ssh_port: 2222  # Custom SSH port
```

**But firewall rule:**
```bash
sudo ufw allow ssh  # Allows port 22, NOT 2222
```

**Result:** Locked out after `ufw enable`

### Recommended Solution

**1. Apply Firewall AFTER Service Verification:**

```bash
# In setup-observability-vps.sh
# Move firewall configuration to AFTER verification

# Line 569: Start services FIRST
log_info "Starting all services..."
sudo systemctl daemon-reload
sudo systemctl enable prometheus node_exporter loki alertmanager grafana-server nginx
sudo systemctl start prometheus node_exporter loki alertmanager grafana-server nginx

sleep 5

# Line 602: Verify services SECOND
SERVICES=("prometheus" "node_exporter" "loki" "alertmanager" "grafana-server" "nginx")
if verify_services "${SERVICES[@]}"; then
    VERIFICATION_OK=true
else
    VERIFICATION_OK=false
    log_error "Service verification failed - NOT enabling firewall"
fi

# NEW: Enable firewall ONLY if services verified
if [[ "$VERIFICATION_OK" == "true" ]]; then
    log_info "Services verified - enabling firewall..."
    configure_firewall_base
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow 3100/tcp
    sudo ufw allow 9090/tcp
    sudo ufw --force enable
    log_success "Firewall enabled"
else
    log_warn "Firewall NOT enabled due to service failures"
    log_warn "Manually enable after fixing: sudo ufw enable"
fi
```

**2. Use Actual SSH Port from Inventory:**

```bash
# In deploy-common.sh
configure_firewall_base() {
    local ssh_port=${1:-22}  # Accept SSH port parameter

    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Use actual SSH port, not default
    sudo ufw allow "${ssh_port}/tcp" comment 'SSH'

    log_success "Firewall base rules configured (SSH port: ${ssh_port})"
}

# Usage in remote scripts:
configure_firewall_base "$SSH_PORT"  # Pass actual port
```

**3. Add Firewall Rollback on Failure:**

```bash
# If service verification fails, remove firewall rules
rollback_firewall() {
    log_warn "Rolling back firewall to allow all (development mode)"
    sudo ufw --force reset
    sudo ufw default allow incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    log_info "Firewall set to permissive mode - secure manually after fixes"
}

# Use in error handler
if [[ "$VERIFICATION_OK" == "false" ]]; then
    rollback_firewall
fi
```

### Implementation Priority
**MEDIUM** - Risk of lockout during deployment. Should be fixed before production deployments on non-standard SSH ports.

---

## SUMMARY OF RECOMMENDATIONS

### Immediate Actions (CRITICAL - Fix Before Next Deployment)

1. **Implement Library Transfer** (Issue #3)
   - Copy `deploy-common.sh` to remote VPS before executing scripts
   - Test: Verify scripts can source library remotely

2. **Add Dynamic Hardware Detection** (Issue #1)
   - Update `inventory.yaml` with actual specs after validation
   - Display detected vs. configured specs

3. **Implement Basic Rollback** (Issue #2)
   - Create system snapshot before deployment
   - Add `--rollback` command to restore snapshot
   - Document rollback procedure

### High-Priority Improvements (HIGH - Fix This Sprint)

4. **Fix Configuration Passing** (Issue HIGH-1)
   - Pass all inventory.yaml config as environment variables
   - Remove hardcoded domains from remote scripts

5. **Add Health Checks** (Issue HIGH-2)
   - Verify Prometheus, Grafana, Loki are responding
   - Check inter-stack connectivity before proceeding

6. **Support Non-Interactive SSH** (Issue HIGH-3)
   - Add cloud-init config generation
   - Support API-based SSH key injection
   - Document manual setup fallback

### Medium-Priority Hardening (MEDIUM - Next Release)

7. **Standardize Domain Config** (Issue MED-1)
   - Single source of truth for domains
   - Validate config before remote execution

8. **Add Pre-Deployment Backup** (Issue MED-2)
   - Backup binaries, configs, and data
   - Implement retention policy (keep last 5)

9. **Fix Firewall Ordering** (Issue MED-3)
   - Apply firewall AFTER service verification
   - Use actual SSH port from inventory
   - Add firewall rollback on failure

---

## TESTING CHECKLIST

Before marking deployment production-ready, verify:

### Deployment Flow Tests
- [ ] Fresh deployment on clean VPS (no existing services)
- [ ] Re-deployment on existing installation (upgrade scenario)
- [ ] Deployment with custom domains (non-default config)
- [ ] Deployment with non-standard SSH ports (not 22)
- [ ] Deployment interruption (Ctrl+C) and resume
- [ ] Network failure during download (retry logic)
- [ ] Service failure during start (rollback logic)

### Configuration Tests
- [ ] inventory.yaml with placeholder IPs (0.0.0.0) - should fail early
- [ ] inventory.yaml with invalid IP format - should fail validation
- [ ] inventory.yaml with custom domains - should use custom, not hardcoded
- [ ] Environment variable override - should take precedence
- [ ] Missing required config fields - should fail with clear message

### SSH and Authentication Tests
- [ ] SSH key not yet copied - should guide user or auto-copy
- [ ] SSH key copied but wrong permissions - should auto-fix
- [ ] SSH port blocked by firewall - should detect and report
- [ ] Passwordless sudo not configured - should fail with fix instructions
- [ ] Non-interactive mode (--auto-approve) - should work without prompts

### Health and Verification Tests
- [ ] All services start successfully - should mark complete
- [ ] Prometheus fails to start - should fail deployment
- [ ] Grafana starts but datasources missing - should warn
- [ ] Inter-stack connectivity fails - should abort VPSManager deployment
- [ ] Firewall blocks service ports - should detect and rollback

### Rollback and Recovery Tests
- [ ] Manual rollback (--rollback) - should restore previous state
- [ ] Automatic rollback on failure - should restore working services
- [ ] Snapshot cleanup - should keep last 5 backups
- [ ] Re-deployment after rollback - should succeed

### Production Readiness Tests
- [ ] Deploy to production-sized VPS (real OVH/DigitalOcean instance)
- [ ] Verify SSL certificate generation (certbot)
- [ ] Check monitoring data flow (metrics, logs, traces)
- [ ] Test alert notifications (email, Slack)
- [ ] Validate security hardening (firewall, sudo, SSH)
- [ ] Performance under load (concurrent deployments)

---

## DEPLOYMENT WORKFLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────┐
│ CHOM Deployment Orchestrator (deploy-enhanced.sh)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. PRE-FLIGHT VALIDATION                                       │
│     ├─ Check dependencies (yq, jq, ssh, scp)                   │
│     ├─ Validate inventory.yaml                                 │
│     ├─ Generate/check SSH keys                                 │
│     └─ Test SSH connectivity to all VPS                        │
│                                                                 │
│  2. REMOTE VALIDATION (per VPS)                                 │
│     ├─ Check OS version (Debian 13)                            │
│     ├─ Check disk space (20GB+)                                │
│     ├─ Check RAM (1GB+)                                         │
│     ├─ Check CPU (1+)                                           │
│     ├─ Check passwordless sudo                                 │
│     └─ ⚠️ MISSING: Update inventory.yaml with detected specs   │
│                                                                 │
│  3. DEPLOYMENT PLAN & CONFIRMATION                              │
│     ├─ Display what will be deployed                           │
│     ├─ Show estimated time                                     │
│     └─ Get user confirmation (unless --auto-approve)           │
│                                                                 │
│  4. DEPLOY OBSERVABILITY STACK                                  │
│     ├─ ⚠️ MISSING: Copy deploy-common.sh to VPS                │
│     ├─ Copy setup-observability-vps.sh to /tmp/                │
│     ├─ ⚠️ PARTIAL: Pass OBSERVABILITY_IP (missing DOMAIN, etc) │
│     ├─ Execute remote script via SSH                           │
│     ├─ ⚠️ MISSING: Health checks (Prometheus, Grafana, Loki)   │
│     └─ Mark state as completed                                 │
│                                                                 │
│  5. DEPLOY VPSMANAGER STACK                                     │
│     ├─ ⚠️ MISSING: Copy deploy-common.sh to VPS                │
│     ├─ Copy setup-vpsmanager-vps.sh to /tmp/                   │
│     ├─ ⚠️ PARTIAL: Pass OBSERVABILITY_IP (missing other config)│
│     ├─ Execute remote script via SSH                           │
│     ├─ ⚠️ MISSING: Health checks (Nginx, PHP, MariaDB)         │
│     ├─ ⚠️ MISSING: Verify connectivity to Observability        │
│     └─ Mark state as completed                                 │
│                                                                 │
│  6. POST-DEPLOYMENT SUMMARY                                     │
│     ├─ Display access URLs                                     │
│     ├─ Show credentials (Grafana, MariaDB)                     │
│     └─ ⚠️ MISSING: Verify end-to-end monitoring flow           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                |
                                | SSH + SCP
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Remote VPS (Observability)                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  setup-observability-vps.sh                                     │
│  ├─ ⚠️ ERROR: Cannot find deploy-common.sh                     │
│  │   (Library not transferred)                                 │
│  │                                                              │
│  ├─ Load common library                                        │
│  ├─ Detect OS (Debian 12/13)                                   │
│  ├─ Run cleanup (stop old services)                            │
│  │                                                              │
│  ├─ DOWNLOAD BINARIES (parallel)                               │
│  │   ├─ Prometheus                                             │
│  │   ├─ Node Exporter                                          │
│  │   ├─ Loki                                                   │
│  │   └─ Alertmanager                                           │
│  │                                                              │
│  ├─ ⚠️ MISSING: Backup existing binaries before replace        │
│  ├─ Install binaries                                           │
│  ├─ Write configuration files                                  │
│  ├─ Create systemd services                                    │
│  │                                                              │
│  ├─ Configure Nginx reverse proxy                              │
│  ├─ ⚠️ RISK: Configure firewall BEFORE starting services       │
│  ├─ Validate ports available                                   │
│  ├─ Start all services                                         │
│  ├─ Verify services (systemctl is-active only)                 │
│  ├─ ⚠️ MISSING: HTTP health checks                             │
│  │                                                              │
│  ├─ Setup SSL (certbot)                                        │
│  └─ Save credentials to /root/.observability-credentials       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Remote VPS (VPSManager)                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  setup-vpsmanager-vps.sh                                        │
│  ├─ ⚠️ ERROR: Cannot find deploy-common.sh                     │
│  │   (Library not transferred)                                 │
│  │                                                              │
│  ├─ Load common library                                        │
│  ├─ Detect OS (Debian 12/13)                                   │
│  ├─ Run cleanup (stop old services)                            │
│  │                                                              │
│  ├─ INSTALL PACKAGES (batch)                                   │
│  │   ├─ Nginx                                                  │
│  │   ├─ PHP 8.2, 8.3, 8.4                                      │
│  │   ├─ MariaDB                                                │
│  │   ├─ Redis                                                  │
│  │   └─ Node Exporter                                          │
│  │                                                              │
│  ├─ Configure PHP (parallel writes)                            │
│  ├─ Configure MariaDB (optimize before first start)            │
│  ├─ ⚠️ RISK: Secure MariaDB (password handling)                │
│  ├─ Configure Redis                                            │
│  │                                                              │
│  ├─ Install Composer                                           │
│  ├─ Clone VPSManager repository                                │
│  ├─ Install VPSManager dependencies                            │
│  ├─ Create VPSManager dashboard                                │
│  │                                                              │
│  ├─ Configure Nginx for dashboard                              │
│  ├─ ⚠️ RISK: Configure firewall BEFORE verifying services      │
│  ├─ Validate ports available                                   │
│  │                                                              │
│  ├─ Start all services (parallel)                              │
│  ├─ Wait for PHP-FPM sockets (parallel)                        │
│  ├─ Verify services (systemctl is-active only)                 │
│  ├─ ⚠️ MISSING: HTTP health checks                             │
│  ├─ ⚠️ MISSING: Verify connectivity to Observability           │
│  │                                                              │
│  ├─ Setup SSL (certbot)                                        │
│  └─ Save credentials to /root/.vpsmanager-credentials          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## INCIDENT RESPONSE RUNBOOK

### If Deployment Fails

**Symptom: Script exits with "Cannot find common library"**
```bash
ERROR: Cannot find common library at /tmp/../lib/deploy-common.sh
```

**Root Cause:** Library not transferred to remote VPS

**Immediate Fix:**
```bash
# On control machine
scp -i ./keys/chom_deploy_key \
    ./lib/deploy-common.sh \
    deploy@<VPS_IP>:/tmp/lib/deploy-common.sh

# Re-run deployment
./deploy-enhanced.sh --resume
```

**Permanent Fix:** Implement Issue #3 solution

---

**Symptom: Deployment completes but services not working**
```bash
✓ All components deployed successfully!
# But: curl http://<IP>:9090 fails
```

**Root Cause:** No health checks - services failed silently

**Diagnosis:**
```bash
# SSH to VPS
ssh -i ./keys/chom_deploy_key deploy@<VPS_IP>

# Check service status
sudo systemctl status prometheus grafana-server loki

# Check logs
sudo journalctl -xeu prometheus
sudo journalctl -xeu grafana-server
```

**Common Issues:**
- Port conflicts: `sudo lsof -i :9090`
- Config errors: `sudo /opt/observability/bin/prometheus --config.file=/etc/observability/prometheus/prometheus.yml`
- Permissions: `sudo chown -R observability:observability /var/lib/observability`

**Permanent Fix:** Implement Issue HIGH-2 solution (health checks)

---

**Symptom: Locked out after firewall enabled**
```bash
# Cannot SSH to VPS after deployment
ssh: connect to host <IP> port 2222: Connection refused
```

**Root Cause:** Firewall enabled with wrong SSH port (allowed 22, but using 2222)

**Recovery via Console:**
```bash
# Login via OVH/provider web console
sudo ufw allow 2222/tcp
sudo ufw reload

# Or disable firewall entirely
sudo ufw disable
```

**Permanent Fix:** Implement Issue MED-3 solution (firewall after verification)

---

**Symptom: Re-deployment fails with "Service already exists"**
```bash
Failed to create service: Unit prometheus.service already exists
```

**Root Cause:** No rollback - old installation conflicts with new

**Fix:**
```bash
# Manual cleanup
ssh -i ./keys/chom_deploy_key deploy@<VPS_IP>

# Stop and remove old services
sudo systemctl stop prometheus grafana-server loki alertmanager
sudo systemctl disable prometheus grafana-server loki alertmanager
sudo rm /etc/systemd/system/{prometheus,grafana-server,loki,alertmanager}.service
sudo systemctl daemon-reload

# Re-run deployment
./deploy-enhanced.sh --force
```

**Permanent Fix:** Implement Issue #2 solution (rollback mechanism)

---

## PRODUCTION READINESS SCORECARD

| Category | Score | Status | Blockers |
|----------|-------|--------|----------|
| **Deployment Flow** | 4/10 | 🔴 NOT READY | Library transfer, rollback |
| **Configuration Management** | 5/10 | 🟡 NEEDS WORK | Domain config, env vars |
| **Error Handling** | 6/10 | 🟡 NEEDS WORK | No rollback, partial health checks |
| **Security** | 7/10 | 🟡 ACCEPTABLE | Credentials in plaintext, firewall ordering |
| **Observability** | 5/10 | 🟡 NEEDS WORK | No end-to-end verification |
| **Documentation** | 8/10 | 🟢 GOOD | Well-documented, needs updated |
| **SSH Management** | 4/10 | 🔴 NOT READY | Interactive-only, no automation support |
| **State Management** | 6/10 | 🟡 NEEDS WORK | Tracks status but not snapshots |
| **Idempotency** | 7/10 | 🟡 ACCEPTABLE | Mostly safe to re-run |
| **Recovery** | 3/10 | 🔴 NOT READY | No rollback, manual cleanup required |

**Overall Score: 5.5/10 - NOT PRODUCTION READY**

**Must-Fix Before Production:**
1. Library transfer (CRITICAL)
2. Rollback mechanism (CRITICAL)
3. Health checks (HIGH)
4. Non-interactive SSH (HIGH)

**Recommended for GA Release:**
5. Dynamic hardware detection
6. Config standardization
7. Pre-deployment backup
8. Firewall ordering fix

---

## HARDWARE DETECTION IMPLEMENTATION PLAN

### Current State Analysis

**Static Specs in inventory.yaml:**
```yaml
observability:
  specs:
    cpu: 1           # User manually enters
    memory_mb: 2048  # User manually enters
    disk_gb: 20      # User manually enters
```

**Detection Already Exists (but not saved):**
```bash
# deploy-enhanced.sh lines 1370-1401
local disk_gb=$(remote_exec "$host" "$user" "$port" \
    "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

local ram_mb=$(remote_exec "$host" "$user" "$port" \
    "free -m | awk '/^Mem:/ {print \$2}'")

local cpu_count=$(remote_exec "$host" "$user" "$port" "nproc")
```

### Implementation: Dynamic Detection with Auto-Update

**Step 1: Add Spec Update Function**

```bash
# Add to deploy-enhanced.sh after validate_remote_vps()

update_inventory_with_detected_specs() {
    local target=$1
    local cpu=$2
    local ram=$3
    local disk=$4

    log_info "Updating inventory.yaml with detected hardware specs..."

    # Create backup of inventory before modifying
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%s)"

    # Update specs using yq (atomic operations)
    yq eval ".${target}.specs.cpu = ${cpu}" -i "$CONFIG_FILE"
    yq eval ".${target}.specs.memory_mb = ${ram}" -i "$CONFIG_FILE"
    yq eval ".${target}.specs.disk_gb = ${disk}" -i "$CONFIG_FILE"

    # Add detection timestamp
    yq eval ".${target}.specs.detected_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" -i "$CONFIG_FILE"

    log_success "Inventory updated: ${cpu} vCPU, ${ram}MB RAM, ${disk}GB disk"
}
```

**Step 2: Call After Validation**

```bash
# Modify validate_remote_vps() at line 1440
validate_remote_vps() {
    # ... existing validation code ...

    # NEW: After successful validation, update inventory
    log_step "Updating inventory with detected specs..."
    update_inventory_with_detected_specs "$name" "$cpu_count" "$ram_mb" "$disk_gb"

    log_success "$name VPS validation complete"
    return 0
}
```

**Step 3: Display Detected vs. Configured**

```bash
# Update show_inventory_review() to show both configured and detected specs
show_inventory_review() {
    # ... existing code ...

    # Read configured specs
    local obs_cpu=$(get_config '.observability.specs.cpu')
    local obs_ram=$(get_config '.observability.specs.memory_mb')
    local obs_disk=$(get_config '.observability.specs.disk_gb')

    # Read detected timestamp
    local obs_detected_at=$(get_config '.observability.specs.detected_at' 2>/dev/null)

    # Display
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" \
        "Specs (configured):" \
        "${obs_cpu} vCPU, ${obs_ram}MB RAM, ${obs_disk}GB Disk"

    if [[ -n "$obs_detected_at" && "$obs_detected_at" != "null" ]]; then
        printf "${CYAN}│${NC} %-20s ${GREEN}%-50s${NC} ${CYAN}│${NC}\n" \
            "Specs (detected):" \
            "Last verified: $(date -d "$obs_detected_at" '+%Y-%m-%d %H:%M')"
    else
        printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" \
            "Specs (detected):" \
            "Not yet detected - will update after validation"
    fi
}
```

**Step 4: Add --detect-specs Command**

```bash
# Add standalone detection mode
detect_specs_only() {
    log_step "Hardware Detection Mode"

    # Check dependencies first
    check_dependencies
    validate_inventory

    # Detect for observability VPS
    local obs_ip=$(get_config '.observability.ip')
    local obs_user=$(get_config '.observability.ssh_user')
    local obs_port=$(get_config '.observability.ssh_port')

    log_info "Detecting specs for Observability VPS..."

    local obs_cpu=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" "nproc")
    local obs_ram=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" \
        "free -m | awk '/^Mem:/ {print \$2}'")
    local obs_disk=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" \
        "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

    update_inventory_with_detected_specs "observability" "$obs_cpu" "$obs_ram" "$obs_disk"

    # Detect for VPSManager VPS
    local vps_ip=$(get_config '.vpsmanager.ip')
    local vps_user=$(get_config '.vpsmanager.ssh_user')
    local vps_port=$(get_config '.vpsmanager.ssh_port')

    log_info "Detecting specs for VPSManager VPS..."

    local vps_cpu=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" "nproc")
    local vps_ram=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" \
        "free -m | awk '/^Mem:/ {print \$2}'")
    local vps_disk=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" \
        "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

    update_inventory_with_detected_specs "vpsmanager" "$vps_cpu" "$vps_ram" "$vps_disk"

    # Display summary
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ Hardware Detection Summary                                  │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│                                                             │"
    echo "│ Observability VPS:                                          │"
    printf "│   CPU:    %-10s vCPU                                    │\n" "$obs_cpu"
    printf "│   RAM:    %-10s MB                                      │\n" "$obs_ram"
    printf "│   Disk:   %-10s GB free                                 │\n" "$obs_disk"
    echo "│                                                             │"
    echo "│ VPSManager VPS:                                             │"
    printf "│   CPU:    %-10s vCPU                                    │\n" "$vps_cpu"
    printf "│   RAM:    %-10s MB                                      │\n" "$vps_ram"
    printf "│   Disk:   %-10s GB free                                 │\n" "$vps_disk"
    echo "│                                                             │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    log_success "inventory.yaml updated with detected specs"
    log_info "Backup saved: ${CONFIG_FILE}.backup.*"
}

# Add to argument parsing
case "$1" in
    --detect-specs)
        detect_specs_only
        exit 0
        ;;
esac
```

**Step 5: Update inventory.yaml Schema**

```yaml
# Add detection metadata
observability:
  hostname: obs.example.com
  ip: 192.0.2.10
  ssh_user: deploy
  ssh_port: 22
  specs:
    cpu: 2              # Will be auto-updated after detection
    memory_mb: 4096     # Will be auto-updated after detection
    disk_gb: 40         # Will be auto-updated after detection
    detected_at: "2025-12-31T15:30:00Z"  # Auto-added timestamp
    detection_source: "remote_query"     # How specs were detected
```

### Usage Examples

**Manual Detection (Before Deployment):**
```bash
# Detect and update inventory.yaml with actual specs
./deploy-enhanced.sh --detect-specs

# Output:
# ┌─────────────────────────────────────────────────────────────┐
# │ Hardware Detection Summary                                  │
# ├─────────────────────────────────────────────────────────────┤
# │ Observability VPS:                                          │
# │   CPU:    2          vCPU                                   │
# │   RAM:    3923       MB                                     │
# │   Disk:   38         GB free                                │
# │ VPSManager VPS:                                             │
# │   CPU:    4          vCPU                                   │
# │   RAM:    7846       MB                                     │
# │   Disk:   76         GB free                                │
# └─────────────────────────────────────────────────────────────┘
# ✓ inventory.yaml updated with detected specs
```

**Automatic Detection (During Deployment):**
```bash
# Specs detected and updated during pre-flight validation
./deploy-enhanced.sh all

# Output:
# [STEP] Validating Observability VPS...
# [INFO] Checking disk space...
# [SUCCESS] Disk space: 38GB available
# [INFO] Checking RAM...
# [SUCCESS] RAM: 3923MB
# [INFO] Checking CPU count...
# [SUCCESS] CPU: 2 vCPU(s)
# [STEP] Updating inventory with detected specs...
# [SUCCESS] Inventory updated: 2 vCPU, 3923MB RAM, 38GB disk
```

**View Detection History:**
```bash
# Show when specs were last detected
yq eval '.observability.specs.detected_at' configs/inventory.yaml
# Output: 2025-12-31T15:30:00Z

# Show detected specs
yq eval '.observability.specs' configs/inventory.yaml
# Output:
# cpu: 2
# memory_mb: 3923
# disk_gb: 38
# detected_at: "2025-12-31T15:30:00Z"
# detection_source: "remote_query"
```

### Benefits

1. **Accuracy**: inventory.yaml always reflects actual hardware
2. **Audit Trail**: Timestamp shows when specs were last verified
3. **Change Detection**: Compare configured vs. detected to spot VPS downgrades
4. **Capacity Planning**: Historical spec data for resource trends
5. **Automation**: Can be called from monitoring scripts to detect changes

### Testing Plan

```bash
# Test 1: Fresh inventory (no detected_at)
cp configs/inventory.yaml.example configs/inventory.yaml
./deploy-enhanced.sh --detect-specs
# Verify: detected_at field added, specs updated

# Test 2: Re-detection (update existing)
./deploy-enhanced.sh --detect-specs
# Verify: detected_at timestamp updated, specs refreshed

# Test 3: Deployment auto-detection
./deploy-enhanced.sh --validate
# Verify: Specs updated during validation

# Test 4: Spec change detection
# Manually change specs in inventory.yaml
yq eval '.observability.specs.cpu = 999' -i configs/inventory.yaml
./deploy-enhanced.sh --detect-specs
# Verify: Incorrect value replaced with actual detected value

# Test 5: Backup verification
ls -lah configs/inventory.yaml.backup.*
# Verify: Backup created before each modification
```

---

## CONCLUSION

The CHOM deployment system has a solid foundation but requires **critical fixes** before production use:

**Must Fix (Blockers):**
1. Transfer common library to remote VPS
2. Implement rollback mechanism
3. Add comprehensive health checks
4. Support non-interactive SSH key distribution
5. Implement dynamic hardware detection

**Should Fix (High Priority):**
6. Pass all configuration from inventory to remote scripts
7. Standardize domain configuration
8. Add pre-deployment backup
9. Fix firewall ordering

**Priority Order:**
1. Issue #3 (Library Transfer) - **1 hour** - Blocking all deployments
2. Issue #1 (Hardware Detection) - **2 hours** - User-requested feature
3. Issue #2 (Rollback) - **4 hours** - Production safety
4. Issue HIGH-2 (Health Checks) - **3 hours** - Reliability
5. Issue HIGH-1 (Config Passing) - **2 hours** - Usability
6. Issue HIGH-3 (SSH Non-Interactive) - **4 hours** - Automation

**Total Estimated Effort:** 16 hours (2 working days)

After these fixes, the deployment system will be **production-ready** with proper error recovery, monitoring, and automation support.

---

**End of Analysis**
