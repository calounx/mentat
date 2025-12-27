# Phase 3: Loki Configuration Migration Guide

**Version:** Loki 2.9.3 → 3.6.3

This document provides the exact configuration changes required for the Loki upgrade.

---

## Current Configuration Analysis

**File:** `/home/calounx/repositories/mentat/observability-stack/loki/loki-config.yaml`

### Schema Configuration (NO CHANGES REQUIRED)

**Current:**
```yaml
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb          # ✓ Recommended for Loki 3.x
      object_store: filesystem
      schema: v13          # ✓ Required for Loki 3.x
      index:
        prefix: index_
        period: 24h
```

**Status:** Already using recommended v13 schema with TSDB indexing.

**Action:** NONE - Configuration compatible with Loki 3.x.

---

## Required Configuration Changes

### 1. Remove Deprecated table_manager

**Reason:** `table_manager` is deprecated in Loki 3.x in favor of `compactor`.

**Current Configuration:**
```yaml
table_manager:
  retention_deletes_enabled: true
  retention_period: 360h  # 15 days
```

**Action:** DELETE entire `table_manager` section.

**Replacement:** Already configured in `compactor` section:
```yaml
compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 10m
  retention_enabled: true           # Replaces table_manager.retention_deletes_enabled
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_store: filesystem
```

### 2. Add Label Limit Enforcement (RECOMMENDED)

**Reason:** Loki 3.4+ enforces maximum 15 labels per series (down from 30).

**Current Configuration:**
```yaml
limits_config:
  retention_period: 360h  # 15 days
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb
  reject_old_samples: true
  reject_old_samples_max_age: 168h  # 7 days
```

**Recommended Addition:**
```yaml
limits_config:
  retention_period: 360h
  max_label_names_per_series: 15  # ADD THIS LINE - Enforce v3.x default
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb
  reject_old_samples: true
  reject_old_samples_max_age: 168h
```

### 3. Optional: Disable Structured Metadata (if not needed)

**Reason:** Structured metadata enabled by default in Loki 3.x, increases index size.

**Only add if you don't plan to use OTLP or structured metadata:**

```yaml
limits_config:
  retention_period: 360h
  max_label_names_per_series: 15
  allow_structured_metadata: false  # OPTIONAL: Add to disable
  ingestion_rate_mb: 10
  # ... rest of config
```

**Recommendation:** Leave enabled (default) for future compatibility.

---

## Configuration Diff

**File:** `/etc/loki/loki-config.yaml`

```diff
--- loki-config.yaml (2.9.3)
+++ loki-config.yaml (3.6.3)
@@ -69,6 +69,7 @@

 limits_config:
   retention_period: 360h  # 15 days
+  max_label_names_per_series: 15
   ingestion_rate_mb: 10
   ingestion_burst_size_mb: 20
   max_streams_per_user: 10000
@@ -82,10 +83,6 @@
       enabled: true
       max_size_mb: 500

-table_manager:
-  retention_deletes_enabled: true
-  retention_period: 360h  # 15 days
-
 analytics:
   reporting_enabled: false
```

---

## Updated Configuration File (Complete)

**File:** `/etc/loki/loki-config.yaml` (Loki 3.6.3)

```yaml
# Loki Configuration
# Optimized for single-node deployment with 15-day retention
# Version: Loki 3.6.3

auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ingester:
  wal:
    enabled: true
    dir: /var/lib/loki/wal
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 1h
  max_chunk_age: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s

storage_config:
  tsdb_shipper:
    active_index_directory: /var/lib/loki/tsdb-index
    cache_location: /var/lib/loki/tsdb-cache
  filesystem:
    directory: /var/lib/loki/chunks

compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_store: filesystem

limits_config:
  retention_period: 360h  # 15 days
  max_label_names_per_series: 15  # Loki 3.x default (enforced)
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 10000
  max_line_size: 256kb
  reject_old_samples: true
  reject_old_samples_max_age: 168h  # 7 days

chunk_store_config:
  chunk_cache_config:
    embedded_cache:
      enabled: true
      max_size_mb: 500

analytics:
  reporting_enabled: false
```

---

## Migration Procedure

### Step 1: Backup Current Configuration

```bash
sudo cp /etc/loki/loki-config.yaml /etc/loki/loki-config.yaml.2.9.3.bak
```

### Step 2: Edit Configuration

```bash
sudo nano /etc/loki/loki-config.yaml
```

**Changes to make:**

1. **ADD** `max_label_names_per_series: 15` under `limits_config`
2. **DELETE** entire `table_manager` section (lines 84-86 in original file)
3. Save and exit (Ctrl+O, Enter, Ctrl+X)

### Step 3: Validate Configuration

```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('/etc/loki/loki-config.yaml'))"

# Verify required fields present
grep -q "schema: v13" /etc/loki/loki-config.yaml && echo "✓ Schema v13"
grep -q "store: tsdb" /etc/loki/loki-config.yaml && echo "✓ TSDB"
grep -q "retention_enabled: true" /etc/loki/loki-config.yaml && echo "✓ Retention"
grep -q "max_label_names_per_series: 15" /etc/loki/loki-config.yaml && echo "✓ Label limit"

# Verify deprecated fields removed
! grep -q "table_manager" /etc/loki/loki-config.yaml && echo "✓ table_manager removed"

# Compare with backup
diff -u /etc/loki/loki-config.yaml.2.9.3.bak /etc/loki/loki-config.yaml
```

### Step 4: Test Configuration (After Loki 3.6.3 Upgrade)

```bash
# Start Loki with new config
sudo systemctl start loki

# Check for configuration errors in logs
sudo journalctl -u loki -n 50 --no-pager | grep -i "config"

# Verify health
curl -s http://localhost:3100/ready | jq
```

---

## Rollback Configuration

If you need to rollback to Loki 2.9.3:

```bash
# Restore original configuration
sudo cp /etc/loki/loki-config.yaml.2.9.3.bak /etc/loki/loki-config.yaml

# Restart Loki
sudo systemctl restart loki
```

---

## Promtail Configuration (NO CHANGES)

Promtail configuration is **backward compatible** between 2.9.3 and 3.6.3.

**No configuration migration required** for Promtail.

**Validation:**

```bash
# Verify Promtail config still valid for 3.6.3
grep -A 5 "clients:" /etc/promtail/promtail.yaml

# Expected structure (no changes needed):
# clients:
#   - url: http://loki-server:3100/loki/api/v1/push
#     basic_auth:
#       username: <username>
#       password: <password>
```

---

## Configuration Verification Checklist

After migration, verify:

- [ ] `schema: v13` present in `schema_config`
- [ ] `store: tsdb` present in `schema_config`
- [ ] `max_label_names_per_series: 15` present in `limits_config`
- [ ] `table_manager` section removed
- [ ] `compactor.retention_enabled: true` present
- [ ] `analytics.reporting_enabled: false` present
- [ ] YAML syntax valid (no parse errors)
- [ ] Loki starts without errors
- [ ] Health check returns `ready`
- [ ] Query functionality works

---

## Troubleshooting Configuration Issues

### Error: "unknown field: table_manager"

**Cause:** `table_manager` not removed from config.

**Solution:**
```bash
# Remove table_manager section
sudo sed -i '/^table_manager:/,/^$/d' /etc/loki/loki-config.yaml
sudo systemctl restart loki
```

### Error: "max_label_names_per_series must be positive"

**Cause:** Invalid value for `max_label_names_per_series`.

**Solution:**
```bash
# Ensure value is positive integer (15 recommended)
grep "max_label_names_per_series" /etc/loki/loki-config.yaml
# Should show: max_label_names_per_series: 15
```

### Error: "schema v13 requires store: tsdb"

**Cause:** Mismatched schema and store configuration.

**Solution:**
```bash
# Verify schema_config
grep -A 5 "schema_config:" /etc/loki/loki-config.yaml
# Must have both:
#   store: tsdb
#   schema: v13
```

---

## Configuration Tuning (Optional)

### For High-Volume Environments

If ingesting > 1GB/day:

```yaml
limits_config:
  ingestion_rate_mb: 50           # Increase from 10
  ingestion_burst_size_mb: 100    # Increase from 20
  max_streams_per_user: 20000     # Increase from 10000

chunk_store_config:
  chunk_cache_config:
    embedded_cache:
      max_size_mb: 1024           # Increase from 500
```

### For Low-Memory Systems

If Loki using > 2GB RAM:

```yaml
query_range:
  results_cache:
    cache:
      embedded_cache:
        max_size_mb: 50           # Reduce from 100

chunk_store_config:
  chunk_cache_config:
    embedded_cache:
      max_size_mb: 256            # Reduce from 500

limits_config:
  max_streams_per_user: 5000      # Reduce from 10000
```

### For Faster Retention Enforcement

```yaml
compactor:
  compaction_interval: 5m         # Reduce from 10m
  retention_delete_delay: 1h      # Reduce from 2h
```

---

## References

- [Loki Configuration Reference](https://grafana.com/docs/loki/latest/configure/)
- [Schema Configuration](https://grafana.com/docs/loki/latest/operations/storage/schema/)
- [Loki Upgrade Guide](https://grafana.com/docs/loki/latest/setup/upgrade/)
- [Retention Configuration](https://grafana.com/docs/loki/latest/operations/storage/retention/)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-15
**Configuration Version:** Loki 3.6.3
