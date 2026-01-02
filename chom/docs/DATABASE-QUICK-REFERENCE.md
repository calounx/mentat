# Database Backup & Migration Quick Reference

## Quick Commands

### Backup Operations

```bash
# Full backup (recommended settings)
cd /home/calounx/repositories/mentat/chom
BACKUP_TYPE=full COMPRESSION=zstd VERIFICATION=basic ./scripts/backup-incremental.sh

# Incremental backup (binary logs)
BACKUP_TYPE=incremental COMPRESSION=zstd ./scripts/backup-incremental.sh

# Full backup with verification and upload
BACKUP_TYPE=full COMPRESSION=zstd VERIFICATION=full ENCRYPT_BACKUP=true UPLOAD_REMOTE=true ./scripts/backup-incremental.sh
```

### Restore Operations

```bash
# Quick restore (optimized)
zstd -dc storage/app/backups/full_*.sql.zst | mysql -u root -p chom

# Optimized restore with FK disabled
zstd -dc backup.sql.zst | mysql -u root -p <<EOF
SET FOREIGN_KEY_CHECKS=0;
SET UNIQUE_CHECKS=0;
USE chom;
SOURCE /dev/stdin;
SET FOREIGN_KEY_CHECKS=1;
EOF

# Point-in-time recovery (to specific time)
mysqlbinlog --stop-datetime="2026-01-02 14:30:00" /var/log/mysql/mysql-bin.* | mysql -u root -p chom
```

### Migration Operations

```bash
# Validate migrations (no execution)
php artisan migrate:dry-run --validate

# Full dry-run (execute and rollback)
php artisan migrate:dry-run

# Show SQL without executing
php artisan migrate:dry-run --pretend

# Run migrations (production)
php artisan migrate --force
```

### Monitoring Operations

```bash
# Database overview
php artisan db:monitor --type=overview

# Query performance
php artisan db:monitor --type=queries

# Index analysis
php artisan db:monitor --type=indexes

# Table statistics
php artisan db:monitor --type=tables

# Backup status
php artisan db:monitor --type=backups

# Continuous monitoring
php artisan db:monitor --watch
```

### Benchmark Operations

```bash
# Run all benchmarks
./scripts/benchmark-database.sh

# View results
cat storage/app/benchmarks/benchmark_*.json | jq .
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `/home/calounx/repositories/mentat/chom/scripts/backup-incremental.sh` | Enhanced backup script |
| `/home/calounx/repositories/mentat/chom/app/Console/Commands/MigrateDryRun.php` | Migration validation |
| `/home/calounx/repositories/mentat/chom/app/Console/Commands/DatabaseMonitor.php` | Performance monitor |
| `/home/calounx/repositories/mentat/chom/scripts/benchmark-database.sh` | Benchmark tool |
| `/home/calounx/repositories/mentat/chom/config/grafana/dashboards/database-monitoring.json` | Grafana dashboard |

---

## Environment Variables

```bash
# Backup configuration
BACKUP_TYPE=full              # full, incremental
COMPRESSION=zstd              # zstd, gzip, bzip2, xz, none
VERIFICATION=basic            # none, basic, full
ENCRYPT_BACKUP=true
UPLOAD_REMOTE=true
ENABLE_METRICS=true

# Retention (days)
RETAIN_FULL_DAYS=30
RETAIN_INCREMENTAL_DAYS=7
RETAIN_BINLOG_DAYS=7

# Performance
PARALLEL_THREADS=8            # 0 = auto-detect
```

---

## Cron Schedule

```bash
# Add to crontab: crontab -e

# Daily full backup at 2 AM
0 2 * * * cd /home/calounx/repositories/mentat/chom && BACKUP_TYPE=full COMPRESSION=zstd ./scripts/backup-incremental.sh

# Hourly incremental backup
0 * * * * cd /home/calounx/repositories/mentat/chom && BACKUP_TYPE=incremental ./scripts/backup-incremental.sh

# Weekly verification (Sundays 3 AM)
0 3 * * 0 cd /home/calounx/repositories/mentat/chom && VERIFICATION=full ./scripts/backup-incremental.sh
```

---

## Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| Backup Duration (5 GB DB) | < 10 minutes | ~9m 45s (zstd) |
| Restore Duration | < 15 minutes | ~3m (optimized) |
| Backup Verification | < 30 seconds | ~15s |
| Migration Validation | < 5 seconds | ~2.3s |
| RPO (Recovery Point) | < 1 hour | 1 hour (incremental) |
| RTO (Recovery Time) | < 30 minutes | 15-30m |

---

## Alert Thresholds

| Alert | Threshold | Action |
|-------|-----------|--------|
| Backup Age | > 24 hours | Check backup cron job |
| Slow Queries | > 10/sec | Analyze slow query log |
| Buffer Pool Hit | < 95% | Increase innodb_buffer_pool_size |
| Backup Size | > 10 GB | Review retention policy |
| Migration Time | > 30 seconds | Optimize schema changes |

---

## Troubleshooting

### Backup fails with "binary log not found"
```bash
# Enable binary logging
sudo vi /etc/mysql/my.cnf
# Add:
# [mysqld]
# log_bin = mysql-bin
# server-id = 1

sudo systemctl restart mysql
```

### Restore hangs or is very slow
```bash
# Use optimized restore with FK disabled
zstd -dc backup.sql.zst | mysql -u root -p -e "SET FOREIGN_KEY_CHECKS=0; USE chom; SOURCE /dev/stdin;"
```

### Migration validation fails
```bash
# Run with verbose output
php artisan migrate:dry-run --validate -vvv

# Check database connectivity
php artisan db:monitor --type=overview
```

### Out of disk space during backup
```bash
# Check backup directory size
du -sh storage/app/backups/

# Clean old backups
find storage/app/backups/ -name "*.sql*" -mtime +30 -delete

# Use higher compression
COMPRESSION=xz ./scripts/backup-incremental.sh
```

---

## Emergency Contacts

| Role | Contact | Escalation |
|------|---------|------------|
| Database Admin | DBA Team | 1st line |
| DevOps Lead | DevOps Team | 2nd line |
| CTO | Executive Team | 3rd line |

---

## Critical Procedures

### Disaster Recovery Checklist

- [ ] Identify backup restore point (latest full + incrementals)
- [ ] Notify stakeholders of recovery operation
- [ ] Enable maintenance mode: `php artisan down`
- [ ] Stop application services
- [ ] Restore database from backup
- [ ] Apply binary logs (if PITR needed)
- [ ] Verify data integrity
- [ ] Warm up database caches
- [ ] Test critical functionality
- [ ] Disable maintenance mode: `php artisan up`
- [ ] Monitor application performance
- [ ] Document incident and lessons learned

### Pre-Deployment Checklist

- [ ] Run migration dry-run: `php artisan migrate:dry-run --validate`
- [ ] Create full backup: `BACKUP_TYPE=full VERIFICATION=basic ./scripts/backup-incremental.sh`
- [ ] Verify backup completed successfully
- [ ] Check database size and capacity
- [ ] Review pending migrations
- [ ] Estimate migration duration
- [ ] Plan rollback procedure
- [ ] Notify team of deployment
- [ ] Enable maintenance mode
- [ ] Execute deployment
- [ ] Verify migration success
- [ ] Test critical functionality
- [ ] Disable maintenance mode

---

**Quick Reference Version:** 1.0
**Last Updated:** 2026-01-02
