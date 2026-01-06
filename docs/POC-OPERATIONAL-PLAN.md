# CHOM PoC Operational Excellence Plan

**Target**: 2-Host Proof-of-Concept (CHOM-APP + OBSERVABILITY)
**Future-Ready**: Architecture extends to 3-4 hosts when adding CHOM-STORAGE
**Focus**: Self-Healing, Background Workers, API Resilience, Cross-Host Communication Patterns, Quick Wins
**Constraint**: NO multi-server HA complexity (no load balancers, no database replication)

**Why 2 Hosts?**: Establish realistic multi-host communication patterns (circuit breakers, graceful degradation, cross-host deployment) that will extend to CHOM-STORAGE hosts without re-architecting.

---

## ARCHITECTURE OVERVIEW (PoC - 2 Hosts)

```
┌─────────────────────────────────────────────────────────────────┐
│ HOST 1: CHOM Application Server (chom-app)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐        │
│  │   Nginx     │  │  PHP-FPM     │  │ Queue Workers  │        │
│  │  (Web)      │  │  (App)       │  │  (Async Jobs)  │        │
│  │             │  │              │  │                │        │
│  │ Port 80/443 │  │ Unix Socket  │  │ 3 Workers      │        │
│  └─────────────┘  └──────────────┘  └────────────────┘        │
│                                                                 │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐        │
│  │ PostgreSQL  │  │    Redis     │  │ node_exporter  │        │
│  │  (Data)     │  │ (Cache/Queue)│  │ (Metrics)      │        │
│  │             │  │              │  │                │        │
│  │ Port 5432   │  │ Port 6379    │  │ Port 9100      │        │
│  └─────────────┘  └──────────────┘  └────────────────┘        │
│                                                                 │
│  Exports metrics to observability host via HTTPS               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTPS (Prometheus scrape)
                            │ HTTPS (Loki push)
                            │
┌─────────────────────────────────────────────────────────────────┐
│ HOST 2: Observability Server (observability)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐       │
│  │ Prometheus   │  │    Loki      │  │   Grafana      │       │
│  │ (Metrics DB) │  │  (Logs DB)   │  │  (Dashboard)   │       │
│  │              │  │              │  │                │       │
│  │ Port 9090    │  │ Port 3100    │  │ Port 3000      │       │
│  └──────────────┘  └──────────────┘  └────────────────┘       │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                           │
│  │Alertmanager  │  │    Nginx     │                           │
│  │  (Alerts)    │  │ (Reverse     │                           │
│  │              │  │  Proxy)      │                           │
│  │ Port 9093    │  │ Port 80/443  │                           │
│  └──────────────┘  └──────────────┘                           │
│                                                                 │
│  Access via chom-app proxy ONLY (no direct user access)        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTPS (metrics scrape)
                            │
┌─────────────────────────────────────────────────────────────────┐
│ Customer VPS Servers (customer-vps-1, customer-vps-2, ...)     │
├─────────────────────────────────────────────────────────────────┤
│  Per-site Unix users  │  VPSManager  │  node_exporter          │
│                       │  (SSH only)  │  (Port 9100)            │
└─────────────────────────────────────────────────────────────────┘
```

### Network Communication

**chom-app → observability**:
- Prometheus pulls metrics from chom-app:9100 (node_exporter)
- Loki receives logs pushed from chom-app
- Alertmanager sends alerts back to chom-app webhooks

**chom-app → customer-vps**:
- SSH connections (port 22) from chom-app to customer VPS servers
- Prometheus scrapes customer VPS node_exporter (port 9100)

**Users → chom-app**:
- HTTPS (port 443) for web interface
- All observability queries proxied through Laravel (NO direct access to observability host)

### Firewall Rules (PoC)

**chom-app (Host 1)**:
```bash
# Inbound
Allow: 80/tcp, 443/tcp (from anywhere)  # Web traffic
Allow: 22/tcp (from admin IPs only)     # SSH management

# Outbound
Allow: 443/tcp to observability host    # Query Prometheus/Loki/Grafana
Allow: 22/tcp to customer VPS servers   # SSH to managed servers
Allow: 9100/tcp to customer VPS servers # Scrape metrics

# Deny all other inbound traffic
```

**observability (Host 2)**:
```bash
# Inbound
Allow: 9100/tcp from observability      # Prometheus scrape chom-app metrics
Allow: 3100/tcp from chom-app           # Loki receive logs
Allow: 9090/tcp from chom-app           # Prometheus queries (proxy)
Allow: 3000/tcp from chom-app           # Grafana queries (proxy)
Allow: 9093/tcp from chom-app           # Alertmanager webhooks
Allow: 22/tcp (from admin IPs only)     # SSH management

# Outbound
Allow: 9100/tcp to customer VPS servers # Scrape customer VPS metrics
Allow: 443/tcp to chom-app              # Alert webhooks

# Deny all other inbound traffic (NO direct user access)
```

**customer-vps (Managed Servers)**:
```bash
# Inbound
Allow: 80/tcp, 443/tcp (from anywhere)  # Customer websites
Allow: 22/tcp from chom-app only        # SSH from chom-app
Allow: 9100/tcp from observability      # Metrics scraping

# Deny all other inbound traffic
```

---

## 1. SELF-HEALING MECHANISMS (PoC-Appropriate)

### 1.1 Systemd Watchdog Auto-Restart

**Purpose**: Automatically restart crashed services without manual intervention

**Implementation**:

```ini
# /etc/systemd/system/chom-worker.service
[Unit]
Description=CHOM Queue Worker
After=network.target postgresql.service redis.service

[Service]
Type=notify
User=www-data
Group=www-data
WorkingDirectory=/var/www/chom/current
ExecStart=/usr/bin/php artisan queue:work --sleep=3 --tries=3 --timeout=180
Restart=always
RestartSec=10s

# Watchdog configuration
WatchdogSec=30s
NotifyAccess=all

# Resource limits
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
```

**Expected Behavior**:
- Service crashes → systemd waits 10 seconds → auto-restart
- Memory exceeds 512MB → systemd kills and restarts
- CPU exceeds 50% → throttled but not killed

---

### 1.2 SSH Operation Retry Logic

**Purpose**: Handle temporary SSH failures without user intervention

**Implementation**: Update `app/Services/Integration/VPSManagerBridge.php`

```php
public function executeWithRetry(
    VpsServer $vps,
    string $command,
    array $args = [],
    int $maxAttempts = 3
): array {
    $attempt = 0;
    $lastException = null;

    while ($attempt < $maxAttempts) {
        try {
            return $this->execute($vps, $command, $args);
        } catch (\Exception $e) {
            $lastException = $e;
            $attempt++;

            if ($attempt < $maxAttempts) {
                // Exponential backoff: 2^attempt seconds + random jitter
                $backoffSeconds = (2 ** $attempt) + random_int(0, 1000) / 1000;

                Log::warning('SSH operation failed, retrying', [
                    'vps' => $vps->hostname,
                    'command' => $command,
                    'attempt' => $attempt,
                    'backoff' => $backoffSeconds,
                    'error' => $e->getMessage(),
                ]);

                sleep($backoffSeconds);
            }
        }
    }

    throw new \RuntimeException(
        "SSH operation failed after {$maxAttempts} attempts: {$lastException->getMessage()}",
        0,
        $lastException
    );
}
```

**Retry Schedule**:
- Attempt 1: Immediate
- Attempt 2: Wait 2-3 seconds
- Attempt 3: Wait 4-5 seconds
- After 3 attempts: Throw exception, move to DLQ

---

### 1.3 Circuit Breaker for SSH Connections

**Purpose**: Fail fast when VPS is down, prevent cascading failures

**Implementation**: Create `app/Services/CircuitBreaker.php`

```php
<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;

class CircuitBreaker
{
    private const STATE_CLOSED = 'closed';   // Normal operation
    private const STATE_OPEN = 'open';       // Failing, reject requests
    private const STATE_HALF_OPEN = 'half_open'; // Testing recovery

    private string $serviceName;
    private int $failureThreshold;
    private int $timeoutSeconds;

    public function __construct(
        string $serviceName,
        int $failureThreshold = 5,
        int $timeoutSeconds = 60
    ) {
        $this->serviceName = $serviceName;
        $this->failureThreshold = $failureThreshold;
        $this->timeoutSeconds = $timeoutSeconds;
    }

    public function call(callable $callback)
    {
        $state = $this->getState();

        if ($state === self::STATE_OPEN) {
            if ($this->shouldAttemptReset()) {
                $this->setState(self::STATE_HALF_OPEN);
            } else {
                throw new \RuntimeException(
                    "Circuit breaker OPEN for {$this->serviceName}. Service unavailable."
                );
            }
        }

        try {
            $result = $callback();
            $this->recordSuccess();
            return $result;
        } catch (\Exception $e) {
            $this->recordFailure();
            throw $e;
        }
    }

    private function recordFailure(): void
    {
        $key = "circuit_breaker:{$this->serviceName}:failures";
        $failures = Cache::increment($key);
        Cache::put($key, $failures, now()->addMinutes(5));

        if ($failures >= $this->failureThreshold) {
            $this->setState(self::STATE_OPEN);
            Cache::put(
                "circuit_breaker:{$this->serviceName}:opened_at",
                now(),
                now()->addMinutes(10)
            );
        }
    }

    private function recordSuccess(): void
    {
        Cache::forget("circuit_breaker:{$this->serviceName}:failures");
        $this->setState(self::STATE_CLOSED);
    }

    private function shouldAttemptReset(): bool
    {
        $openedAt = Cache::get("circuit_breaker:{$this->serviceName}:opened_at");

        if (!$openedAt) {
            return true;
        }

        return now()->diffInSeconds($openedAt) >= $this->timeoutSeconds;
    }

    private function getState(): string
    {
        return Cache::get(
            "circuit_breaker:{$this->serviceName}:state",
            self::STATE_CLOSED
        );
    }

    private function setState(string $state): void
    {
        Cache::put(
            "circuit_breaker:{$this->serviceName}:state",
            $state,
            now()->addHours(1)
        );
    }
}
```

**Usage in VPSManagerBridge**:

```php
public function execute(VpsServer $vps, string $command, array $args = []): array
{
    $circuitBreaker = new CircuitBreaker("vps:{$vps->id}", 5, 60);

    return $circuitBreaker->call(function () use ($vps, $command, $args) {
        return $this->executeWithRetry($vps, $command, $args);
    });
}
```

**Behavior**:
- 5 failures within 5 minutes → Circuit OPEN
- Circuit OPEN → Reject all requests for 60 seconds
- After 60 seconds → Allow 1 test request (HALF_OPEN)
- Test succeeds → Circuit CLOSED (normal operation)
- Test fails → Circuit OPEN for another 60 seconds

---

### 1.4 Health Check Automation

**Purpose**: Detect and restart unhealthy services automatically

**Implementation**: Create `/usr/local/bin/chom-health-check.sh`

```bash
#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/chom/health-checks.log"
ALERT_THRESHOLD=3  # Restart after 3 consecutive failures

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_service() {
    local service=$1
    local check_command=$2

    if eval "$check_command" &>/dev/null; then
        log "✓ $service is healthy"
        # Reset failure counter
        redis-cli DEL "health:${service}:failures" &>/dev/null || true
        return 0
    else
        log "✗ $service is unhealthy"

        # Increment failure counter
        failures=$(redis-cli INCR "health:${service}:failures" 2>/dev/null || echo "0")

        if [ "$failures" -ge "$ALERT_THRESHOLD" ]; then
            log "⚠ $service failed $failures times, restarting..."
            systemctl restart "$service"
            redis-cli DEL "health:${service}:failures" &>/dev/null || true
        fi

        return 1
    fi
}

# Check application health endpoint
check_service "chom-app" "curl -sf http://localhost/health"

# Check PostgreSQL
check_service "postgresql" "pg_isready -U chom"

# Check Redis
check_service "redis" "redis-cli ping"

# Check PHP-FPM
check_service "php8.2-fpm" "systemctl is-active php8.2-fpm"

# Check Queue Workers
check_service "chom-worker@1" "systemctl is-active chom-worker@1"

log "Health check completed"
```

**Cron Schedule**: `/etc/cron.d/chom-health-check`

```cron
*/5 * * * * root /usr/local/bin/chom-health-check.sh
```

**Expected Behavior**:
- Runs every 5 minutes
- Service fails health check 3 times (15 minutes) → Auto-restart
- Logs all actions to `/var/log/chom/health-checks.log`

---

### 1.5 Stuck Job Killer

**Purpose**: Detect and clean up jobs stuck for >1 hour

**Implementation**: Create `app/Console/Commands/KillStuckJobs.php`

```php
<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class KillStuckJobs extends Command
{
    protected $signature = 'queue:kill-stuck-jobs {--timeout=3600}';
    protected $description = 'Kill jobs running longer than timeout (default 1 hour)';

    public function handle()
    {
        $timeout = (int) $this->option('timeout');
        $threshold = now()->subSeconds($timeout);

        $stuckJobs = DB::table('jobs')
            ->where('reserved_at', '<', $threshold)
            ->whereNotNull('reserved_at')
            ->get();

        foreach ($stuckJobs as $job) {
            $this->warn("Killing stuck job: {$job->id} (reserved at {$job->reserved_at})");

            // Move to failed_jobs table
            DB::table('failed_jobs')->insert([
                'uuid' => $job->uuid ?? \Illuminate\Support\Str::uuid(),
                'connection' => 'database',
                'queue' => $job->queue,
                'payload' => $job->payload,
                'exception' => 'Job killed after timeout',
                'failed_at' => now(),
            ]);

            // Delete from jobs table
            DB::table('jobs')->where('id', $job->id)->delete();
        }

        $this->info("Killed {$stuckJobs->count()} stuck jobs");
    }
}
```

**Schedule**: `app/Console/Kernel.php`

```php
protected function schedule(Schedule $schedule)
{
    $schedule->command('queue:kill-stuck-jobs')->everyFifteenMinutes();
}
```

---

### 1.6 Memory Leak Detection & Auto-Restart

**Purpose**: Restart PHP-FPM if memory usage exceeds 95% for 10 minutes

**Implementation**: `/usr/local/bin/chom-memory-monitor.sh`

```bash
#!/bin/bash
set -euo pipefail

MEMORY_THRESHOLD=95  # Percentage
CONSECUTIVE_CHECKS=2  # 2 checks * 5 min = 10 min
COUNTER_FILE="/var/run/chom-memory-counter"

current_memory=$(free | grep Mem | awk '{print int($3/$2 * 100)}')

if [ "$current_memory" -ge "$MEMORY_THRESHOLD" ]; then
    # Increment counter
    if [ -f "$COUNTER_FILE" ]; then
        counter=$(cat "$COUNTER_FILE")
        counter=$((counter + 1))
    else
        counter=1
    fi

    echo "$counter" > "$COUNTER_FILE"

    logger -t chom-memory "Memory usage at ${current_memory}% (threshold: ${MEMORY_THRESHOLD}%) - Check ${counter}/${CONSECUTIVE_CHECKS}"

    if [ "$counter" -ge "$CONSECUTIVE_CHECKS" ]; then
        logger -t chom-memory "CRITICAL: Restarting PHP-FPM due to sustained high memory"
        systemctl restart php8.2-fpm
        rm -f "$COUNTER_FILE"
    fi
else
    # Reset counter
    rm -f "$COUNTER_FILE"
fi
```

**Cron Schedule**:

```cron
*/5 * * * * root /usr/local/bin/chom-memory-monitor.sh
```

---

### 1.7 Cross-Host Network Resilience

**Purpose**: Handle observability host being unreachable without affecting chom-app functionality

**Implementation**: Update `app/Services/Integration/ObservabilityAdapter.php`

```php
private function isObservabilityReachable(): bool
{
    $cacheKey = 'observability:reachable';

    // Check cached status (avoid hammering unreachable host)
    $cached = Cache::get($cacheKey);
    if ($cached !== null) {
        return $cached;
    }

    try {
        $response = Http::timeout(2)->get("{$this->prometheusUrl}/-/healthy");
        $isReachable = $response->successful();

        // Cache result for 30 seconds
        Cache::put($cacheKey, $isReachable, now()->addSeconds(30));

        return $isReachable;
    } catch (\Exception $e) {
        // Cache failure for 30 seconds to prevent repeated attempts
        Cache::put($cacheKey, false, now()->addSeconds(30));
        return false;
    }
}

public function queryMetrics(Tenant $tenant, string $query, array $options = []): array
{
    // Fail fast if observability host is down
    if (!$this->isObservabilityReachable()) {
        Log::warning('Observability host unreachable, using cached data');

        $cacheKey = "metrics:{$tenant->id}:" . md5($query);
        $cached = Cache::get($cacheKey);

        if ($cached) {
            return array_merge($cached, [
                '_cached' => true,
                '_warning' => 'Observability host unreachable'
            ]);
        }

        return [
            'status' => 'error',
            'error' => 'Observability service temporarily unavailable'
        ];
    }

    // Normal query with circuit breaker
    $circuitBreaker = new CircuitBreaker('observability', 5, 60);

    return $circuitBreaker->call(function () use ($tenant, $query, $options) {
        return $this->queryMetricsDirect($query);
    });
}
```

**Expected Behavior**:
- Observability host unreachable → Return cached data immediately
- No repeated connection attempts (cached failure status for 30s)
- chom-app continues serving web requests normally
- Users see stale metrics with warning message

**Health Check Update**: `/usr/local/bin/chom-health-check.sh`

```bash
# Add observability connectivity check
check_service "observability-connection" "curl -sf --max-time 2 https://${OBSERVABILITY_HOST}/-/healthy"

# NOTE: Non-critical - don't restart services if observability is down
# Only log the failure for monitoring
```

---

## 2. BACKGROUND WORKERS (2-Host Architecture)

### 2.1 Queue Configuration

**Purpose**: Move long-running SSH operations off web requests

**Implementation**: `config/queue.php`

```php
'connections' => [
    'database' => [
        'driver' => 'database',
        'table' => 'jobs',
        'queue' => 'default',
        'retry_after' => 180,  // 3 minutes
        'after_commit' => true,
    ],
],

'failed' => [
    'driver' => 'database-uuids',
    'database' => 'pgsql',
    'table' => 'failed_jobs',
],

// Priority queues (highest to lowest)
'priorities' => ['critical', 'high', 'default', 'low', 'batch'],
```

---

### 2.2 Systemd Worker Services

**Purpose**: Run 3 queue workers with auto-restart

**Implementation**: `/etc/systemd/system/chom-worker@.service`

```ini
[Unit]
Description=CHOM Queue Worker %i
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/chom/current

# Worker command with priority support
ExecStart=/usr/bin/php artisan queue:work \
    --queue=critical,high,default,low,batch \
    --sleep=3 \
    --tries=3 \
    --timeout=180 \
    --max-jobs=1000 \
    --max-time=3600

# Auto-restart on failure
Restart=always
RestartSec=10s

# Resource limits per worker
MemoryMax=256M
CPUQuota=33%

# Graceful shutdown
TimeoutStopSec=60
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
```

**Enable 3 workers**:

```bash
systemctl enable chom-worker@{1,2,3}.service
systemctl start chom-worker@{1,2,3}.service
```

---

### 2.3 Job Retry Policies

**Purpose**: Different retry strategies per job type

**Implementation**: Create base job class `app/Jobs/RetryableJob.php`

```php
<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

abstract class RetryableJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    // Default values (can be overridden in child classes)
    public $tries = 3;
    public $timeout = 180;
    public $maxExceptions = 3;

    /**
     * Calculate exponential backoff delay.
     */
    public function backoff(): array
    {
        return [30, 60, 180];  // Wait 30s, then 60s, then 180s
    }

    /**
     * Determine if job should be retried based on exception.
     */
    public function shouldRetry(\Throwable $exception): bool
    {
        // Retry on temporary failures
        if ($exception instanceof \Illuminate\Http\Client\ConnectionException) {
            return true;
        }

        if ($exception instanceof \RuntimeException &&
            str_contains($exception->getMessage(), 'SSH')) {
            return true;
        }

        // Don't retry on permanent failures
        if ($exception instanceof \InvalidArgumentException) {
            return false;
        }

        return true;
    }
}
```

**Example Job**: `app/Jobs/VPS/ProvisionSiteJob.php`

```php
<?php

namespace App\Jobs\VPS;

use App\Jobs\RetryableJob;
use App\Models\Site;
use App\Services\Integration\VPSManagerBridge;

class ProvisionSiteJob extends RetryableJob
{
    public $tries = 5;  // Critical operation, retry more
    public $timeout = 300;  // 5 minutes for site provisioning
    public $queue = 'high';  // High priority

    public function __construct(
        public Site $site,
        public array $config
    ) {}

    public function handle(VPSManagerBridge $vpsManager): void
    {
        $vpsManager->execute(
            $this->site->vpsServer,
            'site:create',
            [
                $this->site->domain,
                $this->config['type'] ?? 'wordpress',
            ]
        );

        $this->site->update(['status' => 'active']);
    }

    public function failed(\Throwable $exception): void
    {
        $this->site->update([
            'status' => 'failed',
            'failure_reason' => $exception->getMessage(),
        ]);
    }
}
```

---

### 2.4 Dead Letter Queue Handling

**Purpose**: Analyze and alert on permanently failed jobs

**Implementation**: `app/Console/Commands/AnalyzeFailedJobs.php`

```php
<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class AnalyzeFailedJobs extends Command
{
    protected $signature = 'queue:analyze-failures';
    protected $description = 'Analyze failed jobs and send alerts';

    public function handle()
    {
        $failures = DB::table('failed_jobs')
            ->where('failed_at', '>', now()->subDay())
            ->get();

        $grouped = $failures->groupBy(function ($job) {
            $payload = json_decode($job->payload, true);
            return $payload['displayName'] ?? 'Unknown';
        });

        foreach ($grouped as $jobType => $jobs) {
            if ($jobs->count() >= 5) {
                $this->error("ALERT: {$jobType} has {$jobs->count()} failures in last 24h");

                // TODO: Send notification via email/Slack
            }
        }

        $this->info("Analyzed {$failures->count()} failed jobs");
    }
}
```

**Schedule**: Run hourly

```php
$schedule->command('queue:analyze-failures')->hourly();
```

---

## 3. API RESILIENCE PATTERNS

### 3.1 Timeout Configuration

**Purpose**: Prevent indefinite waiting on external services

**Implementation**: `config/database.php`

```php
'pgsql' => [
    'driver' => 'pgsql',
    'host' => env('DB_HOST', '127.0.0.1'),
    'port' => env('DB_PORT', '5432'),
    'database' => env('DB_DATABASE', 'chom'),
    'username' => env('DB_USERNAME', 'chom'),
    'password' => env('DB_PASSWORD', ''),
    'charset' => 'utf8',
    'prefix' => '',
    'prefix_indexes' => true,
    'schema' => 'public',
    'sslmode' => 'prefer',

    // Connection timeouts
    'options' => [
        PDO::ATTR_TIMEOUT => 30,  // 30 second query timeout
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ],
],
```

**HTTP Client Timeouts**: Update `app/Services/Integration/ObservabilityAdapter.php`

```php
// Current: Http::timeout(30)
// Change to environment-specific:

Http::timeout(config('services.observability.timeout', 15))
```

**SSH Timeouts**: Update `VPSManagerBridge.php`

```php
private function createSSHConnection(VpsServer $vps): SSH2
{
    $ssh = new SSH2($vps->ip_address, 22, 10);  // 10 second connection timeout

    if (!$ssh->login('stilgar', new RSA($this->getPrivateKey()))) {
        throw new \RuntimeException("SSH authentication failed for {$vps->hostname}");
    }

    $ssh->setTimeout(120);  // 120 second command timeout

    return $ssh;
}
```

---

### 3.2 Graceful Degradation

**Purpose**: Return cached data when observability stack is down

**Implementation**: Update `ObservabilityAdapter.php`

```php
public function queryMetrics(Tenant $tenant, string $query, array $options = []): array
{
    $cacheKey = "metrics:{$tenant->id}:" . md5($query);

    try {
        $result = $this->queryMetricsDirect($query);

        // Cache successful responses for 5 minutes
        Cache::put($cacheKey, $result, now()->addMinutes(5));

        return $result;
    } catch (\Exception $e) {
        Log::warning('Metrics query failed, using cached data', [
            'error' => $e->getMessage(),
        ]);

        // Return cached data if available
        $cached = Cache::get($cacheKey);

        if ($cached) {
            return array_merge($cached, ['_cached' => true]);
        }

        // No cache available, return error
        return ['status' => 'error', 'error' => 'Service unavailable'];
    }
}
```

---

### 3.3 Rate Limiting

**Purpose**: Prevent resource exhaustion from single tenant

**Implementation**: `app/Http/Middleware/ThrottleByTenant.php`

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

class ThrottleByTenant
{
    public function handle(Request $request, Closure $next, string $limit = '100')
    {
        $tenant = $request->user()->currentTenant();

        // Rate limits by tier
        $limits = [
            'starter' => 100,      // 100 req/min
            'pro' => 500,          // 500 req/min
            'enterprise' => 2000,  // 2000 req/min
        ];

        $maxAttempts = $limits[$tenant->tier] ?? 100;

        $key = "tenant:{$tenant->id}";

        if (RateLimiter::tooManyAttempts($key, $maxAttempts)) {
            return response()->json([
                'error' => 'Rate limit exceeded',
                'retry_after' => RateLimiter::availableIn($key),
            ], 429);
        }

        RateLimiter::hit($key, 60);  // 60 second window

        return $next($request);
    }
}
```

**Apply to routes**: `routes/web.php`

```php
Route::middleware(['auth', ThrottleByTenant::class])->group(function () {
    Route::get('/metrics', MetricsDashboard::class);
    Route::post('/sites', CreateSite::class);
});
```

---

### 3.4 Bulkhead Pattern

**Purpose**: Isolate tenant resources to prevent one from affecting others

**Implementation**: Limit concurrent SSH operations per VPS

```php
public function execute(VpsServer $vps, string $command, array $args = []): array
{
    $lockKey = "ssh_lock:vps:{$vps->id}";
    $maxConcurrent = 3;  // Max 3 concurrent SSH operations per VPS

    $lock = Cache::lock($lockKey, 120);  // 2 minute lock timeout

    // Check current operations
    $current = Cache::get("ssh_count:vps:{$vps->id}", 0);

    if ($current >= $maxConcurrent) {
        throw new \RuntimeException(
            "Too many concurrent operations on {$vps->hostname}. Please try again later."
        );
    }

    if ($lock->get()) {
        try {
            Cache::increment("ssh_count:vps:{$vps->id}");

            $result = $this->executeSSH($vps, $command, $args);

            return $result;
        } finally {
            Cache::decrement("ssh_count:vps:{$vps->id}");
            $lock->release();
        }
    }

    throw new \RuntimeException("Could not acquire lock for SSH operation");
}
```

---

## 4. OBSERVABILITY & MONITORING

### 4.1 Enhanced Health Endpoint

**Purpose**: Detailed health status for automated monitoring

**Implementation**: `app/Http/Controllers/HealthController.php`

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use App\Services\Integration\ObservabilityAdapter;

class HealthController extends Controller
{
    public function __invoke(ObservabilityAdapter $observability)
    {
        $checks = [
            'database' => $this->checkDatabase(),
            'redis' => $this->checkRedis(),
            'queue' => $this->checkQueue(),
            'disk' => $this->checkDisk(),
            'observability' => $observability->getHealthStatus(),
        ];

        $healthy = collect($checks)->every(fn($check) => $check['status'] === 'ok');

        return response()->json([
            'status' => $healthy ? 'healthy' : 'unhealthy',
            'timestamp' => now()->toIso8601String(),
            'checks' => $checks,
        ], $healthy ? 200 : 503);
    }

    private function checkDatabase(): array
    {
        try {
            DB::connection()->getPdo();
            return ['status' => 'ok', 'latency_ms' => $this->measureLatency(fn() => DB::select('SELECT 1'))];
        } catch (\Exception $e) {
            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    private function checkRedis(): array
    {
        try {
            Redis::ping();
            return ['status' => 'ok'];
        } catch (\Exception $e) {
            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    private function checkQueue(): array
    {
        try {
            $size = DB::table('jobs')->count();
            $failed = DB::table('failed_jobs')->where('failed_at', '>', now()->subHour())->count();

            return [
                'status' => $failed > 20 ? 'warning' : 'ok',
                'queue_size' => $size,
                'failed_last_hour' => $failed,
            ];
        } catch (\Exception $e) {
            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    private function checkDisk(): array
    {
        $path = storage_path();
        $free = disk_free_space($path);
        $total = disk_total_space($path);
        $used_percent = 100 - ($free / $total * 100);

        return [
            'status' => $used_percent > 90 ? 'warning' : 'ok',
            'used_percent' => round($used_percent, 2),
            'free_gb' => round($free / 1024 / 1024 / 1024, 2),
        ];
    }

    private function measureLatency(callable $callback): float
    {
        $start = microtime(true);
        $callback();
        return round((microtime(true) - $start) * 1000, 2);
    }
}
```

**Route**: `routes/web.php`

```php
Route::get('/health', HealthController::class);
```

---

### 4.2 Prometheus Metrics Export

**Purpose**: Export application metrics for monitoring

**Implementation**: `app/Http/Controllers/MetricsController.php`

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\DB;

class MetricsController extends Controller
{
    public function __invoke()
    {
        $metrics = [];

        // Queue metrics
        $queueSize = DB::table('jobs')->count();
        $failedJobs = DB::table('failed_jobs')->where('failed_at', '>', now()->subHour())->count();

        $metrics[] = "chom_queue_size {$queueSize}";
        $metrics[] = "chom_failed_jobs_last_hour {$failedJobs}";

        // Tenant metrics
        $activeTenants = DB::table('tenants')->where('status', 'active')->count();
        $activeSites = DB::table('sites')->where('status', 'active')->count();

        $metrics[] = "chom_active_tenants {$activeTenants}";
        $metrics[] = "chom_active_sites {$activeSites}";

        // Circuit breaker metrics
        foreach (['vps:1', 'vps:2', 'vps:3'] as $service) {
            $state = \Cache::get("circuit_breaker:{$service}:state", 'closed');
            $stateValue = $state === 'open' ? 1 : 0;
            $metrics[] = "chom_circuit_breaker_open{service=\"{$service}\"} {$stateValue}";
        }

        return response(implode("\n", $metrics))
            ->header('Content-Type', 'text/plain; version=0.0.4');
    }
}
```

**Route**:

```php
Route::get('/metrics', MetricsController::class);
```

---

### 4.3 Alert Rules

**Purpose**: Define critical alerts for operations team

**Implementation**: `deploy/config/mentat/alerts/chom.yml`

```yaml
groups:
  - name: chom_application
    interval: 60s
    rules:
      # Queue backlog alert
      - alert: QueueBacklog
        expr: chom_queue_size > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Queue backlog detected"
          description: "Queue has {{ $value }} pending jobs"

      # Failed jobs spike
      - alert: FailedJobsSpike
        expr: chom_failed_jobs_last_hour > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High job failure rate"
          description: "{{ $value }} jobs failed in the last hour"

      # Circuit breaker open
      - alert: CircuitBreakerOpen
        expr: chom_circuit_breaker_open == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Circuit breaker open for {{ $labels.service }}"
          description: "Service is unavailable"

      # Health check failures
      - alert: HealthCheckFailing
        expr: up{job="chom-app"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "CHOM application is down"
          description: "Health check has failed for 5 minutes"
```

---

## 5. WEEK 1 QUICK WINS

### Priority 1: SSH Resilience (Day 1-2)

**Files to modify**:
1. `app/Services/Integration/VPSManagerBridge.php`
   - Add timeout configuration
   - Implement retry logic with exponential backoff
   - Add basic error logging

**Expected Impact**:
- 80% reduction in SSH timeout errors
- Automatic recovery from temporary network issues
- Better error messages for debugging

**Time Estimate**: 4 hours

---

### Priority 2: Systemd Watchdog (Day 2)

**Files to create**:
1. `/etc/systemd/system/chom-worker@.service`
2. Enable 3 worker instances

**Expected Impact**:
- Workers auto-restart on crash
- Resource limits prevent memory leaks
- Graceful shutdown on deployments

**Time Estimate**: 2 hours

---

### Priority 3: Health Endpoint Enhancement (Day 3)

**Files to modify**:
1. `app/Http/Controllers/HealthController.php`
2. `routes/web.php`

**Expected Impact**:
- Detailed health status for monitoring
- Early detection of database/Redis issues
- Foundation for automated alerts

**Time Estimate**: 3 hours

---

### Priority 4: Circuit Breaker (Day 4-5)

**Files to create**:
1. `app/Services/CircuitBreaker.php`
2. Update `VPSManagerBridge` to use circuit breaker

**Expected Impact**:
- Fail fast when VPS is down
- Prevent cascading failures
- Better user experience during outages

**Time Estimate**: 6 hours

---

### Priority 5: Queue Monitoring (Day 5)

**Files to create**:
1. `app/Http/Controllers/MetricsController.php`
2. Add Prometheus scrape config

**Expected Impact**:
- Visibility into queue performance
- Detect stuck/failed jobs
- Foundation for capacity planning

**Time Estimate**: 3 hours

---

## 6. ONE-SCRIPT DEPLOYMENT ENHANCEMENTS (2-Host Setup)

### 6.0 Deployment Strategy

**Purpose**: Deploy both hosts with single script execution

**Approach**: Script runs on chom-app host, deploys to both hosts

**Prerequisites**:
- SSH access from chom-app to observability host
- DNS records for both hosts configured
- SSL certificates available (Let's Encrypt)

**Deployment Flow**:
```bash
# Run from chom-app host
./deploy-chom-automated.sh

# Script will:
# 1. Deploy chom-app (local)
# 2. SSH to observability host and deploy monitoring stack
# 3. Configure network communication between hosts
# 4. Validate both hosts are healthy
```

---

### 6.1 Auto-Configure All Environment Variables

**Current**: User must manually edit `.env`

**Target**: Script generates all values except secrets

**Implementation**: Update `deploy/deploy-chom-automated.sh`

```bash
# Auto-detect external IP
EXTERNAL_IP=$(curl -s ifconfig.me)

# Auto-generate APP_KEY
APP_KEY=$(php artisan key:generate --show)

# Auto-configure observability URLs
cat > .env <<EOF
APP_NAME=CHOM
APP_ENV=production
APP_KEY=${APP_KEY}
APP_DEBUG=false
APP_URL=https://${DOMAIN}

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=${DB_PASSWORD}

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=${REDIS_PASSWORD}

# Auto-configured observability
CHOM_PROMETHEUS_URL=https://${MENTAT_HOST}/prometheus
CHOM_LOKI_URL=https://${MENTAT_HOST}/loki
CHOM_GRAFANA_URL=https://${MENTAT_HOST}
CHOM_ALERTMANAGER_URL=https://${MENTAT_HOST}/alertmanager

# SSH Configuration
CHOM_SSH_KEY_PATH=/var/www/chom/shared/storage/app/ssh/chom_deploy_key
CHOM_SSH_USER=stilgar
EOF
```

---

### 6.2 Post-Deployment Validation

**Purpose**: Verify deployment succeeded before marking complete

**Implementation**:

```bash
echo "=== Validating Deployment ==="

# Test database connection
if ! sudo -u www-data php artisan db:monitor; then
    echo "ERROR: Database connection failed"
    exit 1
fi

# Test Redis connection
if ! redis-cli ping; then
    echo "ERROR: Redis connection failed"
    exit 1
fi

# Test application health
sleep 5  # Wait for services to start
if ! curl -sf http://localhost/health; then
    echo "ERROR: Health check failed"
    exit 1
fi

# Test queue workers
if ! systemctl is-active chom-worker@1; then
    echo "ERROR: Queue workers not running"
    exit 1
fi

echo "✓ Deployment validation passed"
```

---

### 6.3 Minimize Manual Steps

**Current manual steps**:
1. Set CHOM_APP_HOST (chom-app hostname)
2. Set OBSERVABILITY_HOST (observability hostname)
3. Set DATABASE_PASSWORD
4. Set STRIPE_KEY/SECRET

**Target**: Only 4 inputs required (both hostnames needed for 2-host setup)

```bash
# User inputs
read -p "Enter chom-app domain (e.g., chom.example.com): " CHOM_APP_HOST
read -p "Enter observability host (e.g., observability.example.com): " OBSERVABILITY_HOST
read -sp "Enter Stripe secret key: " STRIPE_SECRET
echo

# Validate SSH access to observability host
if ! ssh -q root@${OBSERVABILITY_HOST} exit; then
    echo "ERROR: Cannot SSH to observability host"
    exit 1
fi

# Everything else auto-generated
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
APP_KEY=$(openssl rand -base64 32)

# Configure observability URLs
CHOM_PROMETHEUS_URL=https://${OBSERVABILITY_HOST}/prometheus
CHOM_LOKI_URL=https://${OBSERVABILITY_HOST}/loki
CHOM_GRAFANA_URL=https://${OBSERVABILITY_HOST}
CHOM_ALERTMANAGER_URL=https://${OBSERVABILITY_HOST}/alertmanager
```

---

### 6.4 Cross-Host Deployment Validation

**Purpose**: Verify both hosts are healthy and communicating

**Implementation**:

```bash
echo "=== Validating 2-Host Deployment ==="

# Validate chom-app (local)
echo "Checking chom-app host..."
if ! curl -sf http://localhost/health; then
    echo "ERROR: chom-app health check failed"
    exit 1
fi

# Validate observability host (remote)
echo "Checking observability host..."
if ! ssh root@${OBSERVABILITY_HOST} "curl -sf http://localhost:9090/-/healthy"; then
    echo "ERROR: Prometheus health check failed"
    exit 1
fi

if ! ssh root@${OBSERVABILITY_HOST} "curl -sf http://localhost:3100/ready"; then
    echo "ERROR: Loki health check failed"
    exit 1
fi

# Validate chom-app → observability connectivity
echo "Checking cross-host connectivity..."
if ! curl -sf https://${OBSERVABILITY_HOST}/prometheus/-/healthy; then
    echo "ERROR: chom-app cannot reach Prometheus"
    exit 1
fi

# Validate observability → chom-app metrics scraping
echo "Checking metrics export..."
if ! ssh root@${OBSERVABILITY_HOST} "curl -sf http://${CHOM_APP_HOST}:9100/metrics | head -n 1"; then
    echo "ERROR: Observability cannot scrape chom-app metrics"
    exit 1
fi

echo "✓ 2-Host deployment validation passed"
```

---

## SUMMARY: IMPLEMENTATION CHECKLIST (2-Host PoC)

### Week 1 (Quick Wins)
- [ ] Day 1-2: SSH resilience (timeout, retry, logging)
- [ ] Day 2: Systemd watchdog for workers
- [ ] Day 3: Enhanced health endpoint
- [ ] Day 3: Cross-host network resilience (observability reachability check)
- [ ] Day 4-5: Circuit breaker implementation
- [ ] Day 5: Queue monitoring and metrics export

### Week 2 (Background Workers)
- [ ] Configure priority queues
- [ ] Create systemd worker services (chom-app host)
- [ ] Implement retry policies
- [ ] Set up DLQ analysis
- [ ] Move SSH operations to async jobs

### Week 3 (Self-Healing)
- [ ] Health check automation script (both hosts)
- [ ] Stuck job killer
- [ ] Memory leak detection
- [ ] Alert rule configuration (observability host)
- [ ] Automated restart policies
- [ ] Cross-host connectivity monitoring

### Week 4 (Deployment & Polish)
- [ ] 2-host deployment script integration
- [ ] Auto-configure environment variables (both hosts)
- [ ] Cross-host deployment validation
- [ ] Firewall rules configuration
- [ ] Minimize manual configuration (4 inputs: 2 hostnames + DB password + Stripe key)
- [ ] Documentation updates
- [ ] End-to-end 2-host testing

---

## METRICS FOR SUCCESS (2-Host PoC)

### Performance Targets
- **SSH Operation Success Rate**: >95%
- **Queue Processing Time**: <5 minutes for 90th percentile
- **API Response Time**: <500ms for 95th percentile (excluding observability queries)
- **chom-app Uptime**: >99.5% (PoC target)
- **observability Uptime**: >95% (can degrade gracefully)

### Cross-Host Reliability
- **Network Latency (chom-app → observability)**: <50ms average
- **Observability Query Success Rate**: >90% (with graceful degradation)
- **Cached Metrics Serving**: <2% of total queries (indicates good observability uptime)

### Self-Healing Effectiveness
- **Auto-Recovery Rate**: >80% of failures resolve without manual intervention
- **Mean Time to Recovery (MTTR)**: <10 minutes for auto-recoverable issues
- **Circuit Breaker Activations**: <5 per day (indicates stable systems)

### Deployment Efficiency (2-Host)
- **Deployment Time**: <20 minutes for both hosts (from script start to validation)
- **Manual Configuration Steps**: ≤4 user inputs required (2 hostnames + DB password + Stripe key)
- **Deployment Success Rate**: >90% on first attempt (2-host complexity)
- **Cross-Host Validation**: 100% pass rate (deployment fails if validation fails)

---

## NEXT STEPS

1. **Review this plan** - Confirm 2-host architecture aligns with PoC goals
2. **Verify infrastructure** - Ensure both hosts are provisioned with network connectivity
3. **Start Week 1 Quick Wins** - Begin with SSH resilience and cross-host network resilience
4. **Monitor cross-host metrics** - Track network latency, observability query success rate
5. **Iterate based on data** - Adjust priorities based on real-world issues

This plan focuses on **practical 2-host resilience** without HA complexity, delivering immediate value while building foundation for future scaling.

---

## APPENDIX: Multi-Host Architecture Strategy

### Why 2 Hosts for PoC?

**Primary Goal**: Establish realistic multi-host communication patterns that will extend to 3-4 hosts in production.

**Current PoC Architecture (2 Hosts)**:
1. **CHOM-APP**: Application server (Laravel, PostgreSQL, Redis, queue workers)
2. **OBSERVABILITY**: Monitoring stack (Prometheus, Loki, Grafana, Alertmanager)

**Future Expansion (3-4 Hosts)**:
3. **CHOM-STORAGE-1**: Customer VPS file storage, backups, media assets
4. **CHOM-STORAGE-2** (optional): Backup/redundant storage or separate backup server

**Architectural Principles**:
- **Separation of Concerns**: Each host has a single responsibility
- **Realistic Multi-Host Communication**: Establish patterns now (circuit breakers, graceful degradation) that scale to 3-4 hosts
- **Resource Isolation**: Workloads don't compete for resources
- **Independent Scaling**: Each service can scale independently

---

### Future Architecture Vision (3-4 Hosts)

```
┌─────────────────────────────────────────────────────────────────┐
│ HOST 1: CHOM-APP (Application)                                 │
│  - Nginx, PHP-FPM, PostgreSQL, Redis                           │
│  - Queue Workers                                               │
│  - Orchestrates SSH to customer VPS                            │
│  - Proxies all user requests to other hosts                    │
└─────────────────────────────────────────────────────────────────┘
                    ▲                  ▲
                    │                  │
            ┌───────┴────────┐    ┌───┴──────────────┐
            │                │    │                  │
┌───────────▼─────┐  ┌───────▼────▼───┐  ┌──────────▼──────────┐
│ OBSERVABILITY   │  │ CHOM-STORAGE-1 │  │ CHOM-STORAGE-2      │
│  - Prometheus   │  │  - Backups     │  │  - Backup replica   │
│  - Loki         │  │  - Media files │  │  - DR storage       │
│  - Grafana      │  │  - Site files  │  │  (optional)         │
│  - Alertmanager │  │  - S3-compat   │  │                     │
└─────────────────┘  └────────────────┘  └─────────────────────┘
```

**Network Communication Patterns**:
- **CHOM-APP → OBSERVABILITY**: Metrics queries, log queries (HTTPS)
- **CHOM-APP → CHOM-STORAGE**: Backup uploads, file retrieval (HTTPS/S3 API)
- **OBSERVABILITY → CHOM-APP**: Metrics scraping (port 9100)
- **OBSERVABILITY → CHOM-STORAGE**: Metrics scraping (port 9100)
- **OBSERVABILITY → Customer VPS**: Metrics scraping (port 9100)
- **CHOM-STORAGE-1 ↔ CHOM-STORAGE-2**: Replication (rsync/S3 sync)

---

### Design Patterns for Multi-Host Resilience

All patterns implemented in this PoC are designed to scale to 3-4 hosts:

**1. Circuit Breaker Pattern**
```php
// Current: Works for observability host
$circuitBreaker = new CircuitBreaker('observability', 5, 60);

// Future: Extends to storage hosts
$circuitBreaker = new CircuitBreaker('chom-storage-1', 5, 60);
$circuitBreaker = new CircuitBreaker('chom-storage-2', 5, 60);
```

**2. Graceful Degradation**
- Observability down → Serve cached metrics
- Storage-1 down → Failover to Storage-2
- All hosts down → Application continues with reduced functionality

**3. Health Check Automation**
- Current: Checks chom-app + observability
- Future: Extends to check all storage hosts
- Each host monitored independently

**4. Cross-Host Deployment**
- Current: Single script deploys 2 hosts
- Future: Extends to deploy all hosts in sequence
- Validates connectivity mesh after deployment

---

### Why NOT Single-Host for PoC?

Starting with single host would require **re-architecting** for multi-host later:
- Network failure handling (not needed on localhost)
- Circuit breakers (not needed on localhost)
- Cross-host deployment (not needed for single host)
- Graceful degradation (not needed on localhost)

By starting with 2 hosts, we establish these patterns **now** and simply extend them when adding CHOM-STORAGE.

---

### PoC → Production Migration Path

**Phase 1 (Current PoC)**: 2 hosts
- CHOM-APP + OBSERVABILITY
- Establish multi-host communication patterns
- Validate resilience patterns work

**Phase 2 (Add Storage)**: 3 hosts
- Add CHOM-STORAGE-1
- Move backups off CHOM-APP PostgreSQL
- Customer VPS file storage on dedicated host
- **No re-architecting needed** - patterns already exist

**Phase 3 (Add Redundancy)**: 4 hosts (optional)
- Add CHOM-STORAGE-2 as replica
- Automatic failover if Storage-1 fails
- Disaster recovery

**Phase 4 (Scale Application)**: 5+ hosts
- Add CHOM-APP-2 (load balanced)
- Add PostgreSQL replica
- Redis Sentinel
- **Now we move to HA architecture** (beyond PoC scope)
