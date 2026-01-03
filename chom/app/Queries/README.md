# Query Objects

This directory contains Query Objects that encapsulate complex database queries for the CHOM application. Query Objects provide a clean, reusable, and testable way to handle complex database operations.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Available Query Objects](#available-query-objects)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)
- [Testing](#testing)

## Overview

Query Objects follow the **Query Object Pattern** to:

- Encapsulate complex query logic
- Provide type-safe, fluent interfaces
- Enable easy testing and reusability
- Support both constructor and builder patterns
- Include caching capabilities
- Offer debugging utilities

## Architecture

All query objects extend `BaseQuery` which provides:

- Common query methods (`get()`, `paginate()`, `count()`, `exists()`)
- Helper methods for filtering (`applySearch()`, `applyDateRange()`, etc.)
- Caching support via `cache()` method
- Debugging methods (`toSql()`, `getBindings()`, `toRawSql()`)

```php
abstract class BaseQuery
{
    abstract protected function buildQuery(): Builder;

    public function get(): Collection
    public function paginate(int $perPage = 15): LengthAwarePaginator
    public function count(): int
    public function exists(): bool
    public function cache(string $key, int $ttl = 300): static
    public function toSql(): string
    public function getBindings(): array
}
```

## Available Query Objects

### 1. SiteSearchQuery

Search and filter sites with multiple criteria.

**Features:**
- Domain name searching
- Status filtering (creating, active, disabled, failed, deleting)
- Site type filtering (wordpress, html, laravel)
- PHP version filtering
- SSL status filtering
- Tenant isolation
- Storage analytics

**File:** `app/Queries/SiteSearchQuery.php`

### 2. BackupSearchQuery

Query backups with date ranges and size filtering.

**Features:**
- Tenant/site filtering
- Status filtering (pending, in_progress, completed, failed)
- Type filtering (full, files, database, config, manual, scheduled)
- Date range filtering
- Size range filtering
- Expiration tracking
- Storage analytics

**File:** `app/Queries/BackupSearchQuery.php`

### 3. TeamMemberQuery

Query team members and organization users.

**Features:**
- Organization-based filtering
- Role-based filtering (owner, admin, member)
- User search by name/email
- Active/inactive status
- Role aggregation
- Activity tracking

**File:** `app/Queries/TeamMemberQuery.php`

### 4. VpsServerQuery

Query VPS servers with load balancing support.

**Features:**
- Status filtering
- Resource availability filtering
- Site count filtering
- Regional filtering
- Provider filtering
- Health status tracking
- Load balancing queries

**File:** `app/Queries/VpsServerQuery.php`

### 5. UsageReportQuery

Generate comprehensive usage reports for billing and analytics.

**Features:**
- Site usage statistics
- Storage usage tracking
- Backup usage analytics
- Bandwidth tracking
- Cost estimation
- Daily/monthly breakdowns

**File:** `app/Queries/UsageReportQuery.php`

### 6. AuditLogQuery

Query audit logs for compliance and security.

**Features:**
- User activity tracking
- Entity-based filtering
- Action-based filtering
- Date range filtering
- IP address tracking
- Security event aggregation

**File:** `app/Queries/AuditLogQuery.php`

## Usage Examples

### SiteSearchQuery

```php
use App\Queries\SiteSearchQuery;

// Basic usage - constructor pattern
$sites = new SiteSearchQuery(
    tenantId: $tenantId,
    status: 'active',
    search: 'example.com'
);
$results = $sites->paginate(20);

// Fluent builder pattern
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active')
    ->withType('wordpress')
    ->sslEnabled()
    ->search('example')
    ->sortBy('created_at', 'desc')
    ->paginate(20);

// Get SSL expiring sites
$expiring = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->sslExpiringSoon(30); // Within 30 days

// Analytics
$totalStorage = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->totalStorageUsed();

$sitesByStatus = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->countByStatus();

// Debugging
$query = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active');

echo $query->toSql(); // Get SQL
print_r($query->getBindings()); // Get bindings
echo $query->toRawSql(); // Get SQL with bindings
```

### BackupSearchQuery

```php
use App\Queries\BackupSearchQuery;

// Find completed backups for a site
$backups = BackupSearchQuery::make()
    ->forSite($siteId)
    ->withStatus('completed')
    ->withType('full')
    ->createdBetween($startDate, $endDate)
    ->paginate(20);

// Find large backups
$largeBackups = BackupSearchQuery::make()
    ->forTenant($tenantId)
    ->minimumSize(1024 * 1024 * 1024) // 1GB
    ->get();

// Get expired backups
$expired = BackupSearchQuery::make()
    ->forSite($siteId)
    ->expired();

// Analytics
$totalSize = BackupSearchQuery::make()
    ->forTenant($tenantId)
    ->totalSize(); // In bytes

$oldest = BackupSearchQuery::make()
    ->forSite($siteId)
    ->oldest();

$latest = BackupSearchQuery::make()
    ->forSite($siteId)
    ->latest();

// Count by type
$byType = BackupSearchQuery::make()
    ->forTenant($tenantId)
    ->countByType();
```

### TeamMemberQuery

```php
use App\Queries\TeamMemberQuery;

// Get all active team members
$members = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->active()
    ->paginate(20);

// Search for specific members
$results = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->search('john')
    ->get();

// Get members by role
$admins = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->admins();

$owners = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->owners();

// Analytics
$roleStats = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->countByRole();

$recentMembers = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->recentlyJoined(30); // Last 30 days

$inactiveMembers = TeamMemberQuery::make()
    ->forOrganization($orgId)
    ->inactiveSince(90); // No login in 90 days
```

### VpsServerQuery

```php
use App\Queries\VpsServerQuery;

// Get available servers
$servers = VpsServerQuery::make()
    ->available()
    ->byRegion('us-east')
    ->get();

// Find server with minimum resources
$servers = VpsServerQuery::make()
    ->withMinimumCpu(4)
    ->withMinimumMemory(8192) // 8GB
    ->byProvider('hetzner')
    ->get();

// Load balancing - get least loaded server
$server = VpsServerQuery::make()
    ->byRegion('eu-central')
    ->leastLoaded();

// Get most loaded server
$server = VpsServerQuery::make()
    ->mostLoaded();

// Health check
$health = VpsServerQuery::make()
    ->byRegion('us-east')
    ->healthCheck();

// Analytics
$byProvider = VpsServerQuery::make()
    ->countByProvider();

$totalCapacity = VpsServerQuery::make()
    ->withStatus('active')
    ->totalMemoryCapacity(); // Total MB

// Filter by health
$unhealthy = VpsServerQuery::make()
    ->withHealthStatus('unhealthy')
    ->get();
```

### UsageReportQuery

```php
use App\Queries\UsageReportQuery;

// Comprehensive report
$report = UsageReportQuery::make(
    $tenantId,
    $startDate,
    $endDate
)->getComprehensiveReport();

// Individual metrics
$siteUsage = UsageReportQuery::make($tenantId, $start, $end)
    ->getSiteUsage();

$storageUsage = UsageReportQuery::make($tenantId, $start, $end)
    ->getStorageUsage();

$backupUsage = UsageReportQuery::make($tenantId, $start, $end)
    ->getBackupUsage();

$billing = UsageReportQuery::make($tenantId, $start, $end)
    ->getBillingData();

// Daily breakdown
$daily = UsageReportQuery::make($tenantId, $start, $end)
    ->getDailySiteActivity();

// Monthly summary
$monthly = UsageReportQuery::make($tenantId, $yearStart, $yearEnd)
    ->getMonthlySummary();
```

### AuditLogQuery

```php
use App\Queries\AuditLogQuery;

// Get user activity
$logs = AuditLogQuery::make()
    ->forUser($userId)
    ->between($startDate, $endDate)
    ->paginate(50);

// Track resource changes
$siteLogs = AuditLogQuery::make()
    ->forResource('site', $siteId)
    ->sortBy('created_at', 'desc')
    ->get();

// Security events
$security = AuditLogQuery::make()
    ->forOrganization($orgId)
    ->securityEvents();

// Failed logins
$failed = AuditLogQuery::make()
    ->forOrganization($orgId)
    ->failedLogins();

// Recent user activity
$recent = AuditLogQuery::make()
    ->recentUserActivity($userId, 24); // Last 24 hours

// Analytics
$byAction = AuditLogQuery::make()
    ->forOrganization($orgId)
    ->between($start, $end)
    ->countByAction();

$timeline = AuditLogQuery::make()
    ->forUser($userId)
    ->between($start, $end)
    ->dailyTimeline();

// IP tracking
$ips = AuditLogQuery::make()
    ->forUser($userId)
    ->between($start, $end)
    ->uniqueIpAddresses();
```

## Caching

All query objects support caching via the `cache()` method:

```php
// Cache results for 5 minutes (300 seconds)
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active')
    ->cache('tenant_' . $tenantId . '_active_sites', 300)
    ->get();

// Cache with custom TTL
$backups = BackupSearchQuery::make()
    ->forSite($siteId)
    ->cache('site_' . $siteId . '_backups', 600) // 10 minutes
    ->get();
```

## Debugging

All query objects provide debugging methods:

```php
$query = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active');

// Get SQL query string
$sql = $query->toSql();
// SELECT * FROM sites WHERE tenant_id = ? AND status = ? AND deleted_at IS NULL

// Get bindings
$bindings = $query->getBindings();
// ['tenant-uuid', 'active']

// Get raw SQL with bindings interpolated (for debugging only)
$rawSql = $query->toRawSql();
// SELECT * FROM sites WHERE tenant_id = 'tenant-uuid' AND status = 'active'...
```

## Best Practices

### 1. Use Fluent Builder Pattern

```php
// Good - fluent and readable
$sites = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active')
    ->sslEnabled()
    ->paginate(20);

// Also good - constructor pattern for simple queries
$sites = new SiteSearchQuery(
    tenantId: $tenantId,
    status: 'active'
);
```

### 2. Reuse Query Objects

```php
// Define base query
$baseQuery = SiteSearchQuery::make()
    ->forTenant($tenantId)
    ->withStatus('active');

// Reuse with different filters
$wordpressSites = $baseQuery->withType('wordpress')->get();
$laravelSites = $baseQuery->withType('laravel')->get();
```

### 3. Combine with Services

```php
class SiteService
{
    public function getActiveSites(string $tenantId): Collection
    {
        return SiteSearchQuery::make()
            ->forTenant($tenantId)
            ->withStatus('active')
            ->get();
    }

    public function searchSites(string $tenantId, string $search): Collection
    {
        return SiteSearchQuery::make()
            ->forTenant($tenantId)
            ->search($search)
            ->get();
    }
}
```

### 4. Use in Controllers

```php
class SiteController extends Controller
{
    public function index(Request $request)
    {
        $query = SiteSearchQuery::make()
            ->forTenant(auth()->user()->tenant_id);

        if ($request->has('search')) {
            $query = $query->search($request->input('search'));
        }

        if ($request->has('status')) {
            $query = $query->withStatus($request->input('status'));
        }

        return $query->paginate(20);
    }
}
```

### 5. Test Query Objects

```php
class SiteSearchQueryTest extends TestCase
{
    public function test_it_filters_by_tenant()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->count(5)->create(['tenant_id' => $tenant->id]);
        Site::factory()->count(3)->create(); // Other tenants

        $results = SiteSearchQuery::make()
            ->forTenant($tenant->id)
            ->get();

        $this->assertCount(5, $results);
    }
}
```

## Testing

All query objects should have comprehensive unit tests. See `tests/Unit/Queries/` for examples.

### Example Test Structure

```php
namespace Tests\Unit\Queries;

use Tests\TestCase;
use App\Queries\SiteSearchQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;

class SiteSearchQueryTest extends TestCase
{
    use RefreshDatabase;

    public function test_filters_by_status(): void
    {
        // Arrange
        Site::factory()->create(['status' => 'active']);
        Site::factory()->create(['status' => 'disabled']);

        // Act
        $results = SiteSearchQuery::make()
            ->withStatus('active')
            ->get();

        // Assert
        $this->assertCount(1, $results);
    }

    public function test_counts_sites_by_type(): void
    {
        // Arrange
        Site::factory()->count(3)->create(['site_type' => 'wordpress']);
        Site::factory()->count(2)->create(['site_type' => 'laravel']);

        // Act
        $counts = SiteSearchQuery::make()->countByType();

        // Assert
        $this->assertEquals(3, $counts['wordpress']);
        $this->assertEquals(2, $counts['laravel']);
    }
}
```

## Performance Considerations

1. **Use Pagination**: Always paginate large result sets
   ```php
   $sites->paginate(20); // Good
   $sites->get(); // Potentially bad for large datasets
   ```

2. **Eager Load Relationships**: Specify relationships to avoid N+1 queries
   ```php
   $sites = SiteSearchQuery::make()
       ->forTenant($tenantId)
       ->with(['vpsServer', 'tenant'])
       ->get();
   ```

3. **Use Caching**: Cache frequently accessed queries
   ```php
   $sites->cache('cache_key', 300)->get();
   ```

4. **Count Before Fetching**: Check count before loading large datasets
   ```php
   $query = SiteSearchQuery::make()->forTenant($tenantId);

   if ($query->count() > 1000) {
       // Use pagination or limit results
   }
   ```

## Contributing

When creating new query objects:

1. Extend `BaseQuery`
2. Implement `buildQuery()` method
3. Support both constructor and fluent builder patterns
4. Add comprehensive PHPDoc comments
5. Include type hints and return types
6. Write unit tests
7. Update this README with usage examples

## License

Part of the CHOM application - see main application LICENSE for details.
