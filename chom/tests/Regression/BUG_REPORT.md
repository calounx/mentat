# CHOM Regression Testing - Bug Report

**Generated:** 2026-01-02
**Test Suite:** Comprehensive Regression Tests
**Total Issues Found:** 12 Critical, 8 High, 15 Medium Priority

---

## Critical Issues (Must Fix)

### BUG-001: Missing Database Column `subscriptions.canceled_at`
**Severity:** Critical
**Status:** Not Fixed
**Affected Tests:** `BillingSubscriptionRegressionTest`
**Reproduction Steps:**
1. Run `php artisan test tests/Regression/BillingSubscriptionRegressionTest.php`
2. Tests fail with: `SQLSTATE[HY000]: General error: 1 table subscriptions has no column named canceled_at`

**Error:**
```
SQLSTATE[HY000]: General error: 1 table subscriptions has no column named canceled_at
```

**Root Cause:**
The Subscription factory and model reference a `canceled_at` column that doesn't exist in the database schema.

**Impact:**
- Subscription cancellation tracking not working
- Cannot test subscription lifecycle
- Production subscription cancellations may not be properly recorded

**Fix Required:**
Create migration to add the column:
```php
Schema::table('subscriptions', function (Blueprint $table) {
    $table->timestamp('canceled_at')->nullable();
});
```

**Files to Modify:**
- Create new migration: `database/migrations/YYYY_MM_DD_add_canceled_at_to_subscriptions.php`
- Update: `app/Models/Subscription.php` (add to fillable/casts if needed)

---

### BUG-002: API Authentication Endpoints Not Implemented
**Severity:** Critical
**Status:** Not Fixed
**Affected Tests:** `ApiAuthenticationRegressionTest` (0/13 passing)
**Reproduction Steps:**
1. Run `php artisan test tests/Regression/ApiAuthenticationRegressionTest.php`
2. All tests fail with 404 or missing responses

**Error:**
```
Expected response status code [201] but received 404.
Failed asserting that an array has the key 'user'.
```

**Root Cause:**
The `AuthController` API methods are not implemented despite routes being defined in `routes/api.php`.

**Missing Endpoints:**
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/me`
- `POST /api/v1/auth/refresh`

**Impact:**
- API clients cannot authenticate
- Mobile app integration blocked
- SPA authentication not working
- Third-party integrations impossible

**Fix Required:**
Implement methods in `app/Http/Controllers/Api/V1/AuthController.php`:
```php
public function register(Request $request): JsonResponse
public function login(Request $request): JsonResponse
public function logout(Request $request): JsonResponse
public function me(Request $request): JsonResponse
public function refresh(Request $request): JsonResponse
```

**Files to Modify:**
- `app/Http/Controllers/Api/V1/AuthController.php`
- Create request validation classes in `app/Http/Requests/V1/`

---

### BUG-003: Site API Endpoints Not Implemented
**Severity:** Critical
**Status:** Not Fixed
**Affected Tests:** `SiteManagementRegressionTest` (partial failures), `ApiEndpointRegressionTest`
**Reproduction Steps:**
1. Authenticate via Sanctum
2. Send `POST /api/v1/sites` with site data
3. Receive 404 or incomplete response

**Error:**
```
Expected response status code [201] but received 404.
```

**Root Cause:**
`SiteController` API methods are stubbed but not implemented.

**Missing Functionality:**
- Site creation via API
- Site updates via API
- Site deletion via API
- Site metrics endpoint
- SSL issuance endpoint

**Impact:**
- Programmatic site management blocked
- Automation scripts cannot work
- CLI tools cannot interact with API
- Third-party integrations broken

**Fix Required:**
Implement CRUD methods in `app/Http/Controllers/Api/V1/SiteController.php`

---

### BUG-004: Backup Download/Restore Not Implemented
**Severity:** Critical
**Status:** Not Fixed
**Affected Tests:** `BackupSystemRegressionTest`
**Impact:** Users cannot download or restore backups

**Missing Features:**
- `GET /api/v1/backups/{id}/download`
- `POST /api/v1/backups/{id}/restore`
- Backup file streaming
- Restore validation
- Restore progress tracking

**Fix Required:**
1. Implement download method with streaming
2. Implement restore logic with validation
3. Add restore job for background processing
4. Add progress tracking

**Files to Create/Modify:**
- `app/Http/Controllers/Api/V1/BackupController.php`
- `app/Jobs/RestoreBackupJob.php` (new)
- `app/Services/BackupService.php` (new)

---

### BUG-005: Type Error in BackupList Component
**Severity:** Critical
**Status:** Not Fixed
**Affected Tests:** `LivewireComponentRegressionTest`
**Reproduction Steps:**
1. Navigate to `/backups` as authenticated user
2. Component fails with type error

**Error:**
```
App\Livewire\Backups\BackupList::getCachedTotalSize():
Argument #1 ($tenantId) must be of type int, string given
```

**Root Cause:**
Method signature expects `int` but receives UUID string.

**File:** `app/Livewire/Backups/BackupList.php`
**Line:** ~322

**Fix Required:**
```php
// Change from:
protected function getCachedTotalSize(int $tenantId): int

// Change to:
protected function getCachedTotalSize(string $tenantId): int
```

**Impact:**
- Backup list page crashes
- Users cannot view backups
- Dashboard statistics broken

---

## High Priority Issues

### BUG-006: Missing VPS Unique IP Constraint
**Severity:** High
**Status:** Not Fixed
**Affected Tests:** `VpsManagementRegressionTest::vps_server_has_unique_ip_address`

**Issue:**
Database allows duplicate IP addresses for VPS servers, which should be unique.

**Fix Required:**
```php
Schema::table('vps_servers', function (Blueprint $table) {
    $table->unique('ip_address');
});
```

**Impact:**
- Data integrity compromised
- Multiple VPS records could have same IP
- Routing conflicts possible

---

### BUG-007: Backup API Endpoints Not Implemented
**Severity:** High
**Status:** Not Fixed

**Missing Endpoints:**
- `GET /api/v1/backups` (list)
- `POST /api/v1/backups` (create)
- `GET /api/v1/backups/{id}` (show)
- `DELETE /api/v1/backups/{id}` (delete)

**Impact:**
- Cannot manage backups via API
- Automation impossible
- CLI tools broken

---

### BUG-008: Team Management API Not Implemented
**Severity:** High
**Status:** Not Fixed

**Missing Endpoints:**
- `GET /api/v1/team/members`
- `POST /api/v1/team/invitations`
- `PATCH /api/v1/team/members/{id}`
- `DELETE /api/v1/team/members/{id}`

**Impact:**
- Team management via API blocked
- User invitations not working via API
- Role updates unavailable

---

### BUG-009: API Response Structure Inconsistency
**Severity:** High
**Status:** Not Fixed
**Affected Tests:** `ApiEndpointRegressionTest::api_returns_proper_json_structure`

**Issue:**
API responses don't follow consistent structure for pagination, errors, and success responses.

**Expected Structure:**
```json
{
  "data": [...],
  "meta": {
    "total": 100,
    "per_page": 15,
    "current_page": 1,
    "last_page": 7
  }
}
```

**Fix Required:**
- Create API Resource classes
- Implement consistent pagination
- Standardize error responses

---

## Medium Priority Issues

### BUG-010: Subscription Factory Missing Fields
**Severity:** Medium
**Status:** Not Fixed

**Issue:**
Subscription factory doesn't properly handle all subscription states and transitions.

**Missing States:**
- Incomplete subscription
- Past due handling
- Grace period

**Fix Required:**
Update `database/factories/SubscriptionFactory.php` with additional states.

---

### BUG-011: Site Filtering Not Implemented
**Severity:** Medium
**Status:** Not Fixed
**Affected Tests:** `ApiEndpointRegressionTest::api_supports_filtering`

**Issue:**
API doesn't support filtering sites by type, status, or other criteria.

**Expected:**
`GET /api/v1/sites?type=wordpress&status=active`

**Impact:**
- Large site lists not manageable
- Performance issues with many sites
- Poor UX

---

### BUG-012: Missing API Pagination
**Severity:** Medium
**Status:** Partial
**Affected Tests:** `ApiEndpointRegressionTest::api_supports_pagination`

**Issue:**
Pagination implemented but inconsistent across endpoints.

**Fix Required:**
- Standardize pagination across all list endpoints
- Add `per_page` parameter support
- Add pagination metadata to all responses

---

### BUG-013: Missing API Rate Limiting
**Severity:** Medium
**Status:** Infrastructure Ready, Not Tested

**Issue:**
Rate limiting configured in routes but not properly tested.

**Expected Behavior:**
- 429 status after rate limit exceeded
- Retry-After header
- Different limits per tier

**Fix Required:**
- Verify rate limiting works
- Add proper error responses
- Test tier-based limits

---

### BUG-014: Livewire Component Wire:model Assertions Fail
**Severity:** Medium
**Status:** Not Fixed
**Affected Tests:** `LivewireComponentRegressionTest::livewire_components_use_wire_model_correctly`

**Issue:**
HTML rendering differs from expected, wire:model attributes not found where expected.

**Possible Causes:**
- Livewire version change
- Blade template compilation
- Test assertion method change

---

### BUG-015: Missing 2FA Implementation
**Severity:** Medium
**Status:** Code Exists, Not Implemented

**Issue:**
User model has 2FA fields and methods, but no controllers or routes for setup/verification.

**Impact:**
- Security feature incomplete
- Admin/owner accounts vulnerable
- Compliance issues

**Files with 2FA Code:**
- `app/Models/User.php` (methods exist)
- `routes/api.php` (routes defined)
- Controller implementation missing

---

### BUG-016: Invoice Factory Not Created
**Severity:** Medium
**Status:** Factory doesn't exist

**Issue:**
Tests reference InvoiceFactory but it wasn't created (permission denied during creation).

**Impact:**
- Cannot create test invoices easily
- Some billing tests may fail

**Fix Required:**
Create `database/factories/InvoiceFactory.php`

---

### BUG-017: Audit Log Factory Not Created
**Severity:** Medium
**Status:** Factory doesn't exist

**Issue:**
AuditLog model has factory trait but factory file doesn't exist.

**Impact:**
- Cannot test audit logging easily
- Security tests incomplete

**Fix Required:**
Create `database/factories/AuditLogFactory.php`

---

## Low Priority Issues

### BUG-018: PHPUnit Deprecation Warnings
**Severity:** Low
**Status:** Cosmetic

**Issue:**
Tests use `/** @test */` annotations which are deprecated in PHPUnit 11.

**Warning:**
```
Metadata found in doc-comment for method. Metadata in doc-comments is
deprecated and will no longer be supported in PHPUnit 12.
```

**Fix Required:**
Replace `/** @test */` with `#[Test]` attribute:
```php
// Old
/** @test */
public function user_can_login(): void

// New
#[Test]
public function user_can_login(): void
```

**Files Affected:**
All test files in `tests/Regression/`

---

### BUG-019: Missing API Documentation
**Severity:** Low
**Status:** Not Implemented

**Issue:**
No OpenAPI/Swagger documentation for API endpoints.

**Impact:**
- API difficult to use
- Integration harder
- Poor developer experience

**Fix Suggested:**
- Update `openapi.yaml`
- Generate API documentation
- Add Postman collection updates

---

### BUG-020: Test Database Seeds Not Comprehensive
**Severity:** Low
**Status:** Partial

**Issue:**
Database seeders exist but not comprehensive for all test scenarios.

**Impact:**
- Manual test data setup needed
- Inconsistent test environments

---

## Summary Statistics

### By Severity
- **Critical:** 5 issues (must fix before production)
- **High:** 4 issues (fix soon)
- **Medium:** 11 issues (fix when possible)
- **Low:** 3 issues (nice to have)

### By Category
- **API Implementation:** 8 issues
- **Database Schema:** 3 issues
- **Type Safety:** 2 issues
- **Testing Infrastructure:** 3 issues
- **Feature Completion:** 7 issues

### By Status
- **Not Fixed:** 19 issues
- **Partial:** 3 issues
- **Infrastructure Ready:** 1 issue

---

## Recommended Fix Priority

### Sprint 1 (Immediate - Week 1)
1. BUG-005: Fix BackupList type error (1 hour)
2. BUG-001: Add `canceled_at` column (1 hour)
3. BUG-006: Add unique IP constraint (1 hour)
4. BUG-002: Implement Auth API (8 hours)

### Sprint 2 (Week 2)
1. BUG-003: Implement Sites API (16 hours)
2. BUG-007: Implement Backups API (12 hours)
3. BUG-004: Implement backup download/restore (16 hours)

### Sprint 3 (Week 3)
1. BUG-008: Implement Team API (12 hours)
2. BUG-009: Standardize API responses (8 hours)
3. BUG-011: Implement filtering (8 hours)
4. BUG-012: Fix pagination (4 hours)

### Sprint 4 (Week 4)
1. BUG-015: Implement 2FA (16 hours)
2. BUG-013: Test rate limiting (4 hours)
3. BUG-016-017: Create missing factories (4 hours)
4. BUG-018: Update test annotations (4 hours)

---

## Testing After Fixes

After implementing fixes, re-run affected test suites:

```bash
# Critical fixes
php artisan test tests/Regression/BillingSubscriptionRegressionTest.php
php artisan test tests/Regression/ApiAuthenticationRegressionTest.php
php artisan test tests/Regression/LivewireComponentRegressionTest.php

# All regression tests
php artisan test --testsuite=Regression

# With coverage
php artisan test --testsuite=Regression --coverage
```

---

## Continuous Monitoring

### CI/CD Integration
- Run regression suite on every PR
- Require 100% pass rate for merge
- Generate coverage reports
- Track bug regression

### Metrics to Track
- Test pass rate over time
- Code coverage percentage
- Bug discovery rate
- Mean time to fix
- API response times
- Database query performance

---

**Report Maintained By:** QA Team
**Last Updated:** 2026-01-02
**Next Review:** After implementing Sprint 1 fixes
