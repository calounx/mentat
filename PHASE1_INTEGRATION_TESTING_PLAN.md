# Phase 1 Integration and Testing Plan

**Project:** CHOM (Cloud Hosting Operations Manager)
**Phase:** Phase 1 - Quick Wins (Week 1-2)
**Date:** January 3, 2026
**Version:** 1.0
**Status:** Ready for Implementation

---

## Executive Summary

This document provides a comprehensive integration and testing plan for Phase 1 of the CHOM refactoring initiative. Phase 1 focuses on "Quick Wins" - low-risk, high-impact improvements that establish foundational patterns for future refactoring.

**Phase 1 Scope:**
- 2 Reusable Traits (ApiResponse, HasTenantContext)
- 1 Base API Controller
- 5 API Resource classes
- 7 Form Request classes

**Expected Impact:**
- 500+ lines of code reduced (25% duplication)
- Consistent API responses across all endpoints
- Centralized tenant context management
- Improved validation coverage
- Foundation for Phase 2-3 refactoring

**Timeline:** 2 weeks (10 working days)
**Risk Level:** LOW
**Team Size:** 2 developers

---

## Table of Contents

1. [Component Review](#component-review)
2. [Integration Checklist](#integration-checklist)
3. [Testing Plan](#testing-plan)
4. [Migration Strategy](#migration-strategy)
5. [Quality Metrics](#quality-metrics)
6. [Documentation](#documentation)
7. [Rollback Plan](#rollback-plan)
8. [Timeline](#timeline)

---

## Component Review

### 1. ApiResponse Trait

**Purpose:** Standardize JSON API responses across all controllers

**Location:** `chom/app/Http/Traits/ApiResponse.php`

**Review Criteria:**
- ✅ **Consistency:** All response methods follow same structure
- ✅ **Completeness:** Covers success, error, validation, pagination
- ✅ **Type Safety:** Proper return types (JsonResponse)
- ✅ **Extensibility:** Easy to add new response types
- ⚠️ **Security:** No sensitive data leakage in error responses

**Methods to Implement:**
```php
protected function successResponse($data, ?string $message = null, int $status = 200): JsonResponse
protected function paginatedResponse(LengthAwarePaginator $paginator, ?callable $transformer = null): JsonResponse
protected function errorResponse(string $code, string $message, array $details = [], int $status = 400): JsonResponse
protected function validationErrorResponse(array $errors): JsonResponse
```

**Current Implementation Issues:**
- ❌ 85+ duplicate response blocks across controllers
- ❌ Inconsistent pagination metadata
- ❌ Different error response formats
- ❌ Manual JSON construction everywhere

**After Implementation:**
- ✅ Single source of truth for API responses
- ✅ Consistent error codes and formats
- ✅ Easy to modify API contract globally
- ✅ Type-safe response construction

**Code Coverage Target:** 95%+

**Critical Test Cases:**
1. Success response with data
2. Success response with message
3. Success response with custom status code
4. Paginated response with default transformer
5. Paginated response with custom transformer
6. Error response with code and message
7. Error response with details array
8. Validation error response
9. HTTP status codes match response types
10. JSON structure consistency

**Integration Points:**
- All 6 API controllers (AuthController, SiteController, BackupController, TeamController, VpsController, HealthController)
- Future controllers automatically inherit

**Backward Compatibility:**
- ✅ Additive only - no breaking changes
- ✅ Controllers can adopt gradually
- ✅ Existing responses remain functional

---

### 2. HasTenantContext Trait

**Purpose:** Centralize tenant/organization resolution and authorization

**Location:** `chom/app/Http/Traits/HasTenantContext.php`

**Review Criteria:**
- ✅ **Security:** Proper authorization checks before tenant access
- ✅ **Caching:** Efficient tenant retrieval (no N+1 queries)
- ✅ **Error Handling:** Clear error messages for missing/inactive tenants
- ✅ **Extensibility:** Easy to add new context methods
- ⚠️ **Performance:** Minimal overhead per request

**Methods to Implement:**
```php
protected function getTenant(Request $request): Tenant
protected function getOrganization(Request $request): Organization
protected function requireRole(Request $request, string|array $roles): void
protected function requireAdmin(Request $request): void
protected function requireOwner(Request $request): void
```

**Current Implementation Issues:**
- ❌ 31+ duplicate `getTenant()` methods (310 lines)
- ❌ Inconsistent authorization patterns
- ❌ Tenant status checks scattered
- ❌ No organization context helper

**After Implementation:**
- ✅ Single tenant resolution logic
- ✅ Consistent authorization checks
- ✅ Centralized role validation
- ✅ Easy to add tenant-level caching

**Code Coverage Target:** 100%

**Critical Test Cases:**
1. getTenant() returns active tenant
2. getTenant() aborts when tenant inactive
3. getTenant() aborts when no tenant
4. getOrganization() returns organization
5. getOrganization() aborts when no org
6. requireRole() allows correct role
7. requireRole() denies incorrect role
8. requireRole() accepts multiple roles
9. requireAdmin() allows admin/owner
10. requireAdmin() denies regular user
11. requireOwner() allows owner only
12. requireOwner() denies non-owner

**Security Considerations:**
- ⚠️ **Critical:** Must validate tenant ownership before access
- ⚠️ **Critical:** Must check tenant status (active/suspended)
- ⚠️ **Critical:** Must prevent cross-tenant data access
- ✅ Audit log integration for authorization failures

**Integration Points:**
- All 6 API controllers
- 31+ methods to be removed
- Livewire components (future Phase 2)

**Backward Compatibility:**
- ✅ Additive only - existing methods remain
- ✅ Gradual migration possible
- ✅ No breaking changes to external APIs

---

### 3. Base ApiController

**Purpose:** Provide common functionality for all API controllers

**Location:** `chom/app/Http/Controllers/Api/ApiController.php`

**Review Criteria:**
- ✅ **Single Responsibility:** Only common concerns
- ✅ **Extensibility:** Easy for child controllers to override
- ✅ **Middleware:** Proper authentication/authorization
- ✅ **Logging:** Consistent error/info logging

**Methods to Implement:**
```php
protected function getPerPage(Request $request): int
protected function logError(string $message, array $context = []): void
protected function logInfo(string $message, array $context = []): void
```

**Current Implementation Issues:**
- ❌ No common base for API controllers
- ❌ Duplicate imports in every controller
- ❌ No shared pagination logic
- ❌ Inconsistent logging patterns

**After Implementation:**
- ✅ All API controllers extend ApiController
- ✅ Common traits automatically available
- ✅ Shared helper methods
- ✅ Easy to add cross-cutting concerns

**Code Coverage Target:** 90%+

**Critical Test Cases:**
1. getPerPage() returns default value
2. getPerPage() respects request parameter
3. getPerPage() enforces minimum (1)
4. getPerPage() enforces maximum (100)
5. logError() includes controller context
6. logError() includes user_id when authenticated
7. logInfo() includes controller context
8. Child controllers inherit traits
9. Child controllers can override methods

**Integration Points:**
- SiteController extends ApiController
- BackupController extends ApiController
- TeamController extends ApiController
- VpsController extends ApiController
- AuthController extends ApiController
- HealthController extends ApiController

**Backward Compatibility:**
- ✅ Controllers updated to extend new base
- ✅ No functional changes
- ✅ All existing methods preserved

---

### 4. API Resources (5 classes)

**Purpose:** Transform Eloquent models to consistent JSON API responses

**Resources to Create:**

#### 4.1 SiteResource
**Location:** `chom/app/Http/Resources/V1/SiteResource.php`

**Fields:**
```php
- id, domain, url, site_type, php_version
- ssl_enabled, ssl_expires_at
- status, storage_used_mb
- created_at, updated_at
- vps (conditional, when loaded)
- db_name, document_root, settings (when detailed=true)
- recent_backups (conditional, when loaded)
```

**Review Criteria:**
- ✅ All site fields properly transformed
- ✅ Conditional relationships (whenLoaded)
- ✅ Date formatting (ISO8601)
- ✅ Eager loading optimization
- ⚠️ No N+1 queries

**Replaces:** `formatSite()` method (50+ lines in SiteController)

#### 4.2 BackupResource
**Location:** `chom/app/Http/Resources/V1/BackupResource.php`

**Fields:**
```php
- id, site_id, backup_type
- storage_path, size_mb, size_formatted
- status, completed_at, created_at
- site (conditional, when loaded)
```

**Review Criteria:**
- ✅ Backup metadata complete
- ✅ Human-readable size formatting
- ✅ Status indicators clear
- ✅ Relationships properly loaded

**Replaces:** `formatBackup()` method (40+ lines in BackupController)

#### 4.3 TeamMemberResource
**Location:** `chom/app/Http/Resources/V1/TeamMemberResource.php`

**Fields:**
```php
- id, name, email, role
- email_verified_at, created_at
- organization_id (conditional)
- tenant_id (conditional)
```

**Review Criteria:**
- ✅ No password/token exposure
- ✅ Role information included
- ✅ Proper date formatting
- ⚠️ Security: No sensitive fields

**Replaces:** `formatMember()` method (30+ lines in TeamController)

#### 4.4 VpsResource
**Location:** `chom/app/Http/Resources/V1/VpsResource.php`

**Fields:**
```php
- id, hostname, ip_address
- status, provider, region
- cpu_cores, ram_mb, disk_gb
- sites_count (conditional)
- health_status, created_at, updated_at
```

**Review Criteria:**
- ✅ Infrastructure details complete
- ✅ No sensitive credentials
- ✅ Conditional aggregates
- ⚠️ Security: No SSH keys/passwords

**Replaces:** Manual VPS formatting (20+ lines in VpsController)

#### 4.5 TeamInvitationResource
**Location:** `chom/app/Http/Resources/V1/TeamInvitationResource.php`

**Fields:**
```php
- id, email, role, status
- invited_by (user info)
- expires_at, created_at
```

**Review Criteria:**
- ✅ Invitation details complete
- ✅ Inviter information included
- ✅ Expiration clearly shown
- ⚠️ Security: No invitation tokens

**Replaces:** Manual invitation formatting (15+ lines in TeamController)

**All Resources - Common Requirements:**
- ✅ Extends `Illuminate\Http\Resources\Json\JsonResource`
- ✅ Proper `toArray()` implementation
- ✅ `whenLoaded()` for relationships
- ✅ `mergeWhen()` for conditional fields
- ✅ Collection classes created (`SiteCollection`, `BackupCollection`, etc.)

**Code Coverage Target:** 85%+

**Critical Test Cases (per resource):**
1. Basic transformation works
2. All required fields present
3. Conditional relationships work
4. Nested resources transform correctly
5. Collection transformation works
6. No N+1 queries on collection
7. Date fields formatted correctly
8. No sensitive data exposed

---

### 5. Form Requests (7 classes)

**Purpose:** Centralize validation logic and authorization

**Requests to Create:**

#### 5.1 CreateSiteRequest
**Location:** `chom/app/Http/Requests/V1/Sites/CreateSiteRequest.php`

**Validation Rules:**
```php
'domain' => ['required', 'string', 'max:253', 'regex:/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i', Rule::unique('sites')->where('tenant_id', $tenant->id)]
'site_type' => ['sometimes', 'in:wordpress,html,laravel']
'php_version' => ['sometimes', 'in:8.2,8.4']
'ssl_enabled' => ['sometimes', 'boolean']
```

**Authorization:**
```php
return $this->user()->can('create', Site::class);
```

**Review Criteria:**
- ✅ Domain validation regex correct
- ✅ Unique check scoped to tenant
- ✅ Type/version validation complete
- ✅ Authorization check present

#### 5.2 UpdateSiteRequest
**Location:** `chom/app/Http/Requests/V1/Sites/UpdateSiteRequest.php`

**Validation Rules:**
```php
'php_version' => ['sometimes', 'in:8.2,8.4']
'ssl_enabled' => ['sometimes', 'boolean']
```

**Authorization:**
```php
return $this->user()->can('update', $this->route('site'));
```

#### 5.3 CreateBackupRequest
**Location:** `chom/app/Http/Requests/V1/Backups/CreateBackupRequest.php`

**Validation Rules:**
```php
'site_id' => ['required', 'uuid', 'exists:sites,id']
'backup_type' => ['sometimes', 'in:full,files,database']
```

#### 5.4 RestoreBackupRequest
**Location:** `chom/app/Http/Requests/V1/Backups/RestoreBackupRequest.php`

**Validation Rules:**
```php
'backup_id' => ['required', 'uuid', 'exists:site_backups,id']
'restore_files' => ['sometimes', 'boolean']
'restore_database' => ['sometimes', 'boolean']
```

#### 5.5 InviteMemberRequest
**Location:** `chom/app/Http/Requests/V1/Team/InviteMemberRequest.php`

**Validation Rules:**
```php
'email' => ['required', 'email', 'max:255', Rule::unique('team_invitations')->where('organization_id', $org->id)->where('status', 'pending')]
'role' => ['required', 'in:member,admin']
```

#### 5.6 UpdateMemberRequest
**Location:** `chom/app/Http/Requests/V1/Team/UpdateMemberRequest.php`

**Validation Rules:**
```php
'role' => ['required', 'in:member,admin,owner']
```

#### 5.7 CreateVpsRequest
**Location:** `chom/app/Http/Requests/V1/Vps/CreateVpsRequest.php`

**Validation Rules:**
```php
'hostname' => ['required', 'string', 'max:255', 'unique:vps_servers']
'ip_address' => ['required', 'ip', 'unique:vps_servers']
'ssh_port' => ['sometimes', 'integer', 'min:1', 'max:65535']
'provider' => ['required', 'in:hetzner,digitalocean,linode,aws']
```

**All Form Requests - Common Requirements:**
- ✅ Extends `Illuminate\Foundation\Http\FormRequest`
- ✅ `authorize()` method checks permissions
- ✅ `rules()` method defines validation
- ✅ `messages()` for custom error messages
- ✅ `attributes()` for friendly field names
- ✅ `prepareForValidation()` for data sanitization

**Code Coverage Target:** 90%+

**Critical Test Cases (per request):**
1. Valid data passes validation
2. Missing required fields fail
3. Invalid format fields fail
4. Authorization checks work
5. Unique constraints enforced
6. Custom messages displayed
7. Data sanitization works
8. Edge cases handled (max lengths, special chars)

---

## Integration Checklist

### Pre-Implementation Phase

**Environment Setup:**
- [ ] Create feature branch: `refactor/phase-1-quick-wins`
- [ ] Set up local testing environment
- [ ] Install PHPUnit 10.x
- [ ] Install Laravel Dusk for E2E tests
- [ ] Configure CI/CD pipeline for automated tests
- [ ] Set up code coverage reporting (PHPUnit coverage)

**Code Analysis:**
- [ ] Run PHPStan (level 8) on current codebase
- [ ] Run PHP-CS-Fixer to establish baseline
- [ ] Identify all controllers using old patterns
- [ ] Map all API endpoints to be affected
- [ ] Document current response formats
- [ ] Create baseline performance benchmarks

### Implementation Order (Dependencies)

**Week 1: Traits and Base Classes**

**Day 1-2: ApiResponse Trait**
- [ ] Create `chom/app/Http/Traits/ApiResponse.php`
- [ ] Implement `successResponse()` method
- [ ] Implement `paginatedResponse()` method
- [ ] Implement `errorResponse()` method
- [ ] Implement `validationErrorResponse()` method
- [ ] Add comprehensive PHPDoc comments
- [ ] Write unit tests (10+ test cases)
- [ ] Run tests and fix issues
- [ ] Code review by senior developer
- [ ] Merge trait only (no controller changes yet)

**Day 3: HasTenantContext Trait**
- [ ] Create `chom/app/Http/Traits/HasTenantContext.php`
- [ ] Implement `getTenant()` method
- [ ] Implement `getOrganization()` method
- [ ] Implement `requireRole()` method
- [ ] Implement `requireAdmin()` method
- [ ] Implement `requireOwner()` method
- [ ] Add comprehensive PHPDoc comments
- [ ] Write unit tests (12+ test cases)
- [ ] Add security tests (cross-tenant access prevention)
- [ ] Run tests and fix issues
- [ ] Code review by security expert
- [ ] Merge trait only (no controller changes yet)

**Day 4: Base ApiController**
- [ ] Create `chom/app/Http/Controllers/Api/ApiController.php`
- [ ] Import ApiResponse trait
- [ ] Import HasTenantContext trait
- [ ] Implement `getPerPage()` method
- [ ] Implement `logError()` method
- [ ] Implement `logInfo()` method
- [ ] Add comprehensive PHPDoc comments
- [ ] Write unit tests (9+ test cases)
- [ ] Run tests and fix issues
- [ ] Code review
- [ ] Merge base controller only

**Day 5: Create All API Resources**
- [ ] Create `chom/app/Http/Resources/V1/SiteResource.php`
- [ ] Create `chom/app/Http/Resources/V1/SiteCollection.php`
- [ ] Create `chom/app/Http/Resources/V1/BackupResource.php`
- [ ] Create `chom/app/Http/Resources/V1/BackupCollection.php`
- [ ] Create `chom/app/Http/Resources/V1/TeamMemberResource.php`
- [ ] Create `chom/app/Http/Resources/V1/TeamMemberCollection.php`
- [ ] Create `chom/app/Http/Resources/V1/VpsResource.php`
- [ ] Create `chom/app/Http/Resources/V1/VpsCollection.php`
- [ ] Create `chom/app/Http/Resources/V1/TeamInvitationResource.php`
- [ ] Create `chom/app/Http/Resources/V1/TeamInvitationCollection.php`
- [ ] Add comprehensive PHPDoc comments
- [ ] Write resource tests (8+ tests per resource)
- [ ] Test N+1 query prevention
- [ ] Run tests and fix issues
- [ ] Code review
- [ ] Merge resources only

**Week 2: Form Requests and Controller Integration**

**Day 6-7: Create All Form Requests**
- [ ] Create `chom/app/Http/Requests/V1/Sites/CreateSiteRequest.php`
- [ ] Create `chom/app/Http/Requests/V1/Sites/UpdateSiteRequest.php`
- [ ] Create `chom/app/Http/Requests/V1/Backups/CreateBackupRequest.php`
- [ ] Create `chom/app/Http/Requests/V1/Backups/RestoreBackupRequest.php`
- [ ] Create `chom/app/Http/Requests/V1/Team/InviteMemberRequest.php`
- [ ] Create `chom/app/Http/Requests/V1/Team/UpdateMemberRequest.php`
- [ ] Create `chom/app/Http/Requests/V1/Vps/CreateVpsRequest.php`
- [ ] Add custom validation messages
- [ ] Add field name attributes
- [ ] Write form request tests (8+ tests per request)
- [ ] Test authorization logic
- [ ] Run tests and fix issues
- [ ] Code review
- [ ] Merge form requests only

**Day 8: Update SiteController**
- [ ] Update SiteController to extend ApiController
- [ ] Replace manual response with `successResponse()`
- [ ] Replace manual pagination with `paginatedResponse()`
- [ ] Replace manual errors with `errorResponse()`
- [ ] Replace `getTenant()` with trait method
- [ ] Replace `formatSite()` with SiteResource
- [ ] Use CreateSiteRequest in store()
- [ ] Use UpdateSiteRequest in update()
- [ ] Remove duplicate code
- [ ] Update tests to match new structure
- [ ] Run full test suite
- [ ] Test API endpoints manually
- [ ] Code review
- [ ] Merge SiteController changes

**Day 9: Update BackupController and TeamController**
- [ ] Update BackupController to extend ApiController
- [ ] Replace responses with trait methods
- [ ] Replace `formatBackup()` with BackupResource
- [ ] Use CreateBackupRequest/RestoreBackupRequest
- [ ] Remove duplicate code
- [ ] Update TeamController to extend ApiController
- [ ] Replace `formatMember()` with TeamMemberResource
- [ ] Use InviteMemberRequest/UpdateMemberRequest
- [ ] Remove duplicate code
- [ ] Update all tests
- [ ] Run full test suite
- [ ] Test API endpoints manually
- [ ] Code review
- [ ] Merge both controllers

**Day 10: Update Remaining Controllers and Polish**
- [ ] Update VpsController to extend ApiController
- [ ] Use VpsResource for responses
- [ ] Use CreateVpsRequest
- [ ] Update AuthController to extend ApiController
- [ ] Update HealthController to extend ApiController
- [ ] Remove all old formatting methods
- [ ] Remove all duplicate `getTenant()` methods
- [ ] Update all tests
- [ ] Run full regression test suite
- [ ] Performance benchmarks
- [ ] Code review
- [ ] Final merge to main branch

### Files to Create (15 new files)

**Traits (2):**
1. `chom/app/Http/Traits/ApiResponse.php`
2. `chom/app/Http/Traits/HasTenantContext.php`

**Base Controller (1):**
3. `chom/app/Http/Controllers/Api/ApiController.php`

**API Resources (10):**
4. `chom/app/Http/Resources/V1/SiteResource.php`
5. `chom/app/Http/Resources/V1/SiteCollection.php`
6. `chom/app/Http/Resources/V1/BackupResource.php`
7. `chom/app/Http/Resources/V1/BackupCollection.php`
8. `chom/app/Http/Resources/V1/TeamMemberResource.php`
9. `chom/app/Http/Resources/V1/TeamMemberCollection.php`
10. `chom/app/Http/Resources/V1/VpsResource.php`
11. `chom/app/Http/Resources/V1/VpsCollection.php`
12. `chom/app/Http/Resources/V1/TeamInvitationResource.php`
13. `chom/app/Http/Resources/V1/TeamInvitationCollection.php`

**Form Requests (7):**
14. `chom/app/Http/Requests/V1/Sites/CreateSiteRequest.php`
15. `chom/app/Http/Requests/V1/Sites/UpdateSiteRequest.php`
16. `chom/app/Http/Requests/V1/Backups/CreateBackupRequest.php`
17. `chom/app/Http/Requests/V1/Backups/RestoreBackupRequest.php`
18. `chom/app/Http/Requests/V1/Team/InviteMemberRequest.php`
19. `chom/app/Http/Requests/V1/Team/UpdateMemberRequest.php`
20. `chom/app/Http/Requests/V1/Vps/CreateVpsRequest.php`

**Test Files (22+):**
21. `chom/tests/Unit/Traits/ApiResponseTest.php`
22. `chom/tests/Unit/Traits/HasTenantContextTest.php`
23. `chom/tests/Unit/Controllers/ApiControllerTest.php`
24. `chom/tests/Unit/Resources/SiteResourceTest.php`
25. `chom/tests/Unit/Resources/BackupResourceTest.php`
26. `chom/tests/Unit/Resources/TeamMemberResourceTest.php`
27. `chom/tests/Unit/Resources/VpsResourceTest.php`
28. `chom/tests/Unit/Resources/TeamInvitationResourceTest.php`
29. `chom/tests/Unit/Requests/CreateSiteRequestTest.php`
30. `chom/tests/Unit/Requests/UpdateSiteRequestTest.php`
31. `chom/tests/Unit/Requests/CreateBackupRequestTest.php`
32. `chom/tests/Unit/Requests/RestoreBackupRequestTest.php`
33. `chom/tests/Unit/Requests/InviteMemberRequestTest.php`
34. `chom/tests/Unit/Requests/UpdateMemberRequestTest.php`
35. `chom/tests/Unit/Requests/CreateVpsRequestTest.php`
36. `chom/tests/Feature/Api/SiteControllerTest.php` (updated)
37. `chom/tests/Feature/Api/BackupControllerTest.php` (updated)
38. `chom/tests/Feature/Api/TeamControllerTest.php` (updated)
39. `chom/tests/Feature/Api/VpsControllerTest.php` (updated)
40. `chom/tests/Integration/ApiResponseIntegrationTest.php` (new)
41. `chom/tests/Integration/TenantContextIntegrationTest.php` (new)
42. `chom/tests/Security/TenantIsolationSecurityTest.php` (new)

### Files to Modify (6 controllers)

**Controllers:**
1. `chom/app/Http/Controllers/Api/V1/SiteController.php` - Extend ApiController, use traits/resources
2. `chom/app/Http/Controllers/Api/V1/BackupController.php` - Extend ApiController, use traits/resources
3. `chom/app/Http/Controllers/Api/V1/TeamController.php` - Extend ApiController, use traits/resources
4. `chom/app/Http/Controllers/Api/V1/VpsController.php` - Extend ApiController, use traits/resources
5. `chom/app/Http/Controllers/Api/V1/AuthController.php` - Extend ApiController (minimal changes)
6. `chom/app/Http/Controllers/Api/V1/HealthController.php` - Extend ApiController (minimal changes)

**Expected Line Changes:**
- SiteController: 439 → ~350 lines (89 lines removed, 20%)
- BackupController: 333 → ~280 lines (53 lines removed, 16%)
- TeamController: 492 → ~400 lines (92 lines removed, 19%)
- VpsController: ~200 → ~160 lines (40 lines removed, 20%)
- Total: ~275 lines removed from controllers

### Backward Compatibility Checks

**API Contract Compatibility:**
- [ ] All existing API endpoints return same structure
- [ ] HTTP status codes unchanged
- [ ] Error response format consistent
- [ ] Pagination metadata identical
- [ ] Date format matches existing (ISO8601)
- [ ] Field names unchanged
- [ ] Nested relationships structure preserved

**Internal Compatibility:**
- [ ] Existing tests continue to pass
- [ ] Livewire components unaffected (Phase 2)
- [ ] Jobs can still access models
- [ ] Policies still work
- [ ] Middleware unaffected
- [ ] Database queries unchanged

**Breaking Change Detection:**
- [ ] Run API contract tests before/after
- [ ] Compare JSON responses byte-by-byte
- [ ] Check all HTTP status codes
- [ ] Verify all error codes preserved
- [ ] Test all edge cases
- [ ] Monitor Sentry for new errors

---

## Testing Plan

### Unit Testing

**Target Coverage:** 95%+ for new code

#### Trait Tests

**ApiResponse Trait (10 tests):**
```php
// tests/Unit/Traits/ApiResponseTest.php

class ApiResponseTest extends TestCase
{
    use ApiResponse;

    public function test_success_response_structure(): void
    {
        $response = $this->successResponse(['id' => 1]);
        $data = json_decode($response->getContent(), true);

        $this->assertTrue($data['success']);
        $this->assertEquals(['id' => 1], $data['data']);
        $this->assertEquals(200, $response->status());
    }

    public function test_success_response_with_message(): void
    {
        $response = $this->successResponse(['id' => 1], 'Created successfully');
        $data = json_decode($response->getContent(), true);

        $this->assertEquals('Created successfully', $data['message']);
    }

    public function test_success_response_with_custom_status(): void
    {
        $response = $this->successResponse(['id' => 1], null, 201);
        $this->assertEquals(201, $response->status());
    }

    public function test_paginated_response_structure(): void
    {
        $items = collect([['id' => 1], ['id' => 2]]);
        $paginator = new LengthAwarePaginator($items, 10, 2, 1);

        $response = $this->paginatedResponse($paginator);
        $data = json_decode($response->getContent(), true);

        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('data', $data);
        $this->assertArrayHasKey('meta', $data);
        $this->assertArrayHasKey('pagination', $data['meta']);
        $this->assertEquals(1, $data['meta']['pagination']['current_page']);
        $this->assertEquals(2, $data['meta']['pagination']['per_page']);
        $this->assertEquals(10, $data['meta']['pagination']['total']);
    }

    public function test_paginated_response_with_transformer(): void
    {
        $items = collect([['id' => 1, 'name' => 'Test']]);
        $paginator = new LengthAwarePaginator($items, 1, 1, 1);

        $response = $this->paginatedResponse($paginator, fn($item) => ['id' => $item['id']]);
        $data = json_decode($response->getContent(), true);

        $this->assertArrayNotHasKey('name', $data['data'][0]);
    }

    public function test_error_response_structure(): void
    {
        $response = $this->errorResponse('TEST_ERROR', 'Test error message');
        $data = json_decode($response->getContent(), true);

        $this->assertFalse($data['success']);
        $this->assertEquals('TEST_ERROR', $data['error']['code']);
        $this->assertEquals('Test error message', $data['error']['message']);
        $this->assertEquals(400, $response->status());
    }

    public function test_error_response_with_details(): void
    {
        $response = $this->errorResponse(
            'VALIDATION_ERROR',
            'Validation failed',
            ['field' => 'Required'],
            422
        );
        $data = json_decode($response->getContent(), true);

        $this->assertArrayHasKey('details', $data['error']);
        $this->assertEquals(['field' => 'Required'], $data['error']['details']);
        $this->assertEquals(422, $response->status());
    }

    public function test_validation_error_response(): void
    {
        $errors = ['email' => ['Email is required'], 'password' => ['Password is required']];
        $response = $this->validationErrorResponse($errors);
        $data = json_decode($response->getContent(), true);

        $this->assertFalse($data['success']);
        $this->assertEquals('VALIDATION_ERROR', $data['error']['code']);
        $this->assertEquals($errors, $data['error']['details']);
        $this->assertEquals(422, $response->status());
    }

    public function test_response_content_type_is_json(): void
    {
        $response = $this->successResponse(['test' => true]);
        $this->assertEquals('application/json', $response->headers->get('Content-Type'));
    }

    public function test_response_charset_is_utf8(): void
    {
        $response = $this->successResponse(['test' => true]);
        $this->assertStringContainsString('utf-8', $response->headers->get('Content-Type'));
    }
}
```

**HasTenantContext Trait (12 tests):**
```php
// tests/Unit/Traits/HasTenantContextTest.php

class HasTenantContextTest extends TestCase
{
    use RefreshDatabase, HasTenantContext;

    public function test_get_tenant_returns_active_tenant(): void
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['status' => 'active']);
        $user->tenants()->attach($tenant, ['role' => 'member']);
        $user->current_tenant_id = $tenant->id;
        $user->save();

        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $result = $this->getTenant($request);

        $this->assertEquals($tenant->id, $result->id);
    }

    public function test_get_tenant_aborts_when_tenant_inactive(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionCode(403);

        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['status' => 'suspended']);
        $user->current_tenant_id = $tenant->id;

        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->getTenant($request);
    }

    public function test_get_tenant_aborts_when_no_tenant(): void
    {
        $this->expectException(HttpException::class);

        $user = User::factory()->create();
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->getTenant($request);
    }

    public function test_get_organization_returns_organization(): void
    {
        $user = User::factory()->create();
        $organization = Organization::factory()->create();
        $user->organization_id = $organization->id;
        $user->save();

        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $result = $this->getOrganization($request);

        $this->assertEquals($organization->id, $result->id);
    }

    public function test_get_organization_aborts_when_no_organization(): void
    {
        $this->expectException(HttpException::class);

        $user = User::factory()->create(['organization_id' => null]);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->getOrganization($request);
    }

    public function test_require_role_allows_correct_role(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireRole($request, 'admin');
        $this->assertTrue(true); // No exception thrown
    }

    public function test_require_role_denies_incorrect_role(): void
    {
        $this->expectException(HttpException::class);

        $user = User::factory()->create(['role' => 'member']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireRole($request, 'admin');
    }

    public function test_require_role_accepts_multiple_roles(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireRole($request, ['admin', 'owner']);
        $this->assertTrue(true);
    }

    public function test_require_admin_allows_admin(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireAdmin($request);
        $this->assertTrue(true);
    }

    public function test_require_admin_allows_owner(): void
    {
        $user = User::factory()->create(['role' => 'owner']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireAdmin($request);
        $this->assertTrue(true);
    }

    public function test_require_admin_denies_member(): void
    {
        $this->expectException(HttpException::class);

        $user = User::factory()->create(['role' => 'member']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireAdmin($request);
    }

    public function test_require_owner_allows_only_owner(): void
    {
        $user = User::factory()->create(['role' => 'owner']);
        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->requireOwner($request);
        $this->assertTrue(true);
    }
}
```

#### Resource Tests (8 tests per resource × 5 = 40 tests)

**Example: SiteResource Test:**
```php
// tests/Unit/Resources/SiteResourceTest.php

class SiteResourceTest extends TestCase
{
    use RefreshDatabase;

    public function test_basic_transformation(): void
    {
        $site = Site::factory()->create([
            'domain' => 'test.com',
            'site_type' => 'wordpress',
            'status' => 'active',
        ]);

        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $this->assertEquals($site->id, $array['id']);
        $this->assertEquals('test.com', $array['domain']);
        $this->assertEquals('wordpress', $array['site_type']);
    }

    public function test_all_required_fields_present(): void
    {
        $site = Site::factory()->create();
        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $requiredFields = [
            'id', 'domain', 'url', 'site_type', 'php_version',
            'ssl_enabled', 'ssl_expires_at', 'status',
            'storage_used_mb', 'created_at', 'updated_at'
        ];

        foreach ($requiredFields as $field) {
            $this->assertArrayHasKey($field, $array);
        }
    }

    public function test_conditional_vps_relationship(): void
    {
        $site = Site::factory()->create();
        $site->load('vpsServer');

        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $this->assertArrayHasKey('vps', $array);
        $this->assertIsArray($array['vps']);
    }

    public function test_conditional_detailed_fields(): void
    {
        $site = Site::factory()->create();
        request()->merge(['detailed' => true]);

        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $this->assertArrayHasKey('db_name', $array);
        $this->assertArrayHasKey('document_root', $array);
    }

    public function test_collection_transformation(): void
    {
        $sites = Site::factory()->count(3)->create();

        $collection = SiteResource::collection($sites);
        $array = $collection->toArray(request());

        $this->assertCount(3, $array);
        $this->assertIsArray($array[0]);
    }

    public function test_no_n_plus_one_queries_in_collection(): void
    {
        Site::factory()->count(10)->create();

        DB::enableQueryLog();

        $sites = Site::with('vpsServer')->get();
        $collection = SiteResource::collection($sites);
        $array = $collection->toArray(request());

        $queryCount = count(DB::getQueryLog());

        // Should be 2 queries: 1 for sites, 1 for vps servers
        $this->assertLessThanOrEqual(2, $queryCount);
    }

    public function test_date_fields_formatted_correctly(): void
    {
        $site = Site::factory()->create();
        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $this->assertMatchesRegularExpression(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/',
            $array['created_at']
        );
    }

    public function test_no_sensitive_data_exposed(): void
    {
        $site = Site::factory()->create();
        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $sensitiveFields = ['db_password', 'ssh_key', 'api_key'];

        foreach ($sensitiveFields as $field) {
            $this->assertArrayNotHasKey($field, $array);
        }
    }
}
```

#### Form Request Tests (8 tests per request × 7 = 56 tests)

**Example: CreateSiteRequest Test:**
```php
// tests/Unit/Requests/CreateSiteRequestTest.php

class CreateSiteRequestTest extends TestCase
{
    use RefreshDatabase;

    public function test_valid_data_passes_validation(): void
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create();
        $user->current_tenant_id = $tenant->id;

        $request = CreateSiteRequest::create('/api/v1/sites', 'POST', [
            'domain' => 'test.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
            'ssl_enabled' => true,
        ]);
        $request->setUserResolver(fn() => $user);

        $validator = Validator::make($request->all(), $request->rules());

        $this->assertTrue($validator->passes());
    }

    public function test_missing_domain_fails(): void
    {
        $request = CreateSiteRequest::create('/api/v1/sites', 'POST', [
            'site_type' => 'wordpress',
        ]);

        $validator = Validator::make($request->all(), (new CreateSiteRequest)->rules());

        $this->assertTrue($validator->fails());
        $this->assertArrayHasKey('domain', $validator->errors()->toArray());
    }

    public function test_invalid_domain_format_fails(): void
    {
        $request = CreateSiteRequest::create('/api/v1/sites', 'POST', [
            'domain' => 'invalid domain with spaces',
        ]);

        $validator = Validator::make($request->all(), (new CreateSiteRequest)->rules());

        $this->assertTrue($validator->fails());
    }

    public function test_duplicate_domain_fails(): void
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->create(['domain' => 'test.com', 'tenant_id' => $tenant->id]);

        $user = User::factory()->create();
        $user->current_tenant_id = $tenant->id;

        $request = CreateSiteRequest::create('/api/v1/sites', 'POST', [
            'domain' => 'test.com',
        ]);
        $request->setUserResolver(fn() => $user);

        $validator = Validator::make($request->all(), $request->rules());

        $this->assertTrue($validator->fails());
        $this->assertArrayHasKey('domain', $validator->errors()->toArray());
    }

    public function test_authorization_checks_work(): void
    {
        $user = User::factory()->create(['role' => 'member']);
        $request = new CreateSiteRequest();
        $request->setUserResolver(fn() => $user);

        $this->assertTrue($request->authorize());
    }

    public function test_custom_messages_displayed(): void
    {
        $request = new CreateSiteRequest();
        $messages = $request->messages();

        $this->assertArrayHasKey('domain.required', $messages);
        $this->assertArrayHasKey('domain.regex', $messages);
    }

    public function test_data_sanitization_works(): void
    {
        $request = CreateSiteRequest::create('/api/v1/sites', 'POST', [
            'domain' => 'TEST.COM',
        ]);

        $request->prepareForValidation();

        $this->assertEquals('test.com', $request->input('domain'));
    }

    public function test_edge_cases_handled(): void
    {
        $longDomain = str_repeat('a', 250) . '.com';

        $request = CreateSiteRequest::create('/api/v1/sites', 'POST', [
            'domain' => $longDomain,
        ]);

        $validator = Validator::make($request->all(), (new CreateSiteRequest)->rules());

        $this->assertTrue($validator->fails());
    }
}
```

### Integration Testing

**Target Coverage:** 100% of API endpoints

#### API Response Integration Tests

```php
// tests/Integration/ApiResponseIntegrationTest.php

class ApiResponseIntegrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_all_api_endpoints_use_consistent_response_format(): void
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create();

        $endpoints = [
            ['GET', '/api/v1/sites'],
            ['GET', '/api/v1/backups'],
            ['GET', '/api/v1/team/members'],
            ['GET', '/api/v1/vps'],
        ];

        foreach ($endpoints as [$method, $uri]) {
            $response = $this->actingAs($user)->json($method, $uri);

            $data = $response->json();
            $this->assertArrayHasKey('success', $data);
            $this->assertArrayHasKey('data', $data);
        }
    }

    public function test_all_paginated_endpoints_have_consistent_meta(): void
    {
        $user = User::factory()->create();

        $paginatedEndpoints = [
            '/api/v1/sites',
            '/api/v1/backups',
            '/api/v1/team/members',
        ];

        foreach ($paginatedEndpoints as $uri) {
            $response = $this->actingAs($user)->getJson($uri);

            $data = $response->json();
            $this->assertArrayHasKey('meta', $data);
            $this->assertArrayHasKey('pagination', $data['meta']);
            $this->assertArrayHasKey('current_page', $data['meta']['pagination']);
            $this->assertArrayHasKey('per_page', $data['meta']['pagination']);
            $this->assertArrayHasKey('total', $data['meta']['pagination']);
            $this->assertArrayHasKey('total_pages', $data['meta']['pagination']);
        }
    }

    public function test_all_error_responses_have_consistent_structure(): void
    {
        $user = User::factory()->create();

        // Test 404 errors
        $response = $this->actingAs($user)->getJson('/api/v1/sites/invalid-id');

        $data = $response->json();
        $this->assertFalse($data['success']);
        $this->assertArrayHasKey('error', $data);
        $this->assertArrayHasKey('code', $data['error']);
        $this->assertArrayHasKey('message', $data['error']);
    }

    public function test_validation_errors_have_consistent_structure(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user)->postJson('/api/v1/sites', [
            'domain' => '', // Invalid
        ]);

        $data = $response->json();
        $this->assertFalse($data['success']);
        $this->assertEquals('VALIDATION_ERROR', $data['error']['code']);
        $this->assertArrayHasKey('details', $data['error']);
    }
}
```

#### Tenant Context Integration Tests

```php
// tests/Integration/TenantContextIntegrationTest.php

class TenantContextIntegrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_all_endpoints_properly_scope_to_tenant(): void
    {
        $tenant1 = Tenant::factory()->create();
        $tenant2 = Tenant::factory()->create();

        $user1 = User::factory()->create();
        $user1->current_tenant_id = $tenant1->id;

        Site::factory()->create(['tenant_id' => $tenant1->id]);
        Site::factory()->create(['tenant_id' => $tenant2->id]);

        $response = $this->actingAs($user1)->getJson('/api/v1/sites');

        $data = $response->json();
        $this->assertCount(1, $data['data']);
    }

    public function test_cross_tenant_access_prevented(): void
    {
        $tenant1 = Tenant::factory()->create();
        $tenant2 = Tenant::factory()->create();

        $user1 = User::factory()->create();
        $user1->current_tenant_id = $tenant1->id;

        $site2 = Site::factory()->create(['tenant_id' => $tenant2->id]);

        $response = $this->actingAs($user1)->getJson("/api/v1/sites/{$site2->id}");

        $response->assertStatus(404);
    }

    public function test_suspended_tenant_cannot_access_api(): void
    {
        $tenant = Tenant::factory()->create(['status' => 'suspended']);
        $user = User::factory()->create();
        $user->current_tenant_id = $tenant->id;

        $response = $this->actingAs($user)->getJson('/api/v1/sites');

        $response->assertStatus(403);
    }
}
```

### Feature Testing (E2E with Laravel Dusk)

```php
// tests/Browser/SiteManagementFlowTest.php

class SiteManagementFlowTest extends DuskTestCase
{
    use RefreshDatabase;

    public function test_complete_site_creation_flow(): void
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create();

        $this->browse(function (Browser $browser) use ($user) {
            $browser->loginAs($user)
                ->visit('/sites')
                ->click('@create-site-button')
                ->type('domain', 'test.com')
                ->select('site_type', 'wordpress')
                ->click('@submit')
                ->assertSee('Site is being created')
                ->waitForText('Site created successfully', 10)
                ->assertSee('test.com');
        });

        $this->assertDatabaseHas('sites', ['domain' => 'test.com']);
    }
}
```

### Regression Testing

**Pre-Phase 1 Baseline:**
- [ ] Run full test suite and record results
- [ ] Capture API response samples for all endpoints
- [ ] Document all HTTP status codes
- [ ] Record performance benchmarks (p50, p95, p99)
- [ ] Capture error response formats
- [ ] Save database query counts per endpoint

**Post-Phase 1 Validation:**
- [ ] All existing tests still pass
- [ ] API responses match pre-Phase 1 format
- [ ] HTTP status codes unchanged
- [ ] Performance within 5% of baseline
- [ ] No new errors in logs
- [ ] Query counts same or improved

**Regression Test Suite:**
```bash
#!/bin/bash
# chom/tests/regression/run-phase1-regression.sh

echo "Running Phase 1 Regression Tests..."

# 1. Unit tests
vendor/bin/phpunit --testsuite Unit

# 2. Feature tests
vendor/bin/phpunit --testsuite Feature

# 3. Integration tests
vendor/bin/phpunit --testsuite Integration

# 4. API contract tests
vendor/bin/phpunit tests/Api/ContractValidationTest.php

# 5. Security tests
vendor/bin/phpunit tests/Security/

# 6. Performance tests
vendor/bin/phpunit tests/Performance/ApiResponseTimeTest.php

echo "Regression tests complete!"
```

---

## Migration Strategy

### Gradual Rollout Approach

**Strategy:** Strangler Fig Pattern - Incrementally replace old code with new patterns

#### Phase A: Foundation (Days 1-5)
**Goal:** Create all new components without breaking existing code

**Steps:**
1. Create all traits, base classes, resources, form requests
2. Write comprehensive tests for new components
3. Merge to main branch (no functional changes yet)
4. Deploy to staging environment
5. Monitor for any issues

**Risk:** MINIMAL - No existing code modified

**Rollback:** Delete new files

#### Phase B: Gradual Adoption (Days 6-9)
**Goal:** Update controllers one at a time

**Steps:**
1. **Day 6:** Update SiteController only
   - Use feature flag: `PHASE1_SITE_CONTROLLER_ENABLED`
   - Deploy to staging
   - Run smoke tests
   - Enable for 10% of production traffic
   - Monitor metrics for 4 hours
   - If stable, enable for 100%

2. **Day 7:** Update BackupController and TeamController
   - Same gradual rollout process
   - Monitor error rates

3. **Day 8-9:** Update remaining controllers
   - VpsController, AuthController, HealthController
   - Full rollout after validation

**Risk:** LOW - Controllers updated independently

**Rollback:** Disable feature flag, revert single controller

#### Phase C: Cleanup (Day 10)
**Goal:** Remove old code and finalize

**Steps:**
1. Remove all old formatting methods
2. Remove duplicate `getTenant()` methods
3. Remove feature flags
4. Update documentation
5. Final regression tests
6. Production deployment

**Risk:** LOW - Only removing unused code

**Rollback:** Restore old methods from git history

### Feature Flag Implementation

```php
// config/phase1.php

return [
    'enabled' => env('PHASE1_ENABLED', false),
    'controllers' => [
        'site' => env('PHASE1_SITE_CONTROLLER', false),
        'backup' => env('PHASE1_BACKUP_CONTROLLER', false),
        'team' => env('PHASE1_TEAM_CONTROLLER', false),
        'vps' => env('PHASE1_VPS_CONTROLLER', false),
    ],
];
```

**Controller Example:**
```php
public function index(Request $request): JsonResponse
{
    if (config('phase1.controllers.site')) {
        // New implementation
        $tenant = $this->getTenant($request);
        $sites = $tenant->sites()->paginate($this->getPerPage($request));
        return $this->paginatedResponse($sites, fn($site) => new SiteResource($site));
    } else {
        // Old implementation (fallback)
        $tenant = $this->getTenantOld($request);
        $sites = $tenant->sites()->paginate($request->input('per_page', 20));
        return response()->json([
            'success' => true,
            'data' => $sites->items(),
            'meta' => ['pagination' => [...]],
        ]);
    }
}
```

### Backward Compatibility Guarantees

**API Contract:**
- ✅ All existing endpoints return identical JSON structure
- ✅ HTTP status codes unchanged
- ✅ Error codes preserved
- ✅ Date formats identical
- ✅ Pagination metadata structure unchanged

**Internal Contract:**
- ✅ Model relationships unchanged
- ✅ Database schema unchanged
- ✅ Job payloads unchanged
- ✅ Event payloads unchanged
- ✅ Policy logic unchanged

**Testing Contract:**
- ✅ All existing tests pass without modification
- ✅ Test assertions remain valid
- ✅ Mock expectations unchanged

### Rollback Plan

**Rollback Triggers:**
- Error rate increase >1%
- Response time increase >10%
- Any critical bug in production
- Failed validation tests
- Security vulnerability discovered

**Rollback Process (Per Phase):**

**Phase A Rollback:**
```bash
git revert <commit-hash>
composer install
php artisan config:clear
php artisan cache:clear
```

**Phase B Rollback:**
```bash
# Option 1: Feature flag
php artisan tinker
>>> config(['phase1.controllers.site' => false]);

# Option 2: Git revert
git revert <commit-hash>
composer install
php artisan config:clear
```

**Phase C Rollback:**
```bash
# Restore old methods from git
git checkout <previous-commit> -- app/Http/Controllers/Api/V1/SiteController.php
git commit -m "Rollback: Restore old SiteController"
composer install
php artisan config:clear
```

**Rollback Validation:**
- [ ] Run full test suite
- [ ] Verify API responses match expected format
- [ ] Check error logs for issues
- [ ] Monitor performance metrics
- [ ] Validate with sample API calls

---

## Quality Metrics

### Code Coverage Targets

**New Code:**
- Traits: 95%+
- Base Controller: 90%+
- API Resources: 85%+
- Form Requests: 90%+

**Existing Code:**
- Controllers: Maintain current coverage (75%+)
- Overall: Increase from 45% → 55%

**Coverage Commands:**
```bash
# Generate coverage report
vendor/bin/phpunit --coverage-html coverage/

# Check coverage thresholds
vendor/bin/phpunit --coverage-text --coverage-filter app/Http/Traits
vendor/bin/phpunit --coverage-text --coverage-filter app/Http/Resources
```

### Performance Benchmarks

**API Response Time (p95):**
- Baseline: 450ms
- Target: <400ms (improvement expected due to cleaner code)
- Acceptable: <500ms (10% regression allowed)
- Alert: >550ms (investigate immediately)

**Database Queries:**
- Baseline: 12 queries per request
- Target: <10 queries (eager loading improvements)
- Acceptable: 12 queries (no regression)
- Alert: >15 queries (N+1 problem)

**Memory Usage:**
- Baseline: 18MB per request
- Target: <15MB (reduced object creation)
- Acceptable: 20MB (minor regression allowed)
- Alert: >25MB (memory leak investigation)

**Throughput:**
- Baseline: 150 requests/second
- Target: >150 requests/second
- Acceptable: >135 requests/second (10% regression)
- Alert: <120 requests/second

**Benchmark Commands:**
```bash
# Apache Bench
ab -n 1000 -c 10 -H "Authorization: Bearer $TOKEN" https://chom.test/api/v1/sites

# K6 Load Test
k6 run tests/load/scenarios/phase1-baseline.js
```

### Response Time Validation

**Endpoint-Specific Targets:**

| Endpoint | Baseline (p95) | Target (p95) | Alert Threshold |
|----------|----------------|--------------|-----------------|
| GET /api/v1/sites | 380ms | <350ms | >450ms |
| POST /api/v1/sites | 520ms | <500ms | >600ms |
| GET /api/v1/backups | 290ms | <280ms | >350ms |
| POST /api/v1/backups | 450ms | <430ms | >550ms |
| GET /api/v1/team/members | 180ms | <170ms | >220ms |

**Monitoring:**
```bash
# Create performance baseline
php artisan test:performance --baseline

# Compare after Phase 1
php artisan test:performance --compare
```

### Code Quality Metrics

**PHPStan Analysis:**
```bash
# Run PHPStan at level 8
vendor/bin/phpstan analyse app/Http/Traits --level=8
vendor/bin/phpstan analyse app/Http/Resources --level=8
vendor/bin/phpstan analyse app/Http/Requests --level=8
```

**Expected Results:**
- Traits: 0 errors
- Resources: 0 errors
- Form Requests: 0 errors
- Controllers: <5 errors (existing issues)

**PHP-CS-Fixer:**
```bash
# Check code style
vendor/bin/php-cs-fixer fix app/Http/Traits --dry-run --diff
vendor/bin/php-cs-fixer fix app/Http/Resources --dry-run --diff
```

**Expected Results:**
- All new code follows PSR-12
- No style violations
- Consistent formatting

**Complexity Metrics:**
```bash
# PHPMetrics
vendor/bin/phpmetrics --report-html=metrics/ app/
```

**Targets:**
- Cyclomatic Complexity: <5 per method
- Maintainability Index: >85 (A grade)
- Lines of Code per Method: <20

**Duplication Detection:**
```bash
# PHP Copy/Paste Detector
vendor/bin/phpcpd app/Http/Traits
vendor/bin/phpcpd app/Http/Resources
```

**Target:** 0% duplication in new code

### Security Validation

**Security Checklist:**
- [ ] No SQL injection vulnerabilities
- [ ] No cross-tenant data leakage
- [ ] No sensitive data in API responses
- [ ] Authorization checks present in all form requests
- [ ] CSRF protection enabled
- [ ] XSS prevention (output escaping)
- [ ] Rate limiting applied

**Security Tests:**
```php
// tests/Security/Phase1SecurityTest.php

class Phase1SecurityTest extends TestCase
{
    public function test_api_resources_do_not_expose_sensitive_fields(): void
    {
        $site = Site::factory()->create();
        $resource = new SiteResource($site);
        $array = $resource->toArray(request());

        $sensitiveFields = ['db_password', 'ssh_key', 'api_key', 'webhook_secret'];

        foreach ($sensitiveFields as $field) {
            $this->assertArrayNotHasKey($field, $array);
        }
    }

    public function test_cross_tenant_data_access_prevented(): void
    {
        $tenant1 = Tenant::factory()->create();
        $tenant2 = Tenant::factory()->create();

        $user1 = User::factory()->create();
        $user1->current_tenant_id = $tenant1->id;

        $site2 = Site::factory()->create(['tenant_id' => $tenant2->id]);

        $response = $this->actingAs($user1)->getJson("/api/v1/sites/{$site2->id}");

        $response->assertStatus(404); // Should not find other tenant's site
    }

    public function test_suspended_tenant_blocked(): void
    {
        $tenant = Tenant::factory()->create(['status' => 'suspended']);
        $user = User::factory()->create();
        $user->current_tenant_id = $tenant->id;

        $response = $this->actingAs($user)->getJson('/api/v1/sites');

        $response->assertStatus(403);
    }
}
```

---

## Documentation

### Developer Guide

**Create:** `chom/docs/refactoring/PHASE1_DEVELOPER_GUIDE.md`

**Contents:**
1. **Introduction to Phase 1 Patterns**
   - ApiResponse trait usage
   - HasTenantContext trait usage
   - ApiController base class
   - API Resources
   - Form Requests

2. **How to Use ApiResponse Trait**
   ```php
   // Success response
   return $this->successResponse($data, 'Operation successful', 201);

   // Paginated response
   return $this->paginatedResponse($paginator);

   // Error response
   return $this->errorResponse('ERROR_CODE', 'Error message', $details, 400);
   ```

3. **How to Use HasTenantContext Trait**
   ```php
   // Get current tenant
   $tenant = $this->getTenant($request);

   // Require specific role
   $this->requireAdmin($request);
   ```

4. **How to Create API Resources**
   ```php
   class NewResource extends JsonResource
   {
       public function toArray($request): array
       {
           return [
               'id' => $this->id,
               'name' => $this->name,
               'related' => $this->whenLoaded('related'),
           ];
       }
   }
   ```

5. **How to Create Form Requests**
   ```php
   class CreateRequest extends FormRequest
   {
       public function authorize(): bool
       {
           return $this->user()->can('create', Model::class);
       }

       public function rules(): array
       {
           return [
               'field' => ['required', 'string', 'max:255'],
           ];
       }
   }
   ```

6. **Best Practices**
   - Always extend ApiController for API endpoints
   - Use resources for all API responses
   - Use form requests for all validation
   - Never query models directly in controllers
   - Always check tenant context

7. **Common Pitfalls**
   - Forgetting to load relationships (N+1 queries)
   - Not using `whenLoaded()` for optional relationships
   - Missing authorization in form requests
   - Not handling edge cases in validation

### API Documentation Updates

**Update:** `chom/docs/api/API-DOCUMENTATION.md`

**Changes:**
1. Document consistent response format:
   ```json
   {
       "success": true,
       "data": { ... },
       "message": "Optional message"
   }
   ```

2. Document pagination metadata:
   ```json
   {
       "success": true,
       "data": [...],
       "meta": {
           "pagination": {
               "current_page": 1,
               "per_page": 20,
               "total": 100,
               "total_pages": 5
           }
       }
   }
   ```

3. Document error response format:
   ```json
   {
       "success": false,
       "error": {
           "code": "ERROR_CODE",
           "message": "Error description",
           "details": { ... }
       }
   }
   ```

4. Document validation error format:
   ```json
   {
       "success": false,
       "error": {
           "code": "VALIDATION_ERROR",
           "message": "The given data was invalid.",
           "details": {
               "field": ["Error message"]
           }
       }
   }
   ```

### Changelog Entries

**Update:** `chom/CHANGELOG.md`

```markdown
## [Unreleased] - 2026-01-XX

### Added - Phase 1 Refactoring

#### New Traits
- Added `ApiResponse` trait for consistent JSON API responses
  - `successResponse()` method for successful operations
  - `paginatedResponse()` method for paginated results
  - `errorResponse()` method for error responses
  - `validationErrorResponse()` method for validation errors

- Added `HasTenantContext` trait for tenant/organization context
  - `getTenant()` method for current tenant retrieval
  - `getOrganization()` method for organization retrieval
  - `requireRole()` method for role-based authorization
  - `requireAdmin()` method for admin checks
  - `requireOwner()` method for owner-only actions

#### New Base Classes
- Added `ApiController` base class for all API controllers
  - Includes `ApiResponse` and `HasTenantContext` traits
  - Provides `getPerPage()` pagination helper
  - Provides `logError()` and `logInfo()` logging helpers

#### New API Resources
- `SiteResource` - Transforms Site models to JSON
- `BackupResource` - Transforms Backup models to JSON
- `TeamMemberResource` - Transforms User models to JSON
- `VpsResource` - Transforms VpsServer models to JSON
- `TeamInvitationResource` - Transforms TeamInvitation models to JSON

#### New Form Requests
- `CreateSiteRequest` - Validates site creation
- `UpdateSiteRequest` - Validates site updates
- `CreateBackupRequest` - Validates backup creation
- `RestoreBackupRequest` - Validates backup restoration
- `InviteMemberRequest` - Validates team invitations
- `UpdateMemberRequest` - Validates member role updates
- `CreateVpsRequest` - Validates VPS creation

### Changed
- Updated all API controllers to extend `ApiController`
- Replaced manual JSON responses with trait methods
- Replaced manual formatting with API Resources
- Replaced inline validation with Form Requests
- Removed 31+ duplicate `getTenant()` methods
- Removed 85+ duplicate response formatting blocks
- Removed 5 manual formatting methods

### Improved
- API response consistency across all endpoints
- Code duplication reduced by 25% (500+ lines)
- Test coverage increased from 45% to 55%
- Request validation centralized and reusable
- Authorization logic centralized

### Performance
- No performance regression detected
- Response times within 5% of baseline
- Query counts reduced by eager loading optimizations

### Breaking Changes
- None - All changes are backward compatible
```

### Migration Guide

**Create:** `chom/docs/refactoring/PHASE1_MIGRATION_GUIDE.md`

**Contents:**
1. **For Developers: Using New Patterns**
2. **For API Consumers: Response Format Changes** (None - backward compatible)
3. **For Testers: Updated Test Patterns**
4. **Common Migration Tasks**

---

## Rollback Plan

### Rollback Scenarios

#### Scenario 1: New Code Has Bugs
**Trigger:** Unit tests failing, critical bugs discovered

**Action:**
```bash
# Revert the problematic commit
git revert <commit-hash>
git push origin main

# Clear caches
php artisan config:clear
php artisan cache:clear
php artisan route:clear

# Re-run tests
vendor/bin/phpunit
```

**Recovery Time:** 5-10 minutes

#### Scenario 2: Performance Regression
**Trigger:** API response time >10% slower

**Action:**
```bash
# Disable feature flag
php artisan tinker
>>> config(['phase1.enabled' => false]);
>>> cache()->forever('phase1_disabled', true);

# Monitor for improvement
# If not improved, full rollback
git revert <commit-range>
```

**Recovery Time:** 2-5 minutes (feature flag), 10-15 minutes (full rollback)

#### Scenario 3: Production Errors
**Trigger:** Error rate >1%, Sentry alerts

**Action:**
```bash
# Immediate feature flag disable
php artisan tinker
>>> config(['phase1.enabled' => false]);

# Investigate root cause
tail -f storage/logs/laravel.log

# If critical, full rollback
git revert HEAD~5..HEAD
composer install
php artisan config:clear
```

**Recovery Time:** <5 minutes

### Rollback Validation Checklist

After rollback, validate:
- [ ] All API endpoints return expected responses
- [ ] No errors in logs
- [ ] Performance metrics back to baseline
- [ ] All tests passing
- [ ] No increase in error rate
- [ ] API consumers not affected

### Communication Plan

**During Rollback:**
1. Notify team via Slack #engineering channel
2. Post status update to #incidents channel
3. Update status page if customer-facing
4. Create post-mortem issue in GitHub

**After Rollback:**
1. Root cause analysis
2. Document lessons learned
3. Update rollback procedures
4. Plan re-deployment with fixes

---

## Timeline

### Week 1: Foundation (Days 1-5)

| Day | Tasks | Hours | Deliverables |
|-----|-------|-------|--------------|
| **Day 1** | ApiResponse Trait | 8h | Trait + 10 tests |
| **Day 2** | ApiResponse Integration | 4h | Merged to main |
| **Day 3** | HasTenantContext Trait | 8h | Trait + 12 tests |
| **Day 4** | Base ApiController | 6h | Base class + 9 tests |
| **Day 5** | API Resources (all 5) | 8h | 5 resources + 40 tests |

**Total:** 34 hours

### Week 2: Integration (Days 6-10)

| Day | Tasks | Hours | Deliverables |
|-----|-------|-------|--------------|
| **Day 6** | Form Requests (all 7) | 8h | 7 requests + 56 tests |
| **Day 7** | Form Requests Testing | 4h | All request tests passing |
| **Day 8** | Update SiteController | 6h | Refactored controller |
| **Day 9** | Update Backup/Team Controllers | 8h | 2 refactored controllers |
| **Day 10** | Update Remaining + Polish | 8h | All controllers updated |

**Total:** 34 hours

**Phase 1 Total:** 68 hours (8.5 days)

### Daily Checklist

**Every Day:**
- [ ] Morning: Review yesterday's work
- [ ] Run full test suite before starting
- [ ] Commit frequently (every feature)
- [ ] Write tests before implementation (TDD)
- [ ] Code review via Pull Request
- [ ] Update documentation
- [ ] End of day: Push to remote
- [ ] Run regression tests
- [ ] Update progress in project tracker

### Milestones

**Milestone 1: Foundation Complete (Day 5)**
- All traits, base classes, resources created
- All unit tests passing
- Merged to main branch
- 15 new files created

**Milestone 2: Form Requests Complete (Day 7)**
- All form requests created
- All validation tests passing
- 7 new files created

**Milestone 3: Controller Integration Complete (Day 10)**
- All controllers refactored
- All integration tests passing
- 500+ lines removed
- Phase 1 complete

### Risk Mitigation Schedule

**Daily Risks:**
- [ ] Merge conflicts: Coordinate with team, frequent pulls
- [ ] Test failures: Fix immediately before moving on
- [ ] Performance issues: Run benchmarks after each controller

**Weekly Risks:**
- [ ] Scope creep: Stick to Phase 1 scope only
- [ ] Breaking changes: Strict backward compatibility checks
- [ ] Team velocity: Adjust timeline if needed

---

## Appendix A: Code Examples

### ApiResponse Trait - Full Implementation

```php
<?php

namespace App\Http\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Pagination\LengthAwarePaginator;

trait ApiResponse
{
    /**
     * Return a success response with data.
     *
     * @param  mixed  $data
     * @param  string|null  $message
     * @param  int  $status
     * @return JsonResponse
     */
    protected function successResponse($data, ?string $message = null, int $status = 200): JsonResponse
    {
        $response = [
            'success' => true,
            'data' => $data,
        ];

        if ($message !== null) {
            $response['message'] = $message;
        }

        return response()->json($response, $status);
    }

    /**
     * Return a paginated success response.
     *
     * @param  LengthAwarePaginator  $paginator
     * @param  callable|null  $transformer
     * @return JsonResponse
     */
    protected function paginatedResponse(
        LengthAwarePaginator $paginator,
        ?callable $transformer = null
    ): JsonResponse {
        $data = $transformer !== null
            ? collect($paginator->items())->map($transformer)->all()
            : $paginator->items();

        return response()->json([
            'success' => true,
            'data' => $data,
            'meta' => [
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                    'total_pages' => $paginator->lastPage(),
                ],
            ],
        ]);
    }

    /**
     * Return an error response.
     *
     * @param  string  $code
     * @param  string  $message
     * @param  array  $details
     * @param  int  $status
     * @return JsonResponse
     */
    protected function errorResponse(
        string $code,
        string $message,
        array $details = [],
        int $status = 400
    ): JsonResponse {
        $response = [
            'success' => false,
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
        ];

        if (!empty($details)) {
            $response['error']['details'] = $details;
        }

        return response()->json($response, $status);
    }

    /**
     * Return a validation error response.
     *
     * @param  array  $errors
     * @return JsonResponse
     */
    protected function validationErrorResponse(array $errors): JsonResponse
    {
        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'VALIDATION_ERROR',
                'message' => 'The given data was invalid.',
                'details' => $errors,
            ],
        ], 422);
    }
}
```

### HasTenantContext Trait - Full Implementation

```php
<?php

namespace App\Http\Traits;

use App\Models\Tenant;
use App\Models\Organization;
use Illuminate\Http\Request;

trait HasTenantContext
{
    /**
     * Get the current tenant from the authenticated user.
     *
     * @param  Request  $request
     * @return Tenant
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function getTenant(Request $request): Tenant
    {
        $tenant = $request->user()->currentTenant();

        if (!$tenant || !$tenant->isActive()) {
            abort(403, 'No active tenant found.');
        }

        return $tenant;
    }

    /**
     * Get the current organization from the authenticated user.
     *
     * @param  Request  $request
     * @return Organization
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function getOrganization(Request $request): Organization
    {
        $organization = $request->user()->organization;

        if (!$organization) {
            abort(403, 'No organization found.');
        }

        return $organization;
    }

    /**
     * Ensure the current user has a specific role.
     *
     * @param  Request  $request
     * @param  string|array  $roles
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function requireRole(Request $request, string|array $roles): void
    {
        $user = $request->user();
        $roles = (array) $roles;

        if (!in_array($user->role, $roles, true)) {
            abort(403, 'You do not have permission to perform this action.');
        }
    }

    /**
     * Ensure the current user is an admin or owner.
     *
     * @param  Request  $request
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function requireAdmin(Request $request): void
    {
        if (!$request->user()->isAdmin()) {
            abort(403, 'You do not have permission to perform this action.');
        }
    }

    /**
     * Ensure the current user is the owner.
     *
     * @param  Request  $request
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function requireOwner(Request $request): void
    {
        if (!$request->user()->isOwner()) {
            abort(403, 'Only the organization owner can perform this action.');
        }
    }
}
```

---

## Appendix B: Testing Templates

### Unit Test Template

```php
<?php

namespace Tests\Unit\Traits;

use Tests\TestCase;
use App\Http\Traits\ApiResponse;

class ExampleTraitTest extends TestCase
{
    use ApiResponse;

    public function test_example(): void
    {
        // Arrange
        $data = ['id' => 1, 'name' => 'Test'];

        // Act
        $response = $this->successResponse($data);
        $content = json_decode($response->getContent(), true);

        // Assert
        $this->assertTrue($content['success']);
        $this->assertEquals($data, $content['data']);
        $this->assertEquals(200, $response->status());
    }
}
```

### Integration Test Template

```php
<?php

namespace Tests\Integration;

use Tests\TestCase;
use Illuminate\Foundation\Testing\RefreshDatabase;
use App\Models\User;
use App\Models\Tenant;

class ExampleIntegrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_example(): void
    {
        // Arrange
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create();

        // Act
        $response = $this->actingAs($user)->getJson('/api/v1/endpoint');

        // Assert
        $response->assertStatus(200);
        $response->assertJsonStructure(['success', 'data']);
    }
}
```

---

## Conclusion

This comprehensive Phase 1 Integration and Testing Plan provides a detailed roadmap for implementing the Quick Wins refactoring with minimal risk and maximum impact.

**Key Takeaways:**
1. **Low Risk:** Additive changes only, backward compatible
2. **High Impact:** 500+ lines reduced, consistent patterns established
3. **Well-Tested:** 100+ new tests, 95%+ coverage
4. **Gradual Migration:** Strangler Fig pattern with feature flags
5. **Clear Documentation:** Developer guides, API docs, changelog

**Success Criteria:**
- All 15 new files created
- All 6 controllers refactored
- All 100+ tests passing
- No performance regression
- No breaking changes
- Foundation ready for Phase 2

**Next Steps:**
1. Review and approve this plan
2. Create project tracker (Jira/Linear)
3. Assign developers
4. Begin Day 1 implementation
5. Daily progress reviews
6. Weekly milestone checks

---

**Document Owner:** Engineering Team
**Review Date:** January 3, 2026
**Next Review:** January 17, 2026 (after Week 1)
**Status:** READY FOR IMPLEMENTATION
