# CHOM Deployment System - Architecture Diagrams

**Version:** 4.3.0 (Current) → 5.0.0 (Proposed)
**Date:** 2025-12-31

---

## Current Architecture (v4.3.0)

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     CONTROL MACHINE                              │
│                   (Developer Laptop/CI Server)                   │
│                                                                  │
│  deploy-enhanced.sh (2,616 lines)                               │
│  ├─ Bash 4.0+                                                   │
│  ├─ Sequential execution                                        │
│  ├─ SSH-based orchestration                                     │
│  └─ State: .deploy-state/deployment.state (JSON)                │
│                                                                  │
│  configs/inventory.yaml                                          │
│  ├─ IP addresses, SSH config                                    │
│  ├─ Hardware specs (STATIC - user input)                        │
│  └─ SMTP password (PLAINTEXT - security risk!)                  │
│                                                                  │
│  lib/deploy-common.sh                                            │
│  └─ Shared utilities (682 lines)                                │
│                                                                  │
│  scripts/                                                        │
│  ├─ setup-observability-vps.sh                                  │
│  └─ setup-vpsmanager-vps.sh                                     │
└──────────────────────────────────────────────────────────────────┘
                           │
                           │ SSH (port 22)
                           │ Key: ./keys/chom_deploy_key
                           │
         ┌─────────────────┴─────────────────┐
         │                                   │
         ▼                                   ▼
┌──────────────────────┐          ┌──────────────────────┐
│  OBSERVABILITY VPS   │          │   VPSMANAGER VPS     │
│   203.0.113.10       │          │   203.0.113.20       │
│                      │          │                      │
│  Prometheus   :9090  │ ◄────────│  Node Exporter :9100 │
│  Grafana      :3000  │  metrics │  Nginx Exp     :9113 │
│  Loki         :3100  │ ◄────────│  MySQL Exp     :9104 │
│  Alertmanager :9093  │   logs   │  PHP-FPM Exp   :9253 │
│  Nginx        :80/443│          │  Promtail      :9080 │
│                      │          │                      │
│  Node Exporter:9100  │          │  Nginx         :80   │
│                      │          │  PHP-FPM       :9000 │
│  Storage:            │          │  MariaDB       :3306 │
│  - Prometheus data   │          │  Redis         :6379 │
│  - Loki logs         │          │  Laravel              │
│  - Grafana DB        │          │                      │
└──────────────────────┘          └──────────────────────┘

Hardware: STATIC (manual entry)     Hardware: STATIC (manual entry)
  cpu: 1                              cpu: 2
  memory_mb: 2048                     memory_mb: 4096
  disk_gb: 20                         disk_gb: 80
```

### Deployment Flow (Sequential)

```
START
  │
  ├─► [Pre-flight Checks]
  │   ├─ Check local dependencies (ssh, yq, jq)
  │   ├─ Validate inventory.yaml
  │   ├─ Test SSH connectivity
  │   ├─ Check sudo access
  │   ├─ Validate OS (Debian 13)
  │   └─ Check hardware (remote commands)
  │
  ├─► [User Confirmation]
  │   └─ "Deploy CHOM Infrastructure? [Y/n]"
  │
  ├─► [Deploy Observability VPS] ──── 5-10 minutes
  │   ├─ Copy setup script via SCP
  │   ├─ Execute: setup-observability-vps.sh
  │   │   ├─ Install Prometheus
  │   │   ├─ Install Loki
  │   │   ├─ Install Grafana
  │   │   ├─ Install Alertmanager
  │   │   ├─ Configure Nginx
  │   │   └─ Start all services
  │   └─ Update state: observability=completed
  │
  ├─► [Deploy VPSManager VPS] ──── 10-15 minutes
  │   ├─ Copy setup script via SCP
  │   ├─ Execute: setup-vpsmanager-vps.sh
  │   │   ├─ Install PHP 8.2, 8.3, 8.4
  │   │   ├─ Install MariaDB
  │   │   ├─ Install Redis
  │   │   ├─ Install Nginx
  │   │   ├─ Deploy Laravel app
  │   │   ├─ Install exporters
  │   │   └─ Start all services
  │   └─ Update state: vpsmanager=completed
  │
  └─► [Deployment Complete] ──── TOTAL: 15-25 minutes

State File (.deploy-state/deployment.state):
{
  "started_at": "...",
  "status": "completed",
  "observability": {"status": "completed", "completed_at": "..."},
  "vpsmanager": {"status": "completed", "completed_at": "..."}
}
```

### Secret Management (CURRENT - INSECURE!)

```
┌───────────────────────────────────────────┐
│  configs/inventory.yaml (PLAINTEXT!)      │
│                                           │
│  observability:                           │
│    config:                                │
│      smtp:                                │
│        host: smtp.gmail.com               │
│        password: "my_secret_password"     │  ← SECURITY RISK!
│                                           │
│  This file may be:                        │
│  ✗ Committed to git                       │
│  ✗ Shared via email/Slack                 │
│  ✗ Visible in process lists               │
│  ✗ Logged to files                        │
└───────────────────────────────────────────┘
                │
                ├─► Git repository (PUBLIC!)
                ├─► Team members (email)
                └─► CI/CD logs (visible)
```

### Hardware Detection (CURRENT - STATIC)

```
┌─────────────────────────────────────────────┐
│  User manually enters hardware specs:      │
│                                             │
│  observability:                             │
│    specs:                                   │
│      cpu: 1          ← User types this      │
│      memory_mb: 2048 ← User types this      │
│      disk_gb: 20     ← User types this      │
│                                             │
│  Problems:                                  │
│  ✗ User may enter wrong values              │
│  ✗ No validation against actual hardware    │
│  ✗ Specs never updated if VPS upgraded      │
│  ✗ Monitoring thresholds based on wrong data│
└─────────────────────────────────────────────┘
```

---

## Proposed Architecture (v5.0.0)

### System Overview (Enhanced)

```
┌─────────────────────────────────────────────────────────────────┐
│                     CONTROL MACHINE                              │
│                                                                  │
│  deploy-enhanced.sh (reduced to ~1,000 lines)                   │
│  ├─ Orchestration only                                          │
│  ├─ Parallel execution (xargs -P)                               │
│  └─ Dependency graph                                            │
│                                                                  │
│  configs/                                                        │
│  ├─ inventory.yaml (NO secrets, NO static hardware)             │
│  ├─ .secrets.env (gitignored, encrypted with sops)              │
│  └─ defaults.yaml (fallback values)                             │
│                                                                  │
│  lib/                                                            │
│  ├─ deploy-common.sh (shared utilities)                         │
│  ├─ hardware-detection.sh (NEW!)                                │
│  ├─ secret-management.sh (NEW!)                                 │
│  └─ state-management.sh (NEW!)                                  │
│                                                                  │
│  .deploy-state/                                                  │
│  ├─ current.json (current deployment)                           │
│  ├─ history/                                                     │
│  │   ├─ 20251231-100000.json (deployment history)               │
│  │   └─ 20251230-143000.json                                    │
│  └─ hardware/                                                    │
│      ├─ observability.json (hardware snapshots)                 │
│      └─ vpsmanager.json                                         │
└──────────────────────────────────────────────────────────────────┘
                           │
                           │ SSH (parallel connections)
         ┌─────────────────┴─────────────────┐
         │                                   │
         ▼                                   ▼
┌──────────────────────┐          ┌──────────────────────┐
│  OBSERVABILITY VPS   │          │   VPSMANAGER VPS     │
│                      │          │                      │
│  Hardware: DETECTED  │          │  Hardware: DETECTED  │
│  ├─ nproc → 2 vCPU   │          │  ├─ nproc → 4 vCPU   │
│  ├─ free -m → 4096MB │          │  ├─ free -m → 8192MB │
│  └─ df -BG → 40GB    │          │  └─ df -BG → 80GB    │
│                      │          │                      │
│  Stored in:          │          │  Stored in:          │
│  .deploy-state/      │          │  .deploy-state/      │
│  hardware/           │          │  hardware/           │
│  observability.json  │          │  vpsmanager.json     │
└──────────────────────┘          └──────────────────────┘
```

### Enhanced Deployment Flow (Parallel)

```
START
  │
  ├─► [Pre-flight Checks]
  │   ├─ Check local dependencies
  │   ├─ Validate inventory.yaml
  │   ├─ Load secrets from .secrets.env (encrypted)
  │   ├─ Validate all secrets are set
  │   ├─ Test SSH connectivity (parallel)
  │   └─ DETECT HARDWARE (NEW!)
  │       ├─ SSH to each VPS in parallel
  │       ├─ Run: nproc, free -m, df -BG
  │       ├─ Store in .deploy-state/hardware/
  │       ├─ Compare with inventory if provided
  │       └─ Display hardware summary table
  │
  ├─► [Hardware Summary] (NEW!)
  │   ┌────────────────────────────────────────────┐
  │   │ Target         vCPU  RAM(MB)  Disk(GB)     │
  │   ├────────────────────────────────────────────┤
  │   │ Observability    2     4096      40    ✓   │
  │   │ VPSManager       4     8192      80    ✓   │
  │   └────────────────────────────────────────────┘
  │
  ├─► [User Confirmation]
  │   └─ "Deploy CHOM Infrastructure? [Y/n]"
  │
  ├─► [PARALLEL DEPLOYMENT] ──── 10-15 minutes (50% faster!)
  │   ├─────────────────────────┬─────────────────────────┐
  │   │                         │                         │
  │   ▼                         ▼                         │
  │   [Observability VPS]       [VPSManager VPS]          │
  │   5-10 min                  10-15 min                 │
  │   │                         │                         │
  │   ├─ Install Prometheus     ├─ Install PHP            │
  │   ├─ Install Loki           ├─ Install MariaDB        │
  │   ├─ Install Grafana        ├─ Install Redis          │
  │   ├─ Install Alertmanager   ├─ Install Nginx          │
  │   └─ Configure Nginx        ├─ Deploy Laravel         │
  │                             └─ Install exporters      │
  │                         │                         │
  │   └─────────────────────────┴─────────────────────────┘
  │                             │
  │                             ▼
  │                     [Both completed]
  │
  └─► [Deployment Complete] ──── TOTAL: 10-15 minutes (was 15-25)

Enhanced State File (.deploy-state/history/20251231-100000.json):
{
  "deployment_id": "20251231-100000-a1b2c3",
  "deployer": {"user": "admin", "hostname": "laptop", "ip": "192.168.1.100"},
  "config": {
    "inventory_sha256": "abc123...",
    "script_version": "5.0.0"
  },
  "targets": {
    "observability": {
      "status": "completed",
      "hardware": {
        "cpu": 2,              ← DETECTED, not user input
        "memory_mb": 4096,     ← DETECTED, not user input
        "disk_gb": 40,         ← DETECTED, not user input
        "detected_at": "2025-12-31T10:05:00Z"
      },
      "components": {
        "prometheus": {"status": "completed", "version": "3.8.1"},
        "grafana": {"status": "completed", "version": "11.3.0"}
      },
      "resources_created": {
        "users": ["observability", "prometheus"],
        "services": ["prometheus.service", "grafana.service"],
        "directories": ["/var/lib/observability"],
        "firewall_rules": ["ufw allow 9090/tcp"]
      }
    }
  }
}
```

### Enhanced Secret Management (SECURE)

```
┌───────────────────────────────────────────┐
│  configs/.secrets.env (ENCRYPTED!)        │
│                                           │
│  # Encrypted with sops or git-crypt       │
│  SMTP_PASSWORD=my_secret_password         │
│  GRAFANA_ADMIN_PASSWORD=xxx               │
│  MARIADB_ROOT_PASSWORD=xxx                │
│                                           │
│  ✓ Gitignored (.gitignore)                │
│  ✓ Encrypted at rest                      │
│  ✓ Loaded at runtime only                 │
│  ✓ Scrubbed from logs                     │
│                                           │
│  # Example .gitignore:                    │
│  .secrets.env                             │
│  !.secrets.env.example                    │
└───────────────────────────────────────────┘
                │
                ├─► Sourced by deploy-enhanced.sh
                ├─► Validated before deployment
                └─► Passed securely to remote (not logged)

Deployment script:
  set -a
  source configs/.secrets.env
  set +a

  # Validate
  if [[ -z "$SMTP_PASSWORD" ]]; then
    log_error "SMTP_PASSWORD not set in .secrets.env"
    exit 1
  fi

  # Pass to remote (scrubbed from logs)
  remote_exec "$host" "$user" "$port" \
    "SMTP_PASSWORD='$SMTP_PASSWORD' /tmp/setup.sh" 2>&1 | \
    sed 's/SMTP_PASSWORD=[^ ]*/SMTP_PASSWORD=[REDACTED]/g'
```

### Enhanced Hardware Detection (DYNAMIC)

```
┌─────────────────────────────────────────────┐
│  Hardware Detection Process (NEW!)          │
│                                             │
│  1. SSH to each VPS                         │
│     ssh deploy@obs.example.com              │
│                                             │
│  2. Detect vCPU count                       │
│     cpu=$(nproc)                            │
│     → Output: 2                             │
│                                             │
│  3. Detect total RAM (MB)                   │
│     memory_mb=$(free -m | awk '/^Mem:/ {print $2}') │
│     → Output: 4096                          │
│                                             │
│  4. Detect total disk (GB)                  │
│     disk_gb=$(df -BG / | awk 'NR==2 {print $2}' | tr -d 'G') │
│     → Output: 40                            │
│                                             │
│  5. Store in state file                     │
│     .deploy-state/hardware/observability.json │
│     {                                       │
│       "cpu": 2,                             │
│       "memory_mb": 4096,                    │
│       "disk_gb": 40,                        │
│       "architecture": "x86_64",             │
│       "os": "Debian 13.0",                  │
│       "detected_at": "2025-12-31T10:05:00Z" │
│     }                                       │
│                                             │
│  6. Compare with inventory (if provided)    │
│     if inventory.specs.cpu != detected.cpu: │
│       warn "CPU mismatch: inventory says 1, detected 2" │
│                                             │
│  7. Display summary table                   │
│     ┌────────────────────────────────────┐ │
│     │ Target         vCPU  RAM   Disk    │ │
│     ├────────────────────────────────────┤ │
│     │ Observability    2   4096MB  40GB  │ │
│     │ VPSManager       4   8192MB  80GB  │ │
│     └────────────────────────────────────┘ │
│                                             │
│  Benefits:                                  │
│  ✓ Always accurate                          │
│  ✓ Detects hardware changes                 │
│  ✓ Historical tracking                      │
│  ✓ Proper monitoring thresholds             │
└─────────────────────────────────────────────┘
```

---

## Scalability Comparison

### Current Architecture (v4.3.0)

```
Sequential Deployment:

Time for 2 VPS:   15-25 minutes
Time for 5 VPS:   40-60 minutes
Time for 10 VPS:  100-150 minutes (2.5 hours!)

┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  VPS 1  │ ──►│  VPS 2  │ ──►│  VPS 3  │ ──►│  VPS 4  │ ...
│ 15 min  │    │ 15 min  │    │ 15 min  │    │ 15 min  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘

Bottleneck: Sequential execution
```

### Proposed Architecture (v5.0.0)

```
Parallel Deployment with Dependency Graph:

Time for 2 VPS:   10-15 minutes (observability + vpsmanager in parallel)
Time for 5 VPS:   15-20 minutes (all in parallel)
Time for 10 VPS:  20-30 minutes (parallel with resource limits)

┌─────────┐
│  VPS 1  │ ──►┐
│ 15 min  │    │
└─────────┘    │
               ├──► All complete in 15 minutes
┌─────────┐    │
│  VPS 2  │ ──►┘
│ 15 min  │
└─────────┘

... up to N VPS in parallel (limited by control machine resources)

Improvement: 80% time reduction for 10+ VPS
```

---

## State Management Comparison

### Current State File (v4.3.0)

```json
{
  "started_at": "2025-12-31T10:00:00Z",
  "status": "completed",
  "observability": {
    "status": "completed",
    "completed_at": "2025-12-31T10:15:00Z"
  },
  "vpsmanager": {
    "status": "completed",
    "completed_at": "2025-12-31T10:30:00Z"
  }
}
```

**Limitations:**
- Only current deployment (no history)
- Only target-level status (not component-level)
- No deployer info (who deployed?)
- No config snapshot (what was deployed?)
- No resource tracking (what was created?)
- No error context (what failed and why?)

### Enhanced State File (v5.0.0)

```json
{
  "version": "5.0",
  "deployment_id": "20251231-100000-a1b2c3",
  "deployer": {
    "user": "admin",
    "hostname": "laptop",
    "ip": "192.168.1.100"
  },
  "started_at": "2025-12-31T10:00:00Z",
  "completed_at": "2025-12-31T10:30:00Z",
  "config": {
    "inventory_sha256": "abc123...",
    "script_version": "5.0.0"
  },
  "targets": {
    "observability": {
      "hardware": {
        "cpu": 2,
        "memory_mb": 4096,
        "disk_gb": 40,
        "detected_at": "2025-12-31T10:05:00Z"
      },
      "components": {
        "prometheus": {
          "status": "completed",
          "version": "3.8.1",
          "started_at": "2025-12-31T10:05:00Z",
          "completed_at": "2025-12-31T10:08:00Z"
        }
      },
      "resources_created": {
        "users": ["observability"],
        "services": ["prometheus.service"],
        "directories": ["/var/lib/observability"],
        "firewall_rules": ["ufw allow 9090/tcp"]
      }
    }
  }
}
```

**Benefits:**
- Full deployment history (multiple files in history/)
- Component-level granularity
- Deployer audit trail
- Config snapshot for reproducibility
- Resource inventory for cleanup
- Hardware detection history

---

## Migration Path: v4.3.0 → v5.0.0

### Phase 1: Security (Week 1)

```
Before:
  configs/inventory.yaml
    smtp:
      password: "my_secret"  ← PLAINTEXT

After:
  configs/inventory.yaml
    smtp:
      host: smtp.gmail.com
      port: 587
      user: alerts@example.com
      # password moved to .secrets.env

  configs/.secrets.env (NEW!)
    SMTP_PASSWORD=my_secret
    GRAFANA_ADMIN_PASSWORD=xxx
    MARIADB_ROOT_PASSWORD=xxx

  .gitignore (UPDATED)
    .secrets.env
    !.secrets.env.example
```

### Phase 2: Hardware Detection (Week 2)

```
Before:
  configs/inventory.yaml
    specs:
      cpu: 1           ← User input
      memory_mb: 2048  ← User input
      disk_gb: 20      ← User input

After:
  configs/inventory.yaml
    # specs removed - detected dynamically

  lib/hardware-detection.sh (NEW!)
    detect_hardware()
      cpu=$(remote_exec "nproc")
      memory_mb=$(remote_exec "free -m | awk '/^Mem:/ {print $2}'")
      disk_gb=$(remote_exec "df -BG / | awk 'NR==2 {print $2}' | tr -d 'G'")

  .deploy-state/hardware/observability.json (NEW!)
    {
      "cpu": 2,          ← Detected
      "memory_mb": 4096, ← Detected
      "disk_gb": 40,     ← Detected
      "detected_at": "2025-12-31T10:05:00Z"
    }
```

### Phase 3: Enhanced State (Week 3-4)

```
Before:
  .deploy-state/deployment.state (single file)

After:
  .deploy-state/
    current.json (symlink to latest)
    history/
      20251231-100000.json
      20251230-143000.json
      20251229-120000.json
    hardware/
      observability.json
      vpsmanager.json
```

### Phase 4: Parallel Deployment (Week 5-6)

```
Before:
  deploy_all() {
    deploy_observability  # 10 min
    deploy_vpsmanager     # 15 min
  }
  # Total: 25 minutes

After:
  deploy_all() {
    echo "observability vpsmanager" | \
      xargs -P 2 -n 1 ./deploy-target.sh
  }
  # Total: 15 minutes (parallel)
```

---

**End of Architecture Diagrams**

Files referenced:
- `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh`
- `/home/calounx/repositories/mentat/chom/deploy/configs/inventory.yaml`
- `/home/calounx/repositories/mentat/chom/deploy/lib/deploy-common.sh`
