# Infrastructure Services Module

## Overview

The Infrastructure Services module is a bounded context responsible for core infrastructure operations including VPS management, observability, notifications, and storage within the CHOM application.

## Responsibilities

- VPS server provisioning and management
- System monitoring and observability
- Multi-channel notification delivery
- File storage operations
- Health checks and metrics

## Architecture

### Service Contracts

- `VpsProviderInterface` - VPS server management operations
- `ObservabilityInterface` - Monitoring, logging, and metrics
- `NotificationInterface` - Multi-channel notification delivery
- `StorageInterface` - File storage operations

### Services

- `VpsManager` - Implements VPS management operations
- `ObservabilityService` - Implements monitoring and logging
- `NotificationService` - Implements notification delivery
- `StorageService` - Implements storage operations

### Value Objects

- `VpsSpecification` - Encapsulates VPS server specifications

## Usage Examples

### VPS Management

```php
use App\Modules\Infrastructure\Contracts\VpsProviderInterface;
use App\Modules\Infrastructure\ValueObjects\VpsSpecification;

$vpsManager = app(VpsProviderInterface::class);

// Provision VPS using predefined specifications
$spec = VpsSpecification::medium('digitalocean', 'nyc1');
$vps = $vpsManager->provision($spec);

// Custom specification
$spec = new VpsSpecification(
    provider: 'digitalocean',
    region: 'nyc1',
    memoryMb: 4096,
    diskGb: 100,
    cpuCores: 2
);

// Check VPS health
$health = $vpsManager->checkHealth($vpsId);

// Get resource usage
$usage = $vpsManager->getResourceUsage($vpsId);

// Find available VPS
$vps = $vpsManager->findAvailable(minMemoryMb: 4096, minDiskGb: 50);

// Deprovision VPS
$success = $vpsManager->deprovision($vpsId);
```

### Observability

```php
use App\Modules\Infrastructure\Contracts\ObservabilityInterface;

$observability = app(ObservabilityInterface::class);

// Record metrics
$observability->recordMetric('site.response_time', 145.5, [
    'site_id' => $siteId,
    'region' => 'us-east',
]);

// Increment counters
$observability->incrementCounter('api.requests', 1, [
    'endpoint' => '/api/sites',
    'status' => 200,
]);

// Record timings
$observability->recordTiming('backup.duration', 5432.1, [
    'backup_type' => 'full',
]);

// Log events
$observability->logEvent('info', 'Site provisioned', [
    'site_id' => $siteId,
    'domain' => 'example.com',
]);

// Record exceptions
try {
    // Some operation
} catch (\Exception $e) {
    $observability->recordException($e, [
        'context' => 'site_provisioning',
    ]);
}

// Health checks
$health = $observability->checkHealth();
// Returns: status, checks (database, cache, disk, memory)
```

### Notifications

```php
use App\Modules\Infrastructure\Contracts\NotificationInterface;

$notifications = app(NotificationInterface::class);

// Send email
$notifications->sendEmail(
    to: 'admin@example.com',
    subject: 'Site Provisioned',
    message: 'Your site has been successfully provisioned.',
    data: ['site_id' => $siteId]
);

// Send Slack notification
$notifications->sendSlack(
    channel: '#alerts',
    message: 'Critical: Backup failed for site XYZ',
    data: ['site_id' => $siteId]
);

// Send SMS
$notifications->sendSms(
    phone: '+1234567890',
    message: 'Your site is ready!'
);

// Send webhook
$notifications->sendWebhook(
    url: 'https://example.com/webhooks/site-created',
    payload: ['site_id' => $siteId, 'domain' => 'example.com']
);

// Broadcast to multiple channels
$results = $notifications->broadcast(
    channels: [
        'email' => ['to' => 'admin@example.com'],
        'slack' => ['channel' => '#alerts'],
    ],
    message: 'Site provisioning completed',
    data: ['subject' => 'Site Ready']
);
```

### Storage Operations

```php
use App\Modules\Infrastructure\Contracts\StorageInterface;

$storage = app(StorageInterface::class);

// Store file
$storage->put('uploads/backup.tar.gz', $fileContents);

// Retrieve file
$contents = $storage->get('uploads/backup.tar.gz');

// Check existence
$exists = $storage->exists('uploads/backup.tar.gz');

// Delete file
$storage->delete('uploads/backup.tar.gz');

// Get file info
$size = $storage->size('uploads/backup.tar.gz');
$lastModified = $storage->lastModified('uploads/backup.tar.gz');

// List directory
$files = $storage->listFiles('uploads');

// Get public URL
$url = $storage->url('public/image.jpg');

// Generate temporary URL (expires in 1 hour)
$tempUrl = $storage->temporaryUrl('private/file.pdf', 3600);
```

## Value Objects

### VpsSpecification

Provides type-safe VPS configuration:

- Predefined sizes (small, medium, large)
- Memory/disk/CPU validation
- IP address validation
- Provider and region configuration

## Module Dependencies

This module depends on:

- VpsServerRepository for VPS data
- Laravel Storage for file operations
- Laravel Mail for email delivery
- Laravel HTTP for webhook/API calls
- Laravel Cache for metrics storage

## Integration Points

This module provides infrastructure services used by:

- SiteHosting module (VPS management)
- Backup module (storage operations)
- All modules (observability and notifications)

## Security Considerations

1. VPS credentials are encrypted
2. Webhook URLs are validated
3. File paths are sanitized
4. Storage operations use Laravel's security features
5. All operations are logged for auditing

## Performance Considerations

1. Metrics are cached for aggregation
2. File operations use streaming for large files
3. Notifications are queued for async delivery
4. Health checks are lightweight

## Testing

Test the module using:

```bash
php artisan test --filter=Infrastructure
```

## Future Enhancements

- Multi-cloud VPS provider support
- Advanced metrics aggregation and dashboards
- Push notification support
- CDN integration
- Object storage support (S3, etc.)
- Real-time health monitoring
- Automated scaling based on metrics
- Cost optimization recommendations
