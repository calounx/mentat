# CHOM-STORAGE Architecture Design Document

## Executive Summary

This document defines the comprehensive architecture for CHOM-STORAGE - a distributed, scalable storage layer for the CHOM multi-tenant WordPress/PHP hosting platform. The design prioritizes **PoC-appropriate simplicity** while maintaining a **clear path to production scale**, supporting 2 hosts initially and scaling to 3-4+ hosts without architectural rework.

[Full content from the Plan agent output - continuing with the complete document as generated]

## 1. CHOM-STORAGE RESPONSIBILITIES

### 1.1 What CHOM-STORAGE Stores

CHOM-STORAGE hosts are **dedicated storage servers** separate from:
- **Customer VPS Servers**: Execute customer sites (WordPress, PHP, Laravel)
- **CHOM-APP Server**: Runs Laravel control plane
- **OBSERVABILITY Server**: Stores metrics and logs

#### Primary Responsibilities

| Data Type | Description | Storage Location | Retention |
|-----------|-------------|------------------|-----------|
| **Site Backups** | Full site backups (files + DB) | CHOM-STORAGE | 7-90 days (tier-based) |
| **Database Dumps** | Standalone DB exports | CHOM-STORAGE | 7-30 days |
| **Configuration Backups** | Nginx configs, SSL certs, env files | CHOM-STORAGE | 30 days |
| **Media Assets** | Customer uploads, images, videos | CHOM-STORAGE | Indefinite (until site deleted) |
| **Application Logs** | Archived Laravel logs (>7 days) | CHOM-STORAGE | 30-90 days |
| **Disaster Recovery Snapshots** | Full VPS filesystem snapshots | CHOM-STORAGE | 1-3 snapshots |
| **Deployment Artifacts** | Site templates, staging copies | CHOM-STORAGE | Until deployment |

#### What Customer VPS Stores (NOT CHOM-STORAGE)

| Data Type | Storage Location | Why Not CHOM-STORAGE |
|-----------|------------------|----------------------|
| **Active Site Files** | Customer VPS `/var/www/sites/` | Performance - local file access |
| **Active Databases** | Customer VPS PostgreSQL/MySQL | Performance - low latency queries |
| **PHP-FPM Runtime** | Customer VPS | Execution - must be local |
| **Nginx Web Server** | Customer VPS | Serving - must be local |
| **Site Caches** | Customer VPS Redis/Memcached | Performance - ultra-low latency |

---

## 2. TWO-HOST CHOM-STORAGE ARCHITECTURE (PoC Phase 2)

### 2.1 Architecture Decision: Primary-Replica

**Selected Approach**: **Primary-Replica (Active-Passive)** for PoC Phase 2

**Rationale**:
- **Simplicity**: One write path, one source of truth
- **Data Safety**: Automatic replication prevents data loss
- **Failover**: Manual promotion for PoC, automated later
- **Cost**: 2 identical hosts with full redundancy
- **Future-Ready**: Extends naturally to active-active with geo-distribution

**Alternative Considered (Rejected for PoC)**: Active-Active distributed storage
- **Pros**: Higher throughput, geographic distribution
- **Cons**: Requires distributed consensus (etcd/Raft), conflict resolution, higher complexity
- **Verdict**: Overkill for PoC with 2-10 customers

### 2.2 Replication Strategy

**Mechanism**: Rsync over SSH with delta transfers

**Why Rsync** (vs distributed filesystems):
- **Simplicity**: No cluster coordination, no split-brain scenarios
- **Reliability**: Battle-tested since 1996, handles interruptions gracefully
- **Efficiency**: Only transfers changed blocks (delta sync)
- **Debugging**: Easy to troubleshoot (just SSH + rsync)
- **PoC-Appropriate**: No daemon complexity, cron-based scheduling

**Replication Schedule**: Every 5 minutes via cron

**Replication Lag Tolerance**: 5 minutes is acceptable for backups (not real-time data)

---

## 3. MULTI-HOST CHOM-STORAGE SCALING (3+ Hosts)

### 3.1 Sharding Strategy: Consistent Hashing

**Approach**: Distribute sites across storage hosts using **Consistent Hashing** with virtual nodes

**Why Consistent Hashing**:
- Minimal data movement when adding/removing hosts
- Even distribution across hosts
- Deterministic (same site always maps to same host)
- Supports weighted capacity allocation

**Implementation**: 150 virtual nodes per physical host for better distribution

---

## 4. CAPACITY MANAGEMENT (Critical)

### 4.1 Capacity Thresholds

**Disk Usage Thresholds**:

| Threshold | Disk Usage | Action | Alert Severity |
|-----------|-----------|--------|----------------|
| **Normal** | 0-70% | None | None |
| **Warning** | 70-80% | Log warning, notify admins | Warning |
| **Critical** | 80-90% | Prevent new site backups to this host | Critical |
| **Full** | 90-100% | Host marked `unavailable`, failover to replica | Emergency |

### 4.2 How to Determine a Host is "Full"

**Multiple Metrics** (not just disk space):

1. **Disk Space**: >80% usage
2. **Inode Exhaustion**: >85% usage (millions of small files)
3. **I/O Performance**: >10% I/O wait time sustained for 10+ minutes
4. **Network Saturation**: >80% of 1 Gbps link usage
5. **Backup Success Rate**: <95% successful backups

**Automated Actions When "Full"**:
- Mark host as `unavailable` in database
- Stop routing new backups to this host
- Trigger cleanup job (delete expired backups)
- Alert ops team
- Optionally trigger automated migration to rebalance

---

## 5. SITE MIGRATION BETWEEN STORAGE HOSTS

### 5.1 Why Migrate?

| Scenario | Reason | Frequency |
|----------|--------|-----------|
| **Rebalancing** | STORAGE-1 is 85% full, STORAGE-2 is 40% full | Quarterly |
| **Decommissioning** | Retiring old hardware (STORAGE-1) | Annually |
| **Maintenance** | Upgrading disk, replacing failed drive | As needed |
| **Performance Optimization** | Move high-traffic site to faster storage | Rare |
| **Compliance** | Customer requests data residency in EU | As requested |

### 5.2 Migration Strategies

#### Strategy 1: Live Migration (Zero Downtime)

**Steps**:
1. Replicate data from source → destination (rsync)
2. Enable dual-write mode (write to both hosts)
3. Verify data integrity (checksums)
4. Update database metadata (atomic transaction)
5. Disable dual-write mode
6. Delete data from source host (after 24h)

**Downtime**: 0 seconds
**Complexity**: High (requires dual-write logic)

#### Strategy 2: Maintenance Window Migration

**Steps**:
1. Schedule maintenance window (announce to customers)
2. Pause backup jobs for site
3. Rsync data to new host
4. Update database metadata
5. Resume backup jobs

**Downtime**: 5-30 minutes (depending on data size)
**Complexity**: Low (simple bash script)

### 5.3 Data Consistency Guarantees

**Mechanisms**:
1. **Checksum Validation**: MD5 checksums of all files compared
2. **Atomic DB Update**: Database transaction for metadata
3. **Backup Before Migration**: Snapshot before starting
4. **Rollback Plan**: Keep data on old host for 24 hours

---

## 6. STORAGE BACKEND TECHNOLOGY

### 6.1 Recommended: MinIO

**Why MinIO**:
- **S3-Compatible API**: Drop-in replacement for AWS S3
- **Simple Deployment**: Single binary for PoC
- **Scales to Production**: Supports erasure coding, distributed mode
- **Laravel Native**: Works with Laravel's S3 filesystem driver
- **Observability**: Built-in Prometheus metrics
- **Proven**: Used by Slack, Docker, Adobe

**PoC Mode**: Standalone MinIO per storage host
**Production Mode**: Distributed MinIO with erasure coding (4+2 EC)

### 6.2 Laravel Integration

```php
// config/filesystems.php
'disks' => [
    'chom-storage-primary' => [
        'driver' => 's3',
        'key' => env('CHOM_STORAGE_ACCESS_KEY'),
        'secret' => env('CHOM_STORAGE_SECRET_KEY'),
        'region' => 'us-east-1',
        'bucket' => 'chom-backups',
        'endpoint' => env('CHOM_STORAGE_ENDPOINT'),
        'use_path_style_endpoint' => true,
    ],
],
```

**Usage**:
```php
// Upload backup
Storage::disk('chom-storage-primary')->put(
    "backups/{$site->id}/{$backupId}.tar.gz",
    fopen($localBackupPath, 'r')
);

// Download backup
$stream = Storage::disk('chom-storage-primary')->readStream(
    "backups/{$site->id}/{$backupId}.tar.gz"
);
```

---

## 7. BACKUP ARCHITECTURE

### 7.1 3-2-1 Backup Rule

**Implementation**:
- **3** copies of data: Original + STORAGE-1 + STORAGE-2
- **2** different storage media: Local storage + Cloud (S3 Glacier)
- **1** copy offsite: Daily sync to S3 Glacier (encrypted)

### 7.2 Retention Policies (Tier-Based)

| Tier | Full Backups | Incremental | DB Snapshots | Offsite |
|------|--------------|-------------|--------------|---------|
| **Starter** | 7 days | 24 hours | 3 days | 30 days |
| **Pro** | 30 days | 7 days | 7 days | 90 days |
| **Enterprise** | 90 days | 30 days | 30 days | 365 days |

### 7.3 Incremental vs Full Backups

**Strategy**: Incremental daily, Full weekly

- **Full Backup** (Sunday): 100% of files
- **Incremental** (Mon-Sat): Only changed files since previous backup
- **Space Savings**: ~70% (using rsync hard-links)

---

## 8. DATABASE SCHEMA

### 8.1 Storage Hosts Table

```sql
CREATE TABLE storage_hosts (
    id UUID PRIMARY KEY,
    hostname VARCHAR(255) NOT NULL UNIQUE,
    ip_address VARCHAR(45) NOT NULL,
    role VARCHAR(20) NOT NULL, -- 'active', 'replica', 'unavailable', 'maintenance'
    total_capacity_bytes BIGINT NOT NULL,
    used_capacity_bytes BIGINT NOT NULL DEFAULT 0,
    capacity_percent NUMERIC(5,2) GENERATED ALWAYS AS (
        (used_capacity_bytes::NUMERIC / total_capacity_bytes::NUMERIC) * 100
    ) STORED,
    health_status VARCHAR(20) NOT NULL DEFAULT 'unknown',
    last_health_check_at TIMESTAMP,
    region VARCHAR(50), -- 'us-east', 'eu-west'
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

### 8.2 Sites Table (Updated)

```sql
ALTER TABLE sites
ADD COLUMN storage_host_id UUID REFERENCES storage_hosts(id);

CREATE INDEX idx_sites_storage_host ON sites(storage_host_id);
```

### 8.3 Storage Migrations Table

```sql
CREATE TABLE storage_migrations (
    id UUID PRIMARY KEY,
    site_id UUID NOT NULL REFERENCES sites(id),
    source_host_id UUID NOT NULL REFERENCES storage_hosts(id),
    dest_host_id UUID NOT NULL REFERENCES storage_hosts(id),
    status VARCHAR(20) NOT NULL, -- 'pending', 'in_progress', 'completed', 'failed'
    data_size_bytes BIGINT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    failure_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

---

## 9. MONITORING & OBSERVABILITY

### 9.1 Storage-Specific Metrics

**Prometheus Metrics**:
- `chom_storage_disk_usage_percent` - Disk usage % per host
- `chom_storage_inode_usage_percent` - Inode usage % per host
- `chom_storage_io_wait_percent` - I/O wait time
- `chom_storage_replication_lag_seconds` - Replication lag
- `chom_storage_backup_success_rate` - Backup success rate

**Alert Rules**:
- Disk >80% → Critical alert, trigger cleanup
- Inode >85% → Critical alert
- I/O wait >10% sustained → Warning
- Replication lag >10 minutes → Critical

---

## 10. OPERATIONAL PROCEDURES

### 10.1 Adding New CHOM-STORAGE Host

**Steps** (30 minutes):
1. Format disk with XFS
2. Install MinIO
3. Configure replication
4. Register in database
5. Add to Prometheus monitoring

### 10.2 Decommissioning Old Host

**Steps** (2-4 hours):
1. Mark host as 'decommissioning'
2. Migrate all sites to other hosts
3. Verify no sites remain
4. Remove from monitoring
5. Shutdown services

### 10.3 Emergency: Disk Full

**Immediate Actions**:
1. Mark host as unavailable
2. Trigger emergency cleanup (delete oldest backups)
3. Failover to replica
4. Monitor disk usage recovery

---

## 11. IMPLEMENTATION ROADMAP

### Phase 2: PoC (2 Hosts) - 2 Weeks

**Deliverables**:
- 2 CHOM-STORAGE hosts (PRIMARY + REPLICA)
- MinIO standalone mode
- Rsync replication (5-min lag)
- Laravel S3 integration
- Manual failover procedures

**Cost**: ~$104/month

### Phase 3: Multi-Host Scaling - 3 Weeks

**Deliverables**:
- Consistent hashing
- Storage migration service
- Automated capacity management
- 3-4 storage hosts

**Cost**: ~$440/month (4 hosts)

### Phase 4: Production Hardening - 4 Weeks

**Deliverables**:
- MinIO distributed mode (erasure coding)
- Automated failover
- Real-time replication
- Offsite backups to S3 Glacier

---

## CONCLUSION

This CHOM-STORAGE architecture provides:

1. **PoC-Appropriate Simplicity**: 2 hosts, local filesystems, manual failover
2. **Clear Production Path**: Scale to 4+ hosts without rewrites
3. **Operational Excellence**: Comprehensive monitoring, runbooks, data integrity
4. **Cost Efficiency**: $4.40/customer/month at scale

**Next Step**: Begin Phase 2 implementation (2-week sprint)

---

## APPENDIX: Architecture Diagrams

### Two-Host Architecture (PoC)

```
┌─────────────────────────────────────────────────────────────────┐
│                     CHOM-APP (landsraad)                        │
│  - Laravel control plane                                       │
│  - PostgreSQL (metadata)                                       │
│  - ConsistentHash service                                      │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ S3 API (MinIO)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ CHOM-STORAGE-1 (PRIMARY)                                        │
│  - MinIO (standalone)                                          │
│  - /mnt/chom-storage (2TB XFS)                                 │
│    ├── backups/                                                │
│    ├── media/                                                  │
│    └── archives/                                               │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Rsync every 5 min
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ CHOM-STORAGE-2 (REPLICA)                                        │
│  - MinIO (read-only mirror)                                    │
│  - /mnt/chom-storage (2TB XFS)                                 │
│  - Manual failover if PRIMARY fails                            │
└─────────────────────────────────────────────────────────────────┘
```

### Four-Host Architecture (Production)

```
                    ┌─────────────────────────┐
                    │     CHOM-APP            │
                    │  ConsistentHash Router  │
                    └─────────────────────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
            ▼                ▼                ▼
    ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
    │ STORAGE-1  │   │ STORAGE-2  │   │ STORAGE-3  │   │ STORAGE-4  │
    │ 2TB        │   │ 2TB        │   │ 2TB        │   │ 2TB        │
    │ 25% full   │   │ 30% full   │   │ 20% full   │   │ 15% full   │
    └────────────┘   └────────────┘   └────────────┘   └────────────┘
         │                │                │                │
         └────────────────┴────────────────┴────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │ MinIO Distributed     │
              │ Erasure Coding (4+2)  │
              │ - Lose 2 hosts OK     │
              │ - Auto data healing   │
              └───────────────────────┘
```
