# CHOM Backup Procedures

**Version:** 1.0
**Last Updated:** 2026-01-02
**Owner:** DevOps Team

---

## Table of Contents

1. [Overview](#overview)
2. [Backup Strategy](#backup-strategy)
3. [Backup Schedules](#backup-schedules)
4. [Backup Components](#backup-components)
5. [Automated Backup Scripts](#automated-backup-scripts)
6. [Manual Backup Procedures](#manual-backup-procedures)
7. [Backup Verification](#backup-verification)
8. [Backup Rotation and Retention](#backup-rotation-and-retention)
9. [Backup Storage](#backup-storage)
10. [Monitoring and Alerting](#monitoring-and-alerting)
11. [Troubleshooting](#troubleshooting)

---

## Overview

This document defines backup procedures for the CHOM production environment. The backup strategy follows the **3-2-1 rule**:

- **3** copies of data (production + 2 backups)
- **2** different storage types (local disk + remote storage)
- **1** off-site backup (cross-VPS or object storage)

### Backup Objectives

- **Zero Data Loss:** Incremental backups every 15 minutes for critical data
- **Fast Recovery:** Latest backup restorable within 30 minutes
- **Long-term Retention:** Monthly archives kept for 12 months
- **Verified Backups:** Automated integrity checking
- **Encrypted Storage:** All backups encrypted at rest

---

## Backup Strategy

### Full vs. Incremental Backups

#### Full Backups
- **Frequency:** Daily at 02:00 UTC
- **Content:** Complete snapshot of all data
- **Retention:** 7 days (rolling)
- **Use Case:** Disaster recovery, major restoration

#### Incremental Backups
- **Frequency:** Hourly (database only)
- **Content:** Changes since last backup
- **Retention:** 24 hours (rolling)
- **Use Case:** Point-in-time recovery, minimal data loss

#### Differential Backups
- **Frequency:** Every 6 hours
- **Content:** Changes since last full backup
- **Retention:** 48 hours
- **Use Case:** Balance between full and incremental

---

## Backup Schedules

### CHOM Application (landsraad)

| Component | Type | Frequency | Time (UTC) | Retention |
|-----------|------|-----------|------------|-----------|
| MariaDB | Full | Daily | 02:00 | 7 days |
| MariaDB | Incremental | Hourly | :15 | 24 hours |
| MariaDB | Binlog | Continuous | Real-time | 3 days |
| Application Files | Full | Daily | 02:30 | 7 days |
| Configuration | Full | Daily | 03:00 | 30 days |
| SSL Certificates | Full | Daily | 03:15 | 90 days |
| Docker Volumes | Full | Daily | 03:30 | 7 days |
| User Uploads | Incremental | 6-hourly | 00,06,12,18 | 7 days |

### Observability Stack (mentat)

| Component | Type | Frequency | Time (UTC) | Retention |
|-----------|------|-----------|------------|-----------|
| Prometheus | Full | Daily | 04:00 | 30 days |
| Loki | Incremental | 6-hourly | 00,06,12,18 | 7 days |
| Grafana Dashboards | Full | Daily | 04:30 | 30 days |
| Alertmanager Config | Full | Daily | 04:45 | 30 days |
| Tempo | Weekly | Weekly | Sun 05:00 | 30 days |

### Cron Schedule

```cron
# CHOM Backups (landsraad)
15 * * * * /opt/chom/deploy/disaster-recovery/scripts/backup-chom.sh --incremental --component database
0 2 * * * /opt/chom/deploy/disaster-recovery/scripts/backup-chom.sh --full
0 */6 * * * /opt/chom/deploy/disaster-recovery/scripts/backup-chom.sh --differential --component uploads

# Observability Backups (mentat)
0 */6 * * * /opt/observability-stack/deploy/disaster-recovery/scripts/backup-observability.sh --incremental --component loki
0 4 * * * /opt/observability-stack/deploy/disaster-recovery/scripts/backup-observability.sh --full
0 5 * * 0 /opt/observability-stack/deploy/disaster-recovery/scripts/backup-observability.sh --component tempo

# Backup Verification
0 6 * * * /opt/chom/deploy/disaster-recovery/scripts/test-backups.sh --daily
0 8 * * 1 /opt/chom/deploy/disaster-recovery/scripts/test-backups.sh --weekly

# Cleanup Old Backups
0 1 * * * /opt/chom/deploy/disaster-recovery/scripts/cleanup-backups.sh
```

---

## Backup Components

### 1. Database (MariaDB)

#### What is Backed Up
- All databases and tables
- User accounts and privileges
- Stored procedures and triggers
- Database configuration
- Binary logs (for point-in-time recovery)

#### Backup Methods

**Method A: mysqldump (Full Logical Backup)**
```bash
docker exec chom-mysql mysqldump \
  --all-databases \
  --single-transaction \
  --quick \
  --lock-tables=false \
  --routines \
  --triggers \
  --events \
  --master-data=2 \
  | gzip > /backups/chom/mysql/full-$(date +%Y%m%d-%H%M%S).sql.gz
```

**Method B: Binary Logs (Incremental)**
```bash
# Enable binary logging in MySQL config
docker exec chom-mysql mysql -e "FLUSH BINARY LOGS;"
docker exec chom-mysql sh -c 'cp -r /var/lib/mysql/mysql-bin.* /var/lib/mysql/backup/'
```

**Method C: Volume Snapshot (Fastest)**
```bash
docker compose -f docker-compose.production.yml stop mysql
tar czf /backups/chom/mysql/volume-$(date +%Y%m%d-%H%M%S).tar.gz \
  -C /var/lib/docker/volumes mysql_data
docker compose -f docker-compose.production.yml start mysql
```

#### Recommended Approach
- **Daily Full:** mysqldump for portability
- **Hourly Incremental:** Binary log shipping
- **Emergency:** Volume snapshot (requires downtime)

---

### 2. Application Files

#### What is Backed Up
```
/opt/chom/
├── app/                    # Laravel application code
├── bootstrap/              # Bootstrap files
├── config/                 # Configuration files
├── database/               # Migrations, seeds
├── public/                 # Public assets
├── resources/              # Views, lang files
├── routes/                 # Route definitions
├── storage/                # Logs, cache, uploads
│   ├── app/               # Application files
│   ├── framework/         # Framework cache
│   └── logs/              # Application logs
└── vendor/                # Dependencies (optional)
```

#### Backup Commands

**Full Application Backup:**
```bash
tar czf /backups/chom/app/full-$(date +%Y%m%d-%H%M%S).tar.gz \
  --exclude='vendor' \
  --exclude='node_modules' \
  --exclude='storage/framework/cache' \
  --exclude='storage/logs/*.log' \
  /opt/chom
```

**Storage Only (User Uploads):**
```bash
rsync -avz --delete \
  /opt/chom/storage/app/ \
  /backups/chom/uploads/$(date +%Y%m%d)/
```

**Configuration Only:**
```bash
tar czf /backups/chom/config/config-$(date +%Y%m%d-%H%M%S).tar.gz \
  /opt/chom/.env \
  /opt/chom/config/ \
  /opt/chom/docker/production/
```

---

### 3. SSL Certificates

#### What is Backed Up
```
/opt/chom/docker/production/ssl/
├── fullchain.pem          # Certificate chain
├── privkey.pem            # Private key
├── cert.pem               # Certificate only
└── chain.pem              # Intermediate certificates
```

#### Backup Commands
```bash
tar czf /backups/chom/ssl/ssl-$(date +%Y%m%d).tar.gz \
  /opt/chom/docker/production/ssl/

# Encrypt with GPG for security
gpg --encrypt --recipient backup@company.com \
  /backups/chom/ssl/ssl-$(date +%Y%m%d).tar.gz
```

---

### 4. Docker Volumes

#### Volumes to Back Up
- `mysql_data` - Database files
- `redis_data` - Redis persistence
- `ssl-certs` - SSL certificate volume
- `php-fpm-socket` - Not needed (runtime only)

#### Backup Commands
```bash
# List all volumes
docker volume ls

# Backup specific volume
docker run --rm \
  -v mysql_data:/source:ro \
  -v /backups/chom/volumes:/backup \
  alpine \
  tar czf /backup/mysql_data-$(date +%Y%m%d).tar.gz -C /source .

# Backup all CHOM volumes
for vol in mysql_data redis_data ssl-certs; do
  docker run --rm \
    -v ${vol}:/source:ro \
    -v /backups/chom/volumes:/backup \
    alpine \
    tar czf /backup/${vol}-$(date +%Y%m%d).tar.gz -C /source .
done
```

---

### 5. Configuration Files

#### Critical Configuration Files
```
/opt/chom/.env                              # Application environment
/opt/chom/docker-compose.production.yml     # Docker configuration
/opt/chom/docker/production/nginx/          # Nginx configuration
/opt/chom/docker/production/mysql/my.cnf    # MySQL configuration
/opt/chom/docker/production/secrets/        # Docker secrets
/etc/cron.d/chom-backup                     # Backup cron jobs
/etc/systemd/system/chom-*.service          # Systemd services
```

#### Backup Commands
```bash
tar czf /backups/chom/config/system-config-$(date +%Y%m%d).tar.gz \
  /opt/chom/.env \
  /opt/chom/docker-compose.production.yml \
  /opt/chom/docker/production/ \
  /etc/cron.d/chom-* \
  /etc/systemd/system/chom-*
```

---

### 6. Observability Data

#### Prometheus Metrics
```bash
# Stop Prometheus to ensure consistency
docker compose -f docker-compose.observability.yml stop prometheus

# Backup data directory
tar czf /backups/observability/prometheus-$(date +%Y%m%d).tar.gz \
  -C /var/lib/docker/volumes prometheus-data

# Restart Prometheus
docker compose -f docker-compose.observability.yml start prometheus
```

#### Loki Logs
```bash
# Incremental backup (last 6 hours)
docker run --rm \
  -v loki-data:/source:ro \
  -v /backups/observability/loki:/backup \
  alpine \
  tar czf /backup/loki-incremental-$(date +%Y%m%d-%H%M).tar.gz \
  --newer-mtime="6 hours ago" \
  -C /source .
```

#### Grafana Dashboards
```bash
# Export all dashboards via API
curl -X GET \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  http://localhost:3000/api/search?type=dash-db \
  | jq -r '.[].uid' \
  | while read uid; do
      curl -X GET \
        -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
        http://localhost:3000/api/dashboards/uid/${uid} \
        > /backups/observability/grafana/dashboard-${uid}.json
    done
```

---

## Automated Backup Scripts

### Installing Backup Scripts

```bash
# 1. Navigate to deployment directory
cd /opt/chom/deploy/disaster-recovery/scripts

# 2. Make scripts executable
chmod +x backup-chom.sh
chmod +x backup-observability.sh
chmod +x restore-chom.sh
chmod +x restore-observability.sh
chmod +x health-check.sh
chmod +x test-backups.sh

# 3. Create backup directories
mkdir -p /backups/chom/{mysql,app,config,ssl,volumes,uploads}
mkdir -p /backups/observability/{prometheus,loki,grafana,tempo}

# 4. Install cron jobs
crontab -e
# Add schedules from "Backup Schedules" section above
```

### Script Usage

#### backup-chom.sh

```bash
# Full backup (all components)
./backup-chom.sh --full

# Incremental database backup
./backup-chom.sh --incremental --component database

# Backup specific component
./backup-chom.sh --component mysql
./backup-chom.sh --component application
./backup-chom.sh --component config
./backup-chom.sh --component ssl

# Differential backup
./backup-chom.sh --differential --component uploads

# Backup with verification
./backup-chom.sh --full --verify

# Backup and send to remote
./backup-chom.sh --full --remote mentat:/backups/chom-remote/

# Show backup status
./backup-chom.sh --status

# List available backups
./backup-chom.sh --list
```

#### backup-observability.sh

```bash
# Full backup
./backup-observability.sh --full

# Incremental logs
./backup-observability.sh --incremental --component loki

# Backup specific component
./backup-observability.sh --component prometheus
./backup-observability.sh --component grafana
./backup-observability.sh --component tempo

# Backup dashboards only
./backup-observability.sh --component grafana-dashboards
```

---

## Manual Backup Procedures

### Emergency Manual Database Backup

When automated backups fail or you need an immediate backup:

```bash
# 1. SSH to landsraad
ssh deploy@51.77.150.96

# 2. Create backup directory
mkdir -p /tmp/emergency-backup

# 3. Dump database
docker exec chom-mysql mysqldump \
  --all-databases \
  --single-transaction \
  --quick \
  --lock-tables=false \
  > /tmp/emergency-backup/db-$(date +%Y%m%d-%H%M%S).sql

# 4. Compress
gzip /tmp/emergency-backup/db-*.sql

# 5. Copy to safe location
scp /tmp/emergency-backup/db-*.sql.gz \
  deploy@51.254.139.78:/backups/emergency/

# 6. Verify
gunzip -t /tmp/emergency-backup/db-*.sql.gz
echo "Backup size: $(du -sh /tmp/emergency-backup/db-*.sql.gz)"
```

### Pre-Deployment Backup

Before any deployment or maintenance:

```bash
# 1. Full system backup
cd /opt/chom/deploy/disaster-recovery/scripts
./backup-chom.sh --full --tag pre-deployment-$(date +%Y%m%d)

# 2. Verify backup completed
./backup-chom.sh --status

# 3. Test backup (optional but recommended)
./test-backups.sh --latest

# 4. Document backup location
echo "Pre-deployment backup: /backups/chom/pre-deployment-$(date +%Y%m%d)" \
  >> /opt/chom/deployment.log
```

### Pre-Migration Backup

Before database migrations:

```bash
# 1. Backup current database state
docker exec chom-mysql mysqldump \
  --all-databases \
  --single-transaction \
  --master-data=2 \
  | gzip > /backups/chom/mysql/pre-migration-$(date +%Y%m%d-%H%M%S).sql.gz

# 2. Create restore point tag
mysql -e "FLUSH BINARY LOGS;"

# 3. Document current database version
docker exec chom-mysql mysql -e "SELECT * FROM migrations;" > /backups/chom/migrations-state.txt

# 4. Backup application code
git rev-parse HEAD > /backups/chom/git-commit.txt
tar czf /backups/chom/app/pre-migration-$(date +%Y%m%d).tar.gz /opt/chom
```

---

## Backup Verification

### Automated Verification

Verification runs automatically after each backup:

```bash
# Verify database backup integrity
gunzip -t /backups/chom/mysql/latest.sql.gz

# Verify tar archives
tar tzf /backups/chom/app/latest.tar.gz > /dev/null

# Verify file count
find /backups/chom/uploads/ -type f | wc -l

# Verify backup size (should not be 0 or too small)
SIZE=$(du -sb /backups/chom/mysql/latest.sql.gz | awk '{print $1}')
if [ $SIZE -lt 1000000 ]; then
  echo "WARNING: Backup suspiciously small ($SIZE bytes)"
fi
```

### Manual Verification

#### Test Database Backup Restoration

```bash
# 1. Create test database
docker exec chom-mysql mysql -e "CREATE DATABASE backup_test;"

# 2. Restore to test database
gunzip < /backups/chom/mysql/latest.sql.gz \
  | docker exec -i chom-mysql mysql backup_test

# 3. Verify table count
docker exec chom-mysql mysql -e "
  SELECT COUNT(*) AS table_count
  FROM information_schema.tables
  WHERE table_schema='backup_test';"

# 4. Verify row count matches production
docker exec chom-mysql mysql -e "
  SELECT table_name, table_rows
  FROM information_schema.tables
  WHERE table_schema='chom'
  ORDER BY table_name;"

# 5. Drop test database
docker exec chom-mysql mysql -e "DROP DATABASE backup_test;"
```

#### Test Application Backup Restoration

```bash
# 1. Extract to temporary location
mkdir -p /tmp/restore-test
tar xzf /backups/chom/app/latest.tar.gz -C /tmp/restore-test

# 2. Verify critical files present
test -f /tmp/restore-test/opt/chom/.env || echo "ERROR: .env missing"
test -f /tmp/restore-test/opt/chom/artisan || echo "ERROR: artisan missing"
test -d /tmp/restore-test/opt/chom/app || echo "ERROR: app/ directory missing"

# 3. Verify file count matches
PROD_COUNT=$(find /opt/chom -type f | wc -l)
TEST_COUNT=$(find /tmp/restore-test/opt/chom -type f | wc -l)
echo "Production files: $PROD_COUNT"
echo "Backup files: $TEST_COUNT"

# 4. Cleanup
rm -rf /tmp/restore-test
```

### Verification Checklist

Run weekly:

- [ ] Latest full backup exists and is < 24 hours old
- [ ] Latest incremental backup exists and is < 1 hour old
- [ ] Backup files are not corrupted (integrity check passes)
- [ ] Backup size is reasonable (not 0 bytes, not suspiciously small)
- [ ] Test restoration completes without errors
- [ ] Restored data matches production data
- [ ] All backup destinations accessible
- [ ] Backup logs show no errors
- [ ] Monitoring shows successful backup metrics
- [ ] Remote backups synchronized

---

## Backup Rotation and Retention

### Retention Policy

```
/backups/chom/
├── mysql/
│   ├── full/
│   │   ├── daily/              # Keep 7 days
│   │   ├── weekly/             # Keep 4 weeks
│   │   └── monthly/            # Keep 12 months
│   ├── incremental/            # Keep 24 hours
│   └── binlogs/                # Keep 3 days
├── app/
│   ├── full/                   # Keep 7 days
│   └── pre-deployment/         # Keep 30 days
├── config/
│   └── daily/                  # Keep 30 days
├── ssl/
│   └── daily/                  # Keep 90 days
└── uploads/
    ├── incremental/            # Keep 7 days
    └── full/                   # Keep 30 days
```

### Automated Cleanup Script

Create `/opt/chom/deploy/disaster-recovery/scripts/cleanup-backups.sh`:

```bash
#!/bin/bash
# Remove backups older than retention period

BACKUP_ROOT="/backups/chom"

# Daily backups: Keep 7 days
find ${BACKUP_ROOT}/mysql/full/daily/ -name "*.sql.gz" -mtime +7 -delete
find ${BACKUP_ROOT}/app/full/ -name "*.tar.gz" -mtime +7 -delete

# Incremental backups: Keep 24 hours
find ${BACKUP_ROOT}/mysql/incremental/ -name "*.sql.gz" -mtime +1 -delete
find ${BACKUP_ROOT}/uploads/incremental/ -mtime +1 -delete

# Weekly backups: Keep 4 weeks
find ${BACKUP_ROOT}/mysql/full/weekly/ -name "*.sql.gz" -mtime +28 -delete

# Monthly backups: Keep 12 months
find ${BACKUP_ROOT}/mysql/full/monthly/ -name "*.sql.gz" -mtime +365 -delete

# Config backups: Keep 30 days
find ${BACKUP_ROOT}/config/ -name "*.tar.gz" -mtime +30 -delete

# SSL backups: Keep 90 days
find ${BACKUP_ROOT}/ssl/ -name "*.tar.gz" -mtime +90 -delete

# Pre-deployment backups: Keep 30 days
find ${BACKUP_ROOT}/app/pre-deployment/ -name "*.tar.gz" -mtime +30 -delete

# Binary logs: Keep 3 days
find ${BACKUP_ROOT}/mysql/binlogs/ -name "mysql-bin.*" -mtime +3 -delete

# Log cleanup actions
logger -t backup-cleanup "Backup cleanup completed: $(date)"
```

---

## Backup Storage

### Local Storage (Primary)

```
Server: landsraad (51.77.150.96)
Path: /backups/chom/
Size: 20GB allocated
Filesystem: ext4
Mount: /dev/vda2

Server: mentat (51.254.139.78)
Path: /backups/observability/
Size: 10GB allocated
Filesystem: ext4
Mount: /dev/vda2
```

### Cross-VPS Storage (Secondary)

```bash
# landsraad -> mentat
rsync -avz --delete \
  -e "ssh -i /home/deploy/.ssh/backup_key" \
  /backups/chom/ \
  deploy@51.254.139.78:/backups/chom-remote/

# mentat -> landsraad
rsync -avz --delete \
  -e "ssh -i /home/deploy/.ssh/backup_key" \
  /backups/observability/ \
  deploy@51.77.150.96:/backups/observability-remote/
```

### OVH Object Storage (Tertiary - Future)

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure OVH Object Storage
rclone config

# Sync backups to object storage
rclone sync /backups/chom/ ovh-object-storage:chom-backups/ \
  --transfers 4 \
  --checkers 8 \
  --contimeout 60s \
  --timeout 300s \
  --retries 3
```

### Backup Storage Monitoring

```bash
# Check disk usage
df -h /backups

# Alert if over 80% full
USAGE=$(df /backups | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $USAGE -gt 80 ]; then
  echo "WARNING: Backup storage ${USAGE}% full" | mail -s "Backup Storage Alert" ops@company.com
fi

# List largest backups
du -sh /backups/*/* | sort -hr | head -10
```

---

## Monitoring and Alerting

### Prometheus Metrics

Add to Prometheus configuration:

```yaml
# Backup success/failure
backup_success{job="chom",component="database"} 1
backup_success{job="chom",component="application"} 1
backup_success{job="observability",component="prometheus"} 1

# Backup size in bytes
backup_size_bytes{job="chom",component="database"} 524288000
backup_size_bytes{job="chom",component="application"} 104857600

# Backup age in seconds
backup_age_seconds{job="chom",component="database"} 3600

# Backup duration in seconds
backup_duration_seconds{job="chom",component="database"} 45
```

### Alertmanager Rules

```yaml
groups:
  - name: backup_alerts
    interval: 5m
    rules:
      - alert: BackupFailed
        expr: backup_success == 0
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Backup failed for {{ $labels.component }}"
          description: "Backup for {{ $labels.component }} has failed."

      - alert: BackupTooOld
        expr: backup_age_seconds > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Backup is too old for {{ $labels.component }}"
          description: "Last backup for {{ $labels.component }} is over 24 hours old."

      - alert: BackupStorageFull
        expr: (node_filesystem_avail_bytes{mountpoint="/backups"} / node_filesystem_size_bytes{mountpoint="/backups"}) < 0.2
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Backup storage is running low"
          description: "Backup storage has less than 20% free space."
```

### Log Monitoring

Monitor backup logs in Grafana:

```promql
# Failed backups in last 24 hours
count_over_time({job="backup"} |= "ERROR" [24h])

# Backup duration trend
avg_over_time(backup_duration_seconds[7d])

# Largest backups
topk(10, backup_size_bytes)
```

---

## Troubleshooting

### Backup Fails with "No Space Left"

```bash
# Check disk usage
df -h /backups

# Find large files
du -sh /backups/* | sort -hr

# Clean old backups manually
./cleanup-backups.sh

# Extend disk if needed (OVH console)
# Then resize filesystem
resize2fs /dev/vda2
```

### Database Backup Hangs

```bash
# Check for long-running queries
docker exec chom-mysql mysql -e "SHOW PROCESSLIST;"

# Kill problematic query
docker exec chom-mysql mysql -e "KILL <query_id>;"

# Use --skip-lock-tables for backup
mysqldump --skip-lock-tables --single-transaction ...
```

### Backup Corrupted

```bash
# Test integrity
gunzip -t backup.sql.gz

# If corrupted, restore from previous backup
ls -ltr /backups/chom/mysql/
# Use second-latest backup

# Prevent corruption
# Always use --verify flag
./backup-chom.sh --full --verify
```

### Slow Backup Performance

```bash
# Use compression level 1 (faster)
tar czf --use-compress-program="gzip -1" ...

# Use pigz (parallel gzip)
tar cf - /opt/chom | pigz -p 4 > backup.tar.gz

# Exclude large unnecessary files
tar czf backup.tar.gz \
  --exclude='*.log' \
  --exclude='cache/*' \
  /opt/chom
```

### Remote Backup Sync Fails

```bash
# Test SSH connection
ssh -i /home/deploy/.ssh/backup_key deploy@51.254.139.78 echo "OK"

# Check SSH key permissions
chmod 600 /home/deploy/.ssh/backup_key

# Test rsync with verbose
rsync -avz --dry-run \
  -e "ssh -i /home/deploy/.ssh/backup_key" \
  /backups/chom/ \
  deploy@51.254.139.78:/backups/chom-remote/

# Check disk space on remote
ssh deploy@51.254.139.78 df -h /backups
```

---

## Quick Reference

### Daily Operations

```bash
# Check last backup status
./backup-chom.sh --status

# Manual full backup
./backup-chom.sh --full

# Verify latest backup
./test-backups.sh --latest

# Check backup disk usage
df -h /backups
```

### Emergency Procedures

```bash
# Immediate database backup before emergency maintenance
docker exec chom-mysql mysqldump --all-databases | gzip > /tmp/emergency-$(date +%Y%m%d-%H%M%S).sql.gz

# Quick application snapshot
tar czf /tmp/app-snapshot-$(date +%Y%m%d-%H%M%S).tar.gz /opt/chom

# Copy to safe location
scp /tmp/emergency-*.sql.gz deploy@51.254.139.78:/backups/emergency/
```

### Monitoring Commands

```bash
# List recent backups
ls -lth /backups/chom/mysql/ | head -10

# Check backup sizes
du -sh /backups/chom/*

# Verify backup age
find /backups/chom/mysql/ -name "full-*.sql.gz" -mtime -1

# View backup logs
tail -f /var/log/backup.log
journalctl -u chom-backup -f
```

---

**END OF BACKUP PROCEDURES GUIDE**
