# CHOM Platform - Advanced SRE/DevOps Dashboards

Enterprise-grade Grafana dashboards for comprehensive monitoring of the CHOM platform, focusing on SRE best practices, DORA metrics, and infrastructure health.

## Quick Start

```bash
# 1. Ensure Prometheus is running and configured
docker-compose up -d prometheus

# 2. Import dashboards to Grafana
# Method A: UI Import (see IMPORT_GUIDE.md)
# Method B: Automated provisioning
cp *.json /var/lib/grafana/dashboards/chom-advanced/

# 3. Configure data source in Grafana
# Settings > Data Sources > Add Prometheus

# 4. Access dashboards
# http://localhost:3000/dashboards
```

## Dashboard Overview

### 1. SRE Golden Signals Dashboard
**File:** `sre-golden-signals.json`
**UID:** `chom-sre-golden-signals`

Monitors the four pillars of service reliability:

- **Latency** - Response time percentiles (p50, p90, p95, p99)
- **Traffic** - Request rates and bandwidth utilization
- **Errors** - Error rates and error budget tracking
- **Saturation** - Resource utilization (CPU, memory, disk, connections)

**Use Cases:**
- Real-time service health monitoring
- SLO/SLA compliance tracking
- On-call engineer primary dashboard
- Incident response and debugging

**Key Panels:**
- Service availability gauge
- Error budget remaining
- Request rate trends
- Latency percentiles by endpoint
- Resource saturation metrics
- SLO achievement tracking (99.9% availability, p95 < 200ms)

---

### 2. DevOps Deployment & Change Management Dashboard
**File:** `devops-deployment.json`
**UID:** `chom-devops-deployment`

Tracks DORA (DevOps Research and Assessment) metrics:

- **Deployment Frequency** - How often deployments occur
- **Lead Time for Changes** - Commit to production time
- **Change Failure Rate** - Percentage requiring rollback
- **Mean Time to Recovery (MTTR)** - Average incident recovery time

**Use Cases:**
- Engineering productivity measurement
- Release process optimization
- DevOps transformation tracking
- Team performance benchmarking

**Key Panels:**
- Deployment frequency trends
- Lead time distribution
- Change failure rate by environment
- MTTR by incident severity
- Pipeline success rates
- Git commit activity
- Deployment timeline visualization
- Rollback frequency analysis

---

### 3. Infrastructure Health Dashboard
**File:** `infrastructure-health.json`
**UID:** `chom-infrastructure-health`

Comprehensive infrastructure monitoring:

- **Service Health** - Uptime, availability, dependencies
- **Disk I/O** - Throughput, IOPS, latency
- **Network** - Inter-service latency, bandwidth
- **SSL Certificates** - Expiry tracking for all domains
- **Backups** - Success rates, duration, freshness
- **Logging** - Error trends and log volume
- **System Resources** - Entropy, process health

**Use Cases:**
- Infrastructure capacity planning
- Performance troubleshooting
- Security compliance monitoring
- Backup verification
- Certificate management

**Key Panels:**
- Service dependency map
- Container/process health table
- Disk I/O performance metrics
- SSL certificate expiry warnings
- Backup success/failure tracking
- Log error rate trends
- System entropy monitoring

---

## Features

### Advanced Visualizations
- **Time Series Graphs** - Trend analysis with multiple percentiles
- **Gauge Panels** - Real-time status indicators
- **Bar Charts** - Deployment frequency, error distribution
- **Tables** - Service health, SSL certificates, backups
- **Pie Charts** - Service dependency distribution

### Templating & Variables
- **Multi-select Dropdowns** - Filter by instance, environment, service
- **Dynamic Updates** - All panels react to variable changes
- **Query-based Options** - Auto-populated from Prometheus

### Alert Integration
- **Deployment Annotations** - Visual markers for deployments
- **Rollback Indicators** - Highlight failed deployments
- **Service Restart Tracking** - Detect container/process restarts

### Thresholds & Colors
- **Green** - Normal operation
- **Yellow** - Warning threshold
- **Red** - Critical threshold
- **Contextual Coloring** - Different metrics have appropriate scales

## Technical Requirements

### Minimum Versions
- Grafana: 8.0+
- Prometheus: 2.30+
- Node Exporter: 1.3+

### Required Exporters
- **Node Exporter** - System metrics (CPU, memory, disk, network)
- **MySQL Exporter** - Database metrics (if using MySQL)
- **Redis Exporter** - Cache metrics (if using Redis)
- **Application Metrics** - Custom CHOM metrics (see IMPORT_GUIDE.md)

### Prometheus Scrape Targets
```yaml
scrape_configs:
  - job_name: 'chom'          # Application metrics
  - job_name: 'node'          # System metrics
  - job_name: 'mysql'         # Database metrics
  - job_name: 'redis'         # Cache metrics
```

## Metrics Reference

### Golden Signals Metrics
```promql
# Latency
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Traffic
sum(rate(http_requests_total[1m]))

# Errors
sum(rate(http_requests_total{code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Saturation
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

### DORA Metrics
```promql
# Deployment Frequency
sum(increase(chom_deployment_total{type="deployment"}[7d]))

# Lead Time
avg(chom_deployment_lead_time_minutes)

# Change Failure Rate
sum(increase(chom_deployment_total{type="rollback"}[30d])) / sum(increase(chom_deployment_total{type="deployment"}[30d]))

# MTTR
avg(chom_incident_mttr_minutes)
```

### Infrastructure Metrics
```promql
# Service Health
up{job=~"chom|node|mysql|redis"}

# Disk IOPS
rate(node_disk_reads_completed_total[5m])

# SSL Certificate Expiry
(ssl_certificate_expiry_seconds - time()) / 86400

# Backup Success Rate
sum(rate(chom_backup_total{status="success"}[1d])) / sum(rate(chom_backup_total[1d]))
```

## Performance Characteristics

### Query Load
- **Average Queries per Dashboard:** 20-30
- **Refresh Rate:** 30 seconds (configurable)
- **Time Range:** 6 hours to 7 days (dashboard-dependent)

### Resource Usage
- **Prometheus Storage:** ~2GB per month (default retention)
- **Grafana Memory:** ~500MB per dashboard instance
- **Query Response Time:** < 1 second (optimized queries)

### Optimization Tips
1. Use Prometheus recording rules for complex queries
2. Adjust refresh interval based on use case (longer = less load)
3. Limit time range when troubleshooting specific incidents
4. Use template variables to reduce query scope

## Alert Configuration

Each dashboard can trigger alerts based on panel thresholds:

### Critical Alerts
- Service availability < 99.9%
- Error rate > 5%
- Error budget burn rate > 14.4x
- SSL certificate expired
- Backup failures > 5%

### Warning Alerts
- p95 latency > 200ms
- CPU usage > 70%
- Memory usage > 80%
- Disk usage > 80%
- SSL certificate expires < 30 days
- Change failure rate > 15%

See `IMPORT_GUIDE.md` for complete alert rule configurations.

## Dashboard Customization

### Common Modifications

1. **Adjust SLO Targets**
   - Edit gauge thresholds for your SLOs
   - Example: Change 99.9% to 99.95% for critical services

2. **Add Custom Panels**
   - Use "Add Panel" button
   - Select Prometheus data source
   - Write PromQL query
   - Configure visualization

3. **Modify Time Ranges**
   - Change default time range in dashboard settings
   - Adjust panel-specific overrides

4. **Update Variables**
   - Dashboard Settings > Variables
   - Add/modify/remove template variables
   - Useful for multi-tenant setups

### Example: Adding Application-Specific Panel

```json
{
  "title": "API Response Codes",
  "targets": [
    {
      "expr": "sum(rate(http_requests_total{job=\"chom\"}[5m])) by (code)",
      "legendFormat": "HTTP {{code}}"
    }
  ],
  "type": "timeseries"
}
```

## Troubleshooting

### Common Issues

**No Data Displayed**
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Verify metrics exist
curl http://localhost:9090/api/v1/query?query=up

# Check Grafana data source
# Settings > Data Sources > Prometheus > Save & Test
```

**Slow Loading**
```bash
# Enable Prometheus query logging
prometheus --log.level=debug

# Check query performance
curl 'http://localhost:9090/api/v1/query?query=YOUR_QUERY'

# Use recording rules for complex queries
```

**Missing Metrics**
```bash
# List all available metrics
curl http://localhost:9090/api/v1/label/__name__/values

# Check application metrics endpoint
curl http://your-app:9090/metrics | grep chom_
```

## Best Practices

### Monitoring Strategy
1. **Start with Golden Signals** - Most critical for service reliability
2. **Track DORA Metrics** - Measure and improve engineering velocity
3. **Monitor Infrastructure** - Prevent capacity and performance issues

### Alert Fatigue Prevention
1. Use multi-window burn rate alerts (1h + 6h)
2. Set appropriate thresholds for your scale
3. Group related alerts together
4. Implement alert inhibition rules

### Dashboard Maintenance
1. Review and update quarterly
2. Remove unused panels
3. Optimize slow queries
4. Document custom metrics
5. Keep annotations current

## Integration Examples

### Slack Notifications
```yaml
# alertmanager.yml
receivers:
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#monitoring'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

### PagerDuty Integration
```yaml
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'YOUR_SERVICE_KEY'
        severity: 'critical'
```

### Webhook Integration
```yaml
receivers:
  - name: 'webhook'
    webhook_configs:
      - url: 'http://your-webhook-url'
        send_resolved: true
```

## Compliance & Security

### Data Retention
- **Prometheus:** 15 days default (configurable)
- **Grafana:** Unlimited dashboard history
- **Logs:** 30 days recommended

### Access Control
- Use Grafana organizations for multi-tenancy
- Implement RBAC (Role-Based Access Control)
- Enable audit logging
- Restrict data source permissions

### Privacy Considerations
- Avoid logging sensitive data
- Use label_replace to anonymize where needed
- Implement data retention policies
- Regular security audits

## Roadmap

### Planned Features
- [ ] Service mesh (Istio) integration
- [ ] Distributed tracing correlation
- [ ] Cost optimization metrics
- [ ] ML-based anomaly detection
- [ ] Mobile app health metrics
- [ ] User journey tracking

### Enhancement Ideas
- Custom business metrics overlay
- Multi-cluster aggregation
- Comparative analysis (week-over-week)
- Automated capacity forecasting
- Incident timeline reconstruction

## Support & Contributing

### Getting Help
1. Check `IMPORT_GUIDE.md` for detailed instructions
2. Review Prometheus/Grafana documentation
3. Open GitHub issue for bugs or feature requests

### Contributing
Contributions welcome! To modify dashboards:
1. Make changes in Grafana UI
2. Export as JSON
3. Format and validate JSON
4. Submit pull request with description

### Reporting Issues
Include:
- Grafana version
- Prometheus version
- Dashboard name and panel
- Error messages or screenshots
- Steps to reproduce

---

## Files in This Directory

```
advanced/
├── README.md                        # This file
├── IMPORT_GUIDE.md                  # Detailed setup instructions
├── sre-golden-signals.json          # SRE Dashboard
├── devops-deployment.json           # DevOps Dashboard
└── infrastructure-health.json       # Infrastructure Dashboard
```

---

## Quick Reference

### Dashboard URLs (after import)
```
http://localhost:3000/d/chom-sre-golden-signals
http://localhost:3000/d/chom-devops-deployment
http://localhost:3000/d/chom-infrastructure-health
```

### Key Metrics to Watch
- **Availability:** > 99.9%
- **p95 Latency:** < 200ms
- **Error Rate:** < 0.1%
- **Deployment Frequency:** > 1/day
- **Change Failure Rate:** < 15%
- **MTTR:** < 1 hour

### Important Thresholds
- **CPU:** Warn: 70%, Critical: 90%
- **Memory:** Warn: 80%, Critical: 95%
- **Disk:** Warn: 80%, Critical: 95%
- **Error Budget Burn:** Critical: 14.4x
- **SSL Expiry:** Warn: 30 days, Critical: 7 days

---

**Version:** 1.0.0
**Created:** 2026-01-02
**License:** MIT
**Maintained By:** CHOM SRE Team
