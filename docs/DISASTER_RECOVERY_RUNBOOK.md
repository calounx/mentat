# Disaster Recovery Runbook - CHOM Production

## Table of Contents
1. [Overview](#overview)
2. [Recovery Time Objectives](#recovery-time-objectives)
3. [Backup Strategy](#backup-strategy)
4. [Incident Response Procedures](#incident-response-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Testing & Validation](#testing--validation)

---

## Overview

This runbook provides step-by-step procedures for recovering CHOM production infrastructure from various disaster scenarios.

### Infrastructure Components
- **mentat.arewel.com** (51.254.139.78): Observability Stack
- **landsraad.arewel.com** (51.77.150.96): CHOM Application

### Critical Data
- MySQL database (customer data, configurations)
- User-uploaded files (storage/app)
- Application configuration (.env, SSL certificates)
- Observability data (metrics, logs, traces)

---

## Recovery Time Objectives

| Component | RTO | RPO | Priority |
|-----------|-----|-----|----------|
| Application Database | 1 hour | 15 minutes | P0 |
| Application Server | 2 hours | 1 hour | P0 |
| User Files | 2 hours | 1 hour | P1 |
| Observability Stack | 4 hours | 24 hours | P2 |
| Historical Metrics | 8 hours | 7 days | P3 |

**Definitions:**
- RTO (Recovery Time Objective): Maximum acceptable downtime
- RPO (Recovery Point Objective): Maximum acceptable data loss
- P0: Critical, P1: High, P2: Medium, P3: Low

---

## Backup Strategy

### Automated Backups

#### 1. Database Backups
**Frequency:** Every 6 hours + before each deployment
**Location:**
- Local: `/var/backups/chom/database/`
- Offsite: S3-compatible storage (OVH Object Storage)

**Retention:**
- Hourly: 48 hours
- Daily: 30 days
- Weekly: 90 days
- Monthly: 1 year

**Verification:** Automated restore test weekly

#### 2. Application Files
**Frequency:** Daily at 02:00 UTC
**Location:**
- Local: `/var/backups/chom/files/`
- Offsite: S3-compatible storage

**Retention:**
- Daily: 14 days
- Weekly: 90 days

#### 3. Configuration Backups
**Frequency:** After each change + daily
**Location:** Git repository + encrypted S3 bucket

**Components:**
- .env files (encrypted)
- Nginx configurations
- SSL certificates
- Supervisor configs
- Cron jobs

#### 4. Observability Data
**Frequency:** Daily snapshots
**Location:** Local volumes + S3

**Retention:**
- Raw metrics: 30 days local, 90 days S3
- Aggregated metrics: 1 year
- Logs: 30 days local, 90 days S3

---

## Incident Response Procedures

### Severity Levels

**SEV-1 (Critical):** Complete service outage
- Response time: Immediate
- Escalation: All hands on deck
- Communication: Every 30 minutes

**SEV-2 (High):** Partial service degradation
- Response time: Within 15 minutes
- Escalation: On-call engineer + backup
- Communication: Every hour

**SEV-3 (Medium):** Non-critical component failure
- Response time: Within 1 hour
- Escalation: On-call engineer
- Communication: Status page update

### Incident Response Steps

1. **Detection & Alert**
   - Prometheus alerts trigger PagerDuty
   - Health check failures
   - User reports

2. **Initial Assessment** (5 minutes)
   ```bash
   # Quick health check
   ssh ops@landsraad.arewel.com "sudo systemctl status nginx php8.2-fpm mysql redis"

   # Check disk space
   ssh ops@landsraad.arewel.com "df -h"

   # Check application logs
   ssh ops@landsraad.arewel.com "tail -100 /var/www/chom/storage/logs/laravel.log"

   # Check system logs
   ssh ops@landsraad.arewel.com "sudo journalctl -u nginx -u php8.2-fpm --since '10 min ago'"
   ```

3. **Incident Declaration**
   - Create incident channel in Slack: `#incident-YYYYMMDD-NNN`
   - Update status page
   - Start incident log

4. **Triage & Mitigation**
   - Identify root cause
   - Implement immediate mitigation
   - Document all actions

5. **Recovery**
   - Follow specific recovery procedure (see below)
   - Verify service restoration
   - Monitor for stability

6. **Post-Incident**
   - Write post-mortem
   - Implement preventive measures
   - Update runbook

---

## Recovery Procedures

### Scenario 1: Database Corruption/Loss

**Symptoms:**
- MySQL errors in logs
- Data inconsistencies
- Query failures

**Recovery Steps:**

1. **Stop Application** (prevent further corruption)
   ```bash
   ssh ops@landsraad.arewel.com
   sudo -i

   # Enable maintenance mode
   cd /var/www/chom
   sudo -u www-data php artisan down --retry=60

   # Stop services
   systemctl stop php8.2-fpm nginx
   ```

2. **Identify Latest Good Backup**
   ```bash
   # List available backups
   ls -lht /var/backups/chom/database/

   # Or from S3
   aws s3 ls s3://chom-backups/database/ --recursive | sort -r
   ```

3. **Restore Database**
   ```bash
   # Stop MySQL
   systemctl stop mysql

   # Backup current (corrupted) state
   mv /var/lib/mysql /var/lib/mysql.corrupted.$(date +%Y%m%d_%H%M%S)

   # Initialize new data directory
   mysql_install_db --user=mysql --datadir=/var/lib/mysql

   # Start MySQL
   systemctl start mysql

   # Restore from backup (choose appropriate backup file)
   BACKUP_FILE="/var/backups/chom/database/db_backup_20260102_120000.sql"
   mysql -u root -p chom < "$BACKUP_FILE"

   # Or restore from S3
   aws s3 cp s3://chom-backups/database/db_backup_20260102_120000.sql.gz - | \
     gunzip | mysql -u root -p chom
   ```

4. **Verify Database**
   ```bash
   # Check database integrity
   mysqlcheck -u root -p --all-databases --check --auto-repair

   # Verify tables
   mysql -u root -p -e "USE chom; SHOW TABLES; SELECT COUNT(*) FROM users;"

   # Run application health check
   cd /var/www/chom
   sudo -u www-data php artisan db:show
   sudo -u www-data php artisan migrate:status
   ```

5. **Restart Services**
   ```bash
   systemctl start php8.2-fpm nginx

   # Disable maintenance mode
   sudo -u www-data php artisan up

   # Restart queue workers
   sudo -u www-data php artisan queue:restart
   ```

6. **Verification**
   ```bash
   # Run smoke tests
   curl -f https://landsraad.arewel.com/health
   curl -f https://landsraad.arewel.com/health/ready

   # Check application functionality
   cd /var/www/chom
   sudo -u www-data php artisan tinker --execute="User::count(); Cache::get('test');"
   ```

**Expected Recovery Time:** 30-60 minutes
**Data Loss:** Based on backup age (max 6 hours for scheduled, 0 for pre-deployment)

---

### Scenario 2: Complete VPS Failure (Application Server)

**Symptoms:**
- VPS unresponsive
- Cannot SSH to server
- Complete service outage

**Recovery Steps:**

1. **Provision New VPS**
   ```bash
   # Using OVH Manager or API
   # Provision VPS with same specs: vps-value-1-2-40
   # OS: Debian 13
   # Datacenter: RBX (same as original)

   # Note new IP address
   NEW_IP="51.77.XXX.XXX"
   ```

2. **Update DNS** (if IP changed)
   ```bash
   # Update A record for landsraad.arewel.com
   # TTL: 3600 (may take up to 1 hour to propagate)

   # Or using Terraform
   cd /path/to/terraform
   terraform apply -var="application_ip=$NEW_IP"
   ```

3. **Bootstrap New Server**
   ```bash
   # Copy bootstrap script to new server
   scp -r /path/to/mentat/docker/vps-base/scripts root@${NEW_IP}:/tmp/

   # SSH to new server
   ssh root@${NEW_IP}

   # Run bootstrap script
   cd /tmp/scripts
   chmod +x bootstrap-vps.sh
   ./bootstrap-vps.sh --role=application
   ```

4. **Restore Application**
   ```bash
   # Install application dependencies
   apt-get update
   apt-get install -y nginx php8.2-fpm mysql-server redis-server \
     php8.2-mysql php8.2-redis php8.2-curl php8.2-gd php8.2-mbstring \
     php8.2-xml php8.2-zip php8.2-bcmath

   # Create application directory
   mkdir -p /var/www/chom
   chown -R www-data:www-data /var/www/chom

   # Clone repository
   cd /var/www
   git clone https://github.com/yourorg/chom.git
   cd chom
   git checkout main

   # Install dependencies
   composer install --no-dev --optimize-autoloader
   npm ci
   npm run build
   ```

5. **Restore Configuration**
   ```bash
   # Restore .env file from backup (encrypted in Git or S3)
   aws s3 cp s3://chom-backups/config/.env.production.enc - | \
     gpg --decrypt > /var/www/chom/.env

   # Restore SSL certificates
   aws s3 sync s3://chom-backups/ssl/ /etc/ssl/chom/

   # Restore nginx configuration
   aws s3 sync s3://chom-backups/config/nginx/ /etc/nginx/sites-available/
   ln -s /etc/nginx/sites-available/chom.conf /etc/nginx/sites-enabled/
   ```

6. **Restore Database**
   ```bash
   # Get latest database backup
   LATEST_BACKUP=$(aws s3 ls s3://chom-backups/database/ | sort -r | head -1 | awk '{print $4}')

   # Restore database
   aws s3 cp "s3://chom-backups/database/${LATEST_BACKUP}" - | \
     gunzip | mysql -u root -p chom
   ```

7. **Restore User Files**
   ```bash
   # Restore storage directory
   mkdir -p /var/www/chom/storage
   aws s3 sync s3://chom-backups/files/storage/ /var/www/chom/storage/

   # Set permissions
   chown -R www-data:www-data /var/www/chom/storage
   chmod -R 775 /var/www/chom/storage
   ```

8. **Application Setup**
   ```bash
   cd /var/www/chom

   # Generate application key if needed
   sudo -u www-data php artisan key:generate

   # Run migrations
   sudo -u www-data php artisan migrate --force

   # Cache configuration
   sudo -u www-data php artisan config:cache
   sudo -u www-data php artisan route:cache
   sudo -u www-data php artisan view:cache
   ```

9. **Start Services**
   ```bash
   systemctl enable nginx php8.2-fpm mysql redis-server
   systemctl start nginx php8.2-fpm mysql redis-server

   # Setup queue workers (supervisor)
   cp /var/www/chom/deployment/supervisor/chom-worker.conf /etc/supervisor/conf.d/
   supervisorctl reread
   supervisorctl update
   supervisorctl start chom-worker:*
   ```

10. **Verification & Testing**
    ```bash
    # Health checks
    curl -f https://landsraad.arewel.com/health

    # Application tests
    cd /var/www/chom
    php artisan test --parallel

    # Load test (optional)
    ab -n 1000 -c 10 https://landsraad.arewel.com/
    ```

11. **Update Monitoring**
    ```bash
    # SSH to observability server
    ssh ops@mentat.arewel.com

    # Update Prometheus targets if IP changed
    sudo vi /etc/prometheus/prometheus.yml
    # Update target: ${NEW_IP}:9100

    sudo systemctl reload prometheus
    ```

**Expected Recovery Time:** 2-4 hours
**Data Loss:** Based on last backup (max 6 hours database, 24 hours files)

---

### Scenario 3: Observability Stack Failure

**Symptoms:**
- Cannot access Grafana
- No metrics in Prometheus
- Alerts not firing

**Recovery Steps:**

1. **Assess Damage**
   ```bash
   ssh ops@mentat.arewel.com

   # Check service status
   sudo systemctl status prometheus grafana-server loki tempo alertmanager

   # Check disk space
   df -h

   # Check logs
   sudo journalctl -u prometheus --since '1 hour ago'
   ```

2. **Quick Fix Attempts**
   ```bash
   # Restart services
   sudo systemctl restart prometheus grafana-server

   # Clear temporary data if disk full
   sudo find /var/lib/prometheus -name '*.tmp' -delete
   ```

3. **Full Recovery (if needed)**
   ```bash
   # Stop services
   sudo systemctl stop prometheus grafana-server loki tempo

   # Backup current state
   sudo tar -czf /tmp/observability-backup-$(date +%Y%m%d).tar.gz \
     /var/lib/prometheus \
     /var/lib/grafana \
     /var/lib/loki \
     /var/lib/tempo

   # Restore from backup
   aws s3 sync s3://chom-backups/observability/prometheus/ /var/lib/prometheus/
   aws s3 sync s3://chom-backups/observability/grafana/ /var/lib/grafana/

   # Fix permissions
   chown -R prometheus:prometheus /var/lib/prometheus
   chown -R grafana:grafana /var/lib/grafana

   # Restart services
   sudo systemctl start prometheus grafana-server loki tempo
   ```

4. **Verification**
   ```bash
   # Check Prometheus
   curl -f http://mentat.arewel.com:9090/-/healthy

   # Check Grafana
   curl -f http://mentat.arewel.com:3000/api/health

   # Verify data
   # Login to Grafana and check dashboards
   ```

**Expected Recovery Time:** 1-2 hours
**Data Loss:** Recent metrics (queries use remote storage for long-term data)

---

### Scenario 4: Deployment Failure & Rollback

**Symptoms:**
- Health checks failing after deployment
- Application errors
- Database migration issues

**Recovery Steps:**

1. **Immediate Rollback**
   ```bash
   ssh ops@landsraad.arewel.com
   cd /var/www/chom

   # Use automated rollback script
   sudo -u www-data /var/www/chom/scripts/rollback.sh --steps=1

   # Or manual rollback
   sudo -u www-data /var/www/chom/scripts/rollback.sh --commit=<previous-commit-hash>
   ```

2. **Verify Rollback**
   ```bash
   # Check health
   curl -f https://landsraad.arewel.com/health

   # Verify version
   cd /var/www/chom
   git log -1 --oneline
   ```

3. **Investigate Failure**
   ```bash
   # Check deployment logs
   tail -500 /var/www/chom/storage/logs/deployment_*.log

   # Check application logs
   tail -500 /var/www/chom/storage/logs/laravel.log

   # Check database migration status
   sudo -u www-data php artisan migrate:status
   ```

4. **Fix & Redeploy**
   - Fix issues in code
   - Test in staging
   - Redeploy with fixes

**Expected Recovery Time:** 10-30 minutes
**Data Loss:** None (rollback to previous working state)

---

### Scenario 5: SSL Certificate Expiration

**Symptoms:**
- Browser SSL warnings
- API connection failures
- Monitoring alerts

**Recovery Steps:**

1. **Immediate Mitigation**
   ```bash
   ssh ops@landsraad.arewel.com

   # Renew Let's Encrypt certificate
   sudo certbot renew --force-renewal

   # Reload nginx
   sudo systemctl reload nginx
   ```

2. **Manual Certificate Installation** (if certbot fails)
   ```bash
   # Get new certificate from provider
   # Copy to server
   scp cert.pem key.pem ops@landsraad.arewel.com:/tmp/

   # Install on server
   ssh ops@landsraad.arewel.com
   sudo cp /tmp/cert.pem /etc/ssl/chom/
   sudo cp /tmp/key.pem /etc/ssl/chom/
   sudo chmod 600 /etc/ssl/chom/key.pem
   sudo systemctl reload nginx
   ```

3. **Verification**
   ```bash
   # Check certificate
   echo | openssl s_client -servername landsraad.arewel.com \
     -connect landsraad.arewel.com:443 2>/dev/null | \
     openssl x509 -noout -dates

   # Test HTTPS
   curl -vI https://landsraad.arewel.com 2>&1 | grep -i 'SSL\|certificate'
   ```

**Expected Recovery Time:** 15-30 minutes
**Data Loss:** None

---

## Testing & Validation

### Monthly DR Drill

**Schedule:** First Sunday of each month, 10:00 UTC

**Test Procedures:**

1. **Database Restore Test**
   ```bash
   # Restore to separate database
   mysql -u root -p -e "CREATE DATABASE chom_dr_test;"
   aws s3 cp s3://chom-backups/database/latest.sql.gz - | \
     gunzip | mysql -u root -p chom_dr_test

   # Verify data
   mysql -u root -p -e "USE chom_dr_test; SELECT COUNT(*) FROM users;"

   # Cleanup
   mysql -u root -p -e "DROP DATABASE chom_dr_test;"
   ```

2. **File Restore Test**
   ```bash
   # Restore to temporary location
   mkdir -p /tmp/dr-test
   aws s3 sync s3://chom-backups/files/storage/ /tmp/dr-test/ --dryrun

   # Verify file count and size
   du -sh /tmp/dr-test
   find /tmp/dr-test -type f | wc -l

   # Cleanup
   rm -rf /tmp/dr-test
   ```

3. **Blue-Green Deployment Test**
   ```bash
   # Test blue-green deployment in staging
   # Document any issues
   ```

### DR Test Checklist

- [ ] Database backup exists and is restorable
- [ ] File backups are complete and accessible
- [ ] Configuration backups are encrypted and retrievable
- [ ] DNS failover procedures documented
- [ ] Team contact list is up to date
- [ ] Runbook procedures are accurate
- [ ] Recovery time within RTO targets
- [ ] Data loss within RPO targets
- [ ] Post-test report completed

### DR Test Report Template

```markdown
# DR Test Report - [Date]

## Test Scenario
[Description of scenario tested]

## Test Results
- **Start Time:** [Time]
- **End Time:** [Time]
- **Actual RTO:** [Time]
- **Target RTO:** [Time]
- **Status:** [PASS/FAIL]

## Issues Identified
1. [Issue description]
2. [Issue description]

## Action Items
- [ ] [Action with owner and due date]
- [ ] [Action with owner and due date]

## Runbook Updates
- [Changes made to runbook]

## Sign-off
- Tester: [Name]
- Reviewer: [Name]
- Date: [Date]
```

---

## Appendix

### Critical Contacts

| Role | Name | Phone | Email |
|------|------|-------|-------|
| Primary On-Call | [Name] | [Phone] | [Email] |
| Secondary On-Call | [Name] | [Phone] | [Email] |
| DevOps Lead | [Name] | [Phone] | [Email] |
| CTO | [Name] | [Phone] | [Email] |
| OVH Support | - | - | support@ovh.com |

### External Services

| Service | URL | Login | Notes |
|---------|-----|-------|-------|
| OVH Manager | https://ovh.com/manager | [Account] | VPS management |
| GitHub | https://github.com | [Account] | Code repository |
| PagerDuty | https://pagerduty.com | [Account] | Alerting |
| AWS S3 | https://s3.console.aws.amazon.com | [Account] | Backup storage |

### Backup Locations

| Type | Primary | Secondary | Tertiary |
|------|---------|-----------|----------|
| Database | /var/backups/chom/database | S3: chom-backups/database | - |
| Files | /var/backups/chom/files | S3: chom-backups/files | - |
| Config | Git repository | S3: chom-backups/config | Encrypted local |
| Observability | /var/lib/prometheus | S3: chom-backups/observability | - |

### Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | DevOps Team | Initial version |

---

**Last Updated:** 2026-01-02
**Next Review:** 2026-04-02
**Owner:** DevOps Team
