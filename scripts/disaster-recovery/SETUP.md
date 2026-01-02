# Disaster Recovery and Backup Setup Guide

## Overview

This guide walks you through setting up a comprehensive disaster recovery and backup strategy for the mentat infrastructure.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [S3 Configuration](#s3-configuration)
3. [GPG Encryption Setup](#gpg-encryption-setup)
4. [Script Installation](#script-installation)
5. [Cron Jobs Setup](#cron-jobs-setup)
6. [Monitoring Integration](#monitoring-integration)
7. [Testing](#testing)
8. [Maintenance](#maintenance)

---

## Prerequisites

### Required Software

Install required dependencies on both VPS:

```bash
# Update package list
apt-get update

# Install AWS CLI
apt-get install -y awscli

# Install GPG for encryption
apt-get install -y gnupg

# Install other utilities
apt-get install -y tar gzip curl wget mailutils

# Verify installations
aws --version
gpg --version
```

### Directory Structure

Create required directories:

```bash
# On landsraad.arewel.com (CHOM VPS)
mkdir -p /opt/mentat/backups
mkdir -p /opt/mentat/scripts/disaster-recovery
mkdir -p /opt/mentat/reports/backup-verification
mkdir -p /opt/mentat/reports/dr-tests
mkdir -p /var/log/backups

# On mentat.arewel.com (Observability VPS)
mkdir -p /var/lib/observability-backups
mkdir -p /opt/observability-stack/backups
mkdir -p /var/log/backups
```

---

## S3 Configuration

### Option 1: AWS S3

1. **Create S3 Bucket:**

```bash
# Using AWS CLI
aws s3 mb s3://mentat-backups --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket mentat-backups \
    --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
    --bucket mentat-backups \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
```

2. **Create IAM User for Backups:**

```bash
# Create IAM user
aws iam create-user --user-name backup-user

# Attach S3 policy
cat > /tmp/backup-policy.json <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::mentat-backups",
                "arn:aws:s3:::mentat-backups/*"
            ]
        }
    ]
}
EOF

aws iam put-user-policy \
    --user-name backup-user \
    --policy-name BackupPolicy \
    --policy-document file:///tmp/backup-policy.json

# Create access keys
aws iam create-access-key --user-name backup-user
```

3. **Configure Lifecycle Policy (Optional):**

```bash
cat > /tmp/lifecycle.json <<'EOF'
{
    "Rules": [
        {
            "Id": "Move to Glacier after 30 days",
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                }
            ],
            "Expiration": {
                "Days": 365
            }
        }
    ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
    --bucket mentat-backups \
    --lifecycle-configuration file:///tmp/lifecycle.json
```

### Option 2: Backblaze B2

1. **Create Bucket:**
   - Log in to Backblaze B2 dashboard
   - Create new bucket: `mentat-backups`
   - Enable encryption
   - Note your endpoint URL (e.g., `s3.us-west-004.backblazeb2.com`)

2. **Create Application Key:**
   - Go to App Keys section
   - Create new application key with read/write access
   - Save the keyID and applicationKey

### Option 3: Wasabi

1. **Create Bucket:**
   - Log in to Wasabi dashboard
   - Create bucket: `mentat-backups`
   - Select region (us-east-1 recommended)

2. **Create Access Keys:**
   - Go to Access Keys
   - Create new access key
   - Save access key ID and secret key

---

## GPG Encryption Setup

### Option 1: GPG Public Key Encryption (Recommended)

```bash
# Generate GPG key pair
gpg --full-generate-key

# Follow prompts:
# - Key type: RSA and RSA
# - Key size: 4096
# - Expiration: 0 (never expires) or set expiration
# - Real name: Backup System
# - Email: backup@arewel.com
# - Passphrase: (use strong passphrase)

# List keys to verify
gpg --list-keys

# Export public key (for recovery on different systems)
gpg --armor --export backup@arewel.com > /opt/mentat/scripts/disaster-recovery/backup-public-key.asc

# Export private key (SECURE THIS CAREFULLY!)
gpg --armor --export-secret-keys backup@arewel.com > /tmp/backup-private-key.asc

# Store private key in secure location:
# - Password manager
# - Hardware security module
# - Offline encrypted USB drive
# - Multiple secure locations

# IMPORTANT: Test decryption before deleting original
gpg --encrypt --recipient backup@arewel.com /etc/hostname
gpg --decrypt hostname.gpg
```

### Option 2: Symmetric Encryption (Simpler)

```bash
# Create passphrase file
openssl rand -base64 32 > /opt/mentat/scripts/disaster-recovery/.gpg-passphrase

# Secure the passphrase file
chmod 600 /opt/mentat/scripts/disaster-recovery/.gpg-passphrase
chown root:root /opt/mentat/scripts/disaster-recovery/.gpg-passphrase

# Test encryption/decryption
gpg --symmetric --cipher-algo AES256 --passphrase-file /opt/mentat/scripts/disaster-recovery/.gpg-passphrase /etc/hostname
gpg --decrypt --passphrase-file /opt/mentat/scripts/disaster-recovery/.gpg-passphrase hostname.gpg

# IMPORTANT: Backup the passphrase file to secure location!
```

---

## Script Installation

### 1. Copy Scripts

```bash
# Navigate to repository
cd /opt/mentat

# Make scripts executable
chmod +x scripts/disaster-recovery/*.sh

# Verify scripts
ls -l scripts/disaster-recovery/
```

### 2. Create Configuration File

```bash
# Copy example config
cp scripts/disaster-recovery/backup-config.env.example \
   scripts/disaster-recovery/backup-config.env

# Edit configuration
nano scripts/disaster-recovery/backup-config.env
```

Example configuration for AWS S3:

```bash
# S3 Provider Configuration
S3_PROVIDER=s3
S3_BUCKET=mentat-backups
S3_REGION=us-east-1
S3_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE
S3_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
S3_STORAGE_CLASS=INTELLIGENT_TIERING

# Backup Configuration
BACKUP_SOURCE_DIR=/opt/mentat/backups
BACKUP_RETENTION_DAYS=30
BACKUP_FULL_RETENTION_DAYS=90

# Encryption Configuration
BACKUP_ENCRYPTION_ENABLED=true
GPG_RECIPIENT=backup@arewel.com

# Monitoring Configuration
METRICS_ENABLED=true
METRICS_PUSHGATEWAY=http://mentat.arewel.com:9091
ALERT_EMAIL=admin@arewel.com
```

### 3. Secure Configuration

```bash
# Restrict permissions
chmod 600 scripts/disaster-recovery/backup-config.env
chown root:root scripts/disaster-recovery/backup-config.env

# Add to .gitignore
echo "scripts/disaster-recovery/backup-config.env" >> .gitignore
echo "scripts/disaster-recovery/.gpg-passphrase" >> .gitignore
```

### 4. Test Scripts

```bash
# Test offsite backup (dry run)
./scripts/disaster-recovery/backup-offsite.sh

# Test backup verification
./scripts/disaster-recovery/verify-backups.sh

# Test recovery simulation
./scripts/disaster-recovery/test-recovery.sh quick
```

---

## Cron Jobs Setup

### 1. Create Crontab Entries

```bash
# Edit root crontab
sudo crontab -e
```

### 2. Add Backup Jobs

```bash
# ============================================================================
# Disaster Recovery and Backup Jobs
# ============================================================================

# Offsite Backup - Daily at 2 AM
0 2 * * * /opt/mentat/scripts/disaster-recovery/backup-offsite.sh >> /var/log/backups/offsite.log 2>&1

# Backup Verification - Daily at 3 AM
0 3 * * * /opt/mentat/scripts/disaster-recovery/verify-backups.sh >> /var/log/backups/verification.log 2>&1

# Recovery Testing - Weekly on Sundays at 4 AM
0 4 * * 0 /opt/mentat/scripts/disaster-recovery/test-recovery.sh database >> /var/log/backups/dr-test.log 2>&1

# Full Recovery Test - Monthly on 1st at 5 AM
0 5 1 * * /opt/mentat/scripts/disaster-recovery/test-recovery.sh full >> /var/log/backups/dr-test-full.log 2>&1

# Log rotation - Daily at 1 AM
0 1 * * * find /var/log/backups -name "*.log" -size +100M -exec gzip {} \;
0 1 * * * find /var/log/backups -name "*.log.gz" -mtime +30 -delete
```

### 3. Verify Cron Jobs

```bash
# List cron jobs
crontab -l

# Check cron service status
systemctl status cron

# Monitor cron execution
tail -f /var/log/syslog | grep CRON
```

---

## Monitoring Integration

### 1. Configure Prometheus Alerts

```bash
# Copy alert rules to Prometheus
cp /opt/mentat/observability-stack/modules/_core/backup_monitoring/alerts.yml \
   /opt/observability-stack/prometheus/rules/

# Reload Prometheus configuration
curl -X POST http://mentat.arewel.com:9090/-/reload
```

### 2. Create Grafana Dashboard

Create a new dashboard in Grafana with the following panels:

**Panel 1: Backup Status**
```promql
backup_offsite_last_run_status
```

**Panel 2: Backup Age**
```promql
(time() - backup_offsite_last_run_timestamp) / 3600
```

**Panel 3: Backup Size Trend**
```promql
backup_offsite_last_run_bytes
```

**Panel 4: Verification Status**
```promql
backup_verification_failed
```

**Panel 5: DR Test Results**
```promql
dr_test_status
```

### 3. Configure Alertmanager

```bash
# Edit Alertmanager config
nano /opt/observability-stack/alertmanager/config.yml
```

Add routing for backup alerts:

```yaml
route:
  group_by: ['alertname', 'component']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'

  routes:
    - match:
        component: backup
      receiver: 'backup-team'
      continue: true

receivers:
  - name: 'backup-team'
    email_configs:
      - to: 'backup-alerts@arewel.com'
        from: 'alertmanager@arewel.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@arewel.com'
        auth_password: 'your-password'
```

---

## Testing

### 1. Initial Test Plan

Execute the following tests to verify your DR setup:

```bash
# Test 1: Create and upload a test backup
echo "test data" > /tmp/test-backup.txt
tar -czf /opt/mentat/backups/test_backup.tar.gz /tmp/test-backup.txt
/opt/mentat/scripts/disaster-recovery/backup-offsite.sh

# Test 2: Verify backup in S3
aws s3 ls s3://mentat-backups/volumes/$(date +%Y-%m-%d)/

# Test 3: Download and verify backup
aws s3 cp s3://mentat-backups/volumes/$(date +%Y-%m-%d)/test_backup.tar.gz.gpg /tmp/
gpg --decrypt /tmp/test_backup.tar.gz.gpg > /tmp/test_restore.tar.gz
tar -tzf /tmp/test_restore.tar.gz

# Test 4: Run backup verification
/opt/mentat/scripts/disaster-recovery/verify-backups.sh

# Test 5: Run quick recovery test
/opt/mentat/scripts/disaster-recovery/test-recovery.sh quick

# Test 6: Verify metrics in Prometheus
curl http://mentat.arewel.com:9091/metrics | grep backup_

# Cleanup test data
rm -f /tmp/test-backup.txt /tmp/test_backup.tar.gz /tmp/test_backup.tar.gz.gpg /tmp/test_restore.tar.gz
```

### 2. Monthly DR Drill

Schedule and execute monthly disaster recovery drills:

```bash
#!/bin/bash
# Monthly DR Drill Script

echo "=== Monthly DR Drill - $(date) ==="

# 1. Verify all backups are recent
echo "1. Checking backup freshness..."
./scripts/disaster-recovery/verify-backups.sh

# 2. Test database recovery
echo "2. Testing database recovery..."
./scripts/disaster-recovery/test-recovery.sh database

# 3. Test volume recovery
echo "3. Testing volume recovery..."
./scripts/disaster-recovery/test-recovery.sh volumes

# 4. Verify offsite backups
echo "4. Verifying offsite backups..."
aws s3 ls s3://mentat-backups/ --recursive --human-readable --summarize

# 5. Update runbook
echo "5. Review and update DR runbook..."
echo "   - Verify contact information"
echo "   - Update recovery procedures"
echo "   - Document any issues found"

# 6. Generate drill report
echo "6. Generating drill report..."
cat > /tmp/dr-drill-report.txt <<EOF
DR Drill Report - $(date)
========================

Backup Verification: [PASS/FAIL]
Database Recovery Test: [PASS/FAIL]
Volume Recovery Test: [PASS/FAIL]
Offsite Backup Status: [PASS/FAIL]

Issues Found:
- [List any issues]

Action Items:
- [List action items]

Next Drill Date: $(date -d "+1 month" +%Y-%m-%d)

EOF

cat /tmp/dr-drill-report.txt
```

---

## Maintenance

### Daily Tasks

```bash
# Monitor backup logs
tail -f /var/log/backups/offsite.log

# Check backup metrics
curl http://mentat.arewel.com:9091/metrics | grep backup_offsite_last_run_status

# Verify S3 usage
aws s3 ls s3://mentat-backups/ --recursive --summarize
```

### Weekly Tasks

```bash
# Review backup verification reports
ls -lh /opt/mentat/reports/backup-verification/

# Check DR test results
ls -lh /opt/mentat/reports/dr-tests/

# Verify cron job execution
grep "backup-offsite.sh" /var/log/syslog
```

### Monthly Tasks

```bash
# Run full DR drill
./scripts/disaster-recovery/test-recovery.sh full

# Review and update DR runbook
nano /opt/mentat/DISASTER_RECOVERY.md

# Audit backup retention
aws s3 ls s3://mentat-backups/mysql/ --recursive

# Test GPG key access
gpg --list-keys
gpg --encrypt --recipient backup@arewel.com /etc/hostname

# Update backup documentation
```

### Quarterly Tasks

```bash
# Full system DR test (requires maintenance window)
# 1. Schedule maintenance window
# 2. Provision test VPS
# 3. Execute full recovery procedure
# 4. Measure and document RTO/RPO
# 5. Update procedures based on findings

# Rotate GPG keys (if using expiring keys)
gpg --edit-key backup@arewel.com

# Review and update S3 lifecycle policies
aws s3api get-bucket-lifecycle-configuration --bucket mentat-backups

# Audit access logs
aws s3api get-bucket-logging --bucket mentat-backups
```

---

## Troubleshooting

### Backup Upload Failures

```bash
# Check S3 connectivity
aws s3 ls s3://mentat-backups/

# Verify credentials
aws sts get-caller-identity

# Check disk space
df -h

# Review error logs
tail -100 /var/log/backups/offsite.log
```

### Encryption Issues

```bash
# Verify GPG key
gpg --list-keys backup@arewel.com

# Test encryption
echo "test" | gpg --encrypt --recipient backup@arewel.com | gpg --decrypt

# Re-import key if needed
gpg --import /opt/mentat/scripts/disaster-recovery/backup-public-key.asc
```

### Restore Failures

```bash
# Verify backup integrity
aws s3 cp s3://mentat-backups/mysql/2024-01-01/backup.sql.gpg /tmp/
gpg --decrypt /tmp/backup.sql.gpg > /tmp/backup.sql
head -20 /tmp/backup.sql

# Check MySQL container
docker ps | grep mysql
docker logs chom-mysql

# Verify network connectivity
docker network ls
docker network inspect chom-network
```

---

## Security Considerations

1. **Encryption Keys**
   - Store GPG private keys offline
   - Use hardware security modules for production
   - Rotate keys annually
   - Test key recovery procedures

2. **Access Control**
   - Use IAM roles with least privilege
   - Enable MFA on AWS account
   - Audit S3 bucket access logs
   - Restrict backup script execution to root

3. **Data Protection**
   - Enable S3 bucket versioning
   - Configure S3 bucket policies to prevent deletion
   - Use separate AWS account for backups (optional)
   - Encrypt all backups at rest and in transit

4. **Compliance**
   - Document backup procedures
   - Maintain audit trail of backups
   - Test recovery regularly
   - Retain backups per regulatory requirements

---

## Support and Documentation

- **Disaster Recovery Runbook:** `/opt/mentat/DISASTER_RECOVERY.md`
- **Backup Logs:** `/var/log/backups/`
- **Verification Reports:** `/opt/mentat/reports/backup-verification/`
- **DR Test Reports:** `/opt/mentat/reports/dr-tests/`
- **Monitoring Dashboard:** `https://mentat.arewel.com:3000/d/backup-monitoring`
- **Alert Rules:** `/opt/observability-stack/prometheus/rules/backup_monitoring/`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-02
**Owner:** DevOps Team
