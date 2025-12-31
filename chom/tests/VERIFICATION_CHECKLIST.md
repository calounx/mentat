# Test Suite Verification Checklist

Use this checklist to verify the test suite is properly set up and working.

## Prerequisites

- [ ] PHP 8.2+ installed
- [ ] Composer dependencies installed (`composer install`)
- [ ] PHPUnit configured (`phpunit.xml` present)
- [ ] Database configuration set for testing

## File Verification

### Test Files
- [ ] `/tests/Unit/ObservabilityAdapterTest.php` exists
- [ ] `/tests/Unit/TenantScopeTest.php` exists
- [ ] `/tests/Feature/SiteControllerAuthorizationTest.php` exists
- [ ] `/tests/Feature/TenantIsolationIntegrationTest.php` exists
- [ ] `/tests/Concerns/WithTenantIsolation.php` exists

### Factory Files
- [ ] `/database/factories/SiteFactory.php` exists
- [ ] `/database/factories/OperationFactory.php` exists
- [ ] `/database/factories/UsageRecordFactory.php` exists
- [ ] `/database/factories/VpsAllocationFactory.php` exists
- [ ] `/database/factories/VpsServerFactory.php` exists

### Documentation Files
- [ ] `/tests/SECURITY_TESTING.md` exists
- [ ] `/tests/QUICK_START_TESTING.md` exists
- [ ] `/tests/TEST_SUITE_SUMMARY.md` exists
- [ ] `/tests/VERIFICATION_CHECKLIST.md` exists (this file)

## Syntax Verification

Run these commands to verify no syntax errors:

```bash
# Check test files
php -l /home/calounx/repositories/mentat/chom/tests/Unit/ObservabilityAdapterTest.php
php -l /home/calounx/repositories/mentat/chom/tests/Unit/TenantScopeTest.php
php -l /home/calounx/repositories/mentat/chom/tests/Feature/SiteControllerAuthorizationTest.php
php -l /home/calounx/repositories/mentat/chom/tests/Feature/TenantIsolationIntegrationTest.php
php -l /home/calounx/repositories/mentat/chom/tests/Concerns/WithTenantIsolation.php

# Check factory files
php -l /home/calounx/repositories/mentat/chom/database/factories/SiteFactory.php
php -l /home/calounx/repositories/mentat/chom/database/factories/OperationFactory.php
php -l /home/calounx/repositories/mentat/chom/database/factories/UsageRecordFactory.php
php -l /home/calounx/repositories/mentat/chom/database/factories/VpsAllocationFactory.php
php -l /home/calounx/repositories/mentat/chom/database/factories/VpsServerFactory.php
```

- [ ] All test files have valid PHP syntax
- [ ] All factory files have valid PHP syntax

## Test Execution Verification

### Run Individual Test Suites

```bash
# 1. PromQL Injection Tests (should see 18 tests pass)
php artisan test --filter=ObservabilityAdapterTest
```
- [ ] ObservabilityAdapterTest runs successfully
- [ ] All 18 tests pass

```bash
# 2. Tenant Scope Tests (should see 21 tests pass)
php artisan test --filter=TenantScopeTest
```
- [ ] TenantScopeTest runs successfully
- [ ] All 21 tests pass

```bash
# 3. Authorization Tests (should see 27 tests pass)
php artisan test --filter=SiteControllerAuthorizationTest
```
- [ ] SiteControllerAuthorizationTest runs successfully
- [ ] All 27 tests pass

```bash
# 4. Integration Tests (should see 16 tests pass)
php artisan test --filter=TenantIsolationIntegrationTest
```
- [ ] TenantIsolationIntegrationTest runs successfully
- [ ] All 16 tests pass

### Run Complete Test Suite

```bash
# Run all tests together (should see 82 total tests pass)
php artisan test
```
- [ ] All tests run without errors
- [ ] Total of 82 tests pass
- [ ] No failures or warnings

## Database Verification

Check that tests use the correct database configuration:

```bash
# Verify PHPUnit configuration
cat phpunit.xml | grep -A 5 "DB_CONNECTION"
```

Expected output:
```xml
<env name="DB_CONNECTION" value="sqlite"/>
<env name="DB_DATABASE" value=":memory:"/>
```

- [ ] Tests use SQLite in-memory database
- [ ] No test data persists between runs

## Model Verification

Verify that all tested models have global scopes:

```bash
# Check Site model
grep -A 10 "protected static function booted" /home/calounx/repositories/mentat/chom/app/Models/Site.php

# Check Operation model
grep -A 10 "protected static function booted" /home/calounx/repositories/mentat/chom/app/Models/Operation.php

# Check UsageRecord model
grep -A 10 "protected static function booted" /home/calounx/repositories/mentat/chom/app/Models/UsageRecord.php

# Check VpsAllocation model
grep -A 10 "protected static function booted" /home/calounx/repositories/mentat/chom/app/Models/VpsAllocation.php
```

- [ ] Site model has global tenant scope
- [ ] Operation model has global tenant scope
- [ ] UsageRecord model has global tenant scope
- [ ] VpsAllocation model has global tenant scope

## Service Verification

Verify ObservabilityAdapter has escaping methods:

```bash
# Check for escaping methods
grep -n "escapePromQLLabelValue\|escapeLogQLString" /home/calounx/repositories/mentat/chom/app/Services/Integration/ObservabilityAdapter.php
```

- [ ] `escapePromQLLabelValue()` method exists
- [ ] `escapeLogQLString()` method exists
- [ ] Methods are used in queries

## Policy Verification

Verify SitePolicy checks tenant ownership:

```bash
# Check for tenant ownership check
grep -n "belongsToTenant" /home/calounx/repositories/mentat/chom/app/Policies/SitePolicy.php
```

- [ ] `belongsToTenant()` method exists
- [ ] All policy methods use tenant check
- [ ] Policies return proper Response objects

## Coverage Verification (Optional)

If you have Xdebug installed:

```bash
# Generate coverage report
XDEBUG_MODE=coverage php artisan test --coverage
```

- [ ] Coverage report generates successfully
- [ ] Coverage is above 80% for tested classes

## Integration Verification

### CI/CD Ready

- [ ] Tests can run in CI environment
- [ ] Tests run in parallel (`php artisan test --parallel`)
- [ ] Tests can stop on first failure (`--stop-on-failure`)

### Production Ready

- [ ] All tests pass consistently
- [ ] No flaky tests (run multiple times to verify)
- [ ] Documentation is complete and accurate

## Troubleshooting

### Issue: Tests fail with "Class not found"
**Solution:**
```bash
composer dump-autoload
php artisan test
```

### Issue: Database errors
**Solution:**
Verify PHPUnit configuration uses SQLite:
```bash
grep "DB_CONNECTION" phpunit.xml
```

### Issue: HTTP client not mocked
**Solution:**
Check that `Http::fake()` is called in tests before making HTTP requests.

### Issue: Factory errors
**Solution:**
Ensure all factory files are in `/database/factories/` and properly namespaced.

## Final Verification

Run this comprehensive check:

```bash
# Clear cache
php artisan cache:clear
php artisan config:clear

# Regenerate autoload
composer dump-autoload

# Run all tests
php artisan test --verbose

# Check syntax of all files
find tests/ -name "*.php" -exec php -l {} \;
find database/factories/ -name "*Factory.php" -exec php -l {} \;
```

- [ ] All tests pass
- [ ] No syntax errors
- [ ] No warnings or deprecations

## Sign-off

Test suite verification completed on: _______________

Verified by: _______________

Notes:
_____________________________________________________________________________
_____________________________________________________________________________
_____________________________________________________________________________

All items checked: [ ] YES  [ ] NO

If NO, list remaining issues:
_____________________________________________________________________________
_____________________________________________________________________________
_____________________________________________________________________________
