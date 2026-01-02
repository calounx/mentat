# CHOM Jobs & Queue Quick Reference

## Quick Test Commands

```bash
# Run all job tests
php artisan test tests/Unit/Jobs/ tests/Feature/Jobs/

# Run specific job test
php artisan test tests/Unit/Jobs/CreateBackupJobTest.php

# Run with detailed output
php artisan test tests/Unit/Jobs/ --testdox

# Run command tests
php artisan test tests/Feature/Commands/
```

## Job Dispatch Examples

```php
use App\Jobs\CreateBackupJob;
use App\Jobs\ProvisionSiteJob;
use App\Jobs\IssueSslCertificateJob;

// Simple dispatch
dispatch(new CreateBackupJob($site));

// Delayed dispatch
dispatch(new CreateBackupJob($site))->delay(now()->addMinutes(10));

// Specific queue
dispatch(new CreateBackupJob($site))->onQueue('high');

// Chain jobs
Bus::chain([
    new ProvisionSiteJob($site),
    new IssueSslCertificateJob($site),
])->dispatch();

// Batch jobs
Bus::batch([
    new CreateBackupJob($site1),
    new CreateBackupJob($site2),
])->dispatch();
```

## Queue Worker Commands

```bash
# Start worker (process all jobs)
php artisan queue:work

# Process one job only
php artisan queue:work --once

# Specific queue priority
php artisan queue:work --queue=high,default,low

# With limits
php artisan queue:work --memory=128 --timeout=60 --max-jobs=100

# View failed jobs
php artisan queue:failed

# Retry all failed jobs
php artisan queue:retry all
```

## Console Commands

```bash
# Database backup
php artisan backup:database
php artisan backup:database --encrypt
php artisan backup:database --encrypt --upload
php artisan backup:database --test

# Clean old backups
php artisan backup:clean --dry-run
php artisan backup:clean --force

# Rotate secrets
php artisan secrets:rotate --dry-run
php artisan secrets:rotate --all
php artisan secrets:rotate --vps=123 --force
```

## Job Configuration

| Job | Queue | Tries | Timeout | Backoff |
|-----|-------|-------|---------|---------|
| CreateBackupJob | default | 3 | 120s | 120s |
| RestoreBackupJob | default | 2 | 90s | 60s |
| ProvisionSiteJob | default | 3 | 90s | 60s |
| IssueSslCertificateJob | default | 3 | 120s | 120s |
| RotateVpsCredentialsJob | high | 3 | 300s | - |

## Test File Locations

```
tests/Unit/Jobs/
├── CreateBackupJobTest.php (11 tests)
├── RestoreBackupJobTest.php (10 tests)
├── ProvisionSiteJobTest.php (10 tests)
├── IssueSslCertificateJobTest.php (9 tests)
└── RotateVpsCredentialsJobTest.php (7 tests)

tests/Feature/Jobs/
├── QueueConnectionTest.php (9 tests)
└── JobChainingTest.php (12 tests)

tests/Feature/Commands/
├── BackupDatabaseCommandTest.php (8 tests)
├── CleanOldBackupsCommandTest.php (7 tests)
└── RotateSecretsCommandTest.php (9 tests)
```

## Events Dispatched

```php
// Backup events
BackupCreated::dispatch($backup, $site);
BackupCompleted::dispatch($backup, $size, $duration);
BackupFailed::dispatch($siteId, $backupType, $error);

// Site events
SiteProvisioned::dispatch($site, $metadata);
SiteProvisioningFailed::dispatch($site, $error);
```

## Testing Patterns

```php
// Test job dispatch
Queue::fake();
dispatch(new MyJob());
Queue::assertPushed(MyJob::class);

// Test events
Event::fake();
// ... trigger event
Event::assertDispatched(MyEvent::class);

// Mock service
$service = $this->mock(MyService::class);
$service->shouldReceive('method')->once()->andReturn($result);
```

## Common Issues

**Permission Error**: `chmod -R 777 storage/`
**Redis Connection**: Check `REDIS_HOST` in `.env`
**Failed Jobs**: `php artisan queue:retry all`
**Clear Failed**: `php artisan queue:flush`

## Monitoring

```bash
# Check queue status
php artisan queue:monitor default --max=100

# List scheduled tasks
php artisan schedule:list

# Run scheduler
php artisan schedule:run
```
