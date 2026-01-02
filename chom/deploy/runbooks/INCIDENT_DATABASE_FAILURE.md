# Incident Runbook: Database Connection Failures

**Severity:** SEV1 (Critical)
**Component:** MariaDB/MySQL Database
**Impact:** Complete application outage
**Expected Resolution Time:** 15-30 minutes

---

## Detection

### Automated Alerts
- Prometheus alert: `DatabaseDown`
- Health check failure: `/health/ready` returns 503
- Application errors: "SQLSTATE[HY000] [2002]"
- Queue workers failing with database connection errors

### Manual Detection
- Users reporting "500 Internal Server Error"
- Application logs showing database connection timeouts
- Unable to access any dynamic content

---

## Triage (First 2 Minutes)

### Severity Assessment
**This is a SEV1 incident. Application is completely down.**

### Quick Checks
```bash
# 1. Check if database container is running
ssh deploy@landsraad.arewel.com "docker ps | grep mysql"

# 2. Check database health
ssh deploy@landsraad.arewel.com "docker exec chom-mysql mysqladmin ping"

# 3. Check connection from app container
ssh deploy@landsraad.arewel.com "docker exec chom-app php artisan tinker --execute='DB::connection()->getPdo();'"

# 4. Check recent database logs
ssh deploy@landsraad.arewel.com "docker logs chom-mysql --tail 50"
```

### Determine Root Cause Category
- [ ] Container stopped/crashed
- [ ] Database corrupted
- [ ] Out of connections
- [ ] Disk space full
- [ ] Configuration error
- [ ] Network issue
- [ ] Permission issue

---

## Resolution Procedures

### Scenario 1: Database Container Stopped

**Symptoms:** `docker ps` shows no mysql container

```bash
# 1. Check why container stopped
ssh deploy@landsraad.arewel.com "docker ps -a | grep mysql"
ssh deploy@landsraad.arewel.com "docker logs chom-mysql --tail 100"

# 2. Restart database container
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml start mysql
EOF

# 3. Wait for startup (30 seconds)
sleep 30

# 4. Verify database is accepting connections
ssh deploy@landsraad.arewel.com "docker exec chom-mysql mysqladmin ping"

# 5. Verify application can connect
curl -s https://landsraad.arewel.com/health/ready | jq '.checks.database'

# 6. If successful, restart queue workers
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart queue scheduler
EOF
```

**Expected Resolution Time:** 2-5 minutes

---

### Scenario 2: Database Corrupted

**Symptoms:** Database starts but queries fail with corruption errors

```bash
# 1. Check database status
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW ENGINE INNODB STATUS\G"
EOF

# 2. Attempt repair (if corruption is minor)
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysqlcheck -u root -p${MYSQL_ROOT_PASSWORD} --auto-repair --all-databases
EOF

# 3. If repair fails, RESTORE FROM BACKUP
# ⚠️  WARNING: This will lose data since last backup (up to 15 minutes)

# 3a. Stop application to prevent further writes
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml stop app queue scheduler
EOF

# 3b. Backup corrupted database for forensics
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysqldump --all-databases > /tmp/corrupted-$(date +%Y%m%d-%H%M%S).sql || true
EOF

# 3c. Restore from latest backup
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/backups/chom
./restore-chom.sh --component database --latest
EOF

# 3d. Verify database integrity
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysqlcheck -u root -p${MYSQL_ROOT_PASSWORD} --check --all-databases
EOF

# 3e. Restart application
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml start app queue scheduler
EOF

# 4. Verify functionality
curl -s https://landsraad.arewel.com/health/ready | jq '.'
```

**Expected Resolution Time:** 20-30 minutes (with data loss)

---

### Scenario 3: Out of Database Connections

**Symptoms:** "Too many connections" error in logs

```bash
# 1. Check current connections
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW PROCESSLIST;"
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Threads_connected';"
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW VARIABLES LIKE 'max_connections';"
EOF

# 2. Kill idle connections (temporary fix)
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
SELECT CONCAT('KILL ', id, ';')
FROM information_schema.processlist
WHERE command = 'Sleep'
AND time > 300;"
EOF

# 3. Restart PHP-FPM to clear connection pool
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart app
EOF

# 4. Monitor connections
watch -n 5 'ssh deploy@landsraad.arewel.com "docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"SHOW STATUS LIKE 'Threads_connected';\""'

# 5. If issue persists, increase max_connections (requires restart)
ssh deploy@landsraad.arewel.com << 'EOF'
# Edit /opt/chom/docker/mysql/custom.cnf
# Add: max_connections = 500
docker compose -f docker-compose.production.yml restart mysql
EOF
```

**Expected Resolution Time:** 5-10 minutes

---

### Scenario 4: Disk Space Full

**Symptoms:** "No space left on device" in database logs

```bash
# 1. Check disk usage
ssh deploy@landsraad.arewel.com "df -h"
ssh deploy@landsraad.arewel.com "du -sh /var/lib/docker/volumes/*"

# 2. EMERGENCY: Clear old logs
ssh deploy@landsraad.arewel.com << 'EOF'
# Clear Docker logs
docker system prune -f
journalctl --vacuum-time=3d

# Clear application logs older than 7 days
find /opt/chom/storage/logs -name "*.log" -mtime +7 -delete
EOF

# 3. Remove old database backups (keep last 7 days)
ssh deploy@landsraad.arewel.com << 'EOF'
find /opt/backups/chom -name "*.sql.gz" -mtime +7 -delete
EOF

# 4. Restart database
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart mysql
EOF

# 5. Verify database can write
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE TABLE test_write (id INT); DROP TABLE test_write;"
EOF

# 6. Restart application
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart app
EOF
```

**Expected Resolution Time:** 10-15 minutes

---

### Scenario 5: Configuration Error

**Symptoms:** Database starts but application can't connect (authentication failed)

```bash
# 1. Verify database credentials in .env
ssh deploy@landsraad.arewel.com "cat /opt/chom/.env | grep DB_"

# 2. Test connection with credentials from .env
ssh deploy@landsraad.arewel.com << 'EOF'
source /opt/chom/.env
docker exec chom-mysql mysql -u ${DB_USERNAME} -p${DB_PASSWORD} -e "SELECT 1;"
EOF

# 3. If credentials are wrong, reset database password
ssh deploy@landsraad.arewel.com << 'EOF'
NEW_PASSWORD=$(openssl rand -base64 32)
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  ALTER USER 'chom'@'%' IDENTIFIED BY '${NEW_PASSWORD}';
  FLUSH PRIVILEGES;
"

# Update .env file
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${NEW_PASSWORD}/" /opt/chom/.env
EOF

# 4. Restart application to pick up new password
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml restart app queue scheduler
EOF

# 5. Verify connection
curl -s https://landsraad.arewel.com/health/ready | jq '.checks.database'
```

**Expected Resolution Time:** 5-10 minutes

---

## Verification Steps

After resolution, verify all functionality:

```bash
# 1. Check database is running
ssh deploy@landsraad.arewel.com "docker ps | grep mysql"
# Expected: Container running, healthy status

# 2. Check health endpoints
curl -s https://landsraad.arewel.com/health/ready | jq '.checks.database'
# Expected: {"status": "ok"}

curl -s https://landsraad.arewel.com/health/dependencies | jq '.database'
# Expected: "connected": true, "latency_ms": < 100

# 3. Test database query
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-app php artisan tinker --execute="
  echo 'Users count: ' . \App\Models\User::count() . PHP_EOL;
"
EOF

# 4. Check connection pool
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Threads_connected';"
EOF
# Expected: < 80% of max_connections

# 5. Check for errors in last 5 minutes
ssh deploy@landsraad.arewel.com "docker logs chom-mysql --since 5m | grep -i error"
# Expected: No critical errors

# 6. Verify queue workers processing
ssh deploy@landsraad.arewel.com "docker exec chom-queue redis-cli LLEN queues:default"
# Expected: Queue depth decreasing

# 7. Monitor for 15 minutes
watch -n 30 'curl -s https://landsraad.arewel.com/health/ready | jq ".checks.database"'
```

---

## Post-Incident Actions

### Immediate (Within 1 Hour)

1. **Document Incident**
   ```bash
   # Create incident report
   cat > /tmp/incident-$(date +%Y%m%d-%H%M%S).md << EOF
   # Database Failure Incident Report

   **Date:** $(date)
   **Severity:** SEV1
   **Duration:** [START] - [END]
   **Root Cause:** [Brief description]
   **Data Loss:** [Yes/No - if yes, specify amount]
   **Resolution:** [What was done]

   ## Timeline
   - HH:MM - Alert triggered
   - HH:MM - On-call acknowledged
   - HH:MM - Root cause identified
   - HH:MM - Fix implemented
   - HH:MM - Service restored
   - HH:MM - Verification complete

   ## Impact
   - Users affected: [Estimate]
   - Transactions lost: [Number]
   - Revenue impact: [Estimate]

   ## Action Items
   - [ ] Update monitoring thresholds
   - [ ] Improve alerting
   - [ ] Document lessons learned
   EOF
   ```

2. **Notify Stakeholders**
   - Update #incidents Slack channel
   - Email engineering manager
   - Update status page (if public)

3. **Check Data Integrity**
   ```bash
   # Run full database integrity check
   ssh deploy@landsraad.arewel.com << 'EOF'
   docker exec chom-mysql mysqlcheck -u root -p${MYSQL_ROOT_PASSWORD} --check --all-databases > /tmp/integrity-check.txt
   EOF
   ```

### Short-term (Within 24 Hours)

1. **Root Cause Analysis**
   - Review all logs leading to incident
   - Identify preventable factors
   - Document contributing factors

2. **Monitoring Improvements**
   - Add alerts for specific failure mode
   - Adjust alert thresholds
   - Add predictive alerts

3. **Update Runbook**
   - Document any new procedures discovered
   - Update estimated resolution times
   - Add any missing scenarios

### Long-term (Within 1 Week)

1. **Preventive Measures**
   - Implement monitoring for root cause
   - Add automated recovery if possible
   - Schedule database maintenance window

2. **Post-Mortem Meeting**
   - Schedule within 48 hours of incident
   - Invite all involved parties
   - Use blameless post-mortem format

3. **Training**
   - Share incident learnings with team
   - Update on-call training materials
   - Practice recovery procedure

---

## Escalation

### Level 1: On-Call Engineer (0-5 minutes)
- Acknowledge alert
- Run triage procedures
- Attempt quick fixes (restart container)

### Level 2: Senior DevOps (5-15 minutes)
**Escalate if:**
- Quick fixes don't work
- Database corruption suspected
- Unsure of root cause

**Contact:**
- Slack: @devops-lead
- Phone: [ON-CALL-NUMBER]

### Level 3: Engineering Manager (15+ minutes)
**Escalate if:**
- Requires data restoration (potential data loss)
- Extended outage (> 30 minutes)
- Customer communication needed

**Contact:**
- Phone: [MANAGER-NUMBER]
- Email: engineering-manager@company.com

### Level 4: CTO (Critical)
**Escalate if:**
- Major data loss confirmed
- Extended outage (> 1 hour)
- Requires emergency budget approval

---

## Prevention Checklist

- [ ] Database backups running every 15 minutes
- [ ] Backup restoration tested monthly
- [ ] Monitoring alerts configured
- [ ] Connection pooling properly configured
- [ ] Disk space monitoring active
- [ ] Database maintenance scheduled
- [ ] Runbook tested and up-to-date
- [ ] On-call team trained

---

## Related Runbooks

- [High CPU/Memory Usage](INCIDENT_HIGH_RESOURCES.md)
- [Disk Space Exhaustion](INCIDENT_DISK_FULL.md)
- [Complete VPS Failure](INCIDENT_VPS_FAILURE.md)
- [Rollback Procedures](ROLLBACK_PROCEDURES.md)
- [Disaster Recovery Plan](../disaster-recovery/DISASTER_RECOVERY_PLAN.md)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-02
**Last Tested:** [DATE]
**Next Review:** 2026-02-02
