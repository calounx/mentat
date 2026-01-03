# Domain Services Quick Reference

## Service Method Signatures

### SiteManagementService

```php
// Constructor
__construct(
    SiteRepository $siteRepository,
    TenantRepository $tenantRepository,
    VpsServerRepository $vpsServerRepository,
    QuotaService $quotaService
)

// Methods
provisionSite(array $data, string $tenantId): Site
updateSiteConfiguration(string $siteId, array $config): Site
changePHPVersion(string $siteId, string $version): Site
enableSSL(string $siteId): Site
disableSite(string $siteId, string $reason = ''): Site
enableSite(string $siteId): Site
deleteSite(string $siteId): bool
getSiteMetrics(string $siteId): array
```

### BackupService

```php
// Constructor
__construct(
    BackupRepository $backupRepository,
    SiteRepository $siteRepository,
    QuotaService $quotaService
)

// Methods
createBackup(string $siteId, string $type = 'full', int $retentionDays = 30): SiteBackup
restoreBackup(string $backupId, string $targetSiteId = null): bool
deleteBackup(string $backupId): bool
scheduleAutomaticBackup(string $siteId, string $frequency): bool
getBackupsBySchedule(string $siteId): Collection
cleanupExpiredBackups(string $siteId = null): int
validateBackupIntegrity(string $backupId): array
```

### TeamManagementService

```php
// Constructor
__construct(UserRepository $userRepository)

// Methods
inviteMember(string $organizationId, string $email, string $role, array $permissions = []): TeamInvitation
acceptInvitation(string $invitationToken, string $userId): bool
cancelInvitation(string $invitationId): bool
updateMemberRole(string $userId, string $newRole): User
updateMemberPermissions(string $userId, array $permissions): User
removeMember(string $userId, string $organizationId): bool
transferOwnership(string $organizationId, string $newOwnerId, string $currentOwnerId): bool
getPendingInvitations(string $organizationId): Collection
```

### QuotaService

```php
// Constructor
__construct(
    TenantRepository $tenantRepository,
    SiteRepository $siteRepository,
    BackupRepository $backupRepository
)

// Methods
checkSiteQuota(string $tenantId): array
checkStorageQuota(string $tenantId): array
checkBackupQuota(string $siteId): array
updateStorageUsage(string $siteId, int $usedMb): void
getTenantUsage(string $tenantId): array
canCreateSite(string $tenantId): bool
canCreateBackup(string $siteId): bool
getQuotaLimitsByTier(string $tier): array
```

## Usage Examples

### Provisioning a Site

```php
use App\Services\SiteManagementService;

$siteService = app(SiteManagementService::class);

$site = $siteService->provisionSite([
    'domain' => 'example.com',
    'site_type' => 'wordpress',
    'php_version' => '8.2',
    'settings' => [
        'wp_version' => '6.4',
    ],
], $tenantId);
```

### Creating a Backup

```php
use App\Services\BackupService;

$backupService = app(BackupService::class);

$backup = $backupService->createBackup(
    siteId: $site->id,
    type: 'full',
    retentionDays: 30
);
```

### Inviting a Team Member

```php
use App\Services\TeamManagementService;

$teamService = app(TeamManagementService::class);

$invitation = $teamService->inviteMember(
    organizationId: $organization->id,
    email: 'newmember@example.com',
    role: 'member',
    permissions: ['manage_sites', 'view_analytics']
);
```

### Checking Quotas

```php
use App\Services\QuotaService;

$quotaService = app(QuotaService::class);

// Check if can create site
if ($quotaService->canCreateSite($tenantId)) {
    // Proceed with site creation
}

// Get detailed quota info
$siteQuota = $quotaService->checkSiteQuota($tenantId);
// Returns: ['current' => 3, 'limit' => 5, 'available' => true, 'percentage' => 60.0]

$storageQuota = $quotaService->checkStorageQuota($tenantId);
// Returns: ['used_gb' => 5.2, 'limit_gb' => 10, 'percentage' => 52.0, ...]
```

## Return Value Structures

### getSiteMetrics()

```php
[
    'site_id' => 'uuid',
    'domain' => 'example.com',
    'status' => 'active',
    'php_version' => '8.2',
    'ssl_enabled' => true,
    'ssl_expires_at' => '2024-12-31T23:59:59Z',
    'ssl_expiring_soon' => false,
    'storage_used_mb' => 512,
    'storage_used_gb' => 0.5,
    'backups_count' => 5,
    'last_backup_at' => '2024-01-01T00:00:00Z',
    'created_at' => '2023-01-01T00:00:00Z',
    'uptime_days' => 365,
]
```

### checkSiteQuota()

```php
[
    'current' => 3,
    'limit' => 5,
    'limit_display' => '5' | 'Unlimited',
    'available' => true,
    'percentage' => 60.0,
]
```

### checkStorageQuota()

```php
[
    'used_mb' => 5120,
    'used_gb' => 5.0,
    'limit_mb' => 10240,
    'limit_gb' => 10,
    'limit_display' => '10 GB' | 'Unlimited',
    'available' => true,
    'percentage' => 50.0,
    'remaining_mb' => 5120,
    'remaining_gb' => 5.0,
]
```

### validateBackupIntegrity()

```php
[
    'backup_id' => 'uuid',
    'valid' => true,
    'checks' => [
        'file_exists' => true,
        'size_match' => true,
        'checksum_match' => true,
        'not_expired' => true,
    ],
]
```

### getTenantUsage()

```php
[
    'tenant_id' => 'uuid',
    'tier' => 'professional',
    'sites' => [...], // checkSiteQuota() structure
    'storage' => [...], // checkStorageQuota() structure
    'backups' => [
        'total' => 15,
    ],
    'limits' => [...], // getQuotaLimitsByTier() structure
]
```

## Tier Limits Configuration

```php
[
    'free' => [
        'max_sites' => 1,
        'max_storage_gb' => 1,
        'max_backups_per_site' => 3,
        'max_bandwidth_gb' => 10,
    ],
    'starter' => [
        'max_sites' => 5,
        'max_storage_gb' => 10,
        'max_backups_per_site' => 5,
        'max_bandwidth_gb' => 100,
    ],
    'professional' => [
        'max_sites' => 20,
        'max_storage_gb' => 100,
        'max_backups_per_site' => 20,
        'max_bandwidth_gb' => 500,
    ],
    'enterprise' => [
        'max_sites' => -1, // Unlimited
        'max_storage_gb' => -1,
        'max_backups_per_site' => -1,
        'max_bandwidth_gb' => -1,
    ],
]
```

## Supported Values

### PHP Versions
- `7.4`, `8.0`, `8.1`, `8.2`, `8.3`

### Site Types
- `wordpress`, `laravel`, `static`

### Backup Types
- `full`, `files`, `database`

### Backup Frequencies
- `daily`, `weekly`, `monthly`

### User Roles (Hierarchy)
1. `owner` (highest)
2. `admin`
3. `member`
4. `viewer` (lowest)

### Permissions
- `manage_sites`
- `manage_backups`
- `manage_billing`
- `view_analytics`
- `manage_team`

### Site Statuses
- `creating`, `active`, `updating`, `disabled`, `deleting`

### Backup Statuses
- `pending`, `processing`, `completed`, `failed`

## Events Dispatched

| Service | Events |
|---------|--------|
| SiteManagementService | SiteProvisioned, SiteUpdated, SiteDisabled, SiteEnabled, SiteDeleted |
| BackupService | BackupCreated, BackupRestored, BackupDeleted, BackupFailed |
| TeamManagementService | MemberInvited, MemberJoined, MemberRemoved, MemberRoleUpdated, OwnershipTransferred |
| QuotaService | QuotaWarning, QuotaExceeded |

## Jobs Dispatched

| Service | Jobs |
|---------|------|
| SiteManagementService | ProvisionSiteJob, UpdatePHPVersionJob, IssueSslCertificateJob, DeleteSiteJob |
| BackupService | CreateBackupJob, RestoreBackupJob |

## Exception Types

All services throw:
- `Illuminate\Validation\ValidationException` - Invalid input data
- `RuntimeException` - Business logic errors (quota exceeded, not found, unauthorized, etc.)

## File Paths

```
app/Services/SiteManagementService.php
app/Services/BackupService.php
app/Services/TeamManagementService.php
app/Services/QuotaService.php
```
