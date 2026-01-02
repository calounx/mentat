# API Usage Optimization Guide

## Overview

This guide provides best practices for optimizing API usage, monitoring data flows, and implementing capacity planning for the CHOM platform. It complements the Grafana dashboards for API Analytics, Data Pipeline, and Tenant Analytics.

## Table of Contents

1. [API Performance Optimization](#api-performance-optimization)
2. [Data Pipeline Best Practices](#data-pipeline-best-practices)
3. [Multi-Tenant Optimization](#multi-tenant-optimization)
4. [Capacity Planning](#capacity-planning)
5. [Usage-Based Billing](#usage-based-billing)
6. [Monitoring and Alerting](#monitoring-and-alerting)
7. [Cost Optimization](#cost-optimization)

---

## API Performance Optimization

### Rate Limiting Strategy

**Tiered Rate Limits**
```
Free Tier:     100 requests/minute,   10,000 requests/day
Pro Tier:      500 requests/minute,   100,000 requests/day
Enterprise:    2,000 requests/minute, 1,000,000 requests/day
```

**Implementation Best Practices**

1. **Token Bucket Algorithm**
   - Allows burst traffic while maintaining average rate
   - Smooths out traffic spikes
   - Prevents resource exhaustion

2. **Rate Limit Headers**
   ```
   X-RateLimit-Limit: 500
   X-RateLimit-Remaining: 487
   X-RateLimit-Reset: 1609459200
   X-RateLimit-Retry-After: 60
   ```

3. **Graceful Degradation**
   - Return HTTP 429 with clear retry information
   - Implement exponential backoff on client side
   - Queue non-critical requests

**Monitoring Queries**
```promql
# Rate limit consumption by tier
(sum(rate(http_requests_total{job="chom-api"}[5m])) by (tier)
  / on(tier) group_left rate_limit_per_minute) * 100

# Identify consumers hitting rate limits
sum(rate(http_requests_total{status="429"}[5m])) by (consumer, tier)
```

### API Response Optimization

**Payload Size Reduction**

1. **Field Selection (Sparse Fieldsets)**
   ```
   GET /api/v1/vps?fields=id,name,status
   ```
   - Reduces bandwidth by 60-80%
   - Faster serialization
   - Lower memory usage

2. **Compression**
   - Enable gzip/brotli compression
   - Reduces payload by 70-90%
   - Configure in Laravel middleware:
   ```php
   'middleware' => ['compress'],
   ```

3. **Pagination**
   ```
   GET /api/v1/sites?page=1&per_page=25
   ```
   - Default: 25 items per page
   - Maximum: 100 items per page
   - Include pagination metadata in response

**Caching Strategy**

1. **HTTP Cache Headers**
   ```php
   return response()->json($data)
       ->header('Cache-Control', 'public, max-age=300')
       ->header('ETag', hash('sha256', json_encode($data)));
   ```

2. **Application-Level Caching**
   ```php
   Cache::remember("vps.{$id}", 300, function () use ($id) {
       return Vps::with('sites')->find($id);
   });
   ```

3. **CDN for Static Resources**
   - Cache API documentation
   - Cache public endpoint responses
   - Use CloudFlare or AWS CloudFront

### API Version Management

**Deprecation Timeline**

1. **Announce Deprecation**: 90 days notice
2. **Warning Period**: Return `X-API-Deprecated` header
3. **Sunset Period**: 180 days before removal
4. **Remove Version**: After sunset period

**Version Headers**
```
X-API-Version: v1
X-API-Deprecated: true
X-API-Sunset: 2026-06-01T00:00:00Z
X-API-Migration-Guide: https://docs.chom.app/api/v1-to-v2
```

**Monitoring Deprecated Endpoints**
```promql
# Track deprecated endpoint usage
sum(rate(http_requests_total{deprecated="true"}[5m])) by (endpoint, consumer)

# Identify consumers still using old versions
count(http_requests_total{api_version=~"v1|v2"}) by (consumer, api_version)
```

---

## Data Pipeline Best Practices

### Queue Architecture

**Queue Prioritization**

```
high-priority:    Real-time notifications, webhook deliveries
default:          Standard background jobs, email sends
low-priority:     Reports generation, data exports
batch:            Bulk operations, data imports
```

**Queue Configuration (Laravel Horizon)**

```php
'defaults' => [
    'high-priority' => [
        'connection' => 'redis',
        'queue' => ['high-priority'],
        'balance' => 'auto',
        'processes' => 10,
        'tries' => 3,
        'timeout' => 60,
    ],
    'default' => [
        'connection' => 'redis',
        'queue' => ['default'],
        'balance' => 'auto',
        'processes' => 5,
        'tries' => 3,
        'timeout' => 120,
    ],
    'batch' => [
        'connection' => 'redis',
        'queue' => ['batch'],
        'balance' => 'simple',
        'processes' => 2,
        'tries' => 5,
        'timeout' => 600,
    ],
],
```

### Job Optimization

**Idempotent Operations**

Always design jobs to be safely retryable:

```php
class ProcessVpsDeployment implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function handle()
    {
        // Check if already processed
        if ($this->vps->deployment_status === 'completed') {
            return;
        }

        // Use database transactions
        DB::transaction(function () {
            // Atomic operations here
            $this->vps->update(['deployment_status' => 'processing']);

            // Process deployment...

            $this->vps->update(['deployment_status' => 'completed']);
        });
    }

    public function uniqueId()
    {
        return $this->vps->id;
    }
}
```

**Chunked Processing**

For large datasets, process in chunks:

```php
Site::query()
    ->where('needs_ssl_renewal', true)
    ->chunk(100, function ($sites) {
        foreach ($sites as $site) {
            RenewSslCertificate::dispatch($site);
        }
    });
```

**Job Batching**

```php
$batch = Bus::batch([
    new ImportSiteData(1, 1000),
    new ImportSiteData(1001, 2000),
    new ImportSiteData(2001, 3000),
])->then(function (Batch $batch) {
    // All jobs completed successfully
    event(new DataImportCompleted($batch));
})->catch(function (Batch $batch, Throwable $e) {
    // First batch job failure
    Log::error('Batch import failed', ['batch_id' => $batch->id]);
})->finally(function (Batch $batch) {
    // Cleanup
})->dispatch();
```

### ETL Pipeline Patterns

**Incremental Processing**

```php
// Track last processed timestamp
$lastProcessed = Cache::get('etl.last_processed_at', now()->subDay());

$newRecords = SourceTable::query()
    ->where('updated_at', '>', $lastProcessed)
    ->orderBy('updated_at')
    ->get();

foreach ($newRecords as $record) {
    TransformAndLoad::dispatch($record);
}

Cache::put('etl.last_processed_at', now());
```

**Schema-on-Write vs Schema-on-Read**

| Pattern | Use Case | Pros | Cons |
|---------|----------|------|------|
| Schema-on-Write | Structured data, known schema | Fast queries, data validation | Inflexible, complex migrations |
| Schema-on-Read | Semi-structured, evolving schema | Flexible, easy ingestion | Slow queries, inconsistent data |

**CHOM Recommendation**: Use schema-on-write for core entities (VPS, Sites, Users), schema-on-read for logs and analytics.

### Data Quality Checks

**Validation Pipeline**

```php
class DataValidationJob implements ShouldQueue
{
    public function handle()
    {
        $validator = Validator::make($this->data, [
            'vps_id' => 'required|exists:vps,id',
            'cpu_usage' => 'required|numeric|min:0|max:100',
            'memory_usage' => 'required|numeric|min:0',
            'timestamp' => 'required|date',
        ]);

        if ($validator->fails()) {
            // Record validation errors
            DataValidationError::create([
                'job_type' => 'vps_metrics',
                'validation_errors' => $validator->errors()->toArray(),
                'data' => $this->data,
            ]);

            // Emit metric
            Metrics::increment('data_validation_errors_total', [
                'validation_type' => 'vps_metrics',
                'field' => $validator->errors()->keys()[0],
            ]);

            return;
        }

        // Process valid data
        $this->processData($this->data);
    }
}
```

**Data Quality Metrics**

```promql
# Validation error rate by type
sum(rate(data_validation_errors_total[5m])) by (validation_type, field)

# Data freshness (time since last import)
time() - max(data_import_last_success_timestamp_seconds) by (source)

# Completeness (records processed vs expected)
(data_import_records_total / data_import_expected_records_total) * 100
```

---

## Multi-Tenant Optimization

### Tenant Isolation

**Database Isolation Strategies**

1. **Schema-based Isolation** (CHOM uses this)
   ```sql
   -- Each tenant has own schema
   SET search_path = tenant_abc123;
   SELECT * FROM sites;
   ```

   **Pros**: Strong isolation, simple backups, easy migrations
   **Cons**: Limited scalability (max ~1000 tenants per DB)

2. **Row-level Isolation**
   ```sql
   -- Shared tables with tenant_id column
   SELECT * FROM sites WHERE tenant_id = 'abc123';
   ```

   **Pros**: Unlimited tenants, efficient resource usage
   **Cons**: Data leakage risk, complex queries

3. **Database-per-Tenant**
   ```
   tenant_abc123_db, tenant_def456_db, tenant_ghi789_db
   ```

   **Pros**: Perfect isolation, independent scaling
   **Cons**: High overhead, complex management

**CHOM Implementation**

```php
// Middleware to set tenant context
class SetTenantContext
{
    public function handle($request, Closure $next)
    {
        $tenant = $request->user()->team;

        // Set database schema
        DB::statement("SET search_path = tenant_{$tenant->id}");

        // Set context for logging/metrics
        app()->instance('current_tenant', $tenant);

        return $next($request);
    }
}

// Prevent cross-tenant queries
class EnforceTenantIsolation
{
    public function handle($request, Closure $next)
    {
        $response = $next($request);

        // Verify no cross-tenant data access
        if (app()->has('query_logger')) {
            $queries = app('query_logger')->getQueries();
            foreach ($queries as $query) {
                if (!$this->isTenantSafe($query)) {
                    Log::critical('Cross-tenant query detected', [
                        'query' => $query,
                        'tenant' => app('current_tenant')->id,
                    ]);

                    Metrics::increment('tenant_isolation_violations_total', [
                        'violation_type' => 'cross_tenant_query',
                    ]);
                }
            }
        }

        return $response;
    }
}
```

### Resource Fair-Sharing

**CPU and Memory Limits**

Use Kubernetes resource quotas:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-abc123-quota
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
```

**Database Connection Pooling**

```php
// config/database.php
'connections' => [
    'tenant' => [
        'driver' => 'pgsql',
        'pool' => [
            'min' => 2,
            'max' => 10,
            'acquire_timeout' => 60000,
        ],
    ],
],
```

**Rate Limiting per Tenant**

```php
// Middleware
class TenantRateLimit
{
    public function handle($request, Closure $next)
    {
        $tenant = $request->user()->team;
        $limit = $this->getTenantLimit($tenant->tier);

        $key = "rate_limit:tenant:{$tenant->id}";
        $current = Redis::incr($key);

        if ($current === 1) {
            Redis::expire($key, 60); // 1 minute window
        }

        if ($current > $limit) {
            Metrics::increment('http_requests_total', [
                'status' => '429',
                'tenant' => $tenant->id,
                'tier' => $tenant->tier,
            ]);

            return response()->json([
                'error' => 'Rate limit exceeded',
                'limit' => $limit,
                'retry_after' => Redis::ttl($key),
            ], 429);
        }

        return $next($request);
    }

    private function getTenantLimit($tier)
    {
        return match($tier) {
            'free' => 100,
            'pro' => 500,
            'enterprise' => 2000,
            default => 100,
        };
    }
}
```

---

## Capacity Planning

### Resource Forecasting

**CPU and Memory Growth**

```promql
# Linear regression for CPU usage (next 7 days)
predict_linear(
  avg_over_time(container_cpu_usage_seconds_total[7d])[7d:1h],
  7 * 24 * 3600
)

# Memory growth rate (per day)
(avg_over_time(container_memory_usage_bytes[1d]) -
 avg_over_time(container_memory_usage_bytes[1d] offset 1d)) /
 avg_over_time(container_memory_usage_bytes[1d] offset 1d) * 100
```

**Storage Growth**

```promql
# Storage growth rate (GB per week)
(sum(tenant_database_size_bytes + tenant_file_storage_bytes) -
 sum(tenant_database_size_bytes offset 7d + tenant_file_storage_bytes offset 7d))
/ 1073741824

# Estimated days until disk full
(disk_total_bytes - disk_used_bytes) /
(rate(disk_used_bytes[7d]) * 86400)
```

**API Request Growth**

```promql
# Request growth rate (month-over-month)
(sum(increase(http_requests_total[30d])) -
 sum(increase(http_requests_total[30d] offset 30d))) /
 sum(increase(http_requests_total[30d] offset 30d)) * 100

# Tenant growth velocity
count(count by (tenant) (http_requests_total)) -
count(count by (tenant) (http_requests_total offset 7d))
```

### Scaling Thresholds

**Horizontal Pod Autoscaling (HPA)**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: chom-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: chom-api
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

**Database Scaling**

1. **Read Replicas**: Add when read:write ratio > 80:20
2. **Connection Pooling**: Max connections = ((core_count * 2) + effective_spindle_count)
3. **Partitioning**: When table > 100GB or 100M rows

**Queue Worker Scaling**

```php
// config/horizon.php
'environments' => [
    'production' => [
        'high-priority' => [
            'maxProcesses' => 10,
            'balanceMaxShift' => 1,
            'balanceCooldown' => 3,
        ],
    ],
],
```

Scale workers when:
- Queue wait time > 30 seconds (p95)
- Queue depth > 1000 jobs
- Job failure rate > 5%

### Cost Optimization

**Right-Sizing Resources**

```promql
# Identify over-provisioned tenants (CPU < 30% utilized)
avg_over_time(
  (container_cpu_usage_seconds_total{tenant!=""}[7d])
)[7d:1h] < 0.30

# Identify under-provisioned tenants (CPU > 80% utilized)
avg_over_time(
  (container_cpu_usage_seconds_total{tenant!=""}[7d])
)[7d:1h] > 0.80
```

**Storage Optimization**

1. **Archive old data**: Move data older than 90 days to cold storage
2. **Compress backups**: Use pg_dump with gzip compression
3. **Cleanup orphaned files**: Remove files without database references

```bash
# Archive old logs
psql -c "DELETE FROM activity_logs WHERE created_at < NOW() - INTERVAL '90 days'"

# Vacuum database
psql -c "VACUUM ANALYZE"

# Find large tables
psql -c "SELECT schemaname, tablename,
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
         FROM pg_tables
         ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
         LIMIT 20"
```

---

## Usage-Based Billing

### Metering Strategy

**Billable Metrics**

```php
class MeteringService
{
    public function recordUsage($tenant, $metric, $quantity, $metadata = [])
    {
        UsageRecord::create([
            'tenant_id' => $tenant->id,
            'metric' => $metric,
            'quantity' => $quantity,
            'metadata' => $metadata,
            'recorded_at' => now(),
        ]);

        // Emit to Prometheus
        Metrics::histogram('tenant_usage_quantity', $quantity, [
            'tenant' => $tenant->id,
            'metric' => $metric,
            'tier' => $tenant->tier,
        ]);
    }
}

// Usage tracking
$metering = app(MeteringService::class);

// API requests
$metering->recordUsage($tenant, 'api_requests', 1, [
    'endpoint' => '/api/v1/vps',
    'method' => 'GET',
]);

// Storage
$metering->recordUsage($tenant, 'storage_gb', $storageGB, [
    'type' => 'database',
]);

// VPS hours
$metering->recordUsage($tenant, 'vps_hours', $vpsCount, [
    'vps_ids' => $vpsIds,
]);
```

**Pricing Models**

```
API Requests:
  - Free:       $0 (included: 10,000/month)
  - Pro:        $0.001 per request over 100,000/month
  - Enterprise: $0.0005 per request over 1,000,000/month

Storage:
  - All Tiers:  $0.10 per GB/month

VPS Management:
  - All Tiers:  $5 per VPS/month

Data Transfer:
  - All Tiers:  $0.05 per GB outbound
```

**Monthly Billing Calculation**

```php
class CalculateMonthlyBill
{
    public function calculate($tenant, $month)
    {
        $basePrice = $this->getBasePricing($tenant->tier);

        // Calculate usage charges
        $apiRequests = UsageRecord::where('tenant_id', $tenant->id)
            ->where('metric', 'api_requests')
            ->whereMonth('recorded_at', $month)
            ->sum('quantity');

        $storageGB = UsageRecord::where('tenant_id', $tenant->id)
            ->where('metric', 'storage_gb')
            ->whereMonth('recorded_at', $month)
            ->avg('quantity'); // Average for the month

        $vpsHours = UsageRecord::where('tenant_id', $tenant->id)
            ->where('metric', 'vps_hours')
            ->whereMonth('recorded_at', $month)
            ->sum('quantity');

        // Apply pricing
        $charges = [
            'base' => $basePrice,
            'api_requests' => $this->calculateApiCharges($tenant->tier, $apiRequests),
            'storage' => $storageGB * 0.10,
            'vps' => ($vpsHours / 730) * 5, // 730 hours in average month
        ];

        $total = array_sum($charges);

        // Record for capacity planning
        Metrics::gauge('tenant_mrr_dollars', $total, [
            'tenant' => $tenant->id,
            'tier' => $tenant->tier,
        ]);

        return [
            'charges' => $charges,
            'total' => $total,
            'usage' => [
                'api_requests' => $apiRequests,
                'storage_gb' => $storageGB,
                'vps_hours' => $vpsHours,
            ],
        ];
    }
}
```

---

## Monitoring and Alerting

### Critical Alerts

**API Health Alerts**

```yaml
# alerts/api-health.yml
groups:
  - name: api_health
    interval: 30s
    rules:
      - alert: HighAPIErrorRate
        expr: |
          (sum(rate(http_requests_total{status=~"5.."}[5m])) by (endpoint) /
           sum(rate(http_requests_total[5m])) by (endpoint)) * 100 > 5
        for: 5m
        labels:
          severity: critical
          component: api
        annotations:
          summary: "High API error rate on {{ $labels.endpoint }}"
          description: "Error rate is {{ $value }}% (threshold: 5%)"
          dashboard: "https://grafana.chom.app/d/chom-api-analytics"

      - alert: APILatencyHigh
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le, endpoint)
          ) * 1000 > 500
        for: 10m
        labels:
          severity: warning
          component: api
        annotations:
          summary: "High API latency on {{ $labels.endpoint }}"
          description: "P95 latency is {{ $value }}ms (threshold: 500ms)"

      - alert: RateLimitViolationsHigh
        expr: |
          sum(rate(http_requests_total{status="429"}[5m])) by (tier) > 10
        for: 5m
        labels:
          severity: warning
          component: api
        annotations:
          summary: "High rate limit violations for {{ $labels.tier }} tier"
          description: "{{ $value }} violations/second"
```

**Data Pipeline Alerts**

```yaml
# alerts/data-pipeline.yml
groups:
  - name: data_pipeline
    interval: 30s
    rules:
      - alert: QueueBacklogHigh
        expr: laravel_queue_size > 1000
        for: 10m
        labels:
          severity: warning
          component: queue
        annotations:
          summary: "High queue backlog on {{ $labels.queue }}"
          description: "{{ $value }} jobs pending (threshold: 1000)"
          dashboard: "https://grafana.chom.app/d/chom-data-pipeline"

      - alert: JobFailureRateHigh
        expr: |
          (sum(rate(laravel_queue_jobs_processed_total{status="failed"}[15m])) by (queue) /
           sum(rate(laravel_queue_jobs_processed_total[15m])) by (queue)) * 100 > 10
        for: 15m
        labels:
          severity: critical
          component: queue
        annotations:
          summary: "High job failure rate on {{ $labels.queue }}"
          description: "Failure rate is {{ $value }}% (threshold: 10%)"

      - alert: ETLJobStalled
        expr: |
          time() - scheduled_job_last_run_timestamp_seconds > 7200
        for: 5m
        labels:
          severity: critical
          component: etl
        annotations:
          summary: "ETL job {{ $labels.job_name }} has not run recently"
          description: "Last run was {{ $value }} seconds ago (threshold: 2 hours)"

      - alert: DataValidationErrorsHigh
        expr: |
          sum(rate(data_validation_errors_total[10m])) by (validation_type) > 1
        for: 10m
        labels:
          severity: warning
          component: data_quality
        annotations:
          summary: "High data validation errors for {{ $labels.validation_type }}"
          description: "{{ $value }} errors/second"
```

**Tenant Health Alerts**

```yaml
# alerts/tenant-health.yml
groups:
  - name: tenant_health
    interval: 60s
    rules:
      - alert: TenantIsolationViolation
        expr: |
          increase(tenant_isolation_violations_total[5m]) > 0
        for: 1m
        labels:
          severity: critical
          component: security
        annotations:
          summary: "Tenant isolation violation detected"
          description: "{{ $labels.violation_type }}: {{ $value }} violations"
          runbook: "https://docs.chom.app/runbooks/tenant-isolation"

      - alert: TenantResourceExhaustion
        expr: |
          (container_memory_usage_bytes{tenant!=""} /
           container_memory_limit_bytes{tenant!=""}) * 100 > 90
        for: 10m
        labels:
          severity: warning
          component: capacity
        annotations:
          summary: "Tenant {{ $labels.tenant }} approaching resource limits"
          description: "Memory usage is {{ $value }}% (threshold: 90%)"

      - alert: TenantStorageGrowthAnomaly
        expr: |
          (tenant_database_size_bytes + tenant_file_storage_bytes -
           (tenant_database_size_bytes offset 7d + tenant_file_storage_bytes offset 7d)) /
          (tenant_database_size_bytes offset 7d + tenant_file_storage_bytes offset 7d) * 100 > 200
        for: 1h
        labels:
          severity: warning
          component: capacity
        annotations:
          summary: "Unusual storage growth for tenant {{ $labels.tenant }}"
          description: "Storage grew {{ $value }}% in 7 days (threshold: 200%)"
```

### SLO-Based Alerts

**Service Level Objectives**

```
API Availability:     99.9% (< 43 minutes downtime/month)
API Latency (p95):    < 200ms
API Error Rate:       < 0.1%
Data Pipeline Health: > 99% job success rate
Queue Processing:     < 60 seconds wait time (p95)
```

**Multi-Window Burn Rate Alerts**

```yaml
# alerts/slo.yml
groups:
  - name: slo_alerts
    interval: 30s
    rules:
      # Fast burn: 2% budget consumed in 1 hour
      - alert: ErrorBudgetBurnRateFast
        expr: |
          (1 - (sum(rate(http_requests_total{status!~"5.."}[1h])) /
                sum(rate(http_requests_total[1h])))) > 0.02
        for: 5m
        labels:
          severity: critical
          slo: availability
        annotations:
          summary: "Fast error budget burn detected"
          description: "Burning 2% of monthly budget per hour"

      # Slow burn: 10% budget consumed in 6 hours
      - alert: ErrorBudgetBurnRateSlow
        expr: |
          (1 - (sum(rate(http_requests_total{status!~"5.."}[6h])) /
                sum(rate(http_requests_total[6h])))) > 0.10
        for: 30m
        labels:
          severity: warning
          slo: availability
        annotations:
          summary: "Slow error budget burn detected"
          description: "Burning 10% of monthly budget per 6 hours"
```

---

## Cost Optimization

### Infrastructure Cost Analysis

**Cost Attribution by Tenant**

```promql
# Compute cost (approximate based on CPU/Memory usage)
sum(
  (container_cpu_usage_seconds_total * 0.05) +  # $0.05 per CPU-hour
  (container_memory_usage_bytes / 1073741824 * 0.01)  # $0.01 per GB-hour
) by (tenant)

# Storage cost
(tenant_database_size_bytes + tenant_file_storage_bytes) / 1073741824 * 0.10

# Network cost (egress)
sum(http_response_size_bytes) by (tenant) / 1073741824 * 0.05
```

**Cost Optimization Opportunities**

1. **Spot Instances**: Use for batch workloads (60-90% savings)
2. **Reserved Instances**: Commit to 1-year for stable workloads (30-50% savings)
3. **Auto-scaling**: Scale down during off-peak hours
4. **Data Lifecycle**: Archive old data to cheaper storage tiers

**Cost Allocation Report**

```php
class GenerateCostAllocationReport
{
    public function generate($month)
    {
        $costs = [];

        foreach (Tenant::all() as $tenant) {
            $costs[] = [
                'tenant' => $tenant->name,
                'tier' => $tenant->tier,
                'compute_cost' => $this->calculateComputeCost($tenant, $month),
                'storage_cost' => $this->calculateStorageCost($tenant, $month),
                'network_cost' => $this->calculateNetworkCost($tenant, $month),
                'total_cost' => 0, // Sum of above
                'revenue' => $this->calculateRevenue($tenant, $month),
                'margin' => 0, // revenue - total_cost
            ];
        }

        return $costs;
    }
}
```

### Performance vs Cost Trade-offs

| Optimization | Performance Impact | Cost Impact | Recommendation |
|--------------|-------------------|-------------|----------------|
| HTTP/2 | +30% throughput | Free | Always enable |
| Redis caching | +80% response time | +$50/month | Enable for hot data |
| CDN | +60% static content | +$100/month | Enable for > 1TB transfer |
| Read replicas | +50% read throughput | +$200/month | Enable at > 80% CPU |
| Multi-AZ deployment | 0% (HA only) | +100% cost | Enable for production |

---

## Dashboard Usage Guide

### API Analytics Dashboard

**Key Metrics to Monitor**

1. **API Request Rate by Endpoint**: Identify most-used endpoints
2. **Rate Limit Consumption**: Prevent tier violations
3. **API Version Adoption**: Track migration progress
4. **Deprecated Endpoint Usage**: Plan removal timeline
5. **Response Payload Sizes**: Optimize bandwidth

**Action Items**

- If rate limit > 80%: Contact customer to upgrade tier
- If deprecated endpoint usage > 0: Send migration notification
- If payload size > 1MB: Implement pagination or field selection
- If error rate > 1%: Investigate and fix root cause

### Data Pipeline Dashboard

**Key Metrics to Monitor**

1. **Queue Job Processing Rate**: Ensure adequate worker capacity
2. **Background Job Success/Failure**: Track reliability
3. **ETL Job Performance**: Optimize slow jobs
4. **Data Validation Errors**: Improve data quality

**Action Items**

- If queue depth > 1000: Scale workers
- If job failure rate > 5%: Review error logs
- If ETL duration > 5 minutes: Optimize queries or add indexes
- If validation errors > 10/min: Fix upstream data source

### Tenant Analytics Dashboard

**Key Metrics to Monitor**

1. **Per-Tenant Resource Usage**: Identify resource hogs
2. **Storage Consumption**: Plan capacity
3. **Tenant Health Scores**: Proactive support
4. **Multi-Tenancy Isolation**: Security verification

**Action Items**

- If resource usage > 90%: Contact tenant about upgrade
- If health score < 75: Investigate issues
- If isolation violation > 0: CRITICAL - investigate immediately
- If churn risk detected: Proactive outreach

---

## Appendix

### Prometheus Metric Naming Conventions

```
<namespace>_<subsystem>_<metric_name>_<unit>_<type>

Examples:
http_requests_total              (counter)
http_request_duration_seconds    (histogram)
laravel_queue_size               (gauge)
tenant_database_size_bytes       (gauge)
```

### Query Examples

```promql
# Top 10 API consumers by request volume (last 24h)
topk(10, sum(increase(http_requests_total[24h])) by (consumer))

# Average queue wait time per queue
histogram_quantile(0.50,
  sum(rate(laravel_queue_wait_seconds_bucket[5m])) by (le, queue)
)

# Storage growth rate (GB per day)
(sum(tenant_database_size_bytes + tenant_file_storage_bytes) -
 sum(tenant_database_size_bytes offset 1d + tenant_file_storage_bytes offset 1d)
) / 1073741824

# Tenant error budget remaining (99.9% SLO)
(1 - ((1 - sum(rate(http_requests_total{status!~"5.."}[30d])) /
            sum(rate(http_requests_total[30d]))) / 0.001)) * 100
```

### Further Reading

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Laravel Horizon Documentation](https://laravel.com/docs/horizon)
- [Multi-Tenancy Patterns](https://docs.microsoft.com/en-us/azure/architecture/patterns/multi-tenancy)
- [Usage-Based Pricing Models](https://stripe.com/docs/billing/subscriptions/usage-based)

---

## Support

For questions or issues:
- Documentation: https://docs.chom.app
- Support: support@chom.app
- GitHub Issues: https://github.com/chom/chom/issues
