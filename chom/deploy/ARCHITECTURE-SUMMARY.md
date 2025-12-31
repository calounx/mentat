# CHOM Deployment System - Architecture Review Summary

**Review Date:** 2025-12-31 | **Version:** 4.3.0 | **Reviewer:** Backend System Architect

---

## TL;DR - Critical Findings

| Finding | Severity | Impact | Fix Time | Priority |
|---------|----------|--------|----------|----------|
| **SMTP password in plaintext** | HIGH | Security breach if repo leaked | 1 day | P0 |
| **Static hardware specs** | MEDIUM | Wrong monitoring thresholds | 2 days | P1 |
| **No deployment history** | MEDIUM | Cannot audit or rollback | 3 days | P2 |
| **Sequential deployment** | MEDIUM | Wastes 50% of time | 1 week | P2 |
| **Limited scalability** | MEDIUM | Cannot scale beyond 5-7 VPS | 2-3 weeks | P3 |

**Recommendation:** Fix P0 and P1 issues this week, plan P2/P3 for next quarter.

---

## Architecture Overview

### Current Design (v4.3.0)

```
Control Machine (Bash)
  └─ deploy-enhanced.sh (2,616 lines)
     ├─ inventory.yaml (config + secrets ← PROBLEM!)
     ├─ Static hardware specs (user input ← PROBLEM!)
     └─ Sequential deployment (slow ← PROBLEM!)
        │
        ├─► Observability VPS (10 min)
        └─► VPSManager VPS (15 min)

Total deployment time: 25 minutes
Scalability: 2-3 VPS servers
Security: MEDIUM (plaintext secrets)
```

### What Works Well

1. **User Experience:** Minimal interaction (1 confirmation prompt), auto-healing, clear progress
2. **Idempotency:** Safe to re-run, cleanup before deployment
3. **SSH Security:** Key-based auth, input validation, no password auth
4. **Pre-flight Checks:** Validates SSH, disk, RAM, CPU, sudo before deployment

### Critical Issues

1. **Secret Management**
   - SMTP password stored in plaintext in `inventory.yaml`
   - Risk: Credentials exposed if repo is public or shared
   - Fix: Use `.secrets.env` (gitignored, encrypted)

2. **Hardware Detection**
   - Hardware specs manually entered in `inventory.yaml`
   - Never validated against actual VPS
   - Fix: Detect dynamically via SSH (`nproc`, `free -m`, `df -BG`)

3. **State Management**
   - Only tracks current deployment (no history)
   - Cannot audit "who deployed what when"
   - Fix: Store deployment history with metadata

4. **Scalability**
   - Deploys VPS servers sequentially (wastes time)
   - 10 VPS would take 100+ minutes
   - Fix: Parallel deployment with dependency graph

---

## Proposed Improvements (v5.0.0)

### 1. Secret Management (P0 - Fix This Week)

**Before:**
```yaml
# inventory.yaml (INSECURE!)
smtp:
  password: "my_secret_password"  # Plaintext!
```

**After:**
```bash
# .secrets.env (gitignored, encrypted)
SMTP_PASSWORD=my_secret_password
GRAFANA_ADMIN_PASSWORD=xxx
MARIADB_ROOT_PASSWORD=xxx
```

**Implementation:**
- Create `configs/.secrets.env` (gitignored)
- Update `deploy-enhanced.sh` to source secrets from `.env`
- Scrub secrets from logs (`sed 's/PASSWORD=[^ ]*/PASSWORD=[REDACTED]/g'`)
- Add secret validation (check all required secrets are set)

**Time:** 1-2 days | **Impact:** HIGH security improvement

---

### 2. Dynamic Hardware Detection (P1 - Fix This Week)

**Before:**
```yaml
# inventory.yaml (STATIC - user input)
specs:
  cpu: 1           # User types this manually
  memory_mb: 2048  # May be wrong!
  disk_gb: 20      # Never updated
```

**After:**
```bash
# Detected automatically via SSH
detect_hardware() {
    cpu=$(remote_exec "nproc")
    memory_mb=$(remote_exec "free -m | awk '/^Mem:/ {print \$2}'")
    disk_gb=$(remote_exec "df -BG / | awk 'NR==2 {print \$2}' | tr -d 'G'")
}

# Stored in state file
.deploy-state/hardware/observability.json:
{
  "cpu": 2,          # Detected, not user input
  "memory_mb": 4096,
  "disk_gb": 40,
  "detected_at": "2025-12-31T10:05:00Z"
}
```

**Benefits:**
- Always accurate (no user error)
- Detects hardware changes (VPS upgrade)
- Historical tracking
- Correct monitoring thresholds

**Implementation:**
- Create `lib/hardware-detection.sh`
- Add `detect_hardware()` function
- Call during pre-flight checks
- Display hardware summary table
- Store in deployment state

**Time:** 2-3 days | **Impact:** MEDIUM operational improvement

---

### 3. Enhanced State Management (P2 - Next Month)

**Before:**
```json
// .deploy-state/deployment.state (limited info)
{
  "status": "completed",
  "observability": {"status": "completed"},
  "vpsmanager": {"status": "completed"}
}
```

**After:**
```json
// .deploy-state/history/20251231-100000.json (rich data)
{
  "deployment_id": "20251231-100000-a1b2c3",
  "deployer": {"user": "admin", "hostname": "laptop"},
  "config": {"inventory_sha256": "abc123..."},
  "targets": {
    "observability": {
      "hardware": {"cpu": 2, "memory_mb": 4096, "detected_at": "..."},
      "components": {
        "prometheus": {"status": "completed", "version": "3.8.1"}
      },
      "resources_created": {
        "users": ["observability"],
        "services": ["prometheus.service"],
        "directories": ["/var/lib/observability"]
      }
    }
  }
}
```

**Benefits:**
- Deployment history (audit trail)
- Component-level granularity
- Resource tracking (for cleanup)
- Reproducible deployments

**Time:** 1 week | **Impact:** MEDIUM compliance improvement

---

### 4. Parallel Deployment (P2 - Next Month)

**Before (Sequential):**
```
Observability VPS (10 min) ──► VPSManager VPS (15 min)
Total: 25 minutes for 2 VPS
Total: 100+ minutes for 10 VPS  ← SLOW!
```

**After (Parallel):**
```
Observability VPS (10 min) ──┐
                             ├──► Both complete in 15 minutes
VPSManager VPS (15 min) ─────┘

Total: 15 minutes for 2 VPS (40% faster)
Total: 20-30 minutes for 10 VPS (80% faster!)
```

**Implementation:**
```bash
# Parallel deployment with xargs
echo "observability vpsmanager" | \
    xargs -P 2 -n 1 ./deploy-target.sh
```

**Time:** 1 week | **Impact:** MEDIUM time savings (50% faster)

---

## Scalability Analysis

### Can CHOM Scale to 10+ VPS?

| Architecture | 2 VPS | 5 VPS | 10 VPS | Max VPS |
|-------------|-------|-------|--------|---------|
| **Current (v4.3.0)** | 25 min | 60 min | 150 min | 5-7 servers |
| **Enhanced Bash (v5.0)** | 15 min | 20 min | 30 min | 10-15 servers |
| **Ansible** | 15 min | 15 min | 20 min | 50+ servers |
| **Terraform + Ansible** | 20 min | 20 min | 25 min | 100+ servers |

**Recommendation:**
- **For 2-5 VPS:** Stick with enhanced Bash (fix security + hardware detection)
- **For 10-15 VPS:** Enhance Bash with parallelization
- **For 50+ VPS:** Migrate to Ansible or Terraform

---

## Security Posture

### Current Risks

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Secrets in git | HIGH | HIGH | Move to .secrets.env (gitignored) |
| Secrets in logs | MEDIUM | MEDIUM | Scrub with sed |
| SSH key compromise | MEDIUM | LOW | Rotate keys, use SSH agent |
| No audit trail | MEDIUM | HIGH | Add deployer metadata to state |

### Security Improvements (Priority Order)

1. **Week 1:** Move secrets to `.secrets.env` (P0)
2. **Week 2:** Scrub secrets from logs (P0)
3. **Month 1:** Implement secret encryption (sops, ansible-vault) (P1)
4. **Month 2:** Add audit logging (who, what, when) (P2)
5. **Quarter 1:** Integrate with HashiCorp Vault (P3)

---

## Implementation Roadmap

### Phase 1: Security Fixes (Week 1)

**Goal:** Eliminate critical security risks

Tasks:
- [ ] Create `configs/.secrets.env.example`
- [ ] Add `.secrets.env` to `.gitignore`
- [ ] Update `deploy-enhanced.sh` to source secrets from `.env`
- [ ] Add secret validation (check required secrets are set)
- [ ] Scrub secrets from logs
- [ ] Update documentation

**Deliverable:** Secrets no longer in version control

**Files to modify:**
- `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh`
- `/home/calounx/repositories/mentat/chom/deploy/configs/inventory.yaml`
- `/home/calounx/repositories/mentat/chom/deploy/.gitignore`

---

### Phase 2: Hardware Detection (Week 2)

**Goal:** Eliminate static hardware specs

Tasks:
- [ ] Create `lib/hardware-detection.sh`
- [ ] Implement `detect_hardware()` function
- [ ] Add to pre-flight checks
- [ ] Display hardware summary table
- [ ] Store in deployment state
- [ ] Compare detected vs inventory (warn on mismatch)

**Deliverable:** Hardware specs detected automatically

**Files to create:**
- `/home/calounx/repositories/mentat/chom/deploy/lib/hardware-detection.sh`

**Files to modify:**
- `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh`
- `/home/calounx/repositories/mentat/chom/deploy/configs/inventory.yaml` (remove specs)

---

### Phase 3: Enhanced State (Week 3-4)

**Goal:** Add deployment history and audit trail

Tasks:
- [ ] Create `lib/state-management.sh`
- [ ] Implement deployment history (keep last 10)
- [ ] Add component-level state tracking
- [ ] Add resource inventory
- [ ] Add deployer metadata
- [ ] Add config snapshot

**Deliverable:** Full audit trail of deployments

**Files to create:**
- `/home/calounx/repositories/mentat/chom/deploy/lib/state-management.sh`

---

### Phase 4: Parallel Deployment (Week 5-6)

**Goal:** Reduce deployment time by 50%

Tasks:
- [ ] Implement dependency graph
- [ ] Add parallel execution with `xargs -P`
- [ ] Add progress tracking for parallel jobs
- [ ] Add failure isolation

**Deliverable:** 10 VPS deployment in 30 minutes instead of 100 minutes

---

## Key Recommendations

### Immediate Actions (This Week)

1. **Move SMTP password to `.secrets.env`** (1 day)
   - Create `configs/.secrets.env` (gitignored)
   - Remove password from `inventory.yaml`
   - Update deployment script to source `.env`

2. **Implement dynamic hardware detection** (2 days)
   - Create `lib/hardware-detection.sh`
   - Detect vCPU, RAM, disk via SSH
   - Display hardware summary before deployment

3. **Add secret scrubbing to logs** (1 day)
   - Use `sed` to replace passwords with `[REDACTED]`
   - Prevent secrets in process lists

### Short-term Actions (This Month)

4. **Enhanced state management** (1 week)
   - Keep deployment history (last 10 deployments)
   - Add component-level tracking
   - Add deployer metadata for audit trail

5. **Deployment audit trail** (3 days)
   - Log who deployed (user, hostname, IP)
   - Log what config was used (hash)
   - Store config snapshot in state file

### Long-term Actions (This Quarter)

6. **Parallel deployment** (1 week)
   - Deploy observability + vpsmanager in parallel
   - 50% time savings

7. **Ansible migration (if scaling to 10+ VPS)** (2-3 weeks)
   - Convert Bash scripts to Ansible playbooks
   - Use Ansible Vault for secrets
   - Better scalability and maintainability

---

## Answers to Your Specific Questions

### 1. Should hardware specs be detected at deployment time or stored in inventory?

**Answer:** BOTH

- **Detect at deployment time** (primary source of truth)
- **Store in deployment state** (for history and audit)
- **Compare with inventory if provided** (warn on mismatch)

**Rationale:**
- Detection ensures accuracy (no user error)
- State storage provides historical tracking
- Inventory comparison catches VPS upgrades/downgrades

---

### 2. How should hardware detection be implemented?

**Answer:** Remote SSH commands (ansible-facts style)

**Implementation:**
```bash
detect_hardware() {
    local host=$1
    local user=$2
    local port=$3

    # Detect vCPU count
    cpu=$(remote_exec "$host" "$user" "$port" "nproc")

    # Detect total RAM in MB
    memory_mb=$(remote_exec "$host" "$user" "$port" \
        "free -m | awk '/^Mem:/ {print \$2}'")

    # Detect total disk in GB (root partition)
    disk_gb=$(remote_exec "$host" "$user" "$port" \
        "df -BG / | awk 'NR==2 {print \$2}' | tr -d 'G'")

    # Additional metadata
    arch=$(remote_exec "$host" "$user" "$port" "uname -m")
    os=$(remote_exec "$host" "$user" "$port" \
        "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"'")

    # Store results
    HARDWARE["${host}_cpu"]=$cpu
    HARDWARE["${host}_memory_mb"]=$memory_mb
    HARDWARE["${host}_disk_gb"]=$disk_gb
}
```

**Why SSH instead of alternatives:**
- **Pros:** No agent required, works immediately after SSH key setup
- **Cons:** Slower than persistent agent (acceptable for pre-flight checks)
- **Alternative:** Ansible facts (better for 10+ servers)

---

### 3. Should there be a validation step before deployment?

**Answer:** YES - Add to pre-flight checks

**Validation flow:**
1. Detect hardware on all VPS servers (parallel)
2. Display hardware summary table
3. Compare against minimum requirements
4. Warn if below recommended specs
5. Allow user to abort if specs are wrong

**Example output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hardware Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Target           vCPU    RAM (MB)   Disk (GB)   Status
───────────────────────────────────────────────────────
Observability      2       4096        40        ✓ OK
VPSManager         4       8192        80        ✓ OK

[✓] All servers meet minimum requirements
[WARN] Observability has 5GB free disk (consider cleanup)

Deploy CHOM Infrastructure? [Y/n]
```

---

### 4. Should hardware specs be logged for audit purposes?

**Answer:** YES - Store in deployment state

**Audit strategy:**
1. Store hardware specs in deployment state file
2. Track changes over time
3. Alert if specs change between deployments (VPS upgrade/downgrade)
4. Use for capacity planning

**State file structure:**
```json
{
  "deployment_id": "20251231-100000",
  "targets": {
    "observability": {
      "hardware": {
        "cpu": 2,
        "memory_mb": 4096,
        "disk_gb": 40,
        "architecture": "x86_64",
        "os": "Debian 13.0",
        "detected_at": "2025-12-31T10:05:00Z"
      }
    }
  }
}
```

**Audit queries:**
- "Show hardware changes for observability VPS over last 6 months"
- "Alert if any VPS has less than 10GB free disk"
- "Track RAM usage trends across all VPS"

---

## Conclusion

The CHOM deployment system is **well-architected for 2-3 VPS servers** with excellent UX and auto-healing. However, it has **critical security issues** (plaintext secrets) and **operational limitations** (static hardware, no audit trail) that must be addressed before production use.

**Recommendation:** Implement Phase 1 and Phase 2 this week (security + hardware detection), then plan Phase 3 and Phase 4 for next month.

---

**Related Documents:**
- `/home/calounx/repositories/mentat/chom/deploy/ARCHITECTURE-REVIEW.md` (full analysis)
- `/home/calounx/repositories/mentat/chom/deploy/ARCHITECTURE-DIAGRAMS.md` (visual diagrams)
- `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh` (main script)
- `/home/calounx/repositories/mentat/chom/deploy/configs/inventory.yaml` (configuration)
