# Disaster Recovery Quick Reference Card

## Emergency Contacts

| Role | Contact | Phone | Email |
|------|---------|-------|-------|
| DevOps Lead | - | - | - |
| DBA | - | - | - |
| Security | - | - | - |

**Escalation Hotline:** -

---

## Critical Commands

### Check Backup Status

```bash
# Check last backup time
curl -s http://mentat.arewel.com:9091/metrics | grep backup_offsite_last_run_timestamp

# List recent backups in S3
aws s3 ls s3://mentat-backups/mysql/$(date +%Y-%m-%d)/

# Check local backups
ls -lh /opt/mentat/chom/storage/app/backups/
```

### Manual Backup

```bash
# Database backup
cd /opt/mentat/chom
docker exec chom-mysql mysqldump -u root -p chom > /tmp/emergency_backup_$(date +%Y%m%d_%H%M%S).sql

# Upload to S3
/opt/mentat/scripts/disaster-recovery/backup-offsite.sh

# Verify backup
/opt/mentat/scripts/disaster-recovery/verify-backups.sh
```

### Emergency Restore

```bash
# 1. Enable maintenance mode
docker exec chom-app php artisan down

# 2. Download latest backup
aws s3 cp s3://mentat-backups/mysql/$(date +%Y-%m-%d)/latest.sql.gpg /tmp/

# 3. Decrypt backup
gpg --decrypt /tmp/latest.sql.gpg > /tmp/restore.sql

# 4. Restore database
docker exec -i chom-mysql mysql -u root -p chom < /tmp/restore.sql

# 5. Disable maintenance mode
docker exec chom-app php artisan up

# 6. Verify
curl https://landsraad.arewel.com/health
```

---

## Recovery Time Objectives (RTO)

| Service | RTO | RPO |
|---------|-----|-----|
| CHOM Application | 2 hours | 1 hour |
| MySQL Database | 1 hour | 15 minutes |
| Observability Stack | 4 hours | 24 hours |

---

## Quick Diagnostics

### Is the backup system working?

```bash
# All checks should return 0
curl -s http://mentat.arewel.com:9091/metrics | grep "backup_offsite_last_run_status 0" && echo "BACKUP FAILED!" || echo "OK"
```

### When was the last backup?

```bash
# Should be < 24 hours ago
echo "Last backup: $(( ($(date +%s) - $(curl -s http://mentat.arewel.com:9091/metrics | grep backup_offsite_last_run_timestamp | awk '{print $2}')) / 3600 )) hours ago"
```

### How much data do we have backed up?

```bash
# Total backup size
aws s3 ls s3://mentat-backups/ --recursive --summarize | tail -2
```

---

## Common Scenarios

### Scenario 1: VPS Down

1. Ping VPS: `ping landsraad.arewel.com`
2. Check provider status page
3. If confirmed down:
   - Notify stakeholders
   - Follow: `/opt/mentat/DISASTER_RECOVERY.md#1-vps-complete-failure`
   - ETA: 2 hours

### Scenario 2: Database Corruption

1. Check error: `docker logs chom-mysql | grep -i corrupt`
2. Enable maintenance: `docker exec chom-app php artisan down`
3. Follow: `/opt/mentat/DISASTER_RECOVERY.md#2-database-corruption`
4. ETA: 1 hour

### Scenario 3: Data Loss

1. Identify lost data
2. Check backup availability: `aws s3 ls s3://mentat-backups/volumes/`
3. Follow: `/opt/mentat/DISASTER_RECOVERY.md#3-application-data-loss`
4. ETA: 50 minutes

### Scenario 4: Monitoring Down

1. Check: `curl http://mentat.arewel.com:9090/-/healthy`
2. Restart: `docker restart prometheus grafana loki`
3. Follow: `/opt/mentat/DISASTER_RECOVERY.md#4-observability-stack-failure`
4. ETA: 15 minutes (application still running)

---

## S3 Backup Locations

```
s3://mentat-backups/
├── mysql/
│   └── YYYY-MM-DD/
│       ├── backup_YYYYMMDD_HHMMSS.sql.gpg
│       └── backup_YYYYMMDD_HHMMSS.sql.gpg
├── volumes/
│   └── YYYY-MM-DD/
│       ├── chom_backup_YYYYMMDD_HHMMSS.tar.gz.gpg
│       └── chom_backup_YYYYMMDD_HHMMSS.tar.gz.gpg
└── config/
    └── YYYY-MM-DD/
        └── config_YYYYMMDD_HHMMSS.tar.gz.gpg
```

---

## Decryption Commands

### Using GPG Public Key

```bash
gpg --decrypt backup_file.gpg > backup_file
```

### Using Passphrase File

```bash
gpg --decrypt --passphrase-file /opt/mentat/scripts/disaster-recovery/.gpg-passphrase backup_file.gpg > backup_file
```

---

## Health Check URLs

| Service | URL | Expected |
|---------|-----|----------|
| CHOM App | https://landsraad.arewel.com/health | 200 OK |
| Prometheus | http://mentat.arewel.com:9090/-/healthy | Prometheus is Healthy |
| Grafana | http://mentat.arewel.com:3000/api/health | {"database":"ok"} |
| Loki | http://mentat.arewel.com:3100/ready | ready |

---

## Pre-Flight Checklist (Before Recovery)

- [ ] Maintenance window scheduled
- [ ] Stakeholders notified
- [ ] Latest backup identified and downloaded
- [ ] Backup integrity verified
- [ ] Recovery procedure reviewed
- [ ] Rollback plan prepared
- [ ] Team assembled (if needed)
- [ ] Evidence preserved (if security incident)

---

## Post-Recovery Checklist

- [ ] All services running
- [ ] Health checks passing
- [ ] Data integrity verified
- [ ] Monitoring restored
- [ ] Stakeholders notified
- [ ] Incident documented
- [ ] Post-mortem scheduled
- [ ] Runbook updated

---

## Useful Monitoring Queries

### Prometheus

```promql
# Backup status (0 = failed, 1 = success)
backup_offsite_last_run_status

# Time since last backup (seconds)
time() - backup_offsite_last_run_timestamp

# Backup size (bytes)
backup_offsite_last_run_bytes

# Verification failures
backup_verification_failed

# DR test status
dr_test_status
```

### Log Queries

```bash
# Check backup logs
tail -f /var/log/backups/offsite.log

# Check verification logs
tail -f /var/log/backups/verification.log

# Check DR test logs
tail -f /var/log/backups/dr-test.log
```

---

## Scripts Location

All DR scripts located at: `/opt/mentat/scripts/disaster-recovery/`

| Script | Purpose | Schedule |
|--------|---------|----------|
| `backup-offsite.sh` | Upload backups to S3 | Daily 2 AM |
| `verify-backups.sh` | Verify backup integrity | Daily 3 AM |
| `test-recovery.sh` | Test recovery procedures | Weekly Sun 4 AM |

---

## Important Files

| File | Purpose | Backup Location |
|------|---------|-----------------|
| `/opt/mentat/chom/.env` | App config | S3 config/ |
| `/opt/mentat/docker-compose.production.yml` | Docker config | S3 config/ |
| `/opt/mentat/scripts/disaster-recovery/backup-config.env` | Backup config | Secure vault |
| `/opt/mentat/scripts/disaster-recovery/.gpg-passphrase` | Encryption key | Secure vault |

---

## Alert Thresholds

| Alert | Threshold | Severity |
|-------|-----------|----------|
| Backup job failed | last_run_status == 0 | Critical |
| Backup not run | > 24 hours | Critical |
| Backup too old | > 48 hours | Critical |
| Verification failed | failed > 0 | Critical |
| Storage full | < 10% free | Critical |
| Backup size abnormal | < 50% of average | Warning |

---

## Remember

1. **Never panic** - Follow the runbook
2. **Document everything** - Even small details matter
3. **Test before applying** - Use test environment when possible
4. **Verify after restore** - Run health checks
5. **Communicate** - Keep stakeholders informed
6. **Learn and improve** - Update runbook after incidents

---

**Keep this card accessible during incidents!**

Print and laminate for physical reference or bookmark digitally.

---

Last Updated: 2026-01-02
