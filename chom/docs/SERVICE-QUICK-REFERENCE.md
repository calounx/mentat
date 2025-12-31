# Service Layer Quick Reference Guide

## Quick Links

- Full Implementation Details: `SERVICE-LAYER-IMPLEMENTATION.md`
- Integration Summary: `SERVICE-LAYER-README.md`
- This Guide: Quick examples and API reference

## Controller Pattern

### Standard Controller Structure

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\V1\Sites\CreateSiteRequest;
use App\Services\Sites\SiteCreationService;
use App\Services\Sites\SiteManagementService;
use Illuminate\Http\JsonResponse;

class SiteController extends Controller
{
    public function __construct(
        protected SiteCreationService $siteCreation,
        protected SiteManagementService $siteManagement
    ) {}

    public function store(CreateSiteRequest $request): JsonResponse
    {
        try {
            $site = $this->siteCreation->createSite(
                $request->tenant(),
                $request->validated()
            );

            return response()->json([
                'success' => true,
                'data' => $site,
            ], 201);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'error' => ['message' => $e->getMessage()],
            ], 500);
        }
    }
}
```

## Service Usage Examples

### SiteQuotaService

```php
use App\Services\Sites\SiteQuotaService;

$quotaService = app(SiteQuotaService::class);

// Check if can create
$canCreate = $quotaService->canCreateSite($tenant);

// Throw exception if can't create
$quotaService->ensureCanCreateSite($tenant);

// Get quota info
$info = $quotaService->getQuotaInfo($tenant);
// Returns: ['current' => 3, 'limit' => 5, 'remaining' => 2, 'can_create' => true]
```

### SiteCreationService

```php
use App\Services\Sites\SiteCreationService;

$siteCreation = app(SiteCreationService::class);

// Create site
$site = $siteCreation->createSite($tenant, [
    'domain' => 'example.com',
    'site_type' => 'wordpress',
    'php_version' => '8.2',
    'ssl_enabled' => true,
]);

// Validate data before creation
$validation = $siteCreation->validateSiteData($tenant, $data);
if (!$validation['valid']) {
    // Handle errors: $validation['errors']
}

// Check creation status
$status = $siteCreation->getCreationStatus($tenant);
// Returns: ['can_create' => true, 'quota_info' => [...], 'vps_available' => true, 'blockers' => []]
```

### SiteManagementService

```php
use App\Services\Sites\SiteManagementService;

$siteManagement = app(SiteManagementService::class);

// Enable site
$result = $siteManagement->enableSite($site);
// Returns: ['success' => true, 'message' => 'Site enabled successfully']

// Disable site
$result = $siteManagement->disableSite($site);

// Update site
$updatedSite = $siteManagement->updateSite($site, [
    'php_version' => '8.4',
    'settings' => ['cache_enabled' => true],
]);

// Delete site
$result = $siteManagement->deleteSite($site, force: false);

// Issue SSL
$result = $siteManagement->issueSSL($site);

// Get health
$health = $siteManagement->getSiteHealth($site);
// Returns: ['healthy' => true, 'issues' => []]
```

### BackupService

```php
use App\Services\Backup\BackupService;

$backupService = app(BackupService::class);

// Create backup
$backup = $backupService->createBackup(
    site: $site,
    backupType: 'full',
    retentionDays: 30
);

// Execute backup (typically in job)
$result = $backupService->executeBackup($backup);

// Delete backup
$result = $backupService->deleteBackup($backup);

// Get download URL
$download = $backupService->getDownloadUrl($backup, expiryMinutes: 15);
// Returns: ['success' => true, 'url' => '...', 'expires_at' => '...']

// Cleanup expired
$count = $backupService->cleanupExpiredBackups($site);

// Get stats
$stats = $backupService->getBackupStats($tenant);
```

### BackupRestoreService

```php
use App\Services\Backup\BackupRestoreService;

$restoreService = app(BackupRestoreService::class);

// Validate restore
$validation = $restoreService->validateRestore($backup);
if (!$validation['valid']) {
    // Handle errors: $validation['errors']
}

// Restore from backup
$result = $restoreService->restoreFromBackup($backup);

// Create safety backup before restore
$preRestoreBackup = $restoreService->createPreRestoreBackup($site, $backupService);

// Estimate time
$estimate = $restoreService->estimateRestoreTime($backup);
// Returns: ['estimated_minutes' => 5, 'size_formatted' => '1.2 GB']
```

### TeamMemberService

```php
use App\Services\Team\TeamMemberService;

$teamService = app(TeamMemberService::class);

// Update role
$result = $teamService->updateMemberRole(
    organization: $organization,
    member: $user,
    newRole: 'admin',
    updater: $currentUser
);

// Remove member
$result = $teamService->removeMember(
    organization: $organization,
    member: $user,
    remover: $currentUser
);

// Get members
$members = $teamService->getMembers($organization);

// Get stats
$stats = $teamService->getMemberStats($organization);
// Returns: ['total' => 5, 'by_role' => ['owner' => 1, 'admin' => 2, 'member' => 2]]
```

### OwnershipTransferService

```php
use App\Services\Team\OwnershipTransferService;

$ownershipService = app(OwnershipTransferService::class);

// Validate transfer first
$validation = $ownershipService->validateTransfer(
    organization: $organization,
    currentOwner: $currentUser,
    newOwner: $newOwnerUser
);

if ($validation['valid']) {
    // Transfer ownership (requires password)
    $result = $ownershipService->transferOwnership(
        organization: $organization,
        currentOwner: $currentUser,
        newOwner: $newOwnerUser,
        password: $request->input('password')
    );
}

// Get eligible members
$eligibleMembers = $ownershipService->getEligibleMembers($organization, $currentUser);
```

### VpsAllocationService

```php
use App\Services\VPS\VpsAllocationService;

$vpsAllocation = app(VpsAllocationService::class);

// Find available VPS
$vps = $vpsAllocation->findAvailableVps($tenant);

// Check if VPS is available
$isAvailable = $vpsAllocation->isVpsAvailable($vps);

// Get allocation info
$info = $vpsAllocation->getAllocationInfo($tenant);

// Check capacity
$hasCapacity = $vpsAllocation->hasCapacity($vps, additionalSites: 5);
```

### VpsHealthService

```php
use App\Services\VPS\VpsHealthService;

$healthService = app(VpsHealthService::class);

// Check health
$health = $healthService->checkHealth($vps);
// Returns: ['healthy' => true, 'load' => 1.2, 'memory_used' => 2048, 'disk_used' => 10240, 'issues' => []]

// Check all VPS
$stats = $healthService->checkAllVpsHealth();
// Returns: ['total' => 10, 'healthy' => 8, 'unhealthy' => 1, 'unknown' => 1]

// Get unhealthy servers
$unhealthyServers = $healthService->getUnhealthyServers();

// Get summary
$summary = $healthService->getHealthSummary();
```

### TenantService

```php
use App\Services\Tenant\TenantService;

$tenantService = app(TenantService::class);

// Create tenant
$tenant = $tenantService->createTenant([
    'organization_id' => $org->id,
    'name' => 'My Tenant',
    'tier' => 'pro',
]);

// Update tenant
$updatedTenant = $tenantService->updateTenant($tenant, [
    'name' => 'Updated Name',
]);

// Activate/Suspend
$result = $tenantService->activateTenant($tenant);
$result = $tenantService->suspendTenant($tenant, reason: 'Payment failed');

// Get metrics
$metrics = $tenantService->getTenantMetrics($tenant);

// Get resource summary
$summary = $tenantService->getResourceSummary($tenant);

// Check if can delete
$canDelete = $tenantService->canDelete($tenant);
```

## Form Request Usage

### In Routes

```php
use App\Http\Requests\V1\Sites\CreateSiteRequest;

Route::post('/sites', function (CreateSiteRequest $request) {
    // Request is already validated and authorized
    $tenant = $request->tenant();
    $validated = $request->validated();

    // Use services...
});
```

### Form Request Methods

```php
// CreateSiteRequest
$request->tenant();      // Get tenant
$request->validated();   // Get validated data

// CreateBackupRequest
$request->tenant();      // Get tenant
$request->site();        // Get site
$request->validated();   // Get validated data
```

## Middleware Usage

### Register Middleware

In `app/Http/Kernel.php`:

```php
protected $middlewareAliases = [
    'tenant' => \App\Http\Middleware\EnsureTenantContext::class,
];
```

### Apply to Routes

```php
// Single route
Route::get('/sites', [SiteController::class, 'index'])
    ->middleware(['auth:sanctum', 'tenant']);

// Route group
Route::middleware(['auth:sanctum', 'tenant'])->group(function () {
    Route::apiResource('sites', SiteController::class);
    Route::apiResource('backups', BackupController::class);
});
```

### Access Tenant in Controller

```php
// Method 1: Via request attributes
$tenant = $request->attributes->get('tenant');

// Method 2: Via base controller helper
$tenant = $this->getTenant($request);

// Method 3: Via form request (if using form request)
$tenant = $request->tenant();
```

## Exception Handling

### QuotaExceededException

```php
use App\Exceptions\QuotaExceededException;

try {
    $site = $siteCreation->createSite($tenant, $data);
} catch (QuotaExceededException $e) {
    // Auto-renders as proper JSON response
    return $e->render();
}

// Or catch context
try {
    $quotaService->ensureCanCreateSite($tenant);
} catch (QuotaExceededException $e) {
    $context = $e->getContext();
    // ['current_sites' => 5, 'limit' => 5]
}
```

## Dependency Injection

### In Controllers

```php
public function __construct(
    protected SiteCreationService $siteCreation,
    protected SiteManagementService $siteManagement
) {}
```

### In Jobs

```php
class ProvisionSiteJob implements ShouldQueue
{
    public function handle(
        VpsManagerInterface $vpsManager,
        SiteManagementService $siteManagement
    ) {
        // Services auto-injected
    }
}
```

### In Console Commands

```php
class CleanupExpiredBackups extends Command
{
    public function handle(BackupService $backupService)
    {
        foreach (Tenant::all() as $tenant) {
            $count = $backupService->cleanupExpiredBackups($tenant);
            $this->info("Cleaned up {$count} backups for {$tenant->name}");
        }
    }
}
```

## Common Patterns

### Service Result Pattern

```php
// Services return arrays with success/message
$result = $siteManagement->enableSite($site);

if ($result['success']) {
    return response()->json([
        'data' => $site,
        'message' => $result['message']
    ]);
} else {
    return response()->json([
        'error' => ['message' => $result['message']]
    ], 500);
}
```

### Validation Pattern

```php
// Validate before executing
$validation = $siteCreation->validateSiteData($tenant, $data);

if (!$validation['valid']) {
    return response()->json([
        'errors' => $validation['errors']
    ], 422);
}

// Proceed with creation
$site = $siteCreation->createSite($tenant, $data);
```

### Status Check Pattern

```php
// Check status before allowing action
$status = $siteCreation->getCreationStatus($tenant);

if (!$status['can_create']) {
    return response()->json([
        'message' => 'Cannot create site',
        'blockers' => $status['blockers']
    ], 403);
}
```

## Testing Services

### Unit Test Example

```php
use Tests\TestCase;
use App\Services\Sites\SiteQuotaService;

class SiteQuotaServiceTest extends TestCase
{
    public function test_enforces_quota_limit()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->count(5)->for($tenant)->create();

        $service = app(SiteQuotaService::class);

        $this->assertFalse($service->canCreateSite($tenant));
    }
}
```

### Integration Test Example

```php
public function test_site_creation_workflow()
{
    $tenant = Tenant::factory()->create();
    $vps = VpsServer::factory()->active()->create();

    $service = app(SiteCreationService::class);

    $site = $service->createSite($tenant, [
        'domain' => 'example.com',
        'site_type' => 'wordpress',
    ]);

    $this->assertEquals('creating', $site->status);
    $this->assertEquals($tenant->id, $site->tenant_id);
}
```

## Performance Tips

1. **Use Eager Loading**: Services already use eager loading where appropriate
2. **Cache Quota Checks**: Consider caching quota info for high-traffic endpoints
3. **Async Operations**: Use jobs for long-running operations (already implemented)
4. **Connection Pooling**: VPS operations use connection pooling (already implemented)

## Troubleshooting

### Service Not Found
**Error**: `Class 'App\Services\Sites\SiteCreationService' not found`

**Solution**: Run `composer dump-autoload`

### Interface Binding Issue
**Error**: `Target [App\Contracts\VpsManagerInterface] is not instantiable`

**Solution**: Ensure VPSManagerBridge implements the interface and is registered in AppServiceProvider

### Middleware Not Working
**Error**: Tenant context not available

**Solution**:
1. Register middleware in Kernel.php
2. Apply to routes
3. Ensure auth middleware is applied first

## Summary

- **Controllers**: Thin, focused on HTTP concerns
- **Services**: Business logic, orchestration, domain operations
- **Form Requests**: Validation and authorization
- **Interfaces**: Contracts for external dependencies
- **Middleware**: Cross-cutting concerns

For detailed implementation see `SERVICE-LAYER-IMPLEMENTATION.md`
