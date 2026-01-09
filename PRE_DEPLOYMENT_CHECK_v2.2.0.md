# Pre-Deployment Check Report - CHOM v2.2.0
**Date:** 2026-01-09
**Target Servers:** mentat.arewel.com, landsraad.arewel.com
**Deployment User:** stilgar

---

## Executive Summary

**Status:** READY FOR DEPLOYMENT with CRITICAL SSH configuration fix required

The repository is ready for v2.2.0 deployment. However, the stilgar user on mentat.arewel.com needs SSH key authorization configured before deployment can proceed.

---

## 1. SSH Access Test Results

### mentat.arewel.com (Observability Server)
- **calounx SSH access:** ✅ SUCCESS
- **stilgar user exists:** ✅ SUCCESS (uid=1002, groups: stilgar, sudo)
- **stilgar SSH key exists:** ✅ SUCCESS (ED25519 key generated)
- **stilgar authorized_keys:** ❌ EMPTY FILE (critical issue)
- **stilgar → mentat SSH:** ❌ FAILED (Permission denied - expected, no authorized key)
- **stilgar → landsraad SSH:** ✅ SUCCESS

**Public Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElWk3U5wLKgouE+GuEQ50XFELnKpgI9TaK8L+DsGGUa stilgar@mentat.arewel.com
```

### landsraad.arewel.com (Application Server)
- **calounx SSH access:** ✅ SUCCESS
- **stilgar user exists:** ✅ SUCCESS (uid=1002, groups: stilgar, sudo)
- **stilgar SSH key exists:** ❌ NOT FOUND (will be generated during deployment)
- **stilgar authorized_keys:** ✅ CONFIGURED (contains mentat's stilgar key)
- **stilgar SSH from mentat:** ✅ SUCCESS

---

## 2. Current Deployment State

### mentat.arewel.com
- **CHOM Deployment:** ❌ NOT DEPLOYED
- **Directory /var/www/chom:** Does not exist
- **Current Version:** N/A (fresh deployment)

### landsraad.arewel.com
- **VPSManager Deployment:** ✅ DEPLOYED
- **Directory /opt/vpsmanager:** Exists (root owned)
- **Current Version:** No VERSION file found
- **Structure:** Basic directories (bin, config, data, lib, templates, var)

---

## 3. Git Repository State

### Branch Information
- **Current Branch:** main
- **Status:** Ahead of chom/main by 158 commits
- **Working Tree:** ✅ CLEAN (no uncommitted changes)

### Recent Commits
```
e684962 docs: Add comprehensive integration test report for v2.2.0
3c653bc feat: Phase 4 UI - VPSManager API endpoints and Livewire components
198ee10 feat: Phase 4 - System health monitoring, observability dashboards, and documentation v2.2.0
```

### Version Files
- **VERSION:** 2.2.0 ✅
- **package.json:** 2.2.0 ✅

---

## 4. Deployment Script Configuration

### Files Status
- **deploy-chom-automated.sh:** ✅ Executable
- **deploy-chom.sh:** ✅ Executable
- **deploy.sh:** ✅ Executable
- **.deployment-secrets:** ❌ Will be generated (normal)
- **.deployment-secrets.template:** ✅ Present

### Configuration Variables
- **MENTAT_HOST:** mentat.arewel.com
- **LANDSRAAD_HOST:** landsraad.arewel.com
- **DEPLOY_USER:** stilgar (configurable)

---

## 5. Critical Issues & Blockers

### CRITICAL: stilgar SSH Configuration on mentat
**Issue:** The stilgar user on mentat.arewel.com has an empty authorized_keys file, preventing SSH access from stilgar@mentat to stilgar@mentat (localhost SSH).

**Impact:** The deployment script may need to SSH from mentat to itself as stilgar, which will fail.

**Fix Required:**
```bash
# Run on mentat.arewel.com as calounx:
ssh calounx@mentat.arewel.com "sudo bash -c 'cat /home/stilgar/.ssh/id_ed25519.pub >> /home/stilgar/.ssh/authorized_keys && chmod 600 /home/stilgar/.ssh/authorized_keys'"
```

**Verification:**
```bash
ssh calounx@mentat.arewel.com "sudo -u stilgar ssh -o StrictHostKeyChecking=no stilgar@mentat.arewel.com 'echo SSH_TEST_OK'"
```

---

## 6. Warnings & Recommendations

### Warnings
1. **VPSManager version unknown:** No VERSION file in /opt/vpsmanager on landsraad
2. **Large commit delta:** 158 commits ahead of chom/main - ensure remote is updated
3. **No SSH key on landsraad stilgar:** Will be generated during deployment (expected)

### Recommendations
1. **Fix SSH authorization** on mentat before deployment (see Critical Issues)
2. **Test SSH access** after fixing authorization
3. **Review deployment secrets template** before generation
4. **Plan for zero-downtime** - this is a fresh deployment, no existing service to migrate
5. **Backup VPSManager state** on landsraad before deployment
6. **Monitor deployment logs** closely for first production deployment

---

## 7. Pre-Deployment Checklist

- [x] Git repository on main branch
- [x] Working tree clean
- [x] VERSION file matches 2.2.0
- [x] package.json version matches 2.2.0
- [x] Deployment scripts executable
- [x] stilgar user exists on both servers
- [x] stilgar has sudo access on both servers
- [ ] **stilgar authorized_keys configured on mentat** (REQUIRED FIX)
- [x] stilgar can SSH to landsraad
- [x] calounx can SSH to both servers
- [x] VPSManager exists on landsraad

---

## 8. Recommended Deployment Commands

### Step 1: Fix SSH Authorization (CRITICAL)
```bash
# Add stilgar's public key to its own authorized_keys on mentat
ssh calounx@mentat.arewel.com "sudo bash -c 'cat /home/stilgar/.ssh/id_ed25519.pub >> /home/stilgar/.ssh/authorized_keys && chmod 600 /home/stilgar/.ssh/authorized_keys && chown stilgar:stilgar /home/stilgar/.ssh/authorized_keys'"

# Verify fix
ssh calounx@mentat.arewel.com "sudo -u stilgar ssh -o StrictHostKeyChecking=no stilgar@mentat.arewel.com 'echo SSH_FIXED'"
```

### Step 2: Transfer Repository to mentat
```bash
# Create deployment staging area
ssh calounx@mentat.arewel.com "sudo mkdir -p /opt/chom-deploy && sudo chown stilgar:stilgar /opt/chom-deploy"

# Transfer repository
rsync -avz --exclude='.git' --exclude='node_modules' --exclude='vendor' \
  /home/calounx/repositories/mentat/ \
  calounx@mentat.arewel.com:/opt/chom-deploy/

# Fix ownership
ssh calounx@mentat.arewel.com "sudo chown -R stilgar:stilgar /opt/chom-deploy"
```

### Step 3: Run Automated Deployment
```bash
# SSH to mentat as calounx
ssh calounx@mentat.arewel.com

# Switch to stilgar
sudo su - stilgar

# Navigate to deployment directory
cd /opt/chom-deploy/deploy

# Run automated deployment
./deploy-chom-automated.sh
```

### Alternative: Manual Deployment with Interactive Mode
```bash
# For more control during first production deployment
./deploy-chom-automated.sh --interactive
```

---

## 9. Post-Deployment Verification

After deployment completes, verify:

1. **CHOM Application:**
   ```bash
   curl -k https://mentat.arewel.com
   curl -k https://chom.arewel.com
   ```

2. **Observability Stack:**
   ```bash
   # Grafana
   curl -k https://mentat.arewel.com:3000
   
   # Prometheus
   curl -k https://mentat.arewel.com:9090
   
   # Loki
   curl -k https://mentat.arewel.com:3100/ready
   ```

3. **VPSManager API:**
   ```bash
   ssh calounx@landsraad.arewel.com "sudo systemctl status vpsmanager"
   ```

4. **VERSION Files:**
   ```bash
   ssh calounx@mentat.arewel.com "cat /var/www/chom/current/VERSION"
   ssh calounx@landsraad.arewel.com "cat /opt/vpsmanager/VERSION"
   ```

---

## 10. Rollback Plan

Since this is a fresh deployment, rollback is simply:
```bash
# On mentat
sudo rm -rf /var/www/chom

# On landsraad (if VPSManager was updated)
sudo systemctl stop vpsmanager
sudo rm -rf /opt/vpsmanager/backup-*
```

---

## Conclusion

**The repository and servers are ready for CHOM v2.2.0 deployment after fixing the critical SSH authorization issue on mentat.**

Key Action Items:
1. Fix stilgar authorized_keys on mentat (5 minutes)
2. Transfer repository to mentat (10 minutes)
3. Run automated deployment script (30-45 minutes)
4. Verify all services (15 minutes)

**Estimated Total Time:** 60-75 minutes

**Risk Level:** LOW (fresh deployment, no existing production to migrate)

---

Generated by: Claude Sonnet 4.5 (claude-code)
Date: 2026-01-09
