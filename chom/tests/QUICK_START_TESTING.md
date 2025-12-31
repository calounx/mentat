# Quick Start: Running Security Tests

## Prerequisites

Ensure your testing environment is set up:

```bash
# Install dependencies
composer install

# Copy environment file
cp .env.example .env.testing

# Configure test database (SQLite in memory)
# This should already be set in phpunit.xml:
# DB_CONNECTION=sqlite
# DB_DATABASE=:memory:
```

## Running All Tests

### Run the entire test suite
```bash
php artisan test
```

### Run with output verbosity
```bash
php artisan test --verbose
```

## Running Security Tests by Category

### 1. PromQL/LogQL Injection Prevention Tests
```bash
php artisan test --filter=ObservabilityAdapterTest
```

**Expected Output:**
```
PASS  Tests\Unit\ObservabilityAdapterTest
✓ tenant id is escaped in promql queries
✓ malicious tenant id with quotes is escaped
✓ tenant id with regex characters is escaped
✓ tenant id with backslashes is double escaped
✓ tenant id with newlines is escaped
✓ vps ip is escaped in queries
✓ malicious vps ip is escaped
✓ query bandwidth escapes tenant id
✓ query disk usage escapes tenant id
✓ logql string escaping in site logs
✓ search logs escapes search terms
✓ loki queries use tenant header
✓ active alerts filtered by tenant
✓ complex promql injection is prevented
✓ embedded dashboard url tenant parameter
✓ scrape config generation includes tenant labels
✓ health checks return false on error
✓ health status aggregate

Tests:  18 passed
```

### 2. Tenant Scope Tests
```bash
php artisan test --filter=TenantScopeTest
```

**Expected Output:**
```
PASS  Tests\Unit\TenantScopeTest
✓ site model filters by authenticated tenant
✓ site model scope works with where clauses
✓ site model scope works with find
✓ site model scope works with first
✓ operation model filters by authenticated tenant
✓ operation model scope works with custom scopes
✓ usage record model filters by authenticated tenant
✓ usage record model scope works with custom scopes
✓ vps allocation model filters by authenticated tenant
✓ count queries respect tenant scope
✓ aggregate queries respect tenant scope
✓ exists queries respect tenant scope
✓ relationships respect tenant scope
✓ pagination respects tenant scope
✓ scope does not apply when user not authenticated
✓ scope does not apply when user has no tenant
✓ update queries respect tenant scope
✓ delete queries respect tenant scope
✓ without global scope allows bypassing tenant filter
✓ complex queries cannot leak tenant data
✓ tenant scope persists across query chains

Tests:  21 passed
```

### 3. Authorization Policy Tests
```bash
php artisan test --filter=SiteControllerAuthorizationTest
```

**Expected Output:**
```
PASS  Tests\Feature\SiteControllerAuthorizationTest
✓ users cannot view sites from other tenants
✓ users cannot access site details from other tenants
✓ users cannot update sites from other tenants
✓ users cannot delete sites from other tenants
✓ viewers cannot create sites
✓ members can create sites
✓ admins can create sites
✓ owners can create sites
✓ viewers cannot update sites
✓ members can update sites
✓ viewers cannot delete sites
✓ members cannot delete sites
✓ admins can delete sites
✓ owners can delete sites
✓ users cannot enable sites from other tenants
✓ users cannot disable sites from other tenants
✓ users cannot issue ssl for sites from other tenants
✓ members can enable sites
✓ members can disable sites
✓ viewers cannot enable sites
✓ viewers cannot disable sites
✓ viewers cannot issue ssl
✓ unauthenticated users cannot access sites
✓ authorization prevents direct access via id
✓ policy belongs to tenant check
✓ search filtering respects tenant boundaries
✓ status filtering respects tenant boundaries

Tests:  27 passed
```

### 4. Integration Tests
```bash
php artisan test --filter=TenantIsolationIntegrationTest
```

**Expected Output:**
```
PASS  Tests\Feature\TenantIsolationIntegrationTest
✓ complete isolation across all models
✓ site model isolation with complex queries
✓ operation model isolation with complex queries
✓ usage record model isolation with complex queries
✓ vps allocation model isolation with complex queries
✓ api site list endpoint enforces isolation
✓ api site show endpoint enforces isolation
✓ site creation is scoped to authenticated tenant
✓ different roles see same tenant scoped data
✓ isolation during relationship loading
✓ aggregate queries respect isolation
✓ batch operations respect isolation
✓ search and filtering maintain isolation
✓ isolation with soft deletes
✓ concurrent tenant requests maintain isolation
✓ model events respect tenant isolation

Tests:  16 passed
```

## Running Specific Test Methods

```bash
# Run a specific test method
php artisan test --filter=test_malicious_tenant_id_with_quotes_is_escaped

# Run multiple specific tests
php artisan test --filter="test_malicious|test_complex"
```

## Test Coverage

### Generate HTML coverage report
```bash
XDEBUG_MODE=coverage php artisan test --coverage-html coverage
```

Then open `coverage/index.html` in your browser.

### Check coverage percentage
```bash
XDEBUG_MODE=coverage php artisan test --coverage
```

### Enforce minimum coverage
```bash
XDEBUG_MODE=coverage php artisan test --coverage --min=80
```

## Parallel Testing

For faster test execution:

```bash
php artisan test --parallel
```

## Continuous Integration

### GitHub Actions Example
```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
      - run: composer install
      - run: php artisan test --parallel
```

## Debugging Failed Tests

### Run with detailed output
```bash
php artisan test --filter=FailingTestName --verbose
```

### Stop on first failure
```bash
php artisan test --stop-on-failure
```

### Run only failed tests
```bash
php artisan test --only-failed
```

## Test Database

Tests use SQLite in-memory database by default (configured in `phpunit.xml`):

```xml
<env name="DB_CONNECTION" value="sqlite"/>
<env name="DB_DATABASE" value=":memory:"/>
```

This means:
- Fast test execution
- No database cleanup needed
- Fresh database for each test run

## Common Issues

### Issue: "Class not found" errors
**Solution:** Regenerate autoload files
```bash
composer dump-autoload
```

### Issue: "Table not found" errors
**Solution:** Run migrations in tests
```php
use Illuminate\Foundation\Testing\RefreshDatabase;

class MyTest extends TestCase
{
    use RefreshDatabase; // This runs migrations automatically
}
```

### Issue: Tests pass individually but fail when run together
**Solution:** Ensure each test is isolated
```php
protected function setUp(): void
{
    parent::setUp();
    // Reset any shared state
}

protected function tearDown(): void
{
    // Clean up after test
    parent::tearDown();
}
```

## Best Practices

1. **Always use RefreshDatabase trait** in tests that interact with the database
2. **Use factories** instead of creating models manually
3. **Use the WithTenantIsolation trait** for tenant-related tests
4. **Test both positive and negative cases** (what should work AND what shouldn't)
5. **Keep tests isolated** - each test should be independent
6. **Use descriptive test names** that explain what's being tested
7. **Group related assertions** in the same test when appropriate

## Test Structure Example

```php
<?php

namespace Tests\Feature;

use App\Models\Site;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithTenantIsolation;
use Tests\TestCase;

class MyFeatureTest extends TestCase
{
    use RefreshDatabase, WithTenantIsolation;

    public function test_feature_description(): void
    {
        // Arrange - Set up test data
        $tenantData = $this->createTenantWithUser();
        $site = Site::factory()->create([
            'tenant_id' => $tenantData['tenant']->id,
        ]);

        // Act - Perform the action
        $this->actingAs($tenantData['user']);
        $response = $this->getJson("/api/v1/sites/{$site->id}");

        // Assert - Verify the results
        $response->assertOk();
        $this->assertEquals($site->id, $response->json('data.id'));
    }
}
```

## Next Steps

After running the security tests:

1. Review any failures and fix the underlying issues
2. Add new tests for any security-sensitive features
3. Run tests before every commit
4. Set up CI/CD to run tests automatically
5. Monitor test coverage and aim for 80%+ on security-critical code

## Support

For more information:
- See `/tests/SECURITY_TESTING.md` for detailed test documentation
- Review individual test files for examples
- Check Laravel testing documentation: https://laravel.com/docs/testing
