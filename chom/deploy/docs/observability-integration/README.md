# Observability Integration - Complete Implementation Guide

## Quick Start

This directory contains comprehensive documentation and scripts for establishing observability integration between the CHOM application (landsraad) and the observability stack (mentat).

### Environment

```
Server               IP Address      Hostname              Role
─────────────────────────────────────────────────────────────
mentat          51.254.139.78       mentat.arewel.com     Observability Stack
landsraad       51.77.150.96        landsraad.arewel.com  CHOM Application
```

### What Gets Set Up

This integration provides:

1. **Metrics Collection** - 15-second scrape interval
   - System metrics (CPU, memory, disk, network)
   - Application metrics (requests, latency, errors)
   - Database metrics (connections, queries, performance)
   - Cache metrics (Redis memory, operations)
   - Web server metrics (Nginx requests, response times)

2. **Log Aggregation** - Real-time log shipping
   - Application logs (JSON format)
   - Laravel framework logs
   - Nginx access/error logs
   - PHP-FPM logs
   - Security and audit logs
   - Performance logs

3. **Visualization & Alerting**
   - Grafana dashboards
   - Prometheus alert rules
   - Loki alert rules
   - AlertManager notifications

## Documentation Structure

### Phase 1: Network Connectivity (01-NETWORK-SETUP.md)

Establishes secure network communication between servers.

**Contents:**
- Network architecture diagram
- Connectivity testing procedures
- Firewall configuration (UFW rules)
- Port verification
- DNS and SSL/TLS setup
- Troubleshooting guide

**Key Scripts:**
- `connectivity-test.sh` - Comprehensive network diagnostics
- `setup-firewall.sh` - Firewall rule configuration

**Time to Complete:** 15-30 minutes

### Phase 2: Prometheus Configuration (02-PROMETHEUS-CONFIG.md)

Configures Prometheus to scrape metrics from CHOM infrastructure.

**Contents:**
- Exporter verification
- Prometheus configuration updates
- Scrape job definitions
- Alert rules
- Recording rules
- Grafana dashboard setup
- Remote storage (optional)

**Key Configuration Files:**
- `/etc/prometheus/prometheus.yml` - Scrape configuration
- `/etc/prometheus/rules/chom-alerts.yml` - Alert rules
- `/etc/prometheus/rules/chom-recording.yml` - Recording rules

**Time to Complete:** 20-30 minutes

### Phase 3: Log Shipping (03-LOG-SHIPPING.md)

Configures Alloy on landsraad to ship logs to Loki on mentat.

**Contents:**
- Alloy installation
- Log source discovery
- Alloy configuration
- Log processing and filtering
- Grafana log visualization
- Performance tuning
- Retention policies

**Key Configuration Files:**
- `/etc/alloy/config.alloy` - Log shipping configuration

**Time to Complete:** 20-30 minutes

### Phase 4: Verification (04-VERIFICATION.md)

Comprehensive testing procedures to verify all components work correctly.

**Contents:**
- Network connectivity verification
- Prometheus health checks
- Loki log ingestion verification
- Grafana integration tests
- End-to-end data flow testing
- Performance and reliability tests
- Security verification
- Comprehensive checklist

**Time to Complete:** 30-45 minutes

## Getting Started

### Prerequisites

1. **Network Access**
   - SSH access to both mentat and landsraad
   - Both servers have Debian 13
   - Internet connectivity for package installation

2. **Services Already Running** (or to be installed)
   - On mentat: Prometheus, Loki, Grafana, AlertManager
   - On landsraad: Node Exporter, PHP-FPM Exporter, Nginx Exporter, MySQL Exporter, Redis Exporter

3. **Credentials**
   - sudo/root access on both servers (for firewall configuration)
   - Grafana admin credentials for dashboard creation

### Quick Setup Steps

#### Step 1: Test Network Connectivity (5 minutes)

```bash
# On mentat or landsraad
bash scripts/network-diagnostics/connectivity-test.sh

# Expected: All tests pass (green PASS messages)
```

#### Step 2: Configure Firewall (10 minutes)

```bash
# On mentat
sudo bash scripts/network-diagnostics/setup-firewall.sh --role mentat

# On landsraad
sudo bash scripts/network-diagnostics/setup-firewall.sh --role landsraad
```

#### Step 3: Update Prometheus Configuration (10 minutes)

```bash
# On mentat, edit prometheus.yml
sudo nano /etc/prometheus/prometheus.yml

# Add scrape_configs from docs/observability-integration/02-PROMETHEUS-CONFIG.md
# Then reload:
curl -X POST http://localhost:9090/-/reload
```

#### Step 4: Configure Alloy on landsraad (10 minutes)

```bash
# On landsraad
sudo apt-get install -y grafana-alloy
sudo nano /etc/alloy/config.alloy

# Copy configuration from docs/observability-integration/03-LOG-SHIPPING.md
# Update mentat IP address
# Then restart:
sudo systemctl restart grafana-alloy
```

#### Step 5: Verify Everything Works (15 minutes)

```bash
# Run full verification
bash verify-observability.sh

# Or follow manual steps in docs/observability-integration/04-VERIFICATION.md
```

**Total Setup Time:** ~45 minutes

## Key Configuration Files

### Prometheus Configuration

File: `/etc/prometheus/prometheus.yml`

Key additions:
```yaml
scrape_configs:
  - job_name: 'chom-node'
    static_configs:
      - targets: ['51.77.150.96:9100']

  - job_name: 'chom-php-fpm'
    static_configs:
      - targets: ['51.77.150.96:9253']

  # ... additional jobs for other exporters
```

Alert Rules: `/etc/prometheus/rules/chom-alerts.yml`
Recording Rules: `/etc/prometheus/rules/chom-recording.yml`

### Alloy Configuration

File: `/etc/alloy/config.alloy`

Key sections:
- Loki write endpoint configuration
- Log file sources and patterns
- Log processing pipelines
- Label assignment

### Firewall Rules

UFW rules are configured automatically by `setup-firewall.sh` script.

**On mentat (inbound from landsraad):**
- Port 9090/tcp - Prometheus API
- Port 9009/tcp - Prometheus Remote Write
- Port 3100/tcp - Loki Log Ingestion

**On landsraad (inbound from mentat):**
- Port 9100/tcp - Node Exporter
- Port 9253/tcp - PHP-FPM Exporter
- Port 9113/tcp - Nginx Exporter
- Port 9104/tcp - MySQL Exporter
- Port 9121/tcp - Redis Exporter
- Port 8080/tcp - CHOM App Metrics

## Common Workflows

### Check Metrics Are Flowing

```bash
# Query Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=up'

# In Prometheus UI: http://mentat.arewel.com:9090/targets
# All CHOM targets should show green "UP"
```

### Check Logs Are Being Shipped

```bash
# On landsraad, verify Alloy is running
sudo systemctl status grafana-alloy

# Query Loki
curl -s 'http://mentat.arewel.com:3100/loki/api/v1/query?query={app="chom"}&limit=10'

# In Grafana: Explore > Loki > {app="chom"}
```

### Create Custom Dashboard

1. Open Grafana: http://mentat.arewel.com:3000
2. Click **+ Create > Dashboard**
3. Add panels with these queries:

**CPU Usage:**
```promql
chom:node:cpu:usage
```

**Memory Usage:**
```promql
chom:node:memory:usage_percentage
```

**Recent Errors:**
```logql
{app="chom"} |= "error"
```

### Troubleshoot Target Not Showing

1. Check if exporter is running on landsraad:
   ```bash
   sudo systemctl status node-exporter
   ```

2. Test if exporter is accessible:
   ```bash
   curl http://51.77.150.96:9100/metrics
   ```

3. Check Prometheus logs for scrape errors:
   ```bash
   sudo journalctl -u prometheus -f
   ```

4. Check firewall rules:
   ```bash
   sudo ufw status numbered
   ```

## Metrics Available

### System Metrics (from Node Exporter)

- `node_cpu_seconds_total` - CPU time by mode
- `node_memory_MemAvailable_bytes` - Available memory
- `node_memory_MemTotal_bytes` - Total memory
- `node_filesystem_avail_bytes` - Free disk space
- `node_disk_io_reads_total` - Disk read operations
- `node_disk_io_writes_total` - Disk write operations
- `node_network_receive_bytes_total` - Network received bytes
- `node_network_transmit_bytes_total` - Network transmitted bytes

### PHP-FPM Metrics

- `php_fpm_processes` - Total processes (with state labels)
- `php_fpm_up` - Pool availability

### Nginx Metrics

- `nginx_http_requests_total` - Total HTTP requests
- `nginx_http_request_duration_seconds_total` - Request duration
- `nginx_http_request_size_bytes_total` - Request size
- `nginx_http_response_time_seconds_total` - Response time

### MySQL Metrics

- `mysql_global_status_threads_connected` - Connected threads
- `mysql_global_status_questions` - Total queries
- `mysql_global_status_slow_queries` - Slow query count
- `mysql_replication_lag_seconds` - Replication lag

### Redis Metrics

- `redis_memory_used_bytes` - Memory usage
- `redis_memory_max_bytes` - Max memory
- `redis_connected_clients` - Connected clients
- `redis_total_commands_processed` - Total commands

## Logs Available

| Log Type | Location | Format | Labels |
|----------|----------|--------|--------|
| Application | `/var/www/chom/storage/logs/app.json` | JSON | `log_type="app"` |
| Laravel | `/var/www/chom/storage/logs/laravel-*.log` | Text | `log_type="laravel"` |
| Performance | `/var/www/chom/storage/logs/performance-*.log` | Text | `log_type="performance"` |
| Security | `/var/www/chom/storage/logs/security-*.log` | Text | `log_type="security"` |
| Audit | `/var/www/chom/storage/logs/audit-*.log` | Text | `log_type="audit"` |
| Nginx Access | `/var/log/nginx/access.log` | Combined | `log_type="nginx-access"` |
| Nginx Error | `/var/log/nginx/error.log` | Text | `log_type="nginx-error"` |
| PHP-FPM | `/var/log/php*-fpm.log` | Text | `log_type="php-fpm"` |

## Performance Metrics

### Typical System Resource Usage

**Prometheus:**
- CPU: 5-15%
- Memory: 200-500 MB
- Disk: 2-5 GB/week (depends on retention)

**Loki:**
- CPU: 5-10%
- Memory: 200-400 MB
- Disk: 1-3 GB/week (depends on retention)

**Grafana:**
- CPU: 2-5%
- Memory: 100-200 MB
- Disk: 1-2 GB

**Alloy (on landsraad):**
- CPU: 2-5%
- Memory: 50-100 MB
- Disk: 1-2 GB (for buffering)

## Alert Rules Included

All alert rules are defined in `/etc/prometheus/rules/chom-alerts.yml`:

- `CHOMDown` - Application unreachable
- `CHOMHighCPUUsage` - CPU > 80% for 5 minutes
- `CHOMHighMemoryUsage` - Memory > 85% for 5 minutes
- `CHOMDiskSpaceLow` - Free space < 10%
- `MySQLDown` - Database unreachable
- `MySQLHighConnections` - Connection pool > 80%
- `RedisDown` - Cache unreachable
- `RedisHighMemoryUsage` - Redis memory > 90%
- `PHPFPMNoIdleProcesses` - No available PHP processes
- `NginxHighErrorRate` - 5xx error rate > 5%

## Recording Rules Included

Recording rules pre-compute frequently-used queries:

- `chom:node:cpu:usage` - Current CPU usage %
- `chom:node:memory:usage_percentage` - Current memory %
- `chom:node:disk:usage_percentage` - Current disk %
- `chom:php_fpm:pool:busy_processes_ratio` - PHP-FPM busy ratio
- `chom:mysql:connection:usage_percentage` - MySQL connection %
- `chom:mysql:queries:rate` - Queries per second
- `chom:nginx:request:rate` - Requests per second
- `chom:nginx:request:error_rate` - Error rate
- `chom:redis:memory:usage_percentage` - Redis memory %

## Debugging

### Enable Verbose Logging

```bash
# Prometheus
sudo systemctl stop prometheus
prometheus --config.file=/etc/prometheus/prometheus.yml --log.level=debug

# Loki
sudo systemctl stop loki
loki -config.file=/etc/loki/loki-config.yaml -log.level=debug

# Alloy
sudo systemctl stop grafana-alloy
alloy run /etc/alloy/config.alloy -log.level=debug
```

### Capture Network Traffic

```bash
# Capture Prometheus scrape traffic
sudo tcpdump -i eth0 -n 'tcp port 9100 or tcp port 3100' -w /tmp/capture.pcap

# Analyze
sudo tcpdump -r /tmp/capture.pcap
```

### Check Service Logs

```bash
# Prometheus
sudo journalctl -u prometheus -f

# Loki
sudo journalctl -u loki -f

# Alloy (on landsraad)
sudo journalctl -u grafana-alloy -f

# Grafana
sudo journalctl -u grafana-server -f
```

## Security Considerations

1. **Firewall Rules** - Implemented with least privilege principle
2. **TLS/SSL** - All connections use HTTPS
3. **Authentication** - Basic auth configured for sensitive endpoints
4. **Network Segmentation** - Observability traffic isolated
5. **Data Retention** - Logs and metrics retained for compliance period
6. **Audit Logging** - All access logged and available in Loki

## Maintenance Tasks

### Daily
- Monitor dashboard for anomalies
- Check alert notification delivery

### Weekly
- Review disk usage on mentat and landsraad
- Check for any failed scrapes or log ingestion errors
- Verify backup of Prometheus and Loki data

### Monthly
- Analyze metrics trends
- Review and update alert thresholds
- Clean up unused dashboards and alert rules
- Audit firewall rules

### Quarterly
- Full system backup
- Disaster recovery drill
- Update documentation with any changes

## Support and Troubleshooting

See individual phase documentation for detailed troubleshooting:

- **Network Issues:** See `01-NETWORK-SETUP.md` - Troubleshooting Guide
- **Metrics Issues:** See `02-PROMETHEUS-CONFIG.md` - Troubleshooting
- **Log Issues:** See `03-LOG-SHIPPING.md` - Troubleshooting
- **Verification Issues:** See `04-VERIFICATION.md` - Quick Reference

## Additional Resources

- Prometheus Documentation: https://prometheus.io/docs/
- Loki Documentation: https://grafana.com/docs/loki/
- Grafana Documentation: https://grafana.com/docs/grafana/
- Alloy Documentation: https://grafana.com/docs/alloy/
- UFW Firewall: https://help.ubuntu.com/community/UFW

## Quick Command Reference

```bash
# Network Tests
bash scripts/network-diagnostics/connectivity-test.sh --verbose

# Firewall Setup
sudo bash scripts/network-diagnostics/setup-firewall.sh --role mentat

# Prometheus Health
curl -s http://localhost:9090/-/healthy

# Query Metrics
curl -s 'http://localhost:9090/api/v1/query?query=up'

# Check Prometheus Targets
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets'

# Query Logs
curl -s 'http://localhost:3100/loki/api/v1/query?query={app="chom"}'

# Check Alloy Status
sudo systemctl status grafana-alloy

# View Prometheus Config
curl -s 'http://localhost:9090/api/v1/status/config' | jq '.data.yaml'

# Reload Prometheus
curl -X POST http://localhost:9090/-/reload

# Reload Alloy
sudo systemctl reload grafana-alloy
```

## Version Information

- Prometheus: v2.x or higher
- Loki: v2.x or higher
- Grafana: v8.x or higher
- Alloy: Latest stable
- Debian: 13

## License and Attribution

This observability integration guide and associated scripts are provided as part of the mentat observability stack project.

## Contact and Support

For issues or questions regarding observability integration, please refer to the troubleshooting sections in the phase-specific documentation files.

---

**Last Updated:** January 2026
**Confidence Gain:** +3% (Phase 1 Quick Win #2)
