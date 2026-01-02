# CHOM Recovery Runbook

**Version:** 1.0
**Last Updated:** 2026-01-02
**Purpose:** Step-by-step recovery procedures for incident response

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Pre-Recovery Checklist](#pre-recovery-checklist)
3. [Recovery Procedures](#recovery-procedures)
4. [Post-Recovery Verification](#post-recovery-verification)
5. [Incident Communication](#incident-communication)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Incident Response Decision Tree

```
Is service down?
├─ YES → Check health-check.sh output
│   ├─ Database unreachable → [Section 3.1: Database Recovery]
│   ├─ Application errors → [Section 3.2: Application Recovery]
│   ├─ Nginx errors → [Section 3.3: Nginx Recovery]
│   └─ All services down → [Section 3.4: Full System Recovery]
│
└─ NO → But degraded performance
    ├─ High latency → [Section 3.5: Performance Recovery]
    ├─ Partial failures → [Section 3.6: Partial Service Recovery]
    └─ Data issues → [Section 3.7: Data Recovery]
```

### Emergency Contact Numbers

| Role | Contact | When to Call |
|------|---------|--------------|
| On-Call Engineer | PagerDuty Auto-page | Any incident |
| DevOps Lead | +33 X XX XX XX XX | Incident > 15 min |
| Engineering Manager | +33 X XX XX XX XX | Incident > 30 min |
| CTO | +33 X XX XX XX XX | Critical/Security incident |
| OVH Emergency Support | +33 9 72 10 10 07 | Infrastructure failure |

---

## Pre-Recovery Checklist

### Before Starting Recovery

Complete this checklist before executing recovery procedures:

- [ ] **Incident Identified:** Clear understanding of the problem
- [ ] **Impact Assessed:** Know which services/users affected
- [ ] **Stakeholders Notified:** Appropriate people informed
- [ ] **Backup Verified:** Latest backup exists and is accessible
- [ ] **Recovery Window:** Have appropriate time/access to recover
- [ ] **Rollback Plan:** Know how to undo recovery if it fails
- [ ] **Tools Ready:** SSH access, scripts available, credentials accessible
- [ ] **Documentation Open:** This runbook and DRP available
- [ ] **Monitoring Active:** Can observe recovery progress
- [ ] **Communication Channel:** Slack/email ready for updates

### Information to Gather

Before proceeding, collect:

```bash
# 1. Current system status
ssh deploy@51.77.150.96
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode full > /tmp/pre-recovery-status.txt

# 2. Recent logs
docker compose -f docker-compose.production.yml logs --tail=100 > /tmp/pre-recovery-logs.txt

# 3. Last known good state
./backup-chom.sh --status > /tmp/backup-status.txt

# 4. Error details
grep ERROR /opt/chom/storage/logs/laravel.log | tail -50 > /tmp/errors.txt

# 5. System metrics
docker stats --no-stream > /tmp/container-stats.txt
df -h > /tmp/disk-usage.txt
free -h > /tmp/memory-usage.txt
```

### Recovery Mode Activation

```bash
# 1. Enable maintenance mode (if application still partially working)
docker exec chom-app php artisan down --message="System maintenance in progress" --retry=60

# 2. Stop non-critical services to free resources
docker compose -f docker-compose.production.yml stop queue scheduler

# 3. Create pre-recovery snapshot (if time permits)
./backup-chom.sh --component database --tag pre-recovery-$(date +%Y%m%d-%H%M%S)

# 4. Log recovery start
echo "[$(date)] Recovery started by $(whoami) - Incident: <description>" >> /var/log/recovery.log
```

---

## Recovery Procedures

### 3.1 Database Recovery

**Scenario:** Database corruption, data loss, or database service failure
**RTO:** 30 minutes
**RPO:** 15 minutes

#### Symptoms
- MySQL container crashes repeatedly
- Database connection errors in application logs
- Data corruption errors
- Tables missing or corrupted

#### Step-by-Step Recovery

```bash
# STEP 1: Assess Database Status (5 minutes)
ssh deploy@51.77.150.96

# Check if MySQL is running
docker ps | grep chom-mysql

# If running, check logs
docker logs chom-mysql --tail=100 | grep -i error

# Test connection
docker exec chom-mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;"

# Check for corruption
docker exec chom-mysql mysqlcheck --all-databases --check

# STEP 2: Stop Application Services (2 minutes)
cd /opt/chom
docker compose -f docker-compose.production.yml stop app queue scheduler nginx

# Verify stopped
docker ps | grep chom

# STEP 3: Attempt Database Repair (5 minutes - if possible)
# Only if corruption is minor
docker exec chom-mysql mysqlcheck --all-databases --auto-repair

# Test if repair worked
docker exec chom-mysql mysql -e "SELECT 1;"

# If repair successful, skip to STEP 7

# STEP 4: Stop Database (1 minute)
docker compose -f docker-compose.production.yml stop mysql

# STEP 5: Backup Corrupted Database (3 minutes - for forensics)
# Create forensic copy
sudo tar czf /tmp/corrupted-mysql-$(date +%Y%m%d-%H%M%S).tar.gz \
  /var/lib/docker/volumes/mysql_data

# STEP 6: Restore Database from Backup (10 minutes)
cd /opt/chom/deploy/disaster-recovery/scripts

# List available backups
./restore-chom.sh --list --component database

# Restore latest backup
./restore-chom.sh --component database --latest

# Or restore specific backup
# ./restore-chom.sh --component database --timestamp 20260102-020000

# STEP 7: Start Database (2 minutes)
cd /opt/chom
docker compose -f docker-compose.production.yml start mysql

# Wait for database to be ready
echo "Waiting for database..."
until docker exec chom-mysql mysql -e "SELECT 1;" &> /dev/null; do
  echo -n "."
  sleep 2
done
echo " Database ready!"

# STEP 8: Verify Database Integrity (2 minutes)
# Check all databases
docker exec chom-mysql mysqlcheck --all-databases --check

# Verify table count
docker exec chom-mysql mysql -e "
  SELECT COUNT(*) AS table_count
  FROM information_schema.tables
  WHERE table_schema='chom';"

# Check recent data (adjust query for your schema)
docker exec chom-mysql mysql chom -e "
  SELECT COUNT(*) AS recent_rows
  FROM users
  WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY);"

# STEP 9: Start Application Services (2 minutes)
docker compose -f docker-compose.production.yml start app nginx queue scheduler

# STEP 10: Verify Application Functionality (3 minutes)
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode post-recovery

# Check application logs
docker logs chom-app --tail=50 | grep -i error

# Test key endpoints
curl -k https://localhost/health
curl -k https://localhost/api/status

# STEP 11: Disable Maintenance Mode (1 minute)
docker exec chom-app php artisan up

# STEP 12: Monitor for 15 Minutes
watch -n 30 './health-check.sh --mode monitoring'

# Check error rates in Grafana
# Check database metrics
# Monitor application logs
```

#### Validation Checklist

After database recovery:

- [ ] MySQL container running and healthy
- [ ] All expected databases present
- [ ] Table counts match expectations
- [ ] Recent data visible (check timestamps)
- [ ] Application can connect to database
- [ ] No corruption errors in logs
- [ ] Queries executing successfully
- [ ] Replication status OK (if applicable)

#### Rollback Plan

If recovery fails:

```bash
# 1. Stop MySQL
docker compose -f docker-compose.production.yml stop mysql

# 2. Try previous backup
./restore-chom.sh --component database --previous

# 3. Or restore to earlier point
./restore-chom.sh --component database --timestamp <earlier_time>

# 4. Escalate to DevOps Lead if multiple restore attempts fail
```

---

### 3.2 Application Recovery

**Scenario:** Application code corruption, configuration issues, deployment failure
**RTO:** 1 hour
**RPO:** 1 hour

#### Symptoms
- PHP fatal errors
- 500 Internal Server Error
- Missing files
- Permission errors
- Container fails to start

#### Step-by-Step Recovery

```bash
# STEP 1: Identify Problem Scope (5 minutes)
ssh deploy@51.77.150.96

# Check container status
docker ps -a | grep chom

# Check application logs
docker logs chom-app --tail=100 | grep -i "fatal\|error"

# Check for recent file changes
find /opt/chom -type f -mtime -1 -ls

# Check permissions
ls -la /opt/chom/storage/

# STEP 2: Enable Maintenance Mode (1 minute)
docker exec chom-app php artisan down --retry=60 || echo "Could not enable maintenance mode"

# STEP 3: Stop Application Containers (2 minutes)
cd /opt/chom
docker compose -f docker-compose.production.yml stop app queue scheduler nginx

# STEP 4: Backup Current State (5 minutes - for forensics)
sudo tar czf /tmp/chom-corrupted-$(date +%Y%m%d-%H%M%S).tar.gz \
  --exclude='vendor' \
  --exclude='node_modules' \
  /opt/chom

# Move to safe location
sudo mv /tmp/chom-corrupted-*.tar.gz /backups/forensics/

# STEP 5: Determine Recovery Method (2 minutes)
# Option A: Code corruption only → Restore application files
# Option B: Configuration issue → Restore config only
# Option C: Multiple issues → Full restore

# For code corruption (Option A):
cd /opt/chom/deploy/disaster-recovery/scripts
./restore-chom.sh --component application --latest

# For config issues (Option B):
./restore-chom.sh --component config --latest

# For full restore (Option C):
./restore-chom.sh --full --exclude database

# STEP 6: Fix Permissions (2 minutes)
cd /opt/chom
sudo chown -R deploy:deploy .
sudo chmod -R 755 .
sudo chmod -R 775 storage bootstrap/cache

# STEP 7: Verify .env File (1 minute)
# Check critical variables present
grep -E 'APP_KEY|DB_HOST|DB_DATABASE|DB_USERNAME|DB_PASSWORD' /opt/chom/.env

# STEP 8: Clear Caches (2 minutes)
# If app container can start
docker compose -f docker-compose.production.yml start app

docker exec chom-app php artisan config:clear
docker exec chom-app php artisan cache:clear
docker exec chom-app php artisan route:clear
docker exec chom-app php artisan view:clear

# STEP 9: Rebuild Containers (5 minutes - if needed)
# Only if application code changed
docker compose -f docker-compose.production.yml build --no-cache app queue scheduler

# STEP 10: Start All Services (3 minutes)
docker compose -f docker-compose.production.yml up -d

# Wait for services to be ready
sleep 10

# STEP 11: Run Health Checks (5 minutes)
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode post-recovery

# STEP 12: Test Key Functionality (10 minutes)
# Test homepage
curl -k https://localhost/ | grep -i "<!DOCTYPE html>"

# Test API
curl -k https://localhost/api/status

# Test database connection
docker exec chom-app php artisan migrate:status

# Test queue
docker exec chom-app php artisan queue:work --once

# STEP 13: Disable Maintenance Mode (1 minute)
docker exec chom-app php artisan up

# STEP 14: Monitor Application (15 minutes)
# Watch logs
docker logs chom-app -f

# Check error rates
tail -f /opt/chom/storage/logs/laravel.log | grep ERROR

# Monitor metrics in Grafana
```

#### Validation Checklist

- [ ] All containers running
- [ ] Application accessible via HTTPS
- [ ] No PHP errors in logs
- [ ] Database connection working
- [ ] User authentication working
- [ ] File uploads working
- [ ] Background jobs processing
- [ ] Scheduler running
- [ ] Metrics being collected

---

### 3.3 Nginx Recovery

**Scenario:** Web server failure, SSL issues, configuration errors
**RTO:** 15 minutes
**RPO:** N/A (stateless)

#### Step-by-Step Recovery

```bash
# STEP 1: Diagnose Issue (3 minutes)
docker logs chom-nginx --tail=100 | grep -i error

# Test config syntax
docker exec chom-nginx nginx -t

# STEP 2: Restore Configuration (5 minutes)
# If config error
cd /opt/chom/deploy/disaster-recovery/scripts
./restore-chom.sh --component config --latest

# STEP 3: Restart Nginx (2 minutes)
docker compose -f docker-compose.production.yml restart nginx

# STEP 4: Verify (5 minutes)
curl -k https://localhost/health
curl -I -k https://localhost/

# Check SSL certificate
echo | openssl s_client -connect localhost:443 2>&1 | grep -A 5 "Certificate chain"
```

---

### 3.4 Full System Recovery

**Scenario:** Complete VPS failure, data center outage, catastrophic failure
**RTO:** 4 hours
**RPO:** 1 hour

#### Step-by-Step Recovery

```bash
# STEP 1: Verify Scope of Failure (10 minutes)
# Try to SSH to server
ssh deploy@51.77.150.96

# If unreachable, check OVH status
# Visit: https://status.ovh.com/
# Check: https://www.ovh.com/manager/

# Verify mentat is accessible
ssh deploy@51.254.139.78
# Check if backups are available
ls -lh /backups/chom-remote/

# STEP 2: Provision New VPS (30 minutes - if needed)
# Via OVH Manager:
# - OS: Debian 13
# - vCPUs: 2+
# - RAM: 4GB+
# - Disk: 40GB+ SSD
# - Region: Same as before (or different if data center issue)
# - Public IP will be assigned

# Note new IP address
NEW_IP="51.77.XXX.XXX"

# STEP 3: Initial Server Setup (20 minutes)
ssh root@${NEW_IP}

# Update system
apt update && apt upgrade -y

# Install essential packages
apt install -y \
  git \
  curl \
  wget \
  vim \
  htop \
  ncdu \
  net-tools \
  ufw \
  fail2ban

# Install Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Create deploy user
useradd -m -s /bin/bash -G sudo,docker deploy
mkdir -p /home/deploy/.ssh

# Setup SSH key (copy from backup or create new)
# From mentat:
scp /backups/chom-remote/ssh/authorized_keys root@${NEW_IP}:/home/deploy/.ssh/
ssh root@${NEW_IP} chown -R deploy:deploy /home/deploy/.ssh
ssh root@${NEW_IP} chmod 700 /home/deploy/.ssh
ssh root@${NEW_IP} chmod 600 /home/deploy/.ssh/authorized_keys

# Configure firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# STEP 4: Restore Application (40 minutes)
# Switch to deploy user
su - deploy

# Clone repository
cd /opt
git clone https://github.com/your-org/chom.git
cd chom

# Or restore from backup if repository unavailable
# From mentat, copy latest backup
scp -r deploy@51.254.139.78:/backups/chom-remote/latest/* /tmp/

# Extract application
cd /opt
tar xzf /tmp/chom-app-latest.tar.gz

# STEP 5: Restore Configuration (10 minutes)
cd /opt/chom

# Restore .env
cp /tmp/backup/.env .env

# Restore Docker configs
cp -r /tmp/backup/docker/production/* docker/production/

# Update .env with new IP if needed
sed -i "s/51.77.150.96/${NEW_IP}/" .env

# STEP 6: Restore Database (30 minutes)
# Create data directory
mkdir -p /var/lib/mysql-restore

# Copy database backup from mentat
scp deploy@51.254.139.78:/backups/chom-remote/mysql/latest.sql.gz /tmp/

# Start minimal MySQL for restore
docker run -d \
  --name mysql-restore \
  -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
  -v /var/lib/mysql-restore:/var/lib/mysql \
  mysql:8.0

# Wait for MySQL
sleep 30

# Restore database
gunzip < /tmp/latest.sql.gz | docker exec -i mysql-restore mysql

# Stop temporary MySQL
docker stop mysql-restore
docker rm mysql-restore

# Move restored data to production volume
docker volume create mysql_data
# Copy data from /var/lib/mysql-restore to volume

# STEP 7: Restore SSL Certificates (10 minutes)
mkdir -p /opt/chom/docker/production/ssl

# Copy certificates from backup
scp -r deploy@51.254.139.78:/backups/chom-remote/ssl/* \
  /opt/chom/docker/production/ssl/

# Or regenerate with Let's Encrypt
# ./deploy/scripts/setup-ssl.sh

# STEP 8: Start Services (15 minutes)
cd /opt/chom

# Pull Docker images
docker compose -f docker-compose.production.yml pull

# Start all services
docker compose -f docker-compose.production.yml up -d

# Watch startup
docker compose -f docker-compose.production.yml logs -f

# STEP 9: Verify System (20 minutes)
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode full

# Test critical functionality
curl -k https://localhost/health
curl -k https://localhost/api/status

# Test database
docker exec chom-mysql mysql -e "SHOW DATABASES;"
docker exec chom-app php artisan migrate:status

# STEP 10: Update DNS (15 minutes - if IP changed)
# Update DNS A records for:
# - chom.yourdomain.com → ${NEW_IP}

# Verify DNS propagation
dig chom.yourdomain.com

# STEP 11: Update Monitoring (10 minutes)
# Update Prometheus targets on mentat
ssh deploy@51.254.139.78

# Edit prometheus.yml to update landsraad IP
# Reload Prometheus

# STEP 12: Final Verification (30 minutes)
# Test from external network
curl https://chom.yourdomain.com/health

# Monitor for errors
docker logs chom-app -f | grep -i error

# Check Grafana dashboards
# Verify metrics flowing
# Verify logs appearing in Loki

# STEP 13: Post-Recovery Actions
# - Document new IP address
# - Update documentation
# - Notify stakeholders
# - Schedule post-incident review
```

---

### 3.5 Performance Recovery

**Scenario:** High latency, resource exhaustion, slow queries
**RTO:** 30 minutes

#### Step-by-Step Recovery

```bash
# STEP 1: Identify Bottleneck (10 minutes)
# Check container resources
docker stats

# Check system resources
htop
free -h
df -h

# Check slow queries
docker exec chom-mysql mysql -e "SHOW PROCESSLIST;"
docker exec chom-mysql mysql -e "
  SELECT * FROM information_schema.processlist
  WHERE time > 10
  ORDER BY time DESC;"

# STEP 2: Immediate Mitigation (5 minutes)
# Clear application cache
docker exec chom-app php artisan cache:clear

# Restart queue workers (if backed up)
docker compose -f docker-compose.production.yml restart queue

# Kill slow queries (if needed)
docker exec chom-mysql mysql -e "KILL <query_id>;"

# STEP 3: Scale Resources (10 minutes - if needed)
# Increase worker processes
# Edit docker-compose.production.yml
# Increase PHP-FPM workers, queue workers, etc.

docker compose -f docker-compose.production.yml up -d --scale queue=3

# STEP 4: Optimize (5 minutes)
# Rebuild caches
docker exec chom-app php artisan config:cache
docker exec chom-app php artisan route:cache
docker exec chom-app php artisan view:cache

# Optimize database (if safe)
docker exec chom-mysql mysqlcheck --optimize --all-databases
```

---

### 3.6 Partial Service Recovery

**Scenario:** Single component failure while others work
**RTO:** 15 minutes

#### Queue Worker Failure

```bash
# Check queue status
docker logs chom-queue --tail=100

# Restart queue
docker compose -f docker-compose.production.yml restart queue

# Check queue depth
docker exec chom-app php artisan queue:work --once
```

#### Redis Failure

```bash
# Check Redis
docker exec chom-redis redis-cli ping

# Restart Redis
docker compose -f docker-compose.production.yml restart redis

# Verify data
docker exec chom-redis redis-cli info stats
```

#### Scheduler Failure

```bash
# Check scheduler logs
docker logs chom-scheduler --tail=100

# Restart scheduler
docker compose -f docker-compose.production.yml restart scheduler

# Manually run pending jobs
docker exec chom-app php artisan schedule:run
```

---

### 3.7 Data Recovery

**Scenario:** Accidental deletion, data corruption
**RTO:** 2 hours
**RPO:** Depends on backup frequency

#### Point-in-Time Recovery

```bash
# STEP 1: Identify Deletion Time (10 minutes)
# Check application logs
grep "deleted" /opt/chom/storage/logs/laravel.log

# Check audit logs
docker exec chom-mysql mysql chom -e "
  SELECT * FROM audit_log
  WHERE action='delete'
  ORDER BY created_at DESC
  LIMIT 10;"

# STEP 2: Find Appropriate Backup (5 minutes)
# List available backups
ls -ltr /backups/chom/mysql/incremental/

# Find backup before deletion
# Example: deletion at 14:30, use 14:15 backup

# STEP 3: Restore to Temporary Database (30 minutes)
# Create temp database
docker exec chom-mysql mysql -e "CREATE DATABASE restore_temp;"

# Restore backup to temp
gunzip < /backups/chom/mysql/incremental/backup-20260102-141500.sql.gz \
  | docker exec -i chom-mysql mysql restore_temp

# STEP 4: Extract Lost Data (15 minutes)
# Find deleted records
docker exec chom-mysql mysql restore_temp -e "
  SELECT * FROM users WHERE id IN (123, 456, 789);" > /tmp/recovered-users.sql

# Or export entire table
docker exec chom-mysql mysqldump restore_temp deleted_table > /tmp/recovered-table.sql

# STEP 5: Import to Production (10 minutes)
# Import recovered data
docker exec -i chom-mysql mysql chom < /tmp/recovered-table.sql

# Or specific records
docker exec -i chom-mysql mysql chom -e "
  INSERT INTO users SELECT * FROM restore_temp.users WHERE id IN (123, 456, 789);"

# STEP 6: Verify Recovery (10 minutes)
# Check data present
docker exec chom-mysql mysql chom -e "SELECT * FROM users WHERE id=123;"

# Test in application
curl -k https://localhost/api/users/123

# STEP 7: Cleanup (5 minutes)
# Drop temporary database
docker exec chom-mysql mysql -e "DROP DATABASE restore_temp;"

# Remove temp files
rm -f /tmp/recovered-*.sql
```

---

## Post-Recovery Verification

### Comprehensive Health Check

```bash
# Run full health check
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode full

# Expected output:
# ✓ All containers running
# ✓ Database accessible
# ✓ Application responding
# ✓ Nginx serving requests
# ✓ SSL certificate valid
# ✓ Metrics being collected
# ✓ Logs flowing to Loki
```

### Manual Verification Steps

#### 1. Service Availability

```bash
# Check all containers running
docker ps --filter "name=chom-" --format "table {{.Names}}\t{{.Status}}\t{{.Health}}"

# Test HTTP endpoints
curl -k https://localhost/health
curl -k https://localhost/api/status
curl -I -k https://localhost/

# Test from external network
curl https://chom.yourdomain.com/health
```

#### 2. Database Health

```bash
# Connection test
docker exec chom-mysql mysql -e "SELECT 1;"

# Check databases
docker exec chom-mysql mysql -e "SHOW DATABASES;"

# Verify data integrity
docker exec chom-mysql mysqlcheck --all-databases --check

# Check replication (if applicable)
docker exec chom-mysql mysql -e "SHOW SLAVE STATUS\G"
```

#### 3. Application Functionality

```bash
# Test user authentication
curl -X POST -k https://localhost/api/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'

# Test database queries
docker exec chom-app php artisan tinker --execute="User::count();"

# Run application tests
docker exec chom-app php artisan test --testsuite=Feature
```

#### 4. Queue and Scheduler

```bash
# Test queue processing
docker exec chom-app php artisan queue:work --once

# Test scheduler
docker exec chom-app php artisan schedule:run

# Check job status
docker exec chom-redis redis-cli llen queues:default
```

#### 5. Monitoring and Logging

```bash
# Check Prometheus targets
curl -s http://51.254.139.78:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'

# Verify metrics
curl -s http://localhost:9100/metrics | grep node_cpu

# Check logs in Loki
# Via Grafana or LogCLI
```

#### 6. SSL Certificates

```bash
# Check certificate expiry
echo | openssl s_client -connect chom.yourdomain.com:443 2>&1 | openssl x509 -noout -dates

# Verify certificate chain
echo | openssl s_client -connect chom.yourdomain.com:443 -showcerts
```

### Post-Recovery Checklist

Complete this checklist before closing incident:

- [ ] All services running and healthy
- [ ] Application accessible via HTTPS
- [ ] Database integrity verified
- [ ] No errors in application logs (last 15 min)
- [ ] Queue processing normally
- [ ] Scheduler jobs running
- [ ] Metrics flowing to Prometheus
- [ ] Logs appearing in Loki
- [ ] SSL certificates valid
- [ ] External accessibility confirmed
- [ ] DNS resolving correctly (if changed)
- [ ] Monitoring dashboards showing normal metrics
- [ ] No active alerts in Alertmanager
- [ ] Recent backup completed successfully
- [ ] Recovery documented in incident log

---

## Incident Communication

### Communication Templates

#### Initial Incident Notification

```
Subject: [INCIDENT] CHOM Service Disruption - Investigating

Team,

We are currently experiencing an incident affecting CHOM production.

Impact: [Describe user impact]
Started: [Time]
Current Status: Investigating
Estimated Resolution: [Time or "Under investigation"]

We are actively working on resolution and will provide updates every 15 minutes.

Next Update: [Time]

Incident Commander: [Name]
```

#### Status Update

```
Subject: [UPDATE] CHOM Service Disruption - In Progress

Update as of [Time]:

Current Status: [What we're doing]
Progress: [What's been done]
Next Steps: [What's planned]

Impact: [Current user impact]
Estimated Resolution: [Updated estimate]

Next Update: [Time]
```

#### Resolution Notification

```
Subject: [RESOLVED] CHOM Service Disruption - Service Restored

Team,

The CHOM service has been restored.

Incident Duration: [Start] to [End] ([Duration])
Root Cause: [Brief explanation]
Resolution: [What was done]

Impact Summary:
- Affected Users: [Number/Percentage]
- Data Loss: [None/Minimal/Description]
- Services Affected: [List]

Next Steps:
- Post-incident review scheduled for [Date/Time]
- Preventive measures to be implemented
- Documentation to be updated

Thank you for your patience.
```

### Communication Channels

| Audience | Channel | Frequency |
|----------|---------|-----------|
| Internal Team | Slack #ops-incidents | Real-time |
| Engineering | Email | Every 30 min |
| Management | Email + Phone | Every hour |
| Users | Status Page | Every 30 min |
| Stakeholders | Email | At start + resolution |

---

## Troubleshooting

### Common Issues During Recovery

#### Issue: Restore Script Fails

```bash
# Check script permissions
ls -l /opt/chom/deploy/disaster-recovery/scripts/restore-chom.sh

# Make executable
chmod +x /opt/chom/deploy/disaster-recovery/scripts/*.sh

# Check backup file exists
ls -lh /backups/chom/mysql/latest.sql.gz

# Verify backup integrity
gunzip -t /backups/chom/mysql/latest.sql.gz

# Run with debug output
bash -x /opt/chom/deploy/disaster-recovery/scripts/restore-chom.sh --latest
```

#### Issue: Database Restore Hangs

```bash
# Check available disk space
df -h

# Check MySQL processes
docker exec chom-mysql mysql -e "SHOW PROCESSLIST;"

# Increase timeouts
docker exec chom-mysql mysql -e "SET GLOBAL max_execution_time=0;"

# Try smaller batch restore
gunzip < backup.sql.gz | split -l 10000 - /tmp/restore-
for file in /tmp/restore-*; do
  docker exec -i chom-mysql mysql < $file
done
```

#### Issue: Containers Won't Start

```bash
# Check logs
docker compose -f docker-compose.production.yml logs

# Check disk space
df -h
docker system df

# Clean up if needed
docker system prune -f

# Check for port conflicts
netstat -tulpn | grep -E ':(80|443|3306|6379)'

# Restart Docker service
sudo systemctl restart docker
```

#### Issue: Permission Errors

```bash
# Fix ownership
sudo chown -R deploy:deploy /opt/chom

# Fix permissions
sudo chmod -R 755 /opt/chom
sudo chmod -R 775 /opt/chom/storage /opt/chom/bootstrap/cache

# Fix SELinux context (if applicable)
sudo chcon -R -t svirt_sandbox_file_t /opt/chom
```

#### Issue: Services Healthy But Application Errors

```bash
# Clear all caches
docker exec chom-app php artisan cache:clear
docker exec chom-app php artisan config:clear
docker exec chom-app php artisan route:clear
docker exec chom-app php artisan view:clear

# Regenerate app key (if lost)
docker exec chom-app php artisan key:generate

# Run migrations
docker exec chom-app php artisan migrate --force

# Rebuild optimized files
docker exec chom-app composer dump-autoload
docker exec chom-app php artisan config:cache
docker exec chom-app php artisan route:cache
```

### When to Escalate

Escalate to next level if:

- Recovery not progressing after 30 minutes
- Multiple recovery attempts failed
- Data loss greater than RPO
- RTO will be exceeded
- Unusual/undocumented situation
- Security implications
- Need additional resources/expertise

---

## Quick Reference Card

Print this section for quick access during incidents:

### Critical Commands

```bash
# Health Check
/opt/chom/deploy/disaster-recovery/scripts/health-check.sh --mode full

# List Backups
/opt/chom/deploy/disaster-recovery/scripts/backup-chom.sh --list

# Restore Database
/opt/chom/deploy/disaster-recovery/scripts/restore-chom.sh --component database --latest

# Restore Application
/opt/chom/deploy/disaster-recovery/scripts/restore-chom.sh --component application --latest

# Full Restore
/opt/chom/deploy/disaster-recovery/scripts/restore-chom.sh --full

# Maintenance Mode
docker exec chom-app php artisan down
docker exec chom-app php artisan up

# Restart Services
docker compose -f /opt/chom/docker-compose.production.yml restart

# View Logs
docker compose -f /opt/chom/docker-compose.production.yml logs -f
```

### Contact Info

- On-Call: PagerDuty Auto-page
- DevOps Lead: +33 X XX XX XX XX
- OVH Support: +33 9 72 10 10 07

### Key Files

- DRP: `/opt/chom/deploy/disaster-recovery/DISASTER_RECOVERY_PLAN.md`
- Backups: `/backups/chom/`
- Logs: `/opt/chom/storage/logs/`
- Config: `/opt/chom/.env`

---

**END OF RECOVERY RUNBOOK**
