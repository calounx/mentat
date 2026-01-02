# Cost Analysis & Capacity Planning Architecture

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CHOM Platform                               │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Laravel Application                          │    │
│  │                                                                 │    │
│  │  ┌──────────────────────────────────────────────────────┐      │    │
│  │  │         MetricsExporter Service                     │      │    │
│  │  │  - Calculate infrastructure costs                   │      │    │
│  │  │  - Track tenant resource usage                      │      │    │
│  │  │  - Monitor capacity utilization                     │      │    │
│  │  │  - Generate optimization recommendations            │      │    │
│  │  └──────────────────────────────────────────────────────┘      │    │
│  │                           │                                     │    │
│  │                           │ Exposes /metrics endpoint           │    │
│  │                           ▼                                     │    │
│  │  ┌──────────────────────────────────────────────────────┐      │    │
│  │  │      Prometheus Format Metrics                      │      │    │
│  │  │  - chom_infrastructure_cost_monthly                 │      │    │
│  │  │  - chom_tenant_cost_monthly                         │      │    │
│  │  │  - chom_storage_bytes_total                         │      │    │
│  │  │  - chom_capacity_headroom                           │      │    │
│  │  └──────────────────────────────────────────────────────┘      │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTP /metrics
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            Prometheus Server                             │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Scrape Configuration                         │    │
│  │  - scrape_interval: 30s                                         │    │
│  │  - targets: ['chom.example.com:80']                            │    │
│  │  - metrics_path: '/metrics'                                     │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Time Series Database                         │    │
│  │  - Stores all metrics with timestamps                          │    │
│  │  - Retention: 15 days (configurable)                           │    │
│  │  - Supports PromQL queries                                     │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Alert Manager                                │    │
│  │  - Budget exceeded alerts                                      │    │
│  │  - Capacity threshold alerts                                   │    │
│  │  - Cost anomaly detection                                      │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ PromQL Queries
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             Grafana Server                               │
│                                                                          │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐   │
│  │    Cost Analysis Dashboard   │  │  Capacity Planning Dashboard │   │
│  │                              │  │                              │   │
│  │  Panels:                     │  │  Panels:                     │   │
│  │  ├─ Total Monthly Cost       │  │  ├─ CPU Utilization          │   │
│  │  ├─ Budget Utilization       │  │  ├─ Memory Utilization       │   │
│  │  ├─ Cost Trend vs Budget     │  │  ├─ Disk Utilization         │   │
│  │  ├─ Cost Breakdown           │  │  ├─ Storage Headroom         │   │
│  │  ├─ Cost per Tenant          │  │  ├─ CPU Trend & Forecast     │   │
│  │  ├─ Storage Growth           │  │  ├─ Memory Trend & Forecast  │   │
│  │  ├─ Bandwidth Usage          │  │  ├─ Storage Growth           │   │
│  │  ├─ Email Service Costs      │  │  ├─ DB Size Projection       │   │
│  │  ├─ Optimization Opps        │  │  ├─ Tenant Resources         │   │
│  │  └─ Infrastructure ROI       │  │  └─ Scaling Recommendations  │   │
│  │                              │  │                              │   │
│  └──────────────────────────────┘  └──────────────────────────────┘   │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    Notification Channels                        │    │
│  │  - Email alerts                                                │    │
│  │  - Slack notifications                                         │    │
│  │  - PagerDuty integration                                       │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Notifications
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Operations Team                                 │
│                                                                          │
│  Daily:                     Weekly:                  Monthly:            │
│  ├─ Review cost dashboard   ├─ Capacity planning    ├─ Cost reports     │
│  ├─ Check anomalies         ├─ Growth forecasts     ├─ Budget review    │
│  └─ Verify budgets          └─ Scaling decisions    └─ Optimization     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌──────────────┐
│ CHOM App     │
│ (Laravel)    │
└──────┬───────┘
       │
       │ 1. Collect resource usage data
       │    - VPS count, storage, bandwidth
       │    - Tenant resource consumption
       │    - Email volume, DB size
       │
       ▼
┌──────────────────────┐
│ MetricsExporter      │
│                      │
│ - Calculate costs    │
│ - Check thresholds   │
│ - Generate metrics   │
└──────┬───────────────┘
       │
       │ 2. Expose Prometheus metrics
       │    GET /metrics
       │
       ▼
┌──────────────────────┐
│ Prometheus           │
│                      │
│ - Scrape every 30s   │
│ - Store time series  │
│ - Evaluate alerts    │
└──────┬───────────────┘
       │
       │ 3. Query metrics (PromQL)
       │
       ▼
┌──────────────────────┐
│ Grafana Dashboards   │
│                      │
│ - Visualize data     │
│ - Show trends        │
│ - Display forecasts  │
└──────┬───────────────┘
       │
       │ 4. Send alerts
       │
       ▼
┌──────────────────────┐
│ Operations Team      │
│                      │
│ - Review metrics     │
│ - Optimize costs     │
│ - Plan capacity      │
└──────────────────────┘
```

## Component Responsibilities

### 1. CHOM Application (Laravel)

**Responsibility:** Track resource usage and generate metrics

**Key Functions:**
- Monitor VPS count and specifications
- Track storage usage per tenant
- Measure bandwidth consumption
- Count email sends
- Monitor database size

**Implementation:**
- `app/Services/MetricsExporter.php` - Main metrics service
- `config/metrics-config.php` - Configuration
- `routes/web.php` - Metrics endpoint

### 2. Prometheus

**Responsibility:** Collect, store, and query metrics

**Key Functions:**
- Scrape CHOM `/metrics` endpoint every 30 seconds
- Store time series data (15 days retention)
- Evaluate alerting rules
- Provide PromQL query interface

**Configuration:**
```yaml
# /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'chom'
    scrape_interval: 30s
    static_configs:
      - targets: ['chom.example.com:80']
```

### 3. Grafana

**Responsibility:** Visualize metrics and send alerts

**Key Functions:**
- Display cost analysis dashboard
- Display capacity planning dashboard
- Show trend lines and forecasts
- Send notifications via email/Slack
- Provide drill-down capabilities

**Dashboards:**
- `cost-analysis.json` - Financial operations
- `capacity-planning.json` - Resource planning

### 4. Alert Manager

**Responsibility:** Handle and route alerts

**Key Functions:**
- Receive alerts from Prometheus/Grafana
- Route to appropriate channels (email, Slack, PagerDuty)
- Throttle alert frequency
- Group related alerts

**Alert Types:**
- Budget exceeded
- Cost anomaly detected
- Capacity threshold exceeded
- Storage headroom low

## Metrics Flow

```
Resource Usage → Calculate Cost → Export Metric → Store in Prometheus → Query in Grafana → Visualize
     ↓                 ↓                ↓                  ↓                   ↓              ↓
  DB queries      Pricing model    Prometheus      Time series DB        Dashboard      Alerts
```

### Example: Storage Cost Tracking

1. **Collect:** Query database for total storage used
   ```php
   $storageBytes = DB::table('sites')->sum('storage_used_bytes');
   ```

2. **Calculate:** Apply pricing model
   ```php
   $storageGB = $storageBytes / (1024 ** 3);
   $cost = $storageGB * 0.15; // $0.15 per GB
   ```

3. **Export:** Generate Prometheus metric
   ```
   chom_infrastructure_cost_monthly{category="storage",resource_type="disk"} 750.50
   chom_storage_bytes_total{service="chom"} 5000000000000
   ```

4. **Store:** Prometheus scrapes and stores
   ```
   [timestamp: 1704211200] chom_storage_bytes_total = 5000000000000
   [timestamp: 1704211230] chom_storage_bytes_total = 5000100000000
   [timestamp: 1704211260] chom_storage_bytes_total = 5000200000000
   ```

5. **Query:** Grafana uses PromQL
   ```promql
   sum(chom_storage_bytes_total{service="chom"})
   ```

6. **Visualize:** Display in dashboard panel
   - Current: 4.55 TB
   - Trend: Growing at 10 GB/day
   - Forecast: 6.25 TB in 90 days
   - Cost: $750/month

7. **Alert:** If threshold exceeded
   - Storage > 80% → Warning
   - Storage > 90% → Critical alert sent

## Forecast Mechanism

```
Historical Data (7/30/90 days)
         ↓
   Linear Regression
         ↓
   predict_linear() in PromQL
         ↓
   Future Values (30/60/90 days)
         ↓
   Display on Dashboard
```

**Example PromQL:**
```promql
# Current CPU usage
avg(rate(node_cpu_seconds_total{mode!="idle"}[5m])) * 100

# 30-day forecast
predict_linear(node_cpu_seconds_total{mode!="idle"}[30d], 30*24*3600) * 100
```

## Integration Points

### Input Sources

1. **CHOM Database**
   - Sites, VPS, Teams tables
   - Storage usage, bandwidth logs
   - Email send logs

2. **System Metrics**
   - Node Exporter (CPU, Memory, Disk)
   - MySQL Exporter (DB metrics)
   - Custom application metrics

3. **External APIs** (optional)
   - Cloud provider cost APIs
   - Email service APIs
   - Payment processor APIs

### Output Destinations

1. **Dashboards**
   - Grafana web UI
   - PDF reports
   - Embedded dashboards

2. **Notifications**
   - Email (SMTP)
   - Slack webhooks
   - PagerDuty API
   - Custom webhooks

3. **Integrations**
   - JIRA tickets for capacity issues
   - Cost reports via email
   - Automated scaling triggers

## Security Considerations

1. **Metrics Endpoint**
   - Consider authentication for `/metrics`
   - Restrict to Prometheus IP
   - Use internal network if possible

2. **Sensitive Data**
   - Don't expose customer names in metrics
   - Use tenant IDs instead of emails
   - Sanitize label values

3. **Access Control**
   - Grafana authentication required
   - Role-based dashboard access
   - Audit log for changes

## Scalability

### Current Design
- Handles up to 1,000 tenants
- Metrics endpoint cached (60s TTL)
- Prometheus 15-day retention
- 30-second scrape interval

### Scaling Considerations

**More Tenants:**
- Implement metric streaming (push model)
- Use Prometheus federation
- Optimize query performance

**More Metrics:**
- Increase Prometheus storage
- Use Thanos for long-term storage
- Implement metric filtering

**More Dashboards:**
- Use Grafana folders
- Implement dashboard templates
- Automated provisioning

## Disaster Recovery

### Backup Strategy
```
Prometheus Data → Daily Backup → S3/Object Storage
Grafana Dashboards → Version Control (Git)
Configuration → Infrastructure as Code
```

### Recovery Procedure
1. Restore Prometheus data from backup
2. Import dashboards from Git
3. Apply configuration
4. Verify metrics collection
5. Test alerts

### RTO/RPO
- **RTO:** 1 hour (time to restore service)
- **RPO:** 24 hours (acceptable data loss)
- **Critical Path:** Prometheus → Grafana → Alerts

---

This architecture provides a robust, scalable foundation for FinOps and capacity planning in CHOM, with clear data flows, defined responsibilities, and comprehensive monitoring capabilities.
