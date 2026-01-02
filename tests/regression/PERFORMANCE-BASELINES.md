# Database Performance Baselines & Targets

## Overview

This document defines expected performance baselines for database operations in the CHOM application. Use these benchmarks to validate optimizations and detect performance degradation.

## Target: 30x Performance Improvement

The optimization goal is to achieve **30x faster** database operations compared to unoptimized baseline through:

1. Strategic indexing
2. Query optimization
3. Caching strategies
4. Connection pooling
5. Backup/restore optimizations

## Baseline Metrics

### 1. Backup Performance

#### Full Backup

| Database Size | Unoptimized | Optimized | Target Speedup |
|---------------|-------------|-----------|----------------|
| 10 MB | 5s | 1s | 5x |
| 100 MB | 60s | 3s | 20x |
| 1 GB | 600s | 20s | 30x |
| 10 GB | 6000s | 200s | 30x |

**Optimizations:**
- `--single-transaction` (no table locks, MVCC)
- `--quick` (streaming, no buffering)
- `--extended-insert` (multi-row inserts)
- Parallel compression (zstd level 3)
- Direct pipe to compression

**Command:**
```bash
mysqldump --single-transaction --quick --extended-insert | zstd -3
```

#### Incremental Backup (Binary Logs)

| Binlog Size | Duration | Target |
|-------------|----------|--------|
| 1 MB | 0.5s | <1s |
| 10 MB | 2s | <3s |
| 100 MB | 15s | <20s |

**Optimizations:**
- Archive only rotated logs
- Compress with zstd
- Parallel archiving

#### Compression Comparison

100 MB database backup:

| Algorithm | Time | Size | Ratio | Throughput |
|-----------|------|------|-------|------------|
| none | 3s | 100 MB | 1:1 | 33 MB/s |
| gzip -6 | 8s | 10 MB | 10:1 | 12.5 MB/s |
| bzip2 -9 | 15s | 8 MB | 12.5:1 | 6.7 MB/s |
| xz -6 | 30s | 5 MB | 20:1 | 3.3 MB/s |
| **zstd -3** | **4s** | **7 MB** | **14:1** | **25 MB/s** |

**Recommendation:** Use `zstd -3` for best speed/compression balance.

### 2. Restore Performance

#### Restore from Backup

| Database Size | Standard | Optimized | Speedup |
|---------------|----------|-----------|---------|
| 10 MB | 10s | 0.5s | 20x |
| 100 MB | 120s | 4s | **30x** |
| 1 GB | 1200s | 40s | **30x** |
| 10 GB | 12000s | 400s | **30x** |

**Optimizations Applied:**

```sql
SET FOREIGN_KEY_CHECKS=0;    -- Skip FK validation during load
SET UNIQUE_CHECKS=0;          -- Skip unique constraint checks
SET AUTOCOMMIT=0;             -- Batch commits
SET sql_log_bin=0;            -- Skip binary logging (if safe)
```

**Restore Command:**
```bash
zstdcat backup.sql.zst | mysql --init-command="SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0; SET AUTOCOMMIT=0"
```

**Post-Restore:**
```sql
SET FOREIGN_KEY_CHECKS=1;
SET UNIQUE_CHECKS=1;
COMMIT;
```

#### Point-in-Time Recovery (PITR)

| Operation | Duration | Target |
|-----------|----------|--------|
| Full restore | 4s | <10s |
| Binlog replay (1 hour) | 30s | <60s |
| **Total PITR** | **34s** | **<70s** |

### 3. Migration Performance

#### Schema Migrations

| Operation | Tables | Unoptimized | Optimized | Speedup |
|-----------|--------|-------------|-----------|---------|
| Add column | 10 | 60s | 5s | 12x |
| Add index | 10 | 180s | 15s | 12x |
| Foreign key | 5 | 120s | 8s | 15x |
| **Combined** | **20** | **300s** | **10s** | **30x** |

**Optimizations:**
- Online DDL (MySQL 5.7+)
- Algorithm=INPLACE when possible
- Lock=NONE for non-blocking changes
- Batched alterations

**Migration Command:**
```sql
ALTER TABLE users
  ADD COLUMN last_login TIMESTAMP,
  ALGORITHM=INPLACE,
  LOCK=NONE;
```

#### Migration Validation (Dry-Run)

| Validation | Target Duration |
|------------|-----------------|
| Pre-checks (7 validations) | <5s |
| Schema preview | <3s |
| Impact analysis | <2s |
| **Total dry-run** | **<10s** |

### 4. Query Performance

#### Slow Query Thresholds

| Query Type | Unoptimized | Optimized | Target |
|------------|-------------|-----------|--------|
| Simple SELECT | 100ms | 3ms | <5ms |
| JOIN (2 tables) | 500ms | 15ms | <20ms |
| JOIN (5 tables) | 2000ms | 60ms | <100ms |
| Aggregation | 1500ms | 50ms | <80ms |
| Full-text search | 3000ms | 100ms | <150ms |

**Key Optimizations:**
- Strategic indexes on foreign keys
- Covering indexes for frequent queries
- Query result caching
- Connection pooling
- Prepared statements

#### Index Performance

| Operation | With Index | Without Index | Speedup |
|-----------|------------|---------------|---------|
| WHERE clause | 3ms | 500ms | 166x |
| ORDER BY | 5ms | 1200ms | 240x |
| JOIN | 10ms | 3000ms | 300x |
| GROUP BY | 15ms | 2500ms | 166x |

### 5. Monitoring Queries

#### Database Monitor Performance

| Monitor Type | Query Count | Duration | Target |
|--------------|-------------|----------|--------|
| overview | 5 | 200ms | <500ms |
| queries | 3 | 150ms | <300ms |
| tables | 2 | 300ms | <500ms |
| indexes | 4 | 400ms | <800ms |
| locks | 2 | 100ms | <200ms |

**Watch Mode:** Refresh every 5s without performance degradation.

### 6. Concurrent Operations

#### Parallel Operation Performance

| Scenario | Operations | Duration | Locks | Issues |
|----------|------------|----------|-------|--------|
| Backup + Monitor | 2 | 5s | 0 | None |
| Backup + Queries | 10 | 6s | 0 | None |
| Migration + Monitor | 2 | 12s | 1 | None |
| Multiple backups | 3 | 15s | 0 | None |

**Target:** Zero deadlocks, zero data corruption.

### 7. Large Database Handling

#### Scalability Targets

| Database Size | Backup | Restore | Migration | Memory |
|---------------|--------|---------|-----------|--------|
| 100 MB | 3s | 4s | 10s | 100 MB |
| 1 GB | 20s | 40s | 30s | 200 MB |
| 10 GB | 200s | 400s | 120s | 500 MB |
| 100 GB | 2000s | 4000s | 600s | 1 GB |

**Memory Efficiency:**
- Streaming operations (no full buffering)
- Constant memory usage regardless of database size
- No temporary file explosion

## Performance Testing Methodology

### How to Measure

#### 1. Backup Performance

```bash
# Measure full backup
time (BACKUP_TYPE=full COMPRESSION=zstd \
  ./scripts/backup-incremental.sh)

# Expected: <3s for 100MB database
```

#### 2. Restore Performance

```bash
# Unoptimized (baseline)
time (zstdcat backup.sql.zst | mysql test_db)

# Optimized
time (zstdcat backup.sql.zst | mysql test_db \
  --init-command="SET FOREIGN_KEY_CHECKS=0; SET UNIQUE_CHECKS=0")

# Calculate speedup: baseline_time / optimized_time
```

#### 3. Query Performance

```sql
-- Enable profiling
SET profiling = 1;

-- Run query
SELECT * FROM users WHERE email = 'test@example.com';

-- Show timing
SHOW PROFILES;

-- Expected: <5ms with index
```

#### 4. Migration Performance

```bash
# Dry-run timing
time (php artisan migrate:dry-run --validate)

# Expected: <10s
```

### Benchmark Script

Use the automated benchmark:

```bash
cd /home/calounx/repositories/mentat/chom
./scripts/benchmark-database.sh
```

**Expected Output:**
- JSON report in `storage/app/benchmarks/`
- Comparison of all compression algorithms
- Restore performance metrics
- Migration validation timing

## Performance Degradation Alerts

### Alert Thresholds

Set up monitoring alerts for:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Backup duration | >10s (100MB) | Investigate |
| Restore duration | >15s (100MB) | Critical |
| Slow queries | >100ms | Review indexes |
| Query rate | >1000 QPS | Scale up |
| Connection pool | >80% full | Increase pool |
| Table fragmentation | >1GB free | OPTIMIZE TABLE |

### Grafana Alerts

Configure in `config/grafana/dashboards/database-monitoring.json`:

```json
{
  "alert": {
    "name": "Slow Query Rate High",
    "conditions": [
      {
        "evaluator": {
          "params": [10],
          "type": "gt"
        },
        "query": {
          "params": ["B", "5m", "now"]
        },
        "reducer": {
          "type": "avg"
        }
      }
    ]
  }
}
```

## Optimization Strategies

### Quick Wins (1-5x improvement)

1. **Add missing indexes**
   ```sql
   CREATE INDEX idx_email ON users(email);
   ```

2. **Use query cache**
   ```sql
   SET GLOBAL query_cache_size = 268435456;  -- 256MB
   ```

3. **Optimize table structure**
   ```sql
   OPTIMIZE TABLE large_table;
   ```

### Medium Effort (5-15x improvement)

1. **Implement connection pooling**
   - Use persistent connections
   - Pool size: 10-50 connections

2. **Add covering indexes**
   ```sql
   CREATE INDEX idx_covering ON users(email, name, created_at);
   ```

3. **Partition large tables**
   ```sql
   ALTER TABLE events PARTITION BY RANGE (YEAR(created_at));
   ```

### Advanced (15-30x improvement)

1. **Implement Redis caching**
   - Cache expensive queries for 5-60 minutes
   - Use cache tags for invalidation

2. **Read replicas**
   - Separate read/write operations
   - Load balance across replicas

3. **Query optimization**
   - Rewrite subqueries as JOINs
   - Use EXPLAIN to identify issues
   - Eliminate N+1 queries

## Regression Detection

### Automated Performance Testing

Run benchmarks before and after changes:

```bash
# Baseline
./scripts/benchmark-database.sh > baseline.json

# After changes
./scripts/benchmark-database.sh > after.json

# Compare (requires jq)
BASELINE_BACKUP=$(jq -r '.results.backup_gzip_duration' baseline.json)
AFTER_BACKUP=$(jq -r '.results.backup_gzip_duration' after.json)

if (( $(echo "$AFTER_BACKUP > $BASELINE_BACKUP * 1.2" | bc -l) )); then
  echo "WARNING: Backup performance degraded by >20%"
fi
```

### CI/CD Integration

```yaml
# .github/workflows/performance-tests.yml
- name: Run Performance Tests
  run: |
    ./scripts/benchmark-database.sh

    # Fail if backup takes >10s
    DURATION=$(jq -r '.results.backup_gzip_duration' storage/app/benchmarks/benchmark_*.json)
    if (( $(echo "$DURATION > 10" | bc -l) )); then
      echo "Performance regression detected!"
      exit 1
    fi
```

## Historical Performance Tracking

### Benchmark History

Track performance over time:

```bash
# Store benchmarks with timestamps
mkdir -p benchmarks/history
cp storage/app/benchmarks/benchmark_*.json benchmarks/history/

# Generate trend report
./scripts/performance-trends.sh
```

### Expected Trends

- **Backup time:** Should remain constant or improve with optimization
- **Restore time:** Linear growth with database size
- **Query time:** Constant with proper indexes
- **Migration time:** Linear with table count

## Validation Checklist

Before considering optimizations successful:

- [ ] Backup duration meets target (30x improvement)
- [ ] Restore duration meets target (30x improvement)
- [ ] No performance regression in queries
- [ ] All tests pass (100% or >90%)
- [ ] No data corruption in any test
- [ ] Concurrent operations work correctly
- [ ] Large database handling (>1GB) verified
- [ ] Migration dry-run completes <10s
- [ ] Monitoring queries <500ms
- [ ] Zero deadlocks under load

## Continuous Monitoring

### Daily Checks

```bash
# Run quick performance check
php artisan db:monitor --type=overview

# Check slow query log
tail -100 /var/log/mysql/slow-query.log
```

### Weekly Benchmarks

```bash
# Full benchmark suite
./scripts/benchmark-database.sh

# Compare to baseline
diff storage/app/benchmarks/benchmark_latest.json benchmarks/baseline.json
```

### Monthly Reviews

- Review performance trends
- Update baselines if improvements made
- Identify new optimization opportunities
- Plan capacity upgrades if needed

## References

- MySQL Performance Tuning: https://dev.mysql.com/doc/refman/8.0/en/optimization.html
- Laravel Query Optimization: https://laravel.com/docs/queries
- Database Indexing Strategies: https://use-the-index-luke.com/
- Backup Best Practices: https://dev.mysql.com/doc/refman/8.0/en/backup-methods.html

---

**Last Updated:** 2026-01-02
**Version:** 1.0.0
**Target Achievement:** 30x Performance Improvement
