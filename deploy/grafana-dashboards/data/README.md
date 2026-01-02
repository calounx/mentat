# CHOM Data & API Analytics Dashboards

This directory contains Grafana dashboards and documentation for monitoring data pipelines, API usage, and multi-tenant analytics in the CHOM platform.

## Dashboards

### 6. API Analytics (`6-api-analytics.json`)

Comprehensive API monitoring dashboard tracking endpoint usage, rate limiting, and API consumer behavior.

**Key Panels:**
- API Request Rate by Endpoint
- API Usage by Consumer (pie chart)
- Rate Limit Consumption by Tier (gauges)
- API Version Adoption (bar chart)
- Deprecated Endpoint Usage
- API Error Distribution
- Response Payload Sizes (p50, p95, p99)
- API Key Distribution and Activity
- Webhook Delivery Success Rate
- Top API Consumers (table)
- Rate Limit Violations (HTTP 429)
- API Response Time by Endpoint (p95)

**Use Cases:**
- Identify most-used API endpoints
- Track API consumer behavior patterns
- Monitor rate limit consumption
- Plan API version migrations
- Optimize response payload sizes
- Ensure webhook reliability

**Variables:**
- `$tier` - Filter by tier (free, pro, enterprise)
- `$endpoint` - Filter by API endpoint

**Refresh Rate:** 30 seconds

---

### 7. Data Pipeline (`7-data-pipeline.json`)

Monitor background job processing, ETL operations, and data flow health.

**Key Panels:**
- Queue Job Processing Rate
- Queue Depth (Pending Jobs)
- Background Job Success/Failure Rate
- Top Failed Jobs (table)
- Data Import/Export Volumes
- ETL Job Performance (p50, p95)
- Data Validation Error Rates
- Data Transformation Latency
- Scheduled Job Execution (table)
- Batch Processing Throughput
- Queue Wait Time
- Job Retry Distribution
- Data Pipeline Health Score

**Use Cases:**
- Monitor queue health and backlog
- Track ETL job performance
- Identify data quality issues
- Optimize batch processing
- Plan worker capacity
- Ensure scheduled jobs run on time

**Variables:**
- `$queue` - Filter by queue name
- `$etl_job` - Filter by ETL job name

**Refresh Rate:** 30 seconds

---

### 8. Tenant Analytics (`8-tenant-analytics.json`)

Multi-tenant resource usage, growth metrics, and isolation verification.

**Key Panels:**
- Per-Tenant Resource Usage (CPU, Memory)
- Tenant Growth Over Time
- Storage Consumption by Tenant (table)
- API Usage by Tenant (top 10)
- Feature Usage by Tenant (table)
- Tenant Health Scores (bar gauge)
- Multi-Tenancy Isolation Verification
- Cross-Tenant Performance Comparison (response time)
- Cross-Tenant Error Rate Comparison
- MRR by Tenant Tier (stacked area)
- Capacity Planning Metrics by Tenant (table)
- Tenant Churn Risk Indicators (table)

**Use Cases:**
- Monitor per-tenant resource consumption
- Track tenant growth and activity
- Verify tenant isolation
- Identify tenants at risk of churn
- Support usage-based billing
- Plan capacity for tenant growth
- Compare performance across tenants

**Variables:**
- `$tenant` - Filter by tenant ID
- `$tier` - Filter by tenant tier

**Refresh Rate:** 30 seconds

---

## Documentation

### API Usage Optimization Guide (`API-USAGE-OPTIMIZATION-GUIDE.md`)

Comprehensive guide covering:

1. **API Performance Optimization**
   - Rate limiting strategies (token bucket algorithm)
   - Response optimization (field selection, compression, pagination)
   - Caching strategies (HTTP headers, application cache, CDN)
   - API version management and deprecation

2. **Data Pipeline Best Practices**
   - Queue architecture and prioritization
   - Job optimization (idempotency, chunking, batching)
   - ETL pipeline patterns (incremental processing)
   - Data quality checks and validation

3. **Multi-Tenant Optimization**
   - Tenant isolation strategies (schema-based, row-level, database-per-tenant)
   - Resource fair-sharing (CPU, memory, database connections)
   - Rate limiting per tenant

4. **Capacity Planning**
   - Resource forecasting (CPU, memory, storage, API requests)
   - Scaling thresholds (HPA, database, queue workers)
   - Cost optimization strategies

5. **Usage-Based Billing**
   - Metering strategy implementation
   - Pricing models and calculations
   - Monthly billing computation

6. **Monitoring and Alerting**
   - Critical alerts (API health, data pipeline, tenant health)
   - SLO-based alerts (error budget burn rate)
   - Alert routing and escalation

7. **Cost Optimization**
   - Infrastructure cost analysis
   - Cost attribution by tenant
   - Performance vs cost trade-offs

---

## Installation

### Import Dashboards

```bash
# Using Grafana API
for dashboard in 6-api-analytics.json 7-data-pipeline.json 8-tenant-analytics.json; do
  curl -X POST \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d @${dashboard} \
    http://grafana.chom.app/api/dashboards/db
done

# Or use Grafana UI:
# 1. Navigate to Dashboards > Import
# 2. Upload JSON file
# 3. Select Prometheus datasource
# 4. Click Import
```

### Configure Datasources

Ensure Prometheus datasource is configured:

```yaml
# datasources.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

---

## Metrics Requirements

### Application Metrics

The dashboards expect the following metrics to be exposed by the CHOM application:

#### API Metrics
```
http_requests_total{job, endpoint, consumer, tier, api_version, status, deprecated}
http_request_duration_seconds_bucket{job, endpoint}
http_response_size_bytes_bucket{job, endpoint}
api_key_last_used{job, tier}
webhook_deliveries_total{job, status}
```

#### Data Pipeline Metrics
```
laravel_queue_jobs_processed_total{job, queue, status, job_type}
laravel_queue_size{job, queue}
laravel_queue_wait_seconds_bucket{job, queue}
laravel_queue_job_retries_total{job, retry_count}
data_import_records_total{job, source}
data_export_records_total{job, destination}
etl_job_duration_seconds_bucket{job, etl_job}
data_validation_errors_total{job, validation_type, field}
data_transformation_duration_seconds_bucket{job, transformation}
scheduled_job_last_run_timestamp_seconds{job, job_name}
scheduled_job_last_duration_seconds{job, job_name}
scheduled_job_last_status{job, job_name}
batch_processing_records_total{job, batch_type}
```

#### Tenant Metrics
```
container_cpu_usage_seconds_total{job, tenant}
container_memory_usage_bytes{job, tenant}
container_memory_limit_bytes{job, tenant}
tenant_database_size_bytes{job, tenant}
tenant_file_storage_bytes{job, tenant}
tenant_feature_vps_count{job, tenant}
tenant_feature_sites_count{job, tenant}
tenant_feature_backup_enabled{job, tenant}
tenant_feature_ssl_enabled{job, tenant}
tenant_isolation_violations_total{job, violation_type}
cross_tenant_query_attempts_total{job}
tenant_mrr_dollars{job, tenant, tier}
```

### Implementing Metrics in Laravel

Use the `prometheus-php` library:

```php
// app/Http/Middleware/PrometheusMetrics.php
class PrometheusMetrics
{
    public function handle($request, Closure $next)
    {
        $start = microtime(true);
        $response = $next($request);
        $duration = microtime(true) - $start;

        // Record HTTP metrics
        app('prometheus')->counter(
            'http_requests_total',
            'Total HTTP requests',
            ['endpoint', 'consumer', 'tier', 'status', 'api_version']
        )->inc([
            $request->route()->getName(),
            $request->user()?->consumer ?? 'anonymous',
            $request->user()?->team->tier ?? 'free',
            $response->status(),
            $request->header('X-API-Version', 'v1'),
        ]);

        app('prometheus')->histogram(
            'http_request_duration_seconds',
            'HTTP request duration',
            ['endpoint'],
            [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
        )->observe($duration, [$request->route()->getName()]);

        return $response;
    }
}

// app/Jobs/ProcessVpsDeployment.php
class ProcessVpsDeployment implements ShouldQueue
{
    public function handle()
    {
        app('prometheus')->counter(
            'laravel_queue_jobs_processed_total',
            'Queue jobs processed',
            ['queue', 'status', 'job_type']
        )->inc([
            $this->queue ?? 'default',
            'success',
            static::class,
        ]);
    }

    public function failed(\Throwable $exception)
    {
        app('prometheus')->counter(
            'laravel_queue_jobs_processed_total',
            'Queue jobs processed',
            ['queue', 'status', 'job_type']
        )->inc([
            $this->queue ?? 'default',
            'failed',
            static::class,
        ]);
    }
}
```

---

## Alert Configuration

### Prometheus Alert Rules

```yaml
# /etc/prometheus/rules/chom-data-alerts.yml
groups:
  - name: api_alerts
    interval: 30s
    rules:
      - alert: HighAPIErrorRate
        expr: |
          (sum(rate(http_requests_total{status=~"5.."}[5m])) /
           sum(rate(http_requests_total[5m]))) * 100 > 5
        for: 5m
        labels:
          severity: critical
          component: api
        annotations:
          summary: "High API error rate detected"
          dashboard: "https://grafana.chom.app/d/chom-api-analytics"

  - name: pipeline_alerts
    interval: 30s
    rules:
      - alert: QueueBacklogHigh
        expr: laravel_queue_size > 1000
        for: 10m
        labels:
          severity: warning
          component: queue
        annotations:
          summary: "Queue backlog on {{ $labels.queue }}"
          dashboard: "https://grafana.chom.app/d/chom-data-pipeline"

  - name: tenant_alerts
    interval: 60s
    rules:
      - alert: TenantIsolationViolation
        expr: increase(tenant_isolation_violations_total[5m]) > 0
        for: 1m
        labels:
          severity: critical
          component: security
        annotations:
          summary: "CRITICAL: Tenant isolation violation"
          dashboard: "https://grafana.chom.app/d/chom-tenant-analytics"
```

---

## Query Examples

### API Analytics

```promql
# Top 10 API consumers by request volume (last 24h)
topk(10, sum(increase(http_requests_total{job="chom-api"}[24h])) by (consumer))

# Rate limit consumption percentage
(sum(rate(http_requests_total{job="chom-api"}[5m])) by (tier) /
 on(tier) group_left rate_limit_per_minute) * 100

# API version adoption over time
sum(increase(http_requests_total{job="chom-api"}[1h])) by (api_version)

# Webhook delivery success rate
sum(rate(webhook_deliveries_total{status="success"}[5m])) /
sum(rate(webhook_deliveries_total[5m])) * 100
```

### Data Pipeline

```promql
# Queue processing rate
sum(rate(laravel_queue_jobs_processed_total[5m])) by (queue)

# Job failure rate
(sum(rate(laravel_queue_jobs_processed_total{status="failed"}[15m])) by (queue) /
 sum(rate(laravel_queue_jobs_processed_total[15m])) by (queue)) * 100

# ETL job duration (p95)
histogram_quantile(0.95,
  sum(rate(etl_job_duration_seconds_bucket[5m])) by (le, etl_job)
)

# Data validation error rate
sum(rate(data_validation_errors_total[5m])) by (validation_type, field)
```

### Tenant Analytics

```promql
# Per-tenant CPU usage
sum(rate(container_cpu_usage_seconds_total{tenant!=""}[5m])) by (tenant) * 100

# Storage consumption by tenant
topk(20, tenant_database_size_bytes + tenant_file_storage_bytes)

# Tenant health score
(
  (1 - (sum(rate(http_requests_total{status=~"5.."}[15m])) by (tenant) /
        sum(rate(http_requests_total[15m])) by (tenant))) * 40 +
  (1 - avg(rate(container_cpu_usage_seconds_total[15m])) by (tenant)) * 30 +
  (1 - (avg(container_memory_usage_bytes) by (tenant) /
        avg(container_memory_limit_bytes) by (tenant))) * 30
) * 100

# Tenant churn risk (declining usage)
(sum(rate(http_requests_total[7d])) by (tenant) -
 sum(rate(http_requests_total offset 7d[7d])) by (tenant)) /
 sum(rate(http_requests_total offset 7d[7d])) by (tenant) * 100
```

---

## Troubleshooting

### Dashboard Not Loading

1. Verify Prometheus datasource is configured:
   ```bash
   curl http://grafana.chom.app/api/datasources
   ```

2. Check Prometheus is scraping metrics:
   ```bash
   curl http://prometheus:9090/api/v1/targets
   ```

3. Verify metrics are being exported:
   ```bash
   curl http://chom-api:9090/metrics | grep http_requests_total
   ```

### Missing Data

1. Check metric names match exactly (case-sensitive)
2. Verify labels exist (job, tenant, queue, etc.)
3. Increase time range to ensure data exists
4. Check Prometheus retention period

### Slow Dashboard Performance

1. Reduce time range (use last 6h instead of 30d)
2. Increase query resolution (step interval)
3. Add rate limit to queries:
   ```promql
   rate(http_requests_total[5m])  # Not raw counter values
   ```
4. Use recording rules for complex queries

---

## Best Practices

### Dashboard Design

1. **Organize by Purpose**: Group related panels together
2. **Use Appropriate Visualizations**:
   - Time series: Trends and patterns
   - Gauges: Current status vs threshold
   - Tables: Detailed breakdowns
   - Pie charts: Distribution percentages
3. **Include Context**: Add descriptions to panels
4. **Link to Runbooks**: Include action items in annotations

### Query Optimization

1. **Use Recording Rules** for frequently-used expensive queries
2. **Aggregate Early** in the query pipeline
3. **Use `rate()` not `increase()`** for request rates
4. **Limit Results** with `topk()` or `bottomk()`
5. **Use `by` Clause** to group results efficiently

### Alerting Strategy

1. **Set Appropriate Thresholds**: Based on SLOs and historical data
2. **Use Multi-Window Alerts**: Fast and slow burn rates
3. **Include Actionable Information**: Links to dashboards and runbooks
4. **Avoid Alert Fatigue**: Tune thresholds and durations
5. **Route Alerts by Severity**: Critical to PagerDuty, warning to Slack

---

## Contributing

To add new panels or dashboards:

1. Create panels in Grafana UI
2. Export dashboard JSON
3. Update `README.md` with panel descriptions
4. Add relevant PromQL queries to documentation
5. Test with sample data
6. Submit pull request

---

## Support

For questions or issues:
- Documentation: https://docs.chom.app/monitoring
- Grafana Dashboards: https://grafana.chom.app
- Support: support@chom.app

---

## License

Copyright (c) 2026 CHOM Platform. All rights reserved.
