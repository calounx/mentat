# Query Objects - Quick Start Guide

## Installation

Query objects are already installed in `app/Queries/`. No additional setup required.

## Basic Usage

### 1. Import the Query Object

```php
use App\Queries\SiteSearchQuery;
use App\Queries\BackupSearchQuery;
use App\Queries\AuditLogQuery;
use App\Queries\VpsServerQuery;
use App\Queries\UsageReportQuery;
use App\Queries\TeamMemberQuery;
```

### 2. Simple Query

```php
// Get all active sites for a tenant
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active')
    ->get();
```

### 3. Paginated Query

```php
// Get paginated results
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->paginate(20);
```

### 4. Count Query

```php
// Just get the count
$count = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active')
    ->count();
```

## Common Patterns

### Searching Sites

```php
// Search by domain
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->search('example')
    ->get();

// Filter by type and SSL
$wordpressSites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withType('wordpress')
    ->sslEnabled()
    ->get();

// Get sites with expiring SSL
$expiring = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->sslExpiringSoon(30); // Within 30 days
```

### Managing Backups

```php
// Get completed backups
$backups = BackupSearchQuery::make()
    ->forSite($siteId)
    ->withStatus('completed')
    ->get();

// Find large backups
$largeBackups = BackupSearchQuery::make()
    ->forTenant($tenantId)
    ->minimumSize(1024 * 1024 * 1024) // 1GB
    ->get();

// Get backups in date range
$backups = BackupSearchQuery::make()
    ->forSite($siteId)
    ->createdBetween($startDate, $endDate)
    ->get();

// Check total storage
$totalSize = BackupSearchQuery::make()
    ->forTenant($tenantId)
    ->totalSize();
```

### Finding VPS Servers

```php
// Get available servers
$servers = VpsServerQuery::make()
    ->available()
    ->byRegion('us-east')
    ->get();

// Find least loaded server for load balancing
$server = VpsServerQuery::make()
    ->byRegion('eu-central')
    ->withMinimumMemory(8192)
    ->leastLoaded();

// Check health status
$health = VpsServerQuery::make()
    ->byRegion('us-east')
    ->healthCheck();
```

### Audit Logs

```php
// Get user activity
$logs = AuditLogQuery::make()
    ->forUser($userId)
    ->between($startDate, $endDate)
    ->paginate(50);

// Track resource changes
$siteLogs = AuditLogQuery::make()
    ->forResource('site', $siteId)
    ->get();

// Security events
$security = AuditLogQuery::make()
    ->forOrganization($orgId)
    ->securityEvents();
```

### Usage Reports

```php
// Get comprehensive report
$report = UsageReportQuery::make(
    $tenantId,
    $startDate,
    $endDate
)->getComprehensiveReport();

// Get specific metrics
$siteUsage = UsageReportQuery::make($tenantId, $start, $end)
    ->getSiteUsage();

$storageUsage = UsageReportQuery::make($tenantId, $start, $end)
    ->getStorageUsage();
```

### Team Members

```php
// Get active team members
$members = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->active()
    ->get();

// Get admins
$admins = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->admins();

// Search members
$results = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->search('john')
    ->get();
```

## Advanced Features

### Caching

```php
// Cache results for 5 minutes
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->cache('tenant_' . $tenantId . '_sites', 300)
    ->get();
```

### Debugging

```php
$query = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active');

// Get SQL
echo $query->toSql();

// Get bindings
print_r($query->getBindings());

// Get SQL with bindings (for debugging only)
echo $query->toRawSql();
```

### Multiple Filters

```php
// Chain multiple filters
$results = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active')
    ->withType('wordpress')
    ->withPhpVersion('8.2')
    ->sslEnabled()
    ->search('example')
    ->sortBy('created_at', 'desc')
    ->paginate(20);
```

## Controller Integration

```php
class SiteController extends Controller
{
    public function index(Request $request)
    {
        $query = SiteSearchQuery::make()
            ->forTenant(auth()->user()->tenant_id);

        // Apply filters from request
        if ($request->filled('search')) {
            $query = $query->search($request->input('search'));
        }

        if ($request->filled('status')) {
            $query = $query->withStatus($request->input('status'));
        }

        if ($request->filled('type')) {
            $query = $query->withType($request->input('type'));
        }

        return $query->paginate(20);
    }
}
```

## Service Integration

```php
class BackupService
{
    public function cleanupExpiredBackups(string $siteId): int
    {
        $expired = BackupSearchQuery::make()
            ->forSite($siteId)
            ->expired()
            ->get();

        $count = 0;
        foreach ($expired as $backup) {
            // Delete backup logic
            $count++;
        }

        return $count;
    }

    public function getBackupStats(string $tenantId): array
    {
        return [
            'total_count' => BackupSearchQuery::make()
                ->forTenant($tenantId)
                ->count(),
            'total_size' => BackupSearchQuery::make()
                ->forTenant($tenantId)
                ->totalSize(),
            'by_type' => BackupSearchQuery::make()
                ->forTenant($tenantId)
                ->countByType(),
        ];
    }
}
```

## Testing

```php
use Tests\TestCase;
use App\Queries\SiteSearchQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;

class SiteServiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_gets_active_sites()
    {
        // Arrange
        $tenant = Tenant::factory()->create();
        Site::factory()->count(5)->create([
            'tenant_id' => $tenant->id,
            'status' => 'active'
        ]);

        // Act
        $sites = SiteSearchQuery::make()
            ->forTenant($tenant->id)
            ->withStatus('active')
            ->get();

        // Assert
        $this->assertCount(5, $sites);
    }
}
```

## Performance Tips

1. **Always use pagination for large datasets**
   ```php
   $sites->paginate(20); // Good
   $sites->get(); // Bad for large datasets
   ```

2. **Use count() when you only need the count**
   ```php
   $count = $sites->count(); // Good
   $count = $sites->get()->count(); // Bad - loads all data
   ```

3. **Cache frequently accessed queries**
   ```php
   $sites->cache('cache_key', 300)->get();
   ```

4. **Check existence before fetching**
   ```php
   if ($sites->exists()) {
       $results = $sites->get();
   }
   ```

## Common Mistakes to Avoid

1. **Don't call get() multiple times**
   ```php
   // Bad
   $count = $query->get()->count();
   $items = $query->get();

   // Good
   $items = $query->get();
   $count = $items->count();
   ```

2. **Don't forget tenant isolation**
   ```php
   // Bad - no tenant filtering
   $sites = SiteSearchQuery::make()->get();

   // Good
   $sites = SiteSearchQuery::make()
       ->forTenant($tenantId)
       ->get();
   ```

3. **Use appropriate methods**
   ```php
   // Bad
   $total = $query->get()->sum('storage_used_mb');

   // Good
   $total = SiteSearchQuery::make()
       ->forTenant($tenantId)
       ->totalStorageUsed();
   ```

## More Examples

See `app/Queries/README.md` for comprehensive documentation and examples.

## Support

For questions or issues:
1. Check the README.md documentation
2. Review the test files in `tests/Unit/Queries/`
3. Examine the source code - all methods are well documented
