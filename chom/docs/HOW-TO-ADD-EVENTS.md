# How to Add New Events - Quick Guide

> **5-Minute Guide** for adding new domain events to CHOM

## Quick Steps

### 1. Create Event Class (2 min)

```bash
# Create event file
touch app/Events/Site/YourEventName.php
```

```php
<?php

namespace App\Events\Site;

use App\Events\AbstractDomainEvent;
use App\Models\Site;

class YourEventName extends AbstractDomainEvent
{
    public function __construct(
        public readonly Site $site,
        public readonly string $additionalData,
        ?string $actorId = null
    ) {
        // 'system' if automated, 'user' if user-triggered
        parent::__construct($actorId, 'system');
    }

    public function getMetadata(): array
    {
        return array_merge(parent::getMetadata(), [
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'additional_data' => $this->additionalData,
        ]);
    }
}
```

**For Deleted Entities:** Use primitive data (strings) instead of models:

```php
class SiteDeleted extends AbstractDomainEvent
{
    public function __construct(
        public readonly string $siteId,  // Not Site $site
        public readonly string $tenantId,
        public readonly string $domain,
        ?string $actorId = null
    ) {
        parent::__construct($actorId);
    }
}
```

---

### 2. Register Event (1 min)

```php
// app/Providers/EventServiceProvider.php

protected $listen = [
    \App\Events\Site\YourEventName::class => [
        \App\Listeners\RecordAuditLog::class,
        \App\Listeners\RecordMetrics::class . '@handleYourEvent',
        \App\Listeners\SendNotification::class . '@handleYourEvent',
    ],
];
```

**Listener Method Naming:**
- Without `@method` → calls `handle()` by default
- With `@method` → calls specific method (e.g., `@handleYourEvent`)

---

### 3. Dispatch Event (1 min)

**In Controller/Service/Job:**

```php
// After the business action completes
YourEventName::dispatch($site, 'some data');
```

**For Deleted Entities:**

```php
// Capture data BEFORE deletion
$siteId = $site->id;
$tenantId = $site->tenant_id;
$domain = $site->domain;

// Delete
$site->delete();

// Emit event with primitive data
SiteDeleted::dispatch($siteId, $tenantId, $domain);
```

---

### 4. Add Listener Methods (Optional, 1 min)

If your event needs custom listener logic:

```php
// app/Listeners/RecordMetrics.php

public function handleYourEvent(YourEventName $event): void
{
    $this->observability->incrementCounter('your_event_total', 1, [
        'site_id' => $event->site->id,
    ]);

    Log::debug('Metric recorded: your_event_total', [
        'site_id' => $event->site->id,
    ]);
}
```

```php
// app/Listeners/SendNotification.php

public function handleYourEvent(YourEventName $event): void
{
    Log::info('TODO: Send notification for your event', [
        'site_id' => $event->site->id,
        'data' => $event->additionalData,
    ]);
}
```

---

## Checklist

- [ ] Event class created in `app/Events/`
- [ ] Event extends `AbstractDomainEvent`
- [ ] Event registered in `EventServiceProvider`
- [ ] Event dispatched in business logic
- [ ] Listener methods added (if needed)
- [ ] Tests written
- [ ] Documentation updated

---

## Testing Your Event

```php
// tests/Unit/Events/YourEventTest.php

public function test_your_event_structure(): void
{
    $site = Site::factory()->create();

    $event = new YourEventName($site, 'test data');

    $this->assertEquals($site->id, $event->site->id);
    $this->assertEquals('test data', $event->additionalData);
}

public function test_your_event_metadata(): void
{
    $site = Site::factory()->create();
    $event = new YourEventName($site, 'test data');

    $metadata = $event->getMetadata();

    $this->assertArrayHasKey('site_id', $metadata);
    $this->assertArrayHasKey('additional_data', $metadata);
}
```

```php
// tests/Integration/YourEventIntegrationTest.php

public function test_your_event_is_dispatched(): void
{
    Event::fake([YourEventName::class]);

    // Trigger business logic that should dispatch event
    $this->performAction();

    Event::assertDispatched(YourEventName::class, function ($event) {
        return $event->site->id === $this->site->id;
    });
}
```

---

## Common Patterns

### Pattern 1: Success/Failure Events

```php
// Success event
SiteProvisioned::dispatch($site, ['duration' => 5.2]);

// Failure event
SiteProvisioningFailed::dispatch($site, $errorMessage, $stackTrace);
```

### Pattern 2: Timed Events

```php
$startTime = microtime(true);

// ... perform action ...

$duration = microtime(true) - $startTime;
YourCompletedEvent::dispatch($entity, $duration);
```

### Pattern 3: Queued vs Synchronous Listeners

**Queued (async):**
- Use for: Email, notifications, cache updates, audit logs
- Trait: `implements ShouldQueue`

**Synchronous (immediate):**
- Use for: Metrics, critical state updates
- Trait: None (just register in `$listen`)

---

## Examples from CHOM

### Example 1: Site Creation

```php
// In SiteCreationService::createSite()
$site = Site::create([...]);
SiteCreated::dispatch($site, $tenant);
```

### Example 2: Site Provisioning

```php
// In ProvisionSiteJob::handle()
$startTime = microtime(true);
$result = $provisioner->provision($site, $vps);

if ($result['success']) {
    $duration = microtime(true) - $startTime;
    SiteProvisioned::dispatch($site, ['duration' => $duration]);
} else {
    SiteProvisioningFailed::dispatch($site, $result['output']);
}
```

### Example 3: Backup Completion

```php
// In CreateBackupJob::handle()
$duration = (int) round(microtime(true) - $startTime);
BackupCompleted::dispatch($backup, $sizeBytes, $duration);
```

---

## Need Help?

- Read the full documentation: `docs/EVENT-DRIVEN-ARCHITECTURE.md`
- Check existing events: `app/Events/`
- Run tests: `php artisan test --filter=Event`
- List registered events: `php artisan event:list`

---

## Tips

✅ **DO:**
- Emit events AFTER state changes (after DB write)
- Include all necessary context in event properties
- Use meaningful event names (`SiteProvisioned`, not `SiteUpdated`)
- Write tests for your events

❌ **DON'T:**
- Emit events inside database transactions (unless necessary)
- Include sensitive data in event metadata
- Use events for trivial actions (getters, setters)
- Forget to register your event in `EventServiceProvider`
