# Observability Integration - Prometheus Configuration

## Overview

This guide covers Prometheus configuration to scrape metrics from the CHOM application server (landsraad) including Node Exporter, application metrics, and various service exporters.

## Architecture

```
mentat (Observability)                    landsraad (CHOM Application)
┌─────────────────────┐                  ┌──────────────────────────┐
│   Prometheus        │                  │  Metrics Exporters       │
│   Port: 9090        │◄─────────────────┤  - Node Exporter: 9100   │
│                     │      Scrape      │  - PHP-FPM: 9253         │
│  - Scrape Config    │      Interval:   │  - Nginx: 9113           │
│  - Alert Rules      │      15 seconds  │  - MySQL: 9104           │
│  - Recording Rules  │                  │  - Redis: 9121           │
│                     │                  │  - CHOM App: 8080        │
└─────────────────────┘                  └──────────────────────────┘
         │                                          ▲
         │                                          │
         │ Query (PromQL)                           │ Metrics (Prometheus format)
         │                                          │
         ▼                                          │
┌─────────────────────┐                           │
│   Grafana           │                           │
│   Port: 3000        │◄──────────────────────────┘
│                     │
│  - Dashboards       │
│  - Alerts           │
│  - Notifications    │
└─────────────────────┘
```

## Phase 1: Verify Exporters are Running

Before configuring Prometheus, ensure all exporters are installed and running on landsraad.

### Check Exporter Status

```bash
# SSH to landsraad
ssh user@landsraad.arewel.com

# 1. Node Exporter (System metrics)
sudo systemctl status node-exporter
curl -s http://localhost:9100/metrics | head -20

# 2. PHP-FPM Exporter (PHP process manager metrics)
sudo systemctl status php-fpm-exporter
curl -s http://localhost:9253/metrics | head -20

# 3. Nginx Exporter
sudo systemctl status nginx-exporter
curl -s http://localhost:9113/metrics | head -20

# 4. MySQL Exporter
sudo systemctl status mysql-exporter
curl -s http://localhost:9104/metrics | head -20

# 5. Redis Exporter
sudo systemctl status redis-exporter
curl -s http://localhost:9121/metrics | head -20

# 6. CHOM Application Metrics (if using Laravel Prometheus bundle)
curl -s http://localhost:8080/metrics | head -20
```

If any exporter is not running:

```bash
# Install and enable
sudo systemctl enable node-exporter
sudo systemctl start node-exporter

# Verify
sudo systemctl status node-exporter
```

## Phase 2: Prometheus Configuration

### Step 2.1: Update Prometheus Configuration

On mentat, edit the Prometheus configuration file:

```bash
# Navigate to Prometheus config
cd /etc/prometheus
sudo cp prometheus.yml prometheus.yml.backup

# Edit with your preferred editor
sudo nano prometheus.yml
```

### Step 2.2: Add CHOM Scrape Jobs

Add the following to the `scrape_configs:` section in `prometheus.yml`:

```yaml
# ============================================================================
# CHOM Application Metrics Collection
# ============================================================================

scrape_configs:
  # ====== CHOM Node Metrics ======
  - job_name: 'chom-node'
    scrape_interval: 15s
    scrape_timeout: 10s

    static_configs:
      - targets: ['51.77.150.96:9100']
        labels:
          environment: 'production'
          server: 'landsraad'
          type: 'system'

    # Metric relabeling
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.+'
        replacement: '${1}'

  # ====== PHP-FPM Metrics ======
  - job_name: 'chom-php-fpm'
    scrape_interval: 15s
    scrape_timeout: 10s

    static_configs:
      - targets: ['51.77.150.96:9253']
        labels:
          environment: 'production'
          server: 'landsraad'
          type: 'app-runtime'

    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.+'
        replacement: '${1}'

  # ====== Nginx Metrics ======
  - job_name: 'chom-nginx'
    scrape_interval: 15s
    scrape_timeout: 10s

    static_configs:
      - targets: ['51.77.150.96:9113']
        labels:
          environment: 'production'
          server: 'landsraad'
          type: 'webserver'

    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.+'
        replacement: '${1}'

  # ====== MySQL Metrics ======
  - job_name: 'chom-mysql'
    scrape_interval: 30s
    scrape_timeout: 10s

    static_configs:
      - targets: ['51.77.150.96:9104']
        labels:
          environment: 'production'
          server: 'landsraad'
          type: 'database'

    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.+'
        replacement: '${1}'

  # ====== Redis Metrics ======
  - job_name: 'chom-redis'
    scrape_interval: 15s
    scrape_timeout: 10s

    static_configs:
      - targets: ['51.77.150.96:9121']
        labels:
          environment: 'production'
          server: 'landsraad'
          type: 'cache'

    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.+'
        replacement: '${1}'

  # ====== CHOM Application Metrics ======
  - job_name: 'chom-app'
    scrape_interval: 15s
    scrape_timeout: 10s

    metrics_path: '/metrics'
    scheme: https

    tls_config:
      insecure_skip_verify: false  # Set to true for self-signed certs

    # Basic auth if required
    # basic_auth:
    #   username: 'prometheus'
    #   password: 'secure-password'

    static_configs:
      - targets: ['landsraad.arewel.com:443']
        labels:
          environment: 'production'
          server: 'landsraad'
          type: 'application'

    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.+'
        replacement: '${1}'
```

### Step 2.3: Global Configuration Settings

Ensure the following global settings are in place:

```yaml
global:
  scrape_interval: 15s          # Default scrape interval
  evaluation_interval: 15s      # How often to evaluate rules
  external_labels:
    monitor: 'chom-production'
    environment: 'production'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Load rules once and periodically evaluate them
rule_files:
  - "/etc/prometheus/rules/*.yml"
  - "/etc/prometheus/rules/chom-alerts.yml"
  - "/etc/prometheus/rules/chom-recording.yml"
```

### Step 2.4: Validate Configuration

Before reloading Prometheus, validate the configuration:

```bash
# Check syntax
promtool check config /etc/prometheus/prometheus.yml

# Check rules (if defined)
promtool check rules /etc/prometheus/rules/chom-alerts.yml
promtool check rules /etc/prometheus/rules/chom-recording.yml

# Expected output: "SUCCESS"
```

### Step 2.5: Reload Prometheus

Reload Prometheus to apply configuration changes:

```bash
# Option 1: Using systemctl (graceful reload)
sudo systemctl reload prometheus

# Option 2: Send HUP signal
sudo kill -HUP $(pidof prometheus)

# Option 3: Using Prometheus HTTP API
curl -X POST http://localhost:9090/-/reload

# Verify Prometheus reloaded successfully
curl -s http://localhost:9090/api/v1/status/config | jq '.status'
```

## Phase 3: Verify Scrape Configuration

### Step 3.1: Check Targets in Prometheus UI

Navigate to Prometheus web interface:

```
http://mentat.arewel.com:9090
```

1. Go to **Status > Targets**
2. Verify all CHOM targets appear (should show green "UP" status)
3. Check for any errors in the "Errors" section

### Step 3.2: Query Metrics

In Prometheus web interface, go to **Graph** tab and test queries:

```promql
# 1. Check if node_exporter metrics exist
up{job="chom-node"}

# 2. Check CPU usage
rate(node_cpu_seconds_total{job="chom-node"}[5m])

# 3. Check memory usage
node_memory_MemAvailable_bytes{job="chom-node"}

# 4. Check PHP-FPM metrics
php_fpm_processes{job="chom-php-fpm"}

# 5. Check Nginx requests
rate(nginx_http_requests_total{job="chom-nginx"}[5m])

# 6. Check MySQL connections
mysql_global_status_threads_connected{job="chom-mysql"}

# 7. Check Redis memory
redis_memory_used_bytes{job="chom-redis"}
```

Expected output: Should return time series data, not empty results.

### Step 3.3: Check Metrics Count

```bash
# Get metrics from each job
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Expected output shows UP status for all targets
```

## Phase 4: Alert Rules Configuration

### Step 4.1: Create Alert Rules File

Create alert rules for CHOM monitoring:

```bash
sudo nano /etc/prometheus/rules/chom-alerts.yml
```

Add the following alert rules:

```yaml
groups:
  - name: chom-alerts
    interval: 30s
    rules:
      # ====== Availability Alerts ======
      - alert: CHOMDown
        expr: up{job=~"chom.*"} == 0
        for: 2m
        labels:
          severity: critical
          service: chom
        annotations:
          summary: "CHOM {{ $labels.job }} is down"
          description: "CHOM {{ $labels.job }} on {{ $labels.instance }} has been unreachable for 2 minutes."

      # ====== System Resource Alerts ======
      - alert: CHOMHighCPUUsage
        expr: |
          (100 - (avg(rate(node_cpu_seconds_total{job="chom-node",mode="idle"}[5m])) * 100)) > 80
        for: 5m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "CHOM high CPU usage ({{ $value | humanize }}%)"
          description: "CHOM on {{ $labels.instance }} has CPU usage above 80% for 5 minutes."

      - alert: CHOMHighMemoryUsage
        expr: |
          (1 - (node_memory_MemAvailable_bytes{job="chom-node"} / node_memory_MemTotal_bytes{job="chom-node"})) * 100 > 85
        for: 5m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "CHOM high memory usage ({{ $value | humanize }}%)"
          description: "CHOM on {{ $labels.instance }} has memory usage above 85% for 5 minutes."

      - alert: CHOMDiskSpaceLow
        expr: |
          (node_filesystem_avail_bytes{job="chom-node",fstype!~"tmpfs"} / node_filesystem_size_bytes{job="chom-node",fstype!~"tmpfs"}) * 100 < 10
        for: 5m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "CHOM disk space low ({{ $value | humanize }}% free)"
          description: "CHOM {{ $labels.device }} has less than 10% free space."

      # ====== Database Alerts ======
      - alert: MySQLDown
        expr: up{job="chom-mysql"} == 0
        for: 1m
        labels:
          severity: critical
          service: chom
        annotations:
          summary: "MySQL is down"
          description: "MySQL on {{ $labels.instance }} has been unreachable for 1 minute."

      - alert: MySQLHighConnections
        expr: |
          mysql_global_status_threads_connected{job="chom-mysql"} / mysql_global_variables_max_connections{job="chom-mysql"} > 0.8
        for: 5m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "MySQL high connection usage"
          description: "MySQL is using {{ $value | humanizePercentage }} of max connections."

      # ====== Cache Alerts ======
      - alert: RedisDown
        expr: up{job="chom-redis"} == 0
        for: 1m
        labels:
          severity: critical
          service: chom
        annotations:
          summary: "Redis is down"
          description: "Redis on {{ $labels.instance }} has been unreachable for 1 minute."

      - alert: RedisHighMemoryUsage
        expr: |
          redis_memory_used_bytes{job="chom-redis"} / redis_memory_max_bytes{job="chom-redis"} > 0.9
        for: 5m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "Redis high memory usage"
          description: "Redis is using {{ $value | humanizePercentage }} of max memory."

      # ====== Application Alerts ======
      - alert: PHPFPMNoIdleProcesses
        expr: |
          php_fpm_processes{state="idle",job="chom-php-fpm"} == 0
        for: 2m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "PHP-FPM has no idle processes"
          description: "PHP-FPM on {{ $labels.instance }} has no available idle processes."

      # ====== Web Server Alerts ======
      - alert: NginxHighErrorRate
        expr: |
          rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
          service: chom
        annotations:
          summary: "Nginx high error rate"
          description: "Nginx error rate is {{ $value | humanizePercentage }} (5xx errors)."
```

### Step 4.2: Create Recording Rules

Recording rules pre-compute frequently queried expressions:

```bash
sudo nano /etc/prometheus/rules/chom-recording.yml
```

```yaml
groups:
  - name: chom-recording
    interval: 30s
    rules:
      # ====== System Metrics ======
      - record: chom:node:cpu:usage
        expr: |
          100 - (avg(rate(node_cpu_seconds_total{job="chom-node",mode="idle"}[5m])) * 100)

      - record: chom:node:memory:usage_percentage
        expr: |
          (1 - (node_memory_MemAvailable_bytes{job="chom-node"} / node_memory_MemTotal_bytes{job="chom-node"})) * 100

      - record: chom:node:disk:usage_percentage
        expr: |
          (1 - (node_filesystem_avail_bytes{job="chom-node"} / node_filesystem_size_bytes{job="chom-node"})) * 100

      # ====== PHP-FPM Metrics ======
      - record: chom:php_fpm:pool:busy_processes_ratio
        expr: |
          php_fpm_processes{state="busy",job="chom-php-fpm"} / php_fpm_processes{state="idle",job="chom-php-fpm"} + php_fpm_processes{state="busy",job="chom-php-fpm"}

      # ====== MySQL Metrics ======
      - record: chom:mysql:connection:usage_percentage
        expr: |
          (mysql_global_status_threads_connected{job="chom-mysql"} / mysql_global_variables_max_connections{job="chom-mysql"}) * 100

      - record: chom:mysql:queries:rate
        expr: |
          rate(mysql_global_status_questions{job="chom-mysql"}[5m])

      # ====== Nginx Metrics ======
      - record: chom:nginx:request:rate
        expr: |
          rate(nginx_http_requests_total{job="chom-nginx"}[5m])

      - record: chom:nginx:request:error_rate
        expr: |
          rate(nginx_http_requests_total{status=~"5..",job="chom-nginx"}[5m]) /
          rate(nginx_http_requests_total{job="chom-nginx"}[5m])

      # ====== Redis Metrics ======
      - record: chom:redis:memory:usage_percentage
        expr: |
          (redis_memory_used_bytes{job="chom-redis"} / redis_memory_max_bytes{job="chom-redis"}) * 100
```

### Step 4.3: Validate and Reload Rules

```bash
# Validate rules syntax
promtool check rules /etc/prometheus/rules/chom-alerts.yml
promtool check rules /etc/prometheus/rules/chom-recording.yml

# Reload Prometheus
sudo systemctl reload prometheus

# Verify in Prometheus UI
# Go to: Status > Rules
```

## Phase 5: Monitoring Dashboard Setup

### Step 5.1: Access Grafana

Navigate to Grafana:

```
http://mentat.arewel.com:3000
```

Default credentials: `admin` / `admin`

### Step 5.2: Add Prometheus Data Source

1. Go to **Configuration > Data Sources**
2. Click **Add data source**
3. Select **Prometheus**
4. Configure:
   - **URL:** `http://localhost:9090`
   - **Access:** `Server (default)`
   - **Scrape interval:** Leave default
5. Click **Save & Test**

Expected: "Data source is working"

### Step 5.3: Import CHOM Dashboard

1. Go to **+ Create > Import**
2. Enter JSON dashboard (see below) or use dashboard ID from Grafana marketplace
3. Select Prometheus data source
4. Click **Import**

### Step 5.4: Create Custom Dashboard

Create a dashboard with the following panels:

```
Row 1: System Overview
  - CPU Usage: chom:node:cpu:usage
  - Memory Usage: chom:node:memory:usage_percentage
  - Disk Usage: chom:node:disk:usage_percentage

Row 2: Application Health
  - PHP-FPM Status: up{job="chom-php-fpm"}
  - Nginx Requests: chom:nginx:request:rate
  - Database Connections: chom:mysql:connection:usage_percentage

Row 3: Performance
  - Request Rate: chom:nginx:request:rate
  - Error Rate: chom:nginx:request:error_rate
  - Query Rate: chom:mysql:queries:rate
```

## Phase 6: Remote Storage Configuration (Optional)

If storing metrics in remote storage (e.g., Mimir, Thanos):

```yaml
# Add to prometheus.yml
remote_write:
  - url: http://mimir:9009/api/prom/push
    queue_config:
      capacity: 10000
      max_shards: 50
      min_shards: 1
      max_samples_per_send: 2000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
```

## Troubleshooting

### Issue: Targets showing "DOWN"

```bash
# 1. Check if exporter is running on target server
ssh landsraad.arewel.com
sudo systemctl status node-exporter

# 2. Test connectivity
curl -v http://51.77.150.96:9100/metrics

# 3. Check Prometheus logs
sudo journalctl -u prometheus -f

# 4. Verify firewall rules
sudo ufw status | grep 9100
```

### Issue: No metrics in queries

```bash
# 1. Check target health in Prometheus UI
# Status > Targets

# 2. Test metrics endpoint directly
curl -s http://51.77.150.96:9100/metrics | grep node_cpu

# 3. Check Prometheus storage
du -sh /var/lib/prometheus

# 4. Verify scrape interval
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[0]'
```

### Issue: High memory/disk usage in Prometheus

```bash
# Adjust retention policy
# Edit /etc/prometheus/prometheus.yml

global:
  external_labels:
    # ...
  # Reduce retention to 7 days

# Add to command line or systemd unit:
# --storage.tsdb.retention.time=7d
# --storage.tsdb.retention.size=50GB

# Restart Prometheus
sudo systemctl restart prometheus
```

## Next Steps

1. **Configure log shipping** (see `03-LOG-SHIPPING.md`)
2. **Run verification tests** (see `04-VERIFICATION.md`)
3. **Setup alerting** (configure AlertManager integration)
4. **Create dashboards** (customize Grafana dashboards)

## Quick Reference

```bash
# Check Prometheus status
curl -s http://localhost:9090/-/healthy

# List all active targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets'

# Query specific metric
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.'

# Check configuration
curl -s 'http://localhost:9090/api/v1/status/config' | jq '.data.yaml' | head -100

# Reload configuration
curl -X POST http://localhost:9090/-/reload

# List alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[]'
```
