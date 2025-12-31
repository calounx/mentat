# CHOM Performance Optimization - Quick Reference Card

**Quick Start:** The essentials for developers

---

## Critical Performance Issues

### 1. NO REDIS CACHING ⚠️
**Problem:** Using database cache (10-50ms) instead of Redis (<1ms)
**Fix:**
```bash
# Install Redis
docker run -d --name redis -p 6379:6379 redis:7-alpine

# Update .env
CACHE_STORE=redis
QUEUE_CONNECTION=redis
```

### 2. NO QUERY CACHING ⚠️
**Problem:** Dashboard queries run on every page load
**Fix:**
```php
// Before (slow)
$this->stats = $this->tenant->sites()->count();

// After (fast)
$this->stats = Cache::remember("tenant:{$this->tenant->id}:stats", 60, fn() =>
    $this->tenant->sites()->count()
);
```

### 3. SEQUENTIAL API CALLS ⚠️
**Problem:** 5 Prometheus queries in series (250ms-1s total)
**Fix:**
```php
// Before (slow)
$cpu = Http::get($prometheusUrl, ['query' => 'cpu...']);
$mem = Http::get($prometheusUrl, ['query' => 'mem...']);
// ... 3 more sequential calls

// After (fast - parallel)
$results = Http::pool(fn (Pool $pool) => [
    $pool->as('cpu')->get($prometheusUrl, ['query' => 'cpu...']),
    $pool->as('mem')->get($prometheusUrl, ['query' => 'mem...']),
    // ... all in parallel
]);
```

---

## Performance Checklist

### Before You Code
- [ ] Is this query running on every request? → Cache it
- [ ] Am I calling external APIs? → Cache + parallelize
- [ ] Am I querying relationships? → Use `with()` eager loading
- [ ] Am I filtering large datasets? → Check indexes exist

### Before You Commit
- [ ] Added cache invalidation for new caches
- [ ] Used `with()` for all relationship access
- [ ] Tested with >100 records in database
- [ ] Checked query count with `DB::getQueryLog()`
- [ ] Verified no N+1 queries

### Before You Deploy
- [ ] Run performance tests: `php artisan test --filter=Performance`
- [ ] Check slow query log
- [ ] Verify cache hit rate >80%
- [ ] Load test with `ab` or `wrk`

---

## Common Performance Patterns

### Pattern 1: Cache Expensive Queries
```php
// Dashboard stats
public function loadStats(): void
{
    $cacheKey = "tenant:{$this->tenant->id}:dashboard:stats";

    $this->stats = Cache::remember($cacheKey, 60, function () {
        return DB::table('sites')
            ->where('tenant_id', $this->tenant->id)
            ->selectRaw('COUNT(*) as total, SUM(...) as storage')
            ->first();
    });
}

// Invalidate on model changes
protected static function booted(): void
{
    static::saved(fn($site) => Cache::forget("tenant:{$site->tenant_id}:dashboard:stats"));
}
```

### Pattern 2: Eager Load Relationships
```php
// Bad (N+1 queries)
$sites = Site::all();
foreach ($sites as $site) {
    echo $site->vpsServer->hostname;  // Query per site!
}

// Good (2 queries total)
$sites = Site::with('vpsServer')->get();
foreach ($sites as $site) {
    echo $site->vpsServer->hostname;  // No extra query
}
```

### Pattern 3: Parallel External API Calls
```php
// Bad (sequential - 5 × 200ms = 1000ms)
$cpu = $this->queryPrometheus('cpu...');
$mem = $this->queryPrometheus('mem...');
$disk = $this->queryPrometheus('disk...');

// Good (parallel - max 200ms)
$results = Http::pool(fn ($pool) => [
    $pool->as('cpu')->get($prometheusUrl, ['query' => 'cpu...']),
    $pool->as('mem')->get($prometheusUrl, ['query' => 'mem...']),
    $pool->as('disk')->get($prometheusUrl, ['query' => 'disk...']),
]);
```

### Pattern 4: Cache External API Results
```php
public function queryMetrics(string $query, array $options): array
{
    $cacheKey = 'prometheus:' . md5($query . serialize($options));
    $ttl = 15; // 15 seconds for real-time data

    return Cache::remember($cacheKey, $ttl, function () use ($query, $options) {
        return Http::timeout(15)->get($prometheusUrl, [
            'query' => $query,
            ...$options
        ])->json();
    });
}
```

### Pattern 5: Use Database Indexes
```php
// Migration
Schema::table('sites', function (Blueprint $table) {
    // Single column index
    $table->index('status');

    // Composite index (for WHERE tenant_id = ? AND status = ?)
    $table->index(['tenant_id', 'status']);
});

// Query that benefits
Site::where('tenant_id', $tenantId)
    ->where('status', 'active')
    ->get();  // Fast with composite index!
```

---

## Performance Targets

| Operation | Target | Critical Threshold |
|-----------|--------|-------------------|
| Cache read (Redis) | <1ms | <5ms |
| Cache write (Redis) | <1ms | <5ms |
| Database query (indexed) | <20ms | <50ms |
| API endpoint | <150ms | <300ms |
| Dashboard load | <100ms | <200ms |
| External API call | <200ms | <500ms |

---

## Quick Commands

### Monitor Performance
```bash
# Enable query logging
DB::enableQueryLog();
# ... run code ...
dd(DB::getQueryLog());

# Check slow queries
tail -f storage/logs/laravel.log | grep "Slow query"

# Monitor cache
redis-cli monitor

# Load test endpoint
ab -n 100 -c 10 http://localhost:8000/api/v1/sites
```

### Debug Performance Issues
```bash
# Install Telescope (dev only)
composer require laravel/telescope --dev
php artisan telescope:install

# View in browser
http://localhost:8000/telescope/requests

# Clear cache
php artisan cache:clear

# Restart queue
php artisan queue:restart
```

### Benchmark Code
```php
use Illuminate\Support\Benchmark;

Benchmark::dd([
    'Method A' => fn() => $this->methodA(),
    'Method B' => fn() => $this->methodB(),
], iterations: 100);
```

---

## Anti-Patterns to Avoid

### ❌ DON'T: Query in Loops
```php
// Bad - N+1 queries
foreach ($sites as $site) {
    $backups = $site->backups()->count();  // Query!
}

// Good - Single query with aggregation
$backupCounts = SiteBackup::query()
    ->whereIn('site_id', $sites->pluck('id'))
    ->groupBy('site_id')
    ->selectRaw('site_id, COUNT(*) as count')
    ->pluck('count', 'site_id');
```

### ❌ DON'T: Cache Forever
```php
// Bad - stale data
Cache::rememberForever($key, fn() => $data);

// Good - with TTL
Cache::remember($key, 60, fn() => $data);  // 60 seconds
```

### ❌ DON'T: Forget Cache Invalidation
```php
// Bad - cache never updates
Cache::remember('user_count', 3600, fn() => User::count());

// Good - invalidate on changes
User::created(fn() => Cache::forget('user_count'));
User::deleted(fn() => Cache::forget('user_count'));
```

### ❌ DON'T: Use `get()` for Large Datasets
```php
// Bad - loads all 10,000 records into memory
$sites = Site::all();

// Good - paginate
$sites = Site::paginate(20);

// Or use cursor for iteration
foreach (Site::cursor() as $site) {
    // Process one at a time
}
```

---

## Emergency Performance Fixes

### If Dashboard is Slow
```php
// Add this to Overview.php
$cacheKey = "tenant:{$this->tenant->id}:stats";
$this->stats = Cache::remember($cacheKey, 60, function () {
    // ... existing query
});
```

### If Metrics Dashboard is Slow
```php
// Change from sequential to parallel
$results = Http::pool(fn ($pool) => [
    $pool->as('cpu')->timeout(15)->get($url1),
    $pool->as('mem')->timeout(15)->get($url2),
    // ... etc
]);
```

### If API is Slow
```php
// Add caching middleware to routes
Route::middleware(['cache.headers:public;max_age=60'])->group(function () {
    Route::get('/api/v1/sites', [SiteController::class, 'index']);
});
```

### If Database is Slow
```bash
# Check for missing indexes
php artisan migrate:status

# Enable slow query log
DB::listen(function ($query) {
    if ($query->time > 100) {
        Log::warning('Slow query', [
            'sql' => $query->sql,
            'time' => $query->time
        ]);
    }
});
```

---

## Key Files to Optimize

### High Impact
1. `app/Livewire/Dashboard/Overview.php` - Cache stats
2. `app/Livewire/Observability/MetricsDashboard.php` - Parallel queries
3. `app/Services/Integration/ObservabilityAdapter.php` - Cache API results
4. `app/Models/Tenant.php` - Cache tier limits, site counts

### Medium Impact
5. `app/Livewire/Backups/BackupList.php` - Optimize queries
6. `app/Services/Integration/VPSManagerBridge.php` - Connection pooling
7. `app/Http/Controllers/Api/V1/SiteController.php` - Response caching

---

## Testing Performance

### Unit Test
```php
public function test_dashboard_performance()
{
    $start = microtime(true);
    $response = $this->get('/dashboard');
    $duration = (microtime(true) - $start) * 1000;

    $this->assertLessThan(200, $duration, "Dashboard took {$duration}ms");
}
```

### Load Test
```bash
# 100 requests, 10 concurrent
ab -n 100 -c 10 http://localhost:8000/api/v1/sites

# With auth token
ab -n 100 -c 10 \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v1/sites
```

---

## Configuration Reference

### Redis (.env)
```env
CACHE_STORE=redis
QUEUE_CONNECTION=redis
REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
```

### Database (.env)
```env
DB_CONNECTION=mysql  # or pgsql for production
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
```

### Performance (.env)
```env
# Enable query logging in dev
LOG_QUERY_SLOW_THRESHOLD=100  # ms

# Queue workers
QUEUE_WORKERS=4

# Session (use Redis for scale)
SESSION_DRIVER=redis
```

---

## Resources

- **Full Analysis:** `/docs/PERFORMANCE-ANALYSIS.md`
- **Implementation Guide:** `/docs/PERFORMANCE-IMPLEMENTATION-GUIDE.md`
- **Testing Guide:** `/docs/PERFORMANCE-TESTING-GUIDE.md`
- **Executive Summary:** `/docs/PERFORMANCE-EXECUTIVE-SUMMARY.md`

---

## Quick Wins (Do These First)

1. ✅ Switch to Redis cache (4 hours, 50x improvement)
2. ✅ Cache dashboard stats (3 hours, 80% faster)
3. ✅ Parallel Prometheus queries (6 hours, 75% faster)
4. ✅ Add missing indexes (4 hours, 40% faster queries)

**Total: 17 hours for 60-80% overall performance improvement**

---

**Last Updated:** December 29, 2025
