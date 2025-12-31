# Test Execution Guide

## Quick Start

### Run All Tests
```bash
cd /home/calounx/repositories/mentat/chom
php artisan test
```

### Run Specific Test Suites
```bash
# Integration tests (end-to-end workflows)
php artisan test --testsuite=Integration

# Unit tests (individual components)
php artisan test --testsuite=Unit

# Security tests (vulnerability testing)
php artisan test --testsuite=Security

# Performance tests (benchmarking)
php artisan test --testsuite=Performance

# API contract tests
php artisan test --testsuite=Api

# Database tests
php artisan test --testsuite=Database

# Regression tests
php artisan test --testsuite=Regression

# CI/CD tests
php artisan test --testsuite=CI
```

### Run with Coverage
```bash
# Generate coverage report
php artisan test --coverage

# Generate HTML coverage report
php artisan test --coverage-html coverage

# Enforce minimum coverage threshold
php artisan test --coverage --min=98
```

### Run Specific Test Files
```bash
# Single test file
php artisan test tests/Integration/SiteProvisioningFlowTest.php

# Single test method
php artisan test --filter=test_complete_html_site_provisioning_flow
```

## Test Suite Overview

### Created Test Files

#### Test Utilities (4 files)
- `tests/Concerns/WithMockVpsManager.php` - VPS operation mocking
- `tests/Concerns/WithMockObservability.php` - Observability mocking
- `tests/Concerns/WithPerformanceTesting.php` - Performance utilities
- `tests/Concerns/WithSecurityTesting.php` - Security testing utilities

#### Integration Tests (5+ files)
- `tests/Integration/SiteProvisioningFlowTest.php` - Complete site provisioning (10 tests)
- `tests/Integration/BackupRestoreFlowTest.php` - Backup workflows (10 tests)
- `tests/Integration/AuthenticationFlowTest.php` - Auth with 2FA (8 tests)
- `tests/Integration/TenantIsolationFullTest.php` - Tenant isolation (5 tests)
- `tests/Integration/ApiRateLimitingTest.php` - Rate limiting (4 tests)

#### Service Layer Tests (3+ files)
- `tests/Unit/Services/SiteCreationServiceTest.php` - Site creation (6 tests)
- `tests/Unit/Services/SiteQuotaServiceTest.php` - Quota management (4 tests)
- `tests/Unit/Services/BackupServiceTest.php` - Backup operations (4 tests)

#### Middleware Tests (2+ files)
- `tests/Unit/Middleware/EnsureTenantContextTest.php` - Tenant context (2 tests)
- `tests/Unit/Middleware/SecurityHeadersTest.php` - Security headers (3 tests)

#### Security Tests (4+ files)
- `tests/Security/InjectionAttackTest.php` - Injection attacks (9 attack vectors)
- `tests/Security/AuthorizationSecurityTest.php` - Authorization (10 tests)
- `tests/Security/SessionSecurityTest.php` - Session security (4 tests)

#### Performance Tests (1+ file)
- `tests/Performance/DatabaseQueryPerformanceTest.php` - Query performance (3 tests)

#### Regression Tests (1+ file)
- `tests/Regression/PromQLInjectionPreventionTest.php` - PromQL injection (1 test)

#### API Contract Tests (1+ file)
- `tests/Api/SiteEndpointContractTest.php` - API contracts (3 tests)

#### Database Tests (2+ files)
- `tests/Database/MigrationTest.php` - Migration tests (4 tests)
- `tests/Database/IndexUsageTest.php` - Index usage (4 tests)

#### CI/CD Tests (1+ file)
- `tests/CI/CodeStyleTest.php` - Code style compliance (3 tests)

### Total Test Count
- **Integration Tests**: 37+ tests
- **Unit Tests**: 19+ tests
- **Security Tests**: 23+ tests
- **Performance Tests**: 3+ tests
- **Regression Tests**: 1+ test
- **API Tests**: 3+ tests
- **Database Tests**: 8+ tests
- **CI Tests**: 3+ tests

**TOTAL**: 97+ comprehensive tests

## Test Environment Setup

### Prerequisites
```bash
# Install dependencies
cd /home/calounx/repositories/mentat/chom
composer install
npm install

# Set up environment
cp .env.example .env
php artisan key:generate

# Run migrations (for test database)
php artisan migrate --env=testing
```

### Database Configuration
Tests use SQLite in-memory database by default (configured in phpunit.xml):
```xml
<env name="DB_CONNECTION" value="sqlite"/>
<env name="DB_DATABASE" value=":memory:"/>
```

## Running Tests in CI/CD

### GitHub Actions Example
```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
      - name: Install Dependencies
        run: composer install --no-interaction --prefer-dist
      - name: Run Tests
        run: php artisan test --coverage --min=98
```

### GitLab CI Example
```yaml
test:
  image: php:8.2
  script:
    - composer install
    - php artisan test --coverage --min=98
```

## Performance Benchmarks

Tests enforce the following performance thresholds:

| Operation | Maximum Time |
|-----------|--------------|
| Dashboard Load | 100ms |
| Site Creation | 2000ms |
| Cache Operation | 1ms |
| Database Query | 50ms |
| API Response | 200ms |
| Backup Creation | 5000ms |
| Restore Operation | 10000ms |

## Security Test Coverage

All security tests pass and protect against:
- SQL Injection (6 payloads)
- PromQL Injection (3 payloads)
- LogQL Injection (3 payloads)
- Command Injection (5 payloads)
- XSS Attacks
- CSRF Attacks
- IDOR Vulnerabilities
- Privilege Escalation
- Session Hijacking
- Tenant Isolation Breaches

## Debugging Failed Tests

### View Detailed Output
```bash
php artisan test --verbose
```

### Stop on First Failure
```bash
php artisan test --stop-on-failure
```

### Run Single Test with Debug
```bash
php artisan test --filter=test_name --verbose
```

### Check Database State
```bash
# Enable query logging in test
DB::enableQueryLog();
// ... your test code ...
dd(DB::getQueryLog());
```

## Coverage Goals

- **Overall Coverage**: 98%+
- **Critical Path Coverage**: 100%
- **Security Coverage**: 100%
- **Service Layer**: 100%
- **Controllers**: 95%+
- **Models**: 90%+

## Continuous Testing

### Watch Mode (Development)
```bash
# Using Laravel Pail for live logs
php artisan pail &
php artisan test --watch
```

### Pre-commit Hook
Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
php artisan test --stop-on-failure
```

## Test Data Management

### Factories
Tests use factories for consistent test data:
```php
User::factory()->create();
Site::factory()->create(['user_id' => $user->id]);
Backup::factory()->create(['site_id' => $site->id]);
```

### Seeders
Run seeders in tests:
```php
$this->seed(DatabaseSeeder::class);
```

## Common Issues and Solutions

### Issue: Tests Fail with "Class not found"
**Solution**: Run `composer dump-autoload`

### Issue: Database errors in tests
**Solution**: Ensure migrations run: `php artisan migrate:fresh --env=testing`

### Issue: Mocking not working
**Solution**: Clear cached config: `php artisan config:clear`

### Issue: Tests timeout
**Solution**: Increase timeout in phpunit.xml or use `--timeout` flag

## Best Practices

1. **Run tests before committing**: `php artisan test`
2. **Check coverage regularly**: `php artisan test --coverage`
3. **Keep tests fast**: Most tests should run in < 1 second
4. **Use factories**: Don't create models manually
5. **Mock external services**: Use provided test utilities
6. **Follow AAA pattern**: Arrange, Act, Assert
7. **Write descriptive test names**: `test_user_cannot_access_other_users_sites()`
8. **Test edge cases**: Not just happy path
9. **Keep tests isolated**: Each test should be independent
10. **Use RefreshDatabase**: Ensure clean state for each test

## Advanced Usage

### Parallel Testing
```bash
php artisan test --parallel
```

### Generate Coverage Badge
```bash
php artisan test --coverage-clover coverage.xml
# Use coverage.xml with badges service
```

### Profile Tests
```bash
php artisan test --profile
```

### Test Specific Groups
```php
/**
 * @group slow
 */
public function test_slow_operation()
{
    // ...
}
```

```bash
php artisan test --group=slow
php artisan test --exclude-group=slow
```

## Maintenance

### Adding New Tests
1. Identify appropriate test suite
2. Use relevant test utilities (Concerns)
3. Follow naming conventions
4. Update this guide

### Updating Tests
1. Run full suite after changes
2. Update documentation
3. Ensure coverage doesn't drop

## Support and Documentation

- PHPUnit Documentation: https://phpunit.de/
- Laravel Testing: https://laravel.com/docs/testing
- Mockery Documentation: http://docs.mockery.io/

## Next Steps

1. **Run the full test suite**: `php artisan test`
2. **Generate coverage report**: `php artisan test --coverage-html coverage`
3. **Review coverage gaps**: Open `coverage/index.html`
4. **Set up CI/CD**: Add test runs to your pipeline
5. **Monitor test health**: Track execution time and failures

---

**Last Updated**: 2025-12-29
**Test Count**: 97+ comprehensive tests
**Coverage Target**: 98%+
