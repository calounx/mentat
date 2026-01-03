# CHOM Observability Stack

Complete production observability implementation for the CHOM Laravel application, providing comprehensive visibility into application behavior, performance, and health.

## Table of Contents

- [Overview](#overview)
- [Components](#components)
- [Quick Start](#quick-start)
- [Metrics](#metrics)
- [Tracing](#tracing)
- [Logging](#logging)
- [Health Checks](#health-checks)
- [Dashboards](#dashboards)
- [Alerting](#alerting)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## Overview

The CHOM observability stack provides:

- **Metrics Collection**: Prometheus-compatible metrics for all application components
- **Distributed Tracing**: Request tracing across services and components
- **Structured Logging**: JSON-formatted logs with rich context
- **Health Checks**: Comprehensive endpoint monitoring
- **Dashboards**: Grafana dashboards for visualization
- **Alerting**: Automated alerts for critical conditions

## Components

### Core Services

1. **MetricsCollector**: Collects and exposes Prometheus metrics
2. **TracingService**: Manages distributed tracing
3. **StructuredLogger**: Provides structured JSON logging
4. **ErrorTracker**: Captures and tracks errors
5. **PerformanceMonitor**: Monitors application performance

### Infrastructure

- **Prometheus**: Time-series metrics storage and querying
- **Grafana**: Metrics visualization and dashboards
- **Loki**: Log aggregation and querying
- **Promtail**: Log collection agent
- **Jaeger**: Distributed tracing backend
- **AlertManager**: Alert routing and management

## Quick Start

### 1. Configure Environment

Add to your `.env` file:

```bash
# Observability
OBSERVABILITY_ENABLED=true
METRICS_ENABLED=true
TRACING_ENABLED=true
STRUCTURED_LOGGING_ENABLED=true

# Prometheus
PROMETHEUS_NAMESPACE=chom
METRICS_ENDPOINT_ENABLED=true
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

### 2. Start Observability Stack

```bash
cd ../observability-stack
docker-compose up -d
```

This starts:
- Prometheus (http://localhost:9090)
- Grafana (http://localhost:3000) - admin/admin
- Loki (http://localhost:3100)
- Jaeger (http://localhost:16686)
- AlertManager (http://localhost:9093)

### 3. Register Middleware

Add to `bootstrap/app.php` or your HTTP kernel:

```php
use App\Http\Middleware\PrometheusMetricsMiddleware;

$app->middleware([
    PrometheusMetricsMiddleware::class,
]);
```

### 4. Register Routes

Add to your route registration (e.g., in `bootstrap/app.php`):

```php
$app->withRouting(
    health: __DIR__.'/../routes/health.php',
);
```

### 5. Start Performance Monitoring

In your `AppServiceProvider` boot method:

```php
use App\Services\PerformanceMonitor;

public function boot(PerformanceMonitor $monitor): void
{
    $monitor->start();
}
```

### 6. Access Dashboards

- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **Jaeger**: http://localhost:16686

## Metrics

### Available Metrics

#### HTTP Metrics

```
chom_laravel_http_requests_total{method, route, status}
chom_laravel_http_requests_errors_total{method, route, status}
chom_laravel_http_request_duration_seconds{method, route, status}
chom_laravel_http_requests_active
```

#### Database Metrics

```
chom_laravel_db_queries_total{connection, type}
chom_laravel_db_query_duration_seconds{connection, type}
chom_laravel_db_queries_slow_total{connection}
```

#### Cache Metrics

```
chom_laravel_cache_operations_total{operation, store}
```

#### Queue Metrics

```
chom_laravel_queue_jobs_total{job, queue, status}
chom_laravel_queue_job_duration_seconds{job, queue}
chom_laravel_queue_jobs_failed_total{job, queue}
```

#### VPS Operation Metrics

```
chom_laravel_vps_operations_total{operation, status, provider}
chom_laravel_vps_operation_duration_seconds{operation}
chom_laravel_vps_operations_failed_total{operation}
```

#### Site Provisioning Metrics

```
chom_laravel_site_provisioning_total{site_type, status}
chom_laravel_site_provisioning_duration_seconds{site_type}
chom_laravel_site_provisioning_failed_total{site_type}
```

#### Tenant Metrics

```
chom_laravel_tenant_sites_count{tenant_id}
chom_laravel_tenant_storage_gb{tenant_id}
chom_laravel_tenant_backups_count{tenant_id}
chom_laravel_tenant_requests_total{tenant_id}
chom_laravel_tenant_errors_total{tenant_id}
```

### Recording Custom Metrics

```php
use App\Services\MetricsCollector;

class YourService
{
    public function __construct(private MetricsCollector $metrics)
    {
    }

    public function performOperation()
    {
        // Increment counter
        $this->metrics->incrementCounter('custom_operations_total', [
            'type' => 'important',
        ]);

        // Set gauge
        $this->metrics->setGauge('active_connections', 42);

        // Observe histogram
        $startTime = microtime(true);
        // ... do work ...
        $duration = microtime(true) - $startTime;
        $this->metrics->observeHistogram('operation_duration', $duration);
    }
}
```

### Accessing Metrics

Metrics are exposed at `/metrics` endpoint (IP whitelisted):

```bash
curl http://localhost:8000/metrics
```

## Tracing

### Automatic Tracing

HTTP requests are automatically traced when `PrometheusMetricsMiddleware` is enabled.

### Manual Tracing

```php
use App\Services\TracingService;

class YourService
{
    public function __construct(private TracingService $tracing)
    {
    }

    public function complexOperation()
    {
        $spanId = $this->tracing->startSpan('database.query', [
            'query' => 'SELECT * FROM users',
        ]);

        try {
            // Perform operation
            $result = DB::select('SELECT * FROM users');

            $this->tracing->addTag('rows_returned', count($result));
            $this->tracing->finishSpan($spanId);

            return $result;
        } catch (\Exception $e) {
            $this->tracing->finishSpan($spanId, [
                'error' => true,
                'error.message' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
```

### Trace Context Propagation

Trace context is automatically propagated:
- In HTTP headers (W3C Trace Context, Jaeger, Zipkin formats)
- In queued jobs
- In event listeners

## Logging

### Structured Logging

```php
use App\Services\StructuredLogger;

class YourService
{
    public function __construct(private StructuredLogger $logger)
    {
    }

    public function performAction()
    {
        // Info log
        $this->logger->info('Action performed', [
            'action' => 'user_registration',
            'user_id' => 123,
        ]);

        // Performance log
        $startTime = microtime(true);
        // ... operation ...
        $this->logger->performance('database_migration', microtime(true) - $startTime);

        // Business event log
        $this->logger->businessEvent('subscription_created', [
            'plan' => 'professional',
            'amount' => 99.00,
        ]);

        // Security event log
        $this->logger->securityEvent('failed_login_attempt', [
            'username' => 'admin',
            'ip' => request()->ip(),
        ], 'warning');
    }
}
```

### Log Context Enrichment

All logs automatically include:
- `trace_id`: Distributed trace ID
- `request_id`: Unique request ID
- `user_id`: Authenticated user ID
- `tenant_id`: Tenant ID (if applicable)
- `ip_address`: Client IP address
- `timestamp`: ISO 8601 timestamp
- `environment`: Application environment

## Health Checks

### Endpoints

#### Liveness Probe
```bash
curl http://localhost:8000/health
```

Returns 200 if application is running.

#### Readiness Probe
```bash
curl http://localhost:8000/health/ready
```

Returns 200 if application is ready to serve traffic.

#### Detailed Health Check
```bash
curl http://localhost:8000/health/detailed
```

Returns comprehensive health information (IP whitelisted).

### Response Example

```json
{
  "status": "healthy",
  "checks": {
    "database": {
      "healthy": true,
      "duration_ms": 2.45,
      "connection": "mysql"
    },
    "redis": {
      "healthy": true,
      "duration_ms": 1.23,
      "memory_used_mb": 12.5
    },
    "queue": {
      "healthy": true,
      "size": 45,
      "max_backlog": 1000
    },
    "storage": {
      "healthy": true,
      "free_percent": 45.2,
      "free_gb": 120.5
    }
  },
  "system": {
    "app": {
      "name": "CHOM",
      "env": "production",
      "version": "1.0.0"
    },
    "php": {
      "version": "8.2.0",
      "memory_usage_mb": 45.2
    }
  },
  "timestamp": "2024-01-03T10:30:00Z"
}
```

## Dashboards

### Available Dashboards

1. **System Overview**: Request rates, error rates, latency, active requests
2. **Database Performance**: Query rates, durations, slow queries
3. **Business Metrics**: Site provisioning, VPS operations, tenant usage

### Importing Dashboards

Dashboards are auto-provisioned in Grafana at:
- `/var/lib/grafana/dashboards/`

### Custom Dashboards

Create custom dashboards in Grafana using the Prometheus datasource and available metrics.

## Alerting

Alerts are automatically configured in Prometheus and routed via AlertManager.

See [ALERTING.md](ALERTING.md) for complete alert documentation.

### Alert Categories

- **Critical**: Immediate action required
- **Warning**: Investigation needed
- **Info**: Informational only

## Configuration

### Main Configuration

Edit `config/observability.php`:

```php
return [
    'enabled' => env('OBSERVABILITY_ENABLED', true),

    'metrics' => [
        'enabled' => env('METRICS_ENABLED', true),
        'namespace' => env('METRICS_NAMESPACE', 'chom'),
        // ...
    ],

    'tracing' => [
        'enabled' => env('TRACING_ENABLED', true),
        'driver' => env('TRACING_DRIVER', 'jaeger'),
        // ...
    ],

    'logging' => [
        'structured' => env('STRUCTURED_LOGGING_ENABLED', true),
        'format' => env('LOG_FORMAT', 'json'),
        // ...
    ],
];
```

### Alert Configuration

Edit `config/alerts.php` to customize alerting rules and thresholds.

## Troubleshooting

### Metrics Not Appearing

1. Check if observability is enabled: `OBSERVABILITY_ENABLED=true`
2. Check if middleware is registered
3. Verify Redis is running and accessible
4. Check `/metrics` endpoint is accessible

### Traces Not Showing in Jaeger

1. Verify Jaeger agent is running: `docker-compose ps`
2. Check tracing is enabled: `TRACING_ENABLED=true`
3. Verify agent host/port configuration
4. Check sampling rate (default 10%)

### High Memory Usage

1. Check metrics buffer size: `PROMETHEUS_BUFFER_SIZE`
2. Monitor active operations
3. Review log sampling configuration
4. Check for memory leaks in custom code

### Health Checks Failing

1. Review detailed health check output
2. Check database connectivity
3. Verify Redis is accessible
4. Check disk space
5. Review application logs

## Best Practices

1. **Always use structured logging** for better searchability
2. **Add business context** to traces and logs
3. **Monitor SLIs** (Service Level Indicators) not just infrastructure
4. **Set up alerts** for business-critical operations
5. **Review dashboards regularly** to understand normal behavior
6. **Test alert routes** to ensure notifications work
7. **Document runbooks** for each alert type

## Support

For issues or questions:
- Check [MONITORING_GUIDE.md](MONITORING_GUIDE.md) for operations documentation
- Review [ALERTING.md](ALERTING.md) for alert runbooks
- Check application logs in Loki
- Review Grafana dashboards for system state

## License

Copyright © 2024 CHOM. All rights reserved.
