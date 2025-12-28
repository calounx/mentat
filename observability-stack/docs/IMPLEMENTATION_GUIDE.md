# Implementation Guide: Priority Features

> Step-by-step implementation guide for Phase 1 features (Quick Wins)

This guide provides detailed implementation instructions for the highest-priority missing features identified in the roadmap.

---

## Table of Contents

1. [PostgreSQL Exporter](#1-postgresql-exporter)
2. [Redis Exporter](#2-redis-exporter)
3. [Blackbox Exporter (Synthetic Monitoring)](#3-blackbox-exporter-synthetic-monitoring)
4. [PagerDuty Integration](#4-pagerduty-integration)
5. [Slack Integration](#5-slack-integration)

---

## 1. PostgreSQL Exporter

### Overview
Monitor PostgreSQL database health, performance, and replication.

### Implementation Steps

#### Step 1: Create Module Structure
```bash
cd observability-stack
mkdir -p modules/_core/postgres_exporter/{dashboards,alerts}
```

#### Step 2: Create module.yaml
**File:** `modules/_core/postgres_exporter/module.yaml`

```yaml
---
module:
  name: postgres_exporter
  version: 0.15.1
  description: "PostgreSQL database metrics exporter"
  category: database

detection:
  services:
    - postgresql
    - postgres
  packages:
    - postgresql-server
    - postgresql
  ports:
    - 5432

installation:
  binary:
    url: "https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.1/postgres_exporter-0.15.1.linux-amd64.tar.gz"
    checksum: "sha256:REPLACE_WITH_ACTUAL_CHECKSUM"
    extract_path: "postgres_exporter-0.15.1.linux-amd64/postgres_exporter"
    install_path: "/usr/local/bin/postgres_exporter"

  user:
    name: postgres_exporter
    system: true
    shell: "/usr/sbin/nologin"

configuration:
  port: 9187
  environment:
    DATA_SOURCE_NAME: "postgresql://postgres_exporter:PASSWORD@localhost:5432/postgres?sslmode=disable"
  flags:
    - "--web.listen-address=:9187"
    - "--web.telemetry-path=/metrics"

  systemd_unit: |
    [Unit]
    Description=PostgreSQL Exporter
    After=network.target postgresql.service

    [Service]
    Type=simple
    User=postgres_exporter
    Group=postgres_exporter
    ExecStart=/usr/local/bin/postgres_exporter
    EnvironmentFile=/etc/default/postgres_exporter
    Restart=on-failure
    RestartSec=5s

    [Install]
    WantedBy=multi-user.target

prometheus:
  scrape_config: |
    - job_name: 'postgres'
      static_configs:
        - targets: ['localhost:9187']
          labels:
            service: 'postgresql'

health_check:
  command: "curl -s http://localhost:9187/metrics | grep -q postgres_up"
  interval: 30s

dashboards:
  - file: "dashboards/postgres-overview.json"
    title: "PostgreSQL Overview"

alerts:
  - file: "alerts/postgres-alerts.yaml"

documentation:
  - "README.md"

dependencies: []

lifecycle:
  pre_install:
    - "CREATE USER postgres_exporter WITH PASSWORD 'CHANGE_ME';"
    - "GRANT pg_monitor TO postgres_exporter;"
  post_install:
    - "systemctl daemon-reload"
    - "systemctl enable postgres_exporter"
    - "systemctl start postgres_exporter"
```

#### Step 3: Create Alert Rules
**File:** `modules/_core/postgres_exporter/alerts/postgres-alerts.yaml`

```yaml
---
groups:
  - name: postgresql_alerts
    interval: 1m
    rules:
      # Availability
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL instance down"
          description: "PostgreSQL instance {{ $labels.instance }} is down"

      # Connections
      - alert: PostgreSQLTooManyConnections
        expr: sum(pg_stat_activity_count) BY (instance) > (pg_settings_max_connections * 0.9)
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL connection pool near limit"
          description: "{{ $labels.instance }} using {{ $value | humanizePercentage }} of max connections"

      - alert: PostgreSQLConnectionPoolExhausted
        expr: sum(pg_stat_activity_count) BY (instance) >= pg_settings_max_connections
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL connection pool exhausted"
          description: "{{ $labels.instance }} has reached max connections"

      # Replication
      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag > 30
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL replication lag"
          description: "Replication lag is {{ $value }}s on {{ $labels.instance }}"

      - alert: PostgreSQLReplicationLagCritical
        expr: pg_replication_lag > 300
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL replication lag critical"
          description: "Replication lag is {{ $value }}s on {{ $labels.instance }} (>5min)"

      # Performance
      - alert: PostgreSQLSlowQueries
        expr: rate(pg_stat_activity_max_tx_duration{state="active"}[1m]) > 60
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL slow queries detected"
          description: "Queries taking >60s on {{ $labels.instance }}"

      - alert: PostgreSQLCacheHitRatioLow
        expr: (pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)) < 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL low cache hit ratio"
          description: "Cache hit ratio is {{ $value | humanizePercentage }} on {{ $labels.instance }}"

      # Deadlocks
      - alert: PostgreSQLDeadlocks
        expr: increase(pg_stat_database_deadlocks[1m]) > 5
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL deadlocks detected"
          description: "{{ $value }} deadlocks in last minute on {{ $labels.instance }}"
```

#### Step 4: Create Dashboard
**File:** `modules/_core/postgres_exporter/dashboards/postgres-overview.json`

This would be a full Grafana dashboard JSON. For brevity, here's the structure:

```json
{
  "dashboard": {
    "title": "PostgreSQL Overview",
    "panels": [
      {
        "title": "PostgreSQL Status",
        "targets": [{"expr": "pg_up"}]
      },
      {
        "title": "Connections",
        "targets": [{"expr": "pg_stat_activity_count"}]
      },
      {
        "title": "Replication Lag",
        "targets": [{"expr": "pg_replication_lag"}]
      },
      {
        "title": "Cache Hit Ratio",
        "targets": [{"expr": "pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)"}]
      }
    ]
  }
}
```

#### Step 5: Create README
**File:** `modules/_core/postgres_exporter/README.md`

```markdown
# PostgreSQL Exporter Module

Monitor PostgreSQL database performance, connections, and replication.

## Metrics

- Connection pool usage
- Query performance
- Replication lag
- Cache hit ratios
- Deadlocks
- Database size

## Prerequisites

- PostgreSQL 10+ installed and running
- Monitoring user with `pg_monitor` role

## Setup

### 1. Create Monitoring User
```sql
CREATE USER postgres_exporter WITH PASSWORD 'SECURE_PASSWORD';
GRANT pg_monitor TO postgres_exporter;
```

### 2. Install Module
```bash
./scripts/module-manager.sh install postgres_exporter
```

### 3. Configure Credentials
Edit `/etc/default/postgres_exporter`:
```
DATA_SOURCE_NAME="postgresql://postgres_exporter:PASSWORD@localhost:5432/postgres?sslmode=disable"
```

### 4. Restart Service
```bash
systemctl restart postgres_exporter
```

## Dashboard

Access the **PostgreSQL Overview** dashboard in Grafana.

## Alerts

Pre-configured alerts for:
- Database down
- High connection usage
- Replication lag
- Low cache hit ratio
- Deadlocks

## Troubleshooting

Check metrics endpoint:
```bash
curl http://localhost:9187/metrics
```

View logs:
```bash
journalctl -u postgres_exporter -f
```
```

---

## 2. Redis Exporter

### Implementation Steps

#### Create Module Structure
```bash
mkdir -p modules/_core/redis_exporter/{dashboards,alerts}
```

#### module.yaml
**File:** `modules/_core/redis_exporter/module.yaml`

```yaml
---
module:
  name: redis_exporter
  version: 1.62.0
  description: "Redis metrics exporter"
  category: cache

detection:
  services:
    - redis
    - redis-server
  packages:
    - redis
    - redis-server
  ports:
    - 6379

installation:
  binary:
    url: "https://github.com/oliver006/redis_exporter/releases/download/v1.62.0/redis_exporter-v1.62.0.linux-amd64.tar.gz"
    checksum: "sha256:REPLACE_WITH_ACTUAL_CHECKSUM"
    extract_path: "redis_exporter-v1.62.0.linux-amd64/redis_exporter"
    install_path: "/usr/local/bin/redis_exporter"

  user:
    name: redis_exporter
    system: true
    shell: "/usr/sbin/nologin"

configuration:
  port: 9121
  flags:
    - "--web.listen-address=:9121"
    - "--redis.addr=redis://localhost:6379"

  systemd_unit: |
    [Unit]
    Description=Redis Exporter
    After=network.target redis.service

    [Service]
    Type=simple
    User=redis_exporter
    Group=redis_exporter
    ExecStart=/usr/local/bin/redis_exporter
    Restart=on-failure
    RestartSec=5s

    [Install]
    WantedBy=multi-user.target

prometheus:
  scrape_config: |
    - job_name: 'redis'
      static_configs:
        - targets: ['localhost:9121']
          labels:
            service: 'redis'

health_check:
  command: "curl -s http://localhost:9121/metrics | grep -q redis_up"
  interval: 30s

dashboards:
  - file: "dashboards/redis-overview.json"
    title: "Redis Overview"

alerts:
  - file: "alerts/redis-alerts.yaml"
```

#### Alert Rules
**File:** `modules/_core/redis_exporter/alerts/redis-alerts.yaml`

```yaml
---
groups:
  - name: redis_alerts
    interval: 1m
    rules:
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis instance down"
          description: "Redis {{ $labels.instance }} is down"

      - alert: RedisMemoryHigh
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis memory usage high"
          description: "Redis using {{ $value | humanizePercentage }} of max memory"

      - alert: RedisMemoryCritical
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.95
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis memory critical"
          description: "Redis using {{ $value | humanizePercentage }} of max memory"

      - alert: RedisEvictions
        expr: increase(redis_evicted_keys_total[5m]) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Redis evicting keys"
          description: "{{ $value }} keys evicted in last 5 minutes"

      - alert: RedisTooManyConnections
        expr: redis_connected_clients > (redis_config_maxclients * 0.9)
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis connection limit approaching"
          description: "{{ $value }} connections ({{ $value | humanizePercentage }} of max)"

      - alert: RedisLowHitRate
        expr: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) < 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis low cache hit rate"
          description: "Hit rate is {{ $value | humanizePercentage }}"
```

---

## 3. Blackbox Exporter (Synthetic Monitoring)

### Overview
External uptime monitoring with HTTP/HTTPS probes, SSL checks, and response time tracking.

### Implementation Steps

#### Module Structure
```bash
mkdir -p modules/_core/blackbox_exporter/{config,dashboards,alerts}
```

#### module.yaml
**File:** `modules/_core/blackbox_exporter/module.yaml`

```yaml
---
module:
  name: blackbox_exporter
  version: 0.25.0
  description: "Synthetic monitoring and external probes"
  category: monitoring

detection:
  # Always installable (no specific service required)
  manual: true

installation:
  binary:
    url: "https://github.com/prometheus/blackbox_exporter/releases/download/v0.25.0/blackbox_exporter-0.25.0.linux-amd64.tar.gz"
    checksum: "sha256:REPLACE_WITH_ACTUAL_CHECKSUM"
    extract_path: "blackbox_exporter-0.25.0.linux-amd64/blackbox_exporter"
    install_path: "/usr/local/bin/blackbox_exporter"

  user:
    name: blackbox_exporter
    system: true
    shell: "/usr/sbin/nologin"

configuration:
  port: 9115
  config_file: "/etc/blackbox_exporter/blackbox.yml"

  config_content: |
    modules:
      http_2xx:
        prober: http
        timeout: 5s
        http:
          method: GET
          valid_status_codes: [200]
          fail_if_not_ssl: false

      http_2xx_ssl:
        prober: http
        timeout: 5s
        http:
          method: GET
          valid_status_codes: [200]
          fail_if_not_ssl: true

      tcp_connect:
        prober: tcp
        timeout: 5s

      icmp:
        prober: icmp
        timeout: 5s

  systemd_unit: |
    [Unit]
    Description=Blackbox Exporter
    After=network.target

    [Service]
    Type=simple
    User=blackbox_exporter
    Group=blackbox_exporter
    ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter/blackbox.yml
    Restart=on-failure
    RestartSec=5s

    [Install]
    WantedBy=multi-user.target

prometheus:
  scrape_config: |
    - job_name: 'blackbox_exporter'
      metrics_path: /metrics
      static_configs:
        - targets: ['localhost:9115']

    - job_name: 'blackbox_http'
      metrics_path: /probe
      params:
        module: [http_2xx]
      static_configs:
        - targets:
          # Add your HTTP endpoints here
          - https://example.com
          - https://api.example.com/health
      relabel_configs:
        - source_labels: [__address__]
          target_label: __param_target
        - source_labels: [__param_target]
          target_label: instance
        - target_label: __address__
          replacement: localhost:9115

health_check:
  command: "curl -s http://localhost:9115/metrics | grep -q blackbox_"
  interval: 30s

dashboards:
  - file: "dashboards/blackbox-overview.json"
    title: "Uptime & Synthetic Monitoring"

alerts:
  - file: "alerts/blackbox-alerts.yaml"
```

#### Alert Rules
**File:** `modules/_core/blackbox_exporter/alerts/blackbox-alerts.yaml`

```yaml
---
groups:
  - name: blackbox_alerts
    interval: 1m
    rules:
      - alert: EndpointDown
        expr: probe_success == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Endpoint {{ $labels.instance }} is down"
          description: "HTTP probe failed for {{ $labels.instance }}"

      - alert: EndpointHighLatency
        expr: probe_duration_seconds > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency for {{ $labels.instance }}"
          description: "Response time is {{ $value }}s"

      - alert: SSLCertExpiringSoon
        expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon"
          description: "SSL cert for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}"

      - alert: SSLCertExpired
        expr: probe_ssl_earliest_cert_expiry - time() < 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "SSL certificate expired"
          description: "SSL cert for {{ $labels.instance }} has expired"

      - alert: HTTPStatusCodeUnexpected
        expr: probe_http_status_code != 200
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Unexpected HTTP status code"
          description: "{{ $labels.instance }} returned {{ $value }}"
```

---

## 4. PagerDuty Integration

### Implementation Steps

#### Step 1: Create Alertmanager Configuration Template
**File:** `alertmanager/config/pagerduty-template.yml`

```yaml
# PagerDuty Integration Configuration
# Copy this template and fill in your integration keys

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'pagerduty-critical'

  # Route critical alerts to PagerDuty high-urgency
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      continue: false

    # Route warnings to PagerDuty low-urgency
    - match:
        severity: warning
      receiver: 'pagerduty-warning'
      continue: false

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY_CRITICAL'
        severity: 'critical'
        description: '{{ .CommonAnnotations.summary }}'
        details:
          firing: '{{ template "pagerduty.default.instances" .Alerts.Firing }}'
          resolved: '{{ template "pagerduty.default.instances" .Alerts.Resolved }}'
          num_firing: '{{ .Alerts.Firing | len }}'
          num_resolved: '{{ .Alerts.Resolved | len }}'
        client: 'Observability Stack'
        client_url: 'https://grafana.example.com'

  - name: 'pagerduty-warning'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY_WARNING'
        severity: 'warning'
        description: '{{ .CommonAnnotations.summary }}'
        client: 'Observability Stack'
```

#### Step 2: Setup Script
**File:** `scripts/setup-pagerduty.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "PagerDuty Integration Setup"
echo "============================"
echo ""

read -rp "PagerDuty Critical Integration Key: " PD_KEY_CRITICAL
read -rp "PagerDuty Warning Integration Key: " PD_KEY_WARNING

# Update Alertmanager config
sed -i "s/YOUR_PAGERDUTY_INTEGRATION_KEY_CRITICAL/${PD_KEY_CRITICAL}/g" /etc/alertmanager/config.yml
sed -i "s/YOUR_PAGERDUTY_INTEGRATION_KEY_WARNING/${PD_KEY_WARNING}/g" /etc/alertmanager/config.yml

# Reload Alertmanager
systemctl reload alertmanager

echo ""
echo "✓ PagerDuty integration configured"
echo "✓ Alertmanager reloaded"
echo ""
echo "Test by triggering a test alert."
```

---

## 5. Slack Integration

### Implementation Steps

#### Alertmanager Slack Template
**File:** `alertmanager/config/slack-template.yml`

```yaml
route:
  routes:
    - match:
        severity: critical
      receiver: 'slack-critical'
      continue: true

    - match:
        severity: warning
      receiver: 'slack-warnings'
      continue: true

receivers:
  - name: 'slack-critical'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#alerts-critical'
        username: 'Observability Stack'
        icon_emoji: ':fire:'
        title: ':fire: {{ .CommonAnnotations.summary }}'
        text: |
          {{ range .Alerts }}
          *Alert:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          *Severity:* {{ .Labels.severity }}
          *Instance:* {{ .Labels.instance }}
          {{ end }}
        send_resolved: true

  - name: 'slack-warnings'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#alerts-warnings'
        username: 'Observability Stack'
        icon_emoji: ':warning:'
        title: ':warning: {{ .CommonAnnotations.summary }}'
        text: |
          {{ range .Alerts }}
          *Alert:* {{ .Annotations.summary }}
          *Severity:* {{ .Labels.severity }}
          *Instance:* {{ .Labels.instance }}
          {{ end }}
        send_resolved: true
```

#### Setup Script
**File:** `scripts/setup-slack.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Slack Integration Setup"
echo "======================="
echo ""
echo "Create a Slack Incoming Webhook:"
echo "1. Go to https://api.slack.com/apps"
echo "2. Create new app → Incoming Webhooks"
echo "3. Copy webhook URL"
echo ""

read -rp "Slack Webhook URL: " SLACK_WEBHOOK

# Update Alertmanager config
sed -i "s|YOUR_SLACK_WEBHOOK_URL|${SLACK_WEBHOOK}|g" /etc/alertmanager/config.yml

# Reload Alertmanager
systemctl reload alertmanager

echo ""
echo "✓ Slack integration configured"
echo "✓ Alertmanager reloaded"
```

---

## Testing & Validation

### Test Module Installation

```bash
# Install module
./scripts/module-manager.sh install postgres_exporter

# Check service status
systemctl status postgres_exporter

# Verify metrics
curl http://localhost:9187/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="postgres")'
```

### Test Alerts

```bash
# Trigger test alert
curl -X POST http://localhost:9093/api/v1/alerts -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]'

# Check Alertmanager
curl http://localhost:9093/api/v1/alerts
```

---

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines on:
- Adding new modules
- Writing dashboards
- Creating alert rules
- Testing procedures

---

## Support

- Issues: https://github.com/calounx/mentat/issues
- Documentation: https://github.com/calounx/mentat/tree/master/observability-stack/docs
