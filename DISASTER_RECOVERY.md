# Disaster Recovery Runbook

## Table of Contents

- [Overview](#overview)
- [Recovery Objectives](#recovery-objectives)
- [Emergency Contacts](#emergency-contacts)
- [Disaster Scenarios](#disaster-scenarios)
  - [1. VPS Complete Failure](#1-vps-complete-failure)
  - [2. Database Corruption](#2-database-corruption)
  - [3. Application Data Loss](#3-application-data-loss)
  - [4. Observability Stack Failure](#4-observability-stack-failure)
  - [5. Network/DNS Issues](#5-networkdns-issues)
  - [6. Security Breach](#6-security-breach)
- [Recovery Procedures](#recovery-procedures)
- [Backup Locations](#backup-locations)
- [Testing Schedule](#testing-schedule)

---

## Overview

This runbook provides step-by-step procedures for recovering from various disaster scenarios affecting the mentat infrastructure.

**Infrastructure:**
- **mentat.arewel.com** (10.10.100.10): Observability VPS (Prometheus, Grafana, Loki, Tempo)
- **landsraad.arewel.com** (10.10.100.20): CHOM Application VPS (Laravel, MySQL, Redis)

**Backup Strategy:**
- **Local backups**: Stored on same VPS (7-day retention)
- **Offsite backups**: S3-compatible storage (30-day retention)
- **Configuration backups**: Daily encrypted snapshots
- **Database backups**: Automated before deployments + daily scheduled backups

---

## Recovery Objectives

| Service | RTO (Recovery Time) | RPO (Recovery Point) | Priority |
|---------|---------------------|---------------------|----------|
| CHOM Application | 2 hours | 1 hour | Critical |
| MySQL Database | 1 hour | 15 minutes | Critical |
| Observability Stack | 4 hours | 24 hours | High |
| Static Assets | 30 minutes | 24 hours | Medium |

**Definitions:**
- **RTO**: Maximum acceptable downtime
- **RPO**: Maximum acceptable data loss

---

## Emergency Contacts

| Role | Name | Contact | Responsibilities |
|------|------|---------|------------------|
| Primary DBA | - | - | Database recovery |
| DevOps Lead | - | - | Infrastructure recovery |
| Security Lead | - | - | Security incidents |
| Product Owner | - | - | Business continuity |

**Escalation Path:**
1. DevOps Engineer (1 hour)
2. DevOps Lead (2 hours)
3. CTO (4 hours)

---

## Disaster Scenarios

### 1. VPS Complete Failure

**Symptoms:**
- VPS unresponsive to SSH/ping
- All services down
- No access via provider console

**Impact:** Complete service outage

**Recovery Procedure:**

#### Step 1: Assess the Situation (5 minutes)

```bash
# Verify VPS is truly down
ping landsraad.arewel.com
ssh root@landsraad.arewel.com

# Check provider status page
# Check monitoring dashboards (if accessible)
```

#### Step 2: Provision New VPS (15 minutes)

```bash
# Option A: Restore from VPS snapshot (if available)
# - Log into hosting provider dashboard
# - Create new VPS from latest snapshot
# - Update DNS records

# Option B: Provision fresh VPS
# Minimum requirements:
# - Debian 12 or Ubuntu 22.04
# - 4GB RAM, 2 vCPUs
# - 80GB SSD
# - Public IP address
```

#### Step 3: Install Base System (20 minutes)

```bash
# SSH into new VPS
ssh root@<NEW_VPS_IP>

# Update system
apt-get update && apt-get upgrade -y

# Install Docker and Docker Compose
curl -fsSL https://get.docker.com | sh
apt-get install -y docker-compose-plugin

# Install essential tools
apt-get install -y git curl wget gnupg unzip
```

#### Step 4: Restore Application Code (10 minutes)

```bash
# Clone repository
cd /opt
git clone https://github.com/yourusername/mentat.git
cd mentat

# Checkout production branch
git checkout main
```

#### Step 5: Restore Configuration Files (10 minutes)

```bash
# Download encrypted config backup from S3
aws s3 cp s3://your-backup-bucket/config/latest/config_*.tar.gz.gpg /tmp/

# Decrypt configuration backup
gpg --decrypt /tmp/config_*.tar.gz.gpg > /tmp/config.tar.gz

# Extract configurations
cd /opt/mentat
tar -xzf /tmp/config.tar.gz

# Verify critical files
ls -la .env chom/.env docker-compose.production.yml
```

#### Step 6: Restore Database (30 minutes)

```bash
# Download latest encrypted database backup
aws s3 cp s3://your-backup-bucket/mysql/$(date +%Y-%m-%d)/backup_*.sql.gpg /tmp/

# Decrypt database backup
gpg --decrypt /tmp/backup_*.sql.gpg > /tmp/backup.sql

# Start MySQL container
cd /opt/mentat/chom
docker compose -f docker-compose.production.yml up -d mysql

# Wait for MySQL to be ready
docker exec chom-mysql mysqladmin ping -h localhost --wait=30

# Restore database
docker exec -i chom-mysql mysql -u root -p$(cat docker/production/secrets/mysql_root_password) chom < /tmp/backup.sql

# Verify restoration
docker exec chom-mysql mysql -u root -p$(cat docker/production/secrets/mysql_root_password) -e "SELECT COUNT(*) FROM users" chom
```

#### Step 7: Restore Docker Volumes (20 minutes)

```bash
# Download volume backups
aws s3 cp s3://your-backup-bucket/volumes/$(date +%Y-%m-%d)/chom_backup_*.tar.gz.gpg /tmp/

# Decrypt volume backup
gpg --decrypt /tmp/chom_backup_*.tar.gz.gpg > /tmp/volumes.tar.gz

# Stop containers
docker compose -f docker-compose.production.yml down

# Restore volumes
cd /tmp
tar -xzf volumes.tar.gz

# Import volumes
for volume_file in *.tar.gz; do
    volume_name=$(basename "$volume_file" .tar.gz)
    docker run --rm \
        -v "docker_${volume_name}:/data" \
        -v "/tmp:/backup" \
        debian:12-slim \
        tar xzf "/backup/${volume_file}" -C /data
done
```

#### Step 8: Start Application Services (10 minutes)

```bash
cd /opt/mentat/chom
docker compose -f docker-compose.production.yml up -d

# Verify all services are running
docker compose -f docker-compose.production.yml ps

# Check logs for errors
docker compose -f docker-compose.production.yml logs --tail=50
```

#### Step 9: Update DNS Records (5 minutes)

```bash
# Update A records to point to new VPS IP
# If using Cloudflare/DNS provider API:
curl -X PUT "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records/RECORD_ID" \
     -H "Authorization: Bearer YOUR_API_TOKEN" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"landsraad.arewel.com","content":"NEW_VPS_IP","ttl":120}'

# DNS propagation can take up to 24 hours
# Use low TTL (120s) for faster propagation
```

#### Step 10: Verify Recovery (15 minutes)

```bash
# Test application health
curl -f https://landsraad.arewel.com/health

# Verify database connectivity
docker exec chom-app php artisan tinker --execute="DB::connection()->getPdo();"

# Check Redis connectivity
docker exec chom-redis redis-cli ping

# Run application tests
docker exec chom-app php artisan test

# Verify monitoring integration
curl http://landsraad.arewel.com:9100/metrics
```

**Total Recovery Time:** ~2 hours

**Post-Recovery Actions:**
1. Document incident in incident log
2. Notify stakeholders of recovery
3. Schedule post-mortem review
4. Update runbook based on lessons learned
5. Review and improve backup procedures

---

### 2. Database Corruption

**Symptoms:**
- MySQL crashes repeatedly
- Table corruption errors in logs
- Data inconsistency issues
- Failed transactions

**Impact:** Application unable to read/write data

**Recovery Procedure:**

#### Step 1: Assess Corruption Severity (5 minutes)

```bash
# Check MySQL error logs
docker logs chom-mysql | grep -i "corrupt\|crash\|error"

# Connect to MySQL
docker exec -it chom-mysql mysql -u root -p

# Check table status
CHECK TABLE users;
CHECK TABLE subscriptions;
CHECK TABLE invoices;
```

#### Step 2: Enable Maintenance Mode (1 minute)

```bash
cd /opt/mentat/chom
docker exec chom-app php artisan down --retry=60
```

#### Step 3: Attempt Automatic Repair (10 minutes)

```bash
# Try MySQL repair utilities
docker exec chom-mysql mysqlcheck -u root -p --auto-repair --all-databases

# If InnoDB corruption:
docker exec -it chom-mysql mysql -u root -p -e "SET GLOBAL innodb_force_recovery = 1;"
docker restart chom-mysql

# Check if repair succeeded
docker exec -it chom-mysql mysql -u root -p -e "CHECK TABLE users;"
```

#### Step 4: Restore from Backup (if repair fails) (30 minutes)

```bash
# Create backup of current corrupted state (for analysis)
docker exec chom-mysql mysqldump -u root -p --all-databases > /tmp/corrupted_backup.sql

# Download latest good backup
aws s3 cp s3://your-backup-bucket/mysql/$(date +%Y-%m-%d)/backup_*.sql.gpg /tmp/

# If today's backup is also corrupted, use previous day
aws s3 cp s3://your-backup-bucket/mysql/$(date -d "1 day ago" +%Y-%m-%d)/backup_*.sql.gpg /tmp/

# Decrypt backup
gpg --decrypt /tmp/backup_*.sql.gpg > /tmp/restore.sql

# Stop application
docker compose -f docker-compose.production.yml stop app queue scheduler

# Drop and recreate database
docker exec -i chom-mysql mysql -u root -p <<EOF
DROP DATABASE chom;
CREATE DATABASE chom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'%';
FLUSH PRIVILEGES;
EOF

# Restore backup
docker exec -i chom-mysql mysql -u root -p chom < /tmp/restore.sql

# Verify restoration
docker exec chom-mysql mysql -u root -p -e "SELECT COUNT(*) FROM users" chom
```

#### Step 5: Apply Missing Transactions (if possible) (15 minutes)

```bash
# If binary logs available, replay transactions since backup
docker exec chom-mysql mysqlbinlog /var/lib/mysql/mysql-bin.000001 \
    --start-datetime="2024-01-01 00:00:00" \
    | docker exec -i chom-mysql mysql -u root -p chom

# Run migrations to ensure schema is current
docker exec chom-app php artisan migrate --force
```

#### Step 6: Verify Data Integrity (10 minutes)

```bash
# Run application verification
docker exec chom-app php artisan app:verify-data-integrity

# Check critical tables
docker exec chom-mysql mysql -u root -p -e "
SELECT
    'users' as table_name, COUNT(*) as count FROM users
UNION ALL
SELECT 'subscriptions', COUNT(*) FROM subscriptions
UNION ALL
SELECT 'invoices', COUNT(*) FROM invoices;
" chom

# Verify foreign key constraints
docker exec chom-mysql mysqlcheck -u root -p --check-foreign-keys chom
```

#### Step 7: Bring Application Online (5 minutes)

```bash
# Clear application cache
docker exec chom-app php artisan cache:clear

# Start all services
docker compose -f docker-compose.production.yml start

# Disable maintenance mode
docker exec chom-app php artisan up

# Monitor logs
docker compose -f docker-compose.production.yml logs -f
```

**Total Recovery Time:** ~1 hour (with backup restore)

**Data Loss:** Up to last backup (15 minutes with frequent backups)

---

### 3. Application Data Loss

**Symptoms:**
- Storage volumes missing/corrupted
- User uploads disappeared
- Application state lost

**Impact:** Loss of user-generated content, session data

**Recovery Procedure:**

#### Step 1: Identify Lost Data (10 minutes)

```bash
# Check Docker volumes
docker volume ls

# Inspect volume contents
docker run --rm -v docker_app-storage:/data debian:12-slim ls -lah /data

# Check Redis data
docker exec chom-redis redis-cli INFO persistence
docker exec chom-redis redis-cli LASTSAVE
```

#### Step 2: Download Volume Backups (15 minutes)

```bash
# List available backups
aws s3 ls s3://your-backup-bucket/volumes/ --recursive

# Download latest volume backup
aws s3 cp s3://your-backup-bucket/volumes/$(date +%Y-%m-%d)/chom_backup_*.tar.gz.gpg /tmp/

# If today's backup missing, try previous days
for i in {1..7}; do
    DATE=$(date -d "$i days ago" +%Y-%m-%d)
    aws s3 ls s3://your-backup-bucket/volumes/$DATE/ && break
done
```

#### Step 3: Restore Volumes (20 minutes)

```bash
# Stop application (data consistency)
docker compose -f docker-compose.production.yml stop app queue scheduler

# Decrypt backup
gpg --decrypt /tmp/chom_backup_*.tar.gz.gpg > /tmp/volumes.tar.gz

# Extract individual volume backups
mkdir -p /tmp/volume-restore
cd /tmp/volume-restore
tar -xzf /tmp/volumes.tar.gz

# Restore each volume
for volume in app-storage redis-data; do
    echo "Restoring $volume..."
    docker run --rm \
        -v "docker_${volume}:/data" \
        -v "/tmp/volume-restore:/backup" \
        debian:12-slim \
        bash -c "rm -rf /data/* && tar xzf /backup/${volume}.tar.gz -C /data"
done

# Verify restoration
docker run --rm -v docker_app-storage:/data debian:12-slim ls -lah /data
```

#### Step 4: Restart Application (5 minutes)

```bash
# Start services
docker compose -f docker-compose.production.yml start

# Verify application functionality
curl https://landsraad.arewel.com/health

# Check logs
docker logs chom-app --tail=100
```

**Total Recovery Time:** ~50 minutes

---

### 4. Observability Stack Failure

**Symptoms:**
- Grafana dashboard inaccessible
- No metrics/logs being collected
- Prometheus/Loki down

**Impact:** Loss of monitoring visibility (application still running)

**Recovery Procedure:**

#### Step 1: Quick Diagnostics (5 minutes)

```bash
# Check service status
ssh root@mentat.arewel.com
systemctl status prometheus grafana-server loki

# Check Docker containers (if containerized)
docker ps -a | grep -E "prometheus|grafana|loki|tempo"

# Check disk space (common issue)
df -h
```

#### Step 2: Restart Services (10 minutes)

```bash
# If using systemd
systemctl restart prometheus
systemctl restart grafana-server
systemctl restart loki

# If using Docker
cd /opt/observability-stack
docker compose restart

# Verify services are running
curl http://localhost:9090/-/healthy  # Prometheus
curl http://localhost:3000/api/health # Grafana
curl http://localhost:3100/ready      # Loki
```

#### Step 3: Restore Configurations (if needed) (15 minutes)

```bash
# Download config backup
aws s3 cp s3://your-backup-bucket/config/latest/observability_config_*.tar.gz.gpg /tmp/

# Decrypt and extract
gpg --decrypt /tmp/observability_config_*.tar.gz.gpg | tar -xz -C /opt/observability-stack

# Reload configurations
systemctl reload prometheus
curl -X POST http://localhost:3000/api/admin/provisioning/dashboards/reload
```

#### Step 4: Restore Historical Data (optional) (30 minutes)

```bash
# Download Prometheus TSDB backup
aws s3 sync s3://your-backup-bucket/prometheus-tsdb/latest/ /var/lib/prometheus/

# Download Loki chunks
aws s3 sync s3://your-backup-bucket/loki-data/latest/ /var/lib/loki/

# Restart services to load data
systemctl restart prometheus loki
```

**Total Recovery Time:** 15-60 minutes (depending on data restore)

**Note:** Observability stack failure doesn't affect application availability.

---

### 5. Network/DNS Issues

**Symptoms:**
- Domain not resolving
- SSL certificate errors
- Unable to reach services via domain

**Impact:** Service inaccessible via domain (may be reachable via IP)

**Recovery Procedure:**

#### Step 1: Diagnose Issue (5 minutes)

```bash
# Test DNS resolution
dig landsraad.arewel.com
nslookup landsraad.arewel.com

# Test direct IP access
curl http://<VPS_IP>

# Check SSL certificate
openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com
```

#### Step 2: Fix DNS Records (10 minutes)

```bash
# Verify current DNS settings
dig landsraad.arewel.com +short

# Update DNS via provider API or dashboard
# Ensure A record points to correct IP
# Ensure AAAA record (IPv6) if applicable
# Check CNAME records for subdomains

# Reduce TTL for faster propagation
# Wait for DNS propagation (can take up to 24 hours)
```

#### Step 3: Renew SSL Certificate (if expired) (10 minutes)

```bash
# Check certificate expiry
echo | openssl s_client -servername landsraad.arewel.com -connect landsraad.arewel.com:443 2>/dev/null | openssl x509 -noout -dates

# Renew Let's Encrypt certificate
certbot renew --force-renewal

# Or with Docker
docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    -p 80:80 \
    certbot/certbot renew --force-renewal

# Restart web server
systemctl reload nginx
# or
docker restart chom-nginx
```

#### Step 4: Verify Resolution (5 minutes)

```bash
# Test from multiple locations
curl -I https://landsraad.arewel.com

# Use online DNS checkers
# - https://dnschecker.org
# - https://www.whatsmydns.net

# Verify SSL
curl -vI https://landsraad.arewel.com
```

**Total Recovery Time:** 30 minutes + DNS propagation

---

### 6. Security Breach

**Symptoms:**
- Unauthorized access detected
- Malware/backdoor found
- Data exfiltration suspected
- Compromised credentials

**Impact:** Potential data breach, service compromise

**Recovery Procedure:**

#### Step 1: Immediate Containment (5 minutes)

```bash
# STOP - Do not delete anything yet (preserve evidence)

# Enable maintenance mode
docker exec chom-app php artisan down

# Block all incoming traffic (except your IP)
iptables -A INPUT -s YOUR_IP -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -j DROP

# Isolate affected services
docker network disconnect chom-network chom-app
```

#### Step 2: Assess Breach Scope (30 minutes)

```bash
# Check for unauthorized users
cat /etc/passwd
last -f /var/log/wtmp
lastlog

# Check for suspicious processes
ps auxf
lsof -i

# Check for backdoors
find / -name "*.php" -mtime -7 -ls
find /var/www -name "*.php" -exec grep -l "eval\|base64_decode\|system\|exec" {} \;

# Check SSH authorized_keys
cat /root/.ssh/authorized_keys
cat /home/*/.ssh/authorized_keys

# Check for modified system files
debsums -c

# Review logs for suspicious activity
grep -i "failed\|unauthorized\|invalid" /var/log/auth.log
docker logs chom-app | grep -E "POST|PUT|DELETE" | grep -v "200 OK"
```

#### Step 3: Preserve Evidence (15 minutes)

```bash
# Create forensic backup
INCIDENT_ID="incident-$(date +%Y%m%d-%H%M%S)"
mkdir -p /tmp/$INCIDENT_ID

# Copy logs
cp -r /var/log /tmp/$INCIDENT_ID/
docker logs chom-app > /tmp/$INCIDENT_ID/app.log
docker logs chom-nginx > /tmp/$INCIDENT_ID/nginx.log

# Dump current database state
docker exec chom-mysql mysqldump -u root -p --all-databases > /tmp/$INCIDENT_ID/database.sql

# Create memory dump (if needed)
dd if=/dev/mem of=/tmp/$INCIDENT_ID/memory.dump bs=1M

# Upload evidence to secure location
tar -czf /tmp/$INCIDENT_ID.tar.gz -C /tmp $INCIDENT_ID
aws s3 cp /tmp/$INCIDENT_ID.tar.gz s3://security-incidents/$INCIDENT_ID.tar.gz
```

#### Step 4: Eradicate Threat (30 minutes)

```bash
# Change all passwords immediately
docker exec -i chom-mysql mysql -u root -p <<EOF
UPDATE users SET password = NULL WHERE email = 'compromised@email.com';
EOF

# Revoke API keys/tokens
# Rotate database credentials
# Regenerate application keys

# Remove backdoors/malware
rm -f /path/to/backdoor.php

# Update and patch system
apt-get update && apt-get upgrade -y

# Update Docker images
docker compose -f docker-compose.production.yml pull
```

#### Step 5: Recovery (varies)

```bash
# Option A: Clean recovery from backup (RECOMMENDED)
# Follow "VPS Complete Failure" procedure
# This ensures no persistence mechanisms remain

# Option B: In-place recovery (risky)
# Only if breach scope is fully understood
# Rebuild containers from clean images
docker compose -f docker-compose.production.yml down
docker system prune -a --volumes
docker compose -f docker-compose.production.yml up -d
```

#### Step 6: Strengthen Security (60 minutes)

```bash
# Enable fail2ban
apt-get install fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Configure firewall (UFW)
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# Set up intrusion detection
apt-get install aide
aideinit
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Enable audit logging
apt-get install auditd
systemctl enable auditd
systemctl start auditd

# Implement MFA for SSH
# Install Google Authenticator
apt-get install libpam-google-authenticator
google-authenticator

# Update sshd_config
sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

#### Step 7: Monitoring and Verification (ongoing)

```bash
# Set up continuous monitoring
# Add alerting for:
# - Failed login attempts
# - File modifications
# - Unusual network traffic
# - Privilege escalations

# Schedule regular security scans
crontab -e
# Add: 0 2 * * * aide --check

# Monitor in real-time
tail -f /var/log/auth.log
docker logs -f chom-app
```

**Total Recovery Time:** 2-4 hours (depending on breach severity)

**Post-Incident Actions:**
1. File incident report
2. Notify affected users (if data breach)
3. Conduct thorough post-mortem
4. Review and update security policies
5. Implement lessons learned
6. Consider third-party security audit

---

## Recovery Procedures

### Point-in-Time Recovery (PITR)

For recovering to a specific point in time:

```bash
# Restore database to specific timestamp
# 1. Find backup before target time
aws s3 ls s3://your-backup-bucket/mysql/ --recursive | grep "backup_"

# 2. Restore that backup (as in Database Corruption procedure)

# 3. Apply binary logs up to target time
docker exec chom-mysql mysqlbinlog \
    --start-datetime="2024-01-01 00:00:00" \
    --stop-datetime="2024-01-01 12:34:56" \
    /var/lib/mysql/mysql-bin.* \
    | docker exec -i chom-mysql mysql -u root -p chom
```

### Cross-Region Failover

If primary region is unavailable:

```bash
# 1. Provision VPS in secondary region
# 2. Restore from replicated S3 bucket
aws s3 sync s3://backup-bucket-replica/latest/ /tmp/restore/

# 3. Follow normal recovery procedures
# 4. Update DNS to point to new region
# 5. Update monitoring endpoints
```

---

## Backup Locations

### Local Backups (On-VPS)

| Data Type | Location | Retention |
|-----------|----------|-----------|
| MySQL | `/opt/mentat/chom/storage/app/backups/` | 7 days |
| Docker Volumes | `/opt/mentat/docker/backups/` | 7 days |
| Observability | `/var/lib/observability-backups/` | 7 days |
| Logs | `/var/log/` | 30 days |

### Offsite Backups (S3)

| Data Type | S3 Prefix | Retention | Encryption |
|-----------|-----------|-----------|------------|
| MySQL Dumps | `mysql/YYYY-MM-DD/` | 30 days | GPG |
| Docker Volumes | `volumes/YYYY-MM-DD/` | 30 days | GPG |
| Configurations | `config/YYYY-MM-DD/` | 90 days | GPG |
| Prometheus TSDB | `prometheus-tsdb/YYYY-MM-DD/` | 30 days | GPG |
| Loki Data | `loki-data/YYYY-MM-DD/` | 30 days | GPG |

### Backup Verification

All backups are automatically verified after upload:
- File integrity checks (MD5/SHA256)
- Size verification
- Decryption test (encrypted backups)
- Restore test (monthly)

---

## Testing Schedule

### Regular DR Tests

| Test Type | Frequency | Owner | Duration |
|-----------|-----------|-------|----------|
| Backup Verification | Daily | Automated | 10 min |
| Database Restore Test | Weekly | DevOps | 30 min |
| Full Volume Restore | Monthly | DevOps | 2 hours |
| Complete DR Drill | Quarterly | All Teams | 4 hours |
| Tabletop Exercise | Quarterly | Leadership | 2 hours |

### Monthly DR Drill Checklist

```bash
# Month: ___________  Tester: ___________

# 1. Backup Verification
[ ] Local backups present and recent
[ ] Offsite backups uploading successfully
[ ] Encryption working correctly
[ ] Backup sizes reasonable

# 2. Restore Test
[ ] Download random backup from S3
[ ] Decrypt backup successfully
[ ] Restore to test environment
[ ] Verify data integrity
[ ] Application functions correctly

# 3. Documentation
[ ] Runbook still accurate
[ ] Contact information current
[ ] Credentials accessible
[ ] Recovery procedures updated

# 4. Results
Pass/Fail: ___________
Issues Found: ___________
Time to Restore: ___________
Notes: ___________
```

### Quarterly Full DR Drill

**Scenario:** Complete VPS failure simulation

**Objectives:**
1. Provision new VPS in under 20 minutes
2. Restore application from offsite backups
3. Achieve RTO targets
4. Verify data integrity
5. Update documentation

**Procedure:**
1. Schedule maintenance window
2. Provision clean test VPS
3. Follow complete recovery runbook
4. Time each step
5. Document issues/improvements
6. Hold post-drill review
7. Update runbook

---

## Appendix A: Recovery Scripts

### Quick Recovery Script

```bash
#!/bin/bash
# Quick recovery automation script
# Usage: ./quick-recovery.sh [scenario]

SCENARIO=${1:-full}

case $SCENARIO in
    "full")
        echo "Full system recovery..."
        # Implement full recovery automation
        ;;
    "database")
        echo "Database recovery..."
        # Implement database recovery
        ;;
    "volumes")
        echo "Volume recovery..."
        # Implement volume recovery
        ;;
    *)
        echo "Usage: $0 {full|database|volumes}"
        exit 1
        ;;
esac
```

### Backup Verification Script

See `/scripts/disaster-recovery/verify-backups.sh`

---

## Appendix B: Recovery Checklists

### Pre-Recovery Checklist

- [ ] Incident documented
- [ ] Stakeholders notified
- [ ] Maintenance mode enabled
- [ ] Evidence preserved (if security incident)
- [ ] Recovery team assembled
- [ ] Recovery plan reviewed
- [ ] Required credentials accessible
- [ ] Backup availability confirmed

### Post-Recovery Checklist

- [ ] All services operational
- [ ] Data integrity verified
- [ ] Monitoring restored
- [ ] DNS updated (if needed)
- [ ] SSL certificates valid
- [ ] Performance benchmarks met
- [ ] Stakeholders notified
- [ ] Incident report filed
- [ ] Post-mortem scheduled
- [ ] Runbook updated

---

## Document Information

- **Version:** 1.0
- **Last Updated:** 2026-01-02
- **Next Review:** 2026-04-02
- **Owner:** DevOps Team
- **Classification:** Internal Use Only

**Change Log:**

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-01-02 | 1.0 | System | Initial version |

---

**Remember:** This runbook is a living document. After every incident or DR drill, update it with lessons learned!
