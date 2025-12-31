# Test Suite Quick Reference

## Quick Commands

### Run Everything
```bash
cd /home/calounx/repositories/mentat/chom
php artisan test
```

### Run with Coverage
```bash
php artisan test --coverage --min=98
php artisan test --coverage-html coverage
```

### Run by Suite
```bash
php artisan test --testsuite=Integration    # End-to-end workflows (37+ tests)
php artisan test --testsuite=Security       # Security attacks (23+ tests)
php artisan test --testsuite=Performance    # Performance benchmarks (3+ tests)
php artisan test --testsuite=Unit           # Unit tests (19+ tests)
php artisan test --testsuite=Api            # API contracts (3+ tests)
php artisan test --testsuite=Database       # Database tests (8+ tests)
php artisan test --testsuite=Regression     # Regression tests (1+ test)
php artisan test --testsuite=CI             # Code quality (3+ tests)
```

### Run Single File
```bash
php artisan test tests/Integration/SiteProvisioningFlowTest.php
php artisan test tests/Security/InjectionAttackTest.php
```

### Debug Options
```bash
php artisan test --verbose                  # Detailed output
php artisan test --stop-on-failure         # Stop at first failure
php artisan test --filter=test_name        # Run specific test
```

## Test Utilities

### VPS Mocking (WithMockVpsManager)
```php
use Tests\Concerns\WithMockVpsManager;

$this->mockSuccessfulVpsAllocation();
$this->mockSuccessfulSshConnection();
$this->mockCommandExecution('command', 'output');
$this->assertCommandExecuted('command');
```

### Observability Mocking (WithMockObservability)
```php
use Tests\Concerns\WithMockObservability;

$this->mockPrometheusQuery('query', ['result']);
$this->mockLokiLogPush('stream', 'message');
$this->assertPrometheusMetricRecorded('metric');
```

### Performance Testing (WithPerformanceTesting)
```php
use Tests\Concerns\WithPerformanceTesting;

$this->assertBenchmark(fn() => $operation(), 'dashboard_load');
$this->assertNoN1Queries($setup, $test);
$this->assertMaxQueries(5);
```

### Security Testing (WithSecurityTesting)
```php
use Tests\Concerns\WithSecurityTesting;

$this->assertSqlInjectionProtection($callback);
$this->assertPromQLInjectionProtection($callback);
$this->assertTenantIsolation($user, $resourceId, $uri);
```

## Key Files

### Test Utilities
- `/home/calounx/repositories/mentat/chom/tests/Concerns/WithMockVpsManager.php`
- `/home/calounx/repositories/mentat/chom/tests/Concerns/WithMockObservability.php`
- `/home/calounx/repositories/mentat/chom/tests/Concerns/WithPerformanceTesting.php`
- `/home/calounx/repositories/mentat/chom/tests/Concerns/WithSecurityTesting.php`

### Integration Tests
- `/home/calounx/repositories/mentat/chom/tests/Integration/SiteProvisioningFlowTest.php`
- `/home/calounx/repositories/mentat/chom/tests/Integration/BackupRestoreFlowTest.php`
- `/home/calounx/repositories/mentat/chom/tests/Integration/AuthenticationFlowTest.php`

### Security Tests
- `/home/calounx/repositories/mentat/chom/tests/Security/InjectionAttackTest.php`
- `/home/calounx/repositories/mentat/chom/tests/Security/AuthorizationSecurityTest.php`
- `/home/calounx/repositories/mentat/chom/tests/Security/SessionSecurityTest.php`

## Performance Benchmarks

| Operation | Threshold | Test |
|-----------|-----------|------|
| Dashboard Load | < 100ms | `assertBenchmark('dashboard_load')` |
| Site Creation | < 2000ms | `assertBenchmark('site_creation')` |
| Cache Operation | < 1ms | `assertBenchmark('cache_operation')` |
| DB Query | < 50ms | `assertBenchmark('database_query')` |
| API Response | < 200ms | `assertBenchmark('api_response')` |

## Security Coverage

| Attack Type | Test File | Payloads |
|-------------|-----------|----------|
| SQL Injection | InjectionAttackTest | 6 |
| PromQL Injection | InjectionAttackTest | 3 |
| Command Injection | InjectionAttackTest | 5 |
| XSS | SecurityTesting trait | 5 |
| Authorization | AuthorizationSecurityTest | 10 |

## Documentation

- **Comprehensive Guide**: `/home/calounx/repositories/mentat/chom/tests/COMPREHENSIVE_TEST_SUITE.md`
- **Execution Guide**: `/home/calounx/repositories/mentat/chom/tests/TEST_EXECUTION_GUIDE.md`
- **Implementation Summary**: `/home/calounx/repositories/mentat/chom/tests/COMPREHENSIVE_TEST_IMPLEMENTATION_SUMMARY.md`
- **Files List**: `/home/calounx/repositories/mentat/chom/tests/FILES_CREATED.txt`

## CI/CD Integration

### GitHub Actions
```yaml
- name: Run Tests
  run: php artisan test --coverage --min=98
```

### GitLab CI
```yaml
test:
  script:
    - php artisan test --coverage --min=98
```

## Troubleshooting

```bash
# Clear cache
php artisan config:clear
php artisan cache:clear

# Rebuild autoload
composer dump-autoload

# Check syntax
vendor/bin/pint --test

# Fresh database
php artisan migrate:fresh --env=testing
```

## Stats

- **Total Tests**: 97+
- **Total Files**: 23 test files
- **Code Lines**: 5,430+
- **Coverage Goal**: 98%
- **Execution Time**: ~90 seconds
- **Security Tests**: 100% coverage
- **Critical Paths**: 100% coverage

---
**Quick Start**: `cd /home/calounx/repositories/mentat/chom && php artisan test`
