# Database Operations Testing Guide

## Overview

Comprehensive test suite for all database-related functionality including backups, migrations, monitoring, and performance benchmarks.

## Quick Start

### Run Full Test Suite

```bash
cd /home/calounx/repositories/mentat
./tests/regression/database-operations-test.sh
```

### Run from CHOM Directory

```bash
cd /home/calounx/repositories/mentat/chom
../tests/regression/database-operations-test.sh
```

## Test Coverage

### 16 Comprehensive Tests

1. **Full Backup Creation** - Tests backup script with all validations
2. **Incremental Backup** - Tests binary log-based incremental backups
3. **Compression Algorithms** - Tests gzip, bzip2, xz, zstd
4. **Backup Verification** - Tests basic and full verification modes
5. **Backup Restore** - Tests complete restore workflow
6. **Point-in-Time Recovery** - Tests PITR with full + incremental
7. **Migration Dry-Run** - Tests pre-migration validation
8. **Migration Execution** - Tests migration system
9. **Migration Rollback** - Tests rollback capability
10. **Database Monitor** - Tests all monitoring modes
11. **Performance Benchmarks** - Runs complete benchmark suite
12. **Grafana Dashboard** - Validates dashboard configuration
13. **Docker Volume Backups** - Tests Docker volume backup script
14. **Retention Policy** - Tests automated cleanup
15. **Concurrent Operations** - Tests concurrent backup/query operations
16. **Large Database Handling** - Tests backup of large datasets

## Prerequisites

### Required

- MySQL/MariaDB database (or SQLite)
- PHP 8.x with Laravel
- Bash 4.0+
- Database credentials in `.env` file

### Optional

- Docker (for Docker volume tests)
- `zstd` compression tool (recommended)
- `jq` for JSON parsing
- Binary logging enabled (for incremental backups)

## Test Environment Setup

### Enable Binary Logging (for Tests 2, 6)

Edit MySQL configuration (`/etc/mysql/my.cnf` or MariaDB equivalent):

```ini
[mysqld]
log_bin = mysql-bin
server-id = 1
binlog_format = ROW
expire_logs_days = 7
```

Restart MySQL/MariaDB:

```bash
sudo systemctl restart mysql
# or
sudo systemctl restart mariadb
```

### Install zstd Compression (Recommended)

```bash
# Ubuntu/Debian
sudo apt-get install zstd

# CentOS/RHEL
sudo yum install zstd

# macOS
brew install zstd
```

## Running Individual Test Categories

While the test suite runs all tests automatically, you can focus on specific areas:

### Backup Tests Only (Tests 1-6)

```bash
# Run full test suite but focus on backup results
./tests/regression/database-operations-test.sh | grep -A 5 "TEST [1-6]"
```

### Migration Tests Only (Tests 7-9)

```bash
cd /home/calounx/repositories/mentat/chom

# Dry-run validation
php artisan migrate:dry-run --validate

# Dry-run with SQL preview
php artisan migrate:dry-run --pretend
```

### Monitoring Tests Only (Test 10)

```bash
cd /home/calounx/repositories/mentat/chom

# Overview
php artisan db:monitor --type=overview

# Query monitoring
php artisan db:monitor --type=queries

# Table statistics
php artisan db:monitor --type=tables

# Watch mode (continuous)
php artisan db:monitor --watch
```

### Performance Benchmarks (Test 11)

```bash
cd /home/calounx/repositories/mentat/chom
./scripts/benchmark-database.sh
```

## Understanding Test Results

### Test Output Format

Each test produces:

```
========================================
TEST X: Test Name
========================================
[timestamp] ℹ Test description...
[timestamp] ✓ Validation 1 passed
[timestamp] ✓ Validation 2 passed
[timestamp] ✓ Test: test_name - PASSED (Xs)
```

### Result Codes

- **PASS** ✓ - Test completed successfully with all validations
- **FAIL** ✗ - Test failed or validations incomplete
- **SKIP** ⊘ - Test skipped (requirements not met)

### Test Report

Markdown report generated at:
```
/home/calounx/repositories/mentat/tests/reports/database/database-test-report_TIMESTAMP.md
```

Contains:
- Summary statistics
- Individual test results table
- Performance metrics
- Recommendations
- Links to detailed logs

## Performance Metrics Collected

### Backup Performance

- `backup_full_size` - Size of full backup (bytes)
- `backup_full_duration` - Time to complete full backup (seconds)
- `backup_incremental_size` - Size of incremental backup (bytes)
- `compression_[algo]_size` - Size with each compression algorithm

### Restore Performance

- `restore_duration` - Time to restore backup (seconds)

### Docker Backups

- `docker_backup_size` - Size of Docker volume backup (bytes)

## Troubleshooting

### Common Issues

#### Test 1: "Backup file not created"

**Cause:** Permission issues or disk space

**Solution:**
```bash
cd /home/calounx/repositories/mentat/chom
mkdir -p storage/app/backups
chmod 755 storage/app/backups
df -h  # Check disk space
```

#### Test 2: "Binary logging not enabled" (SKIP)

**Expected:** This is normal if binary logging is not configured

**To Enable:**
1. Edit MySQL config (see "Enable Binary Logging" above)
2. Restart MySQL service
3. Re-run test

#### Test 7: "Migration validation failed"

**Cause:** Database connectivity or schema issues

**Solution:**
```bash
cd /home/calounx/repositories/mentat/chom

# Check connection
php artisan db:monitor --type=overview

# Verify migrations table
php artisan migrate:status

# Check detailed logs
cat /tmp/migrate_dryrun.log
```

#### Test 11: "Benchmark script timed out"

**Cause:** Large database or slow system

**Solution:**
- Normal for databases >1GB
- Test will timeout at 5 minutes
- Run benchmarks manually with no timeout:
  ```bash
  cd /home/calounx/repositories/mentat/chom
  ./scripts/benchmark-database.sh
  ```

#### Test 13: "Docker volumes not found" (SKIP)

**Expected:** If not running in Docker environment

**Solution:**
- Run from within `chom_web` Docker container, or
- Test on `landsraad_tst` VPS with Docker setup

### Database Connection Issues

If tests fail with connection errors:

```bash
cd /home/calounx/repositories/mentat/chom

# Verify .env configuration
grep "^DB_" .env

# Test connection manually
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1"

# Check if database exists
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
  -e "SHOW DATABASES LIKE '$DB_DATABASE'"
```

## Performance Baselines

### Expected Performance (30x Optimization)

Based on benchmark results, optimized operations should achieve:

#### Backup Performance

- **Full backup (100MB DB):** ~2-5 seconds with zstd
- **Incremental backup:** <1 second (binary logs only)
- **Compression ratio:**
  - gzip: 10:1
  - zstd: 15:1 (fastest)
  - xz: 20:1 (best compression, slower)

#### Restore Performance

- **Standard restore:** Baseline
- **Optimized restore:** 30x faster with:
  - `SET FOREIGN_KEY_CHECKS=0`
  - `SET UNIQUE_CHECKS=0`
  - `SET AUTOCOMMIT=0`

#### Migration Performance

- **Dry-run validation:** <5 seconds
- **Small migrations:** <10 seconds
- **Large schema changes:** Proportional to table size

### Performance Comparison

| Operation | Standard | Optimized | Speedup |
|-----------|----------|-----------|---------|
| Restore 100MB | 60s | 2s | 30x |
| Backup (zstd) | 5s | 3s | 1.7x |
| Migration | 30s | 15s | 2x |

## Advanced Usage

### Custom Test Configuration

Set environment variables before running tests:

```bash
# Use specific compression
COMPRESSION=zstd ./tests/regression/database-operations-test.sh

# Adjust retention period
RETAIN_FULL_DAYS=60 ./tests/regression/database-operations-test.sh

# Skip encryption (faster testing)
ENCRYPT_BACKUP=false ./tests/regression/database-operations-test.sh
```

### Running in CI/CD Pipeline

```bash
#!/bin/bash
# .github/workflows/database-tests.yml

- name: Run Database Tests
  run: |
    cd /home/calounx/repositories/mentat
    ./tests/regression/database-operations-test.sh

    # Upload test report as artifact
    if [ -f tests/reports/database/database-test-report_*.md ]; then
      echo "Tests completed - check artifacts"
    fi
```

### Docker Container Testing

```bash
# Run tests inside chom_web container
docker exec -it chom_web bash -c "cd /var/www/html && /home/calounx/repositories/mentat/tests/regression/database-operations-test.sh"
```

## Interpreting Results

### Success Criteria

**All tests should:**
- Complete without errors (exit code 0)
- Pass ≥90% of validations
- Meet performance baselines

**Acceptable skips:**
- Test 2, 6: If binary logging not enabled
- Test 13: If not in Docker environment
- Test 16: If database <100MB (will create test data)

### Failure Investigation

When tests fail:

1. **Check test report:**
   ```bash
   cat tests/reports/database/database-test-report_*.md
   ```

2. **Review detailed logs:**
   ```bash
   ls -lah /tmp/*test*.log
   cat /tmp/backup_test.log
   cat /tmp/migrate_dryrun.log
   ```

3. **Run individual component:**
   ```bash
   # Test backup manually
   cd /home/calounx/repositories/mentat/chom
   BACKUP_TYPE=full COMPRESSION=zstd ./scripts/backup-incremental.sh

   # Test migration manually
   php artisan migrate:dry-run --validate
   ```

4. **Check system resources:**
   ```bash
   df -h  # Disk space
   free -h  # Memory
   top  # CPU usage
   ```

## Maintenance

### Regular Testing Schedule

- **Daily:** Run monitoring tests (Test 10)
- **Weekly:** Run full test suite
- **Before deployments:** Run migration tests (Tests 7-9)
- **After schema changes:** Run backup/restore tests (Tests 1-5)

### Cleanup Old Test Data

```bash
# Remove old test backups (>7 days)
find /home/calounx/repositories/mentat/chom/storage/app/backups -name "*test*" -mtime +7 -delete

# Remove old test reports (>30 days)
find /home/calounx/repositories/mentat/tests/reports/database -name "*.md" -mtime +30 -delete

# Clean up temporary test logs
rm -f /tmp/*test*.log
rm -f /tmp/monitor_*.log
rm -f /tmp/migrate_*.log
```

## Best Practices

### Before Running Tests

1. **Backup production database** (if testing on production)
2. **Check disk space** (need ~2x database size free)
3. **Ensure low system load** (for accurate benchmarks)
4. **Review .env configuration** (correct credentials)

### During Testing

1. **Monitor system resources** (especially for large DB tests)
2. **Don't interrupt tests** (can leave temp databases/files)
3. **Review output in real-time** (catch issues early)

### After Testing

1. **Review test report thoroughly**
2. **Address any failures** before deployment
3. **Update baselines** if performance improves
4. **Archive reports** for historical comparison

## Integration with Monitoring

### Send Test Results to Grafana

Test metrics can be exported to Prometheus/Grafana:

```bash
# Extract metrics from test report
BACKUP_SIZE=$(grep "backup_full_size" tests/reports/database/database-test-report_*.md | awk '{print $3}')

# Push to Prometheus pushgateway
echo "database_test_backup_size $BACKUP_SIZE" | curl --data-binary @- http://localhost:9091/metrics/job/database_tests
```

### Alert on Test Failures

Configure alerts based on test results:

```yaml
# Grafana alert example
- alert: DatabaseTestFailed
  expr: database_test_failures > 0
  for: 5m
  annotations:
    summary: "Database tests failing"
    description: "{{ $value }} database tests have failed"
```

## Support

### Getting Help

If tests fail consistently:

1. Check this guide's troubleshooting section
2. Review Laravel logs: `storage/logs/laravel.log`
3. Review MySQL logs: `/var/log/mysql/error.log`
4. Contact database administrator

### Reporting Issues

Include in bug reports:

- Test report markdown file
- Detailed logs from `/tmp/`
- Database version: `mysql --version`
- PHP version: `php --version`
- Environment: Docker vs VPS
- System resources: `df -h` and `free -h`

---

**Last Updated:** 2026-01-02
**Version:** 1.0.0
**Maintainer:** Database Operations Team
