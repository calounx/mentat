# CHOM Data & API Analytics - Quick Reference

## Dashboard URLs

```
Dashboard 6: https://grafana.chom.app/d/chom-api-analytics
Dashboard 7: https://grafana.chom.app/d/chom-data-pipeline
Dashboard 8: https://grafana.chom.app/d/chom-tenant-analytics
```

---

## Common Investigations

### API Performance Issue

```
1. Open: Dashboard 6 (API Analytics)
2. Check: API Response Time panel (bottom)
3. Check: API Error Distribution
4. Filter: Use $endpoint variable to isolate problem
5. Action: Review optimization guide Section 1
```

### Queue Backlog

```
1. Open: Dashboard 7 (Data Pipeline)
2. Check: Queue Depth panel
3. Check: Top Failed Jobs table
4. Check: Queue Wait Time
5. Action: Scale workers or fix failing jobs
```

### Tenant Isolation Violation

```
1. Open: Dashboard 8 (Tenant Analytics)
2. Check: Multi-Tenancy Isolation panel
3. CRITICAL: Any value > 0 is a security issue
4. Action: Review logs immediately, follow security runbook
```

### High API Error Rate

```
1. Open: Dashboard 6 (API Analytics)
2. Check: API Error Distribution panel
3. Filter: By endpoint or consumer
4. Check: Top API Consumers table
5. Action: Fix application errors or block abusive consumers
```

### Tenant Churn Risk

```
1. Open: Dashboard 8 (Tenant Analytics)
2. Check: Tenant Churn Risk Indicators table
3. Check: Feature Usage by Tenant
4. Check: Tenant Health Scores
5. Action: Proactive outreach, investigate performance
```

---

## Key Metrics Thresholds

### API (Dashboard 6)

| Metric | Warning | Critical |
|--------|---------|----------|
| Error Rate | > 1% | > 5% |
| Response Time (p95) | > 200ms | > 500ms |
| Rate Limit Usage | > 80% | > 95% |
| Deprecated Endpoint Usage | > 10 req/s | > 100 req/s |

### Data Pipeline (Dashboard 7)

| Metric | Warning | Critical |
|--------|---------|----------|
| Queue Depth | > 500 jobs | > 1000 jobs |
| Job Failure Rate | > 5% | > 10% |
| Queue Wait Time (p95) | > 30s | > 120s |
| ETL Duration | > 2 min | > 5 min |
| Pipeline Health | < 95% | < 90% |

### Tenant Analytics (Dashboard 8)

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU Usage | > 70% | > 90% |
| Memory Usage | > 80% | > 95% |
| Tenant Health Score | < 85 | < 70 |
| Isolation Violations | ANY | ANY |
| Storage Growth | > 100% week | > 200% week |

---

## Quick PromQL Queries

### API Metrics

```promql
# Current request rate
sum(rate(http_requests_total{job="chom-api"}[5m]))

# Error rate percentage
(sum(rate(http_requests_total{status=~"5.."}[5m])) /
 sum(rate(http_requests_total[5m]))) * 100

# Top endpoints by traffic
topk(10, sum(rate(http_requests_total[5m])) by (endpoint))

# Rate limit usage
(sum(rate(http_requests_total[5m])) by (tier) /
 on(tier) group_left rate_limit_per_minute) * 100
```

### Queue Metrics

```promql
# Current queue depth
laravel_queue_size

# Job processing rate
sum(rate(laravel_queue_jobs_processed_total[5m])) by (queue)

# Job failure rate
(sum(rate(laravel_queue_jobs_processed_total{status="failed"}[15m])) /
 sum(rate(laravel_queue_jobs_processed_total[15m]))) * 100

# Queue wait time (p95)
histogram_quantile(0.95,
  sum(rate(laravel_queue_wait_seconds_bucket[5m])) by (le, queue)
)
```

### Tenant Metrics

```promql
# Tenant CPU usage
sum(rate(container_cpu_usage_seconds_total{tenant!=""}[5m])) by (tenant) * 100

# Tenant storage total
tenant_database_size_bytes + tenant_file_storage_bytes

# Tenant health score
(
  (1 - (sum(rate(http_requests_total{status=~"5.."}[15m])) by (tenant) /
        sum(rate(http_requests_total[15m])) by (tenant))) * 40 +
  (1 - avg(rate(container_cpu_usage_seconds_total[15m])) by (tenant)) * 30 +
  (1 - (avg(container_memory_usage_bytes) by (tenant) /
        avg(container_memory_limit_bytes) by (tenant))) * 30
) * 100

# Active tenants (24h)
count(count by (tenant) (rate(http_requests_total[24h]) > 0))
```

---

## Alert Response Playbook

### HighAPIErrorRate (Critical)

1. **Check:** Dashboard 6 - API Error Distribution
2. **Identify:** Which endpoint(s) are failing
3. **Review:** Application logs for errors
4. **Action:**
   - If database: Check DB connection pool
   - If external service: Check third-party status
   - If application bug: Deploy hotfix
5. **Communicate:** Update status page

### QueueBacklogHigh (Warning)

1. **Check:** Dashboard 7 - Queue Depth
2. **Identify:** Which queue(s) are backed up
3. **Review:** Top Failed Jobs table
4. **Action:**
   - If capacity issue: Scale workers
   - If failing jobs: Fix and redeploy
   - If data issue: Clear invalid jobs
5. **Monitor:** Wait time returns to normal

### TenantIsolationViolation (Critical)

1. **STOP:** Potential security incident
2. **Check:** Dashboard 8 - Isolation panel
3. **Identify:** Violation type and affected tenants
4. **Action:**
   - Immediately review application logs
   - Check database query logs
   - Verify middleware configuration
   - Escalate to security team
5. **Remediate:** Fix vulnerability, notify affected tenants if needed

### TenantResourceExhaustion (Warning)

1. **Check:** Dashboard 8 - Per-Tenant Resource Usage
2. **Identify:** Which tenant(s) are affected
3. **Review:** Feature usage and API calls
4. **Action:**
   - Contact tenant about upgrade
   - Review for abuse or misconfiguration
   - Adjust resource limits if appropriate
5. **Monitor:** Resource usage trends

---

## Dashboard Variables Guide

### API Analytics Variables

**$tier**
- Values: free, pro, enterprise, all
- Usage: Filter API metrics by customer tier
- Example: Compare rate limit usage across tiers

**$endpoint**
- Values: All API endpoints
- Usage: Focus on specific endpoint performance
- Example: Investigate slow /api/v1/vps endpoint

### Data Pipeline Variables

**$queue**
- Values: high-priority, default, low-priority, batch
- Usage: Filter queue metrics by priority
- Example: Monitor high-priority queue separately

**$etl_job**
- Values: All ETL job names
- Usage: Focus on specific ETL job performance
- Example: Optimize slow ImportSitesJob

### Tenant Analytics Variables

**$tenant**
- Values: All tenant IDs
- Usage: Focus on specific tenant(s)
- Example: Investigate resource usage for tenant_abc123

**$tier**
- Values: free, pro, enterprise
- Usage: Compare metrics across customer tiers
- Example: Analyze feature adoption by tier

---

## Time Range Recommendations

| Investigation | Time Range | Reason |
|---------------|------------|--------|
| Real-time incident | Last 15 minutes | Immediate impact |
| Performance issue | Last 1 hour | Pattern identification |
| Daily operations | Last 6 hours | Normal monitoring |
| Trend analysis | Last 7 days | Week-over-week comparison |
| Capacity planning | Last 30 days | Monthly trends |
| Billing period | Last month | Usage-based billing |

---

## Data Retention

| Metric Type | Retention | Resolution |
|-------------|-----------|------------|
| Raw metrics | 15 days | 15 seconds |
| 5m aggregates | 90 days | 5 minutes |
| 1h aggregates | 1 year | 1 hour |
| Long-term (Thanos) | 2 years | 1 hour |

---

## Integration Points

### Alertmanager

```yaml
route:
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: pagerduty
    - match:
        severity: warning
      receiver: slack
    - match:
        component: security
      receiver: security-team

receivers:
  - name: pagerduty
    pagerduty_configs:
      - service_key: '<key>'
  - name: slack
    slack_configs:
      - api_url: '<webhook>'
        channel: '#alerts'
```

### Slack Commands

```
/grafana api-analytics          # Open API dashboard
/grafana data-pipeline          # Open pipeline dashboard
/grafana tenant tenant_abc123   # Open tenant view
/grafana alert list             # List active alerts
```

### API Endpoints

```bash
# Get current metrics
curl http://chom-api:9090/metrics

# Query Prometheus
curl 'http://prometheus:9090/api/v1/query?query=http_requests_total'

# Render dashboard snapshot
curl -X POST http://grafana:3000/api/snapshots \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"dashboard": {...}}'
```

---

## Cost Attribution Formula

```python
# Monthly cost per tenant
def calculate_tenant_cost(tenant_id, month):
    # Compute cost (CPU + Memory)
    cpu_hours = query(f"sum(container_cpu_usage_seconds_total{{tenant='{tenant_id}'}}[{month}]) / 3600")
    memory_gb_hours = query(f"avg_over_time(container_memory_usage_bytes{{tenant='{tenant_id}'}}[{month}]) / 1073741824")

    compute_cost = (cpu_hours * 0.05) + (memory_gb_hours * 0.01)

    # Storage cost
    storage_gb = query(f"avg_over_time((tenant_database_size_bytes + tenant_file_storage_bytes){{tenant='{tenant_id}'}}[{month}]) / 1073741824")
    storage_cost = storage_gb * 0.10

    # Network cost (egress)
    network_gb = query(f"sum(http_response_size_bytes{{tenant='{tenant_id}'}}[{month}]) / 1073741824")
    network_cost = network_gb * 0.05

    return {
        'compute': compute_cost,
        'storage': storage_cost,
        'network': network_cost,
        'total': compute_cost + storage_cost + network_cost
    }
```

---

## Optimization Priorities

### Week 1: Quick Wins
1. Enable HTTP/2 (free, +30% throughput)
2. Add response compression (free, -70% bandwidth)
3. Implement field selection (free, -60% payload)

### Week 2: Caching
1. Enable Redis for hot data (+$50/mo, +80% response time)
2. Add HTTP cache headers (free)
3. CDN for static content (+$100/mo if > 1TB transfer)

### Month 1: Scaling
1. Read replicas when read > 80% (+$200/mo, +50% read throughput)
2. Queue worker auto-scaling (variable cost)
3. Database connection pooling (free, better utilization)

### Quarter 1: Infrastructure
1. Multi-AZ deployment (high availability, +100% cost)
2. Kubernetes autoscaling (efficiency improvement)
3. Spot instances for batch workloads (-60% cost)

---

## Support Resources

**Documentation:**
- Full Guide: `/deploy/grafana-dashboards/data/API-USAGE-OPTIMIZATION-GUIDE.md`
- README: `/deploy/grafana-dashboards/data/README.md`
- Summary: `/deploy/grafana-dashboards/data/IMPLEMENTATION-SUMMARY.md`

**Dashboards:**
- API Analytics: `6-api-analytics.json`
- Data Pipeline: `7-data-pipeline.json`
- Tenant Analytics: `8-tenant-analytics.json`

**External:**
- Prometheus Docs: https://prometheus.io/docs/
- Grafana Docs: https://grafana.com/docs/
- Laravel Horizon: https://laravel.com/docs/horizon

**Support:**
- Email: support@chom.app
- Slack: #monitoring-alerts
- On-call: PagerDuty escalation

---

**Last Updated:** 2026-01-02
**Version:** 1.0
**Owner:** Data Engineering Team
