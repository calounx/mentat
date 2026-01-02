# CHOM Production Rollback Procedures

**Version:** 1.0.0
**Last Updated:** 2026-01-02
**Environment:** Production

---

## Table of Contents

1. [Overview](#1-overview)
2. [When to Rollback](#2-when-to-rollback)
3. [Rollback Decision Matrix](#3-rollback-decision-matrix)
4. [Emergency Rollback (< 5 minutes)](#4-emergency-rollback--5-minutes)
5. [Standard Rollback (< 15 minutes)](#5-standard-rollback--15-minutes)
6. [Database Rollback](#6-database-rollback)
7. [Rollback Verification](#7-rollback-verification)
8. [Post-Rollback Actions](#8-post-rollback-actions)
9. [Rollback Scenarios](#9-rollback-scenarios)

---

## 1. Overview

### 1.1 Purpose

This document provides detailed procedures for rolling back CHOM production deployments when issues are encountered that cannot be quickly resolved forward.

### 1.2 Rollback Philosophy

**Forward Fix vs Rollback:**
- **Forward Fix:** Preferred when issue is isolated and fix is quick (< 15 min)
- **Rollback:** Required when:
  - Issue impact is severe (SEV1/SEV2)
  - Root cause unknown
  - Fix time uncertain
  - User data at risk
  - Multiple systems affected

### 1.3 Rollback Types

| Type | Duration | Use Case | Risk Level |
|------|----------|----------|------------|
| Emergency | < 5 min | Critical outage, automated | High |
| Standard | < 15 min | Controlled rollback, manual | Medium |
| Database | < 30 min | Data corruption/loss | Very High |
| Full System | < 60 min | Complete environment recovery | Very High |

### 1.4 Key Principles

1. **Safety First:** Preserve user data above all else
2. **Communication:** Keep stakeholders informed at every step
3. **Documentation:** Log all actions taken
4. **Verification:** Always verify rollback success before declaring complete
5. **Learn:** Conduct post-mortem after every rollback

---

## 2. When to Rollback

### 2.1 Rollback Triggers (Automatic)

Automated rollback should be triggered when:

- **Application Completely Down**
  - Health checks failing for > 2 minutes
  - Error rate > 50% for > 1 minute
  - No successful requests for > 2 minutes

- **Critical Data Issues**
  - Database corruption detected
  - Data loss detected
  - Integrity constraint violations

- **Security Issues**
  - Security vulnerability exposed
  - Unauthorized access detected
  - Data breach suspected

### 2.2 Rollback Triggers (Manual)

Manual rollback should be considered when:

- **High Error Rates**
  - Error rate > 10% sustained for > 5 minutes
  - Critical functionality broken
  - Payment processing failing

- **Performance Degradation**
  - Response time > 5 seconds sustained
  - Database queries timing out
  - Queue jobs failing repeatedly

- **User Impact**
  - Multiple user reports of issues
  - Critical features unavailable
  - Incorrect data displayed to users

### 2.3 Do NOT Rollback When

- Minor cosmetic issues
- Single user reports (not reproducible)
- Issues affecting < 1% of users
- Issue has known workaround
- Fix is already in progress and nearly complete

---

## 3. Rollback Decision Matrix

### 3.1 Decision Tree

```
Issue Detected
    │
    ├─> Is application completely down?
    │   ├─> YES → EMERGENCY ROLLBACK (Section 4)
    │   └─> NO → Continue
    │
    ├─> Is data at risk?
    │   ├─> YES → DATABASE ROLLBACK (Section 6)
    │   └─> NO → Continue
    │
    ├─> Error rate > 10%?
    │   ├─> YES → STANDARD ROLLBACK (Section 5)
    │   └─> NO → Continue
    │
    ├─> Can fix be deployed in < 15 min?
    │   ├─> YES → Forward fix (deploy fix)
    │   └─> NO → STANDARD ROLLBACK (Section 5)
    │
    └─> Monitor and prepare for potential rollback
```

### 3.2 Severity-Based Decision

| Severity | Impact | Response | Rollback Decision |
|----------|--------|----------|-------------------|
| SEV1 | Complete outage | Immediate | **EMERGENCY ROLLBACK** |
| SEV2 | Major functionality impaired | < 5 min | **STANDARD ROLLBACK if fix > 15 min** |
| SEV3 | Minor functionality impaired | < 30 min | **Forward fix preferred** |
| SEV4 | No user impact | Next deploy | **No rollback needed** |

### 3.3 Stakeholder Approval

| Rollback Type | Approval Required | Approval Timeout |
|---------------|-------------------|------------------|
| Emergency | None (inform after) | N/A |
| Standard | On-call engineer | Immediate |
| Database | Engineering Manager | < 5 minutes |
| Full System | CTO | < 10 minutes |

**Emergency Override:** On-call engineer can execute any rollback if they determine user data is at risk.

---

## 4. Emergency Rollback (< 5 minutes)

**Use When:** Application is completely down, automated response required.

### 4.1 Automated Emergency Rollback

This should be automated via monitoring system (Alertmanager) if possible.

**Trigger Conditions:**
- Health check `/health/ready` failing for > 2 minutes
- Error rate > 50% for > 1 minute

**Automated Actions:**

```bash
#!/bin/bash
# /usr/local/bin/emergency-rollback.sh
# This script should be triggered by Alertmanager

set -euo pipefail

ROLLBACK_LOG="/var/log/chom/emergency-rollback-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ROLLBACK_LOG"
}

log "=========================================="
log "EMERGENCY ROLLBACK INITIATED"
log "=========================================="

# Send alert to team
curl -X POST https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"🚨 EMERGENCY ROLLBACK INITIATED - Application down\"}" || true

# 1. Enable maintenance mode (< 5 seconds)
log "Step 1: Enabling maintenance mode..."
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan down --render='errors::maintenance'" || true

# 2. Stop queue workers (< 5 seconds)
log "Step 2: Stopping queue workers..."
ssh deploy@landsraad.arewel.com "sudo systemctl stop chom-queue-*" || true

# 3. Switch to previous code version (< 30 seconds)
log "Step 3: Reverting code..."
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
PREVIOUS_VERSION=$(git describe --tags --abbrev=0 HEAD^)
sudo -u www-data git checkout "$PREVIOUS_VERSION" 2>&1
sudo -u www-data composer install --optimize-autoloader --no-dev 2>&1
EOF

# 4. Clear caches (< 10 seconds)
log "Step 4: Clearing caches..."
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan route:clear
sudo -u www-data php artisan view:clear
EOF

# 5. Restore application caches (< 10 seconds)
log "Step 5: Restoring caches..."
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
EOF

# 6. Restart PHP-FPM (< 5 seconds)
log "Step 6: Restarting PHP-FPM..."
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"

# 7. Start queue workers (< 5 seconds)
log "Step 7: Starting queue workers..."
ssh deploy@landsraad.arewel.com "sudo systemctl start chom-queue-*"

# 8. Verify health (< 10 seconds)
log "Step 8: Verifying health..."
sleep 5
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://landsraad.arewel.com/health/ready || echo "000")

if [ "$HEALTH_STATUS" = "200" ]; then
    log "Health check PASSED"

    # 9. Disable maintenance mode (< 5 seconds)
    log "Step 9: Disabling maintenance mode..."
    ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan up"

    log "=========================================="
    log "EMERGENCY ROLLBACK COMPLETED SUCCESSFULLY"
    log "=========================================="

    # Send success notification
    curl -X POST https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
        -H 'Content-Type: application/json' \
        -d "{\"text\":\"✅ EMERGENCY ROLLBACK COMPLETED - Application restored\"}"

    exit 0
else
    log "Health check FAILED - HTTP $HEALTH_STATUS"
    log "MANUAL INTERVENTION REQUIRED"

    # Send failure notification
    curl -X POST https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
        -H 'Content-Type: application/json' \
        -d "{\"text\":\"❌ EMERGENCY ROLLBACK FAILED - Manual intervention required\"}"

    exit 1
fi
```

### 4.2 Manual Emergency Rollback

If automation fails or is unavailable, execute manually:

```bash
# Execute from your control machine
cd /tmp/chom-deploy/chom/deploy/runbooks

# Run emergency rollback script
./emergency-rollback.sh

# OR execute steps manually:

# Step 1: Enable maintenance mode
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan down"

# Step 2: Stop queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl stop chom-queue-worker chom-queue-default chom-queue-emails chom-queue-notifications chom-queue-reports"

# Step 3: Revert code to previous version
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
PREVIOUS_VERSION=$(git describe --tags --abbrev=0 HEAD^)
sudo -u www-data git checkout "$PREVIOUS_VERSION"
sudo -u www-data composer install --optimize-autoloader --no-dev
EOF

# Step 4: Clear all caches
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan route:clear
sudo -u www-data php artisan view:clear
EOF

# Step 5: Restore production caches
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
EOF

# Step 6: Restart services
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"
ssh deploy@landsraad.arewel.com "sudo systemctl start chom-queue-worker chom-queue-default chom-queue-emails chom-queue-notifications chom-queue-reports"

# Step 7: Verify health
sleep 5
curl -s https://landsraad.arewel.com/health/ready | jq '.'

# Step 8: Disable maintenance mode (only if health check passes)
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan up"
```

### 4.3 Emergency Rollback Verification

```bash
# Verify services running
ssh deploy@landsraad.arewel.com << 'EOF'
sudo systemctl is-active nginx
sudo systemctl is-active php8.4-fpm
sudo systemctl is-active mysql
sudo systemctl is-active redis-server
sudo systemctl is-active chom-queue-worker
EOF

# Verify health endpoints
curl -s https://landsraad.arewel.com/health/ready | jq '.status'
# Expected: "ok"

curl -s https://landsraad.arewel.com/health/live | jq '.status'
# Expected: "ok"

# Verify no errors in logs
ssh deploy@landsraad.arewel.com "sudo tail -50 /var/www/chom/storage/logs/laravel.log | grep -i error"

# Test critical functionality
curl -s https://landsraad.arewel.com/login | grep -q "csrf" && echo "Login page: OK"
```

---

## 5. Standard Rollback (< 15 minutes)

**Use When:** Controlled rollback needed, manual intervention preferred.

### 5.1 Pre-Rollback Steps

```bash
# 1. Notify team
# Send message to #incidents Slack channel:
# "Starting standard rollback - [Brief description of issue]"

# 2. Document current state
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
echo "Current version:" > /tmp/rollback-info.txt
git describe --always >> /tmp/rollback-info.txt
echo "" >> /tmp/rollback-info.txt
echo "Current commit:" >> /tmp/rollback-info.txt
git log -1 >> /tmp/rollback-info.txt
EOF

# 3. Capture error logs
ssh deploy@landsraad.arewel.com "sudo tail -500 /var/www/chom/storage/logs/laravel.log > /tmp/error-logs-$(date +%Y%m%d-%H%M%S).log"

# 4. Identify rollback target
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
echo "Available versions:"
git tag -l --sort=-version:refname | head -10
EOF

# Choose rollback target (previous stable version)
ROLLBACK_TARGET="v1.2.3"  # Replace with actual version
```

### 5.2 Rollback Execution

```bash
# Step 1: Enable maintenance mode
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan down --message='System maintenance in progress' --retry=60"

# Step 2: Stop queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl stop chom-queue-*"

# Step 3: Create database backup (safety measure)
ssh deploy@landsraad.arewel.com << 'EOF'
BACKUP_FILE="/var/backups/chom/pre-rollback-$(date +%Y%m%d-%H%M%S).sql"
sudo mysqldump -u chom -p chom > "$BACKUP_FILE"
sudo gzip "$BACKUP_FILE"
echo "Database backed up to: ${BACKUP_FILE}.gz"
EOF

# Step 4: Checkout rollback version
ssh deploy@landsraad.arewel.com << EOF
cd /var/www/chom
sudo -u www-data git fetch --all --tags
sudo -u www-data git checkout tags/${ROLLBACK_TARGET}
EOF

# Step 5: Install dependencies
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data composer install --optimize-autoloader --no-dev
EOF

# Step 6: Check if migrations need to be rolled back
# WARNING: This is destructive! Only run if you know what you're doing.
# Most of the time, you should NOT rollback migrations.
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
echo "Current migration status:"
sudo -u www-data php artisan migrate:status
echo ""
echo "Do you need to rollback migrations? (y/N)"
EOF

# If migration rollback needed (RARE):
# ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan migrate:rollback --step=1"

# Step 7: Clear all caches
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan route:clear
sudo -u www-data php artisan view:clear
sudo -u www-data php artisan event:clear
EOF

# Step 8: Rebuild production caches
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
sudo -u www-data php artisan event:cache
EOF

# Step 9: Clear Redis cache (optional but recommended)
ssh deploy@landsraad.arewel.com "redis-cli -a YOUR_REDIS_PASSWORD FLUSHDB"

# Step 10: Restart PHP-FPM
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"

# Step 11: Start queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl start chom-queue-*"

# Step 12: Verify health
sleep 10
echo "Checking application health..."
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan health:check
EOF

curl -s https://landsraad.arewel.com/health/ready | jq '.'

# Step 13: Disable maintenance mode (only if health checks pass)
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan up"

# Step 14: Monitor for 5 minutes
echo "Rollback complete. Monitoring for 5 minutes..."
for i in {1..5}; do
    sleep 60
    echo "Minute $i: Checking health..."
    curl -s https://landsraad.arewel.com/health/ready | jq '.status'
done
```

### 5.3 Standard Rollback Checklist

Execute in order, checking off each item:

- [ ] Team notified in #incidents
- [ ] Current state documented
- [ ] Error logs captured
- [ ] Rollback target identified
- [ ] Maintenance mode enabled
- [ ] Queue workers stopped
- [ ] Database backup created
- [ ] Code reverted to target version
- [ ] Dependencies installed
- [ ] Migrations reviewed (rollback only if necessary)
- [ ] All caches cleared
- [ ] Production caches rebuilt
- [ ] Redis cache cleared
- [ ] PHP-FPM restarted
- [ ] Queue workers started
- [ ] Health checks passed
- [ ] Maintenance mode disabled
- [ ] Application monitored for 5 minutes
- [ ] No new errors detected
- [ ] Team notified of completion

---

## 6. Database Rollback

**WARNING:** Database rollbacks are extremely dangerous and should be a last resort.

**Use Only When:**
- Critical data corruption detected
- Irreversible data loss has occurred
- Database schema change broke application

**DO NOT Use When:**
- Data can be fixed with queries
- Only a few records affected
- Issue can be resolved forward

### 6.1 Database Rollback Decision Tree

```
Database Issue Detected
    │
    ├─> Is data corrupted beyond repair?
    │   ├─> NO → Fix with SQL queries (preferred)
    │   └─> YES → Continue
    │
    ├─> Can we restore only affected tables?
    │   ├─> YES → Selective table restore (Section 6.3)
    │   └─> NO → Continue
    │
    ├─> Is complete database restore required?
    │   ├─> YES → Full database rollback (Section 6.2)
    │   └─> UNCERTAIN → Escalate to DBA/CTO
```

### 6.2 Full Database Rollback

**WARNING: This will lose ALL data changes since backup!**

```bash
# Step 1: GET APPROVAL FROM CTO/ENGINEERING MANAGER
# DO NOT PROCEED WITHOUT APPROVAL

# Step 2: Put application in maintenance mode
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan down --message='Database maintenance in progress'"

# Step 3: Stop all services that write to database
ssh deploy@landsraad.arewel.com << 'EOF'
sudo systemctl stop chom-queue-*
sudo systemctl stop php8.4-fpm
EOF

# Step 4: Create current database dump (even if corrupted - for forensics)
ssh deploy@landsraad.arewel.com << 'EOF'
FORENSIC_BACKUP="/var/backups/chom/forensic-$(date +%Y%m%d-%H%M%S).sql"
sudo mysqldump -u chom -p --single-transaction --quick chom > "$FORENSIC_BACKUP" || true
sudo gzip "$FORENSIC_BACKUP"
echo "Forensic backup saved to: ${FORENSIC_BACKUP}.gz"
EOF

# Step 5: Identify backup to restore
ssh deploy@landsraad.arewel.com << 'EOF'
echo "Available backups:"
ls -lh /var/backups/chom/*.sql.gz | tail -10
EOF

# Choose backup file
BACKUP_FILE="/var/backups/chom/chom-20260102-030000.sql.gz"  # Replace with actual file

# Step 6: Verify backup integrity
ssh deploy@landsraad.arewel.com "gunzip -t $BACKUP_FILE && echo 'Backup file is valid' || echo 'ERROR: Backup file is corrupted!'"

# Step 7: Drop and recreate database
ssh deploy@landsraad.arewel.com << 'EOF'
mysql -u root -p << MYSQL
DROP DATABASE chom;
CREATE DATABASE chom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'localhost';
FLUSH PRIVILEGES;
MYSQL
EOF

# Step 8: Restore database from backup
ssh deploy@landsraad.arewel.com << EOF
gunzip -c $BACKUP_FILE | mysql -u chom -p chom
echo "Database restored from: $BACKUP_FILE"
EOF

# Step 9: Verify database integrity
ssh deploy@landsraad.arewel.com << 'EOF'
mysql -u chom -p chom -e "SHOW TABLES;"
mysql -u chom -p chom -e "SELECT COUNT(*) FROM users;"
mysql -u chom -p chom -e "SELECT COUNT(*) FROM sites;"
EOF

# Step 10: Run migrations (if needed)
# This should only be necessary if the backup is from an older schema version
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan migrate:status
# If migrations are pending:
# sudo -u www-data php artisan migrate --force
EOF

# Step 11: Clear application caches
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan config:cache
redis-cli -a YOUR_REDIS_PASSWORD FLUSHDB
EOF

# Step 12: Start services
ssh deploy@landsraad.arewel.com << 'EOF'
sudo systemctl start php8.4-fpm
sudo systemctl start chom-queue-*
EOF

# Step 13: Verify application health
sleep 10
curl -s https://landsraad.arewel.com/health/ready | jq '.'

# Step 14: Smoke test critical functionality
# - Login as test user
# - Verify user data intact
# - Verify site data intact
# - Test creating new records

# Step 15: Disable maintenance mode (only if verification passes)
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan up"

# Step 16: Notify team and stakeholders
# Include:
# - Data loss window (time between backup and rollback)
# - What data was lost
# - What data was preserved
# - Next steps for affected users
```

### 6.3 Selective Table Restore

If only specific tables are corrupted:

```bash
# Step 1: Identify affected tables
AFFECTED_TABLES="users sites"  # Replace with actual tables

# Step 2: Extract tables from backup
ssh deploy@landsraad.arewel.com << EOF
BACKUP_FILE="/var/backups/chom/chom-20260102-030000.sql.gz"
TEMP_DIR="/tmp/table-restore-\$(date +%Y%m%d-%H%M%S)"
mkdir -p "\$TEMP_DIR"

# Extract specific tables
for table in $AFFECTED_TABLES; do
    echo "Extracting table: \$table"
    gunzip -c "\$BACKUP_FILE" | sed -n "/-- Table structure for table \\\`\$table\\\`/,/-- Table structure for table/p" > "\$TEMP_DIR/\$table.sql"
done
EOF

# Step 3: Backup current tables (even if corrupted)
ssh deploy@landsraad.arewel.com << EOF
for table in $AFFECTED_TABLES; do
    echo "Backing up current table: \$table"
    mysqldump -u chom -p chom \$table > "\$TEMP_DIR/\$table-current.sql" || true
done
EOF

# Step 4: Drop and restore affected tables
ssh deploy@landsraad.arewel.com << EOF
for table in $AFFECTED_TABLES; do
    echo "Restoring table: \$table"
    mysql -u chom -p chom -e "DROP TABLE IF EXISTS \$table;"
    mysql -u chom -p chom < "\$TEMP_DIR/\$table.sql"
done
EOF

# Step 5: Verify restoration
ssh deploy@landsraad.arewel.com << EOF
for table in $AFFECTED_TABLES; do
    echo "Verifying table: \$table"
    mysql -u chom -p chom -e "SELECT COUNT(*) FROM \$table;"
done
EOF
```

---

## 7. Rollback Verification

### 7.1 Technical Verification

```bash
# Service health checks
ssh deploy@landsraad.arewel.com << 'EOF'
echo "=== Service Status ==="
for service in nginx php8.4-fpm mysql redis-server chom-queue-worker; do
    status=$(sudo systemctl is-active $service)
    echo "$service: $status"
done
EOF

# Application health checks
echo "=== Application Health ==="
curl -s https://landsraad.arewel.com/health/ready | jq '.'
curl -s https://landsraad.arewel.com/health/live | jq '.'
curl -s https://landsraad.arewel.com/health/basic | jq '.'

# Database connectivity
ssh deploy@landsraad.arewel.com "mysql -u chom -p -e 'SELECT 1;' && echo 'Database: OK'"

# Redis connectivity
ssh deploy@landsraad.arewel.com "redis-cli -a YOUR_REDIS_PASSWORD ping && echo 'Redis: OK'"

# Queue workers
ssh deploy@landsraad.arewel.com "ps aux | grep 'queue:work' | grep -v grep | wc -l"
echo "Expected queue workers: 5"

# Error log check
ssh deploy@landsraad.arewel.com "sudo tail -100 /var/www/chom/storage/logs/laravel.log | grep -i error | wc -l"
echo "Recent errors (should be 0 or very low)"
```

### 7.2 Functional Verification

Manual tests to perform:

1. **Homepage Access**
   - [ ] Homepage loads without errors
   - [ ] Static assets loading
   - [ ] No console errors in browser

2. **User Authentication**
   - [ ] Login page accessible
   - [ ] Can log in with test account
   - [ ] Session persists across pages
   - [ ] Can log out successfully

3. **Core Functionality**
   - [ ] Dashboard loads
   - [ ] Can view organizations
   - [ ] Can view sites
   - [ ] Data displays correctly

4. **Critical Workflows**
   - [ ] Can create new organization
   - [ ] Can create new site
   - [ ] Can edit existing records
   - [ ] Can delete records (soft delete)

5. **Background Jobs**
   - [ ] Queue workers processing jobs
   - [ ] Email delivery working
   - [ ] Scheduled tasks running

### 7.3 Performance Verification

```bash
# Response time test
echo "=== Response Time Test ==="
for i in {1..10}; do
    curl -o /dev/null -s -w "Request $i: %{time_total}s\n" https://landsraad.arewel.com
done

# Expected: All requests < 1 second

# Resource usage check
ssh deploy@landsraad.arewel.com << 'EOF'
echo "=== Resource Usage ==="
echo "CPU:"
top -bn1 | grep "Cpu(s)"
echo ""
echo "Memory:"
free -h
echo ""
echo "Disk:"
df -h /
EOF

# Expected:
# - CPU < 50% idle
# - Memory < 80% used
# - Disk < 80% used
```

### 7.4 Monitoring Verification

```bash
# Check Prometheus metrics
curl -s http://51.254.139.78:9090/api/v1/query?query=up{job="chom"} | jq '.data.result[0].value[1]'
# Expected: "1" (target is up)

# Check recent errors in Loki
# Access Grafana: https://mentat.arewel.com
# Run query: {job="chom"} |= "error" | __timestamp__ > now() - 5m
# Expected: No critical errors

# Verify alerting
curl -s http://51.254.139.78:9093/api/v1/alerts | jq '.data[] | select(.state=="firing")'
# Expected: No firing alerts
```

---

## 8. Post-Rollback Actions

### 8.1 Immediate Actions (< 30 minutes)

```bash
# 1. Update team in #incidents
# Message: "Rollback completed successfully. Application stable. Monitoring continues."

# 2. Notify stakeholders
# - Engineering Manager
# - Product Manager
# - Customer Support (if user-facing issues)

# 3. Document rollback
cat > /tmp/rollback-report-$(date +%Y%m%d-%H%M%S).md << 'EOF'
# Rollback Report

## Summary
- **Date/Time:** [YYYY-MM-DD HH:MM]
- **Type:** [Emergency/Standard/Database]
- **Executed By:** [Name]
- **Duration:** [X minutes]
- **Downtime:** [X minutes]

## Reason for Rollback
[Description of issue that triggered rollback]

## Actions Taken
1. [Action 1]
2. [Action 2]
...

## Rollback Target
- **Version:** [v1.2.3]
- **Commit:** [abc123]

## Data Impact
- **Data Loss:** [Yes/No]
- **Affected Records:** [Count or N/A]
- **Time Window:** [Start - End or N/A]

## Verification Results
- [ ] All services healthy
- [ ] Application functional
- [ ] Performance normal
- [ ] No errors in logs

## Next Steps
1. [Next step 1]
2. [Next step 2]
...
EOF

# 4. Update status page (if applicable)
# Mark incident as resolved

# 5. Continue monitoring
# Watch metrics, logs, and error rates for next 4 hours
```

### 8.2 Short-term Actions (< 24 hours)

- [ ] **Root Cause Analysis**
  - Review error logs
  - Identify what caused the issue
  - Document findings

- [ ] **Fix Development**
  - Create fix for the issue
  - Test fix in staging environment
  - Code review for fix

- [ ] **Communication**
  - Update stakeholders on root cause
  - Provide timeline for fix deployment
  - Update customers if they were affected

- [ ] **Documentation**
  - Update runbook with lessons learned
  - Document any gaps in rollback procedure
  - Update monitoring/alerting if needed

### 8.3 Long-term Actions (< 1 week)

- [ ] **Post-Mortem**
  - Schedule post-mortem meeting (within 48 hours)
  - Invite all relevant stakeholders
  - Use blameless post-mortem format

- [ ] **Process Improvements**
  - Identify preventable aspects
  - Update deployment procedures
  - Improve testing processes
  - Enhance monitoring/alerting

- [ ] **Fix Deployment**
  - Deploy fix to production
  - Verify fix resolves issue
  - Monitor for recurrence

- [ ] **Training**
  - Share learnings with team
  - Update training materials
  - Practice rollback procedures

---

## 9. Rollback Scenarios

### 9.1 Scenario: Bad Migration

**Symptom:** Database errors after migration, application won't start.

**Rollback Steps:**

```bash
# 1. Identify problematic migration
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan migrate:status"

# 2. Rollback specific migration
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan migrate:rollback --step=1"

# 3. Verify database state
ssh deploy@landsraad.arewel.com "mysql -u chom -p chom -e 'SHOW TABLES;'"

# 4. Restart application
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"

# 5. Verify
curl -s https://landsraad.arewel.com/health/ready | jq '.'
```

### 9.2 Scenario: Memory Leak

**Symptom:** PHP-FPM consuming excessive memory, application slowing down.

**Rollback Steps:**

```bash
# 1. Identify current memory usage
ssh deploy@landsraad.arewel.com "ps aux --sort=-%mem | grep php-fpm | head -10"

# 2. Emergency: Restart PHP-FPM (temporary fix)
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"

# 3. If issue persists: Full application rollback
# Follow Standard Rollback procedure (Section 5)

# 4. Monitor memory usage
watch -n 5 'ssh deploy@landsraad.arewel.com "free -h"'
```

### 9.3 Scenario: Queue Job Failures

**Symptom:** Queue jobs failing repeatedly, backlog growing.

**Rollback Steps:**

```bash
# 1. Stop queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl stop chom-queue-*"

# 2. Check queue depth
ssh deploy@landsraad.arewel.com "redis-cli -a YOUR_REDIS_PASSWORD LLEN queues:default"

# 3. Inspect failed jobs
ssh deploy@landsraad.arewel.com "mysql -u chom -p chom -e 'SELECT * FROM failed_jobs ORDER BY failed_at DESC LIMIT 10;'"

# 4. Clear failed jobs queue (if needed)
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan queue:flush"

# 5. Rollback application code
# Follow Standard Rollback procedure (Section 5)

# 6. Restart queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl start chom-queue-*"

# 7. Monitor queue processing
watch -n 5 'ssh deploy@landsraad.arewel.com "redis-cli -a YOUR_REDIS_PASSWORD LLEN queues:default"'
```

### 9.4 Scenario: Third-Party API Failure

**Symptom:** External API (Stripe, Brevo) integration broken, payment/email failures.

**Decision:** This may NOT require rollback if:
- Error handling is working correctly
- Failed operations are queued for retry
- User experience is acceptable (error messages shown)

**If Rollback Needed:**

```bash
# 1. Check API integration status
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data php artisan tinker --execute="
    // Test Stripe
    try {
        \Stripe\Stripe::setApiKey(config('services.stripe.secret'));
        \Stripe\Balance::retrieve();
        echo 'Stripe: OK\n';
    } catch (\Exception $e) {
        echo 'Stripe: FAILED - ' . $e->getMessage() . '\n';
    }
"
EOF

# 2. If integration code is broken: Rollback
# Follow Standard Rollback procedure (Section 5)

# 3. If API itself is down: Wait for API recovery
# No rollback needed - monitor and notify users
```

### 9.5 Scenario: Configuration Error

**Symptom:** Wrong configuration value deployed, application behaving incorrectly.

**Rollback Steps:**

```bash
# 1. Identify configuration issue
ssh deploy@landsraad.arewel.com "cd /var/www/chom && grep -i ERROR_SETTING .env"

# 2. Fix configuration (quick fix - no code rollback needed)
ssh deploy@landsraad.arewel.com << 'EOF'
cd /var/www/chom
sudo -u www-data sed -i 's/WRONG_VALUE/CORRECT_VALUE/' .env
EOF

# 3. Clear config cache
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan config:clear"

# 4. Rebuild config cache
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan config:cache"

# 5. Restart PHP-FPM
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"

# 6. Verify
curl -s https://landsraad.arewel.com/health/ready | jq '.'
```

---

## Rollback Checklist Summary

### Pre-Rollback

- [ ] Issue severity assessed
- [ ] Rollback decision made
- [ ] Team notified
- [ ] Stakeholders informed
- [ ] Current state documented
- [ ] Error logs captured
- [ ] Rollback target identified

### During Rollback

- [ ] Maintenance mode enabled
- [ ] Services stopped
- [ ] Backup created (if needed)
- [ ] Code/database reverted
- [ ] Caches cleared
- [ ] Services restarted
- [ ] Health checks performed

### Post-Rollback

- [ ] All services healthy
- [ ] Application functional
- [ ] Performance normal
- [ ] No errors in logs
- [ ] Monitoring verified
- [ ] Maintenance mode disabled
- [ ] Team notified
- [ ] Stakeholders updated

### Follow-Up

- [ ] Rollback documented
- [ ] Root cause identified
- [ ] Fix developed and tested
- [ ] Post-mortem scheduled
- [ ] Process improvements identified
- [ ] Runbook updated

---

## Emergency Contacts

| Role | Name | Phone | Email | Escalation Level |
|------|------|-------|-------|------------------|
| On-Call Engineer | TBD | TBD | TBD | 1st |
| Backup Engineer | TBD | TBD | TBD | 2nd |
| Engineering Manager | TBD | TBD | TBD | 3rd |
| CTO | TBD | TBD | TBD | Final |

**Communication Channels:**
- Slack: #incidents (real-time updates)
- Email: ops@arewel.com (formal notifications)
- Phone: For SEV1 incidents only

---

## Document Control

**Version:** 1.0.0
**Created:** 2026-01-02
**Last Updated:** 2026-01-02
**Next Review:** 2026-02-02

**Approval:**
- [ ] Infrastructure Lead: _________________ Date: _______
- [ ] Application Lead: _________________ Date: _______
- [ ] Operations Manager: _________________ Date: _______

---

**END OF ROLLBACK PROCEDURES**
