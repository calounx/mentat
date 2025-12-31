# CHOM Architecture - Quick Reference Card

**Review Date:** 2025-12-31 | **System Version:** 4.3.0 | **Pages:** 4 detailed docs

---

## Critical Findings (Fix This Week)

| Issue | Severity | Fix Time | Files Affected |
|-------|----------|----------|----------------|
| SMTP password in plaintext | HIGH | 1 day | inventory.yaml, deploy-enhanced.sh |
| Static hardware specs | MEDIUM | 2 days | inventory.yaml, deploy-enhanced.sh |

---

## System Stats

```
Language:        Bash 4.0+
Main Script:     deploy-enhanced.sh (2,616 lines)
Library:         deploy-common.sh (682 lines)
Config:          inventory.yaml (58 lines)
Target Servers:  2 VPS (observability, vpsmanager)
Deployment Time: 15-25 minutes (sequential)
Max Scalability: 5-7 VPS servers
```

---

## Architecture at a Glance

```
┌──────────────────┐
│ Control Machine  │
│  deploy-enhanced │ ─SSH─► Observability VPS (Prometheus, Grafana, Loki)
│  inventory.yaml  │ ─SSH─► VPSManager VPS (Nginx, PHP, MariaDB, Redis)
└──────────────────┘
```

---

## What Works Well

1. **UX:** Minimal interaction (1 prompt), auto-healing, clear progress
2. **Idempotency:** Safe to re-run, cleanup before deployment
3. **Security:** SSH keys (not passwords), input validation
4. **Pre-flight:** Validates SSH, disk, RAM, CPU before deploy

---

## Critical Issues

### 1. Secret Management (P0)

**Problem:**
```yaml
smtp:
  password: "my_secret"  # Plaintext in inventory.yaml!
```

**Fix:**
```bash
# .secrets.env (gitignored)
SMTP_PASSWORD=my_secret
GRAFANA_ADMIN_PASSWORD=xxx
```

**Action:**
- Create `configs/.secrets.env`
- Update deploy-enhanced.sh to source .env
- Remove password from inventory.yaml

---

### 2. Hardware Detection (P1)

**Problem:**
```yaml
specs:
  cpu: 1           # User input, never validated
  memory_mb: 2048  # May be wrong!
```

**Fix:**
```bash
# Detect via SSH
cpu=$(remote_exec "nproc")
memory_mb=$(remote_exec "free -m | awk '/^Mem:/ {print $2}'")
```

**Action:**
- Create `lib/hardware-detection.sh`
- Call during pre-flight checks
- Display hardware summary table

---

## Quick Fixes (Copy-Paste Ready)

### Fix 1: Move Secrets to .env

```bash
# Create .secrets.env
cd /home/calounx/repositories/mentat/chom/deploy
cat > configs/.secrets.env << 'EOF'
# SMTP Configuration
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=alerts@example.com
SMTP_PASSWORD=your_password_here

# Admin Passwords
GRAFANA_ADMIN_PASSWORD=secure_random_password
MARIADB_ROOT_PASSWORD=secure_random_password
EOF

# Gitignore it
echo ".secrets.env" >> .gitignore

# Update deploy-enhanced.sh (add after line 45)
set -a
source "${SCRIPT_DIR}/configs/.secrets.env"
set +a

# Remove password from inventory.yaml
sed -i '/password:/d' configs/inventory.yaml
```

---

### Fix 2: Add Hardware Detection

```bash
# Create hardware detection library
cat > lib/hardware-detection.sh << 'EOSH'
#!/bin/bash
detect_hardware() {
    local host=$1
    local user=$2
    local port=$3

    cpu=$(remote_exec "$host" "$user" "$port" "nproc")
    memory_mb=$(remote_exec "$host" "$user" "$port" "free -m | awk '/^Mem:/ {print \$2}'")
    disk_gb=$(remote_exec "$host" "$user" "$port" "df -BG / | awk 'NR==2 {print \$2}' | tr -d 'G'")

    echo "Hardware: ${cpu} vCPU, ${memory_mb}MB RAM, ${disk_gb}GB disk"
}
EOSH

# Add to deploy-enhanced.sh (after line 50)
source "${SCRIPT_DIR}/lib/hardware-detection.sh"

# Remove specs from inventory.yaml
sed -i '/specs:/,+3d' configs/inventory.yaml
```

---

## Deployment Flow

```
1. Pre-flight Checks (1 min)
   ├─ Validate inventory.yaml
   ├─ Test SSH connectivity
   ├─ Detect hardware (NEW!)
   └─ Check disk/RAM/CPU

2. User Confirmation (1 prompt)
   └─ "Deploy? [Y/n]"

3. Deploy Observability (10 min)
   ├─ Install Prometheus
   ├─ Install Grafana
   └─ Install Loki

4. Deploy VPSManager (15 min)
   ├─ Install Nginx/PHP/MariaDB
   └─ Install exporters

Total: 15-25 minutes
```

---

## File Locations

```
/home/calounx/repositories/mentat/chom/deploy/
├─ deploy-enhanced.sh          # Main orchestrator (2,616 lines)
├─ lib/deploy-common.sh        # Shared utilities (682 lines)
├─ configs/
│  ├─ inventory.yaml           # Configuration
│  └─ .secrets.env             # Secrets (gitignored, NEW!)
├─ scripts/
│  ├─ setup-observability-vps.sh
│  └─ setup-vpsmanager-vps.sh
└─ .deploy-state/
   ├─ deployment.state         # Current deployment
   └─ hardware/                # Hardware snapshots (NEW!)
      ├─ observability.json
      └─ vpsmanager.json
```

---

## State File Structure

**Current (v4.3.0):**
```json
{
  "status": "completed",
  "observability": {"status": "completed"},
  "vpsmanager": {"status": "completed"}
}
```

**Enhanced (v5.0.0):**
```json
{
  "deployment_id": "20251231-100000",
  "deployer": {"user": "admin"},
  "targets": {
    "observability": {
      "hardware": {"cpu": 2, "memory_mb": 4096},
      "components": {"prometheus": {"status": "completed"}}
    }
  }
}
```

---

## Scalability Comparison

| Servers | Current (v4.3.0) | Enhanced (v5.0.0) | Ansible |
|---------|------------------|-------------------|---------|
| 2 VPS   | 25 min           | 15 min            | 15 min  |
| 5 VPS   | 60 min           | 20 min            | 15 min  |
| 10 VPS  | 150 min          | 30 min            | 20 min  |
| Max     | 5-7 servers      | 10-15 servers     | 50+ servers |

---

## Security Checklist

- [ ] Move SMTP password to `.secrets.env`
- [ ] Add `.secrets.env` to `.gitignore`
- [ ] Scrub secrets from logs
- [ ] Validate all required secrets before deploy
- [ ] Rotate secrets quarterly
- [ ] Use encrypted secret store (sops, vault)

---

## Hardware Requirements

### Minimum

| VPS | vCPU | RAM | Disk |
|-----|------|-----|------|
| Observability | 1 | 2GB | 20GB |
| VPSManager | 2 | 4GB | 40GB |

### Recommended

| VPS | vCPU | RAM | Disk |
|-----|------|-----|------|
| Observability | 2 | 4GB | 40GB |
| VPSManager | 4 | 8GB | 80GB |

---

## Commands Reference

```bash
# Full deployment
./deploy-enhanced.sh all

# Auto-approve (CI/CD)
./deploy-enhanced.sh --auto-approve all

# Pre-flight checks only
./deploy-enhanced.sh --validate

# Show deployment plan
./deploy-enhanced.sh --plan

# Resume failed deployment
./deploy-enhanced.sh --resume

# Force deployment (skip validation)
./deploy-enhanced.sh --force all
```

---

## Troubleshooting

**Issue:** SSH connection fails
**Fix:** Check IP in inventory.yaml, verify SSH key copied

**Issue:** Insufficient disk space
**Fix:** Clean up VPS: `sudo apt-get clean && sudo journalctl --vacuum-time=7d`

**Issue:** Service conflicts
**Fix:** Stop conflicting services: `sudo systemctl stop prometheus`

**Issue:** Hardware detection fails
**Fix:** Verify SSH sudo access: `ssh deploy@vps 'sudo nproc'`

---

## Next Steps (Priority Order)

1. **Week 1:** Fix secret management (P0)
2. **Week 2:** Add hardware detection (P1)
3. **Month 1:** Enhanced state management (P2)
4. **Month 2:** Parallel deployment (P2)
5. **Quarter 1:** Ansible migration (if scaling to 10+ VPS)

---

## Related Documentation

1. **ARCHITECTURE-REVIEW.md** (full 13-section analysis)
2. **ARCHITECTURE-DIAGRAMS.md** (visual architecture diagrams)
3. **ARCHITECTURE-SUMMARY.md** (executive summary)
4. **HARDWARE-DETECTION-IMPLEMENTATION.md** (implementation guide)

---

## Contact

**Reviewed by:** Backend System Architect
**Review date:** 2025-12-31
**System version:** 4.3.0
**Repository:** /home/calounx/repositories/mentat/chom/deploy

---

**End of Quick Reference**

Print this page for quick troubleshooting during deployments!
