# CHOM Observability - Quick Reference

Fast reference for common observability tasks.

## Quick Access URLs

| Service | URL | Login |
|---------|-----|-------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger | http://localhost:16686 | - |
| AlertManager | http://localhost:9093 | - |
| Metrics | http://localhost:8000/metrics | IP whitelisted |
| Health | http://localhost:8000/health/detailed | IP whitelisted |

## Common Commands

### Start/Stop Observability Stack
```bash
cd observability-stack

# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# Restart specific service
docker-compose restart prometheus

# View logs
docker-compose logs -f grafana
```

### Check Application Health
```bash
# Basic health
curl http://localhost:8000/health

# Detailed health (IP whitelisted)
curl http://localhost:8000/health/detailed | jq

# Metrics
curl http://localhost:8000/metrics
```

### Query Prometheus
```bash
# Current error rate
curl 'http://localhost:9090/api/v1/query?query=chom:http:error_rate'

# Request rate
curl 'http://localhost:9090/api/v1/query?query=chom:http:request_rate'

# Top slow endpoints
curl 'http://localhost:9090/api/v1/query?query=topk(10,chom:http:request_duration_p95_by_route)'
```

## Using Services in Code

### Metrics Collection
```php
use App\Services\MetricsCollector;

// Inject in constructor
public function __construct(private MetricsCollector $metrics) {}

// Counter
$this->metrics->incrementCounter('operations_total', ['type' => 'important']);

// Gauge
$this->metrics->setGauge('active_users', 42);

// Histogram
$this->metrics->observeHistogram('operation_duration', $duration);
```

### Distributed Tracing
```php
use App\Services\TracingService;

public function __construct(private TracingService $tracing) {}

// Start span
$spanId = $this->tracing->startSpan('database.query', ['table' => 'users']);

// Add tags
$this->tracing->addTag('rows', 100);

// Finish span
$this->tracing->finishSpan($spanId);
```

### Structured Logging
```php
use App\Services\StructuredLogger;

public function __construct(private StructuredLogger $logger) {}

// Log with context
$this->logger->info('User registered', ['user_id' => 123]);

// Performance log
$this->logger->performance('api.call', $duration);

// Business event
$this->logger->businessEvent('subscription_created', ['plan' => 'pro']);
```

### Error Tracking
```php
use App\Services\ErrorTracker;

public function __construct(private ErrorTracker $errorTracker) {}

try {
    // risky operation
} catch (\Exception $e) {
    $this->errorTracker->captureException($e, ['extra' => 'context']);
    throw $e;
}
```

### Performance Monitoring
```php
use App\Services\PerformanceMonitor;

public function __construct(private PerformanceMonitor $monitor) {}

// Track operation
$opId = $this->monitor->startOperation('complex_calculation');
// ... do work ...
$this->monitor->finishOperation($opId);

// Track callable
$result = $this->monitor->track('api_call', fn() => $this->callApi());
```

## Environment Variables

### Essential Configuration
```bash
# Enable observability
OBSERVABILITY_ENABLED=true
METRICS_ENABLED=true
TRACING_ENABLED=true

# Metrics
METRICS_ENDPOINT_PATH=/metrics
METRICS_IP_WHITELIST=127.0.0.1,::1

# Tracing
TRACING_DRIVER=jaeger
JAEGER_AGENT_HOST=localhost
JAEGER_AGENT_PORT=6831

# Health Checks
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_IP_WHITELIST=127.0.0.1,::1
```

## Dashboard Navigation

### System Overview
**Path**: Grafana → Dashboards → CHOM → System Overview

**Key Metrics**:
- Request Rate: Should be steady
- Error Rate: Should be <1%
- Response Time p95: Should be <500ms
- Cache Hit Rate: Should be >70%

### Database Performance
**Path**: Grafana → Dashboards → CHOM → Database Performance

**Key Metrics**:
- Query Duration p95: Should be <100ms
- Slow Query Rate: Should be minimal
- Connection Pool: Should be <80%

### Business Metrics
**Path**: Grafana → Dashboards → CHOM → Business Metrics

**Key Metrics**:
- Site Provisioning Success: Should be >90%
- Queue Job Success: Should be >95%
- Tenant Resource Usage: Monitor trends

## Alert Response

### Critical Alert Received
1. Acknowledge in AlertManager: http://localhost:9093
2. Check relevant Grafana dashboard
3. Review logs: Grafana → Explore → Loki
4. Check traces if needed: Jaeger
5. Follow runbook in ALERTING.md

### Common Alert Quick Fixes

**High Error Rate**
```bash
# Check recent deployments
git log --oneline -10

# Check application logs
docker-compose logs app | grep ERROR

# Rollback if needed
git revert HEAD && deploy
```

**Slow Response Time**
```bash
# Check slow queries
curl 'http://localhost:9090/api/v1/query?query=chom:db:slow_query_rate'

# Check system load
htop
```

**Queue Backlog**
```bash
# Check queue size
php artisan queue:monitor

# Scale workers
php artisan queue:work --workers=10
```

## Prometheus Query Examples

### Error Rate
```promql
# Current error rate
chom:http:error_rate

# Error rate by route
sum(rate(chom_laravel_http_requests_errors_total[5m])) by (route)
```

### Response Time
```promql
# p95 response time
chom:http:request_duration_p95

# p95 by route
histogram_quantile(0.95,
  sum(rate(chom_laravel_http_request_duration_seconds_bucket[5m]))
  by (le, route)
)
```

### Database Performance
```promql
# Slow query rate
chom:db:slow_query_rate

# Query duration p95
chom:db:query_duration_p95
```

### Queue Performance
```promql
# Job failure rate
chom:queue:failure_rate

# Job rate by job type
chom:queue:job_rate_by_job
```

## Log Queries (Loki)

### Error Logs
```logql
{app="chom"} |= "error" | json
```

### Logs by User
```logql
{app="chom"} | json | user_id="123"
```

### Slow Requests
```logql
{app="chom"} | json | duration_ms > 500
```

### Security Events
```logql
{app="chom"} | json | event_type="security"
```

## Troubleshooting

### Metrics Not Appearing
1. Check middleware registered: `php artisan route:list | grep metrics`
2. Check Redis running: `redis-cli ping`
3. Check IP whitelist in config/observability.php
4. Check Prometheus targets: http://localhost:9090/targets

### Dashboards Not Loading
1. Check Grafana datasources: Settings → Data Sources
2. Verify Prometheus accessible from Grafana
3. Check dashboard provisioning logs: `docker-compose logs grafana`

### No Logs in Loki
1. Check Promtail running: `docker-compose ps promtail`
2. Check log paths in promtail-config.yml
3. Check Promtail logs: `docker-compose logs promtail`

### Traces Not Appearing
1. Check Jaeger running: `docker-compose ps jaeger`
2. Verify tracing enabled: `TRACING_ENABLED=true`
3. Check sampling rate (default 10%)

## Performance Thresholds

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Error Rate | <0.1% | 0.1-1% | >1% |
| Response Time p95 | <250ms | 250-500ms | >500ms |
| DB Query p95 | <50ms | 50-100ms | >100ms |
| Cache Hit Rate | >80% | 50-80% | <50% |
| Queue Job Success | >99% | 95-99% | <95% |
| Memory Usage | <70% | 70-85% | >85% |
| Disk Space | >20% | 10-20% | <10% |

## Useful PromQL Functions

```promql
# Rate of increase over time
rate(metric[5m])

# Average over time
avg_over_time(metric[5m])

# Maximum over time
max_over_time(metric[5m])

# Histogram quantile
histogram_quantile(0.95, sum(rate(metric_bucket[5m])) by (le))

# Top N values
topk(10, metric)

# Bottom N values
bottomk(10, metric)
```

## Quick Diagnostics

### Check System Health
```bash
curl -s http://localhost:8000/health/detailed | jq '.checks'
```

### Check Error Rate
```bash
curl -s 'http://localhost:9090/api/v1/query?query=chom:http:error_rate' | jq
```

### Check Slow Endpoints
```bash
curl -s 'http://localhost:9090/api/v1/query?query=topk(5,chom:http:request_duration_p95_by_route)' | jq
```

### Check Queue Backlog
```bash
php artisan queue:monitor
```

### Check Database Connections
```bash
mysql -e "SHOW PROCESSLIST;"
```

## Documentation Links

- [OBSERVABILITY.md](OBSERVABILITY.md) - Complete setup guide
- [MONITORING_GUIDE.md](MONITORING_GUIDE.md) - Daily operations
- [ALERTING.md](ALERTING.md) - Alert runbooks
- [observability-stack/README.md](../observability-stack/README.md) - Stack documentation
