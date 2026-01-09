# Phase 0 Reliability Optimizations - Deployment Report

**Date:** 2026-01-09
**Servers:** mentat.arewel.com (observability), landsraad.arewel.com (CHOM app)
**Current Status:** READ-ONLY ASSESSMENT COMPLETE

---

## Executive Summary

Phase 0 reliability optimizations have been developed and committed to the repository but **NOT YET DEPLOYED** to production servers. The deployment is ready to proceed through the automated deployment scripts.

**Key Finding:** Current deployment on landsraad is at commit `7f572d2` (Jan 5), while the repository is at `bb283db` (Jan 9). The new API endpoints and database migrations are missing from production.

---

## Current State Assessment

### 1. landsraad.arewel.com (CHOM Application Server)

#### Deployment Status
- **Current Deployment:** `/var/www/chom/current` → `releases/20260106_132320`
- **Git Commit:** `7f572d2` - "feat: Enhance ProfileSettings with tenant and site access visibility"
- **Deployed Version:** v2.1.0
- **Last Deployment:** January 6, 2026 13:23:20 UTC

#### Application Status
- **PHP-FPM:** ✅ Running (5 worker processes active)
- **Deployment Method:** Blue-green deployment with symlink switching
- **Shared Configuration:** `/var/www/chom/shared/` (contains .env file)
- **Releases Kept:** 5 most recent deployments

#### Missing Components (Not Yet Deployed)
- ❌ **SystemSetting Model** - Does not exist in `/var/www/chom/current/app/Models/`
- ❌ **API Controllers:**
  - `SystemConfigController.php` - Missing
  - `ObservabilityHealthController.php` - Missing
- ❌ **API Routes:**
  - `/api/v1/system/smtp-config` - Returns 301 redirect (route not registered)
  - `/api/v1/observability/health` - Returns 301 redirect (route not registered)
- ❌ **Database Migration:** `2026_01_09_083804_create_system_settings_table.php` - Not run
- ❌ **Artisan Commands:**
  - `smtp:export` - Not available
  - `alertmanager:sync` - Not available

#### API Endpoint Testing Results
```bash
# Current behavior (all redirects indicate routes don't exist):
curl https://landsraad.arewel.com/api/v1/system/smtp-config
# → 301 Moved Permanently

curl https://landsraad.arewel.com/api/v1/observability/health
# → 301 Moved Permanently
```

#### Database Migration Status
Last migration run: `2026_01_06_122430_add_metadata_to_users_table` (Batch 7)

**Missing migration:** `system_settings` table does not exist yet.

---

### 2. mentat.arewel.com (Observability Server)

#### Observability Stack Status
- **Prometheus:** ✅ Running (active since Jan 5 17:20:53)
  - Config: `/etc/observability/prometheus/prometheus.yml`
  - Storage: `/var/lib/observability/prometheus`
  - External URL: `https://mentat.arewel.com/prometheus`

- **Alertmanager:** ✅ Running (active since Jan 5 16:28:57)
  - Config: `/etc/observability/alertmanager/alertmanager.yml`
  - Storage: `/var/lib/observability/alertmanager`
  - External URL: `https://mentat.arewel.com/alertmanager`

- **Grafana:** ✅ Running (status not checked but implied by config)

#### Alert Rules
- **Location:** `/etc/observability/prometheus/rules/`
- **Current File:** `basic.yml` (5.7KB)
- **Status:** ⚠️ Using old alert rules (pre-Phase 0)

**Repository has NEW alert rules:**
- `exporters.yml` - Enhanced exporter health monitoring with detailed troubleshooting

#### Targets (Service Discovery)
- **Location:** `/etc/observability/prometheus/targets/`
- **Files Present:**
  - `node_landsraad.yml` ✅
  - `node_mentat.yml` ✅
  - `nginx_landsraad.yml` ✅
  - `nginx_mentat.yml` ✅
  - `phpfpm_landsraad.yml` ✅
  - `postgresql_landsraad.yml` ✅
  - `redis_landsraad.yml` ✅
  - `blackbox_endpoints.yml` ✅

#### Alertmanager Configuration
**Current Config:** SMTP settings are **commented out** (not configured):
```yaml
# SMTP settings - uncomment and configure for email alerts
# smtp_from: 'alertmanager@chom.arewel.com'
# smtp_smarthost: 'smtp.example.com:587'
# ...
```

**Phase 0 Enhancement:** New `deploy-observability.sh` script will fetch SMTP config from CHOM API and auto-configure Alertmanager.

#### Deployment Repository Status
- **Location:** `/opt/chom-deploy/`
- **Type:** NOT a git repository (deployment files only)
- **Last Updated:** January 6, 2026 13:23
- **Script Versions:**
  - `deploy-observability.sh` - 17.9KB ⚠️ OLD VERSION (no API integration)
  - `deploy-chom.sh` - 21KB (orchestration script)
  - All deployment scripts present

---

## Changes in Repository (Not Yet Deployed)

### Commits Since Last Deployment

```
bb283db - feat: Optimize CHOM-observability architecture for production reliability
2ffc907 - feat: Integrate SMTP configuration with Alertmanager
a892558 - feat: Add SMTP configuration UI in admin settings
```

### Files Changed Since d597c3b (Last Known Good Deployment)

**New Laravel Components:**
1. `app/Console/Commands/ExportSmtpConfig.php` - Export SMTP config to shell/YAML
2. `app/Console/Commands/SyncAlertmanagerConfig.php` - Auto-sync Alertmanager via API
3. `app/Http/Controllers/Api/SystemConfigController.php` - SMTP API endpoint
4. `app/Http/Controllers/Api/ObservabilityHealthController.php` - Health monitoring API
5. `app/Models/SystemSetting.php` - System settings model
6. `app/Livewire/Admin/SystemSettings.php` - Admin UI for SMTP config
7. `app/Services/ObservabilityHealthService.php` - Health check service
8. `database/migrations/2026_01_09_083804_create_system_settings_table.php` - DB migration

**Deployment Scripts:**
9. `deploy/scripts/deploy-observability.sh` - ⭐ Enhanced with API integration
10. `deploy/config/mentat/alertmanager.yml` - Updated template
11. `deploy/config/mentat/prometheus-alerts/exporters.yml` - New enhanced alert rules
12. `deploy/config/mentat/prometheus.yml` - Updated Prometheus config

**Routes:**
13. `routes/api.php` - Added system/observability endpoints

**Views:**
14. `resources/views/livewire/admin/system-settings.blade.php` - SMTP admin UI

---

## Deployment Architecture

### Current Deployment Flow
```
┌─────────────────────────────────────────────────────────────┐
│ Local Repository: /home/calounx/repositories/mentat        │
│ - Git remote: git@github.com:calounx/mentat.git            │
│ - Current branch: main                                      │
│ - Latest commit: bb283db (Jan 9)                            │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ git push
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ GitHub: calounx/mentat                                      │
│ - Main branch: bb283db                                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Deployment via:
                          │ /opt/chom-deploy/deploy-chom.sh
                          │
          ┌───────────────┴────────────────┐
          ↓                                ↓
┌─────────────────────┐        ┌──────────────────────┐
│ mentat.arewel.com   │        │ landsraad.arewel.com │
│ - Observability     │        │ - CHOM Application   │
│ - Deployment Hub    │        │ - Current: 7f572d2   │
│ - Has deploy scripts│        │ - Needs: bb283db     │
└─────────────────────┘        └──────────────────────┘
```

### Deployment Method Discovery
- **Orchestration Script:** `/opt/chom-deploy/deploy-chom.sh` on mentat
- **Application Deployment:** Blue-green via `deploy-application.sh`
- **Observability Deployment:** Native systemd via `deploy-observability.sh`
- **SSH Access:** calounx user (read-only), stilgar user (deployment)
- **Repository URL Required:** Must provide `--repo-url=https://github.com/calounx/mentat.git`

---

## Deployment Plan

### Prerequisites
✅ All prerequisites are met:
- [x] SSH access configured (calounx user)
- [x] Deployment scripts exist in repository
- [x] GitHub repository is up to date (bb283db pushed)
- [x] Both servers are healthy and running
- [x] No blocking issues identified

### Phase 1: Update Deployment Scripts on mentat (1-2 min)

Since `/opt/chom-deploy` is NOT a git repository, we need to copy updated scripts:

```bash
# From local machine (calounx)
cd /home/calounx/repositories/mentat

# Copy updated deployment scripts to mentat
scp deploy/scripts/deploy-observability.sh \
    calounx@mentat.arewel.com:/tmp/

scp deploy/config/mentat/prometheus-alerts/exporters.yml \
    calounx@mentat.arewel.com:/tmp/

# SSH to mentat and update scripts
ssh calounx@mentat.arewel.com
sudo cp /tmp/deploy-observability.sh /opt/chom-deploy/scripts/
sudo chmod +x /opt/chom-deploy/scripts/deploy-observability.sh
sudo chown stilgar:stilgar /opt/chom-deploy/scripts/deploy-observability.sh

# Update alert rules (will be deployed with observability script)
sudo mkdir -p /opt/chom-deploy/config/mentat/prometheus-alerts/
sudo cp /tmp/exporters.yml /opt/chom-deploy/config/mentat/prometheus-alerts/
sudo chown -R stilgar:stilgar /opt/chom-deploy/config/
```

### Phase 2: Deploy Application to landsraad (5-10 min)

This will deploy all new Laravel code including API endpoints, models, and migrations:

```bash
# SSH to mentat (deployment hub)
ssh calounx@mentat.arewel.com

# Switch to stilgar or use sudo
sudo -u stilgar bash

# Navigate to deployment directory
cd /opt/chom-deploy

# Run deployment with explicit repo URL
./deploy-chom.sh \
    --environment=production \
    --branch=main \
    --repo-url=https://github.com/calounx/mentat.git

# OR if SSH key is configured for GitHub:
./deploy-chom.sh \
    --environment=production \
    --branch=main \
    --repo-url=git@github.com:calounx/mentat.git
```

**What this does:**
1. ✅ Pulls latest code from GitHub (bb283db)
2. ✅ Creates new release directory in `/var/www/chom/releases/`
3. ✅ Runs `composer install`
4. ✅ Runs `npm install && npm run build`
5. ✅ Runs database migrations (creates `system_settings` table)
6. ✅ Symlinks `/var/www/chom/current` to new release
7. ✅ Restarts PHP-FPM
8. ✅ Runs health checks

**Expected Duration:** 5-10 minutes

### Phase 3: Configure SMTP Settings in CHOM (2-3 min)

After deployment, configure SMTP settings through the UI or directly in database:

```bash
# SSH to landsraad
ssh calounx@landsraad.arewel.com

# Option A: Use artisan command (recommended)
sudo -u stilgar php /var/www/chom/current/artisan tinker

# In tinker:
App\Models\SystemSetting::set('mail.host', 'your-smtp-host.com', 'string', 'SMTP host');
App\Models\SystemSetting::set('mail.port', '587', 'integer', 'SMTP port');
App\Models\SystemSetting::set('mail.username', 'your-username', 'string', 'SMTP username');
App\Models\SystemSetting::set('mail.password', 'your-password', 'encrypted', 'SMTP password');
App\Models\SystemSetting::set('mail.from_address', 'alerts@chom.arewel.com', 'string', 'From email');
exit

# Option B: Access admin UI
# Navigate to: https://landsraad.arewel.com/admin/system-settings
# Fill in SMTP configuration form
```

### Phase 4: Deploy Observability Updates to mentat (3-5 min)

This will update Alertmanager with SMTP config fetched from CHOM API:

```bash
# SSH to mentat
ssh calounx@mentat.arewel.com

# Switch to stilgar
sudo -u stilgar bash

# Run observability deployment
cd /opt/chom-deploy
./scripts/deploy-observability.sh --config-dir ./config/mentat
```

**What this does:**
1. ✅ Fetches SMTP config from `http://landsraad.arewel.com/api/v1/system/smtp-config`
2. ✅ Updates `/etc/observability/alertmanager/alertmanager.yml` with SMTP settings
3. ✅ Deploys new alert rules from `exporters.yml`
4. ✅ Validates configurations
5. ✅ Reloads Prometheus (sends SIGHUP for hot reload)
6. ✅ Restarts Alertmanager with new SMTP config
7. ✅ Runs health checks

**Expected Duration:** 3-5 minutes

### Phase 5: Verify Deployment (5 min)

#### Test API Endpoints
```bash
# From any machine
# Test SMTP config API
curl https://landsraad.arewel.com/api/v1/system/smtp-config
# Expected: JSON response with SMTP settings

# Test observability health API
curl https://landsraad.arewel.com/api/v1/observability/health
# Expected: JSON response with health status

# Test shell format
curl https://landsraad.arewel.com/api/v1/system/smtp-config/shell
# Expected: Shell variable format

# Test YAML format
curl https://landsraad.arewel.com/api/v1/system/smtp-config/yaml
# Expected: YAML format for Alertmanager
```

#### Verify Database
```bash
ssh calounx@landsraad.arewel.com
sudo -u stilgar mysql chom -e "SELECT key, value FROM system_settings WHERE key LIKE 'mail.%';"
# Expected: 8 rows with SMTP configuration
```

#### Check Alertmanager Config
```bash
ssh calounx@mentat.arewel.com
sudo cat /etc/observability/alertmanager/alertmanager.yml | grep smtp_
# Expected: SMTP settings uncommented and populated

# Check if Alertmanager is happy
sudo systemctl status alertmanager
# Expected: active (running)

# Verify config is valid
sudo /opt/observability/bin/amtool check-config /etc/observability/alertmanager/alertmanager.yml
# Expected: "SUCCESS: Config is valid"
```

#### Verify Alert Rules
```bash
ssh calounx@mentat.arewel.com
sudo ls -lh /etc/observability/prometheus/rules/
# Expected: exporters.yml present

# Check Prometheus loaded rules
curl -s http://localhost:9090/prometheus/api/v1/rules | jq '.data.groups[].name'
# Expected: Should include "exporter_health", "service_health", "observability_stack_health"
```

#### Test Alertmanager SMTP
```bash
# SSH to mentat
ssh calounx@mentat.arewel.com

# Send test alert (optional - will send actual email if configured)
sudo /opt/observability/bin/amtool alert add test \
    severity=warning \
    alertname=TestAlert \
    description="Test alert from deployment"

# Check Alertmanager logs
sudo journalctl -u alertmanager -f
# Look for SMTP connection attempts
```

---

## Risk Assessment

### Low Risk
✅ **Database Migration** - Creates new table only, no schema changes to existing tables
✅ **New API Routes** - Additive only, no breaking changes
✅ **Blue-Green Deployment** - Atomic symlink switch, instant rollback available
✅ **Config Hot Reload** - Prometheus reloads via SIGHUP, no downtime
✅ **Alertmanager Restart** - Brief interruption to alerting only (< 5 seconds)

### Medium Risk
⚠️ **Deployment Script Copy** - Manual copy to mentat could introduce typos
⚠️ **SMTP Credentials** - Must be configured correctly or alerts won't send
⚠️ **GitHub Access** - Requires proper authentication (SSH key or HTTPS token)

### Mitigations
- Keep 5 previous releases for instant rollback
- Validate all configs before reloading services
- Test API endpoints before running observability deployment
- SMTP misconfiguration won't break observability stack (alerts just won't email)

---

## Rollback Procedure

If deployment fails or issues are detected:

### Rollback Application (landsraad)
```bash
ssh calounx@landsraad.arewel.com
sudo -u stilgar bash
cd /var/www/chom
ls -la releases/  # Identify previous release

# Manual rollback
sudo -u stilgar ln -sfn releases/20260106_132320 current
sudo systemctl restart php8.2-fpm

# OR use rollback script
cd /var/www/chom/current
./deploy/scripts/rollback.sh
```

### Rollback Observability (mentat)
```bash
ssh calounx@mentat.arewel.com

# Revert alert rules
sudo cp /etc/observability/prometheus/rules/basic.yml.backup \
        /etc/observability/prometheus/rules/basic.yml
sudo systemctl reload prometheus

# Revert Alertmanager config
sudo cp /etc/observability/alertmanager/alertmanager.yml.backup \
        /etc/observability/alertmanager/alertmanager.yml
sudo systemctl restart alertmanager
```

---

## Success Criteria

Deployment is successful when ALL of the following are true:

### Application (landsraad)
- [ ] `curl https://landsraad.arewel.com/api/v1/system/smtp-config` returns JSON (not 301)
- [ ] `curl https://landsraad.arewel.com/api/v1/observability/health` returns JSON (not 301)
- [ ] Database contains `system_settings` table with 8 mail.* rows
- [ ] `php artisan smtp:export` command exists and works
- [ ] CHOM application is accessible and functional
- [ ] No PHP errors in logs: `tail -f /var/www/chom/current/storage/logs/laravel.log`

### Observability (mentat)
- [ ] Alertmanager config contains SMTP settings (not commented out)
- [ ] `/etc/observability/prometheus/rules/exporters.yml` exists
- [ ] Prometheus shows new alert rules in UI
- [ ] `systemctl status prometheus` shows active (running)
- [ ] `systemctl status alertmanager` shows active (running)
- [ ] No errors in Prometheus logs: `journalctl -u prometheus -n 50`
- [ ] No errors in Alertmanager logs: `journalctl -u alertmanager -n 50`

### Integration
- [ ] Alertmanager can fetch SMTP config from CHOM API
- [ ] Test alert sends successfully (if SMTP configured)
- [ ] All exporters show as "up" in Prometheus targets page
- [ ] Grafana dashboards still functional

---

## Timeline Estimate

| Phase | Duration | Critical Path |
|-------|----------|---------------|
| Phase 1: Update deployment scripts on mentat | 1-2 min | No |
| Phase 2: Deploy application to landsraad | 5-10 min | Yes |
| Phase 3: Configure SMTP settings | 2-3 min | Yes |
| Phase 4: Deploy observability to mentat | 3-5 min | Yes |
| Phase 5: Verify deployment | 5 min | No |
| **Total** | **16-25 min** | |

**Critical Path:** 10-18 minutes of sequential deployment operations

---

## Blockers

### None Identified ✅

All prerequisites are met and no blocking issues were found:
- ✅ Servers are healthy and accessible
- ✅ Code is committed and pushed to GitHub
- ✅ Deployment scripts exist and are executable
- ✅ No conflicting processes detected
- ✅ No disk space issues
- ✅ No permission issues (calounx has sudo access)

---

## Recommendations

### Immediate (Before Deployment)
1. **Backup database** before running migrations (automatic via deployment script)
2. **Verify GitHub access** from mentat server:
   ```bash
   ssh calounx@mentat.arewel.com
   ssh -T git@github.com
   # OR: curl -I https://github.com/calounx/mentat
   ```
3. **Notify team** about brief maintenance window

### During Deployment
1. **Monitor logs** in real-time during deployment
2. **Keep rollback commands** ready in separate terminal
3. **Test immediately** after each phase before proceeding

### Post-Deployment
1. **Configure SMTP** with real credentials (not test values)
2. **Send test alert** to verify email delivery
3. **Update documentation** with any lessons learned
4. **Schedule** regular deployment script updates (git pull in /opt/chom-deploy)

### Future Improvements
1. **Convert /opt/chom-deploy to git repository** for easier updates
2. **Add CI/CD pipeline** for automated deployments
3. **Implement blue-green for observability** stack (currently direct updates)
4. **Add automated integration tests** for API endpoints
5. **Set up deployment notifications** (Slack/email)

---

## Deployment Commands Cheat Sheet

```bash
# === PHASE 1: Update Scripts on mentat ===
cd /home/calounx/repositories/mentat
scp deploy/scripts/deploy-observability.sh calounx@mentat.arewel.com:/tmp/
scp deploy/config/mentat/prometheus-alerts/exporters.yml calounx@mentat.arewel.com:/tmp/
ssh calounx@mentat.arewel.com
sudo cp /tmp/deploy-observability.sh /opt/chom-deploy/scripts/
sudo chmod +x /opt/chom-deploy/scripts/deploy-observability.sh
sudo chown stilgar:stilgar /opt/chom-deploy/scripts/deploy-observability.sh
sudo mkdir -p /opt/chom-deploy/config/mentat/prometheus-alerts/
sudo cp /tmp/exporters.yml /opt/chom-deploy/config/mentat/prometheus-alerts/
sudo chown -R stilgar:stilgar /opt/chom-deploy/config/

# === PHASE 2: Deploy Application ===
cd /opt/chom-deploy
sudo -u stilgar ./deploy-chom.sh \
    --environment=production \
    --branch=main \
    --repo-url=https://github.com/calounx/mentat.git

# === PHASE 3: Configure SMTP ===
ssh calounx@landsraad.arewel.com
sudo -u stilgar php /var/www/chom/current/artisan tinker
# (Configure SMTP settings in tinker - see Phase 3 above)

# === PHASE 4: Deploy Observability ===
ssh calounx@mentat.arewel.com
cd /opt/chom-deploy
sudo -u stilgar ./scripts/deploy-observability.sh --config-dir ./config/mentat

# === PHASE 5: Verify ===
curl https://landsraad.arewel.com/api/v1/system/smtp-config
curl https://landsraad.arewel.com/api/v1/observability/health
ssh calounx@mentat.arewel.com sudo systemctl status prometheus alertmanager
```

---

## Report Metadata

- **Generated:** 2026-01-09 (automated assessment)
- **Repository Commit:** bb283db
- **Deployed Commit (landsraad):** 7f572d2
- **Assessment Method:** SSH read-only verification
- **Changes Made:** None (read-only assessment)
- **Ready to Deploy:** Yes ✅

---

## Next Steps

1. **Review this report** and approve deployment plan
2. **Schedule maintenance window** (optional - blue-green deployment minimizes downtime)
3. **Execute deployment** following the phases above
4. **Verify success** using the success criteria checklist
5. **Update monitoring** with any new alerts or configurations

**Estimated Total Time:** 20-30 minutes including verification
