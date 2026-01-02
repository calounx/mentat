# CHOM Observability Integration Guide

This document describes how to configure the CHOM application for integration with the observability stack deployed on mentat_tst.

## Architecture Overview

```
+------------------+                    +------------------+
|   landsraad_tst  |                    |    mentat_tst    |
|                  |                    |                  |
|  +------------+  |                    |  +------------+  |
|  |    CHOM    |  |   /metrics         |  | Prometheus |  |
|  | Laravel App|<-+--------------------+--| (scraping) |  |
|  +------------+  |                    |  +------------+  |
|        |         |                    |        |         |
|        | logs    |                    |        v         |
|        v         |                    |  +------------+  |
|  +------------+  |   push logs        |  |  Grafana   |  |
|  |  Promtail  |--+--------------------+->|            |  |
|  +------------+  |                    |  +------------+  |
|        |         |                    |        ^         |
|        | JSON    |                    |        |         |
|        v         |                    |  +------------+  |
|  storage/logs/   |                    |  |    Loki    |  |
|  app.json        |                    |  +------------+  |
|                  |                    |                  |
+------------------+                    +------------------+
```

## Components

### 1. Prometheus Metrics Export

The `/metrics` endpoint exposes application metrics in Prometheus text exposition format.

**Endpoint:** `GET /metrics`

**Metrics Exposed:**
- `chom_app_info` - Application version and environment info
- `chom_uptime_seconds` - Application uptime
- `chom_memory_usage_bytes` - Current memory usage
- `chom_memory_peak_bytes` - Peak memory usage
- `chom_disk_free_bytes` - Free disk space
- `chom_disk_total_bytes` - Total disk space
- `chom_db_connections_active` - Active database connections
- `chom_health_status` - Health status (1=healthy, 0=unhealthy)
- `chom_sites_total` - Total number of sites
- `chom_sites_by_status` - Sites grouped by status
- `chom_tenants_total` - Total number of tenants
- `chom_users_total` - Total number of users
- `chom_backups_last_24h` - Backups in last 24 hours
- Custom metrics from MetricsCollector

**Configuration:**
```env
PROMETHEUS_ENABLED=true
PROMETHEUS_NAMESPACE=chom

# Optional: Basic auth for /metrics endpoint
PROMETHEUS_AUTH_ENABLED=true
PROMETHEUS_AUTH_USERNAME=prometheus
PROMETHEUS_AUTH_PASSWORD=secret
```

### 2. Structured Logging for Loki

The application outputs JSON-formatted logs that Promtail can collect and forward to Loki.

**Log Channels:**
- `production` - JSON to stdout (for containerized deployments)
- `json_file` - JSON to `storage/logs/app.json` (for Promtail file scraping)
- `observability` - Configurable stack channel

**Configuration:**
```env
LOG_CHANNEL=observability
LOG_OBSERVABILITY_CHANNELS=json_file
LOG_LEVEL=info
```

**Log Format (JSON):**
```json
{
  "message": "User logged in",
  "context": {"user_id": 123},
  "level": 200,
  "level_name": "INFO",
  "channel": "production",
  "datetime": "2024-01-15T10:30:00.000000+00:00",
  "extra": {}
}
```

### 3. Distributed Tracing (Tempo)

OpenTelemetry-based distributed tracing for Tempo integration.

**Configuration:**
```env
TEMPO_ENABLED=true
TEMPO_ENDPOINT=http://mentat-tst:4318

OTEL_SERVICE_NAME=chom
OTEL_EXPORTER_OTLP_ENDPOINT=http://mentat-tst:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_SAMPLER_ARG=0.1  # 10% sampling
```

**Note:** OpenTelemetry PHP SDK needs to be installed separately:
```bash
composer require open-telemetry/sdk
composer require open-telemetry/exporter-otlp
```

### 4. Grafana Dashboards

The application can embed Grafana dashboards for visualization.

**Configuration:**
```env
GRAFANA_ENABLED=true
GRAFANA_URL=http://mentat-tst:3000
GRAFANA_API_KEY=your-api-key

GRAFANA_DASHBOARD_OVERVIEW=chom-overview
GRAFANA_DASHBOARD_SITES=chom-sites
GRAFANA_DASHBOARD_VPS=chom-vps
```

## Configuration Files

| File | Description |
|------|-------------|
| `config/observability.php` | Main observability configuration |
| `config/logging.php` | Logging channels including JSON formatters |
| `config/chom.php` | Legacy observability settings (use observability.php) |
| `.env.example` | Environment variables documentation |
| `.env.production.example` | Production deployment template |

## Deployment Configurations

| File | Description |
|------|-------------|
| `deploy/configs/promtail-chom.yaml` | Promtail configuration for landsraad_tst |
| `deploy/configs/prometheus-chom-scrape.yaml` | Prometheus scrape config for mentat_tst |

## Setup Steps

### 1. Configure CHOM (.env on landsraad_tst)

```env
# Enable observability
OBSERVABILITY_ENABLED=true

# Prometheus
PROMETHEUS_ENABLED=true
PROMETHEUS_URL=http://mentat-tst:9090
PROMETHEUS_AUTH_ENABLED=true
PROMETHEUS_AUTH_USERNAME=prometheus
PROMETHEUS_AUTH_PASSWORD=your-secure-password

# Loki
LOKI_ENABLED=true
LOKI_URL=http://mentat-tst:3100

# Logging
LOG_CHANNEL=observability
LOG_LEVEL=info

# Grafana
GRAFANA_ENABLED=true
GRAFANA_URL=http://mentat-tst:3000
```

### 2. Configure Prometheus (on mentat_tst)

Add to `/etc/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'chom'
    scrape_interval: 15s
    metrics_path: '/metrics'
    scheme: https
    basic_auth:
      username: 'prometheus'
      password: 'your-secure-password'
    static_configs:
      - targets: ['landsraad-tst:443']
        labels:
          environment: 'production'
          app: 'chom'
```

### 3. Configure Promtail (on landsraad_tst)

Copy `deploy/configs/promtail-chom.yaml` to `/etc/promtail/promtail.yaml` and update:
- Replace `MENTAT_TST_IP` with actual IP/hostname
- Restart Promtail: `systemctl restart promtail`

### 4. Verify Integration

```bash
# Test metrics endpoint
curl -u prometheus:password https://chom.yourdomain.com/metrics

# Test health endpoint
curl https://chom.yourdomain.com/health

# Check Prometheus targets (on mentat_tst)
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="chom")'

# Check Loki logs (on mentat_tst)
curl -G 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={job="chom"}'
```

## Useful PromQL Queries

```promql
# Request rate
rate(chom_http_requests_total[5m])

# Error rate percentage
sum(rate(chom_http_errors_total{type="5xx"}[5m])) / sum(rate(chom_http_requests_total[5m])) * 100

# Memory usage in MB
chom_memory_usage_bytes / 1024 / 1024

# Disk usage percentage
(chom_disk_total_bytes - chom_disk_free_bytes) / chom_disk_total_bytes * 100

# Sites by status
chom_sites_by_status
```

## Useful LogQL Queries

```logql
# All CHOM logs
{job="chom"}

# Error logs only
{job="chom"} | json | level="ERROR"

# Search for specific text
{job="chom"} |= "exception"

# Security-related logs
{job="chom", log_type="security"}

# Slow request logs
{job="chom", log_type="performance"} |= "Slow request"
```

## Troubleshooting

### Metrics not appearing in Prometheus

1. Check if /metrics endpoint is accessible:
   ```bash
   curl -u prometheus:password http://landsraad-tst/metrics
   ```

2. Check Prometheus target status:
   - Navigate to Prometheus UI > Status > Targets
   - Look for the 'chom' job

3. Check firewall rules between mentat_tst and landsraad_tst

### Logs not appearing in Loki

1. Check Promtail status:
   ```bash
   systemctl status promtail
   journalctl -u promtail -f
   ```

2. Verify log file exists and has content:
   ```bash
   ls -la /var/www/chom/storage/logs/app.json
   tail -f /var/www/chom/storage/logs/app.json
   ```

3. Test Loki connection:
   ```bash
   curl http://mentat-tst:3100/ready
   ```

### Application not writing JSON logs

1. Check LOG_CHANNEL setting:
   ```bash
   php artisan tinker
   > config('logging.default')
   ```

2. Clear config cache:
   ```bash
   php artisan config:clear
   ```

## Security Considerations

1. **Metrics Endpoint Protection**
   - Enable basic auth for /metrics endpoint
   - Or restrict access via IP allowlist in web server config
   - Or access via internal network only

2. **Log Data Sensitivity**
   - Avoid logging sensitive data (passwords, tokens)
   - Use context filtering in production
   - Configure log retention policies in Loki

3. **Network Security**
   - Use TLS for all connections in production
   - Restrict observability ports to internal network
   - Use secure credentials for authentication
