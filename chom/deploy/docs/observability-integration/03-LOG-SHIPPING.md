# Observability Integration - Log Shipping Configuration

## Overview

This guide covers setting up log shipping from CHOM application (landsraad) to Loki on the observability server (mentat) using Grafana Alloy, which combines agent and log forwarding capabilities.

## Architecture

```
landsraad (CHOM Application)              mentat (Observability)
┌──────────────────────────┐             ┌──────────────────┐
│  Log Sources             │             │   Loki           │
│  - CHOM app logs         │             │   Port: 3100     │
│  - Laravel logs          │             │                  │
│  - Nginx access logs     │    Push     │ Log Storage &    │
│  - Nginx error logs      ├────────────►│ Querying         │
│  - PHP-FPM logs          │             │                  │
│  - Security logs         │   (HTTP)    │                  │
│  - Performance logs      │   Port 3100 │                  │
│  - Audit logs            │             │                  │
│                          │             └──────────────────┘
│  Grafana Alloy Agent     │                     ▲
│  ┌────────────────────┐  │                     │
│  │ - File targets     │  │                     │ Query (LogQL)
│  │ - JSON parsing     │  │                     │
│  │ - Relabeling       │  │                     │
│  │ - Filtering        │  │                     │
│  │ - Batching         │  │                     │
│  └────────────────────┘  │             ┌──────────────────┐
└──────────────────────────┘             │   Grafana        │
                                         │   Port: 3000     │
                                         │                  │
                                         │ Dashboard &      │
                                         │ Log Exploration  │
                                         └──────────────────┘
```

## Phase 1: Alloy Installation

### Step 1.1: Install Grafana Alloy on landsraad

```bash
# SSH to landsraad
ssh user@landsraad.arewel.com

# Download and install Alloy
sudo apt-get update
sudo apt-get install -y grafana-alloy

# Verify installation
alloy --version
sudo systemctl status grafana-alloy
```

### Step 1.2: Verify Alloy Service

```bash
# Check if Alloy is running
sudo systemctl status grafana-alloy

# View logs
sudo journalctl -u grafana-alloy -f

# Check Alloy is listening
sudo netstat -tlnp | grep alloy

# Expected: Alloy running and listening on admin port (typically 12345)
```

## Phase 2: Log Source Discovery

### Step 2.1: Identify Log Locations

On landsraad, find all relevant log files:

```bash
# CHOM application logs
ls -la /var/www/chom/storage/logs/

# Laravel logs
ls -la /var/www/chom/storage/logs/laravel-*.log

# Nginx logs
ls -la /var/log/nginx/

# PHP-FPM logs
ls -la /var/log/php*-fpm.log

# System logs
ls -la /var/log/

# Ownership and permissions check
stat /var/www/chom/storage/logs/
stat /var/log/nginx/
```

### Step 2.2: Verify Log Readability

Ensure Alloy can read the logs:

```bash
# Check if current user can read logs
cat /var/www/chom/storage/logs/app.log | head -5

# If permission denied, add Alloy user to appropriate group
sudo usermod -a -G adm grafana-alloy
sudo usermod -a -G www-data grafana-alloy

# Restart Alloy
sudo systemctl restart grafana-alloy
```

## Phase 3: Alloy Configuration

### Step 3.1: Create Alloy Configuration

Edit the Alloy configuration file:

```bash
# Create or edit configuration
sudo nano /etc/alloy/config.alloy
```

### Step 3.2: Basic Alloy Configuration

Use the following as a template (also available in existing config):

```alloy
// ============================================================================
// Grafana Alloy Configuration for CHOM Log Shipping
// ============================================================================

// ============================================================================
// LOKI CONFIGURATION - Remote write endpoint
// ============================================================================

loki.write "default" {
    endpoint {
        url = "http://51.254.139.78:3100/loki/api/v1/push"

        // Tenant ID for multi-tenant Loki
        tenant_id = "chom"

        // Batching configuration for performance
        batchwait = "1s"
        batchsize = "1MiB"

        // Retry configuration
        min_backoff_period = "500ms"
        max_backoff_period = "5m"
        max_backoff_retries = 10
    }

    external_labels = {
        environment = "production",
        instance    = "landsraad",
        app         = "chom",
        region      = "eu-west",
    }
}

// ============================================================================
// LOG SOURCES - File monitoring
// ============================================================================

// CHOM Application JSON Logs
local.file_match "chom_app_logs" {
    path_targets = [{
        __path__ = "/var/www/chom/storage/logs/app.json",
        job      = "chom",
        log_type = "app",
    }]
}

loki.source.file "chom_app" {
    targets    = local.file_match.chom_app_logs.targets
    forward_to = [loki.process.chom_json.receiver]
}

// JSON log processing
loki.process "chom_json" {
    stage.json {
        expressions = {
            level    = "level",
            message  = "message",
            context  = "context",
            channel  = "channel",
            datetime = "datetime",
        }
    }

    stage.labels {
        values = {
            level   = "",
            channel = "",
        }
    }

    stage.timestamp {
        source = "datetime"
        format = "RFC3339Nano"
    }

    stage.output {
        source = "message"
    }

    forward_to = [loki.write.default.receiver]
}

// Laravel Log Files
local.file_match "chom_laravel_logs" {
    path_targets = [{
        __path__ = "/var/www/chom/storage/logs/laravel-*.log",
        job      = "chom",
        log_type = "laravel",
    }]
}

loki.source.file "chom_laravel" {
    targets    = local.file_match.chom_laravel_logs.targets
    forward_to = [loki.process.chom_laravel.receiver]
}

loki.process "chom_laravel" {
    // Laravel log format: [YYYY-MM-DD HH:MM:SS] environment.LEVEL: message
    stage.regex {
        expression = "^\\[(?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\] (?P<env>\\w+)\\.(?P<level>\\w+): (?P<message>.*)$"
    }

    stage.labels {
        values = {
            level = "",
        }
    }

    stage.timestamp {
        source = "timestamp"
        format = "2006-01-02 15:04:05"
    }

    stage.output {
        source = "message"
    }

    forward_to = [loki.write.default.receiver]
}

// Performance Logs
local.file_match "chom_performance_logs" {
    path_targets = [{
        __path__ = "/var/www/chom/storage/logs/performance-*.log",
        job      = "chom",
        log_type = "performance",
    }]
}

loki.source.file "chom_performance" {
    targets    = local.file_match.chom_performance_logs.targets
    forward_to = [loki.process.chom_laravel.receiver]
}

// Security Logs
local.file_match "chom_security_logs" {
    path_targets = [{
        __path__ = "/var/www/chom/storage/logs/security-*.log",
        job      = "chom",
        log_type = "security",
    }]
}

loki.source.file "chom_security" {
    targets    = local.file_match.chom_security_logs.targets
    forward_to = [loki.process.chom_laravel.receiver]
}

// Audit Logs
local.file_match "chom_audit_logs" {
    path_targets = [{
        __path__ = "/var/www/chom/storage/logs/audit-*.log",
        job      = "chom",
        log_type = "audit",
    }]
}

loki.source.file "chom_audit" {
    targets    = local.file_match.chom_audit_logs.targets
    forward_to = [loki.process.chom_laravel.receiver]
}

// Nginx Access Logs
local.file_match "nginx_access_logs" {
    path_targets = [{
        __path__ = "/var/log/nginx/access.log",
        job      = "chom",
        log_type = "nginx-access",
    }]
}

loki.source.file "nginx_access" {
    targets    = local.file_match.nginx_access_logs.targets
    forward_to = [loki.process.nginx_access.receiver]
}

loki.process "nginx_access" {
    // Nginx log format
    stage.regex {
        expression = "^(?P<remote_addr>[\\d\\.]+) - (?P<remote_user>\\S+) \\[(?P<time_local>[^\\]]+)\\] \"(?P<request>[^\"]+)\" (?P<status>\\d+) (?P<body_bytes_sent>\\d+) \"(?P<http_referer>[^\"]*)\" \"(?P<http_user_agent>[^\"]*)\""
    }

    stage.labels {
        values = {
            status = "",
        }
    }

    stage.timestamp {
        source = "time_local"
        format = "02/Jan/2006:15:04:05 -0700"
    }

    forward_to = [loki.write.default.receiver]
}

// Nginx Error Logs
local.file_match "nginx_error_logs" {
    path_targets = [{
        __path__ = "/var/log/nginx/error.log",
        job      = "chom",
        log_type = "nginx-error",
    }]
}

loki.source.file "nginx_error" {
    targets    = local.file_match.nginx_error_logs.targets
    forward_to = [loki.write.default.receiver]
}

// PHP-FPM Logs
local.file_match "php_fpm_logs" {
    path_targets = [{
        __path__ = "/var/log/php*-fpm.log",
        job      = "chom",
        log_type = "php-fpm",
    }]
}

loki.source.file "php_fpm" {
    targets    = local.file_match.php_fpm_logs.targets
    forward_to = [loki.write.default.receiver]
}

// ============================================================================
// METRICS CONFIGURATION (Optional - Remote Prometheus write)
// ============================================================================

// Uncomment if using Prometheus remote write from Alloy
/*
prometheus.remote_write "default" {
    endpoint {
        url = "http://51.254.139.78:9090/api/v1/write"

        queue_config {
            capacity             = 10000
            max_shards           = 50
            min_shards           = 1
            max_samples_per_send = 2000
            batch_send_deadline  = "5s"
            min_backoff          = "30ms"
            max_backoff          = "5s"
        }
    }

    external_labels = {
        environment = "production",
        instance    = "landsraad",
    }
}

// Node Exporter metrics
prometheus.scrape "node_exporter" {
    targets = [{
        __address__ = "localhost:9100",
    }]

    forward_to      = [prometheus.remote_write.default.receiver]
    job_name        = "node_exporter"
    scrape_interval = "15s"
}
*/

// ============================================================================
// ALLOY SELF-MONITORING
// ============================================================================

logging {
    level  = "info"
    format = "json"
}

// Alloy metrics (optional)
prometheus.scrape "alloy" {
    targets = [{
        __address__ = "127.0.0.1:12345",
    }]

    job_name = "alloy"
}
```

### Step 3.3: Update Alloy Configuration Path

Replace the Loki endpoint with your actual mentat IP:

```bash
# In the loki.write "default" block, update:
# url = "http://51.254.139.78:3100/loki/api/v1/push"

# If using hostname instead (requires DNS resolution):
# url = "http://mentat.arewel.com:3100/loki/api/v1/push"
```

### Step 3.4: Validate Configuration

```bash
# Validate Alloy configuration syntax
sudo alloy fmt /etc/alloy/config.alloy --check

# If there are errors, display them:
sudo alloy fmt /etc/alloy/config.alloy

# Fix any formatting issues
sudo alloy fmt /etc/alloy/config.alloy -w
```

### Step 3.5: Reload Alloy

```bash
# Restart Alloy with new configuration
sudo systemctl restart grafana-alloy

# Verify it's running
sudo systemctl status grafana-alloy

# Check for errors
sudo journalctl -u grafana-alloy -n 50 -f
```

## Phase 4: Verify Log Shipping

### Step 4.1: Check Alloy Status

```bash
# Check if Alloy is running
sudo systemctl status grafana-alloy

# View recent logs
sudo journalctl -u grafana-alloy -n 100

# Expected: No errors, configuration reloaded successfully
```

### Step 4.2: Verify Logs Appear in Loki

On mentat, query Loki:

```bash
# Use Loki HTTP API to check for logs
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={app="chom"}&start=0&end='$(date +%s)'' | jq '.'

# Should return recent logs from CHOM
```

In Grafana:

1. Go to **Explore** (left sidebar)
2. Select **Loki** data source
3. Run the following queries:

```logql
# All CHOM logs
{app="chom"}

# Only error logs
{app="chom", level="error"}

# Nginx access logs
{app="chom", log_type="nginx-access"}

# Laravel logs
{app="chom", log_type="laravel"}

# Security logs
{app="chom", log_type="security"}
```

### Step 4.3: Monitor Log Ingestion Rate

```bash
# Check logs being written
curl -s 'http://mentat.arewel.com:3100/loki/api/v1/query?query=rate(loki_distributor_lines_received_total[5m])' | jq '.data.result'

# Expected: Non-zero ingestion rate indicates logs are flowing
```

## Phase 5: Log Processing and Filtering

### Step 5.1: Add Log Filtering

To reduce log volume, add filtering to Alloy:

```alloy
// Filter out health check logs (reduce noise)
loki.process "chom_nginx_filtered" {
    stage.regex {
        expression = "^(?P<remote_addr>[\\d\\.]+) - (?P<remote_user>\\S+) \\[(?P<time_local>[^\\]]+)\\] \"(?P<request>[^\"]+)\" (?P<status>\\d+) (?P<body_bytes_sent>\\d+) \"(?P<http_referer>[^\"]*)\" \"(?P<http_user_agent>[^\"]*)\""
    }

    stage.labels {
        values = {
            status = "",
        }
    }

    // Drop health check logs
    stage.drop {
        expression = "GET /health HTTP"
    }

    stage.timestamp {
        source = "time_local"
        format = "02/Jan/2006:15:04:05 -0700"
    }

    forward_to = [loki.write.default.receiver]
}
```

### Step 5.2: Add Log Sampling

To sample high-volume logs:

```alloy
// Sample logs (keep 10% of logs)
loki.process "chom_sampling" {
    stage.sampling {
        rate = 0.1  // Keep 10% of logs
    }

    forward_to = [loki.write.default.receiver]
}
```

## Phase 6: Log Visualization in Grafana

### Step 6.1: Create Log Dashboard

In Grafana:

1. **+ Create > Dashboard**
2. Add panels with the following queries:

```logql
# Panel 1: Error Logs Timeline
{app="chom", level=~"error|ERROR"} | json level="level", message="message"

# Panel 2: Application Logs
{app="chom", log_type="app"} | json

# Panel 3: Nginx Errors
{app="chom", log_type="nginx-access", status=~"5.."}

# Panel 4: Security Events
{app="chom", log_type="security"}

# Panel 5: Performance Issues
{app="chom", log_type="performance"} |= "slow"
```

### Step 6.2: Create Loki Alert Rules

Create alert rules based on log patterns:

```yaml
# /etc/loki/rules.yaml on mentat

groups:
  - name: chom-logs
    interval: 1m
    rules:
      # High error rate in application logs
      - alert: CHOMHighErrorRate
        expr: count(rate({app="chom", level=~"error|ERROR"}[5m])) > 10
        for: 5m
        annotations:
          summary: "CHOM high error rate in logs"

      # Database connection errors
      - alert: CHOMDatabaseError
        expr: count({app="chom"} |= "SQLSTATE") by (level) > 0
        for: 2m
        annotations:
          summary: "CHOM database connection error detected"

      # Security events
      - alert: CHOMSecurityEvent
        expr: count({app="chom", log_type="security"} |= "unauthorized") > 0
        for: 1m
        annotations:
          summary: "CHOM security event detected"
```

## Phase 7: Performance Tuning

### Step 7.1: Optimize Batch Settings

In Alloy configuration, tune batching:

```alloy
loki.write "default" {
    endpoint {
        url = "http://51.254.139.78:3100/loki/api/v1/push"

        // Reduce batching for real-time logs
        batchwait = "500ms"    # Faster flushing
        batchsize = "512KiB"   # Smaller batches

        // Or for high-volume logs
        batchwait = "5s"       # Batch longer
        batchsize = "10MiB"    # Larger batches
    }
}
```

### Step 7.2: Monitor Alloy Metrics

```bash
# Check Alloy internal metrics
curl -s http://localhost:12345/metrics | grep loki

# Expected metrics:
# - loki_request_duration_seconds
# - loki_batch_size
# - loki_batch_retries
```

### Step 7.3: Monitor Loki Throughput

On mentat:

```bash
# Check Loki ingestion metrics
curl -s 'http://localhost:3100/loki/api/v1/query?query=rate(loki_distributor_bytes_received_total[5m])' | jq '.data.result[0].value'

# Check Loki errors
curl -s 'http://localhost:3100/loki/api/v1/query?query=rate(loki_distributor_errors_total[5m])' | jq '.data.result[0].value'
```

## Troubleshooting

### Issue: Logs not appearing in Loki

```bash
# 1. Check Alloy is running
sudo systemctl status grafana-alloy

# 2. Check configuration errors
sudo journalctl -u grafana-alloy -f

# 3. Verify network connectivity to Loki
ssh landsraad.arewel.com
curl -v http://51.254.139.78:3100/ready

# 4. Check log file permissions
ls -la /var/www/chom/storage/logs/
stat /var/www/chom/storage/logs/app.log

# 5. Manually test Loki push
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "streams": [{
      "stream": {"job":"chom", "level":"test"},
      "values": [["1234567890", "test log"]]
    }]
  }' \
  http://51.254.139.78:3100/loki/api/v1/push
```

### Issue: High log volume/storage

```bash
# 1. Reduce retention in Loki
# Edit /etc/loki/loki-config.yaml

limits_config:
  retention_period: 168h  # 7 days

# 2. Enable compression in Alloy
loki.write "default" {
    endpoint {
        url = "http://51.254.139.78:3100/loki/api/v1/push"
        compression = "snappy"  # or "gzip"
    }
}

# 3. Sample high-volume logs in Alloy
stage.sampling {
    rate = 0.1  # Keep 10% of logs
}

# 4. Restart services
sudo systemctl restart grafana-alloy
```

### Issue: Connection timeouts

```bash
# 1. Check firewall rules on mentat
sudo ufw status | grep 3100

# 2. Check if Loki is accepting connections
curl -v http://51.254.139.78:3100/ready

# 3. Increase timeout in Alloy
loki.write "default" {
    endpoint {
        url = "http://51.254.139.78:3100/loki/api/v1/push"
        timeout = "30s"
    }
}
```

## Quick Reference

```bash
# Check log shipping status
sudo systemctl status grafana-alloy
sudo journalctl -u grafana-alloy -f

# Test Loki connectivity
curl http://51.254.139.78:3100/ready

# View Alloy configuration
sudo cat /etc/alloy/config.alloy | head -50

# Reload Alloy
sudo systemctl restart grafana-alloy

# Check log ingestion rate
curl -s 'http://mentat.arewel.com:3100/loki/api/v1/query_range?query={app="chom"}&limit=100' | jq '.data.result | length'

# Query logs in Grafana
# Explore > Loki > {app="chom"}
```

## Next Steps

1. **Run verification tests** (see `04-VERIFICATION.md`)
2. **Create alerting rules** (based on logs and metrics)
3. **Setup log retention policies** (manage storage)
4. **Create operational dashboards** (visualize system state)
