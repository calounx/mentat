# Event-Driven Architecture

> **Status:** Production Ready (v5.1.0)
> **Last Updated:** 2025-12-31
> **Maintainer:** Development Team

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Events Catalog](#events-catalog)
- [Listeners](#listeners)
- [Performance](#performance)
- [Error Handling](#error-handling)
- [Developer Guide](#developer-guide)
- [Testing](#testing)
- [Deployment](#deployment)

---

## Overview

CHOM uses an event-driven architecture to decouple business logic from cross-cutting concerns like audit logging, cache invalidation, metrics recording, and notifications. This architectural pattern provides:

- **Loose Coupling**: Core business logic doesn't depend on side effects
- **Scalability**: Events and listeners can be queued for async processing
- **Maintainability**: Single place to manage event→listener mappings
- **Testability**: Can mock events without triggering real side effects
- **Future-Proof**: Foundation for event sourcing, webhooks, CQRS

### Key Benefits

| Before (Imperative) | After (Event-Driven) |
|---------------------|----------------------|
| Manual `AuditLog::log()` calls scattered everywhere | Automatic audit logging via `RecordAuditLog` listener |
| Manual `$tenant->updateCachedStats()` in model hooks | Automatic cache updates via `UpdateTenantMetrics` listener |
| Manual `MetricsCollector::increment()` calls | Automatic metrics via `RecordMetrics` listener |
| Tightly coupled notification logic | Decoupled `SendNotification` listener |

---

## Architecture

### Event Flow Diagram

```
┌─────────────────┐
│  User Action    │
│  (Controller)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Business Logic  │
│   (Service)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Domain Event   │ ◄── SiteCreated, SiteProvisioned, etc.
│   ::dispatch()  │
└────────┬────────┘
         │
         ├──────────┬──────────┬──────────┐
         ▼          ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
    │Update  │ │Record  │ │Send    │ │Record  │
    │Tenant  │ │Audit   │ │Notif.  │ │Metrics │
    │Metrics │ │Log     │ │        │ │        │
    └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘
        │          │          │          │
        ▼          ▼          ▼          │ (sync)
    ┌────────────────────────────┐       │
    │       Redis Queue          │       │
    │  (UpdateTenantMetrics)     │       │
    │  (RecordAuditLog)          │       │
    │  (SendNotification)        │       │
    └────────────────────────────┘       │
                                         ▼
                                  ┌────────────┐
                                  │ Prometheus │
                                  │  (Metrics) │
                                  └────────────┘
```

### Components

1. **Events** (`app/Events/`) - Domain events representing business facts
2. **Listeners** (`app/Listeners/`) - Handlers that react to events
3. **EventServiceProvider** (`app/Providers/EventServiceProvider.php`) - Event→listener registration
4. **Queue System** (Redis) - Async processing for non-critical listeners

---

## Events Catalog

All domain events extend `AbstractDomainEvent` which provides:
- `occurredAt` - Timestamp when event occurred
- `actorId` - ID of user who triggered the event
- `actorType` - Type of actor (user, system, api)
- `getMetadata()` - Event metadata for audit logs
- `getEventName()` - Human-readable event name

### Site Events

#### `App\Events\Site\SiteCreated`

**When:** After `Site` record is created in database
**Triggered By:** `SiteCreationService::createSite()`
**Listeners:**
- `UpdateTenantMetrics` - Update tenant cached site count
- `RecordAuditLog` - Log site creation action
- `RecordMetrics` - Increment `sites_created_total` counter

**Properties:**
```php
public readonly Site $site;
public readonly Tenant $tenant;
```

**Example:**
```php
SiteCreated::dispatch($site, $tenant);
```

---

#### `App\Events\Site\SiteProvisioned`

**When:** After site is successfully provisioned on VPS
**Triggered By:** `ProvisionSiteJob::handle()` (success path)
**Listeners:**
- `RecordAuditLog` - Log successful provisioning
- `SendNotification` - Notify user of success
- `RecordMetrics` - Increment `sites_provisioned_total`, record duration histogram

**Properties:**
```php
public readonly Site $site;
public readonly array $provisioningDetails; // ['duration' => 5.2]
```

**Example:**
```php
SiteProvisioned::dispatch($site, ['duration' => $duration]);
```

---

#### `App\Events\Site\SiteProvisioningFailed`

**When:** After site provisioning fails
**Triggered By:** `ProvisionSiteJob::handle()` (failure paths)
**Listeners:**
- `RecordAuditLog` - Log failure with error details
- `SendNotification` - Alert user of failure
- `RecordMetrics` - Increment `sites_provisioning_failed_total`

**Properties:**
```php
public readonly Site $site;
public readonly string $errorMessage;
public readonly ?string $errorTrace;
```

**Example:**
```php
SiteProvisioningFailed::dispatch($site, 'No VPS server available');
```

---

#### `App\Events\Site\SiteDeleted`

**When:** After site is soft-deleted
**Triggered By:** `SiteController::destroy()`
**Listeners:**
- `UpdateTenantMetrics` - Update tenant cached site count
- `RecordAuditLog` - Log site deletion
- `RecordMetrics` - Increment `sites_deleted_total`

**Properties (Primitive Data):**
```php
public readonly string $siteId;
public readonly string $tenantId;
public readonly string $domain;
```

**Note:** Uses primitive data (strings) because site is soft-deleted and model may not be accessible.

**Example:**
```php
$siteId = $site->id;
$tenantId = $site->tenant_id;
$domain = $site->domain;
$site->delete();
SiteDeleted::dispatch($siteId, $tenantId, $domain);
```

---

### Backup Events

#### `App\Events\Backup\BackupCreated`

**When:** After `SiteBackup` record is created (before actual backup)
**Triggered By:** `CreateBackupJob::handle()`
**Listeners:**
- `RecordAuditLog` - Log backup job start

**Properties:**
```php
public readonly SiteBackup $backup;
public readonly Site $site;
```

---

#### `App\Events\Backup\BackupCompleted`

**When:** After backup file is successfully created
**Triggered By:** `CreateBackupJob::handle()` (success path)
**Listeners:**
- `RecordAuditLog` - Log successful backup
- `SendNotification` - Notify user of completion
- `RecordMetrics` - Record backup size and duration

**Properties:**
```php
public readonly SiteBackup $backup;
public readonly int $sizeBytes;
public readonly int $durationSeconds;
```

**Example:**
```php
BackupCompleted::dispatch($backup, $sizeBytes, $duration);
```

---

#### `App\Events\Backup\BackupFailed`

**When:** After backup creation fails
**Triggered By:** `CreateBackupJob::handle()` (failure paths)
**Listeners:**
- `RecordAuditLog` - Log backup failure
- `SendNotification` - Alert user of failure
- `RecordMetrics` - Increment `backups_failed_total`

**Properties (Primitive Data):**
```php
public readonly string $siteId;
public readonly string $backupType; // 'full', 'database', 'files'
public readonly string $errorMessage;
```

**Example:**
```php
BackupFailed::dispatch($siteId, 'full', 'Insufficient disk space');
```

---

## Listeners

### Queued Listeners (Asynchronous)

#### `App\Listeners\UpdateTenantMetrics`

**Purpose:** Update tenant cached statistics (site count, storage, etc.)
**Queue:** `default`
**Retry Policy:** 3 tries with 30s backoff
**Replaces:** Manual cache invalidation in `Site` model lifecycle hooks

**Handles:**
- `SiteCreated` - Increment cached site count
- `SiteDeleted` - Decrement cached site count

**Idempotent:** Yes (safe to run multiple times)

---

#### `App\Listeners\RecordAuditLog`

**Purpose:** Centralized audit logging for all domain events
**Queue:** `default`
**Retry Policy:** 3 tries with 60s backoff
**Replaces:** Scattered `AuditLog::log()` calls

**Handles:** All domain events (via `AbstractDomainEvent` base class)

**Audit Log Fields:**
- `action` - Event name (e.g., "site.created")
- `organization` - User's organization
- `user` - User who triggered event
- `resource_type` - Resource affected (e.g., "site")
- `resource_id` - Resource ID
- `metadata` - Full event metadata
- `severity` - "info", "warning", "error"

**Idempotent:** Yes (duplicate audit logs are acceptable)

---

#### `App\Listeners\SendNotification`

**Purpose:** Send user notifications for significant events
**Queue:** `notifications`
**Retry Policy:** 3 tries with 120s backoff

**Handles:**
- `SiteProvisioned` - "Your site is ready!"
- `SiteProvisioningFailed` - "Site provisioning failed"
- `BackupCompleted` - "Backup completed successfully"
- `BackupFailed` - "Backup failed"

**Current Implementation:** Logs notifications (TODO: implement email/Slack)

---

### Synchronous Listeners (Immediate)

#### `App\Listeners\RecordMetrics`

**Purpose:** Record Prometheus metrics for monitoring
**Queue:** None (synchronous)
**Replaces:** Manual `MetricsCollector` calls

**Why Synchronous?** Metrics must be recorded immediately for accurate monitoring and alerting.

**Metrics Recorded:**
- `sites_created_total` - Counter
- `sites_provisioned_total` - Counter
- `sites_provisioning_failed_total` - Counter
- `sites_deleted_total` - Counter
- `site_provisioning_duration_seconds` - Histogram
- `backups_completed_total` - Counter
- `backups_failed_total` - Counter
- `backup_duration_seconds` - Histogram
- `backup_size_bytes` - Histogram

---

## Performance

### Benchmarks

Performance tests are in `tests/Performance/EventPerformanceTest.php`.

| Metric | Target | Actual (Avg) |
|--------|--------|--------------|
| Event dispatch overhead | <1ms | ~0.3ms |
| Site creation with events | <100ms | ~45ms |
| Full site lifecycle (create→provision→delete) | <200ms | ~120ms |
| 100 site creations | >10 sites/sec | ~15 sites/sec |
| Memory per 1000 events | <50MB | ~12MB |

### Queue Impact

- **Per Site Creation:** 2 queued jobs (UpdateTenantMetrics, RecordAuditLog)
- **Per Backup:** 2-3 queued jobs (RecordAuditLog, SendNotification if failed)
- **Queue Capacity:** Redis handles 10,000+ jobs/minute easily
- **Impact:** Negligible (queue depth scales linearly)

### Optimization Tips

1. **Use Queued Listeners for Slow Operations**
   - Email sending → SendNotification (queued)
   - External API calls → Queue them
   - Database aggregations → UpdateTenantMetrics (queued)

2. **Keep Synchronous Listeners Fast**
   - RecordMetrics: Simple counter increment (<1ms)
   - Avoid heavy computations in sync listeners

3. **Monitor Queue Depth**
   - Use `php artisan queue:monitor` to track queue length
   - Scale workers if queue depth grows beyond 1000 jobs

---

## Error Handling

### Retry Logic

All queued listeners have retry configuration:

```php
public $tries = 3;          // Number of retry attempts
public $backoff = 30;       // Seconds to wait between retries
```

**Backoff Strategy:** Fixed backoff (can be configured for exponential backoff)

### Failure Handling

Each listener implements `failed()` method:

```php
public function failed($event, \Throwable $exception): void
{
    Log::error('Listener failed', [
        'event' => get_class($event),
        'error' => $exception->getMessage(),
    ]);
}
```

**Failure Behavior:**
- After 3 failed retries, job is moved to `failed_jobs` table
- Check failed jobs: `php artisan queue:failed`
- Retry failed job: `php artisan queue:retry {id}`

### Graceful Degradation

Listeners handle missing data gracefully:

- `UpdateTenantMetrics` - Skips update if tenant not found
- `RecordAuditLog` - Creates log with null user if user missing
- `SendNotification` - Logs notification if email service unavailable

---

## Developer Guide

### How to Add a New Event

**Step 1: Create Event Class**

```php
// app/Events/Site/SslCertificateExpiring.php
namespace App\Events\Site;

use App\Events\AbstractDomainEvent;
use App\Models\Site;

class SslCertificateExpiring extends AbstractDomainEvent
{
    public function __construct(
        public readonly Site $site,
        public readonly int $daysUntilExpiration,
        ?string $actorId = null
    ) {
        parent::__construct($actorId, 'system');
    }

    public function getMetadata(): array
    {
        return array_merge(parent::getMetadata(), [
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'days_until_expiration' => $this->daysUntilExpiration,
            'ssl_expires_at' => $this->site->ssl_expires_at->toIso8601String(),
        ]);
    }
}
```

**Step 2: Register Event in EventServiceProvider**

```php
// app/Providers/EventServiceProvider.php
protected $listen = [
    \App\Events\Site\SslCertificateExpiring::class => [
        \App\Listeners\RecordAuditLog::class,
        \App\Listeners\SendNotification::class . '@handleSslExpiring',
        \App\Listeners\RecordMetrics::class . '@handleSslExpiring',
    ],
];
```

**Step 3: Dispatch Event in Business Logic**

```php
// In a scheduled command or job
if ($site->isSslExpiringSoon()) {
    \App\Events\Site\SslCertificateExpiring::dispatch(
        $site,
        $site->ssl_expires_at->diffInDays(now())
    );
}
```

**Step 4: Add Listener Methods (if needed)**

```php
// app/Listeners/SendNotification.php
public function handleSslExpiring(SslCertificateExpiring $event): void
{
    // Send email notification
    Log::info("TODO: Send SSL expiring notification", [
        'site_id' => $event->site->id,
        'days_remaining' => $event->daysUntilExpiration,
    ]);
}
```

**Step 5: Write Tests**

```php
// tests/Unit/Events/SslEventTest.php
public function test_ssl_certificate_expiring_event(): void
{
    $site = Site::factory()->create([
        'ssl_expires_at' => now()->addDays(10),
    ]);

    $event = new SslCertificateExpiring($site, 10);

    $this->assertEquals(10, $event->daysUntilExpiration);
    $this->assertArrayHasKey('days_until_expiration', $event->getMetadata());
}
```

### Best Practices

✅ **DO:**
- Use events for significant business actions (created, updated, deleted, failed)
- Include all necessary context in event properties
- Use primitive data for soft-deleted entities
- Make listeners idempotent (safe to retry)
- Queue slow operations (email, API calls)

❌ **DON'T:**
- Emit events for trivial actions (getters, setters)
- Include sensitive data in event metadata (passwords, API keys)
- Perform heavy computation in event constructors
- Dispatch events inside database transactions (unless necessary)
- Use events as a replacement for return values

---

## Testing

### Unit Tests

Test events in isolation:

```php
public function test_site_created_event_metadata(): void
{
    $site = Site::factory()->create();
    $tenant = Tenant::factory()->create();

    $event = new SiteCreated($site, $tenant);
    $metadata = $event->getMetadata();

    $this->assertArrayHasKey('site_id', $metadata);
    $this->assertEquals($site->id, $metadata['site_id']);
}
```

### Integration Tests

Test event dispatch and listener execution:

```php
public function test_site_created_event_triggers_listeners(): void
{
    Event::fake([SiteCreated::class]);

    $site = $this->siteCreationService->createSite($tenant, $data);

    Event::assertDispatched(SiteCreated::class, function ($event) use ($site) {
        return $event->site->id === $site->id;
    });
}
```

### Performance Tests

Run performance benchmarks:

```bash
php artisan test --filter=EventPerformanceTest
```

---

## Deployment

### Pre-Deployment Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] Queue workers are running (`php artisan queue:work`)
- [ ] Redis is available
- [ ] Prometheus metrics endpoint is accessible
- [ ] Event listeners are registered (`php artisan event:list`)

### Deployment Steps

1. **Deploy Code**
   ```bash
   git pull origin main
   composer install --no-dev --optimize-autoloader
   ```

2. **Clear Caches**
   ```bash
   php artisan config:cache
   php artisan event:cache
   php artisan route:cache
   ```

3. **Restart Queue Workers**
   ```bash
   php artisan queue:restart
   ```

4. **Monitor Queue**
   ```bash
   php artisan queue:monitor default,notifications --max=1000
   ```

### Rollback Plan

If issues occur, disable events temporarily:

```php
// In EventServiceProvider.php
public function boot(): void
{
    if (config('features.events_enabled', true)) {
        parent::boot();
    }
}
```

```bash
# .env
EVENTS_ENABLED=false
```

Then re-enable model lifecycle hooks in `app/Models/Site.php` (see git history).

---

## Monitoring

### Metrics to Watch

- **Queue Depth:** `php artisan queue:monitor`
- **Failed Jobs:** `SELECT COUNT(*) FROM failed_jobs WHERE queue = 'default'`
- **Event Dispatch Rate:** Prometheus metric `events_dispatched_total`
- **Listener Failure Rate:** Prometheus metric `listeners_failed_total`

### Alerts

Set up alerts for:
- Queue depth >1000 jobs
- Failed jobs >10 in 5 minutes
- Listener retry rate >5% of total events
- Event dispatch time >100ms (p95)

---

## Troubleshooting

### Events Not Firing

1. Check event registration: `php artisan event:list`
2. Verify event is dispatched: Add `Log::info()` before dispatch
3. Check queue workers are running: `ps aux | grep queue:work`

### Listeners Not Executing

1. Check queued jobs: `php artisan queue:failed`
2. Verify listener is registered: `php artisan event:list`
3. Check Redis connection: `redis-cli ping`
4. Run queue worker manually: `php artisan queue:work --once`

### Performance Issues

1. Run performance tests: `php artisan test --filter=EventPerformanceTest`
2. Profile event dispatch: Add timing logs
3. Check queue depth: May need more workers
4. Consider caching event metadata

---

## Future Enhancements

**Phase 2 - Additional Events:**
- Team events (RoleChanged, MemberRemoved)
- SSL events (CertificateRequested, CertificateIssued)
- Security events (VpsCredentialsRotated, ApiTokenRotated)
- Quota events (SiteQuotaExceeded, StorageQuotaExceeded)

**Phase 3 - Advanced Patterns:**
- Event Sourcing (events as source of truth)
- Event Store (dedicated event storage)
- Event Replay (rebuild state from events)
- Webhook System (external event subscriptions)
- CQRS (separate read/write models)

---

## References

- [Laravel Events Documentation](https://laravel.com/docs/12.x/events)
- [Laravel Queue Documentation](https://laravel.com/docs/12.x/queues)
- [Domain-Driven Design: Events](https://martinfowler.com/eaaDev/DomainEvent.html)
- [Event-Driven Architecture Patterns](https://microservices.io/patterns/data/event-driven-architecture.html)

---

**Questions or Issues?** Contact the development team or open an issue in GitHub.
