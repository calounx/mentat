# CHOM Health Checks & Monitoring

Comprehensive health check system for monitoring application and infrastructure status.

---

## Table of Contents

- [Overview](#overview)
- [Health Endpoints](#health-endpoints)
- [Monitoring Setup](#monitoring-setup)
- [Health Check Components](#health-check-components)
- [Blackbox Monitoring](#blackbox-monitoring)
- [Internal Health Checks](#internal-health-checks)
- [Response Codes](#response-codes)
- [Troubleshooting](#troubleshooting)

---

## Overview

CHOM provides multiple health check endpoints for different monitoring scenarios:

1. **Public Health Endpoint** (`/health`) - External monitoring, load balancers
2. **API Health Endpoints** (`/api/v1/health/*`) - Internal health checks
3. **Kubernetes-style Probes** - Liveness and readiness checks
4. **VPSManager Health** - Infrastructure health monitoring

**Key Features:**
- Database connectivity verification
- Service availability checks
- Graceful degradation status
- Prometheus metrics integration
- Blackbox probe support

---

## Health Endpoints

### 1. Public Health Endpoint

**URL:** `/health`

**Purpose:** Primary health check for external monitoring (load balancers, uptime monitors, blackbox probes)

**Method:** GET

**Authentication:** None required (public)

**Response Format:**

**Healthy (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2026-01-09T12:23:00+00:00",
  "checks": {
    "database": true
  }
}
```

**Unhealthy (503 Service Unavailable):**
```json
{
  "status": "unhealthy",
  "timestamp": "2026-01-09T12:23:00+00:00",
  "checks": {
    "database": false
  }
}
```

**Implementation:**

```php
// Location: routes/web.php
Route::get('/health', function () {
    try {
        // Test database connection
        DB::connection()->getPdo();
        $dbHealthy = true;
    } catch (\Exception $e) {
        $dbHealthy = false;
    }

    $status = $dbHealthy ? 200 : 503;

    return response()->json([
        'status' => $dbHealthy ? 'healthy' : 'unhealthy',
        'timestamp' => now()->toIso8601String(),
        'checks' => [
            'database' => $dbHealthy,
        ],
    ], $status);
})->name('health');
```

**Use Cases:**
- Load balancer health checks
- Uptime monitoring services
- Blackbox Prometheus probes
- External status pages

---

### 2. API Health Endpoint

**URL:** `/api/v1/health`

**Purpose:** Detailed internal health status

**Method:** GET

**Authentication:** Optional (Bearer token)

**Response Format:**

```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "timestamp": "2026-01-09T12:23:00+00:00",
    "version": "2.2.0",
    "checks": {
      "database": {
        "status": "healthy",
        "latency_ms": 2.34
      },
      "cache": {
        "status": "healthy",
        "driver": "redis"
      },
      "queue": {
        "status": "healthy",
        "pending_jobs": 5
      },
      "storage": {
        "status": "healthy",
        "disk_usage_percent": 45.2
      }
    }
  }
}
```

**Use Cases:**
- Internal monitoring dashboards
- Detailed diagnostics
- API health verification

---

### 3. Kubernetes-Style Probes

#### Liveness Probe

**URL:** `/api/v1/health/liveness`

**Purpose:** Determine if application needs to be restarted

**Response:** 200 OK if application is running, 503 if restart needed

**Example:**
```bash
curl http://localhost/api/v1/health/liveness
# 200 OK = healthy, keep running
# 503 Service Unavailable = unhealthy, restart container
```

#### Readiness Probe

**URL:** `/api/v1/health/readiness`

**Purpose:** Determine if application can accept traffic

**Response:** 200 OK if ready, 503 if not ready

**Example:**
```bash
curl http://localhost/api/v1/health/readiness
# 200 OK = ready for traffic
# 503 Service Unavailable = not ready, don't route traffic
```

**Use Cases:**
- Kubernetes liveness probes
- Docker health checks
- Container orchestration

---

### 4. VPSManager Health

**Command:** `vpsmanager health`

**Purpose:** Infrastructure-level health checks

**Checks:**
- Server connectivity (SSH)
- Disk space availability
- Service status (nginx, PHP-FPM, MySQL)
- Site availability
- SSL certificate expiry
- Backup status

**Example:**
```bash
sudo /opt/vpsmanager/bin/vpsmanager health

# Output:
# ✓ SSH connectivity: OK
# ✓ Disk space: 45% used (55% free)
# ✓ Nginx: running
# ✓ PHP-FPM: running
# ✓ MySQL: running
# ✓ Sites responding: 10/10
# ✗ SSL expiring soon: example.com (5 days)
# ✓ Recent backups: 10/10
```

---

## Monitoring Setup

### Blackbox Monitoring (Prometheus)

**Configuration:** `observability-stack/prometheus/prometheus.yml`

```yaml
scrape_configs:
  - job_name: 'blackbox-chom-health'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://chom.arewel.com/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
```

**Metrics:**
- `probe_success{instance="https://chom.arewel.com/health"}` - 1 if healthy, 0 if unhealthy
- `probe_duration_seconds` - Response time
- `probe_http_status_code` - HTTP status code

**Alert Rules:**

```yaml
groups:
  - name: chom_health
    rules:
      - alert: CHOMHealthCheckFailing
        expr: probe_success{job="blackbox-chom-health"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "CHOM health check failing"
          description: "Health endpoint at {{ $labels.instance }} has been down for 5 minutes"

      - alert: CHOMHealthCheckSlow
        expr: probe_duration_seconds{job="blackbox-chom-health"} > 5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "CHOM health check slow"
          description: "Health check at {{ $labels.instance }} taking {{ $value }}s"
```

### Grafana Dashboard

**Panel Configuration:**

```json
{
  "title": "CHOM Health Status",
  "targets": [
    {
      "expr": "probe_success{job=\"blackbox-chom-health\"}",
      "legendFormat": "Health Status"
    }
  ],
  "thresholds": [
    {
      "value": 0,
      "color": "red"
    },
    {
      "value": 1,
      "color": "green"
    }
  ]
}
```

---

## Health Check Components

### 1. Database Health

**What it checks:**
- Database connection establishment
- Query execution capability
- Connection pool status

**Healthy Criteria:**
- Can establish connection to database
- Can execute simple query (SELECT 1)
- Response time < 100ms

**Degraded Criteria:**
- Connection established but slow (100ms - 500ms)
- Connection pool near capacity

**Unhealthy Criteria:**
- Cannot establish connection
- Connection timeout
- Query execution fails

### 2. Cache Health

**What it checks:**
- Redis/Memcached connectivity
- Cache read/write operations
- Memory usage

**Healthy Criteria:**
- Can connect to cache server
- Can read and write test key
- Memory usage < 80%

**Degraded Criteria:**
- High memory usage (80% - 95%)
- Slow response time (> 50ms)

**Unhealthy Criteria:**
- Cannot connect to cache
- Memory exhausted (> 95%)
- Operations failing

### 3. Queue Health

**What it checks:**
- Queue worker status
- Pending job count
- Failed job count

**Healthy Criteria:**
- Queue workers running
- Pending jobs < 1000
- Failed jobs < 10 in last hour

**Degraded Criteria:**
- High pending job count (1000 - 5000)
- Moderate failed job rate (10 - 50)

**Unhealthy Criteria:**
- No queue workers running
- Pending jobs > 5000
- High failure rate (> 50 failures/hour)

### 4. Storage Health

**What it checks:**
- Disk space availability
- File system writability
- Backup storage status

**Healthy Criteria:**
- Disk usage < 80%
- Can write to storage directories
- Backup storage accessible

**Degraded Criteria:**
- Disk usage 80% - 90%
- Slow write operations

**Unhealthy Criteria:**
- Disk usage > 90%
- Cannot write to storage
- Backup storage unavailable

### 5. External Services

**What it checks:**
- VPSManager API connectivity
- Stripe API status
- Observability stack (Prometheus, Loki, Grafana)

**Healthy Criteria:**
- All external services responding
- Response time < 1s
- No error rates

**Degraded Criteria:**
- One or more services slow (1s - 5s)
- Low error rate (< 5%)

**Unhealthy Criteria:**
- Critical service unavailable
- High error rate (> 5%)
- Timeout errors

---

## Blackbox Monitoring

### What is Blackbox Monitoring?

Blackbox monitoring tests applications from the outside, like a user would. It doesn't require access to internal application code or metrics.

**Benefits:**
- Verifies actual user experience
- Tests end-to-end availability
- Catches issues internal metrics might miss
- Simple to set up and maintain

### Blackbox Exporter Configuration

**Location:** `observability-stack/blackbox-exporter/config.yml`

```yaml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      method: GET
      fail_if_not_ssl: true
      preferred_ip_protocol: "ip4"

  http_post_2xx:
    prober: http
    timeout: 10s
    http:
      method: POST
      valid_status_codes: [200, 201, 202]

  tcp_connect:
    prober: tcp
    timeout: 5s

  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
```

### Testing Blackbox Probes

```bash
# Test directly via blackbox exporter
curl "http://localhost:9115/probe?target=https://chom.arewel.com/health&module=http_2xx"

# Check specific metrics
curl "http://localhost:9115/probe?target=https://chom.arewel.com/health&module=http_2xx" | grep probe_success

# Expected output:
# probe_success 1
```

---

## Internal Health Checks

### Laravel Health Check System

**Implementation Example:**

```php
<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;

class HealthCheckService
{
    public function checkAll(): array
    {
        return [
            'status' => $this->getOverallStatus(),
            'timestamp' => now()->toIso8601String(),
            'version' => config('app.version'),
            'checks' => [
                'database' => $this->checkDatabase(),
                'cache' => $this->checkCache(),
                'queue' => $this->checkQueue(),
                'storage' => $this->checkStorage(),
            ],
        ];
    }

    protected function checkDatabase(): array
    {
        try {
            $start = microtime(true);
            DB::connection()->getPdo();
            $latency = (microtime(true) - $start) * 1000;

            return [
                'status' => 'healthy',
                'latency_ms' => round($latency, 2),
            ];
        } catch (\Exception $e) {
            return [
                'status' => 'unhealthy',
                'error' => $e->getMessage(),
            ];
        }
    }

    protected function checkCache(): array
    {
        try {
            $testKey = 'health_check_' . now()->timestamp;
            $testValue = 'test';

            Redis::set($testKey, $testValue, 'EX', 10);
            $retrieved = Redis::get($testKey);

            if ($retrieved !== $testValue) {
                throw new \Exception('Cache read/write mismatch');
            }

            return ['status' => 'healthy', 'driver' => config('cache.default')];
        } catch (\Exception $e) {
            return ['status' => 'unhealthy', 'error' => $e->getMessage()];
        }
    }

    protected function checkQueue(): array
    {
        try {
            $pendingJobs = Queue::size();
            $status = $pendingJobs < 1000 ? 'healthy' : 'degraded';

            return [
                'status' => $status,
                'pending_jobs' => $pendingJobs,
            ];
        } catch (\Exception $e) {
            return ['status' => 'unhealthy', 'error' => $e->getMessage()];
        }
    }

    protected function checkStorage(): array
    {
        try {
            $diskUsage = $this->getDiskUsagePercent();
            $status = $diskUsage < 80 ? 'healthy' : ($diskUsage < 90 ? 'degraded' : 'unhealthy');

            return [
                'status' => $status,
                'disk_usage_percent' => round($diskUsage, 2),
            ];
        } catch (\Exception $e) {
            return ['status' => 'unhealthy', 'error' => $e->getMessage()];
        }
    }

    protected function getDiskUsagePercent(): float
    {
        $total = disk_total_space(storage_path());
        $free = disk_free_space(storage_path());
        return (($total - $free) / $total) * 100;
    }

    protected function getOverallStatus(): string
    {
        $checks = [
            $this->checkDatabase(),
            $this->checkCache(),
            $this->checkQueue(),
            $this->checkStorage(),
        ];

        $statuses = array_column($checks, 'status');

        if (in_array('unhealthy', $statuses)) {
            return 'unhealthy';
        }

        if (in_array('degraded', $statuses)) {
            return 'degraded';
        }

        return 'healthy';
    }
}
```

---

## Response Codes

### HTTP Status Codes

| Code | Meaning | When to Use |
|------|---------|-------------|
| **200 OK** | Healthy | All checks passed |
| **206 Partial Content** | Degraded | Some checks degraded but functional |
| **503 Service Unavailable** | Unhealthy | Critical checks failed |
| **500 Internal Server Error** | Error | Health check itself failed |

### Status Values

| Status | Description | Action Required |
|--------|-------------|-----------------|
| **healthy** | All systems operational | None - continue normal operation |
| **degraded** | Some systems impaired | Monitor closely, plan maintenance |
| **unhealthy** | Critical systems failing | Immediate action required |
| **unknown** | Cannot determine status | Investigate health check system |

---

## Troubleshooting

### Issue: Health check returns 404

**Symptom:** Accessing `/health` returns 404 Not Found

**Solution:**
1. Verify route exists in `routes/web.php`
2. Clear route cache:
```bash
php artisan route:clear
php artisan route:cache
```
3. Test locally:
```bash
php artisan route:list | grep health
```

### Issue: Health check returns 503 but application works

**Symptom:** `/health` returns unhealthy but application appears functional

**Solution:**
1. Check specific failing component:
```bash
curl http://localhost/api/v1/health | jq '.data.checks'
```
2. Verify database connectivity:
```bash
php artisan tinker
>>> DB::connection()->getPdo();
```
3. Check error logs:
```bash
tail -f storage/logs/laravel.log
```

### Issue: Blackbox probe showing probe_success=0

**Symptom:** Prometheus metric `probe_success` is 0

**Solution:**
1. Test endpoint manually:
```bash
curl -I https://chom.arewel.com/health
```
2. Check blackbox exporter logs:
```bash
docker logs blackbox-exporter
# or
journalctl -u blackbox-exporter -f
```
3. Verify SSL certificate:
```bash
curl -v https://chom.arewel.com/health 2>&1 | grep SSL
```
4. Test through blackbox exporter directly:
```bash
curl "http://localhost:9115/probe?target=https://chom.arewel.com/health&module=http_2xx"
```

### Issue: Health check slow (> 5 seconds)

**Symptom:** Health endpoint taking too long to respond

**Solution:**
1. Check database query performance
2. Remove expensive checks from public health endpoint
3. Use caching for non-critical checks:
```php
Route::get('/health', function () {
    // Cache health status for 30 seconds
    return Cache::remember('health_status', 30, function () {
        // Expensive health checks here
    });
});
```
4. Optimize database queries
5. Add timeout to external service checks

---

## Best Practices

### 1. Keep Public Health Endpoint Simple

The public `/health` endpoint should be fast and lightweight:
- Test only critical dependencies (database)
- Avoid external API calls
- Set short timeouts
- Cache results if needed

### 2. Use Separate Endpoints for Detailed Checks

Use `/api/v1/health` for comprehensive diagnostics:
- Detailed component status
- Performance metrics
- Dependency health
- Resource usage

### 3. Return Appropriate Status Codes

- **200**: Everything healthy, route traffic
- **503**: Unhealthy, stop routing traffic
- Avoid **500** errors (health check itself should never fail)

### 4. Include Timestamps

Always include timestamps in responses:
```json
{
  "timestamp": "2026-01-09T12:23:00+00:00"
}
```

### 5. Log Health Check Failures

Log when health checks fail for debugging:
```php
if (!$dbHealthy) {
    Log::error('Health check failed: database connection error', [
        'exception' => $exception->getMessage(),
    ]);
}
```

### 6. Monitor Health Check Performance

Track health check response times:
```promql
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{path="/health"}[5m]))
```

### 7. Test Health Checks Regularly

Include health check tests in your test suite:
```php
public function test_health_endpoint_returns_200_when_healthy()
{
    $response = $this->get('/health');
    $response->assertStatus(200);
    $response->assertJsonStructure(['status', 'timestamp', 'checks']);
}
```

---

## Related Documentation

- [Observability](observability.md) - Metrics and logging
- [Self-Healing](self-healing.md) - Automated recovery
- [Multi-Tenancy Architecture](../architecture/multi-tenancy.md) - Security isolation

---

## References

- [Health Endpoint Implementation Report](../../HEALTH-ENDPOINT-IMPLEMENTATION-REPORT.md)
- [Prometheus Blackbox Exporter](https://github.com/prometheus/blackbox_exporter)
- [Kubernetes Health Checks](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

---

**Last Updated:** 2026-01-09
**Version:** 2.2.0
**Status:** Production Ready
