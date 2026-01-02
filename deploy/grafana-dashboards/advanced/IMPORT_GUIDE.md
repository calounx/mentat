# Advanced Grafana Dashboards - Import & Configuration Guide

This guide provides step-by-step instructions for importing and configuring the advanced SRE/DevOps monitoring dashboards for the CHOM platform.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Dashboard Overview](#dashboard-overview)
- [Metrics Requirements](#metrics-requirements)
- [Import Instructions](#import-instructions)
- [Dashboard Configuration](#dashboard-configuration)
- [Alert Rules](#alert-rules)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Components

1. **Grafana** (version 8.0+)
2. **Prometheus** (configured as data source)
3. **Node Exporter** (for system metrics)
4. **Application Metrics** (CHOM custom metrics)

### Required Exporters

```bash
# Node Exporter for system metrics
docker run -d \
  --name=node-exporter \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host

# MySQL Exporter (if using MySQL)
docker run -d \
  --name=mysql-exporter \
  -p 9104:9104 \
  -e DATA_SOURCE_NAME="user:password@(mysql:3306)/" \
  prom/mysqld-exporter

# Redis Exporter (if using Redis)
docker run -d \
  --name=redis-exporter \
  -p 9121:9121 \
  oliver006/redis_exporter \
  --redis.addr=redis://redis:6379
```

---

## Dashboard Overview

### 1. SRE Golden Signals Dashboard
**File:** `sre-golden-signals.json`

**Purpose:** Monitor the four golden signals of SRE: Latency, Traffic, Errors, and Saturation

**Key Metrics:**
- **Latency:** p50, p90, p95, p99 response times
- **Traffic:** Requests per second, bandwidth utilization
- **Errors:** Error rates, error budget tracking
- **Saturation:** CPU, memory, disk, database connections
- **SLO Tracking:** Availability, latency targets, error rate objectives

**Best For:**
- On-call engineers
- SRE teams
- Service reliability monitoring
- SLO/SLA compliance tracking

### 2. DevOps Deployment & Change Management Dashboard
**File:** `devops-deployment.json`

**Purpose:** Track DORA metrics and deployment performance

**Key Metrics:**
- **Deployment Frequency:** How often code is deployed
- **Lead Time for Changes:** Time from commit to production
- **Change Failure Rate:** % of deployments requiring rollback
- **Mean Time to Recovery (MTTR):** Average recovery time
- **Pipeline Success Rate:** CI/CD pipeline health
- **Git Activity:** Commit frequency and patterns

**Best For:**
- Engineering managers
- DevOps teams
- Release management
- Continuous improvement tracking

### 3. Infrastructure Health Dashboard
**File:** `infrastructure-health.json`

**Purpose:** Comprehensive infrastructure monitoring and health checks

**Key Metrics:**
- **Service Health:** Uptime, dependency maps
- **Disk I/O:** Throughput, IOPS, latency
- **Network:** Inter-service latency, bandwidth
- **SSL Certificates:** Expiry tracking for all domains
- **Backups:** Success rates, duration, freshness
- **Logging:** Error trends, log volume
- **System Entropy:** Randomness pool status

**Best For:**
- Infrastructure teams
- Security teams
- Platform engineers
- Capacity planning

---

## Metrics Requirements

### Application Metrics (CHOM)

Your application must expose the following Prometheus metrics:

#### HTTP Metrics
```python
# Python example using prometheus_client
from prometheus_client import Counter, Histogram, Gauge

# Request counter
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'code', 'job']
)

# Request duration histogram
http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint', 'job'],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)

# Request/Response size
http_request_size_bytes = Histogram(
    'http_request_size_bytes',
    'HTTP request size in bytes',
    ['job']
)

http_response_size_bytes = Histogram(
    'http_response_size_bytes',
    'HTTP response size in bytes',
    ['job']
)
```

#### Deployment Metrics
```python
# Deployment tracking
chom_deployment_total = Counter(
    'chom_deployment_total',
    'Total deployments',
    ['type', 'environment', 'version']  # type: deployment|rollback
)

chom_deployment_duration_seconds = Gauge(
    'chom_deployment_duration_seconds',
    'Deployment duration',
    ['environment', 'version']
)

chom_deployment_lead_time_minutes = Gauge(
    'chom_deployment_lead_time_minutes',
    'Lead time from commit to deployment',
    ['environment']
)

chom_deployment_info = Gauge(
    'chom_deployment_info',
    'Deployment information',
    ['type', 'version', 'environment']
)
```

#### Error Budget & SLO Metrics
```python
chom_error_budget_consumed_total = Counter(
    'chom_error_budget_consumed_total',
    'Total error budget consumed',
    ['service']
)
```

#### Incident Metrics
```python
chom_incident_mttr_minutes = Gauge(
    'chom_incident_mttr_minutes',
    'Mean time to recovery in minutes',
    ['severity']
)
```

#### Pipeline Metrics
```python
chom_pipeline_runs_total = Counter(
    'chom_pipeline_runs_total',
    'Total pipeline runs',
    ['pipeline', 'status']  # status: success|failure
)

chom_pipeline_duration_seconds = Histogram(
    'chom_pipeline_duration_seconds',
    'Pipeline duration in seconds',
    ['pipeline', 'stage']
)
```

#### Git Metrics
```python
chom_git_commits_total = Counter(
    'chom_git_commits_total',
    'Total git commits',
    ['branch']
)
```

#### Service Dependency Metrics
```python
chom_service_latency_seconds = Histogram(
    'chom_service_latency_seconds',
    'Inter-service latency',
    ['source_service', 'target_service'],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0)
)
```

#### SSL Certificate Metrics
```python
ssl_certificate_expiry_seconds = Gauge(
    'ssl_certificate_expiry_seconds',
    'SSL certificate expiry timestamp',
    ['domain', 'issuer']
)

ssl_certificate_valid = Gauge(
    'ssl_certificate_valid',
    'SSL certificate validity (1=valid, 0=invalid)',
    ['domain']
)
```

#### Backup Metrics
```python
chom_backup_total = Counter(
    'chom_backup_total',
    'Total backups',
    ['type', 'status']  # type: database|files, status: success|failure
)

chom_backup_duration_seconds = Gauge(
    'chom_backup_duration_seconds',
    'Backup duration',
    ['type', 'instance']
)

chom_backup_last_timestamp_seconds = Gauge(
    'chom_backup_last_timestamp_seconds',
    'Last backup timestamp',
    ['type', 'status']
)

chom_backup_size_bytes = Gauge(
    'chom_backup_size_bytes',
    'Backup size in bytes',
    ['type']
)
```

#### Logging Metrics
```python
chom_log_entries_total = Counter(
    'chom_log_entries_total',
    'Total log entries',
    ['service', 'level', 'error_type']  # level: debug|info|warning|error|critical
)
```

### Example Prometheus Configuration

```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # CHOM Application
  - job_name: 'chom'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter (system metrics)
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  # MySQL Exporter
  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']

  # Redis Exporter
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']

  # Nginx (if using)
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
```

---

## Import Instructions

### Method 1: Grafana UI Import

1. **Login to Grafana**
   - Navigate to your Grafana instance (e.g., `http://localhost:3000`)
   - Login with admin credentials

2. **Access Import Interface**
   - Click the **+** icon in the left sidebar
   - Select **Import**

3. **Upload Dashboard JSON**
   - Click **Upload JSON file**
   - Select one of the dashboard files:
     - `sre-golden-signals.json`
     - `devops-deployment.json`
     - `infrastructure-health.json`

4. **Configure Import Settings**
   - **Name:** Keep default or customize
   - **Folder:** Select or create a folder (recommended: "CHOM - Advanced")
   - **UID:** Keep default or customize
   - **Prometheus Data Source:** Select your Prometheus instance

5. **Complete Import**
   - Click **Import**
   - Repeat for all three dashboards

### Method 2: Provisioning (Automated)

For automated deployment, use Grafana provisioning:

1. **Create Provisioning Directory Structure**
   ```bash
   mkdir -p /etc/grafana/provisioning/dashboards
   mkdir -p /var/lib/grafana/dashboards/chom-advanced
   ```

2. **Copy Dashboard Files**
   ```bash
   cp sre-golden-signals.json /var/lib/grafana/dashboards/chom-advanced/
   cp devops-deployment.json /var/lib/grafana/dashboards/chom-advanced/
   cp infrastructure-health.json /var/lib/grafana/dashboards/chom-advanced/
   ```

3. **Create Provisioning Configuration**
   ```yaml
   # /etc/grafana/provisioning/dashboards/chom-advanced.yml
   apiVersion: 1

   providers:
     - name: 'CHOM Advanced Dashboards'
       orgId: 1
       folder: 'CHOM - Advanced'
       type: file
       disableDeletion: false
       updateIntervalSeconds: 10
       allowUiUpdates: true
       options:
         path: /var/lib/grafana/dashboards/chom-advanced
         foldersFromFilesStructure: false
   ```

4. **Restart Grafana**
   ```bash
   systemctl restart grafana-server
   # or
   docker restart grafana
   ```

### Method 3: Docker Compose

```yaml
version: '3.8'

services:
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana-data:/var/lib/grafana
      - ./dashboards/advanced:/etc/grafana/provisioning/dashboards/chom-advanced
      - ./provisioning:/etc/grafana/provisioning
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      - monitoring

volumes:
  grafana-data:
  prometheus-data:

networks:
  monitoring:
```

---

## Dashboard Configuration

### Data Source Configuration

1. **Verify Prometheus Connection**
   - Navigate to: **Configuration** > **Data Sources**
   - Click on your Prometheus data source
   - Scroll down and click **Save & Test**
   - Should display: "Data source is working"

2. **Configure Scrape Interval**
   - Ensure Prometheus is scraping at appropriate intervals
   - Recommended: 15s for real-time monitoring
   - Adjust in `prometheus.yml`:
     ```yaml
     global:
       scrape_interval: 15s
     ```

### Dashboard Variables

Each dashboard includes template variables for filtering:

#### SRE Golden Signals Dashboard
- **instance:** Filter by server instance (multi-select)
  - Query: `label_values(http_requests_total{job="chom"}, instance)`

#### DevOps Deployment Dashboard
- **environment:** Filter by deployment environment (multi-select)
  - Query: `label_values(chom_deployment_total, environment)`
- **pipeline:** Filter by CI/CD pipeline (multi-select)
  - Query: `label_values(chom_pipeline_runs_total, pipeline)`

#### Infrastructure Health Dashboard
- **instance:** Filter by server instance (multi-select)
  - Query: `label_values(up{job=~"chom|node|mysql|redis"}, instance)`
- **service:** Filter by service type (multi-select)
  - Query: `label_values(up{job=~"chom|node|mysql|redis"}, job)`

### Customizing Thresholds

You can customize alert thresholds for your environment:

1. **Click on Panel Title** > **Edit**
2. **Navigate to Field Tab** (right sidebar)
3. **Find Thresholds Section**
4. **Adjust Values:**
   - Green: Normal/Good
   - Yellow: Warning
   - Red: Critical

**Common Threshold Adjustments:**

| Metric | Default | Adjust Based On |
|--------|---------|----------------|
| CPU % | Yellow: 70%, Red: 90% | Server capacity |
| Memory % | Yellow: 80%, Red: 95% | Available RAM |
| Error Rate | Yellow: 1%, Red: 5% | SLO targets |
| p95 Latency | Yellow: 200ms, Red: 500ms | User expectations |
| Disk Usage | Yellow: 80%, Red: 95% | Storage capacity |

### Time Range Defaults

Each dashboard has optimized default time ranges:

- **SRE Golden Signals:** 6 hours (real-time monitoring)
- **DevOps Deployment:** 7 days (trend analysis)
- **Infrastructure Health:** 6 hours (current state)

**To Change Default:**
1. Set desired time range in top-right picker
2. Click **Save Dashboard** icon
3. Check "Save current time range as dashboard default"

### Refresh Intervals

Default: 30 seconds for all dashboards

**To Adjust:**
1. Click time picker dropdown (top-right)
2. Select refresh interval (10s, 30s, 1m, 5m, etc.)
3. Save dashboard to persist

---

## Alert Rules

### Creating Prometheus Alert Rules

Create alert rules file for Prometheus:

```yaml
# /etc/prometheus/alerts/chom-advanced.yml
groups:
  - name: sre_golden_signals
    interval: 30s
    rules:
      # High Error Rate
      - alert: HighErrorRate
        expr: |
          (
            sum(rate(http_requests_total{job="chom",code=~"5.."}[5m]))
            /
            sum(rate(http_requests_total{job="chom"}[5m]))
          ) * 100 > 5
        for: 5m
        labels:
          severity: critical
          team: sre
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }} (threshold: 5%)"

      # Error Budget Burn Rate
      - alert: ErrorBudgetBurning
        expr: |
          (
            sum(rate(http_requests_total{job="chom",code=~"5.."}[1h]))
            /
            sum(rate(http_requests_total{job="chom"}[1h]))
          ) / (1 - 0.999) > 14.4
        for: 15m
        labels:
          severity: critical
          team: sre
        annotations:
          summary: "Error budget burning too fast"
          description: "Current burn rate: {{ $value | humanize }} (consumes 30d budget in 2d)"

      # High Latency
      - alert: HighLatency
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket{job="chom"}[5m])) by (le)
          ) * 1000 > 500
        for: 10m
        labels:
          severity: warning
          team: sre
        annotations:
          summary: "High latency detected"
          description: "p95 latency is {{ $value | humanize }}ms (threshold: 500ms)"

      # Service Down
      - alert: ServiceDown
        expr: up{job=~"chom|mysql|redis"} == 0
        for: 1m
        labels:
          severity: critical
          team: sre
        annotations:
          summary: "Service {{ $labels.job }} is down"
          description: "Service {{ $labels.job }} on {{ $labels.instance }} is unreachable"

      # High CPU Usage
      - alert: HighCPUUsage
        expr: |
          100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle",job="node"}[5m])) * 100) > 90
        for: 15m
        labels:
          severity: warning
          team: infrastructure
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value | humanize }}%"

      # High Memory Usage
      - alert: HighMemoryUsage
        expr: |
          (
            1 - (
              node_memory_MemAvailable_bytes{job="node"}
              /
              node_memory_MemTotal_bytes{job="node"}
            )
          ) * 100 > 95
        for: 10m
        labels:
          severity: critical
          team: infrastructure
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | humanize }}%"

      # Disk Space Low
      - alert: DiskSpaceLow
        expr: |
          (
            1 - (
              node_filesystem_avail_bytes{job="node",fstype!~"tmpfs|fuse.lxcfs|squashfs|vfat"}
              /
              node_filesystem_size_bytes{job="node",fstype!~"tmpfs|fuse.lxcfs|squashfs|vfat"}
            )
          ) * 100 > 90
        for: 5m
        labels:
          severity: warning
          team: infrastructure
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk usage is {{ $value | humanize }}% on {{ $labels.mountpoint }}"

  - name: devops_deployment
    interval: 60s
    rules:
      # High Change Failure Rate
      - alert: HighChangeFailureRate
        expr: |
          (
            sum(increase(chom_deployment_total{type="rollback"}[7d])) by (environment)
            /
            sum(increase(chom_deployment_total{type="deployment"}[7d])) by (environment)
          ) * 100 > 20
        for: 1h
        labels:
          severity: warning
          team: devops
        annotations:
          summary: "High change failure rate in {{ $labels.environment }}"
          description: "Failure rate is {{ $value | humanize }}% (threshold: 20%)"

      # Pipeline Failure
      - alert: PipelineFailureRate
        expr: |
          (
            sum(rate(chom_pipeline_runs_total{status="success"}[1h])) by (pipeline)
            /
            sum(rate(chom_pipeline_runs_total[1h])) by (pipeline)
          ) * 100 < 80
        for: 30m
        labels:
          severity: warning
          team: devops
        annotations:
          summary: "Low pipeline success rate for {{ $labels.pipeline }}"
          description: "Success rate is {{ $value | humanize }}% (threshold: 80%)"

  - name: infrastructure_health
    interval: 60s
    rules:
      # SSL Certificate Expiring Soon
      - alert: SSLCertificateExpiringSoon
        expr: (ssl_certificate_expiry_seconds - time()) / 86400 < 30
        for: 1h
        labels:
          severity: warning
          team: security
        annotations:
          summary: "SSL certificate for {{ $labels.domain }} expiring soon"
          description: "Certificate expires in {{ $value | humanize }} days"

      # SSL Certificate Expired
      - alert: SSLCertificateExpired
        expr: (ssl_certificate_expiry_seconds - time()) / 86400 < 0
        for: 5m
        labels:
          severity: critical
          team: security
        annotations:
          summary: "SSL certificate for {{ $labels.domain }} has EXPIRED"
          description: "Certificate expired {{ $value | humanize }} days ago"

      # Backup Failed
      - alert: BackupFailed
        expr: |
          (
            sum(rate(chom_backup_total{status="success"}[24h])) by (type)
            /
            sum(rate(chom_backup_total[24h])) by (type)
          ) * 100 < 95
        for: 1h
        labels:
          severity: critical
          team: infrastructure
        annotations:
          summary: "Backup failures detected for {{ $labels.type }}"
          description: "Success rate is {{ $value | humanize }}% (threshold: 95%)"

      # Backup Too Old
      - alert: BackupTooOld
        expr: (time() - chom_backup_last_timestamp_seconds) / 3600 > 48
        for: 1h
        labels:
          severity: warning
          team: infrastructure
        annotations:
          summary: "Backup for {{ $labels.type }} is stale"
          description: "Last successful backup was {{ $value | humanize }} hours ago"

      # High Log Error Rate
      - alert: HighLogErrorRate
        expr: sum(rate(chom_log_entries_total{level="error"}[5m])) by (service) > 10
        for: 10m
        labels:
          severity: warning
          team: sre
        annotations:
          summary: "High error log rate in {{ $labels.service }}"
          description: "Error rate is {{ $value | humanize }} errors/sec"

      # Low System Entropy
      - alert: LowSystemEntropy
        expr: node_entropy_available_bits{job="node"} < 200
        for: 5m
        labels:
          severity: warning
          team: security
        annotations:
          summary: "Low system entropy on {{ $labels.instance }}"
          description: "Available entropy: {{ $value | humanize }} bits (threshold: 200)"
```

### Adding Alert Rules to Prometheus

1. **Update Prometheus Configuration**
   ```yaml
   # /etc/prometheus/prometheus.yml
   rule_files:
     - "alerts/chom-advanced.yml"
   ```

2. **Validate Configuration**
   ```bash
   promtool check config /etc/prometheus/prometheus.yml
   promtool check rules /etc/prometheus/alerts/chom-advanced.yml
   ```

3. **Reload Prometheus**
   ```bash
   # Send SIGHUP to reload
   killall -HUP prometheus

   # Or restart service
   systemctl restart prometheus

   # Or Docker
   docker restart prometheus
   ```

### Configuring Alertmanager

```yaml
# /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'team-notifications'
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
      continue: true
    - match:
        team: sre
      receiver: 'sre-team'
    - match:
        team: devops
      receiver: 'devops-team'
    - match:
        team: infrastructure
      receiver: 'infrastructure-team'

receivers:
  - name: 'team-notifications'
    slack_configs:
      - channel: '#monitoring-alerts'
        title: 'CHOM Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'critical-alerts'
    slack_configs:
      - channel: '#critical-alerts'
        title: 'CRITICAL: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'

  - name: 'sre-team'
    slack_configs:
      - channel: '#sre-team'

  - name: 'devops-team'
    slack_configs:
      - channel: '#devops-team'

  - name: 'infrastructure-team'
    slack_configs:
      - channel: '#infrastructure-team'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

---

## Troubleshooting

### No Data Displayed

**Problem:** Dashboard panels show "No data"

**Solutions:**

1. **Verify Prometheus is scraping targets**
   ```bash
   # Check Prometheus targets
   curl http://localhost:9090/api/v1/targets

   # Or visit Prometheus UI
   # http://localhost:9090/targets
   ```

2. **Check if metrics exist**
   ```bash
   # Query Prometheus
   curl 'http://localhost:9090/api/v1/query?query=up'

   # Should return instances with up=1
   ```

3. **Verify data source in Grafana**
   - Configuration > Data Sources > Prometheus
   - Click "Save & Test"
   - Should show: "Data source is working"

4. **Check time range**
   - Ensure time range covers when metrics were collected
   - Try selecting "Last 24 hours"

5. **Verify metric names**
   - Some metrics may have different names in your setup
   - Use Prometheus query browser to find actual metric names
   - Update dashboard queries accordingly

### Queries Timing Out

**Problem:** Panels show "Query timeout" or take very long to load

**Solutions:**

1. **Increase Grafana timeout**
   ```ini
   # /etc/grafana/grafana.ini
   [dataproxy]
   timeout = 300
   ```

2. **Optimize Prometheus queries**
   - Reduce time range
   - Use recording rules for complex queries
   - Increase scrape interval if too frequent

3. **Add Prometheus recording rules**
   ```yaml
   # /etc/prometheus/rules/chom-recording.yml
   groups:
     - name: chom_recordings
       interval: 30s
       rules:
         - record: chom:http_request_duration_seconds:p95
           expr: |
             histogram_quantile(0.95,
               sum(rate(http_request_duration_seconds_bucket{job="chom"}[5m])) by (le)
             )

         - record: chom:error_rate:5m
           expr: |
             sum(rate(http_requests_total{job="chom",code=~"5.."}[5m]))
             /
             sum(rate(http_requests_total{job="chom"}[5m]))
   ```

### Missing Metrics

**Problem:** Some panels work, others show "No data"

**Solutions:**

1. **Check which metrics are missing**
   - Visit Prometheus query browser
   - Try querying specific metric names
   - Example: `chom_deployment_total`

2. **Ensure application is exporting metrics**
   ```bash
   # Check application metrics endpoint
   curl http://localhost:9090/metrics | grep chom_
   ```

3. **Add missing metrics to your application**
   - Refer to [Metrics Requirements](#metrics-requirements) section
   - Implement missing metrics in your code
   - Restart application

4. **Use conditional queries**
   - Some panels may require optional features
   - Disable panels for non-existent metrics
   - Or modify queries to handle missing data

### Incorrect Values

**Problem:** Metrics show but values seem wrong

**Solutions:**

1. **Verify metric labels**
   - Ensure label names match (job, instance, etc.)
   - Check label values are correct
   - Update queries to match your labels

2. **Check aggregation functions**
   - Some queries use `sum()`, `avg()`, etc.
   - Ensure aggregation makes sense for your setup
   - Adjust `by (label)` clauses as needed

3. **Verify units and formatting**
   - Check panel units (seconds, bytes, etc.)
   - Ensure histogram buckets match your data
   - Adjust thresholds for your scale

### Dashboard Variables Not Working

**Problem:** Template variables show no options or don't filter

**Solutions:**

1. **Check variable queries**
   - Dashboard Settings > Variables
   - Test query in Prometheus
   - Ensure metric and labels exist

2. **Verify variable syntax in panels**
   - Should use `$variable` or `${variable}`
   - Multi-value variables need regex: `=~"$variable"`

3. **Refresh variable options**
   - Variables > Refresh icon
   - Or set auto-refresh in variable settings

### Permission Issues

**Problem:** Cannot import dashboards or save changes

**Solutions:**

1. **Check Grafana user permissions**
   - Admin users can import dashboards
   - Editors can modify dashboards
   - Viewers cannot make changes

2. **Verify folder permissions**
   - Ensure user has access to target folder
   - Create new folder if needed

3. **Check provisioning conflicts**
   - Provisioned dashboards may be read-only
   - Set `allowUiUpdates: true` in provisioning config
   - Or remove from provisioning to allow edits

---

## Best Practices

### Dashboard Organization

1. **Create Folder Structure**
   ```
   CHOM Dashboards/
   ├── Advanced/
   │   ├── SRE Golden Signals
   │   ├── DevOps Deployment
   │   └── Infrastructure Health
   ├── Basic/
   │   ├── System Overview
   │   └── Application
   └── Business/
       └── Business Metrics
   ```

2. **Use Consistent Naming**
   - Prefix with project: "CHOM - Dashboard Name"
   - Makes searching easier
   - Groups related dashboards

3. **Tag Appropriately**
   - Each dashboard has relevant tags
   - Makes filtering and searching easier
   - Examples: `chom`, `sre`, `devops`, `infrastructure`

### Performance Optimization

1. **Use Recording Rules**
   - Pre-calculate expensive queries
   - Reduces dashboard load time
   - See recording rules example above

2. **Limit Time Ranges**
   - Don't query years of data
   - Use appropriate defaults (6h, 7d, 30d)
   - Add time range selector for flexibility

3. **Optimize Query Intervals**
   - Match scrape interval
   - Use `[5m]` rate intervals for 15s scrape
   - Adjust based on data granularity needs

4. **Cache Dashboard Data**
   ```ini
   # /etc/grafana/grafana.ini
   [caching]
   enabled = true
   ```

### Monitoring Best Practices

1. **Set Appropriate SLOs**
   - Availability: 99.9% (adjust based on tier)
   - Latency: p95 < 200ms (adjust for API type)
   - Error Rate: < 0.1% (adjust for criticality)

2. **Regular Review**
   - Weekly: Review error budget consumption
   - Monthly: Adjust SLOs and thresholds
   - Quarterly: Optimize queries and add features

3. **Alert Tuning**
   - Start with conservative thresholds
   - Tune based on false positive rate
   - Use multi-window alerts (1h + 6h burn rate)

4. **Documentation**
   - Document custom metrics
   - Maintain runbooks for alerts
   - Keep dashboard annotations updated

---

## Additional Resources

### Documentation
- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Google SRE Book - Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)

### Community Dashboards
- [Grafana Dashboard Library](https://grafana.com/grafana/dashboards/)
- [Awesome Prometheus Alerts](https://awesome-prometheus-alerts.grep.to/)

### CHOM-Specific
- Main Import Guide: `/deploy/grafana-dashboards/IMPORT_GUIDE.md`
- Basic Dashboards: `/deploy/grafana-dashboards/*.json`

---

## Support

If you encounter issues not covered in this guide:

1. **Check Logs**
   - Grafana: `/var/log/grafana/grafana.log`
   - Prometheus: `docker logs prometheus` or journalctl

2. **Verify Configuration**
   - Use `promtool check config` for Prometheus
   - Check Grafana UI for data source errors

3. **Community Resources**
   - Grafana Community Forums
   - Prometheus Mailing List
   - Stack Overflow (tags: grafana, prometheus)

---

**Version:** 1.0
**Last Updated:** 2026-01-02
**Maintained By:** CHOM SRE Team
