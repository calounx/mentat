# Testing Guide

Comprehensive testing guidelines for CHOM.

## Quick Start

```bash
# Run all tests
composer test

# Run with coverage
php artisan test --coverage

# Run specific test
php artisan test --filter=SiteTest

# Parallel testing
php artisan test --parallel
```

## Test Structure

```
tests/
├── Feature/          # Integration tests
│   ├── Auth/
│   ├── Sites/
│   ├── VPS/
│   └── API/
├── Unit/            # Unit tests
│   ├── Services/
│   ├── Models/
│   └── ValueObjects/
└── TestCase.php     # Base test case
```

## Writing Tests

### Feature Tests

Test complete user flows:

```php
<?php

namespace Tests\Feature;

use App\Models\User;
use Tests\TestCase;

class SiteCreationTest extends TestCase
{
    public function test_owner_can_create_site(): void
    {
        $user = User::factory()->create(['role' => 'owner']);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/sites', [
                'domain' => 'example.test',
                'type' => 'wordpress',
            ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'data' => [
                    'id',
                    'domain',
                    'type',
                    'status',
                ],
            ]);

        $this->assertDatabaseHas('sites', [
            'domain' => 'example.test',
        ]);
    }

    public function test_viewer_cannot_create_site(): void
    {
        $user = User::factory()->create(['role' => 'viewer']);

        $response = $this->actingAs($user)
            ->postJson('/api/v1/sites', [
                'domain' => 'example.test',
                'type' => 'wordpress',
            ]);

        $response->assertForbidden();
    }
}
```

### Unit Tests

Test isolated logic:

```php
<?php

namespace Tests\Unit\Services;

use App\Services\DomainValidator;
use Tests\TestCase;

class DomainValidatorTest extends TestCase
{
    private DomainValidator $validator;

    protected function setUp(): void
    {
        parent::setUp();
        $this->validator = new DomainValidator();
    }

    public function test_valid_domain(): void
    {
        $this->assertTrue($this->validator->isValid('example.com'));
        $this->assertTrue($this->validator->isValid('sub.example.com'));
    }

    public function test_invalid_domain(): void
    {
        $this->assertFalse($this->validator->isValid('invalid'));
        $this->assertFalse($this->validator->isValid('example..com'));
    }
}
```

## Test Data

### Factories

```php
// Create single model
$user = User::factory()->create();

// Create with attributes
$user = User::factory()->create([
    'role' => 'admin',
    'email' => 'admin@test.com',
]);

// Create multiple
$users = User::factory(10)->create();

// Create without persisting
$user = User::factory()->make();
```

### Seeders

```bash
# Use test seeders
php artisan db:seed --class=TestUserSeeder
php artisan db:seed --class=TestDataSeeder
```

## Testing Patterns

### Authentication

```php
// Authenticate user
$this->actingAs($user);

// API authentication
$this->actingAs($user, 'api');

// Sanctum token
$token = $user->createToken('test')->plainTextToken;
$this->withToken($token);
```

### Database

```php
// Assert database has record
$this->assertDatabaseHas('sites', [
    'domain' => 'example.com',
]);

// Assert database missing
$this->assertDatabaseMissing('sites', [
    'domain' => 'deleted.com',
]);

// Assert soft deleted
$this->assertSoftDeleted('sites', [
    'id' => $site->id,
]);
```

### JSON Responses

```php
$response = $this->getJson('/api/v1/sites');

$response->assertOk()
    ->assertJsonStructure([
        'data' => [
            '*' => ['id', 'domain', 'type'],
        ],
        'meta' => ['total'],
    ])
    ->assertJsonPath('meta.total', 10);
```

### Validation

```php
$response = $this->postJson('/api/v1/sites', [
    'domain' => '', // Invalid
]);

$response->assertUnprocessable()
    ->assertJsonValidationErrors(['domain']);
```

### Jobs & Events

```php
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Event;

// Fake job dispatch
Bus::fake();
$this->postJson('/api/v1/sites', $data);
Bus::assertDispatched(ProcessSiteCreation::class);

// Fake events
Event::fake();
$site->delete();
Event::assertDispatched(SiteDeleted::class);
```

### Mocking

```php
use Illuminate\Support\Facades\Http;

// Mock HTTP responses
Http::fake([
    'api.example.com/*' => Http::response(['success' => true]),
]);

$response = $this->getJson('/api/v1/external');
$response->assertOk();
```

## Coverage Requirements

- **Minimum**: 80% overall coverage
- **Critical paths**: 100% coverage
- **Security features**: 100% coverage
- **Business logic**: 90%+ coverage

## Running Specific Tests

```bash
# By filter
php artisan test --filter=Site

# By file
php artisan test tests/Feature/SiteTest.php

# By group
php artisan test --group=api

# Stop on first failure
php artisan test --stop-on-failure
```

## Test Groups

Use groups to organize tests:

```php
/**
 * @group api
 * @group sites
 */
class SiteApiTest extends TestCase
{
    // ...
}
```

## Continuous Integration

Tests run automatically on:
- Every pull request
- Every push to main branch
- Nightly builds

## Performance Testing

### Database Performance

```bash
php artisan db:seed --class=PerformanceTestSeeder
php artisan test --group=performance
```

### Load Testing

Use Laravel Dusk for browser testing:

```bash
php artisan dusk
```

## Best Practices

1. **AAA Pattern**: Arrange, Act, Assert
2. **One assertion per test**: Focus tests
3. **Test names describe behavior**: `test_user_can_create_site`
4. **Use factories**: Don't manually create test data
5. **Clean database**: Use RefreshDatabase trait
6. **Mock external services**: Don't hit real APIs
7. **Test edge cases**: Not just happy paths
8. **Keep tests fast**: < 1 minute for full suite

## Debugging Tests

```bash
# Verbose output
php artisan test --verbose

# Show output
php artisan test --display-warnings

# Debug single test
php artisan test --filter=test_name --debug
```

## Test Database

Use in-memory SQLite for speed:

```env
DB_CONNECTION=sqlite
DB_DATABASE=:memory:
```

Or separate test database:

```env
DB_CONNECTION=mysql
DB_DATABASE=chom_test
```

## Continuous Testing

Watch for changes:

```bash
php artisan test --watch
```

---

Happy testing!
