# Database Operations Test Execution Checklist

## Pre-Test Preparation

### Environment Setup
- [ ] Database server running and accessible
- [ ] PHP 8.x installed and configured
- [ ] Laravel application environment configured (`.env` file present)
- [ ] Database credentials verified in `.env`
- [ ] Test user has appropriate database permissions (CREATE, DROP, SELECT, INSERT, etc.)
- [ ] Sufficient disk space available (minimum 2GB free, recommend 10GB)

### Optional Components
- [ ] Binary logging enabled (for incremental backup tests)
- [ ] zstd compression tool installed (recommended)
- [ ] Docker installed and running (for Docker volume tests)
- [ ] jq installed (for JSON parsing in reports)
- [ ] Grafana running (for dashboard validation)

### Backup Prerequisites
```bash
cd /home/calounx/repositories/mentat/chom
mkdir -p storage/app/backups
chmod 755 storage/app/backups
df -h  # Verify disk space
```

### Database Connectivity Test
```bash
cd /home/calounx/repositories/mentat/chom
php artisan db:monitor --type=overview
# Should show database connection successful
```

---

## Test Execution

### Option 1: Full Test Suite (Recommended)

```bash
cd /home/calounx/repositories/mentat
./tests/regression/database-operations-test.sh
```

**Expected Duration:** 5-15 minutes

**Success Indicators:**
- [ ] Script completes without errors
- [ ] Exit code 0
- [ ] Test report generated in `tests/reports/database/`
- [ ] ≥90% tests pass (14+ of 16)
- [ ] No critical failures

### Option 2: Quick Validation

```bash
cd /home/calounx/repositories/mentat
./tests/regression/run-database-tests.sh --quick
```

**Expected Duration:** 30-60 seconds

**Tests Run:**
- [ ] Database connectivity verified
- [ ] Backup system functional
- [ ] Migration system operational

### Option 3: Category-Specific Tests

#### Backup Tests Only
```bash
./tests/regression/run-database-tests.sh --backup
```
- [ ] Full backup with gzip
- [ ] Full backup with zstd
- [ ] Incremental backup (if binary logging enabled)

#### Migration Tests Only
```bash
./tests/regression/run-database-tests.sh --migration
```
- [ ] Migration dry-run validation
- [ ] Migration status check
- [ ] Rollback capability verified

#### Monitoring Tests Only
```bash
./tests/regression/run-database-tests.sh --monitoring
```
- [ ] Overview monitoring
- [ ] Query monitoring
- [ ] Table statistics
- [ ] JSON output

#### Performance Benchmarks
```bash
./tests/regression/run-database-tests.sh --performance
```
- [ ] Backup compression comparison
- [ ] Restore performance measurement
- [ ] Database size analysis
- [ ] JSON report generated

---

## Test Results Validation

### Review Test Report

```bash
# Find latest report
REPORT=$(ls -t tests/reports/database/database-test-report_*.md | head -1)

# View summary
cat "$REPORT" | head -50

# Check for failures
grep -i "FAIL" "$REPORT"

# View performance metrics
grep -A 10 "Performance Metrics" "$REPORT"
```

### Expected Results

#### Test Summary
- [ ] Total Tests: 16
- [ ] Passed: 14-16 (87-100%)
- [ ] Failed: 0
- [ ] Skipped: 0-2 (acceptable)

#### Individual Test Results

**Test 1: Full Backup Creation**
- [ ] Status: PASS
- [ ] Duration: <10s (for 100MB DB)
- [ ] Validations: ≥5/6 passed
- [ ] Backup file created and verified

**Test 2: Incremental Backup**
- [ ] Status: PASS or SKIP (if binary logging disabled)
- [ ] Duration: <5s
- [ ] Binary logs archived if enabled

**Test 3: Compression Algorithms**
- [ ] Status: PASS
- [ ] Duration: <60s
- [ ] All algorithms tested (gzip, bzip2, xz, zstd)
- [ ] Decompression tests passed

**Test 4: Backup Verification**
- [ ] Status: PASS
- [ ] Basic verification: file integrity check
- [ ] Full verification: test restore (if enabled)

**Test 5: Backup Restore**
- [ ] Status: PASS
- [ ] Duration: <30s (for 100MB DB)
- [ ] All tables restored
- [ ] Foreign keys intact

**Test 6: Point-in-Time Recovery**
- [ ] Status: PASS or SKIP
- [ ] Full + incremental backup workflow verified

**Test 7: Migration Dry-Run**
- [ ] Status: PASS
- [ ] Duration: <10s
- [ ] All 7 pre-checks executed
- [ ] Validation report generated

**Test 8: Migration Execution**
- [ ] Status: PASS
- [ ] Migration status command works
- [ ] Migrations table verified

**Test 9: Migration Rollback**
- [ ] Status: PASS
- [ ] Rollback command available
- [ ] Options verified (--step, --force, --pretend)

**Test 10: Database Monitor**
- [ ] Status: PASS
- [ ] All monitor types work (overview, queries, tables)
- [ ] JSON output valid
- [ ] Duration: <5s per type

**Test 11: Performance Benchmarks**
- [ ] Status: PASS
- [ ] Duration: <5 minutes
- [ ] JSON report generated
- [ ] All benchmarks completed

**Test 12: Grafana Dashboard**
- [ ] Status: PASS
- [ ] Dashboard JSON valid
- [ ] Panels configured
- [ ] Metrics defined

**Test 13: Docker Volume Backups**
- [ ] Status: PASS or SKIP (if not in Docker)
- [ ] Volume backup created
- [ ] Tarball valid

**Test 14: Retention Policy**
- [ ] Status: PASS
- [ ] Old backups cleaned up
- [ ] Retention enforced

**Test 15: Concurrent Operations**
- [ ] Status: PASS
- [ ] No deadlocks
- [ ] No corruption
- [ ] All operations completed

**Test 16: Large Database Handling**
- [ ] Status: PASS
- [ ] Backup completed (>100MB dataset)
- [ ] No memory errors
- [ ] Performance acceptable

### Performance Metrics Validation

- [ ] **backup_full_size:** Reasonable size (compressed)
- [ ] **backup_full_duration:** Within target (<10s for 100MB)
- [ ] **restore_duration:** Within target (<30s for 100MB)
- [ ] **compression_zstd_size:** Best compression ratio achieved

---

## Post-Test Actions

### Success Path (All Tests Pass)

- [ ] Review test report for any warnings
- [ ] Verify performance metrics meet targets
- [ ] Save baseline metrics for future comparison
- [ ] Schedule regular test execution
- [ ] Integrate into CI/CD pipeline

### Failure Path (Some Tests Fail)

#### 1. Identify Failures
```bash
# List failed tests
grep "FAIL" tests/reports/database/database-test-report_*.md
```

#### 2. Review Detailed Logs
```bash
# Check all test logs
ls -lah /tmp/*test*.log

# View specific failure log
cat /tmp/backup_test.log
cat /tmp/migrate_dryrun.log
```

#### 3. Debug Common Issues

**Database Connection Failures:**
```bash
# Verify .env configuration
cd /home/calounx/repositories/mentat/chom
grep "^DB_" .env

# Test connection manually
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1"
```

**Backup Failures:**
```bash
# Check disk space
df -h

# Verify permissions
ls -la storage/app/backups
chmod 755 storage/app/backups

# Test backup manually
BACKUP_TYPE=full COMPRESSION=gzip ./scripts/backup-incremental.sh
```

**Migration Failures:**
```bash
# Check migrations table
php artisan migrate:status

# Verify schema
php artisan db:monitor --type=overview

# Run dry-run with verbose output
php artisan migrate:dry-run --validate
```

#### 4. Re-run Failed Tests
```bash
# Re-run specific category
./tests/regression/run-database-tests.sh --backup    # For backup failures
./tests/regression/run-database-tests.sh --migration # For migration failures
```

---

## Performance Validation

### Compare Against Baselines

Reference: `PERFORMANCE-BASELINES.md`

#### Backup Performance

- [ ] Full backup (100MB): <3s (target), actual: _____s
- [ ] Compression ratio (zstd): >10:1 (target), actual: _____:1
- [ ] Incremental backup: <1s (target), actual: _____s

#### Restore Performance

- [ ] Standard restore: Baseline measured: _____s
- [ ] Optimized restore: <4s for 100MB (target), actual: _____s
- [ ] Speedup achieved: >30x (target), actual: _____x

#### Migration Performance

- [ ] Dry-run validation: <10s (target), actual: _____s
- [ ] Pre-checks execution: <5s (target), actual: _____s

#### Monitoring Performance

- [ ] Overview query: <500ms (target), actual: _____ms
- [ ] Query monitoring: <300ms (target), actual: _____ms
- [ ] Table statistics: <500ms (target), actual: _____ms

### Benchmark Results

```bash
# View latest benchmark results
cat storage/app/benchmarks/benchmark_*.json | jq '.'

# Extract specific metrics
jq -r '.results.backup_gzip_duration' storage/app/benchmarks/benchmark_*.json
jq -r '.results.restore_standard_duration' storage/app/benchmarks/benchmark_*.json
```

---

## Documentation

### Test Report Archive

- [ ] Test report saved: `tests/reports/database/database-test-report_TIMESTAMP.md`
- [ ] Report reviewed and understood
- [ ] Failures documented (if any)
- [ ] Performance metrics recorded

### Update Baseline (If Improved)

```bash
# Save current benchmark as new baseline
cp storage/app/benchmarks/benchmark_*.json \
   tests/regression/baselines/baseline_$(date +%Y%m).json

# Update PERFORMANCE-BASELINES.md with new targets
# Document improvements achieved
```

### Share Results

- [ ] Test results communicated to team
- [ ] Any failures or warnings addressed
- [ ] Performance improvements documented
- [ ] Next steps planned

---

## Maintenance Schedule

### Daily (Automated)

```bash
# Quick validation check
*/0 9 * * * /home/calounx/repositories/mentat/tests/regression/run-database-tests.sh --quick >> /var/log/db-tests-daily.log 2>&1
```

- [ ] Quick validation passes
- [ ] Logs reviewed
- [ ] Alerts checked

### Weekly (Manual)

```bash
# Full test suite
0 2 * * 0 /home/calounx/repositories/mentat/tests/regression/database-operations-test.sh >> /var/log/db-tests-weekly.log 2>&1
```

- [ ] Full test suite executed
- [ ] Test report reviewed
- [ ] Performance metrics compared to baseline
- [ ] Issues addressed

### Monthly (Comprehensive)

- [ ] Full test suite with large database
- [ ] Performance benchmarks run
- [ ] Baseline comparison and update
- [ ] Documentation review and update
- [ ] Test suite maintenance (update for new features)

### Before Deployments (Critical)

- [ ] Full test suite executed
- [ ] All tests pass (100% or acceptable skips)
- [ ] Migration dry-run successful
- [ ] Backup and restore verified
- [ ] Performance within targets
- [ ] Test report attached to deployment notes

---

## CI/CD Integration Checklist

### GitHub Actions

- [ ] Workflow file created: `.github/workflows/database-tests.yml`
- [ ] MySQL service configured
- [ ] PHP and extensions installed
- [ ] Test script executable in CI
- [ ] Test reports uploaded as artifacts
- [ ] Failure notifications configured

### GitLab CI

- [ ] Pipeline stage defined: `database-tests`
- [ ] MySQL service container configured
- [ ] Dependencies installed (mysql-client, zstd)
- [ ] Test artifacts preserved
- [ ] Pipeline notifications enabled

### Jenkins

- [ ] Job created: "Database Operations Tests"
- [ ] SCM polling configured
- [ ] Build triggers set
- [ ] Test execution script configured
- [ ] Post-build actions: archive reports, send notifications

---

## Troubleshooting Reference

### Common Issues Quick Reference

| Issue | Quick Fix |
|-------|-----------|
| "Database connection failed" | Check .env credentials |
| "Backup file not created" | Check disk space and permissions |
| "Binary logging not enabled" | Edit my.cnf, restart MySQL (optional) |
| "Docker volumes not found" | Normal if not in Docker (SKIP expected) |
| "Benchmark timed out" | Normal for large DBs, run manually |
| "Migration validation failed" | Check database schema conflicts |
| "Permission denied" | chmod 755 storage/app/backups |
| "zstd not found" | Install: apt-get install zstd |

### Get Detailed Help

```bash
# View testing guide
cat tests/regression/DATABASE-TESTING-GUIDE.md | less

# View performance baselines
cat tests/regression/PERFORMANCE-BASELINES.md | less

# View test summary
cat tests/regression/DATABASE-TEST-SUMMARY.md | less
```

---

## Final Validation

### Before Marking Complete

- [ ] Test suite executed successfully
- [ ] Test report generated and reviewed
- [ ] ≥90% tests passed
- [ ] No critical failures
- [ ] Performance meets targets
- [ ] Documentation read and understood
- [ ] Next steps planned (schedule, CI/CD integration)

### Success Criteria Met

- [ ] All backup operations functional
- [ ] Migration system validated
- [ ] Monitoring queries working
- [ ] Performance within 30x improvement target
- [ ] No data loss or corruption in any test
- [ ] Production-ready status confirmed

---

## Sign-Off

**Test Execution Date:** _________________

**Executed By:** _________________

**Results Summary:**
- Total Tests: _____
- Passed: _____
- Failed: _____
- Skipped: _____

**Performance:**
- Backup (100MB): _____s (target: <3s)
- Restore (100MB): _____s (target: <4s)
- Speedup: _____x (target: >30x)

**Status:** ☐ PASS ☐ PASS WITH WARNINGS ☐ FAIL

**Notes:**
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

**Approved for Production:** ☐ YES ☐ NO ☐ CONDITIONAL

**Next Review Date:** _________________

---

**Checklist Version:** 1.0.0
**Last Updated:** 2026-01-02
