# CHOM Observability - Complete Index

Quick navigation to all observability components and documentation.

## Documentation

| Document | Description | Words | Link |
|----------|-------------|-------|------|
| OBSERVABILITY.md | Complete setup and usage guide | 7,500 | [View](OBSERVABILITY.md) |
| MONITORING_GUIDE.md | Daily operations and monitoring | 5,000 | [View](MONITORING_GUIDE.md) |
| ALERTING.md | Alert runbooks and procedures | 6,000 | [View](ALERTING.md) |
| OBSERVABILITY-QUICK-REFERENCE.md | Quick commands and examples | 2,000 | [View](OBSERVABILITY-QUICK-REFERENCE.md) |
| OBSERVABILITY-IMPLEMENTATION-SUMMARY.md | Implementation details | 3,500 | [View](OBSERVABILITY-IMPLEMENTATION-SUMMARY.md) |

## Core Services

| Service | Location | Lines | Purpose |
|---------|----------|-------|---------|
| MetricsCollector | app/Services/MetricsCollector.php | 500 | Prometheus metrics collection |
| TracingService | app/Services/TracingService.php | 545 | Distributed tracing |
| StructuredLogger | app/Services/StructuredLogger.php | 410 | JSON structured logging |
| ErrorTracker | app/Services/ErrorTracker.php | 425 | Error capture and tracking |
| PerformanceMonitor | app/Services/PerformanceMonitor.php | 310 | Performance monitoring |

## HTTP Components

| Component | Location | Lines | Purpose |
|-----------|----------|-------|---------|
| PrometheusMetricsMiddleware | app/Http/Middleware/PrometheusMetricsMiddleware.php | 215 | HTTP metrics collection |
| HealthCheckController | app/Http/Controllers/HealthCheckController.php | 360 | Health check endpoints |
| MetricsController | app/Http/Controllers/MetricsController.php | 50 | Metrics export endpoint |

## Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| observability.php | config/observability.php | Main observability configuration |
| alerts.php | config/alerts.php | Alert rules and thresholds |
| health.php | routes/health.php | Health and metrics routes |

## Tests

| Test Suite | Location | Tests | Coverage |
|------------|----------|-------|----------|
| MetricsCollectorTest | tests/Unit/Services/Observability/MetricsCollectorTest.php | 18 | All metric types |
| TracingServiceTest | tests/Unit/Services/Observability/TracingServiceTest.php | 15 | Tracing features |
| PerformanceMonitorTest | tests/Unit/Services/Observability/PerformanceMonitorTest.php | 8 | Performance tracking |

## Grafana Dashboards

| Dashboard | Location | Panels | Purpose |
|-----------|----------|--------|---------|
| System Overview | grafana/dashboards/system-overview.json | 7 | HTTP, errors, latency |
| Database Performance | grafana/dashboards/database-performance.json | 6 | DB queries, connections |
| Business Metrics | grafana/dashboards/business-metrics.json | 9 | VPS, sites, tenants |

## Observability Stack

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Metrics storage and querying |
| Grafana | 3000 | Visualization and dashboards |
| Loki | 3100 | Log aggregation |
| Jaeger | 16686 | Distributed tracing UI |
| AlertManager | 9093 | Alert routing |
| Redis Exporter | 9121 | Redis metrics |
| Node Exporter | 9100 | System metrics |

## Stack Configuration

| File | Location | Purpose |
|------|----------|---------|
| Docker Compose | observability-stack/docker-compose.yml | Service definitions |
| Prometheus Config | observability-stack/prometheus/prometheus.yml | Scrape configuration |
| Recording Rules | observability-stack/prometheus/recording-rules.yml | Metric aggregations |
| Alerting Rules | observability-stack/prometheus/alerting-rules.yml | Alert definitions |
| Loki Config | observability-stack/loki/loki-config.yml | Log storage config |
| Promtail Config | observability-stack/promtail/promtail-config.yml | Log collection |
| AlertManager Config | observability-stack/alertmanager/alertmanager.yml | Alert routing |
| Datasources | observability-stack/grafana/provisioning/datasources/datasources.yml | Auto-provisioning |
| Dashboards | observability-stack/grafana/provisioning/dashboards/dashboards.yml | Dashboard loading |

## Quick Access URLs

```
Grafana:       http://localhost:3000       (admin/admin)
Prometheus:    http://localhost:9090
Jaeger:        http://localhost:16686
AlertManager:  http://localhost:9093
Metrics:       http://localhost:8000/metrics
Health:        http://localhost:8000/health/detailed
```

## Key Metrics

### HTTP Metrics
- `chom_laravel_http_requests_total` - Request count
- `chom_laravel_http_request_duration_seconds` - Response time
- `chom_laravel_http_requests_errors_total` - Error count
- `chom_laravel_http_requests_active` - Active requests

### Database Metrics
- `chom_laravel_db_queries_total` - Query count
- `chom_laravel_db_query_duration_seconds` - Query duration
- `chom_laravel_db_queries_slow_total` - Slow query count

### Queue Metrics
- `chom_laravel_queue_jobs_total` - Job count
- `chom_laravel_queue_job_duration_seconds` - Job duration
- `chom_laravel_queue_jobs_failed_total` - Failed jobs

### Business Metrics
- `chom_laravel_site_provisioning_total` - Site provisioning
- `chom_laravel_vps_operations_total` - VPS operations
- `chom_laravel_tenant_sites_count` - Tenant sites
- `chom_laravel_tenant_storage_gb` - Tenant storage

## Alert Rules

### Critical (7)
1. HighErrorRate - >1% error rate
2. CriticalErrorRate - >5% error rate
3. VerySlowResponseTime - >2s response time
4. DatabaseUnavailable - DB health check failed
5. VpsOperationFailures - >5% VPS failures
6. SiteProvisioningFailures - >10% provisioning failures
7. RedisUnavailable - Redis health check failed

### Warning (9)
1. SlowResponseTime - >500ms response time
2. SlowDatabaseQueries - >100ms query time
3. HighJobFailureRate - >5% job failures
4. LowCacheHitRate - <50% cache hit rate
5. HighMemoryUsage - >85% memory
6. HighCPUUsage - >80% CPU
7. LowDiskSpace - <10% free space
8. CriticalDiskSpace - <5% free space
9. DatabaseConnectionPoolHigh - >90% pool usage

## Common Commands

### Start Stack
```bash
cd observability-stack && docker-compose up -d
```

### Check Health
```bash
curl http://localhost:8000/health/detailed | jq
```

### View Metrics
```bash
curl http://localhost:8000/metrics
```

### Query Prometheus
```bash
curl 'http://localhost:9090/api/v1/query?query=chom:http:error_rate'
```

### View Logs
```bash
docker-compose -f observability-stack/docker-compose.yml logs -f
```

## Integration Checklist

- [ ] Configure environment variables in .env
- [ ] Start observability stack
- [ ] Register PrometheusMetricsMiddleware
- [ ] Start PerformanceMonitor in AppServiceProvider
- [ ] Configure alert email recipients
- [ ] Set up Slack webhook
- [ ] Test metrics endpoint
- [ ] Test health checks
- [ ] Verify Grafana dashboards loaded
- [ ] Test alert routing

## Next Steps

1. **Configuration**: Edit observability-stack/.env with your settings
2. **Start Stack**: `cd observability-stack && docker-compose up -d`
3. **Access Grafana**: http://localhost:3000 (admin/admin)
4. **Review Dashboards**: Check System Overview dashboard
5. **Test Alerts**: Trigger a test alert to verify routing
6. **Production Deploy**: Follow observability-stack/README.md

## Support

- **Issues**: Check troubleshooting sections in documentation
- **Examples**: See OBSERVABILITY-QUICK-REFERENCE.md
- **Runbooks**: See ALERTING.md for detailed procedures
- **Operations**: See MONITORING_GUIDE.md for daily tasks

---

**Last Updated**: January 3, 2026
**Status**: Production Ready ✅
