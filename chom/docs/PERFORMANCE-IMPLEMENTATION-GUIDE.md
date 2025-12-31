# CHOM Performance Optimization - Implementation Guide

## Table of Contents
1. [Redis Migration](#1-redis-migration)
2. [Dashboard Caching](#2-dashboard-caching)
3. [Prometheus Query Optimization](#3-prometheus-query-optimization)
4. [Database Query Optimization](#4-database-query-optimization)
5. [SSH Connection Pooling](#5-ssh-connection-pooling)
6. [Monitoring Setup](#6-monitoring-setup)

---

## 1. Redis Migration

### Step 1.1: Install Redis

**Using Docker (Development):**
```bash
docker run -d --name redis \
  -p 6379:6379 \
  redis:7-alpine \
  redis-server --appendonly yes
```

**Using Package Manager (Production):**
```bash
# Ubuntu/Debian
sudo apt-get install redis-server

# Start Redis
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

### Step 1.2: Install PHP Redis Extension

```bash
# Using PECL
pecl install redis
echo "extension=redis.so" | sudo tee -a /etc/php/8.2/cli/php.ini
echo "extension=redis.so" | sudo tee -a /etc/php/8.2/fpm/php.ini

# Or install via package manager
sudo apt-get install php-redis

# Restart PHP-FPM
sudo systemctl restart php8.2-fpm
```

### Step 1.3: Update Configuration

**.env:**
```env
# Cache Configuration
CACHE_STORE=redis
CACHE_PREFIX=chom-cache-

# Queue Configuration
QUEUE_CONNECTION=redis
REDIS_QUEUE=default

# Session Configuration (optional)
SESSION_DRIVER=redis

# Redis Connection
REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_DB=0
REDIS_CACHE_DB=1
```

**config/database.php (verify Redis config):**
```php
'redis' => [
    'client' => env('REDIS_CLIENT', 'phpredis'),

    'options' => [
        'cluster' => env('REDIS_CLUSTER', 'redis'),
        'prefix' => env('REDIS_PREFIX', Str::slug(env('APP_NAME', 'laravel')).'_database_'),
        'persistent' => env('REDIS_PERSISTENT', true),  // Add this
    ],

    'default' => [
        'url' => env('REDIS_URL'),
        'host' => env('REDIS_HOST', '127.0.0.1'),
        'username' => env('REDIS_USERNAME'),
        'password' => env('REDIS_PASSWORD'),
        'port' => env('REDIS_PORT', '6379'),
        'database' => env('REDIS_DB', '0'),
        'read_timeout' => 60,  // Add timeout
        'max_retries' => 3,
        'backoff_algorithm' => 'decorrelated_jitter',
    ],

    'cache' => [
        // Separate DB for cache
        'database' => env('REDIS_CACHE_DB', '1'),
        // ... rest of config
    ],
],
```

### Step 1.4: Test Redis Connection

```bash
# Test Redis
php artisan tinker

# In Tinker:
>>> Cache::put('test', 'value', 60);
>>> Cache::get('test');
# Should return: "value"

>>> Redis::ping();
# Should return: "+PONG"
```

### Step 1.5: Clear Old Cache

```bash
# Clear database cache
php artisan cache:clear

# Clear config cache
php artisan config:clear

# Restart queue workers
php artisan queue:restart
```

**Verification:**
```bash
# Monitor Redis in real-time
redis-cli monitor

# Check Redis keys
redis-cli
127.0.0.1:6379> KEYS *
127.0.0.1:6379> INFO stats
```

---

## 2. Dashboard Caching

### Step 2.1: Update Dashboard Overview Component

**File:** `app/Livewire/Dashboard/Overview.php`

```php
<?php

namespace App\Livewire\Dashboard;

use App\Models\Site;
use App\Models\Tenant;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class Overview extends Component
{
    public ?Tenant $tenant = null;
    public array $stats = [];
    public array $recentSites = [];

    // Cache TTL in seconds
    private const STATS_CACHE_TTL = 60;  // 1 minute
    private const SITES_CACHE_TTL = 300; // 5 minutes

    public function mount(): void
    {
        $user = auth()->user();

        if (!$user) {
            return;
        }

        $this->tenant = $user->currentTenant();

        if ($this->tenant) {
            $this->loadStats();
            $this->loadRecentSites();
        }
    }

    public function loadStats(): void
    {
        if (!$this->tenant) {
            $this->stats = $this->getEmptyStats();
            return;
        }

        try {
            // Cache key with tenant ID
            $cacheKey = "tenant:{$this->tenant->id}:dashboard:stats";

            $this->stats = Cache::remember($cacheKey, self::STATS_CACHE_TTL, function () {
                // Batch all site stats into a single query
                $siteStats = DB::table('sites')
                    ->where('tenant_id', $this->tenant->id)
                    ->selectRaw('
                        COUNT(*) as total_sites,
                        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as active_sites,
                        SUM(CASE WHEN ssl_enabled = 1 AND ssl_expires_at IS NOT NULL AND ssl_expires_at <= ? THEN 1 ELSE 0 END) as ssl_expiring_soon,
                        SUM(storage_used_mb) as total_storage_mb
                    ', ['active', now()->addDays(30)])
                    ->first();

                return [
                    'total_sites' => (int) ($siteStats->total_sites ?? 0),
                    'active_sites' => (int) ($siteStats->active_sites ?? 0),
                    'storage_used_mb' => (int) ($siteStats->total_storage_mb ?? 0),
                    'ssl_expiring_soon' => (int) ($siteStats->ssl_expiring_soon ?? 0),
                ];
            });

        } catch (\Exception $e) {
            Log::error('Failed to load dashboard stats', [
                'tenant_id' => $this->tenant->id,
                'error' => $e->getMessage(),
            ]);

            $this->stats = $this->getEmptyStats();
        }
    }

    public function loadRecentSites(): void
    {
        if (!$this->tenant) {
            $this->recentSites = [];
            return;
        }

        try {
            $cacheKey = "tenant:{$this->tenant->id}:dashboard:recent_sites";

            $this->recentSites = Cache::remember($cacheKey, self::SITES_CACHE_TTL, function () {
                return $this->tenant->sites()
                    ->with('vpsServer:id,hostname')
                    ->orderBy('created_at', 'desc')
                    ->limit(5)
                    ->get()
                    ->map(fn($site) => [
                        'id' => $site->id,
                        'domain' => $site->domain,
                        'status' => $site->status,
                        'ssl_enabled' => $site->ssl_enabled,
                        'created_at' => $site->created_at->diffForHumans(),
                    ])
                    ->toArray();
            });

        } catch (\Exception $e) {
            Log::error('Failed to load recent sites', [
                'tenant_id' => $this->tenant->id,
                'error' => $e->getMessage(),
            ]);

            $this->recentSites = [];
        }
    }

    /**
     * Refresh stats (called manually or via Livewire polling)
     */
    public function refreshStats(): void
    {
        if (!$this->tenant) {
            return;
        }

        // Clear cache to force refresh
        Cache::forget("tenant:{$this->tenant->id}:dashboard:stats");
        Cache::forget("tenant:{$this->tenant->id}:dashboard:recent_sites");

        $this->loadStats();
        $this->loadRecentSites();
    }

    private function getEmptyStats(): array
    {
        return [
            'total_sites' => 0,
            'active_sites' => 0,
            'storage_used_mb' => 0,
            'ssl_expiring_soon' => 0,
        ];
    }

    public function render()
    {
        return view('livewire.dashboard.overview')
            ->layout('layouts.app', ['title' => 'Dashboard']);
    }
}
```

### Step 2.2: Add Cache Invalidation on Model Events

**File:** `app/Models/Site.php`

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

class Site extends Model
{
    // ... existing code ...

    protected static function booted(): void
    {
        // Apply tenant scope automatically to all queries
        static::addGlobalScope('tenant', function ($builder) {
            if (auth()->check() && auth()->user()->currentTenant()) {
                $builder->where('tenant_id', auth()->user()->currentTenant()->id);
            }
        });

        // Cache invalidation on model events
        static::saved(function ($site) {
            self::invalidateTenantCache($site->tenant_id);
        });

        static::deleted(function ($site) {
            self::invalidateTenantCache($site->tenant_id);
        });
    }

    /**
     * Invalidate all tenant caches when sites change
     */
    private static function invalidateTenantCache(string $tenantId): void
    {
        $keys = [
            "tenant:{$tenantId}:dashboard:stats",
            "tenant:{$tenantId}:dashboard:recent_sites",
            "tenant:{$tenantId}:site_count",
        ];

        foreach ($keys as $key) {
            Cache::forget($key);
        }

        // If using cache tags (Redis only):
        // Cache::tags(["tenant:{$tenantId}", "sites"])->flush();
    }
}
```

### Step 2.3: Update Tenant Model Methods

**File:** `app/Models/Tenant.php`

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

class Tenant extends Model
{
    // ... existing code ...

    /**
     * Get current site count (cached)
     */
    public function getSiteCount(): int
    {
        return Cache::remember(
            "tenant:{$this->id}:site_count",
            300, // 5 minutes
            fn() => $this->sites()->count()
        );
    }

    /**
     * Get total storage used in MB (cached)
     */
    public function getStorageUsedMb(): int
    {
        return Cache::remember(
            "tenant:{$this->id}:total_storage_mb",
            300, // 5 minutes
            fn() => (int) $this->sites()->sum('storage_used_mb')
        );
    }

    /**
     * Check if tenant can create more sites (cached)
     */
    public function canCreateSite(): bool
    {
        $maxSites = $this->getMaxSites();

        if ($maxSites === -1) {
            return true; // Unlimited
        }

        $currentCount = $this->getSiteCount();

        return $currentCount < $maxSites;
    }

    /**
     * Get the tier limits for this tenant (cached)
     */
    public function tierLimits()
    {
        return Cache::remember(
            "tenant:{$this->id}:tier_limits",
            86400, // 24 hours (limits rarely change)
            fn() => TierLimit::where('tier', $this->tier)->first()
        );
    }
}
```

---

## 3. Prometheus Query Optimization

### Step 3.1: Install Async HTTP Support

```bash
composer require guzzlehttp/promises
```

### Step 3.2: Update ObservabilityAdapter for Parallel Queries

**File:** `app/Services/Integration/ObservabilityAdapter.php`

Add these methods:

```php
use Illuminate\Support\Facades\Http;
use Illuminate\Http\Client\Pool;
use GuzzleHttp\Promise\Utils;

/**
 * Query multiple metrics in parallel
 */
public function queryMetricsBatch(Tenant $tenant, array $queries, array $options = []): array
{
    $results = [];

    try {
        // Build cache keys for all queries
        $cacheKeys = [];
        foreach ($queries as $name => $query) {
            $cacheKeys[$name] = $this->getMetricsCacheKey($query, $options, $tenant->id);
        }

        // Check cache first
        $cached = Cache::many($cacheKeys);

        // Separate cached and uncached queries
        $uncached = [];
        foreach ($queries as $name => $query) {
            if (isset($cached[$cacheKeys[$name]]) && $cached[$cacheKeys[$name]] !== null) {
                $results[$name] = $cached[$cacheKeys[$name]];
            } else {
                $uncached[$name] = $query;
            }
        }

        // If all queries are cached, return early
        if (empty($uncached)) {
            return $results;
        }

        // Execute uncached queries in parallel
        $responses = Http::pool(function (Pool $pool) use ($uncached, $tenant, $options) {
            $poolRequests = [];

            foreach ($uncached as $name => $query) {
                $scopedQuery = $this->injectTenantScope($query, $tenant->id);

                $poolRequests[$name] = $pool->as($name)
                    ->timeout(15)  // Reduced from 30s
                    ->retry(2, 100) // Retry on failure
                    ->get("{$this->prometheusUrl}/api/v1/query", [
                        'query' => $scopedQuery,
                        'time' => $options['time'] ?? null,
                    ]);
            }

            return $poolRequests;
        });

        // Process responses and cache them
        $ttl = $this->getMetricsCacheTTL($options);

        foreach ($uncached as $name => $query) {
            if (isset($responses[$name]) && $responses[$name]->successful()) {
                $data = $responses[$name]->json();
                $results[$name] = $data;

                // Cache the result
                Cache::put($cacheKeys[$name], $data, $ttl);
            } else {
                $results[$name] = ['status' => 'error', 'error' => 'Query failed'];

                Log::warning('Prometheus parallel query failed', [
                    'query_name' => $name,
                    'status' => $responses[$name]->status() ?? 'unknown',
                ]);
            }
        }

    } catch (\Exception $e) {
        Log::error('Prometheus batch query exception', [
            'error' => $e->getMessage(),
        ]);

        // Return partial results with errors for failed queries
        foreach ($queries as $name => $query) {
            if (!isset($results[$name])) {
                $results[$name] = ['status' => 'error', 'error' => $e->getMessage()];
            }
        }
    }

    return $results;
}

/**
 * Generate cache key for metrics query
 */
private function getMetricsCacheKey(string $query, array $options, string $tenantId): string
{
    $key = implode(':', [
        'prometheus',
        'query',
        md5($query),
        md5(serialize($options)),
        $tenantId,
    ]);

    return $key;
}

/**
 * Get cache TTL based on query options
 */
private function getMetricsCacheTTL(array $options): int
{
    // Cache duration based on query step/resolution
    $step = $options['step'] ?? 15;

    return match(true) {
        $step <= 15 => 15,      // 15s data: cache 15s
        $step <= 60 => 60,      // 1m data: cache 1m
        $step <= 300 => 300,    // 5m data: cache 5m
        default => 900,         // 15m+ data: cache 15m
    };
}

/**
 * Updated queryMetrics with caching
 */
public function queryMetrics(Tenant $tenant, string $query, array $options = []): array
{
    $cacheKey = $this->getMetricsCacheKey($query, $options, $tenant->id);
    $ttl = $this->getMetricsCacheTTL($options);

    return Cache::remember($cacheKey, $ttl, function () use ($tenant, $query, $options) {
        $scopedQuery = $this->injectTenantScope($query, $tenant->id);

        try {
            $response = Http::timeout(15)
                ->retry(2, 100)
                ->get("{$this->prometheusUrl}/api/v1/query", [
                    'query' => $scopedQuery,
                    'time' => $options['time'] ?? null,
                ]);

            if ($response->successful()) {
                return $response->json();
            }

            Log::warning('Prometheus query failed', [
                'query' => $scopedQuery,
                'status' => $response->status(),
            ]);

            return ['status' => 'error', 'error' => $response->body()];

        } catch (\Exception $e) {
            Log::error('Prometheus query exception', [
                'query' => $scopedQuery,
                'error' => $e->getMessage(),
            ]);

            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    });
}
```

### Step 3.3: Update MetricsDashboard to Use Parallel Queries

**File:** `app/Livewire/Observability/MetricsDashboard.php`

```php
public function loadMetrics(): void
{
    $this->loading = true;
    $this->error = null;

    try {
        $tenant = $this->getTenant();
        $adapter = app(ObservabilityAdapter::class);

        $timeRange = $this->getTimeRangeSeconds();
        $step = $this->calculateStep($timeRange);

        // Build site filter
        $siteFilter = '';
        if ($this->siteFilter) {
            $site = $tenant->sites()->find($this->siteFilter);
            if ($site) {
                $siteFilter = ",domain=\"{$site->domain}\"";
            }
        }

        // Define all queries
        $queries = [
            'cpu' => "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"{$siteFilter}}[5m])) * 100)",
            'memory' => "(1 - (node_memory_MemAvailable_bytes{$siteFilter} / node_memory_MemTotal_bytes{$siteFilter})) * 100",
            'disk' => "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\"{$siteFilter}} / node_filesystem_size_bytes{mountpoint=\"/\"{$siteFilter}})) * 100",
            'network' => "irate(node_network_receive_bytes_total{device!=\"lo\"{$siteFilter}}[5m])",
            'http' => "sum(rate(nginx_http_requests_total{$siteFilter}[5m])) by (status)",
        ];

        // Execute all queries in parallel with caching
        $results = $adapter->queryMetricsBatch($tenant, $queries, [
            'step' => $step,
            'start' => now()->subSeconds($timeRange)->timestamp,
            'end' => now()->timestamp,
        ]);

        // Assign results
        $this->cpuData = $results['cpu'] ?? [];
        $this->memoryData = $results['memory'] ?? [];
        $this->diskData = $results['disk'] ?? [];
        $this->networkData = $results['network'] ?? [];
        $this->httpData = $results['http'] ?? [];

    } catch (\Exception $e) {
        Log::error('Failed to load metrics', ['error' => $e->getMessage()]);
        $this->error = 'Failed to load metrics. Please check your observability stack connection.';
    }

    $this->loading = false;
}
```

---

## 4. Database Query Optimization

### Step 4.1: Add Missing Indexes

**Create Migration:**
```bash
php artisan make:migration add_performance_indexes_to_tables
```

**File:** `database/migrations/2025_12_29_000000_add_performance_indexes_to_tables.php`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Add composite index on sites for faster tenant queries
        Schema::table('sites', function (Blueprint $table) {
            $table->index(['tenant_id', 'status'], 'idx_sites_tenant_status');
            $table->index(['tenant_id', 'created_at'], 'idx_sites_tenant_created');
        });

        // Add composite index on site_backups
        Schema::table('site_backups', function (Blueprint $table) {
            $table->index(['site_id', 'created_at'], 'idx_backups_site_created');
            $table->index(['site_id', 'backup_type'], 'idx_backups_site_type');
        });

        // Add index on operations for faster filtering
        Schema::table('operations', function (Blueprint $table) {
            $table->index(['tenant_id', 'status'], 'idx_operations_tenant_status');
            $table->index(['tenant_id', 'created_at'], 'idx_operations_tenant_created');
        });

        // Add index on usage_records for time-based queries
        Schema::table('usage_records', function (Blueprint $table) {
            $table->index(['tenant_id', 'created_at'], 'idx_usage_tenant_created');
        });
    }

    public function down(): void
    {
        Schema::table('sites', function (Blueprint $table) {
            $table->dropIndex('idx_sites_tenant_status');
            $table->dropIndex('idx_sites_tenant_created');
        });

        Schema::table('site_backups', function (Blueprint $table) {
            $table->dropIndex('idx_backups_site_created');
            $table->dropIndex('idx_backups_site_type');
        });

        Schema::table('operations', function (Blueprint $table) {
            $table->dropIndex('idx_operations_tenant_status');
            $table->dropIndex('idx_operations_tenant_created');
        });

        Schema::table('usage_records', function (Blueprint $table) {
            $table->dropIndex('idx_usage_tenant_created');
        });
    }
};
```

**Run Migration:**
```bash
php artisan migrate
```

### Step 4.2: Optimize BackupList Query

**File:** `app/Livewire/Backups/BackupList.php`

Replace lines 241-252 with:

```php
public function render()
{
    try {
        $tenant = $this->getTenant();

        if (!$tenant) {
            return view('livewire.backups.backup-list', [
                'backups' => collect(),
                'sites' => collect(),
                'totalSize' => 0,
            ])->layout('layouts.app', ['title' => 'Backups']);
        }

        // Fetch sites for filter dropdown (cached)
        $sites = Cache::remember(
            "tenant:{$tenant->id}:sites:list",
            300,
            fn() => $tenant->sites()->orderBy('domain')->get(['id', 'domain'])
        );

        // Build optimized backup query using whereHas with better query planning
        $query = SiteBackup::query()
            ->whereHas('site', fn($q) => $q->where('tenant_id', $tenant->id))
            ->with('site:id,domain')
            ->orderBy('created_at', 'desc');

        if ($this->siteFilter) {
            $query->where('site_id', $this->siteFilter);
        }

        if ($this->typeFilter) {
            $query->where('backup_type', $this->typeFilter);
        }

        $backups = $query->paginate(15);

        // Get cached total backup size
        $totalSize = $this->getCachedTotalSize($tenant->id);

        return view('livewire.backups.backup-list', [
            'backups' => $backups,
            'sites' => $sites,
            'totalSize' => $totalSize,
        ])->layout('layouts.app', ['title' => 'Backups']);

    } catch (\Exception $e) {
        Log::error('Failed to load backup list', [
            'error' => $e->getMessage(),
        ]);

        return view('livewire.backups.backup-list', [
            'backups' => collect(),
            'sites' => collect(),
            'totalSize' => 0,
            'error' => 'Failed to load backups. Please try again.',
        ])->layout('layouts.app', ['title' => 'Backups']);
    }
}
```

---

## 5. SSH Connection Pooling

### Step 5.1: Create SSH Connection Pool Service

**File:** `app/Services/Integration/SSHConnectionPool.php`

```php
<?php

namespace App\Services\Integration;

use App\Models\VpsServer;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use phpseclib3\Net\SSH2;
use phpseclib3\Crypt\PublicKeyLoader;

class SSHConnectionPool
{
    private const MAX_IDLE_TIME = 300; // 5 minutes
    private const CACHE_PREFIX = 'ssh_pool:';

    /**
     * Get SSH connection from pool or create new one
     */
    public function get(VpsServer $vps): SSH2
    {
        $cacheKey = self::CACHE_PREFIX . $vps->id;

        // Try to get existing connection from cache
        $connectionData = Cache::get($cacheKey);

        if ($connectionData && $this->isConnectionValid($connectionData['connection'])) {
            Log::debug('SSH connection reused from pool', ['vps' => $vps->hostname]);
            return $connectionData['connection'];
        }

        // Create new connection
        $connection = $this->createConnection($vps);

        // Store in cache with TTL
        Cache::put($cacheKey, [
            'connection' => $connection,
            'created_at' => now(),
        ], self::MAX_IDLE_TIME);

        Log::debug('SSH connection created and cached', ['vps' => $vps->hostname]);

        return $connection;
    }

    /**
     * Release connection back to pool (extends TTL)
     */
    public function release(VpsServer $vps, SSH2 $connection): void
    {
        $cacheKey = self::CACHE_PREFIX . $vps->id;

        if ($this->isConnectionValid($connection)) {
            Cache::put($cacheKey, [
                'connection' => $connection,
                'created_at' => now(),
            ], self::MAX_IDLE_TIME);
        }
    }

    /**
     * Remove connection from pool
     */
    public function disconnect(VpsServer $vps): void
    {
        $cacheKey = self::CACHE_PREFIX . $vps->id;

        $connectionData = Cache::get($cacheKey);

        if ($connectionData) {
            try {
                $connectionData['connection']->disconnect();
            } catch (\Exception $e) {
                Log::warning('Error disconnecting SSH', ['error' => $e->getMessage()]);
            }

            Cache::forget($cacheKey);
        }
    }

    /**
     * Create new SSH connection
     */
    private function createConnection(VpsServer $vps): SSH2
    {
        $ssh = new SSH2($vps->ip_address, 22);
        $ssh->setTimeout(120);

        $keyPath = config('chom.ssh_key_path', storage_path('app/ssh/chom_deploy_key'));

        if (!file_exists($keyPath)) {
            throw new \RuntimeException("SSH key not found at: {$keyPath}");
        }

        $this->validateSshKeyPermissions($keyPath);

        $key = PublicKeyLoader::load(file_get_contents($keyPath));

        if (!$ssh->login('root', $key)) {
            throw new \RuntimeException("SSH authentication failed for VPS: {$vps->hostname}");
        }

        Log::info('SSH connected', ['vps' => $vps->hostname, 'ip' => $vps->ip_address]);

        return $ssh;
    }

    /**
     * Check if connection is still valid
     */
    private function isConnectionValid(SSH2 $ssh): bool
    {
        try {
            // Test connection with simple command
            $result = $ssh->exec('echo "test"');
            return $result === "test\n" || $result === "test";
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Validate SSH key file permissions
     */
    private function validateSshKeyPermissions(string $keyPath): void
    {
        $perms = fileperms($keyPath) & 0777;

        if ($perms !== 0600 && $perms !== 0400) {
            throw new \RuntimeException(
                "SSH key at {$keyPath} has insecure permissions (" . sprintf('0%o', $perms) . "). " .
                "Expected 0600 or 0400. Run: chmod 600 {$keyPath}"
            );
        }
    }

    /**
     * Clear all connections from pool
     */
    public function clearAll(): void
    {
        // Note: This is a simplified version
        // In production, you'd want to maintain a registry of all connection keys
        Log::info('Clearing all SSH connections from pool');
        // Implementation depends on your caching strategy
    }
}
```

### Step 5.2: Update VPSManagerBridge to Use Connection Pool

**File:** `app/Services/Integration/VPSManagerBridge.php`

```php
<?php

namespace App\Services\Integration;

use App\Models\VpsServer;
use Illuminate\Support\Facades\Log;
use phpseclib3\Net\SSH2;

class VPSManagerBridge
{
    private ?SSH2 $ssh = null;
    private string $vpsmanagerPath = '/opt/vpsmanager/bin/vpsmanager';
    private int $timeout = 120;

    public function __construct(
        private SSHConnectionPool $connectionPool
    ) {}

    /**
     * Connect to a VPS server via SSH (using connection pool)
     */
    public function connect(VpsServer $vps): void
    {
        // Get connection from pool
        $this->ssh = $this->connectionPool->get($vps);
    }

    /**
     * Disconnect from current VPS (return to pool)
     */
    public function disconnect(VpsServer $vps = null): void
    {
        if ($this->ssh && $vps) {
            // Return connection to pool instead of disconnecting
            $this->connectionPool->release($vps, $this->ssh);
        }

        $this->ssh = null;
    }

    /**
     * Execute a VPSManager command on the remote VPS
     */
    public function execute(VpsServer $vps, string $command, array $args = []): array
    {
        $this->connect($vps);

        // Build command with arguments
        $fullCommand = $this->vpsmanagerPath . ' ' . $command;

        foreach ($args as $key => $value) {
            if (is_bool($value)) {
                if ($value) {
                    $fullCommand .= " --{$key}";
                }
            } elseif (is_numeric($key)) {
                $fullCommand .= ' ' . escapeshellarg($value);
            } else {
                $fullCommand .= " --{$key}=" . escapeshellarg($value);
            }
        }

        $fullCommand .= ' --format=json 2>&1';

        Log::info('VPSManager command', [
            'vps' => $vps->hostname,
            'command' => $command,
        ]);

        $output = $this->ssh->exec($fullCommand);
        $exitCode = $this->ssh->getExitStatus() ?? 0;

        // Return connection to pool (don't disconnect)
        $this->disconnect($vps);

        $result = [
            'success' => $exitCode === 0,
            'exit_code' => $exitCode,
            'output' => $output,
            'data' => null,
        ];

        if (!empty($output)) {
            $jsonData = $this->parseJsonOutput($output);
            if ($jsonData !== null) {
                $result['data'] = $jsonData;
            }
        }

        Log::info('VPSManager result', [
            'vps' => $vps->hostname,
            'command' => $command,
            'success' => $result['success'],
        ]);

        return $result;
    }

    // ... rest of the methods remain the same ...
}
```

---

## 6. Monitoring Setup

### Step 6.1: Install Laravel Telescope (Development)

```bash
composer require laravel/telescope --dev
php artisan telescope:install
php artisan migrate
```

**Configuration:** `config/telescope.php`

```php
'enabled' => env('TELESCOPE_ENABLED', env('APP_DEBUG')),

'storage' => [
    'database' => [
        'connection' => env('DB_CONNECTION', 'mysql'),
        'chunk' => 1000,
    ],
],

'path' => env('TELESCOPE_PATH', 'telescope'),

// Enable query monitoring
'watchers' => [
    Watchers\QueryWatcher::class => [
        'enabled' => env('TELESCOPE_QUERY_WATCHER', true),
        'slow' => 100, // Log queries taking more than 100ms
    ],

    Watchers\RequestWatcher::class => [
        'enabled' => env('TELESCOPE_REQUEST_WATCHER', true),
        'size_limit' => 64, // KB
    ],

    Watchers\CacheWatcher::class => [
        'enabled' => env('TELESCOPE_CACHE_WATCHER', true),
    ],

    Watchers\JobWatcher::class => [
        'enabled' => env('TELESCOPE_JOB_WATCHER', true),
    ],

    Watchers\ClientRequestWatcher::class => [
        'enabled' => env('TELESCOPE_CLIENT_REQUEST_WATCHER', true),
    ],
],
```

### Step 6.2: Add Performance Monitoring Middleware

**File:** `app/Http/Middleware/PerformanceMonitor.php`

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class PerformanceMonitor
{
    public function handle(Request $request, Closure $next)
    {
        $startTime = microtime(true);
        $startMemory = memory_get_usage();

        $response = $next($request);

        $duration = (microtime(true) - $startTime) * 1000;
        $memory = (memory_get_usage() - $startMemory) / 1024 / 1024;

        // Log slow requests (>1 second)
        if ($duration > 1000) {
            Log::warning('Slow request detected', [
                'url' => $request->fullUrl(),
                'method' => $request->method(),
                'duration_ms' => round($duration, 2),
                'memory_mb' => round($memory, 2),
                'user_id' => auth()->id(),
                'tenant_id' => auth()->user()?->currentTenant()?->id,
            ]);
        }

        // Add performance headers in development
        if (config('app.debug')) {
            $response->headers->set('X-Debug-Time', round($duration, 2) . 'ms');
            $response->headers->set('X-Debug-Memory', round($memory, 2) . 'MB');
            $response->headers->set('X-Debug-Queries', \DB::getQueryLog() ? count(\DB::getQueryLog()) : 0);
        }

        return $response;
    }
}
```

**Register Middleware:** `bootstrap/app.php`

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->append(\App\Http\Middleware\PerformanceMonitor::class);
})
```

### Step 6.3: Enable Slow Query Logging

**File:** `app/Providers/AppServiceProvider.php`

```php
<?php

namespace App\Providers;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // Log slow queries (>100ms)
        DB::listen(function ($query) {
            if ($query->time > 100) {
                Log::warning('Slow query detected', [
                    'sql' => $query->sql,
                    'bindings' => $query->bindings,
                    'time_ms' => $query->time,
                    'connection' => $query->connectionName,
                ]);
            }
        });

        // Enable query log in local environment
        if ($this->app->environment('local')) {
            DB::enableQueryLog();
        }
    }
}
```

### Step 6.4: Track External API Performance

**File:** `app/Services/Integration/ObservabilityMetrics.php`

```php
<?php

namespace App\Services\Integration;

use Illuminate\Support\Facades\Log;

class ObservabilityMetrics
{
    /**
     * Track external API query performance
     */
    public static function track(string $service, string $operation, callable $callback)
    {
        $start = microtime(true);

        try {
            $result = $callback();
            $duration = (microtime(true) - $start) * 1000;

            Log::info("External API query", [
                'service' => $service,
                'operation' => $operation,
                'duration_ms' => round($duration, 2),
                'status' => 'success',
            ]);

            // Log slow external API calls (>500ms)
            if ($duration > 500) {
                Log::warning("Slow external API call", [
                    'service' => $service,
                    'operation' => $operation,
                    'duration_ms' => round($duration, 2),
                ]);
            }

            return $result;

        } catch (\Exception $e) {
            $duration = (microtime(true) - $start) * 1000;

            Log::error("External API query failed", [
                'service' => $service,
                'operation' => $operation,
                'duration_ms' => round($duration, 2),
                'error' => $e->getMessage(),
            ]);

            throw $e;
        }
    }
}
```

**Usage in ObservabilityAdapter:**

```php
use App\Services\Integration\ObservabilityMetrics;

public function queryMetrics(Tenant $tenant, string $query, array $options = []): array
{
    return ObservabilityMetrics::track('prometheus', 'query', function () use ($tenant, $query, $options) {
        // ... existing query logic
    });
}
```

---

## Testing Performance Improvements

### Test 1: Cache Performance

```bash
# Test cache speed
php artisan tinker

# Set value
>>> $start = microtime(true);
>>> Cache::put('test', str_repeat('x', 10000), 60);
>>> $write_time = (microtime(true) - $start) * 1000;
>>> echo "Write: {$write_time}ms\n";

# Get value
>>> $start = microtime(true);
>>> $value = Cache::get('test');
>>> $read_time = (microtime(true) - $start) * 1000;
>>> echo "Read: {$read_time}ms\n";
```

**Expected:**
- Database cache: 10-50ms read/write
- Redis cache: <1ms read/write

### Test 2: Parallel HTTP Requests

Create a test route to compare sequential vs parallel:

```php
// routes/web.php (for testing only)
Route::get('/test/parallel', function () {
    $urls = [
        'http://localhost:9090/-/healthy',
        'http://localhost:3100/ready',
        'http://localhost:3000/api/health',
    ];

    // Sequential
    $start = microtime(true);
    foreach ($urls as $url) {
        Http::timeout(5)->get($url);
    }
    $sequential_time = (microtime(true) - $start) * 1000;

    // Parallel
    $start = microtime(true);
    Http::pool(fn ($pool) => array_map(
        fn($url) => $pool->timeout(5)->get($url),
        $urls
    ));
    $parallel_time = (microtime(true) - $start) * 1000;

    return [
        'sequential_ms' => round($sequential_time, 2),
        'parallel_ms' => round($parallel_time, 2),
        'improvement' => round(($sequential_time / $parallel_time), 2) . 'x faster',
    ];
});
```

### Test 3: Dashboard Performance

```bash
# Before optimization
time curl http://localhost:8000/dashboard

# After optimization (with cached data)
time curl http://localhost:8000/dashboard
```

Monitor with Telescope:
- http://localhost:8000/telescope/requests

Look for:
- Request duration reduction
- Query count reduction
- Cache hit ratio increase

---

## Rollback Plan

If any optimization causes issues:

### Redis Rollback

```env
# Revert to database cache/queue
CACHE_STORE=database
QUEUE_CONNECTION=database
SESSION_DRIVER=database
```

```bash
php artisan config:clear
php artisan cache:clear
php artisan queue:restart
```

### Cache Rollback

To disable specific caches, wrap in feature flag:

```php
if (config('app.features.dashboard_cache', true)) {
    $this->stats = Cache::remember(...);
} else {
    $this->stats = $this->loadStatsDirectly();
}
```

### Index Rollback

```bash
# Rollback specific migration
php artisan migrate:rollback --step=1
```

---

## Next Steps

1. Deploy Phase 1 (Redis migration) to staging
2. Monitor cache hit rates and performance metrics
3. Deploy Phase 2 (caching) incrementally
4. Set up load testing to verify improvements
5. Deploy to production with feature flags
6. Monitor for 1 week before proceeding to next phase

---

**Implementation Checklist:**

- [ ] Redis server installed and running
- [ ] PHP Redis extension installed
- [ ] .env updated with Redis configuration
- [ ] Cache migrated to Redis and tested
- [ ] Queue migrated to Redis and tested
- [ ] Dashboard caching implemented
- [ ] Cache invalidation working
- [ ] Parallel Prometheus queries implemented
- [ ] Database indexes created
- [ ] SSH connection pooling implemented
- [ ] Monitoring middleware added
- [ ] Telescope installed (development)
- [ ] Performance baselines recorded
- [ ] Load testing completed
- [ ] Documentation updated

