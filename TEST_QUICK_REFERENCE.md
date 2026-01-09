# Multi-Tenancy Security Tests - Quick Reference

Quick commands to run the comprehensive unit tests for Phase 1 & 2 multi-tenancy implementation.

## VPSManager Bash Tests

### Users.sh Unit Tests (Phase 2)
```bash
# Run all users.sh unit tests (no root required)
./deploy/vpsmanager/tests/unit/test-users.sh
```

**Tests:** 19 tests for domain_to_username() and related functions
**Duration:** ~1 second
**Requirements:** bash 4.0+, no root needed

---

## Laravel/CHOM Tests (Phase 1)

### Run All Tests
```bash
# From project root
php artisan test
```

### Run Specific Test Files

#### 1. BackupRepository Unit Tests
```bash
php artisan test chom/tests/Unit/Repositories/BackupRepositoryTest.php
```
**Tests:** 6 security-focused repository tests
**Focus:** Database-level tenant isolation

#### 2. StoreBackupRequest Validation Tests
```bash
php artisan test chom/tests/Unit/Requests/StoreBackupRequestTest.php
```
**Tests:** 17 validation and security tests
**Focus:** Cross-tenant site_id rejection

#### 3. BackupController Unit Tests
```bash
php artisan test chom/tests/Unit/Controllers/BackupControllerTest.php
```
**Tests:** 16 controller security tests
**Focus:** Consistent security across all endpoints

#### 4. Feature Tests (Existing)
```bash
php artisan test chom/tests/Feature/BackupTenantIsolationTest.php
```
**Tests:** 8 end-to-end integration tests
**Focus:** API-level tenant isolation

### Run Only Multi-Tenancy Security Tests
```bash
# Run all new unit tests
php artisan test chom/tests/Unit/Repositories/BackupRepositoryTest.php --filter=test_find_by_id_and_tenant
php artisan test chom/tests/Unit/Requests/StoreBackupRequestTest.php --filter=cross_tenant
php artisan test chom/tests/Unit/Controllers/BackupControllerTest.php --filter=cross_tenant
```

---

## VPSManager Integration Tests

### Site Isolation Tests (Requires Full Environment)
```bash
# Run comprehensive site isolation integration tests (requires root)
sudo ./deploy/vpsmanager/tests/integration/test-site-isolation.sh
```

**Tests:** 7 integration tests
**Duration:** ~30-60 seconds
**Requirements:**
- Root privileges
- VPSManager installed at /opt/vpsmanager
- nginx, PHP 8.2+, MariaDB running

---

## Test Coverage Summary

| Test Suite | File | Tests | Focus |
|------------|------|-------|-------|
| Repository Unit | BackupRepositoryTest.php | 6 | Database isolation |
| Validation Unit | StoreBackupRequestTest.php | 17 | Input validation |
| Controller Unit | BackupControllerTest.php | 16 | Endpoint security |
| Feature | BackupTenantIsolationTest.php | 8 | End-to-end API |
| Bash Unit | test-users.sh | 19 | Username generation |
| Integration | test-site-isolation.sh | 7 | System-level isolation |
| **TOTAL** | **6 files** | **73** | **Full coverage** |

---

## Quick Test Status Check

### Check if VPSManager tests pass
```bash
./deploy/vpsmanager/tests/unit/test-users.sh && echo "✓ PASSED" || echo "✗ FAILED"
```

### Check Laravel tests (requires setup)
```bash
php artisan test chom/tests/Unit/Repositories/BackupRepositoryTest.php --filter=test_find_by_id_and_tenant_returns_null_for_cross_tenant_access
```

---

## Expected Output (Success)

### VPSManager Unit Tests
```
==============================================================================
VPSManager Users.sh Unit Tests
==============================================================================
✓ PASS: Found users.sh
...
[TEST 19] Documentation example works as described
✓ PASS: Documentation example verified

==============================================================================
Test Summary
==============================================================================
Total Tests: 19
Passed: 19
Failed: 0

✓ ALL TESTS PASSED
```

### Laravel Tests
```
PASS  Tests\Unit\Repositories\BackupRepositoryTest
✓ find by id and tenant returns backup for same tenant
✓ find by id and tenant returns null for cross tenant access
✓ find by id and tenant returns null for nonexistent backup
✓ find by id and tenant properly loads site relationship
✓ find by id and tenant prevents information leakage
✓ find by id and tenant enforces tenant filter at database level

Tests:  6 passed
Time:   1.23s
```

---

## Troubleshooting

### Laravel Tests Fail with "Class not found"
```bash
# Run composer dump-autoload
composer dump-autoload

# Clear config cache
php artisan config:clear

# Run tests again
php artisan test
```

### VPSManager Tests Fail
```bash
# Check if users.sh exists
ls -l /home/calounx/repositories/mentat/deploy/vpsmanager/lib/core/users.sh

# Make test script executable
chmod +x /home/calounx/repositories/mentat/deploy/vpsmanager/tests/unit/test-users.sh

# Run with debug mode
bash -x /home/calounx/repositories/mentat/deploy/vpsmanager/tests/unit/test-users.sh
```

---

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Multi-Tenancy Security Tests

on: [push, pull_request]

jobs:
  bash-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run VPSManager Unit Tests
        run: ./deploy/vpsmanager/tests/unit/test-users.sh

  laravel-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
      - name: Install Dependencies
        run: composer install
      - name: Run Tests
        run: |
          php artisan test chom/tests/Unit/Repositories/BackupRepositoryTest.php
          php artisan test chom/tests/Unit/Requests/StoreBackupRequestTest.php
          php artisan test chom/tests/Unit/Controllers/BackupControllerTest.php
```

---

## Files Created

### New Test Files
1. `/home/calounx/repositories/mentat/chom/tests/Unit/Repositories/BackupRepositoryTest.php` (updated)
2. `/home/calounx/repositories/mentat/chom/tests/Unit/Requests/StoreBackupRequestTest.php` (new)
3. `/home/calounx/repositories/mentat/chom/tests/Unit/Controllers/BackupControllerTest.php` (new)
4. `/home/calounx/repositories/mentat/deploy/vpsmanager/tests/unit/test-users.sh` (new)

### Documentation
1. `/home/calounx/repositories/mentat/MULTI_TENANCY_TESTS_SUMMARY.md` (new)
2. `/home/calounx/repositories/mentat/TEST_QUICK_REFERENCE.md` (this file)
3. `/home/calounx/repositories/mentat/deploy/vpsmanager/tests/README.md` (updated)

---

## Next Steps

1. **Run the VPSManager unit tests** to verify they pass:
   ```bash
   ./deploy/vpsmanager/tests/unit/test-users.sh
   ```

2. **Setup Laravel test environment** if not already configured:
   ```bash
   cp .env.example .env
   php artisan key:generate
   composer install
   ```

3. **Run Laravel tests** to verify implementation:
   ```bash
   php artisan test
   ```

4. **Review test coverage** in the summary document:
   ```bash
   cat MULTI_TENANCY_TESTS_SUMMARY.md
   ```

---

## Documentation

For comprehensive test documentation, see:
- **MULTI_TENANCY_TESTS_SUMMARY.md** - Complete test documentation
- **deploy/vpsmanager/tests/README.md** - VPSManager test documentation
- **chom/tests/Feature/BackupTenantIsolationTest.php** - Feature test examples

---

Created: 2026-01-09
Author: Claude Code
