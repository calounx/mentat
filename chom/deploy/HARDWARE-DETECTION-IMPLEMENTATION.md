# Dynamic Hardware Detection - Implementation Guide

**Feature:** Automatic hardware detection for VPS servers
**Priority:** P1 (Implement this week)
**Effort:** 2-3 days
**Impact:** MEDIUM operational improvement

---

## Problem Statement

**Current Issue:**
Hardware specifications are manually entered in `inventory.yaml` and never validated:

```yaml
observability:
  specs:
    cpu: 1           # User types this manually
    memory_mb: 2048  # May be wrong!
    disk_gb: 20      # Never updated if VPS is upgraded
```

**Problems:**
1. User may enter wrong values (typos, outdated info)
2. No validation against actual hardware
3. Specs never updated if VPS is upgraded/downgraded
4. Monitoring thresholds based on incorrect data
5. Capacity planning based on assumptions, not reality

---

## Solution Design

**Proposed Approach:**
1. Detect hardware automatically via SSH during pre-flight checks
2. Store detected specs in deployment state (audit trail)
3. Compare with inventory if provided (warn on mismatch)
4. Display hardware summary table before deployment
5. Use detected specs for monitoring configuration

**Benefits:**
- Always accurate (no user error)
- Detects hardware changes (VPS upgrade/downgrade)
- Historical tracking (capacity planning)
- Correct monitoring thresholds (no false alerts)

---

## Implementation Plan

### Step 1: Create Hardware Detection Library

**File:** `/home/calounx/repositories/mentat/chom/deploy/lib/hardware-detection.sh`

```bash
#!/bin/bash
# =============================================================================
# CHOM Hardware Detection Library
# Detects VPS hardware specifications via SSH
# =============================================================================

# Global hardware storage (associative array)
declare -A DETECTED_HARDWARE

# Detect hardware specifications for a remote VPS
# Args: host, user, port, target_name
detect_hardware() {
    local host=$1
    local user=$2
    local port=$3
    local target=$4

    log_info "Detecting hardware for ${target} (${host})..."

    # Detect vCPU count
    local cpu_count
    cpu_count=$(remote_exec "$host" "$user" "$port" "nproc" 2>/dev/null)

    if [[ -z "$cpu_count" ]] || ! [[ "$cpu_count" =~ ^[0-9]+$ ]]; then
        log_error "Failed to detect CPU count for ${target}"
        return 1
    fi

    # Detect total RAM in MB
    local memory_mb
    memory_mb=$(remote_exec "$host" "$user" "$port" \
        "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null)

    if [[ -z "$memory_mb" ]] || ! [[ "$memory_mb" =~ ^[0-9]+$ ]]; then
        log_error "Failed to detect RAM for ${target}"
        return 1
    fi

    # Detect total disk in GB (root partition)
    local disk_gb
    disk_gb=$(remote_exec "$host" "$user" "$port" \
        "df -BG / | awk 'NR==2 {print \$2}' | tr -d 'G'" 2>/dev/null)

    if [[ -z "$disk_gb" ]] || ! [[ "$disk_gb" =~ ^[0-9]+$ ]]; then
        log_error "Failed to detect disk size for ${target}"
        return 1
    fi

    # Detect free disk in GB (for warnings)
    local disk_free_gb
    disk_free_gb=$(remote_exec "$host" "$user" "$port" \
        "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'" 2>/dev/null)

    # Detect architecture
    local arch
    arch=$(remote_exec "$host" "$user" "$port" "uname -m" 2>/dev/null)

    # Detect OS version
    local os_version
    os_version=$(remote_exec "$host" "$user" "$port" \
        "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"'" 2>/dev/null)

    # Detect kernel version
    local kernel_version
    kernel_version=$(remote_exec "$host" "$user" "$port" "uname -r" 2>/dev/null)

    # Store in global associative array
    DETECTED_HARDWARE["${target}_cpu"]=$cpu_count
    DETECTED_HARDWARE["${target}_memory_mb"]=$memory_mb
    DETECTED_HARDWARE["${target}_disk_gb"]=$disk_gb
    DETECTED_HARDWARE["${target}_disk_free_gb"]=$disk_free_gb
    DETECTED_HARDWARE["${target}_arch"]=$arch
    DETECTED_HARDWARE["${target}_os"]=$os_version
    DETECTED_HARDWARE["${target}_kernel"]=$kernel_version

    log_success "Hardware detected: ${cpu_count} vCPU, ${memory_mb}MB RAM, ${disk_gb}GB disk"

    # Compare with inventory if provided
    compare_with_inventory "$target" "$cpu_count" "$memory_mb" "$disk_gb"

    return 0
}

# Compare detected hardware with inventory.yaml (if provided)
# Args: target, detected_cpu, detected_memory_mb, detected_disk_gb
compare_with_inventory() {
    local target=$1
    local detected_cpu=$2
    local detected_memory=$3
    local detected_disk=$4

    # Try to read from inventory (may not exist if specs removed)
    local inventory_cpu
    inventory_cpu=$(yq eval ".${target}.specs.cpu" "$CONFIG_FILE" 2>/dev/null)

    local inventory_memory
    inventory_memory=$(yq eval ".${target}.specs.memory_mb" "$CONFIG_FILE" 2>/dev/null)

    local inventory_disk
    inventory_disk=$(yq eval ".${target}.specs.disk_gb" "$CONFIG_FILE" 2>/dev/null)

    # Compare CPU
    if [[ "$inventory_cpu" != "null" ]] && [[ -n "$inventory_cpu" ]]; then
        if [[ "$inventory_cpu" != "$detected_cpu" ]]; then
            log_warn "CPU mismatch for ${target}: inventory says ${inventory_cpu}, detected ${detected_cpu}"
            log_warn "Update inventory.yaml or VPS may have been upgraded/downgraded"
        fi
    fi

    # Compare RAM
    if [[ "$inventory_memory" != "null" ]] && [[ -n "$inventory_memory" ]]; then
        if [[ "$inventory_memory" != "$detected_memory" ]]; then
            log_warn "RAM mismatch for ${target}: inventory says ${inventory_memory}MB, detected ${detected_memory}MB"
            log_warn "Update inventory.yaml or VPS may have been upgraded/downgraded"
        fi
    fi

    # Compare Disk
    if [[ "$inventory_disk" != "null" ]] && [[ -n "$inventory_disk" ]]; then
        # Allow 10% difference (disk sizes vary slightly)
        local diff=$((detected_disk - inventory_disk))
        local abs_diff=${diff#-}  # Absolute value

        if [[ $abs_diff -gt $((inventory_disk / 10)) ]]; then
            log_warn "Disk mismatch for ${target}: inventory says ${inventory_disk}GB, detected ${detected_disk}GB"
            log_warn "Update inventory.yaml or VPS may have been resized"
        fi
    fi
}

# Display hardware summary table
display_hardware_summary() {
    echo ""
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "${BOLD}  Hardware Summary${NC}"
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    printf "%-20s %6s %10s %10s %10s %8s\n" \
        "Target" "vCPU" "RAM (MB)" "Disk (GB)" "Free (GB)" "Status"
    echo "────────────────────────────────────────────────────────────────────"

    # Sort targets alphabetically
    local targets=($(echo "${!DETECTED_HARDWARE[@]}" | tr ' ' '\n' | grep '_cpu$' | sed 's/_cpu$//' | sort))

    for target in "${targets[@]}"; do
        local cpu="${DETECTED_HARDWARE[${target}_cpu]}"
        local memory="${DETECTED_HARDWARE[${target}_memory_mb]}"
        local disk="${DETECTED_HARDWARE[${target}_disk_gb]}"
        local disk_free="${DETECTED_HARDWARE[${target}_disk_free_gb]}"

        # Determine status
        local status="${GREEN}✓ OK${NC}"

        # Check against minimum requirements
        if [[ "$target" == "observability" ]]; then
            if [[ $cpu -lt 1 ]] || [[ $memory -lt 2048 ]] || [[ $disk -lt 20 ]]; then
                status="${RED}✗ Below minimum${NC}"
            fi
        elif [[ "$target" == "vpsmanager" ]]; then
            if [[ $cpu -lt 2 ]] || [[ $memory -lt 4096 ]] || [[ $disk -lt 40 ]]; then
                status="${RED}✗ Below minimum${NC}"
            fi
        fi

        # Warn if low disk space
        if [[ -n "$disk_free" ]] && [[ $disk_free -lt 10 ]]; then
            status="${YELLOW}⚠ Low disk${NC}"
        fi

        printf "%-20s %6s %10s %10s %10s %8b\n" \
            "$target" "$cpu" "$memory" "$disk" "$disk_free" "$status"
    done

    echo ""
}

# Validate hardware meets minimum requirements
# Returns 0 if all servers meet requirements, 1 otherwise
validate_hardware_requirements() {
    local all_ok=true

    # Define minimum requirements
    local -A MIN_REQUIREMENTS=(
        ["observability_cpu"]=1
        ["observability_memory_mb"]=2048
        ["observability_disk_gb"]=20
        ["vpsmanager_cpu"]=2
        ["vpsmanager_memory_mb"]=4096
        ["vpsmanager_disk_gb"]=40
    )

    # Check each target
    for target in observability vpsmanager; do
        local cpu="${DETECTED_HARDWARE[${target}_cpu]}"
        local memory="${DETECTED_HARDWARE[${target}_memory_mb]}"
        local disk="${DETECTED_HARDWARE[${target}_disk_gb]}"

        # Check CPU
        if [[ $cpu -lt ${MIN_REQUIREMENTS[${target}_cpu]} ]]; then
            log_error "${target}: Insufficient CPU (${cpu} vCPU, minimum ${MIN_REQUIREMENTS[${target}_cpu]})"
            all_ok=false
        fi

        # Check RAM
        if [[ $memory -lt ${MIN_REQUIREMENTS[${target}_memory_mb]} ]]; then
            log_error "${target}: Insufficient RAM (${memory}MB, minimum ${MIN_REQUIREMENTS[${target}_memory_mb]}MB)"
            all_ok=false
        fi

        # Check Disk
        if [[ $disk -lt ${MIN_REQUIREMENTS[${target}_disk_gb]} ]]; then
            log_error "${target}: Insufficient disk (${disk}GB, minimum ${MIN_REQUIREMENTS[${target}_disk_gb]}GB)"
            all_ok=false
        fi

        # Warn if low disk space
        local disk_free="${DETECTED_HARDWARE[${target}_disk_free_gb]}"
        if [[ -n "$disk_free" ]] && [[ $disk_free -lt 10 ]]; then
            log_warn "${target}: Low free disk space (${disk_free}GB remaining)"
            log_warn "Consider cleaning up before deployment"
        fi
    done

    if [[ "$all_ok" == "true" ]]; then
        log_success "All servers meet minimum requirements"
        return 0
    else
        log_error "Some servers do not meet minimum requirements"
        return 1
    fi
}

# Save hardware specs to deployment state
# Args: state_file
save_hardware_to_state() {
    local state_file=$1

    log_info "Saving hardware specs to state file..."

    # Create hardware directory if it doesn't exist
    mkdir -p "${STATE_DIR}/hardware"

    # Save hardware for each target
    for target in observability vpsmanager; do
        local hardware_file="${STATE_DIR}/hardware/${target}.json"

        cat > "$hardware_file" << EOF
{
  "cpu": ${DETECTED_HARDWARE[${target}_cpu]},
  "memory_mb": ${DETECTED_HARDWARE[${target}_memory_mb]},
  "disk_gb": ${DETECTED_HARDWARE[${target}_disk_gb]},
  "disk_free_gb": ${DETECTED_HARDWARE[${target}_disk_free_gb]},
  "architecture": "${DETECTED_HARDWARE[${target}_arch]}",
  "os": "${DETECTED_HARDWARE[${target}_os]}",
  "kernel": "${DETECTED_HARDWARE[${target}_kernel]}",
  "detected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

        chmod 600 "$hardware_file"
        log_debug "Hardware saved to: $hardware_file"
    done

    log_success "Hardware specs saved to state"
}

# =============================================================================
# Library Initialization
# =============================================================================

log_info "Hardware Detection library loaded"
```

---

### Step 2: Integrate into deploy-enhanced.sh

**Modifications to `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh`:**

```bash
# At the top of the file (after sourcing deploy-common.sh)
source "${SCRIPT_DIR}/lib/hardware-detection.sh"

# In the run_preflight_checks() function, add after SSH connectivity checks:

run_preflight_checks() {
    # ... existing SSH checks ...

    # NEW: Hardware detection
    print_section "Hardware Detection"

    log_info "Detecting hardware for all VPS servers..."

    # Detect hardware for observability VPS
    local obs_ip=$(get_config ".observability.ip")
    local obs_user=$(get_config ".observability.ssh_user")
    local obs_port=$(get_config ".observability.ssh_port")

    if ! detect_hardware "$obs_ip" "$obs_user" "$obs_port" "observability"; then
        log_error "Failed to detect hardware for observability VPS"
        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            exit 1
        fi
    fi

    # Detect hardware for vpsmanager VPS
    local vps_ip=$(get_config ".vpsmanager.ip")
    local vps_user=$(get_config ".vpsmanager.ssh_user")
    local vps_port=$(get_config ".vpsmanager.ssh_port")

    if ! detect_hardware "$vps_ip" "$vps_user" "$vps_port" "vpsmanager"; then
        log_error "Failed to detect hardware for vpsmanager VPS"
        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            exit 1
        fi
    fi

    # Display hardware summary table
    display_hardware_summary

    # Validate hardware meets minimum requirements
    if ! validate_hardware_requirements; then
        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            log_error "Hardware validation failed. Use --force to deploy anyway."
            exit 1
        else
            log_warn "Hardware validation failed, but --force specified. Continuing..."
        fi
    fi

    # Save hardware to state
    save_hardware_to_state "$STATE_FILE"

    # ... rest of pre-flight checks ...
}
```

---

### Step 3: Update inventory.yaml

**Remove static hardware specs from `configs/inventory.yaml`:**

**Before:**
```yaml
observability:
  hostname: obs.example.com
  ip: 203.0.113.10
  ssh_user: deploy
  ssh_port: 22
  specs:                    # ← REMOVE THIS SECTION
    cpu: 1
    memory_mb: 2048
    disk_gb: 20
  components:
    - prometheus
    - loki
```

**After:**
```yaml
observability:
  hostname: obs.example.com
  ip: 203.0.113.10
  ssh_user: deploy
  ssh_port: 22
  # specs removed - detected dynamically
  components:
    - prometheus
    - loki
```

**Optional: Keep specs for comparison (will show warnings if mismatch):**
```yaml
observability:
  specs:
    cpu: 2                  # For comparison only
    memory_mb: 4096         # Actual specs detected via SSH
    disk_gb: 40             # Warnings shown if mismatch
```

---

### Step 4: Update State File Structure

**Modify `update_state()` function to include hardware:**

```bash
update_state() {
    local target=$1
    local status=$2
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # ... existing state update logic ...

    # Add hardware specs if available
    if [[ -n "${DETECTED_HARDWARE[${target}_cpu]}" ]]; then
        local cpu="${DETECTED_HARDWARE[${target}_cpu]}"
        local memory="${DETECTED_HARDWARE[${target}_memory_mb]}"
        local disk="${DETECTED_HARDWARE[${target}_disk_gb]}"

        jq ".${target}.hardware = {
            \"cpu\": $cpu,
            \"memory_mb\": $memory,
            \"disk_gb\": $disk,
            \"detected_at\": \"$timestamp\"
        }" "$STATE_FILE" > "$tmp_file"

        mv "$tmp_file" "$STATE_FILE"
    fi
}
```

---

### Step 5: Update Documentation

**Add to README.md:**

```markdown
## Hardware Detection

CHOM automatically detects VPS hardware specifications during deployment:

- **CPU:** Number of vCPU cores (`nproc`)
- **RAM:** Total memory in MB (`free -m`)
- **Disk:** Total disk size in GB (`df -BG`)

Hardware specs are:
- Detected during pre-flight checks
- Displayed in a summary table
- Stored in deployment state for audit trail
- Compared with inventory.yaml (if provided)

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hardware Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Target           vCPU    RAM (MB)   Disk (GB)   Free (GB)   Status
────────────────────────────────────────────────────────────────────
Observability      2       4096        40          35       ✓ OK
VPSManager         4       8192        80          70       ✓ OK

[✓] All servers meet minimum requirements
```

### Hardware Requirements

**Observability VPS:**
- Minimum: 1 vCPU, 2GB RAM, 20GB disk
- Recommended: 2 vCPU, 4GB RAM, 40GB disk

**VPSManager VPS:**
- Minimum: 2 vCPU, 4GB RAM, 40GB disk
- Recommended: 4 vCPU, 8GB RAM, 80GB disk

### Hardware History

Hardware specs are stored in `.deploy-state/hardware/` for audit purposes:

```bash
cat .deploy-state/hardware/observability.json
{
  "cpu": 2,
  "memory_mb": 4096,
  "disk_gb": 40,
  "detected_at": "2025-12-31T10:05:00Z"
}
```
```

---

## Testing Plan

### Test Case 1: Normal Detection

**Setup:**
- 2 VPS servers with standard specs
- Clean deployment

**Expected Result:**
```
[INFO] Detecting hardware for observability (203.0.113.10)...
[✓] Hardware detected: 2 vCPU, 4096MB RAM, 40GB disk
[INFO] Detecting hardware for vpsmanager (203.0.113.20)...
[✓] Hardware detected: 4 vCPU, 8192MB RAM, 80GB disk

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hardware Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Target           vCPU    RAM (MB)   Disk (GB)   Free (GB)   Status
────────────────────────────────────────────────────────────────────
Observability      2       4096        40          35       ✓ OK
VPSManager         4       8192        80          70       ✓ OK

[✓] All servers meet minimum requirements
```

---

### Test Case 2: Below Minimum Requirements

**Setup:**
- Observability VPS with only 1GB RAM

**Expected Result:**
```
[ERROR] observability: Insufficient RAM (1024MB, minimum 2048MB)
[ERROR] Some servers do not meet minimum requirements
[ERROR] Hardware validation failed. Use --force to deploy anyway.
```

---

### Test Case 3: Mismatch with Inventory

**Setup:**
- inventory.yaml says 2 vCPU
- Actual VPS has 4 vCPU

**Expected Result:**
```
[WARN] CPU mismatch for observability: inventory says 2, detected 4
[WARN] Update inventory.yaml or VPS may have been upgraded/downgraded
```

---

### Test Case 4: Low Disk Space

**Setup:**
- VPS with less than 10GB free disk

**Expected Result:**
```
Target           vCPU    RAM (MB)   Disk (GB)   Free (GB)   Status
────────────────────────────────────────────────────────────────────
Observability      2       4096        40          5        ⚠ Low disk

[WARN] observability: Low free disk space (5GB remaining)
[WARN] Consider cleaning up before deployment
```

---

### Test Case 5: SSH Failure

**Setup:**
- SSH to VPS fails

**Expected Result:**
```
[ERROR] Failed to detect CPU count for observability
[ERROR] Failed to detect hardware for observability VPS
```

---

## Rollout Plan

### Week 1: Implementation

**Day 1-2:**
- Create `lib/hardware-detection.sh`
- Implement core detection functions
- Unit test on test VPS

**Day 3:**
- Integrate into `deploy-enhanced.sh`
- Update inventory.yaml (remove static specs)
- Update state management

**Day 4:**
- Write documentation
- Create test cases
- Test on staging VPS

**Day 5:**
- Code review
- Bug fixes
- Deploy to production

### Week 2: Monitoring

**Day 1-3:**
- Monitor deployments
- Collect feedback
- Fix edge cases

**Day 4-5:**
- Update documentation based on feedback
- Add additional hardware metrics (swap, network, etc)

---

## Success Criteria

1. **Accuracy:** Hardware detection matches actual VPS specs (100% accuracy)
2. **Performance:** Detection adds less than 10 seconds to pre-flight checks
3. **Reliability:** No false positives/negatives in hardware validation
4. **Usability:** Clear hardware summary table displayed before deployment
5. **Audit:** All hardware specs stored in deployment state

---

## Future Enhancements

### Phase 2: Additional Metrics (Month 2)

- Swap size detection
- Network interface detection
- Disk I/O performance test
- CPU model and frequency

### Phase 3: Capacity Planning (Quarter 1)

- Historical hardware usage tracking
- Capacity forecasting (when will we run out of disk?)
- Recommendations (upgrade VPS if usage > 80%)

### Phase 4: Automated Scaling (Quarter 2)

- Detect when resources are low
- Automatically trigger VPS upgrade via cloud API
- Re-deploy with new specs

---

## Files to Create/Modify

### Files to Create

1. `/home/calounx/repositories/mentat/chom/deploy/lib/hardware-detection.sh` (NEW)
2. `/home/calounx/repositories/mentat/chom/deploy/.deploy-state/hardware/observability.json` (auto-generated)
3. `/home/calounx/repositories/mentat/chom/deploy/.deploy-state/hardware/vpsmanager.json` (auto-generated)

### Files to Modify

1. `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh`
   - Source hardware-detection.sh
   - Call detect_hardware() in pre-flight checks
   - Display hardware summary
   - Validate requirements

2. `/home/calounx/repositories/mentat/chom/deploy/configs/inventory.yaml`
   - Remove `specs.cpu`, `specs.memory_mb`, `specs.disk_gb`
   - (Optional: keep for comparison)

3. `/home/calounx/repositories/mentat/chom/deploy/README.md`
   - Add hardware detection section
   - Update minimum requirements

---

**End of Implementation Guide**

Next steps: Review this guide, then implement Phase 1 (create library) and Phase 2 (integrate into deploy-enhanced.sh).
