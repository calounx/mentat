# CHOM Data & API Analytics Dashboards - Index

## Quick Navigation

| Document | Purpose | Audience | Size |
|----------|---------|----------|------|
| [QUICK-REFERENCE.md](#quick-reference) | Fast lookup for common tasks | Operators, On-call | 12 KB |
| [README.md](#readme) | Complete dashboard documentation | Developers, SREs | 16 KB |
| [API-USAGE-OPTIMIZATION-GUIDE.md](#optimization-guide) | Performance and cost optimization | Data Engineers, Architects | 32 KB |
| [IMPLEMENTATION-SUMMARY.md](#implementation-summary) | Technical implementation details | Engineers, Product | 24 KB |

## Dashboards

| Dashboard | Panels | Use Case | File | Size |
|-----------|--------|----------|------|------|
| **6. API Analytics** | 12 | API performance, rate limiting, webhooks | 6-api-analytics.json | 28 KB |
| **7. Data Pipeline** | 13 | Queue processing, ETL, batch operations | 7-data-pipeline.json | 32 KB |
| **8. Tenant Analytics** | 12 | Multi-tenancy, billing, churn risk | 8-tenant-analytics.json | 40 KB |

**Total:** 37 panels, 100 KB

---

## Quick Reference

**File:** `QUICK-REFERENCE.md` (12 KB)

One-page reference for:
- Common investigation workflows
- Key metric thresholds
- Essential PromQL queries
- Alert response playbooks
- Dashboard variables guide
- Cost attribution formulas

**Use when:** You need to quickly investigate an incident or check a specific metric.

**Key sections:**
1. Dashboard URLs and access
2. Common investigation patterns (5 scenarios)
3. Metric thresholds (warning/critical)
4. PromQL quick queries (15+ examples)
5. Alert response playbooks (4 critical alerts)
6. Dashboard variables guide
7. Time range recommendations
8. Integration points (Alertmanager, Slack)

**Start here for:** Real-time troubleshooting

---

## README

**File:** `README.md` (16 KB)

Comprehensive dashboard documentation including:
- Panel-by-panel descriptions
- Installation instructions
- Metrics requirements (60+ metrics)
- Alert configuration examples
- Query examples
- Troubleshooting guide

**Use when:** Setting up dashboards or learning what metrics are tracked.

**Key sections:**
1. Dashboard overviews (6, 7, 8)
2. Key panels and use cases
3. Installation guide (Grafana import)
4. Metrics requirements (detailed list)
5. Implementing metrics in Laravel
6. Alert configuration (Prometheus rules)
7. Query examples (API, pipeline, tenant)
8. Troubleshooting (missing data, slow performance)
9. Best practices (design, queries, alerts)

**Start here for:** Initial setup and configuration

---

## Optimization Guide

**File:** `API-USAGE-OPTIMIZATION-GUIDE.md` (32 KB)

850+ line comprehensive guide covering:

### 1. API Performance Optimization (150 lines)
- Rate limiting strategies
  - Tiered limits (free: 100/min, pro: 500/min, enterprise: 2000/min)
  - Token bucket algorithm
  - Rate limit headers and graceful degradation
- Response optimization
  - Field selection (sparse fieldsets)
  - Compression (gzip/brotli, 70-90% reduction)
  - Pagination (25-100 items/page)
- Caching strategies
  - HTTP cache headers (max-age, ETag)
  - Application-level caching (Laravel Cache)
  - CDN for static resources
- API version management
  - Deprecation timeline (90d notice, 180d sunset)
  - Version headers and migration guides

### 2. Data Pipeline Best Practices (200 lines)
- Queue architecture
  - Prioritization (high/default/low/batch)
  - Laravel Horizon configuration
- Job optimization
  - Idempotent operations (safe retries)
  - Chunked processing (batch 100 records)
  - Job batching (parallel execution)
- ETL pipeline patterns
  - Incremental processing (last processed timestamp)
  - Schema-on-write vs schema-on-read
  - CHOM recommendation: Write for core entities, read for logs
- Data quality checks
  - Validation pipeline with error tracking
  - Data quality metrics (error rate, freshness, completeness)

### 3. Multi-Tenant Optimization (150 lines)
- Tenant isolation strategies
  - Schema-based (CHOM uses this) - Strong isolation, simple backups
  - Row-level - Unlimited tenants, data leakage risk
  - Database-per-tenant - Perfect isolation, high overhead
- CHOM implementation
  - Middleware to set tenant context
  - Cross-tenant query prevention
  - Isolation violation monitoring
- Resource fair-sharing
  - CPU and memory limits (Kubernetes quotas)
  - Database connection pooling
  - Rate limiting per tenant

### 4. Capacity Planning (100 lines)
- Resource forecasting
  - CPU/memory growth (linear regression)
  - Storage growth (GB per week)
  - API request growth (month-over-month)
- Scaling thresholds
  - Horizontal Pod Autoscaling (70% CPU, 80% memory)
  - Database scaling (read replicas, partitioning)
  - Queue worker scaling (based on wait time, depth, failure rate)
- Cost optimization
  - Right-sizing resources
  - Storage optimization (archive, compress, cleanup)

### 5. Usage-Based Billing (80 lines)
- Metering strategy
  - Real-time usage recording
  - Billable metrics (API requests, storage, VPS hours, data transfer)
- Pricing models
  - API: $0.001 per request (over included)
  - Storage: $0.10 per GB/month
  - VPS: $5 per VPS/month
  - Data transfer: $0.05 per GB outbound
- Monthly billing calculation
  - Usage aggregation
  - Tier-based pricing
  - MRR tracking

### 6. Monitoring and Alerting (120 lines)
- Critical alerts
  - API health (error rate, latency, rate limits)
  - Data pipeline (queue backlog, job failures, ETL stalls)
  - Tenant security (isolation violations, resource exhaustion)
- SLO-based alerts
  - Service Level Objectives (99.9% availability, 200ms p95 latency)
  - Error budget burn rates (fast: 2%/hour, slow: 10%/6h)

### 7. Cost Optimization (50 lines)
- Infrastructure cost analysis
  - Cost attribution by tenant
  - Compute, storage, network costs
- Optimization opportunities
  - Spot instances (60-90% savings)
  - Reserved instances (30-50% savings)
  - Auto-scaling and lifecycle management

**Use when:** Optimizing performance, reducing costs, or planning capacity.

**Start here for:** Strategic planning and optimization

---

## Implementation Summary

**File:** `IMPLEMENTATION-SUMMARY.md` (24 KB)

Technical implementation documentation covering:

### Dashboard Specifications
- **API Analytics (Dashboard 6)**
  - 12 panels detailed specifications
  - Queries, visualizations, thresholds
  - Variables: $tier, $endpoint

- **Data Pipeline (Dashboard 7)**
  - 13 panels detailed specifications
  - Queue, ETL, batch processing metrics
  - Variables: $queue, $etl_job

- **Tenant Analytics (Dashboard 8)**
  - 12 panels detailed specifications
  - Multi-tenancy, billing, isolation metrics
  - Variables: $tenant, $tier

### Technical Architecture
- Data engineering principles
  - Schema-on-write for structured metrics
  - Incremental processing patterns
  - Data quality and validation
- Multi-tenancy patterns
  - Schema-based isolation
  - Resource fair-sharing
  - Usage metering
- Monitoring strategy
  - RED metrics (Requests, Errors, Duration)
  - USE metrics (Utilization, Saturation, Errors)
  - Business metrics (growth, churn, revenue)

### Metrics Implementation
- 60+ required metrics detailed
- Laravel implementation examples
- Prometheus configuration
- Custom business metrics

### Alert Rules
- Critical alerts (API, pipeline, tenant)
- SLO alerts (error budget)
- Alert severity and routing

### Usage Scenarios
1. API performance degradation
2. Queue backlog investigation
3. Tenant churn risk detection
4. (Detailed investigation workflows)

### Performance Considerations
- Query optimization (recording rules)
- Dashboard load time (<10s)
- Storage requirements (~500 MB/day)

### Future Enhancements
- Predictive analytics (ML forecasting)
- Cost attribution dashboard
- Real-time alerting dashboard
- Data lineage visualization

**Use when:** Understanding implementation details or planning extensions.

**Start here for:** Technical deep-dive

---

## Dashboard Files

### 6. API Analytics (`6-api-analytics.json`)

**UID:** `chom-api-analytics`
**Panels:** 12
**Size:** 28 KB

**Tracks:**
- API request rates and patterns
- Rate limit consumption by tier
- API version adoption and deprecation
- Error distribution and analysis
- Response payload optimization
- Webhook delivery reliability
- Consumer behavior and abuse detection
- API key lifecycle management

**Key queries:**
```promql
# Request rate by endpoint
sum(rate(http_requests_total{job="chom-api"}[5m])) by (endpoint)

# Rate limit consumption
(sum(rate(http_requests_total[5m])) by (tier) / rate_limit_per_minute) * 100

# Webhook success rate
sum(rate(webhook_deliveries_total{status="success"}[5m])) / sum(rate(webhook_deliveries_total[5m]))
```

**Variables:**
- `$tier`: free, pro, enterprise, all
- `$endpoint`: Dynamic list from metrics

**Refresh:** 30 seconds
**Time range:** Default 6 hours

---

### 7. Data Pipeline (`7-data-pipeline.json`)

**UID:** `chom-data-pipeline`
**Panels:** 13
**Size:** 32 KB

**Tracks:**
- Queue job processing and backlog
- Background job success/failure rates
- Data import/export volumes
- ETL job performance and duration
- Data validation and quality errors
- Transformation latency
- Scheduled job execution status
- Batch processing throughput
- Queue wait times and capacity

**Key queries:**
```promql
# Queue processing rate
sum(rate(laravel_queue_jobs_processed_total[5m])) by (queue)

# Job failure rate
(sum(rate(laravel_queue_jobs_processed_total{status="failed"}[15m])) /
 sum(rate(laravel_queue_jobs_processed_total[15m]))) * 100

# ETL job duration (p95)
histogram_quantile(0.95, sum(rate(etl_job_duration_seconds_bucket[5m])) by (le, etl_job))
```

**Variables:**
- `$queue`: high-priority, default, low-priority, batch, all
- `$etl_job`: Dynamic list from metrics

**Refresh:** 30 seconds
**Time range:** Default 6 hours

---

### 8. Tenant Analytics (`8-tenant-analytics.json`)

**UID:** `chom-tenant-analytics`
**Panels:** 12
**Size:** 40 KB

**Tracks:**
- Per-tenant resource usage (CPU, memory)
- Tenant growth and activity trends
- Storage consumption and growth
- API usage by tenant
- Feature adoption rates
- Tenant health scoring
- Multi-tenancy isolation verification
- Cross-tenant performance comparison
- Usage-based billing (MRR)
- Capacity planning metrics
- Tenant churn risk indicators

**Key queries:**
```promql
# Per-tenant CPU usage
sum(rate(container_cpu_usage_seconds_total{tenant!=""}[5m])) by (tenant) * 100

# Tenant health score
(
  (1 - (sum(rate(http_requests_total{status=~"5.."}[15m])) by (tenant) /
        sum(rate(http_requests_total[15m])) by (tenant))) * 40 +
  (1 - avg(rate(container_cpu_usage_seconds_total[15m])) by (tenant)) * 30 +
  (1 - (avg(container_memory_usage_bytes) by (tenant) /
        avg(container_memory_limit_bytes) by (tenant))) * 30
) * 100

# Isolation violations
sum(increase(tenant_isolation_violations_total[1h])) by (violation_type)
```

**Variables:**
- `$tenant`: Dynamic list of all tenants
- `$tier`: free, pro, enterprise, all

**Refresh:** 30 seconds
**Time range:** Default 6 hours

---

## Metrics Taxonomy

### HTTP Metrics
```
http_requests_total{job, endpoint, consumer, tier, api_version, status, deprecated}
http_request_duration_seconds_bucket{job, endpoint}
http_response_size_bytes_bucket{job, endpoint}
```

### Queue Metrics
```
laravel_queue_jobs_processed_total{job, queue, status, job_type}
laravel_queue_size{job, queue}
laravel_queue_wait_seconds_bucket{job, queue}
laravel_queue_job_retries_total{job, retry_count}
```

### Data Pipeline Metrics
```
data_import_records_total{job, source}
data_export_records_total{job, destination}
etl_job_duration_seconds_bucket{job, etl_job}
data_validation_errors_total{job, validation_type, field}
data_transformation_duration_seconds_bucket{job, transformation}
scheduled_job_last_run_timestamp_seconds{job, job_name}
scheduled_job_last_duration_seconds{job, job_name}
batch_processing_records_total{job, batch_type}
```

### Tenant Metrics
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

### Webhook Metrics
```
webhook_deliveries_total{job, status}
api_key_last_used{job, tier}
```

**Total metrics:** 60+
**Label cardinality:** ~1000 time series per tenant

---

## Getting Started

### 1. First-Time Setup (15 minutes)

```bash
# 1. Import dashboards to Grafana
cd /home/calounx/repositories/mentat/deploy/grafana-dashboards/data
for dash in 6-api-analytics.json 7-data-pipeline.json 8-tenant-analytics.json; do
  curl -X POST http://grafana:3000/api/dashboards/db \
    -H "Authorization: Bearer $GRAFANA_API_KEY" \
    -H "Content-Type: application/json" \
    -d @$dash
done

# 2. Verify Prometheus datasource
curl http://grafana:3000/api/datasources

# 3. Check metrics are being scraped
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets'

# 4. Test dashboard loads
open http://grafana.chom.app/d/chom-api-analytics
```

### 2. Daily Operations (5 minutes)

```bash
# Morning routine
1. Open API Analytics dashboard
2. Check error rate and latency
3. Review rate limit consumption
4. Open Data Pipeline dashboard
5. Check queue depths and job failures
6. Open Tenant Analytics dashboard
7. Verify no isolation violations
8. Review tenant health scores
```

### 3. Incident Response (Real-time)

```bash
# Use QUICK-REFERENCE.md
1. Identify alert type
2. Follow playbook steps
3. Use dashboard to investigate
4. Review logs and metrics
5. Implement fix
6. Verify resolution in dashboard
```

### 4. Capacity Planning (Monthly)

```bash
# Use OPTIMIZATION-GUIDE.md
1. Review tenant growth trends
2. Analyze storage growth rates
3. Check API request patterns
4. Forecast resource needs
5. Plan infrastructure scaling
6. Estimate costs
```

---

## Implementation Checklist

### Pre-Deployment
- [x] Create dashboard JSON files
- [x] Validate JSON syntax
- [x] Write comprehensive documentation
- [x] Define required metrics (60+)
- [x] Write alert rules
- [x] Create quick reference guide

### Deployment
- [ ] Import dashboards to Grafana
- [ ] Configure Prometheus datasource
- [ ] Verify dashboard rendering
- [ ] Test variables and filters
- [ ] Configure alert routing

### Application Changes
- [ ] Implement HTTP metrics middleware
- [ ] Add queue job metrics
- [ ] Implement ETL job tracking
- [ ] Add tenant isolation monitoring
- [ ] Implement usage metering
- [ ] Add webhook delivery tracking

### Operational Readiness
- [ ] Train team on dashboards
- [ ] Document runbooks
- [ ] Set up alert channels (Slack, PagerDuty)
- [ ] Define SLOs and error budgets
- [ ] Create on-call rotation
- [ ] Schedule capacity planning reviews

---

## Support and Resources

### Documentation
- Quick Reference: `QUICK-REFERENCE.md`
- Full README: `README.md`
- Optimization Guide: `API-USAGE-OPTIMIZATION-GUIDE.md`
- Implementation Details: `IMPLEMENTATION-SUMMARY.md`

### Dashboards
- API Analytics: `6-api-analytics.json`
- Data Pipeline: `7-data-pipeline.json`
- Tenant Analytics: `8-tenant-analytics.json`

### External Resources
- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- Laravel Horizon: https://laravel.com/docs/horizon
- PromQL: https://prometheus.io/docs/prometheus/latest/querying/basics/

### Contact
- Support: support@chom.app
- Monitoring Team: #monitoring-alerts (Slack)
- On-Call: PagerDuty escalation

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-01-02 | Initial release | Data Engineering Team |

---

## License

Copyright (c) 2026 CHOM Platform. All rights reserved.

---

**Total Package Size:** 188 KB
**Files:** 7 (3 dashboards + 4 documentation)
**Panels:** 37
**Metrics:** 60+
**Documentation:** 1200+ lines

**Status:** Ready for deployment
