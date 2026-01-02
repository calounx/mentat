# Observability Integration - Verification and Testing

## Overview

This guide provides comprehensive verification procedures to ensure all observability components are working correctly between mentat and landsraad.

## Phase 1: Network Connectivity Verification

### Step 1.1: Execute Connectivity Test Suite

```bash
# From landsraad or mentat
bash /home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/connectivity-test.sh --verbose

# Expected output:
# - All ping tests: PASS
# - All port tests: PASS
# - DNS resolution: PASS
# - Latency measurements: Successful
```

### Step 1.2: Verify Critical Ports

Create a port testing script:

```bash
#!/bin/bash
# Test all observability ports

TARGET_IP="51.254.139.78"  # mentat

echo "Testing connectivity to observability server..."
echo ""

# Define ports
declare -A ports=(
    ["Prometheus:9090"]="9090"
    ["Prometheus Remote Write:9009"]="9009"
    ["Loki:3100"]="3100"
    ["Grafana:3000"]="3000"
    ["Node Exporter:9100"]="9100"
)

# Test each port
for port_name in "${!ports[@]}"; do
    port="${ports[$port_name]}"
    if timeout 2 bash -c "echo > /dev/tcp/$TARGET_IP/$port" 2>/dev/null; then
        echo "✓ $port_name - OPEN"
    else
        echo "✗ $port_name - CLOSED"
    fi
done
```

## Phase 2: Prometheus Verification

### Step 2.1: Check Prometheus Health

On mentat:

```bash
# Check service status
sudo systemctl status prometheus

# Test health endpoint
curl -s http://localhost:9090/-/healthy
# Expected: "Prometheus is healthy"

# Check readiness
curl -s http://localhost:9090/-/ready
# Expected: "Prometheus is ready"
```

### Step 2.2: Verify Targets Configuration

In Prometheus web UI:

```
http://mentat.arewel.com:9090/targets
```

Expected targets (all should be green "UP"):
- `chom-node` (Node Exporter)
- `chom-php-fpm` (PHP-FPM Exporter)
- `chom-nginx` (Nginx Exporter)
- `chom-mysql` (MySQL Exporter)
- `chom-redis` (Redis Exporter)
- `chom-app` (CHOM Application)

### Step 2.3: Query Sample Metrics

In Prometheus Graph tab, test these queries:

```promql
# 1. Check if targets are up
up{job=~"chom.*"}
# Expected: Multiple results with value 1 (up) or 0 (down)

# 2. Check node metrics
node_cpu_seconds_total{job="chom-node"}
# Expected: Multiple metrics with different modes (user, system, idle, etc.)

# 3. Check memory
node_memory_MemAvailable_bytes{job="chom-node"}
# Expected: Single value showing available memory

# 4. Check disk usage
node_filesystem_avail_bytes{job="chom-node"}
# Expected: Filesystem availability metrics

# 5. Check PHP-FPM
php_fpm_processes{job="chom-php-fpm"}
# Expected: Metrics showing processes in different states

# 6. Check Nginx
nginx_http_requests_total{job="chom-nginx"}
# Expected: Request count metrics

# 7. Check MySQL
mysql_global_status_threads_connected{job="chom-mysql"}
# Expected: Connection count

# 8. Check Redis
redis_memory_used_bytes{job="chom-redis"}
# Expected: Memory usage in bytes
```

### Step 2.4: Verify Recording Rules

In Prometheus Rules tab:

```
http://mentat.arewel.com:9090/rules
```

Expected:
- Recording rules listed and functional
- Rule evaluation shows recent evaluation times
- No evaluation errors

Test recording rules:

```promql
# Query recorded metrics
chom:node:cpu:usage
# Expected: Current CPU usage percentage

chom:node:memory:usage_percentage
# Expected: Current memory usage percentage

chom:mysql:connection:usage_percentage
# Expected: MySQL connection percentage
```

### Step 2.5: Verify Alert Rules

Test alert rule evaluation:

```bash
# Check alert rules are loaded
curl -s 'http://localhost:9090/api/v1/rules' | jq '.data.groups[]'

# Check specific alert
curl -s 'http://localhost:9090/api/v1/rules' | jq '.data.groups[].rules[] | select(.name=="CHOMDown")'
```

## Phase 3: Loki Log Verification

### Step 3.1: Check Loki Health

On mentat:

```bash
# Check service status
sudo systemctl status loki

# Test ready endpoint
curl -s http://localhost:3100/ready
# Expected: "ready"

# Test build info
curl -s http://localhost:3100/loki/api/v1/status/buildinfo | jq '.'
```

### Step 3.2: Verify Log Ingestion

Query Loki for received logs:

```bash
# Count logs received
curl -s 'http://localhost:3100/loki/api/v1/query_range?query=sum(rate(loki_distributor_lines_received_total[5m]))' | jq '.data.result'

# Expected: Non-zero value indicating active log ingestion
```

### Step 3.3: Query Logs in Grafana

1. Go to **Explore** in Grafana
2. Select **Loki** data source
3. Run the following queries:

```logql
# All logs from CHOM
{app="chom"}
# Expected: Multiple log entries with timestamps

# Error logs only
{app="chom", level=~"error|ERROR"}
# Expected: Error-level logs

# Application logs
{app="chom", log_type="app"}
# Expected: JSON-formatted application logs

# Nginx access logs
{app="chom", log_type="nginx-access"}
# Expected: HTTP request logs

# Laravel logs
{app="chom", log_type="laravel"}
# Expected: Laravel framework logs

# Security logs
{app="chom", log_type="security"}
# Expected: Security-related events

# Performance logs
{app="chom", log_type="performance"}
# Expected: Performance metric logs

# Query with filter
{app="chom"} |= "error"
# Expected: Logs containing "error"

# Query with label filter
{app="chom", log_type="nginx-access", status=~"5.."}
# Expected: Nginx 5xx error logs
```

### Step 3.4: Test Log Line Parsing

Query and inspect parsed logs:

```logql
# Parse JSON from app logs
{app="chom", log_type="app"} | json

# Extract specific fields
{app="chom"} | json level="level", message="message"

# Filter by parsed field
{app="chom", log_type="laravel"} | regexp "(?P<method>\w+) (?P<path>/\S*)"
```

## Phase 4: Grafana Integration Verification

### Step 4.1: Verify Data Source Connections

In Grafana:

1. **Configuration > Data Sources**
2. For each data source, click it and click **Test**

Expected:
- Prometheus: "Data source is working"
- Loki: "Data source is working"

### Step 4.2: Verify Dashboard Functionality

1. Create a test dashboard with these panels:

**Panel 1: System Metrics**
```promql
# Query 1: CPU Usage
chom:node:cpu:usage

# Query 2: Memory Usage
chom:node:memory:usage_percentage

# Query 3: Disk Usage
chom:node:disk:usage_percentage
```

**Panel 2: Application Status**
```promql
# Up/Down status
up{job=~"chom.*"}
```

**Panel 3: Recent Errors**
```logql
{app="chom"} |= "error" | json | line_format "{{.message}}"
```

**Panel 4: Request Rate**
```promql
rate(nginx_http_requests_total{job="chom-nginx"}[5m])
```

2. Verify all panels display data correctly
3. Test time range selector (1h, 6h, 24h, 7d)
4. Test refresh intervals

### Step 4.3: Test Alert Notifications

Create a test alert rule:

```yaml
# In Alertmanager configuration
groups:
  - name: test-alerts
    rules:
      - alert: TestAlert
        expr: vector(1)
        for: 0m
        annotations:
          summary: "Test alert for verification"
```

Verify:
1. Alert appears in Prometheus Alerts tab
2. Notification is sent (check configured channels)
3. Alert can be resolved in Grafana

## Phase 5: End-to-End Data Flow Testing

### Step 5.1: Inject Test Data

On landsraad, generate test metrics:

```bash
# Force application to generate metrics
curl -s http://localhost:8080/metrics | head -20

# Trigger some PHP-FPM activity
for i in {1..10}; do curl -s http://localhost/api/health; done

# Generate some Nginx logs
curl -s http://localhost/nonexistent 2>/dev/null | head -5

# Check error logs
tail -5 /var/log/nginx/error.log
```

### Step 5.2: Verify Metrics Appear in Prometheus

In Prometheus UI, query for recent metrics:

```promql
# Recent requests (should increase after curl commands)
increase(nginx_http_requests_total[1m])

# Recent errors (should show 404s from nonexistent URL)
increase(nginx_http_requests_total{status="404"}[1m])
```

### Step 5.3: Verify Logs Appear in Loki

In Grafana Explore > Loki:

```logql
# Recent nginx logs
{app="chom", log_type="nginx-access"}
# Should show the curl requests from above

# Recent error logs
{app="chom", log_type="nginx-error"}
# Should show any error requests
```

### Step 5.4: Verify Dashboard Updates

Check Grafana dashboard panels:

1. All panels should show recent data
2. Timestamps should be current
3. Graphs should show recent activity

## Phase 6: Performance and Reliability Testing

### Step 6.1: Load Test Logging

Generate high-volume logs and verify system performance:

```bash
# On landsraad, generate logs
for i in {1..1000}; do
    curl -s -w "HTTP %{http_code} - Request $i\n" http://localhost/ >> /tmp/test.log
done

# Monitor Alloy resource usage
top -p $(pgrep -f "grafana-alloy")
# Expected: CPU < 50%, Memory < 200MB

# Monitor Loki resource usage (on mentat)
top -p $(pgrep -f "loki")
# Expected: CPU < 30%, Memory < 500MB
```

### Step 6.2: Test High-Frequency Metrics

Generate high-frequency metrics:

```bash
# Run a script that generates many metrics
while true; do
    curl -s http://localhost:8080/metrics | wc -l
    sleep 1
done

# Monitor Prometheus resource usage
top -p $(pgrep prometheus)
# Expected: CPU < 40%, Memory < 1GB
```

### Step 6.3: Network Resilience Test

Test how system handles network interruptions:

```bash
# Simulate network latency (on mentat)
sudo tc qdisc add dev eth0 root netem delay 500ms
# Test queries - should still work with higher latency

# Remove latency
sudo tc qdisc del dev eth0 root netem delay 500ms

# Simulate packet loss
sudo tc qdisc add dev eth0 root netem loss 10%
# Test queries - should still function with 10% loss

# Remove packet loss
sudo tc qdisc del dev eth0 root netem loss 10%
```

### Step 6.4: Component Failure Testing

Test how system handles component failures:

```bash
# Simulate Prometheus failure
sudo systemctl stop prometheus
# Verify: Logs still flowing to Loki
# Verify: Grafana shows "unavailable" for Prometheus data source

# Restore Prometheus
sudo systemctl start prometheus
# Verify: Data resumes flowing

# Simulate Loki failure
sudo systemctl stop loki
# Verify: Application still running
# Verify: Grafana shows "unavailable" for Loki data source

# Restore Loki
sudo systemctl start loki
```

## Phase 7: Security Verification

### Step 7.1: Verify Firewall Rules

```bash
# On mentat
sudo ufw status numbered | grep -E "9090|3100|3000"

# Expected:
# To 9090/tcp from 51.77.150.96 ALLOW (Prometheus)
# To 3100/tcp from 51.77.150.96 ALLOW (Loki)
# To 3000/tcp ALLOW (Grafana public)

# On landsraad
sudo ufw status numbered | grep -E "9100|9253|9113"

# Expected rules allowing mentat IP
```

### Step 7.2: Verify TLS/SSL Configuration

```bash
# Check if HTTPS is enabled on CHOM
openssl s_client -servername landsraad.arewel.com -connect 51.77.150.96:443 </dev/null | openssl x509 -noout -dates

# Check certificate validity
openssl s_client -servername mentat.arewel.com -connect 51.254.139.78:443 </dev/null | openssl x509 -noout -subject

# Expected: Valid dates, proper subject name
```

### Step 7.3: Verify Data Privacy

```bash
# Check if sensitive labels are in metrics
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[].labels'

# Verify: No passwords, API keys, or tokens in labels

# Check Loki retention
curl -s 'http://localhost:3100/loki/api/v1/status/retention' | jq '.'

# Verify: Appropriate retention periods set
```

## Comprehensive Verification Checklist

### Network Layer
- [ ] Ping test successful (< 50ms latency)
- [ ] DNS resolution working for both hostnames
- [ ] Port 9090 (Prometheus) accessible
- [ ] Port 3100 (Loki) accessible
- [ ] Port 3000 (Grafana) accessible
- [ ] All exporter ports (9100, 9253, 9113, 9104, 9121) accessible

### Prometheus Layer
- [ ] Prometheus service running and healthy
- [ ] All CHOM targets showing "UP" status
- [ ] Recording rules evaluating successfully
- [ ] Alert rules loaded and functional
- [ ] Sample queries returning data
- [ ] Metrics retention configured appropriately

### Loki Layer
- [ ] Loki service running and healthy
- [ ] Alloy agent running on landsraad
- [ ] Logs being ingested (non-zero ingestion rate)
- [ ] All log types visible (app, laravel, nginx, security, etc.)
- [ ] Log parsing working correctly
- [ ] Log retention configured appropriately

### Grafana Layer
- [ ] Grafana accessible and running
- [ ] Prometheus data source connected
- [ ] Loki data source connected
- [ ] Dashboards displaying data
- [ ] Alert rules configured
- [ ] Notifications working

### Exporters Layer
- [ ] Node Exporter running on landsraad
- [ ] PHP-FPM Exporter running
- [ ] Nginx Exporter running
- [ ] MySQL Exporter running
- [ ] Redis Exporter running
- [ ] CHOM app metrics endpoint accessible

### Security Layer
- [ ] Firewall rules properly configured
- [ ] SSH access limited (rate-limited)
- [ ] TLS certificates valid
- [ ] No sensitive data in metrics
- [ ] Network access logs in place

### Performance Layer
- [ ] CPU usage within normal ranges
- [ ] Memory usage stable
- [ ] Disk I/O acceptable
- [ ] Network latency acceptable
- [ ] Log ingestion keeping up with volume

### Documentation Layer
- [ ] Network setup documented
- [ ] Prometheus configuration documented
- [ ] Log shipping configuration documented
- [ ] Runbooks created for common issues
- [ ] Alert thresholds documented

## Performance Baseline

After verification, establish performance baseline:

```bash
# Record baseline metrics
date > /var/log/observability-baseline.txt
echo "Prometheus metrics count:" >> /var/log/observability-baseline.txt
curl -s 'http://localhost:9090/api/v1/query?query=count(count(*)%20by%20(__name__))' | jq '.data.result[0].value' >> /var/log/observability-baseline.txt

echo "Loki log volume:" >> /var/log/observability-baseline.txt
curl -s 'http://localhost:3100/loki/api/v1/query_range?query=sum(rate(loki_distributor_lines_received_total[5m]))&start=0&end='$(date +%s)'' | jq '.data.result[0].value' >> /var/log/observability-baseline.txt

echo "Prometheus disk usage:" >> /var/log/observability-baseline.txt
du -sh /var/lib/prometheus >> /var/log/observability-baseline.txt

echo "Loki disk usage:" >> /var/log/observability-baseline.txt
du -sh /var/lib/loki >> /var/log/observability-baseline.txt
```

## Troubleshooting Quick Reference

| Issue | Check | Solution |
|-------|-------|----------|
| Targets DOWN | Port accessible? Service running? | Restart exporter, check firewall |
| No metrics | Scrape config correct? | Check Prometheus config, reload |
| Logs not flowing | Alloy running? Loki accessible? | Check Alloy logs, test connectivity |
| High latency | Network path? MTU size? | Trace route, test MTU |
| Memory issues | Retention too long? | Reduce retention period |
| Disk full | Log volume too high? | Implement log sampling/filtering |

## Next Steps

1. **Create operational runbooks** for common issues
2. **Setup alerting rules** for critical thresholds
3. **Configure log retention policies** for compliance
4. **Document custom dashboards** and queries
5. **Schedule regular audits** of observability stack

## Additional Testing Commands

```bash
# Prometheus API tests
curl -s 'http://localhost:9090/api/v1/query?query=up'
curl -s 'http://localhost:9090/api/v1/query_range?query=up&start=1577836800&end=1577923200&step=300'
curl -s 'http://localhost:9090/api/v1/series?match=chom_.*'
curl -s 'http://localhost:9090/api/v1/label/__name__/values'

# Loki API tests
curl -s 'http://localhost:3100/loki/api/v1/labels'
curl -s 'http://localhost:3100/loki/api/v1/label/job/values'
curl -s 'http://localhost:3100/loki/api/v1/query?query={app="chom"}'
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={app="chom"}&start=0&end='$(date +%s)''

# Alloy status (on landsraad)
curl -s 'http://localhost:12345/api/v1/status'
curl -s 'http://localhost:12345/metrics'
```
