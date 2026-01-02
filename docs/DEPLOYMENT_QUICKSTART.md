# CHOM Deployment Quick Start Guide

## Overview

This guide provides step-by-step instructions for deploying the CHOM application to production using the blue-green deployment strategy with comprehensive monitoring and automated backups.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Deploying to Production](#deploying-to-production)
4. [Monitoring Deployments](#monitoring-deployments)
5. [Rollback Procedures](#rollback-procedures)
6. [Backup & Recovery](#backup--recovery)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Access

- [ ] SSH access to production servers
- [ ] GitHub repository access
- [ ] OVH Manager access (for VPS management)
- [ ] Grafana access (for monitoring)
- [ ] Slack webhook (for notifications)

### Required Tools

```bash
# Install required tools locally
sudo apt-get install -y \
  git \
  ssh \
  curl \
  jq \
  aws-cli

# Verify installations
git --version
ssh -V
aws --version
```

### SSH Configuration

Add to `~/.ssh/config`:

```
Host landsraad
    HostName 51.77.150.96
    User ops
    IdentityFile ~/.ssh/chom_deploy_key
    StrictHostKeyChecking no

Host mentat
    HostName 51.254.139.78
    User ops
    IdentityFile ~/.ssh/chom_deploy_key
    StrictHostKeyChecking no
```

Test connection:
```bash
ssh landsraad "hostname && uptime"
ssh mentat "hostname && uptime"
```

---

## Initial Setup

### 1. Configure GitHub Secrets

Navigate to repository settings → Secrets and add:

```bash
PRODUCTION_SSH_KEY="-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----"
PRODUCTION_HOST="51.77.150.96"
PRODUCTION_USER="ops"
SSH_KNOWN_HOSTS="51.77.150.96 ssh-ed25519 AAAA..."
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
GRAFANA_URL="https://mentat.arewel.com:3000"
GRAFANA_API_KEY="glsa_XXXXXXXXXXXX"
PROMETHEUS_URL="http://mentat.arewel.com:9090"
```

### 2. Setup Terraform (Infrastructure as Code)

```bash
cd terraform/

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your credentials
vi terraform.tfvars

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply (DNS and backup storage only)
terraform apply
```

### 3. Configure Automated Backups

On the application server:

```bash
ssh landsraad

# Create backup directories
sudo mkdir -p /var/backups/chom/{database,files,config,reports}
sudo chown -R ops:ops /var/backups/chom

# Setup cron for automated backups
crontab -e
```

Add to crontab:
```bash
# Database backups every 6 hours
0 */6 * * * /var/www/chom/scripts/backup-automated.sh --type=database >> /var/log/chom/backup-cron.log 2>&1

# Full backup daily at 02:00 UTC
0 2 * * * /var/www/chom/scripts/backup-automated.sh --type=all >> /var/log/chom/backup-cron.log 2>&1

# Health check every 5 minutes
*/5 * * * * /var/www/chom/scripts/health-check-enhanced.sh --format=prometheus | curl --data-binary @- http://mentat.arewel.com:9091/metrics/job/health_check/instance/landsraad 2>/dev/null
```

### 4. Configure Environment Variables

On the application server:

```bash
ssh landsraad
cd /var/www/chom

# Copy and edit .env
sudo cp .env.example .env
sudo vi .env
```

Required variables:
```bash
APP_ENV=production
APP_DEBUG=false
APP_URL=https://landsraad.arewel.com

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=SECURE_PASSWORD_HERE

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=SECURE_PASSWORD_HERE
REDIS_PORT=6379

CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

# Backup Configuration
S3_BUCKET=chom-backups
S3_REGION=eu-west-1
BACKUP_ENCRYPTION_KEY=SECURE_KEY_HERE

# Monitoring
PROMETHEUS_PUSHGATEWAY=http://mentat.arewel.com:9091
GRAFANA_URL=http://mentat.arewel.com:3000

# Notifications
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK
```

---

## Deploying to Production

### Method 1: Automated CI/CD (Recommended)

**Via Git Tag:**

```bash
# Create and push a tag
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# GitHub Actions will automatically:
# 1. Build and test
# 2. Run security scans
# 3. Deploy using blue-green strategy
# 4. Run health checks
# 5. Send notifications
```

**Via Git Push:**

```bash
# Push to main branch
git push origin main

# Deployment will trigger automatically
```

**Manual Trigger:**

1. Go to GitHub Actions tab
2. Select "Production Deployment Pipeline"
3. Click "Run workflow"
4. Choose deployment strategy:
   - Blue-Green (recommended)
   - Canary (for gradual rollout)
   - Rolling (for minor updates)

### Method 2: Manual Deployment

**Blue-Green Deployment:**

```bash
# 1. Build artifact locally
cd chom
composer install --no-dev --optimize-autoloader
npm ci && npm run build

# 2. Create artifact
cd ..
tar -czf chom-$(date +%Y%m%d_%H%M%S).tar.gz chom/

# 3. Upload to server
scp chom-*.tar.gz landsraad:/tmp/

# 4. SSH to server and deploy
ssh landsraad

# 5. Run blue-green deployment
export VERSION=$(date +%Y%m%d_%H%M%S)
export ARTIFACT_PATH="/tmp/chom-${VERSION}.tar.gz"
export APP_PATH="/var/www/chom"

sudo /var/www/chom/scripts/deploy-blue-green.sh
```

**Canary Deployment:**

```bash
ssh landsraad

export VERSION=$(date +%Y%m%d_%H%M%S)
export ARTIFACT_PATH="/tmp/chom-${VERSION}.tar.gz"
export CANARY_STAGES="10,25,50,100"
export CANARY_INTERVAL=300

sudo /var/www/chom/scripts/deploy-canary.sh
```

### Deployment Checklist

Before deployment:
- [ ] Code reviewed and approved
- [ ] Tests passing in CI
- [ ] Staging deployment successful
- [ ] Database migrations tested
- [ ] Rollback plan documented
- [ ] Team notified in Slack

During deployment:
- [ ] Monitor deployment logs
- [ ] Watch Grafana dashboards
- [ ] Check error rates
- [ ] Verify health checks

After deployment:
- [ ] Run smoke tests
- [ ] Verify key features
- [ ] Check user reports
- [ ] Update deployment log
- [ ] Tag release in Git

---

## Monitoring Deployments

### Real-Time Monitoring

**Access Grafana:**
```
URL: https://mentat.arewel.com:3000
Login: admin / [password]
Dashboard: "CHOM Production Overview"
```

**Key Metrics to Watch:**

1. **Error Rate**
   - Normal: < 1%
   - Warning: > 5%
   - Critical: > 10%

2. **Response Time (p95)**
   - Normal: < 500ms
   - Warning: > 1000ms
   - Critical: > 2000ms

3. **Request Rate**
   - Compare before/after deployment
   - Should remain stable

4. **System Resources**
   - CPU: < 80%
   - Memory: < 85%
   - Disk: < 85%

### Health Check Commands

**Quick Health Check:**
```bash
# From local machine
curl -f https://landsraad.arewel.com/health

# From server
ssh landsraad "/var/www/chom/scripts/health-check-enhanced.sh"
```

**Enhanced Health Check:**
```bash
ssh landsraad "/var/www/chom/scripts/health-check-enhanced.sh --format=json" | jq '.'
```

**Prometheus Metrics:**
```bash
# Push health metrics to Prometheus
ssh landsraad "/var/www/chom/scripts/health-check-enhanced.sh --format=prometheus" | \
  curl --data-binary @- http://mentat.arewel.com:9091/metrics/job/health_check
```

### Deployment Logs

**View Deployment Logs:**
```bash
ssh landsraad "tail -100 /var/log/chom/deployment_*.log"

# Follow in real-time
ssh landsraad "tail -f /var/log/chom/deployment_*.log"
```

**View Application Logs:**
```bash
ssh landsraad "tail -100 /var/www/chom/storage/logs/laravel.log"

# Filter errors only
ssh landsraad "grep ERROR /var/www/chom/storage/logs/laravel.log | tail -50"
```

**View Nginx Access Logs:**
```bash
ssh landsraad "tail -100 /var/log/nginx/access.log"

# Show 5xx errors
ssh landsraad "grep ' 5[0-9][0-9] ' /var/log/nginx/access.log | tail -20"
```

---

## Rollback Procedures

### Automatic Rollback

CI/CD pipeline automatically rolls back if:
- Health checks fail
- Error rate > 10%
- Database migration fails

### Manual Rollback

**Quick Rollback (Last Deployment):**

```bash
ssh landsraad
cd /var/www/chom
sudo -u www-data ./scripts/rollback.sh --steps=1
```

**Rollback Multiple Steps:**

```bash
# Rollback last 3 deployments
sudo -u www-data ./scripts/rollback.sh --steps=3
```

**Rollback to Specific Commit:**

```bash
# Find commit hash
git log --oneline -10

# Rollback to specific commit
sudo -u www-data ./scripts/rollback.sh --commit=abc123def
```

**Rollback with Database:**

```bash
# Rollback includes database migrations
sudo -u www-data ./scripts/rollback.sh --steps=1

# Rollback without touching database
sudo -u www-data ./scripts/rollback.sh --steps=1 --skip-migrations
```

### Verify Rollback

```bash
# Check current version
ssh landsraad "cd /var/www/chom && git log -1 --oneline"

# Run health checks
ssh landsraad "/var/www/chom/scripts/health-check-enhanced.sh"

# Check application
curl -f https://landsraad.arewel.com/health
```

---

## Backup & Recovery

### Manual Backup

**Database Only:**
```bash
ssh landsraad "/var/www/chom/scripts/backup-automated.sh --type=database"
```

**Files Only:**
```bash
ssh landsraad "/var/www/chom/scripts/backup-automated.sh --type=files"
```

**Full Backup:**
```bash
ssh landsraad "/var/www/chom/scripts/backup-automated.sh --type=all"
```

### List Backups

**Local Backups:**
```bash
ssh landsraad "ls -lht /var/backups/chom/database/ | head -10"
ssh landsraad "ls -lht /var/backups/chom/files/ | head -10"
```

**S3 Backups:**
```bash
aws s3 ls s3://chom-backups/database/ --recursive | sort -r | head -10
aws s3 ls s3://chom-backups/files/ --recursive | sort -r | head -10
```

### Restore from Backup

**Restore Database:**

```bash
ssh landsraad

# List available backups
ls -lht /var/backups/chom/database/

# Choose backup file
BACKUP_FILE="/var/backups/chom/database/db_backup_20260102_120000.sql.gz"

# Restore
gunzip < "$BACKUP_FILE" | mysql -u root -p chom

# Or from S3
aws s3 cp s3://chom-backups/database/db_backup_20260102_120000.sql.gz - | \
  gunzip | mysql -u root -p chom
```

**Restore Files:**

```bash
ssh landsraad

# Choose backup
BACKUP_FILE="/var/backups/chom/files/storage_backup_20260102_020000.tar.gz"

# Extract to temporary location
mkdir -p /tmp/restore
tar -xzf "$BACKUP_FILE" -C /tmp/restore/

# Verify and move
rsync -av /tmp/restore/storage/ /var/www/chom/storage/

# Fix permissions
chown -R www-data:www-data /var/www/chom/storage
```

For complete disaster recovery procedures, see: [`/docs/DISASTER_RECOVERY_RUNBOOK.md`](./DISASTER_RECOVERY_RUNBOOK.md)

---

## Troubleshooting

### Common Issues

**Issue: Deployment fails with "disk full" error**

```bash
# Check disk space
ssh landsraad "df -h"

# Clean old releases
ssh landsraad "cd /var/www/releases && ls -t | tail -n +6 | xargs rm -rf"

# Clean old logs
ssh landsraad "find /var/log/chom -name '*.log' -mtime +7 -delete"

# Clean old backups
ssh landsraad "find /var/backups/chom -type f -mtime +7 -delete"
```

**Issue: Health checks failing after deployment**

```bash
# Check service status
ssh landsraad "systemctl status nginx php8.2-fpm mysql redis"

# Check application logs
ssh landsraad "tail -100 /var/www/chom/storage/logs/laravel.log"

# Restart services
ssh landsraad "sudo systemctl restart php8.2-fpm nginx"

# Run health check
ssh landsraad "/var/www/chom/scripts/health-check-enhanced.sh"
```

**Issue: Database migration fails**

```bash
# Check migration status
ssh landsraad "cd /var/www/chom && php artisan migrate:status"

# Try to repair
ssh landsraad "cd /var/www/chom && php artisan migrate:refresh --force"

# If still failing, restore from backup
# See "Restore Database" section above
```

**Issue: High error rate after deployment**

```bash
# Check error logs
ssh landsraad "grep ERROR /var/www/chom/storage/logs/laravel.log | tail -50"

# Check Nginx errors
ssh landsraad "tail -100 /var/log/nginx/error.log"

# If errors persist, rollback immediately
ssh landsraad "cd /var/www/chom && sudo -u www-data ./scripts/rollback.sh --steps=1"
```

**Issue: Slow performance after deployment**

```bash
# Check system resources
ssh landsraad "top -bn1 | head -20"

# Check slow queries
ssh landsraad "mysql -e 'SHOW FULL PROCESSLIST;'"

# Clear and rebuild caches
ssh landsraad "cd /var/www/chom && php artisan optimize:clear && php artisan optimize"

# Restart PHP-FPM
ssh landsraad "sudo systemctl restart php8.2-fpm"
```

**Issue: Queue workers not processing jobs**

```bash
# Check queue status
ssh landsraad "cd /var/www/chom && php artisan queue:monitor"

# Check worker processes
ssh landsraad "pgrep -fa 'artisan queue:work'"

# Restart workers
ssh landsraad "cd /var/www/chom && php artisan queue:restart"

# Or via supervisor
ssh landsraad "sudo supervisorctl restart chom-worker:*"
```

### Emergency Contacts

**Incident Response:**
1. Create incident channel: `#incident-YYYYMMDD-NNN`
2. Update status page (if available)
3. Contact on-call engineer
4. Escalate to CTO if > 1 hour downtime

**On-Call:**
- Primary: [Name] - [Phone]
- Secondary: [Name] - [Phone]
- Escalation: CTO - [Phone]

**External Support:**
- OVH VPS Support: support@ovh.com
- GitHub Support: support@github.com

---

## Useful Commands Reference

### Deployment

```bash
# Check current version
ssh landsraad "cd /var/www/chom && git log -1 --oneline"

# List releases
ssh landsraad "ls -lt /var/www/releases/"

# Check deployment logs
ssh landsraad "ls -lt /var/log/chom/deployment_*.log | head -5"
```

### Monitoring

```bash
# Health check
curl -f https://landsraad.arewel.com/health

# Check services
ssh landsraad "systemctl status nginx php8.2-fpm mysql redis"

# Check metrics endpoint
curl http://landsraad.arewel.com:9100/metrics
```

### Maintenance

```bash
# Clear caches
ssh landsraad "cd /var/www/chom && php artisan optimize:clear"

# Restart services
ssh landsraad "sudo systemctl restart php8.2-fpm nginx"

# Check disk usage
ssh landsraad "df -h && du -sh /var/www/* /var/backups/*"
```

---

## Additional Resources

- [Full Deployment Architecture](./DEPLOYMENT_ARCHITECTURE.md)
- [Disaster Recovery Runbook](./DISASTER_RECOVERY_RUNBOOK.md)
- [Infrastructure as Code (Terraform)](../terraform/)
- [CI/CD Pipeline Configuration](../.github/workflows/deploy-production.yml)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-02
**Maintained By:** DevOps Team
