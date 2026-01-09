# CHOM Self-Healing & Automated Recovery

Automated recovery strategies and self-healing capabilities for the Cloud Hosting & Observability Manager.

---

## Table of Contents

- [Overview](#overview)
- [Self-Healing Architecture](#self-healing-architecture)
- [Recovery Strategies](#recovery-strategies)
- [Automated Actions](#automated-actions)
- [Circuit Breakers](#circuit-breakers)
- [Retry Mechanisms](#retry-mechanisms)
- [Graceful Degradation](#graceful-degradation)
- [Monitoring & Alerting](#monitoring--alerting)
- [Manual Intervention](#manual-intervention)

---

## Overview

CHOM implements self-healing capabilities to automatically detect and recover from common failure scenarios without human intervention.

**Goals:**
- Minimize downtime and manual intervention
- Automatically recover from transient failures
- Gracefully degrade when full recovery isn't possible
- Alert operators only when necessary
- Maintain service availability

**Principles:**
1. **Detect** - Identify failures through health checks and monitoring
2. **Diagnose** - Determine root cause and recovery strategy
3. **Recover** - Execute automated recovery actions
4. **Verify** - Confirm recovery was successful
5. **Learn** - Log incidents for analysis and improvement

---

## Self-Healing Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Monitoring Layer                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │  Health  │  │  Metrics │  │   Logs   │             │
│  │  Checks  │  │(Prometheus)│  │ (Loki)  │             │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘             │
└───────┼────────────┼─────────────┼──────────────────────┘
        │            │             │
        ▼            ▼             ▼
┌─────────────────────────────────────────────────────────┐
│              Detection & Diagnosis                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Failure Detection Service                       │  │
│  │  - Database connection failures                  │  │
│  │  - Service unavailability                        │  │
│  │  - High error rates                              │  │
│  │  - Resource exhaustion                           │  │
│  └────────────────────┬─────────────────────────────┘  │
└────────────────────────┼────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Recovery Actions                           │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐          │
│  │ Restart   │  │  Retry    │  │ Degrade   │          │
│  │ Services  │  │ Operations│  │ Gracefully│          │
│  └───────────┘  └───────────┘  └───────────┘          │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Verification & Notification                │
│  - Verify recovery successful                           │
│  - Log incident details                                 │
│  - Alert if manual intervention needed                  │
└─────────────────────────────────────────────────────────┘
```

---

## Recovery Strategies

### 1. Service Restart

**When:** Service crashes or becomes unresponsive

**Actions:**
- Systemd automatic restart (configured in service files)
- Health check triggers restart
- Clear stale state before restart

**Example - PHP-FPM:**
```ini
# /etc/systemd/system/php8.2-fpm.service.d/override.conf
[Service]
Restart=always
RestartSec=10s
StartLimitBurst=5
StartLimitIntervalSec=60s
```

**Example - Loki:**
```ini
# /etc/systemd/system/loki.service
[Service]
Restart=on-failure
RestartSec=5s
StartLimitBurst=3
StartLimitIntervalSec=30s
```

### 2. Connection Pool Reset

**When:** Database connection pool exhausted

**Actions:**
- Close idle connections
- Reset connection pool
- Re-establish fresh connections

**Implementation:**
```php
<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

class DatabaseHealthService
{
    public function resetConnectionPool(): bool
    {
        try {
            // Close all connections
            DB::disconnect();

            // Wait for connections to close
            sleep(2);

            // Test new connection
            DB::connection()->getPdo();

            Log::info('Database connection pool reset successfully');
            return true;
        } catch (\Exception $e) {
            Log::error('Failed to reset connection pool', [
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }
}
```

### 3. Cache Invalidation

**When:** Corrupt cache data or cache server issues

**Actions:**
- Flush affected cache entries
- Rebuild cache from source
- Switch to fallback (database queries)

**Implementation:**
```php
public function healCacheIssues(): bool
{
    try {
        // Flush problematic cache entries
        Cache::tags(['problematic'])->flush();

        // Test cache read/write
        $testKey = 'health_check_' . now()->timestamp;
        Cache::put($testKey, 'test', 10);

        if (Cache::get($testKey) !== 'test') {
            throw new \Exception('Cache read/write failed');
        }

        Log::info('Cache healed successfully');
        return true;
    } catch (\Exception $e) {
        // Fall back to database queries
        config(['cache.default' => 'array']);
        Log::warning('Cache healing failed, using fallback', [
            'error' => $e->getMessage(),
        ]);
        return false;
    }
}
```

### 4. Queue Retry

**When:** Jobs fail due to transient issues

**Actions:**
- Retry failed jobs with exponential backoff
- Move to dead letter queue after max attempts
- Alert on persistent failures

**Implementation:**
```php
<?php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class ProcessBackup implements ShouldQueue
{
    use InteractsWithQueue, Queueable, SerializesModels;

    // Retry configuration
    public $tries = 5;
    public $backoff = [10, 30, 60, 300, 900]; // exponential backoff
    public $timeout = 3600;

    public function handle()
    {
        // Job logic
    }

    public function failed(\Throwable $exception)
    {
        // Alert after all retries exhausted
        Log::error('Backup job failed after all retries', [
            'exception' => $exception->getMessage(),
            'backup_id' => $this->backup->id,
        ]);

        // Trigger alert
        Alert::send(new JobFailureAlert($this, $exception));
    }
}
```

### 5. Resource Cleanup

**When:** Disk space, memory, or file descriptors exhausted

**Actions:**
- Clean up temporary files
- Remove old logs
- Clear expired cache entries
- Terminate idle processes

**Implementation - Scheduled Task:**
```php
// app/Console/Kernel.php
protected function schedule(Schedule $schedule)
{
    // Clean temporary files daily
    $schedule->call(function () {
        $this->cleanupTemporaryFiles();
    })->daily();

    // Clean old logs weekly
    $schedule->call(function () {
        $this->cleanupOldLogs();
    })->weekly();

    // Emergency cleanup when disk space low
    $schedule->call(function () {
        $diskUsage = $this->getDiskUsagePercent();
        if ($diskUsage > 90) {
            $this->emergencyCleanup();
        }
    })->everyFiveMinutes();
}

protected function emergencyCleanup()
{
    // Delete old temporary files
    exec('find /tmp -type f -mtime +1 -delete');

    // Compress and archive old logs
    exec('find /var/log -type f -name "*.log" -mtime +7 -exec gzip {} \;');

    // Clear expired cache
    Cache::flush();

    Log::warning('Emergency cleanup performed due to low disk space');
}
```

### 6. Site Recovery

**When:** Individual site becomes unresponsive

**Actions:**
- Restart PHP-FPM pool for site
- Check file permissions
- Verify nginx configuration
- Test database connectivity

**Implementation:**
```bash
#!/usr/bin/env bash
# deploy/vpsmanager/lib/self-healing/site-recovery.sh

recover_site() {
    local domain="$1"
    local site_root="/var/www/sites/${domain}"

    log_info "Starting site recovery for: ${domain}"

    # 1. Check if site directory exists
    if [[ ! -d "$site_root" ]]; then
        log_error "Site directory does not exist: ${site_root}"
        return 1
    fi

    # 2. Fix file permissions
    log_info "Fixing file permissions..."
    fix_site_permissions "$domain"

    # 3. Restart PHP-FPM pool
    log_info "Restarting PHP-FPM pool..."
    systemctl restart "php8.2-fpm-${domain}"

    # 4. Reload nginx
    log_info "Reloading nginx..."
    nginx -t && systemctl reload nginx

    # 5. Test site responsiveness
    log_info "Testing site responsiveness..."
    if test_site_health "$domain"; then
        log_success "Site recovered successfully: ${domain}"
        return 0
    else
        log_error "Site recovery failed: ${domain}"
        return 1
    fi
}

test_site_health() {
    local domain="$1"
    local url="https://${domain}"
    local response

    response=$(curl -s -o /dev/null -w "%{http_code}" "$url")

    if [[ "$response" -eq 200 ]]; then
        return 0
    else
        log_warning "Site health check failed: ${domain} (HTTP ${response})"
        return 1
    fi
}
```

---

## Automated Actions

### Health Check Based Recovery

**Triggered by:** `/health` endpoint returning 503

**Actions:**
1. Log failure details
2. Attempt database connection reset
3. Clear cache if needed
4. Restart affected services
5. Verify recovery
6. Alert if recovery fails

**Script Example:**
```bash
#!/usr/bin/env bash
# deploy/scripts/health-check-recovery.sh

set -euo pipefail

HEALTH_URL="${1:-http://localhost/health}"
MAX_RETRIES=3
RETRY_DELAY=10

check_and_recover() {
    local attempt=1

    while [[ $attempt -le $MAX_RETRIES ]]; do
        echo "Health check attempt ${attempt}/${MAX_RETRIES}..."

        # Check health endpoint
        if curl -f -s "$HEALTH_URL" > /dev/null 2>&1; then
            echo "✓ Health check passed"
            return 0
        fi

        echo "✗ Health check failed, attempting recovery..."

        # Attempt recovery
        recover_services

        # Wait before retry
        sleep $RETRY_DELAY

        ((attempt++))
    done

    echo "✗ Recovery failed after ${MAX_RETRIES} attempts"
    send_alert "CHOM health check recovery failed"
    return 1
}

recover_services() {
    # Reset database connections
    echo "Resetting database connections..."
    php artisan db:reconnect

    # Clear cache
    echo "Clearing cache..."
    php artisan cache:clear

    # Restart queue workers
    echo "Restarting queue workers..."
    php artisan queue:restart

    # Wait for services to stabilize
    sleep 5
}

send_alert() {
    local message="$1"
    # Send to monitoring system, Slack, etc.
    curl -X POST "$ALERT_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"${message}\"}"
}

check_and_recover
```

### Prometheus Alert-Triggered Recovery

**Alert Manager Configuration:**
```yaml
# alertmanager.yml
route:
  receiver: 'webhook-recovery'
  routes:
    - match:
        alertname: CHOMHealthCheckFailing
      receiver: 'webhook-recovery'

receivers:
  - name: 'webhook-recovery'
    webhook_configs:
      - url: 'http://chom.arewel.com/api/v1/webhooks/alert-recovery'
        send_resolved: true
```

**Recovery Webhook Handler:**
```php
<?php

namespace App\Http\Controllers\Webhooks;

use App\Services\SelfHealingService;
use Illuminate\Http\Request;

class AlertRecoveryController extends Controller
{
    public function __invoke(Request $request, SelfHealingService $selfHealing)
    {
        $alert = $request->input('alerts')[0] ?? null;

        if (!$alert) {
            return response()->json(['error' => 'No alert data'], 400);
        }

        $alertName = $alert['labels']['alertname'] ?? 'unknown';
        $status = $alert['status'] ?? 'unknown';

        Log::info('Received alert webhook', [
            'alert_name' => $alertName,
            'status' => $status,
        ]);

        // Only act on firing alerts
        if ($status !== 'firing') {
            return response()->json(['message' => 'Alert not firing, no action taken']);
        }

        // Execute recovery based on alert type
        $recovered = match ($alertName) {
            'CHOMHealthCheckFailing' => $selfHealing->recoverFromHealthCheckFailure(),
            'HighErrorRate' => $selfHealing->recoverFromHighErrorRate(),
            'DiskSpaceLow' => $selfHealing->cleanupDiskSpace(),
            'QueueBacklog' => $selfHealing->processQueueBacklog(),
            default => false,
        };

        if ($recovered) {
            return response()->json([
                'message' => 'Recovery successful',
                'alert' => $alertName,
            ]);
        }

        return response()->json([
            'message' => 'Recovery failed, manual intervention required',
            'alert' => $alertName,
        ], 500);
    }
}
```

---

## Circuit Breakers

### Purpose

Prevent cascading failures by temporarily blocking requests to failing services.

### Implementation

```php
<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;

class CircuitBreaker
{
    protected $serviceName;
    protected $failureThreshold = 5;
    protected $timeoutSeconds = 60;
    protected $recoveryTimeout = 300; // 5 minutes

    public function __construct(string $serviceName)
    {
        $this->serviceName = $serviceName;
    }

    public function call(callable $operation)
    {
        if ($this->isOpen()) {
            throw new \Exception("Circuit breaker is OPEN for {$this->serviceName}");
        }

        try {
            $result = $operation();
            $this->recordSuccess();
            return $result;
        } catch (\Exception $e) {
            $this->recordFailure();

            if ($this->shouldOpen()) {
                $this->open();
            }

            throw $e;
        }
    }

    protected function isOpen(): bool
    {
        return Cache::has($this->getOpenKey());
    }

    protected function shouldOpen(): bool
    {
        $failures = $this->getFailureCount();
        return $failures >= $this->failureThreshold;
    }

    protected function open(): void
    {
        Cache::put($this->getOpenKey(), true, $this->recoveryTimeout);

        Log::warning("Circuit breaker OPENED for {$this->serviceName}", [
            'failure_count' => $this->getFailureCount(),
        ]);

        // Schedule recovery attempt
        $this->scheduleRecoveryAttempt();
    }

    protected function recordFailure(): void
    {
        $key = $this->getFailureKey();
        $count = Cache::get($key, 0);
        Cache::put($key, $count + 1, $this->timeoutSeconds);
    }

    protected function recordSuccess(): void
    {
        Cache::forget($this->getFailureKey());
        Cache::forget($this->getOpenKey());
    }

    protected function getFailureCount(): int
    {
        return Cache::get($this->getFailureKey(), 0);
    }

    protected function getFailureKey(): string
    {
        return "circuit_breaker:{$this->serviceName}:failures";
    }

    protected function getOpenKey(): string
    {
        return "circuit_breaker:{$this->serviceName}:open";
    }

    protected function scheduleRecoveryAttempt(): void
    {
        // Schedule a job to test recovery
        \App\Jobs\TestCircuitBreakerRecovery::dispatch($this->serviceName)
            ->delay(now()->addSeconds($this->recoveryTimeout / 2));
    }
}
```

### Usage Example

```php
$breaker = new CircuitBreaker('vpsmanager_api');

try {
    $result = $breaker->call(function () {
        return Http::timeout(5)->get('http://vpsmanager/api/sites');
    });
} catch (\Exception $e) {
    // Fallback behavior
    Log::warning('VPSManager API unavailable, using cached data');
    $result = Cache::get('sites_cache');
}
```

---

## Retry Mechanisms

### Exponential Backoff

**Strategy:** Wait increasingly longer between retry attempts

```php
<?php

namespace App\Services;

class RetryService
{
    public function retryWithBackoff(
        callable $operation,
        int $maxAttempts = 5,
        int $initialDelayMs = 100
    ) {
        $attempt = 1;

        while ($attempt <= $maxAttempts) {
            try {
                return $operation();
            } catch (\Exception $e) {
                if ($attempt >= $maxAttempts) {
                    throw $e;
                }

                // Calculate exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms
                $delayMs = $initialDelayMs * (2 ** ($attempt - 1));

                // Add jitter to prevent thundering herd
                $jitterMs = rand(0, $delayMs / 2);
                $totalDelayMs = $delayMs + $jitterMs;

                Log::debug("Retry attempt {$attempt}/{$maxAttempts}, waiting {$totalDelayMs}ms", [
                    'error' => $e->getMessage(),
                ]);

                usleep($totalDelayMs * 1000);
                $attempt++;
            }
        }
    }
}
```

### Usage

```php
$retry = new RetryService();

$result = $retry->retryWithBackoff(function () {
    return DB::connection()->getPdo();
}, maxAttempts: 5, initialDelayMs: 100);
```

---

## Graceful Degradation

### Fallback Strategies

When full recovery isn't possible, provide degraded functionality:

**1. Cached Data Fallback**
```php
public function getSites()
{
    try {
        // Try to fetch fresh data
        $sites = $this->vpsManagerApi->getSites();
        Cache::put('sites_cache', $sites, 3600);
        return $sites;
    } catch (\Exception $e) {
        Log::warning('VPSManager API unavailable, using cached data');
        return Cache::get('sites_cache', []);
    }
}
```

**2. Read-Only Mode**
```php
public function isReadOnlyMode(): bool
{
    return Cache::get('system:read_only_mode', false);
}

public function enableReadOnlyMode(string $reason): void
{
    Cache::put('system:read_only_mode', true, 3600);
    Log::warning('System entered read-only mode', ['reason' => $reason]);
}

// In controllers
if ($this->isReadOnlyMode()) {
    return response()->json([
        'error' => 'System is temporarily in read-only mode',
    ], 503);
}
```

**3. Feature Flags**
```php
public function canUseFeature(string $feature): bool
{
    // Disable features when related services are unavailable
    return match ($feature) {
        'backups' => $this->isVPSManagerHealthy(),
        'metrics' => $this->isPrometheusHealthy(),
        'logs' => $this->isLokiHealthy(),
        default => true,
    };
}
```

---

## Monitoring & Alerting

### Alert Severity Levels

| Severity | Description | Action | Example |
|----------|-------------|--------|---------|
| **Critical** | Service down, immediate action required | Page on-call engineer | Database unavailable |
| **High** | Degraded functionality, needs attention soon | Create ticket, notify team | High error rate |
| **Medium** | Minor issue, can wait for business hours | Log for review | Slow query detected |
| **Low** | Informational, no action needed | Log only | Successful recovery |

### Self-Healing Metrics

**Prometheus Metrics:**
```promql
# Recovery attempts
chom_recovery_attempts_total{service="database",outcome="success"}

# Circuit breaker state
chom_circuit_breaker_state{service="vpsmanager_api"} # 0=closed, 1=open

# Retry counts
chom_retry_attempts_total{operation="backup_creation"}

# Healing duration
chom_healing_duration_seconds{service="php_fpm"}
```

**Grafana Dashboard:**
- Recovery success rate
- Time to recovery
- Circuit breaker trip frequency
- Failed recovery attempts requiring manual intervention

---

## Manual Intervention

### When to Intervene

Automated recovery should trigger manual intervention when:

1. **Recovery fails after max attempts** - Persistent issue requiring investigation
2. **Circuit breaker remains open** - Underlying problem not resolved
3. **Resource exhaustion** - Needs capacity planning or scaling
4. **Data corruption** - Requires careful manual restoration
5. **Security incident** - Requires forensic analysis

### Manual Recovery Procedures

**1. Database Recovery**
```bash
# Check database status
sudo systemctl status mysql

# Review error logs
sudo tail -f /var/log/mysql/error.log

# Restart database
sudo systemctl restart mysql

# Verify connectivity
php artisan tinker
>>> DB::connection()->getPdo();
```

**2. Service Recovery**
```bash
# Check all services
sudo systemctl status php8.2-fpm nginx loki prometheus grafana-server

# Restart specific service
sudo systemctl restart php8.2-fpm

# Check logs
sudo journalctl -u php8.2-fpm -f
```

**3. Site Recovery**
```bash
# Use VPSManager recovery
sudo /opt/vpsmanager/bin/vpsmanager site recover example.com

# Or manual recovery
sudo /opt/vpsmanager/lib/self-healing/site-recovery.sh example.com
```

---

## Best Practices

### 1. Implement Idempotent Recovery

Recovery actions should be safe to run multiple times:
```php
public function resetCache(): void
{
    // Safe to run multiple times
    Cache::flush();

    // Verify cache is empty
    if (Cache::has('test_key')) {
        throw new \Exception('Cache flush failed');
    }
}
```

### 2. Log All Recovery Attempts

```php
Log::info('Starting automatic recovery', [
    'service' => $serviceName,
    'failure_count' => $failureCount,
    'trigger' => $trigger,
]);

// ... recovery logic ...

Log::info('Recovery completed', [
    'service' => $serviceName,
    'success' => $success,
    'duration_ms' => $duration,
]);
```

### 3. Set Reasonable Timeouts

Don't let recovery attempts hang indefinitely:
```php
set_time_limit(30); // Max 30 seconds for recovery
```

### 4. Test Recovery Procedures

Include recovery tests in your test suite:
```php
public function test_recovery_from_database_failure()
{
    // Simulate database failure
    DB::disconnect();

    // Trigger recovery
    $service = new DatabaseHealthService();
    $recovered = $service->resetConnectionPool();

    // Verify recovery
    $this->assertTrue($recovered);
    $this->assertTrue(DB::connection()->getPdo());
}
```

### 5. Monitor Recovery Effectiveness

Track metrics:
- Recovery success rate
- Time to recovery (MTTR)
- Frequency of recovery attempts
- Manual intervention rate

---

## Related Documentation

- [Health Checks](health-checks.md) - System health monitoring
- [Observability](observability.md) - Metrics and logging
- [Multi-Tenancy Architecture](../architecture/multi-tenancy.md) - Security isolation

---

**Last Updated:** 2026-01-09
**Version:** 2.2.0
**Status:** Planned (Phase 4)
