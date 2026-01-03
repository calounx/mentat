# Infrastructure Interfaces - Quick Reference Guide

## Quick Start

### 1. Enable Infrastructure Service Provider

Already registered in the application. If needed, add to your bootstrap/app.php or config:

```php
App\Providers\InfrastructureServiceProvider::class
```

### 2. Configure Environment

Add to `.env`:

```env
# VPS Provider
VPS_PROVIDER=local

# Observability
OBSERVABILITY_DRIVER=null

# Notifications
NOTIFICATION_CHANNELS=log

# Storage
STORAGE_DRIVER=local
```

## Common Usage Patterns

### VPS Management

```php
use App\Contracts\Infrastructure\VpsProviderInterface;
use App\ValueObjects\VpsSpecification;

class ServerManager
{
    public function __construct(
        private VpsProviderInterface $vps
    ) {}

    public function createServer()
    {
        $spec = VpsSpecification::medium();
        $server = $this->vps->createServer($spec);

        // Execute setup commands
        $this->vps->executeCommand(
            $server['id'],
            'apt-get update && apt-get upgrade -y'
        );

        return $server;
    }
}
```

### Metrics and Monitoring

```php
use App\Contracts\Infrastructure\ObservabilityInterface;

class MetricsService
{
    public function __construct(
        private ObservabilityInterface $metrics
    ) {}

    public function trackDeployment()
    {
        $trace = $this->metrics->startTrace('deployment');

        try {
            // Deployment logic
            $this->metrics->incrementCounter('deployments.success');
        } catch (\Exception $e) {
            $this->metrics->logError($e);
            $this->metrics->incrementCounter('deployments.failed');
        } finally {
            $this->metrics->endTrace($trace);
        }
    }
}
```

### Send Notifications

```php
use App\Contracts\Infrastructure\NotificationInterface;
use App\ValueObjects\EmailNotification;

class AlertService
{
    public function __construct(
        private NotificationInterface $notifier
    ) {}

    public function sendAlert(string $message)
    {
        $email = new EmailNotification(
            to: ['admin@example.com'],
            subject: 'System Alert',
            body: $message
        );

        $this->notifier->sendEmail($email);
    }
}
```

### File Storage

```php
use App\Contracts\Infrastructure\StorageInterface;

class BackupManager
{
    public function __construct(
        private StorageInterface $storage
    ) {}

    public function storeBackup(string $content)
    {
        $path = 'backups/' . date('Y-m-d-His') . '.sql';
        $this->storage->store($path, $content);

        return $this->storage->temporaryUrl(
            $path,
            now()->addHours(24)
        );
    }
}
```

### Caching

```php
use App\Contracts\Infrastructure\CacheInterface;

class UserRepository
{
    public function __construct(
        private CacheInterface $cache
    ) {}

    public function getUser(int $id)
    {
        return $this->cache->remember(
            "user:{$id}",
            3600,
            fn() => User::find($id)
        );
    }

    public function clearUserCache()
    {
        $this->cache->tags(['users'])->flush();
    }
}
```

## Value Object Cheat Sheet

### VpsSpecification

```php
// Predefined sizes
$small = VpsSpecification::small();
$medium = VpsSpecification::medium();
$large = VpsSpecification::large();

// Custom specification
$custom = new VpsSpecification(
    cpuCores: 4,
    ramMb: 8192,
    diskGb: 200,
    region: 'us-east-1',
    os: 'ubuntu-22.04'
);

// Modify immutably
$modified = $custom->withCpuCores(8);

// Get cost estimate
$monthlyCost = $custom->getMonthlyCost();
```

### Email Notification

```php
$email = new EmailNotification(
    to: ['user@example.com', 'admin@example.com'],
    subject: 'Welcome to CHOM',
    body: '<h1>Welcome!</h1><p>Your account is ready.</p>',
    cc: ['manager@example.com'],
    attachments: ['/path/to/guide.pdf'],
    from: 'noreply@chom.app',
    isHtml: true
);
```

### SMS Notification

```php
$sms = new SmsNotification(
    phone: '+12345678900',  // E.164 format
    message: 'Your verification code is 123456'
);

// Check segment count
$segments = $sms->getSegmentCount();
```

### Command Result

```php
$result = $vps->executeCommand($serverId, 'ls -la');

if ($result->isSuccessful()) {
    echo $result->output;
    echo "Executed in {$result->executionTime}s";
} else {
    echo "Error: {$result->error}";
    echo "Exit code: {$result->exitCode}";
}

// Get output as array
$lines = $result->getOutputLines();
```

## Testing Quick Reference

### Use Test Implementations

```php
// In your test
use App\Infrastructure\Cache\ArrayCacheAdapter;
use App\Infrastructure\Observability\NullObservability;
use App\Infrastructure\Notification\LogNotifier;

public function test_service_behavior()
{
    // No Redis needed
    $cache = new ArrayCacheAdapter();

    // No Prometheus needed
    $metrics = new NullObservability();

    // No email server needed
    $notifier = new LogNotifier();

    $service = new MyService($cache, $metrics, $notifier);

    // Test your service
    $result = $service->performAction();

    // Assert cache was used
    $this->assertTrue($cache->has('expected_key'));
}
```

### Mock Providers

```php
use App\Contracts\Infrastructure\VpsProviderInterface;

public function test_server_creation()
{
    $mock = $this->createMock(VpsProviderInterface::class);
    $mock->method('createServer')
         ->willReturn([
             'id' => 'test-123',
             'ip_address' => '192.168.1.1',
             'status' => 'online'
         ]);

    $manager = new ServerManager($mock);
    $result = $manager->createServer();

    $this->assertEquals('test-123', $result['id']);
}
```

## Configuration Quick Reference

### VPS Providers

```env
# Local (Docker-based)
VPS_PROVIDER=local
VPS_LOCAL_USE_DOCKER=true

# DigitalOcean
VPS_PROVIDER=digitalocean
DIGITALOCEAN_TOKEN=your-api-token
DIGITALOCEAN_SSH_KEY_ID=12345

# Generic SSH
VPS_PROVIDER=ssh
SSH_PRIVATE_KEY_PATH=/path/to/key
```

### Observability

```env
# Prometheus
OBSERVABILITY_DRIVER=prometheus
PROMETHEUS_PUSH_GATEWAY_URL=http://localhost:9091
PROMETHEUS_NAMESPACE=chom

# Disabled (for testing)
OBSERVABILITY_DRIVER=null
```

### Notifications

```env
# Email only
NOTIFICATION_CHANNELS=email

# Multiple channels
NOTIFICATION_CHANNELS=email,slack,log

# Slack configuration
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### Storage

```env
# Local filesystem
STORAGE_DRIVER=local

# AWS S3
STORAGE_DRIVER=s3
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=your-bucket
```

### Cache

```env
# Redis
CACHE_DEFAULT=redis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

# Array (in-memory, testing only)
CACHE_DEFAULT=array
```

## Common Gotchas

### 1. Don't Type-Hint Implementations

```php
// ❌ Bad - tightly coupled
public function __construct(LocalVpsProvider $vps) {}

// ✅ Good - loosely coupled
public function __construct(VpsProviderInterface $vps) {}
```

### 2. Always Handle Exceptions

```php
// ❌ Bad - no error handling
$server = $vps->createServer($spec);

// ✅ Good - proper error handling
try {
    $server = $vps->createServer($spec);
} catch (RuntimeException $e) {
    Log::error('Server creation failed', ['error' => $e->getMessage()]);
    throw $e;
}
```

### 3. Use Value Objects

```php
// ❌ Bad - primitive obsession
public function createServer(int $cpu, int $ram, int $disk, string $os) {}

// ✅ Good - value object
public function createServer(VpsSpecification $spec) {}
```

### 4. Remember to Flush

```php
// Observability metrics should be flushed
// This happens automatically on app shutdown, but you can force it:
$observability->flush();
```

### 5. Cache Tags Require Redis

```php
// Array cache supports tags, but they're in-memory only
$cache = new ArrayCacheAdapter();
$cache->tags(['users'])->put('key', 'value');  // Works

// Redis cache has persistent tags
$cache = new RedisCacheAdapter();
$cache->tags(['users'])->put('key', 'value');  // Persisted
```

## Interface Method Signatures

### VpsProviderInterface

```php
createServer(VpsSpecification $spec): array
deleteServer(string $serverId): bool
getServerStatus(string $serverId): ServerStatus
executeCommand(string $serverId, string $command, int $timeout = 300): CommandResult
uploadFile(string $serverId, string $localPath, string $remotePath): bool
downloadFile(string $serverId, string $remotePath, string $localPath): bool
isServerReachable(string $serverId): bool
getServerMetrics(string $serverId): array
restartServer(string $serverId): bool
getProviderName(): string
```

### ObservabilityInterface

```php
recordMetric(string $name, float $value, array $tags = []): void
incrementCounter(string $name, int $value = 1, array $tags = []): void
recordTiming(string $name, int $milliseconds, array $tags = []): void
recordEvent(string $name, array $data = []): void
startTrace(string $name, array $context = []): TraceId
endTrace(TraceId $traceId, array $metadata = []): void
logError(Throwable $exception, array $context = []): void
recordGauge(string $name, float $value, array $tags = []): void
recordHistogram(string $name, float $value, array $tags = []): void
flush(): void
```

### NotificationInterface

```php
sendEmail(EmailNotification $notification): bool
sendSms(SmsNotification $notification): bool
sendSlack(SlackNotification $notification): bool
sendWebhook(WebhookNotification $notification): bool
sendInApp(InAppNotification $notification): bool
getSupportedChannels(): array
```

### StorageInterface

```php
store(string $path, $contents, array $options = []): bool
get(string $path): ?string
exists(string $path): bool
delete(string $path): bool
size(string $path): int
url(string $path): string
temporaryUrl(string $path, DateTimeInterface $expiration): string
copy(string $from, string $to): bool
move(string $from, string $to): bool
listFiles(string $directory, bool $recursive = false): array
getMetadata(string $path): array
```

### CacheInterface

```php
get(string $key, $default = null)
put(string $key, $value, ?int $ttl = null): bool
forget(string $key): bool
has(string $key): bool
remember(string $key, ?int $ttl, Closure $callback)
flush(): bool
tags(array $tags): self
increment(string $key, int $value = 1): int
decrement(string $key, int $value = 1): int
forever(string $key, $value): bool
many(array $keys): array
putMany(array $values, ?int $ttl = null): bool
```

## Available Implementations

### VPS Providers
- `LocalVpsProvider` - Docker-based local development
- `DigitalOceanVpsProvider` - DigitalOcean API
- `GenericSshVpsProvider` - Generic SSH access

### Observability
- `PrometheusObservability` - Prometheus metrics
- `NullObservability` - No-op for testing

### Notifications
- `MultiChannelNotifier` - Composite (multiple channels)
- `EmailNotifier` - Laravel Mail
- `LogNotifier` - Logging (testing/development)

### Storage
- `LocalStorageAdapter` - Local filesystem
- `S3StorageAdapter` - AWS S3 or compatible

### Cache
- `RedisCacheAdapter` - Redis backend
- `ArrayCacheAdapter` - In-memory (testing)

## Need Help?

- **Full Documentation**: See `INFRASTRUCTURE-INTERFACES.md`
- **Implementation Details**: See `INTERFACE-IMPLEMENTATION-SUMMARY.md`
- **Tests**: Check `/tests/Unit/Infrastructure/` for examples
- **Configuration**: See `config/infrastructure.php`

## Common Commands

```bash
# Run infrastructure tests
php artisan test --filter Infrastructure

# Run specific test
php artisan test tests/Unit/Infrastructure/Vps/LocalVpsProviderTest.php

# Clear cache
php artisan cache:clear

# Check service provider registration
php artisan about
```
