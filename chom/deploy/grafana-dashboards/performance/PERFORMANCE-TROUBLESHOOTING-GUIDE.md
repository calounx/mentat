# CHOM Performance Troubleshooting Guide

## Table of Contents
1. [Application Performance (APM)](#application-performance-apm)
2. [Database Performance](#database-performance)
3. [Frontend Performance](#frontend-performance)
4. [Performance Testing Methodology](#performance-testing-methodology)
5. [Quick Reference](#quick-reference)

---

## Application Performance (APM)

### Slow Endpoint Response Times

**Symptom**: Response times > 500ms (p95)

**Diagnosis Steps**:
```bash
# 1. Check endpoint heatmap in APM dashboard
# Look for red/orange patterns indicating slow endpoints

# 2. Examine slow query log
tail -f /var/log/chom/slow-queries.log

# 3. Profile the endpoint
php artisan telescope:pause  # If using Laravel Telescope
# Make test request
curl -w "@curl-format.txt" https://chom.example.com/api/endpoint

# 4. Check application logs
tail -f storage/logs/laravel.log | grep -i "slow\|timeout\|error"
```

**Common Causes & Solutions**:

| Cause | Solution | Expected Impact |
|-------|----------|----------------|
| N+1 queries | Add eager loading: `Model::with(['relation'])` | 50-80% reduction |
| Missing cache | Implement route/query caching | 60-90% reduction |
| Slow API calls | Add timeout, implement async processing | 40-70% reduction |
| Large payload | Implement pagination, reduce fields | 30-60% reduction |
| Memory leak | Profile with Blackfire/Xdebug, fix leaks | 20-50% reduction |

**Quick Fixes**:
```php
// Before: N+1 Query Problem
$users = User::all();
foreach ($users as $user) {
    echo $user->profile->bio; // Separate query for each user
}

// After: Eager Loading
$users = User::with('profile')->get();
foreach ($users as $user) {
    echo $user->profile->bio; // Single query for all profiles
}

// Cache expensive queries
$data = Cache::remember('expensive-query', 3600, function () {
    return DB::table('complex_view')->get();
});
```

---

### High Cache Miss Rate

**Symptom**: Cache hit rate < 90%

**Diagnosis Steps**:
```bash
# 1. Check cache statistics
php artisan cache:stats

# 2. Monitor Redis (if using)
redis-cli info stats
redis-cli --bigkeys

# 3. Check cache eviction rate
# In Grafana: Cache Operations Breakdown panel
```

**Cache Strategy by Layer**:

```php
// 1. Application Cache (1-24 hours)
Cache::tags(['users', 'profiles'])
    ->remember("user.{$id}", 3600, fn() => User::with('profile')->find($id));

// 2. Query Cache (5-60 minutes)
DB::table('sites')
    ->where('user_id', $userId)
    ->remember(300)
    ->get();

// 3. View Cache (indefinite, manual invalidation)
return view('dashboard')->cache('dashboard-' . auth()->id());

// 4. Route Cache
Route::get('/api/sites', [SiteController::class, 'index'])
    ->middleware('cache.response:3600');
```

**Cache Invalidation Strategy**:
```php
// Model Observer for automatic invalidation
class UserObserver
{
    public function saved(User $user)
    {
        Cache::tags(['users'])->flush();
        Cache::forget("user.{$user->id}");
    }
}

// Time-based + Event-based hybrid
Cache::remember('dashboard-stats', now()->addMinutes(5), function () {
    return DB::table('stats')->get();
});

// Invalidate on specific events
Event::listen(SiteCreated::class, fn() => Cache::tags(['sites'])->flush());
```

---

### Queue Job Delays

**Symptom**: Queue processing time > 5s average

**Diagnosis Steps**:
```bash
# 1. Check queue depth
php artisan queue:monitor

# 2. Monitor failed jobs
php artisan queue:failed

# 3. Check worker status
supervisorctl status chom-worker:*

# 4. Profile job execution
php artisan queue:work --verbose --timeout=60
```

**Optimization Strategies**:

```php
// 1. Job Chunking for large datasets
class ProcessLargeDataset implements ShouldQueue
{
    public function handle()
    {
        // Before: Process all at once (slow, memory intensive)
        // $records = Record::all();
        // $this->process($records);

        // After: Chunk processing
        Record::chunk(100, function ($records) {
            $this->process($records);
        });
    }
}

// 2. Job Batching for parallel execution
Bus::batch([
    new ProcessRecord(1),
    new ProcessRecord(2),
    new ProcessRecord(3),
])->dispatch();

// 3. Job Priorities
class CriticalJob implements ShouldQueue
{
    public $queue = 'high-priority';
    public $tries = 3;
    public $timeout = 30;
}

// 4. Delayed dispatching for non-urgent tasks
ProcessReport::dispatch($data)->delay(now()->addMinutes(5));
```

**Worker Configuration**:
```ini
# /etc/supervisor/conf.d/chom-worker.conf
[program:chom-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /path/to/chom/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=chom
numprocs=8  # Increase for higher throughput
redirect_stderr=true
stdout_logfile=/var/log/chom/worker.log
stopwaitsecs=3600
```

---

### PHP-FPM Pool Exhaustion

**Symptom**: Pool utilization > 80%

**Diagnosis Steps**:
```bash
# 1. Check PHP-FPM status
curl http://localhost/fpm-status

# 2. Monitor pool metrics
watch -n 1 'curl -s http://localhost/fpm-status'

# 3. Check for slow requests
tail -f /var/log/php-fpm/slow.log
```

**Configuration Optimization**:
```ini
# /etc/php/8.2/fpm/pool.d/chom.conf

[chom]
; Dynamic pool management
pm = dynamic
pm.max_children = 50        # Increase based on available memory
pm.start_servers = 10       # 25% of max_children
pm.min_spare_servers = 5    # 10% of max_children
pm.max_spare_servers = 15   # 30% of max_children
pm.max_requests = 500       # Prevent memory leaks

; Process management
pm.process_idle_timeout = 10s
request_terminate_timeout = 60s
request_slowlog_timeout = 5s

; Memory limits (adjust based on avg request memory)
php_admin_value[memory_limit] = 256M

; Increase if needed (memory_in_MB / memory_limit * 0.8)
; Example: 4GB RAM / 256MB * 0.8 = ~12 workers
```

**Calculation Formula**:
```
max_children = (Total RAM - OS - Other Services) / Average Memory per Request

Example:
- Server RAM: 8GB
- OS + Services: 2GB
- Available: 6GB = 6144MB
- Avg memory/request: 128MB
- max_children = 6144 / 128 = 48 workers
```

---

### OPcache Inefficiency

**Symptom**: OPcache hit rate < 95%

**Configuration**:
```ini
# /etc/php/8.2/mods-available/opcache.ini

[opcache]
; Enable OPcache
opcache.enable=1
opcache.enable_cli=0

; Memory and file limits
opcache.memory_consumption=256        # Increase if needed
opcache.interned_strings_buffer=16   # For large applications
opcache.max_accelerated_files=10000  # Adjust to file count

; Revalidation (production)
opcache.validate_timestamps=0         # Disable for production
opcache.revalidate_freq=0

; Performance
opcache.save_comments=1
opcache.enable_file_override=1
opcache.max_wasted_percentage=5

; Optimization level
opcache.optimization_level=0x7FFEBFFF

; Production settings
opcache.huge_code_pages=1
```

**Cache Invalidation**:
```bash
# After deployment
php artisan opcache:clear

# Or via script
curl http://localhost/opcache-clear.php
```

---

## Database Performance

### Slow Query Detection

**Symptom**: Query latency > 100ms (p95)

**Enable Slow Query Log**:
```sql
-- MySQL Configuration
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.1;  -- 100ms threshold
SET GLOBAL log_queries_not_using_indexes = 1;
```

**Analysis Tools**:
```bash
# 1. Analyze slow query log
mysqldumpslow -s t -t 10 /var/log/mysql/slow.log

# 2. Use pt-query-digest (Percona Toolkit)
pt-query-digest /var/log/mysql/slow.log | head -50

# 3. Check query execution plan
mysql> EXPLAIN SELECT * FROM sites WHERE user_id = 123;
```

**Optimization Process**:

1. **Identify slow query**:
```sql
-- Before: Full table scan
SELECT * FROM sites WHERE created_at > '2024-01-01';
-- Execution time: 2.5s (slow)
```

2. **Analyze execution plan**:
```sql
EXPLAIN SELECT * FROM sites WHERE created_at > '2024-01-01'\G

*************************** 1. row ***************************
           type: ALL        # Bad: Full table scan
      possible_keys: NULL   # No index available
            key: NULL
        rows: 125000        # Scanning all rows
        Extra: Using where
```

3. **Add appropriate index**:
```sql
-- Create index
CREATE INDEX idx_sites_created_at ON sites(created_at);

-- Verify improvement
EXPLAIN SELECT * FROM sites WHERE created_at > '2024-01-01'\G

*************************** 1. row ***************************
           type: range      # Good: Range scan
      possible_keys: idx_sites_created_at
            key: idx_sites_created_at
        rows: 5000          # Much fewer rows
        Extra: Using index condition
```

4. **Verify performance**:
```sql
-- After optimization
SELECT * FROM sites WHERE created_at > '2024-01-01';
-- Execution time: 0.05s (20x faster!)
```

---

### Deadlock Resolution

**Symptom**: Deadlock rate > 1 per hour

**Diagnosis**:
```sql
-- Show recent deadlocks
SHOW ENGINE INNODB STATUS\G

-- Monitor in real-time
SELECT * FROM information_schema.INNODB_TRX;
SELECT * FROM information_schema.INNODB_LOCKS;
SELECT * FROM information_schema.INNODB_LOCK_WAITS;
```

**Common Patterns & Solutions**:

**Pattern 1: Lock Order Inconsistency**
```php
// Problem: Transaction A and B lock in different order
// Transaction A:
DB::transaction(function () {
    DB::table('users')->where('id', 1)->lockForUpdate()->first();
    DB::table('sites')->where('id', 1)->lockForUpdate()->first();
});

// Transaction B (reverse order):
DB::transaction(function () {
    DB::table('sites')->where('id', 1)->lockForUpdate()->first();  // Deadlock!
    DB::table('users')->where('id', 1)->lockForUpdate()->first();
});

// Solution: Always lock in same order
DB::transaction(function () {
    // Always: users first, then sites
    DB::table('users')->where('id', 1)->lockForUpdate()->first();
    DB::table('sites')->where('id', 1)->lockForUpdate()->first();
});
```

**Pattern 2: Long-running Transactions**
```php
// Problem: Transaction holds locks too long
DB::transaction(function () {
    $user = User::lockForUpdate()->find(1);

    // Expensive external API call while holding lock
    $result = Http::timeout(30)->get('https://api.example.com');  // BAD!

    $user->update(['data' => $result]);
});

// Solution: Minimize transaction scope
$result = Http::timeout(30)->get('https://api.example.com');  // Outside transaction

DB::transaction(function () use ($result) {
    $user = User::lockForUpdate()->find(1);
    $user->update(['data' => $result]);  // Quick update only
});
```

**Pattern 3: Gap Locks**
```php
// Problem: Range locks cause gaps
DB::transaction(function () {
    // Locks range of IDs, including gaps
    DB::table('sites')
        ->whereBetween('id', [1, 100])
        ->lockForUpdate()
        ->get();
});

// Solution: Use specific IDs
DB::transaction(function () {
    DB::table('sites')
        ->whereIn('id', [1, 5, 10, 25])  // Specific IDs only
        ->lockForUpdate()
        ->get();
});
```

**Retry Logic**:
```php
use Illuminate\Database\QueryException;

class DeadlockRetryHandler
{
    public static function retry(callable $callback, int $maxAttempts = 3)
    {
        $attempts = 0;

        begin:
        try {
            return DB::transaction($callback);
        } catch (QueryException $e) {
            if ($e->getCode() === '40001' && ++$attempts < $maxAttempts) {
                // Deadlock detected, retry with exponential backoff
                usleep(pow(2, $attempts) * 100000);  // 0.2s, 0.4s, 0.8s
                goto begin;
            }
            throw $e;
        }
    }
}

// Usage
DeadlockRetryHandler::retry(function () {
    // Your transaction logic
});
```

---

### Connection Pool Exhaustion

**Symptom**: Connection pool utilization > 75%

**Immediate Actions**:
```bash
# 1. Check current connections
mysql -e "SHOW PROCESSLIST;"

# 2. Kill long-running queries
mysql -e "SELECT CONCAT('KILL ', id, ';') FROM information_schema.PROCESSLIST WHERE TIME > 60;"

# 3. Monitor connection usage
watch -n 1 'mysql -e "SHOW STATUS LIKE \"Threads_connected\";"'
```

**Configuration Tuning**:
```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf

[mysqld]
# Connection limits
max_connections = 200               # Increase based on load
max_user_connections = 180          # Per-user limit

# Connection timeout
wait_timeout = 300                  # 5 minutes idle timeout
interactive_timeout = 300

# Thread cache
thread_cache_size = 50              # Reuse connections

# Connection pooling (application side)
# Laravel .env
DB_POOL_MIN=10
DB_POOL_MAX=30
```

**Application-Level Pooling**:
```php
// config/database.php
'mysql' => [
    'driver' => 'mysql',
    'options' => [
        PDO::ATTR_PERSISTENT => true,  // Persistent connections
        PDO::ATTR_TIMEOUT => 10,
    ],
    'pool' => [
        'min' => 10,
        'max' => 30,
    ],
],
```

**Connection Leak Detection**:
```php
// Middleware to track connection usage
class DatabaseConnectionMonitor
{
    public function handle($request, Closure $next)
    {
        $before = DB::connection()->getPdo()->query('SHOW STATUS LIKE "Threads_connected"')->fetch();

        $response = $next($request);

        $after = DB::connection()->getPdo()->query('SHOW STATUS LIKE "Threads_connected"')->fetch();

        if ($after['Value'] > $before['Value'] + 5) {
            Log::warning('Possible connection leak', [
                'route' => $request->path(),
                'before' => $before['Value'],
                'after' => $after['Value'],
            ]);
        }

        return $response;
    }
}
```

---

### Index Optimization

**Symptom**: Index usage efficiency < 95%

**Index Analysis**:
```sql
-- 1. Find unused indexes
SELECT
    object_schema,
    object_name,
    index_name
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE index_name IS NOT NULL
AND count_star = 0
AND object_schema = 'chom'
ORDER BY object_schema, object_name;

-- 2. Find duplicate indexes
SELECT
    a.TABLE_NAME,
    a.INDEX_NAME AS index1,
    b.INDEX_NAME AS index2,
    a.COLUMN_NAME
FROM information_schema.STATISTICS a
JOIN information_schema.STATISTICS b
    ON a.TABLE_SCHEMA = b.TABLE_SCHEMA
    AND a.TABLE_NAME = b.TABLE_NAME
    AND a.COLUMN_NAME = b.COLUMN_NAME
    AND a.INDEX_NAME < b.INDEX_NAME
WHERE a.TABLE_SCHEMA = 'chom';

-- 3. Check index cardinality
SELECT
    TABLE_NAME,
    INDEX_NAME,
    CARDINALITY,
    COLUMN_NAME
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'chom'
ORDER BY CARDINALITY;
```

**Index Strategy**:

```sql
-- 1. Composite indexes (order matters!)

-- Bad: Separate indexes
CREATE INDEX idx_user ON sites(user_id);
CREATE INDEX idx_status ON sites(status);

-- Query using both columns
SELECT * FROM sites WHERE user_id = 123 AND status = 'active';
-- Uses only one index, still needs to filter

-- Good: Composite index
CREATE INDEX idx_user_status ON sites(user_id, status);
-- Query using composite
SELECT * FROM sites WHERE user_id = 123 AND status = 'active';
-- Uses both columns from single index!

-- 2. Covering indexes (include all needed columns)

-- Query that needs multiple columns
SELECT id, name, status FROM sites WHERE user_id = 123;

-- Regular index
CREATE INDEX idx_user ON sites(user_id);
-- Still needs to look up id, name, status from table

-- Covering index
CREATE INDEX idx_user_covering ON sites(user_id, id, name, status);
-- All needed data in index, no table lookup!

-- 3. Prefix indexes (for long strings)

-- Bad: Index entire column
CREATE INDEX idx_description ON sites(description);  -- description is TEXT

-- Good: Prefix index
CREATE INDEX idx_description_prefix ON sites(description(50));

-- 4. Partial indexes (MySQL 8.0+, PostgreSQL)

-- Only index active records
CREATE INDEX idx_active_sites ON sites(user_id) WHERE status = 'active';
```

**Migration Pattern**:
```php
// Database migration
public function up()
{
    Schema::table('sites', function (Blueprint $table) {
        // Drop unused indexes
        $table->dropIndex('idx_old_unused');

        // Add composite index
        $table->index(['user_id', 'status'], 'idx_user_status');

        // Add covering index for common query
        $table->index(['user_id', 'created_at', 'name'], 'idx_user_created_name');
    });
}
```

---

### Buffer Pool Optimization

**Symptom**: Buffer pool hit rate < 99%

**Configuration**:
```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf

[mysqld]
# Buffer pool size (70-80% of available RAM)
innodb_buffer_pool_size = 4G

# Multiple instances for better concurrency (1 per GB, max 64)
innodb_buffer_pool_instances = 4

# Optimize flushing
innodb_flush_method = O_DIRECT
innodb_flush_neighbors = 0  # For SSD

# Log buffer
innodb_log_buffer_size = 32M
innodb_log_file_size = 512M
```

**Monitoring**:
```sql
-- Check buffer pool efficiency
SHOW STATUS LIKE 'Innodb_buffer_pool%';

-- Key metrics to watch:
-- Innodb_buffer_pool_read_requests: Total read requests
-- Innodb_buffer_pool_reads: Reads from disk (should be low)
-- Hit rate = (read_requests - reads) / read_requests * 100

-- Check buffer pool content
SELECT
    POOL_ID,
    SUM(NUMBER_PAGES) as pages,
    SUM(DATA_SIZE) / 1024 / 1024 as data_mb
FROM information_schema.INNODB_BUFFER_POOL_STATS
GROUP BY POOL_ID;
```

---

## Frontend Performance

### Core Web Vitals Optimization

**LCP (Largest Contentful Paint) > 2.5s**

**Diagnosis**:
```javascript
// Measure LCP in browser
new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    console.log('LCP:', entry.startTime, entry.element);
  }
}).observe({ entryTypes: ['largest-contentful-paint'] });
```

**Solutions**:

1. **Optimize Images**:
```html
<!-- Before: Large unoptimized image -->
<img src="/images/hero.jpg" alt="Hero">

<!-- After: Optimized with modern formats -->
<picture>
  <source srcset="/images/hero.avif" type="image/avif">
  <source srcset="/images/hero.webp" type="image/webp">
  <img src="/images/hero.jpg"
       alt="Hero"
       loading="lazy"
       width="1200"
       height="600">
</picture>
```

2. **Preload Critical Resources**:
```html
<head>
  <!-- Preload LCP image -->
  <link rel="preload" as="image" href="/images/hero.webp">

  <!-- Preload critical CSS -->
  <link rel="preload" as="style" href="/css/critical.css">

  <!-- Preload critical fonts -->
  <link rel="preload" as="font" type="font/woff2"
        href="/fonts/main.woff2" crossorigin>
</head>
```

3. **Optimize Server Response (TTFB)**:
```php
// Add response caching
Route::middleware(['cache.headers:public;max_age=3600'])
    ->get('/api/data', [ApiController::class, 'data']);

// Enable HTTP/2 server push
response()->header('Link', '</css/app.css>; rel=preload; as=style');
```

---

**FID (First Input Delay) > 100ms**

**Solutions**:

1. **Code Splitting**:
```javascript
// Before: Load everything upfront
import { HeavyComponent } from './HeavyComponent';

// After: Dynamic import
const HeavyComponent = lazy(() => import('./HeavyComponent'));

// Or with webpack
import(/* webpackChunkName: "heavy" */ './HeavyComponent')
  .then(module => {
    // Use component
  });
```

2. **Defer Non-Critical JavaScript**:
```html
<!-- Critical JS: inline or async -->
<script async src="/js/critical.js"></script>

<!-- Non-critical JS: defer -->
<script defer src="/js/analytics.js"></script>
<script defer src="/js/chat-widget.js"></script>
```

3. **Use Web Workers**:
```javascript
// Heavy computation in main thread (blocks UI)
const result = heavyComputation(data);

// Move to Web Worker
const worker = new Worker('/js/heavy-worker.js');
worker.postMessage(data);
worker.onmessage = (e) => {
  const result = e.data;
  // Update UI
};
```

---

**CLS (Cumulative Layout Shift) > 0.1**

**Solutions**:

1. **Reserve Space for Images/Ads**:
```html
<!-- Before: No dimensions -->
<img src="/image.jpg" alt="Product">
<!-- CLS occurs when image loads and shifts content -->

<!-- After: Explicit dimensions -->
<img src="/image.jpg"
     alt="Product"
     width="600"
     height="400"
     style="aspect-ratio: 600/400">
```

2. **Font Loading Optimization**:
```css
/* Before: Flash of Invisible Text (FOIT) */
@font-face {
  font-family: 'CustomFont';
  src: url('/fonts/custom.woff2');
}

/* After: Flash of Unstyled Text (FOUT) with fallback */
@font-face {
  font-family: 'CustomFont';
  src: url('/fonts/custom.woff2');
  font-display: swap;  /* Show fallback immediately */
}

body {
  font-family: 'CustomFont', Arial, sans-serif;
}
```

3. **Avoid Inserting Content Above Existing**:
```javascript
// Before: Insert at top (causes shift)
container.prepend(newElement);

// After: Reserve space or insert at bottom
const placeholder = document.createElement('div');
placeholder.style.height = '100px';  // Reserve space
container.prepend(placeholder);

// Load content
fetch('/api/data').then(data => {
  placeholder.replaceWith(createContent(data));
});
```

---

### Asset Optimization

**JavaScript Bundle Size**

```bash
# 1. Analyze bundle size
npm run build -- --analyze

# 2. Common issues and fixes

# Remove unused dependencies
npm prune

# Replace heavy libraries
# Before: moment.js (72KB)
import moment from 'moment';
# After: date-fns (13KB)
import { format } from 'date-fns';

# Tree shaking (eliminate dead code)
# webpack.config.js
module.exports = {
  mode: 'production',  // Enables tree shaking
  optimization: {
    usedExports: true,
    sideEffects: false,
  },
};
```

**CSS Optimization**:
```bash
# Remove unused CSS
npm install -D purgecss @fullhuman/postcss-purgecss

# postcss.config.js
module.exports = {
  plugins: [
    require('@fullhuman/postcss-purgecss')({
      content: [
        './resources/views/**/*.blade.php',
        './resources/js/**/*.vue',
      ],
      defaultExtractor: content => content.match(/[\w-/:]+(?<!:)/g) || []
    })
  ]
}
```

**Image Optimization**:
```bash
# Batch optimize images
npm install -g sharp-cli

# Convert to WebP
find public/images -name "*.jpg" -exec sh -c 'sharp -i "$1" -o "${1%.jpg}.webp" resize 1200' _ {} \;

# Compress PNGs
find public/images -name "*.png" -exec optipng -o7 {} \;
```

---

### Browser Caching Strategy

```nginx
# nginx configuration
location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}

location ~* \.(html)$ {
    expires 1h;
    add_header Cache-Control "public, must-revalidate";
}

# Service Worker for offline caching
// sw.js
const CACHE_NAME = 'chom-v1';
const urlsToCache = [
  '/css/app.css',
  '/js/app.js',
  '/images/logo.svg'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(urlsToCache))
  );
});

self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => response || fetch(event.request))
  );
});
```

---

## Performance Testing Methodology

### Baseline Establishment

```bash
# 1. Load test with k6
k6 run --vus 10 --duration 5m tests/load/scenarios/api-baseline.js

# 2. Record baseline metrics
# - p50, p95, p99 response times
# - Error rate
# - Throughput (requests/sec)

# 3. Create baseline report
cat > baseline-$(date +%Y%m%d).txt <<EOF
Date: $(date)
Scenario: API Baseline
VUs: 10
Duration: 5m

Results:
- p50: 45ms
- p95: 120ms
- p99: 350ms
- Error rate: 0.05%
- Throughput: 450 req/s
EOF
```

### Before/After Comparison

```javascript
// k6 test script with thresholds
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  thresholds: {
    // Performance budgets
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],  // < 1% errors
  },
  stages: [
    { duration: '2m', target: 10 },
    { duration: '5m', target: 10 },
    { duration: '2m', target: 0 },
  ],
};

export default function() {
  const response = http.get('https://chom.example.com/api/sites');

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
```

### Regression Detection

```bash
#!/bin/bash
# regression-check.sh

BASELINE_FILE="baseline-latest.json"
CURRENT_FILE="test-results-$(date +%Y%m%d).json"

# Run current test
k6 run --out json=$CURRENT_FILE test.js

# Compare with baseline
BASELINE_P95=$(jq '.metrics.http_req_duration.values["p(95)"]' $BASELINE_FILE)
CURRENT_P95=$(jq '.metrics.http_req_duration.values["p(95)"]' $CURRENT_FILE)

# Alert if regression > 20%
THRESHOLD=$(echo "$BASELINE_P95 * 1.2" | bc)
if (( $(echo "$CURRENT_P95 > $THRESHOLD" | bc -l) )); then
    echo "REGRESSION DETECTED!"
    echo "Baseline p95: ${BASELINE_P95}ms"
    echo "Current p95: ${CURRENT_P95}ms"
    exit 1
fi
```

---

## Quick Reference

### Performance Budget Checklist

```markdown
## Application Performance (APM)
- [ ] P95 Response Time < 500ms
- [ ] Cache Hit Rate > 90%
- [ ] Queue Processing < 5s avg
- [ ] PHP-FPM Utilization < 80%
- [ ] OPcache Hit Rate > 95%
- [ ] Memory per Request < 50MB

## Database Performance
- [ ] Query Latency (p95) < 100ms
- [ ] Deadlock Rate < 1/hour
- [ ] Connection Pool < 75%
- [ ] Buffer Pool Hit > 99%
- [ ] Index Efficiency > 95%

## Frontend Performance
- [ ] LCP < 2.5s
- [ ] FID < 100ms
- [ ] CLS < 0.1
- [ ] TTFB < 600ms
- [ ] JavaScript Bundle < 200KB
- [ ] Total Page Size < 1MB
```

### Common Commands

```bash
# Application Performance
php artisan cache:clear
php artisan opcache:clear
php artisan queue:restart
supervisorctl restart chom-worker:*

# Database Performance
mysql -e "SHOW PROCESSLIST;"
mysql -e "SHOW ENGINE INNODB STATUS\G"
pt-query-digest /var/log/mysql/slow.log

# Frontend Performance
lighthouse https://chom.example.com --view
npm run build -- --analyze
curl -w "@curl-format.txt" -o /dev/null -s https://chom.example.com
```

### Metric Targets by Environment

| Metric | Development | Staging | Production |
|--------|-------------|---------|------------|
| P95 Response | < 1s | < 500ms | < 300ms |
| Cache Hit | > 70% | > 85% | > 95% |
| LCP | < 4s | < 3s | < 2.5s |
| Error Rate | < 5% | < 1% | < 0.1% |

---

## Additional Resources

- [Laravel Performance Best Practices](https://laravel.com/docs/performance)
- [MySQL Performance Tuning](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [Web.dev Core Web Vitals](https://web.dev/vitals/)
- [k6 Load Testing](https://k6.io/docs/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)

---

**Last Updated**: 2026-01-02
**Version**: 1.0.0
**Maintained by**: CHOM DevOps Team
