# Backup Module

## Overview

The Backup module is a bounded context responsible for all backup-related operations within the CHOM application. It handles backup creation, restoration, scheduling, retention management, and integrity validation.

## Responsibilities

- Backup creation (full, files-only, database-only)
- Backup restoration to original or different sites
- Automated backup scheduling
- Retention policy enforcement
- Backup integrity validation
- Backup storage management

## Architecture

### Service Contracts

- `BackupStorageInterface` - Backup file storage operations

### Services

- `BackupOrchestrator` - Orchestrates backup operations (wraps BackupService)
- `BackupStorageService` - Implements backup storage operations

### Value Objects

- `BackupConfiguration` - Encapsulates backup settings (type, retention, compression, encryption)
- `RetentionPolicy` - Encapsulates retention rules and cleanup logic

## Usage Examples

### Creating Backups

```php
use App\Modules\Backup\Services\BackupOrchestrator;
use App\Modules\Backup\ValueObjects\BackupConfiguration;

$orchestrator = app(BackupOrchestrator::class);

// Create full backup with 30-day retention
$config = BackupConfiguration::full(retentionDays: 30);
$backup = $orchestrator->createBackup($siteId, $config);

// Create encrypted files-only backup
$config = BackupConfiguration::filesOnly(retentionDays: 14)
    ->withEncryption();
$backup = $orchestrator->createBackup($siteId, $config);

// Create database-only backup
$config = BackupConfiguration::databaseOnly(retentionDays: 7);
$backup = $orchestrator->createBackup($siteId, $config);
```

### Restoring Backups

```php
// Restore to original site
$success = $orchestrator->restoreBackup($backupId);

// Restore to different site
$success = $orchestrator->restoreBackup($backupId, $targetSiteId);
```

### Backup Scheduling

```php
// Schedule daily backups
$success = $orchestrator->scheduleAutomaticBackup($siteId, 'daily');

// Schedule weekly backups
$success = $orchestrator->scheduleAutomaticBackup($siteId, 'weekly');

// Schedule monthly backups
$success = $orchestrator->scheduleAutomaticBackup($siteId, 'monthly');
```

### Retention Policies

```php
use App\Modules\Backup\ValueObjects\RetentionPolicy;

// Apply default retention policy (10 backups, 30 days)
$policy = RetentionPolicy::default();
$deletedCount = $orchestrator->applyRetentionPolicy($siteId, $policy);

// Apply aggressive cleanup (5 backups, 7 days)
$policy = RetentionPolicy::aggressive();
$deletedCount = $orchestrator->applyRetentionPolicy($siteId, $policy);

// Apply compliance policy (100 backups, 365 days)
$policy = RetentionPolicy::compliance();
$deletedCount = $orchestrator->applyRetentionPolicy($siteId, $policy);

// Custom policy
$policy = new RetentionPolicy(
    maxBackups: 20,
    maxAgeDays: 60,
    keepMinimumOne: true
);
```

### Integrity Validation

```php
// Validate backup integrity
$results = $orchestrator->validateIntegrity($backupId);

// Results include:
// - file_exists: bool
// - size_match: bool
// - checksum_match: bool|null
// - not_expired: bool
// - valid: bool (overall status)
```

### Backup Statistics

```php
// Get comprehensive backup statistics
$stats = $orchestrator->getStatistics($siteId);

// Returns:
// - total_backups
// - completed_backups
// - failed_backups
// - total_size_bytes/mb/gb
// - last_backup_at
// - last_backup_status
```

### Storage Operations

```php
use App\Modules\Backup\Contracts\BackupStorageInterface;

$storage = app(BackupStorageInterface::class);

// Store backup file
$storage->store('/tmp/backup.tar.gz', 'backups/site/backup.tar.gz');

// Retrieve backup file
$storage->retrieve('backups/site/backup.tar.gz', '/tmp/restore.tar.gz');

// Check if exists
$exists = $storage->exists('backups/site/backup.tar.gz');

// Get file size
$size = $storage->getSize('backups/site/backup.tar.gz');

// Calculate checksum
$checksum = $storage->getChecksum('backups/site/backup.tar.gz');

// Delete backup
$storage->delete('backups/site/backup.tar.gz');
```

## Value Objects

### BackupConfiguration

Provides type-safe backup configuration:

- Backup type validation (full, files, database)
- Retention period enforcement (1-365 days)
- Compression and encryption options
- Fluent builder methods

### RetentionPolicy

Encapsulates retention rules:

- Maximum backup count limit
- Maximum age in days
- Minimum backup guarantee
- Age-based deletion logic
- Predefined policies (default, aggressive, conservative, compliance)

## Module Dependencies

This module depends on:

- `BackupService` (existing service)
- SiteBackup model and repository
- Laravel Storage for file operations
- Job queue for async backup operations

## Integration with Existing Code

This module wraps the existing `BackupService` to:

1. Provide a clean module interface
2. Add value objects for type safety
3. Implement retention policy logic
4. Add backup statistics and validation
5. Maintain backward compatibility

## Events

The module uses existing backup events:

- `BackupCreated` - When backup is created
- `BackupRestored` - When backup is restored
- `BackupFailed` - When backup operation fails
- `BackupDeleted` - When backup is deleted

## Security Considerations

1. Backups are stored securely with optional encryption
2. Integrity validation using checksums
3. Access control through site policies
4. Audit logging for all operations
5. Automated cleanup of expired backups

## Performance Considerations

1. Backup operations run asynchronously via jobs
2. Large backups are compressed to save storage
3. Checksums are calculated efficiently
4. Retention cleanup runs as scheduled task

## Testing

Test the module using:

```bash
php artisan test --filter=Backup
```

## Future Enhancements

- Incremental backup support
- Multi-cloud backup storage
- Backup encryption at rest
- Point-in-time recovery
- Automated backup testing/verification
- Backup performance metrics
- Cross-region backup replication
