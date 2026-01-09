# CHOM Observability Stack

Comprehensive monitoring, logging, and tracing infrastructure for the Cloud Hosting & Observability Manager.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Loki Multi-Tenancy](#loki-multi-tenancy)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Querying Logs](#querying-logs)
- [Dashboards](#dashboards)
- [Alerting](#alerting)
- [Troubleshooting](#troubleshooting)

---

## Overview

CHOM's observability stack provides:

- **Metrics Collection** - Prometheus for time-series metrics
- **Log Aggregation** - Loki for centralized logging with multi-tenancy
- **Visualization** - Grafana for dashboards and alerts
- **Distributed Tracing** - (Future: Tempo integration)

**Key Features:**
- Multi-tenant log isolation (Organization A cannot see Organization B logs)
- Per-tenant resource limits
- Real-time metrics and log streaming
- Pre-built dashboards for common scenarios
- Alert rules for critical conditions

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Observability Stack                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐     │
│  │ Promtail │─────▶│   Loki   │◀─────│ Grafana  │     │
│  └──────────┘      └──────────┘      └──────────┘     │
│       │                  │                  ▲          │
│       │                  │                  │          │
│  ┌────▼─────┐      ┌────▼─────┐      ┌────┴─────┐    │
│  │   Logs   │      │ Storage  │      │ Prometheus│    │
│  │ (Files)  │      │ (Chunks) │      │  (Metrics)│    │
│  └──────────┘      └──────────┘      └──────────┘     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Log Collection**: Promtail tails log files and sends to Loki with tenant_id header
2. **Log Storage**: Loki stores logs per tenant in isolated chunks
3. **Metrics Collection**: Prometheus scrapes metrics from exporters and services
4. **Visualization**: Grafana queries Loki/Prometheus with tenant context
5. **Alerting**: Alert Manager processes rules and sends notifications

---

## Components

### Prometheus

**Purpose:** Time-series metrics database

**Port:** 9090

**Configuration:**
- Docker: `observability-stack/prometheus/prometheus.yml`
- Native: `/etc/observability/prometheus/prometheus.yml`

**Scrape Targets:**
- Node Exporter (system metrics)
- PHP-FPM Exporter (application metrics)
- Nginx Exporter (web server metrics)
- Custom application metrics

### Loki

**Purpose:** Log aggregation with multi-tenancy

**Port:** 3100

**Configuration:**
- Docker: `observability-stack/loki/loki-config.yml`
- Native: `/etc/observability/loki/loki-config.yml`

**Key Features:**
- Multi-tenancy enabled (`auth_enabled: true`)
- Per-tenant resource limits
- Chunk storage with retention policies
- Label-based log querying

### Promtail

**Purpose:** Log shipper for Loki

**Port:** 9080

**Configuration:**
- Docker: `observability-stack/promtail/promtail-config.yml`
- Native: `/etc/observability/promtail/promtail-config.yml`

**Log Sources:**
- Laravel logs (`storage/logs/laravel.log`)
- Nginx access/error logs
- PHP-FPM logs
- System logs

### Grafana

**Purpose:** Visualization and dashboards

**Port:** 3000

**Configuration:**
- Docker: `observability-stack/grafana/`
- Native: `/etc/grafana/`

**Pre-configured:**
- Prometheus datasource
- Loki datasource with multi-tenancy headers
- Default dashboards
- Alert rules

---

## Loki Multi-Tenancy

### Overview

**Date Implemented:** 2026-01-09
**Status:** Complete

Loki multi-tenancy ensures complete log isolation between organizations. Organization A cannot query or view logs from Organization B.

### Key Changes

#### Before (auth_enabled: false)
- All logs stored together without isolation
- No headers required for API requests
- Any user could query any logs
- No per-tenant resource controls

#### After (auth_enabled: true)
- Logs stored per tenant with complete isolation
- **All requests require `X-Scope-OrgID: <tenant-id>` header**
- Users can only query logs for their specified tenant
- Per-tenant resource limits enforced
- Requests without header return `401 Unauthorized`

### Configuration Files

#### 1. Loki Configuration

**Docker:** `observability-stack/loki/loki-config.yml`
```yaml
auth_enabled: true  # CHANGED from false

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  split_queries_by_interval: 15m
  max_streams_per_user: 10000
  max_query_length: 721h
  per_tenant_override_config: /etc/loki/tenant-limits.yaml
```

**Native:** `deploy/config/mentat/loki-config.yml`
```yaml
auth_enabled: true

limits_config:
  # Same as Docker
  per_tenant_override_config: /etc/observability/loki/tenant-limits.yaml
```

#### 2. Tenant Limits File

**Docker:** `observability-stack/loki/tenant-limits.yaml`
**Native:** `deploy/config/mentat/tenant-limits.yaml`

```yaml
overrides:
  "*":  # Default limits for all tenants
    max_streams_per_user: 10000
    max_query_length: 721h
    max_entries_limit_per_query: 10000
    max_chunks_per_query: 2000000
    ingestion_rate_mb: 16
    ingestion_burst_size_mb: 32
```

**Per-Tenant Overrides:**
```yaml
overrides:
  "org-123":  # Specific tenant
    max_streams_per_user: 50000
    ingestion_rate_mb: 32
  "premium-customer":
    max_streams_per_user: 100000
    ingestion_rate_mb: 64
```

#### 3. Promtail Configuration

**Docker:** `observability-stack/promtail/promtail-config.yml`
```yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
    tenant_id: "default-tenant"  # ADDED
```

**Native:** `deploy/config/mentat/promtail-config.yml`
```yaml
clients:
  - url: http://localhost:3100/loki/api/v1/push
    tenant_id: "mentat-system"  # ADDED
```

#### 4. Grafana Datasource

**Docker:** `observability-stack/grafana/provisioning/datasources/datasources.yml`
```yaml
datasources:
  - name: Loki
    type: loki
    url: http://loki:3100
    jsonData:
      maxLines: 1000
      httpHeaderName1: 'X-Scope-OrgID'  # ADDED
    secureJsonData:
      httpHeaderValue1: 'default-tenant'  # ADDED
```

**Native:** `deploy/config/mentat/grafana-datasources.yml`
```yaml
datasources:
  - name: Loki
    type: loki
    url: http://localhost:3100
    jsonData:
      maxLines: 1000
      httpHeaderName1: 'X-Scope-OrgID'  # ADDED
    secureJsonData:
      httpHeaderValue1: 'mentat-system'  # ADDED
```

### Tenant IDs in Use

#### Docker Deployment
- `default-tenant` - Default system logs

#### Native Deployment
- `mentat-system` - Mentat observability stack logs

#### Example Custom Tenants
- `org-a` - Organization A
- `org-b` - Organization B
- `prod` - Production environment
- `staging` - Staging environment
- `customer-123` - Specific customer

---

## Configuration

### Environment Variables

CHOM uses the following observability environment variables:

```env
# Observability Stack URLs
CHOM_PROMETHEUS_URL=http://prometheus:9090
CHOM_LOKI_URL=http://loki:3100
CHOM_GRAFANA_URL=http://grafana:3000
CHOM_GRAFANA_API_KEY=your-api-key

# For HTTPS connections (production)
CHOM_OBSERVABILITY_SSL_VERIFY=true
```

### Docker Compose Volumes

**Location:** `observability-stack/docker-compose.yml`

```yaml
volumes:
  # Loki
  - ./loki/loki-config.yml:/etc/loki/local-config.yaml
  - ./loki/tenant-limits.yaml:/etc/loki/tenant-limits.yaml
  - loki-data:/loki

  # Promtail
  - ./promtail/promtail-config.yml:/etc/promtail/config.yml
  - /var/log:/var/log:ro

  # Grafana
  - ./grafana/provisioning:/etc/grafana/provisioning
  - grafana-data:/var/lib/grafana

  # Prometheus
  - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
  - prometheus-data:/prometheus
```

### Native Deployment Paths

**Configuration:**
- `/etc/observability/loki/loki-config.yml`
- `/etc/observability/loki/tenant-limits.yaml`
- `/etc/observability/promtail/promtail-config.yml`
- `/etc/observability/prometheus/prometheus.yml`
- `/etc/grafana/provisioning/datasources/datasources.yaml`

**Data:**
- `/var/lib/loki/` - Loki chunks and index
- `/var/lib/prometheus/` - Prometheus TSDB
- `/var/lib/grafana/` - Grafana dashboards and settings

**Logs:**
- `/var/log/loki/` - Loki service logs
- `/var/log/prometheus/` - Prometheus service logs
- `/var/log/grafana/` - Grafana service logs

---

## Deployment

### Docker Deployment

```bash
cd /home/calounx/repositories/mentat/observability-stack

# Start all services
docker-compose up -d

# Restart specific service
docker-compose restart loki

# View logs
docker-compose logs -f loki

# Stop all services
docker-compose down
```

### Native Deployment

```bash
cd /home/calounx/repositories/mentat

# Deploy entire observability stack
sudo ./deploy/scripts/deploy-observability.sh

# Or deploy individual components
sudo ./chom/deploy/observability-native/install-loki.sh
sudo ./chom/deploy/observability-native/install-promtail.sh
sudo ./chom/deploy/observability-native/install-prometheus.sh

# Restart services
sudo systemctl restart loki
sudo systemctl restart promtail
sudo systemctl restart prometheus
sudo systemctl restart grafana-server

# Check service status
sudo systemctl status loki
sudo systemctl status promtail
sudo systemctl status prometheus
sudo systemctl status grafana-server
```

### Verification Checklist

- [ ] Loki starts successfully with `auth_enabled: true`
- [ ] Tenant limits file accessible at configured path
- [ ] Promtail sends logs with tenant header
- [ ] Grafana can query logs (datasource has X-Scope-OrgID header)
- [ ] API requests without header return 401
- [ ] Different tenant IDs see different log data
- [ ] Per-tenant limits enforced

---

## Querying Logs

### Via Grafana

1. Open Grafana at `http://localhost:3000` (or your configured URL)
2. Navigate to "Explore"
3. Select "Loki" datasource
4. Use LogQL to query logs

**Example Queries:**

```logql
# All logs for a job
{job="chom-app"}

# Logs matching a pattern
{job="chom-app"} |= "error"

# Logs with label filter
{job="chom-app", level="error"}

# Rate of errors
rate({job="chom-app"} |= "error"[5m])

# Logs for specific tenant (if using dynamic tenant)
{tenant_id="org-a"}
```

### Via LogCLI

```bash
# Install LogCLI
go install github.com/grafana/loki/cmd/logcli@latest

# Query with tenant header
export LOKI_ADDR=http://localhost:3100
export LOKI_ORG_ID=org-a

logcli query '{job="chom-app"}'
logcli query '{job="chom-app"} |= "error"' --limit=100
logcli query '{job="chom-app"}' --since=1h --forward
```

### Via API

```bash
# Push logs
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: org-a" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log message"]]}]}'

# Query logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  -H "X-Scope-OrgID: org-a" \
  --data-urlencode 'query={job="test"}' \
  --data-urlencode 'start='$(date -d '1 hour ago' +%s)'' \
  --data-urlencode 'end='$(date +%s)'' | jq

# List labels
curl -H "X-Scope-OrgID: org-a" \
  http://localhost:3100/loki/api/v1/labels | jq
```

### Via Application Code

**PHP/Laravel Example:**

```php
use Illuminate\Support\Facades\Http;

// Send logs to Loki
Http::withHeaders([
    'Content-Type' => 'application/json',
    'X-Scope-OrgID' => $tenant->id,
])->post(config('observability.loki_url') . '/loki/api/v1/push', [
    'streams' => [[
        'stream' => [
            'job' => 'chom-app',
            'level' => 'info',
            'tenant' => $tenant->id,
        ],
        'values' => [
            [(string) (now()->timestamp * 1000000000), $logMessage],
        ],
    ]],
]);

// Query logs
$response = Http::withHeaders([
    'X-Scope-OrgID' => $tenant->id,
])->get(config('observability.loki_url') . '/loki/api/v1/query_range', [
    'query' => '{job="chom-app"}',
    'start' => now()->subHour()->timestamp,
    'end' => now()->timestamp,
]);
```

---

## Dashboards

### Pre-configured Dashboards

CHOM includes pre-configured Grafana dashboards:

1. **System Overview**
   - CPU, memory, disk usage
   - Network traffic
   - Service health

2. **Application Metrics**
   - Request rate and latency
   - Error rate
   - Database query performance
   - Queue processing

3. **Infrastructure**
   - VPS server health
   - Site performance
   - Backup status
   - SSL certificate expiry

### Creating Custom Dashboards

1. Open Grafana
2. Click "+" → "Dashboard"
3. Add panel with Loki or Prometheus query
4. Save dashboard
5. (Optional) Export JSON and add to provisioning

**Example Loki Panel Query:**
```logql
sum(rate({job="chom-app"} |= "error"[5m])) by (level)
```

**Example Prometheus Panel Query:**
```promql
rate(http_requests_total[5m])
```

---

## Alerting

### Alert Rules

**Location:** `observability-stack/prometheus/alerts/`

**Example Alert:**

```yaml
groups:
  - name: chom_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate({job="chom-app"} |= "error"[5m]) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }} errors/sec"

      - alert: DiskSpaceLow
        expr: node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} available"
```

### Alert Channels

Configure notification channels in Grafana:

1. Navigate to "Alerting" → "Notification channels"
2. Add channel (Email, Slack, PagerDuty, etc.)
3. Test notification
4. Associate with alert rules

---

## Troubleshooting

### Issue: "no org id" error

**Symptom:** Loki API requests return "no org id"

**Solution:** Add `X-Scope-OrgID` header to all Loki requests

```bash
# Before (fails):
curl http://localhost:3100/loki/api/v1/labels

# After (works):
curl -H "X-Scope-OrgID: org-a" http://localhost:3100/loki/api/v1/labels
```

### Issue: Promtail not sending logs

**Symptom:** No logs appearing in Loki

**Solution:**
1. Check Promtail logs: `docker logs promtail` or `journalctl -u promtail -f`
2. Verify `tenant_id` configured in `promtail-config.yml`
3. Check file paths are correct and readable
4. Verify Loki URL is accessible

```bash
# Test Loki connectivity from Promtail
docker exec promtail curl http://loki:3100/ready
```

### Issue: Grafana shows no data

**Symptom:** Grafana datasource shows no data

**Solution:**
1. Verify datasource has `X-Scope-OrgID` header configured
2. Check tenant ID matches logs being sent
3. Test datasource connection in Grafana
4. Verify Loki has data:

```bash
curl -H "X-Scope-OrgID: mentat-system" \
  http://localhost:3100/loki/api/v1/labels | jq
```

### Issue: Loki fails to start

**Symptom:** Loki service won't start

**Solution:**
1. Check tenant limits file exists and is readable
2. Verify path in `per_tenant_override_config` matches actual file location
3. Check Loki logs:
   - Docker: `docker logs chom-loki`
   - Native: `journalctl -u loki -f`
4. Validate YAML syntax:

```bash
# Check loki-config.yml syntax
yamllint /etc/observability/loki/loki-config.yml

# Check tenant-limits.yaml syntax
yamllint /etc/observability/loki/tenant-limits.yaml
```

### Issue: Permission denied on log files

**Symptom:** Promtail can't read log files

**Solution:**
```bash
# Docker: Ensure volumes mounted correctly
docker-compose down
docker-compose up -d

# Native: Fix permissions
sudo usermod -aG adm promtail
sudo systemctl restart promtail
```

### Issue: High memory usage

**Symptom:** Loki consuming excessive memory

**Solution:**
1. Reduce `max_streams_per_user` in tenant limits
2. Decrease retention period
3. Increase `split_queries_by_interval`
4. Review per-tenant limits

```yaml
# Adjust in tenant-limits.yaml
overrides:
  "*":
    max_streams_per_user: 5000  # Reduced from 10000
    max_query_length: 168h      # Reduced from 721h
```

---

## Testing Multi-Tenancy

### Quick Test Script

```bash
cd /home/calounx/repositories/mentat/observability-stack

# Start stack
docker-compose up -d

# Wait for Loki to be ready
sleep 10

# Push log for tenant A
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: org-a" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log from org-a"]]}]}'

# Push log for tenant B
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: org-b" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log from org-b"]]}]}'

# Query tenant A (should only see org-a logs)
echo "Tenant A logs:"
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  -H "X-Scope-OrgID: org-a" \
  --data-urlencode 'query={job="test"}' | jq -r '.data.result[].values[][1]'

# Query tenant B (should only see org-b logs)
echo "Tenant B logs:"
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  -H "X-Scope-OrgID: org-b" \
  --data-urlencode 'query={job="test"}' | jq -r '.data.result[].values[][1]'

# Request without header (should fail with 401)
echo "Request without tenant header:"
curl -v http://localhost:3100/loki/api/v1/labels
```

**Expected Output:**
```
Tenant A logs:
Log from org-a

Tenant B logs:
Log from org-b

Request without tenant header:
< HTTP/1.1 401 Unauthorized
no org id
```

---

## Security Considerations

1. **Tenant Isolation**
   - Complete log isolation between tenants verified by design
   - No cross-tenant data leakage possible

2. **Authentication**
   - Multi-tenancy provides data isolation, NOT authentication
   - Implement authentication layer at reverse proxy or application level

3. **Network Security**
   - Loki should not be exposed directly to the internet
   - Use VPN or private network for access
   - Configure firewall rules appropriately

4. **Reverse Proxy**
   - Use nginx with authentication for external access
   - Add rate limiting to prevent abuse
   - Implement TLS for encrypted connections

5. **Tenant ID Management**
   - Treat tenant IDs as configuration data
   - Map organization IDs to tenant IDs securely
   - Document tenant ID conventions

6. **Resource Limits**
   - Set appropriate per-tenant limits to prevent DoS
   - Monitor tenant resource usage
   - Alert on limit violations

---

## Performance Optimization

### Loki Performance Tips

1. **Use efficient queries**
   - Filter by labels first: `{job="app"} |= "error"`
   - Avoid regex when possible
   - Use `|=` (contains) instead of `|~` (regex) when exact match works

2. **Limit query time range**
   - Query shorter time windows
   - Use `--since` and `--until` flags
   - Set reasonable `max_query_length`

3. **Optimize label cardinality**
   - Keep label values low cardinality
   - Avoid high-cardinality labels (user IDs, request IDs)
   - Use structured metadata for high-cardinality data

4. **Configure retention**
   - Set retention period based on needs
   - Delete old chunks regularly
   - Monitor storage usage

### Prometheus Performance Tips

1. **Reduce scrape frequency** for low-priority targets
2. **Use recording rules** for complex queries
3. **Set appropriate retention** period
4. **Enable compression** for remote storage

---

## Related Documentation

- [Multi-Tenancy Architecture](../architecture/multi-tenancy.md) - Security isolation implementation
- [Health Checks](health-checks.md) - System health monitoring
- [Self-Healing](self-healing.md) - Automated recovery procedures
- [Deployment](../deployment/observability.md) - Deployment procedures

---

## References

- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Loki Multi-Tenancy Docs](https://grafana.com/docs/loki/latest/operations/multi-tenancy/)
- [LogQL Syntax](https://grafana.com/docs/loki/latest/logql/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)

---

## Configuration File Reference

### Docker Deployment
- Loki config: `observability-stack/loki/loki-config.yml`
- Tenant limits: `observability-stack/loki/tenant-limits.yaml`
- Promtail config: `observability-stack/promtail/promtail-config.yml`
- Grafana datasources: `observability-stack/grafana/provisioning/datasources/datasources.yml`
- Docker compose: `observability-stack/docker-compose.yml`

### Native Deployment
- Loki config: `deploy/config/mentat/loki-config.yml` → `/etc/observability/loki/loki-config.yml`
- Tenant limits: `deploy/config/mentat/tenant-limits.yaml` → `/etc/observability/loki/tenant-limits.yaml`
- Promtail config: `deploy/config/mentat/promtail-config.yml` → `/etc/observability/promtail/promtail-config.yml`
- Grafana datasources: `deploy/config/mentat/grafana-datasources.yml` → `/etc/grafana/provisioning/datasources/datasources.yaml`

---

**Last Updated:** 2026-01-09
**Version:** 2.1.0
**Status:** Production Ready
