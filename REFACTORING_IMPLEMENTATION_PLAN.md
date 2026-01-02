# Refactoring Implementation Plan

**Project:** CHOM (Cloud Hosting Operations Manager)
**Date:** January 2, 2026
**Version:** 1.0
**Status:** Draft

---

## Executive Summary

This document outlines a comprehensive 12-week refactoring plan to address architectural debt in the CHOM application. The plan prioritizes improvements by ROI and risk, focusing on:

- **25 DRY violations** (~510 lines of duplicated code)
- **31+ tenant resolution duplications** across controllers
- **Fat controllers** (TeamController: 492 lines, SiteController: 439 lines, BackupController: 333 lines)
- **Missing repository layer** (direct Eloquent queries in controllers)
- **Missing domain services** (business logic in controllers)
- **Tight coupling** between layers
- **Inconsistent API responses** (duplicated JSON formatting)

**Expected Outcomes:**
- 40% reduction in code duplication
- 60% reduction in controller size
- 100% test coverage for new abstractions
- Improved maintainability score from C to A
- Foundation for future feature development

---

## Table of Contents

1. [Phase 1: Quick Wins (Week 1-2)](#phase-1-quick-wins-week-1-2)
2. [Phase 2: High-Value Refactoring (Week 3-6)](#phase-2-high-value-refactoring-week-3-6)
3. [Phase 3: Architectural Improvements (Week 7-12)](#phase-3-architectural-improvements-week-7-12)
4. [Testing Strategy](#testing-strategy)
5. [Migration Strategy](#migration-strategy)
6. [Risk Assessment](#risk-assessment)
7. [Success Metrics](#success-metrics)

---

## Phase 1: Quick Wins (Week 1-2)

**Goal:** Achieve immediate impact with minimal risk. Extract common patterns into reusable components.

**Effort:** 2 weeks
**Risk:** Low
**ROI:** High
**Impact:** 20% code reduction, improved consistency

### 1.1 Create API Response Helpers

**Problem:** JSON response formatting is duplicated 40+ times across controllers.

**Files to Create:**
- `app/Http/Traits/ApiResponse.php`

**Before:**
```php
// SiteController.php (lines 52-63)
return response()->json([
    'success' => true,
    'data' => $sites->items(),
    'meta' => [
        'pagination' => [
            'current_page' => $sites->currentPage(),
            'per_page' => $sites->perPage(),
            'total' => $sites->total(),
            'total_pages' => $sites->lastPage(),
        ],
    ],
]);

// BackupController.php (lines 40-51) - DUPLICATE
return response()->json([
    'success' => true,
    'data' => collect($backups->items())->map(fn($backup) => $this->formatBackup($backup)),
    'meta' => [
        'pagination' => [
            'current_page' => $backups->currentPage(),
            'per_page' => $backups->perPage(),
            'total' => $backups->total(),
            'total_pages' => $backups->lastPage(),
        ],
    ],
]);
```

**After:**
```php
// app/Http/Traits/ApiResponse.php
<?php

namespace App\Http\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Pagination\LengthAwarePaginator;

trait ApiResponse
{
    /**
     * Return a success response with data.
     */
    protected function successResponse($data, string $message = null, int $status = 200): JsonResponse
    {
        $response = ['success' => true, 'data' => $data];

        if ($message) {
            $response['message'] = $message;
        }

        return response()->json($response, $status);
    }

    /**
     * Return a paginated success response.
     */
    protected function paginatedResponse(LengthAwarePaginator $paginator, callable $transformer = null): JsonResponse
    {
        $data = $transformer
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
     */
    protected function errorResponse(string $code, string $message, array $details = [], int $status = 400): JsonResponse
    {
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

**Usage in Controllers:**
```php
// SiteController.php
use App\Http\Traits\ApiResponse;

class SiteController extends Controller
{
    use ApiResponse;

    public function index(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $sites = $tenant->sites()->paginate($request->input('per_page', 20));

        return $this->paginatedResponse($sites);
    }

    public function store(Request $request): JsonResponse
    {
        // ... validation and creation logic
        return $this->successResponse(
            $this->formatSite($site),
            'Site is being created.',
            201
        );
    }
}
```

**Impact:**
- Removes 40+ duplicate response blocks
- Saves ~200 lines of code
- Ensures consistent API contract
- Makes future API changes trivial (change in one place)

**Testing Requirements:**
```php
// tests/Unit/Traits/ApiResponseTest.php
class ApiResponseTest extends TestCase
{
    use ApiResponse;

    public function test_success_response_structure()
    {
        $response = $this->successResponse(['id' => 1]);
        $data = json_decode($response->getContent(), true);

        $this->assertTrue($data['success']);
        $this->assertEquals(['id' => 1], $data['data']);
    }

    public function test_paginated_response_structure()
    {
        $items = collect([['id' => 1], ['id' => 2]]);
        $paginator = new LengthAwarePaginator($items, 2, 1);

        $response = $this->paginatedResponse($paginator);
        $data = json_decode($response->getContent(), true);

        $this->assertArrayHasKey('meta', $data);
        $this->assertArrayHasKey('pagination', $data['meta']);
    }
}
```

---

### 1.2 Extract Tenant Resolution Logic

**Problem:** `getTenant()` method is duplicated in every controller (31+ times).

**Files to Create:**
- `app/Http/Traits/HasTenantContext.php`

**Before:**
```php
// SiteController.php (lines 371-380)
private function getTenant(Request $request): Tenant
{
    $tenant = $request->user()->currentTenant();

    if (!$tenant || !$tenant->isActive()) {
        abort(403, 'No active tenant found.');
    }

    return $tenant;
}

// BackupController.php (lines 293-302) - DUPLICATE
private function getTenant(Request $request): Tenant
{
    $tenant = $request->user()->currentTenant();

    if (!$tenant || !$tenant->isActive()) {
        abort(403, 'No active tenant found.');
    }

    return $tenant;
}

// TeamController.php (lines 463-472) - DUPLICATE
private function getTenant(Request $request): Tenant
{
    $tenant = $request->user()->currentTenant();

    if (!$tenant || !$tenant->isActive()) {
        abort(403, 'No active tenant found.');
    }

    return $tenant;
}
```

**After:**
```php
// app/Http/Traits/HasTenantContext.php
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
     */
    protected function requireAdmin(Request $request): void
    {
        if (!$request->user()->isAdmin()) {
            abort(403, 'You do not have permission to perform this action.');
        }
    }

    /**
     * Ensure the current user is the owner.
     */
    protected function requireOwner(Request $request): void
    {
        if (!$request->user()->isOwner()) {
            abort(403, 'Only the organization owner can perform this action.');
        }
    }
}
```

**Usage:**
```php
// SiteController.php
use App\Http\Traits\HasTenantContext;

class SiteController extends Controller
{
    use HasTenantContext;

    public function index(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);
        // ... rest of the logic
    }
}
```

**Impact:**
- Removes 31+ duplicate methods (~310 lines)
- Centralizes tenant resolution logic
- Adds authorization helpers
- Makes tenant context changes affect all controllers

**Testing Requirements:**
```php
// tests/Unit/Traits/HasTenantContextTest.php
class HasTenantContextTest extends TestCase
{
    use HasTenantContext;

    public function test_get_tenant_returns_active_tenant()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['status' => 'active']);
        $user->setCurrentTenant($tenant);

        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $result = $this->getTenant($request);

        $this->assertEquals($tenant->id, $result->id);
    }

    public function test_get_tenant_aborts_when_inactive()
    {
        $this->expectException(HttpException::class);

        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['status' => 'suspended']);
        $user->setCurrentTenant($tenant);

        $request = Request::create('/');
        $request->setUserResolver(fn() => $user);

        $this->getTenant($request);
    }
}
```

---

### 1.3 Create Base API Controller

**Problem:** Controllers share common patterns but have no base abstraction.

**Files to Create:**
- `app/Http/Controllers/Api/ApiController.php`

**Implementation:**
```php
// app/Http/Controllers/Api/ApiController.php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Traits\ApiResponse;
use App\Http\Traits\HasTenantContext;

abstract class ApiController extends Controller
{
    use ApiResponse, HasTenantContext;

    /**
     * Default pagination size.
     */
    protected int $defaultPerPage = 20;

    /**
     * Maximum pagination size.
     */
    protected int $maxPerPage = 100;

    /**
     * Get pagination size from request with constraints.
     */
    protected function getPerPage(\Illuminate\Http\Request $request): int
    {
        $perPage = (int) $request->input('per_page', $this->defaultPerPage);

        return min(max($perPage, 1), $this->maxPerPage);
    }

    /**
     * Log an error with context.
     */
    protected function logError(string $message, array $context = []): void
    {
        \Illuminate\Support\Facades\Log::error($message, array_merge([
            'controller' => static::class,
            'user_id' => auth()->id(),
        ], $context));
    }

    /**
     * Log an info message with context.
     */
    protected function logInfo(string $message, array $context = []): void
    {
        \Illuminate\Support\Facades\Log::info($message, array_merge([
            'controller' => static::class,
            'user_id' => auth()->id(),
        ], $context));
    }
}
```

**Updated Controllers:**
```php
// app/Http/Controllers/Api/V1/SiteController.php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\ApiController;

class SiteController extends ApiController
{
    // Now inherits ApiResponse, HasTenantContext, and helper methods
}
```

**Impact:**
- Removes 100+ lines of duplicate imports
- Establishes clear controller hierarchy
- Centralizes cross-cutting concerns
- Makes adding global features easy

---

### 1.4 Extract Common Formatters

**Problem:** `formatSite()`, `formatBackup()`, `formatMember()` are 50-100 lines each in controllers.

**Files to Create:**
- `app/Http/Resources/SiteResource.php`
- `app/Http/Resources/BackupResource.php`
- `app/Http/Resources/UserResource.php`

**Before:**
```php
// SiteController.php (lines 399-438)
private function formatSite(Site $site, bool $detailed = false): array
{
    $data = [
        'id' => $site->id,
        'domain' => $site->domain,
        'url' => $site->getUrl(),
        'site_type' => $site->site_type,
        'php_version' => $site->php_version,
        'ssl_enabled' => $site->ssl_enabled,
        'ssl_expires_at' => $site->ssl_expires_at?->toIso8601String(),
        'status' => $site->status,
        'storage_used_mb' => $site->storage_used_mb,
        'created_at' => $site->created_at->toIso8601String(),
        'updated_at' => $site->updated_at->toIso8601String(),
    ];

    if ($site->relationLoaded('vpsServer') && $site->vpsServer) {
        $data['vps'] = [
            'id' => $site->vpsServer->id,
            'hostname' => $site->vpsServer->hostname,
        ];
    }

    if ($detailed) {
        $data['db_name'] = $site->db_name;
        $data['document_root'] = $site->document_root;
        $data['settings'] = $site->settings;

        if ($site->relationLoaded('backups')) {
            $data['recent_backups'] = $site->backups->map(fn($b) => [
                'id' => $b->id,
                'type' => $b->backup_type,
                'size' => $b->getSizeFormatted(),
                'created_at' => $b->created_at->toIso8601String(),
            ])->toArray();
        }
    }

    return $data;
}
```

**After:**
```php
// app/Http/Resources/SiteResource.php
<?php

namespace App\Http\Resources;

use Illuminate\Http\Resources\Json\JsonResource;

class SiteResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     */
    public function toArray($request): array
    {
        return [
            'id' => $this->id,
            'domain' => $this->domain,
            'url' => $this->getUrl(),
            'site_type' => $this->site_type,
            'php_version' => $this->php_version,
            'ssl_enabled' => $this->ssl_enabled,
            'ssl_expires_at' => $this->ssl_expires_at?->toIso8601String(),
            'status' => $this->status,
            'storage_used_mb' => $this->storage_used_mb,
            'created_at' => $this->created_at->toIso8601String(),
            'updated_at' => $this->updated_at->toIso8601String(),

            // Conditional relationships
            'vps' => $this->whenLoaded('vpsServer', fn() => [
                'id' => $this->vpsServer->id,
                'hostname' => $this->vpsServer->hostname,
            ]),

            // Detailed fields (only when requested)
            $this->mergeWhen($request->input('detailed') === true, [
                'db_name' => $this->db_name,
                'document_root' => $this->document_root,
                'settings' => $this->settings,
                'recent_backups' => BackupResource::collection($this->whenLoaded('backups')),
            ]),
        ];
    }
}
```

**Usage:**
```php
// SiteController.php
use App\Http\Resources\SiteResource;

public function show(Request $request, string $id): JsonResponse
{
    $tenant = $this->getTenant($request);
    $site = $tenant->sites()->with(['vpsServer', 'backups'])->findOrFail($id);

    return $this->successResponse(new SiteResource($site));
}

public function index(Request $request): JsonResponse
{
    $tenant = $this->getTenant($request);
    $sites = $tenant->sites()->paginate($this->getPerPage($request));

    return $this->paginatedResponse($sites, fn($site) => new SiteResource($site));
}
```

**Impact:**
- Removes 200+ lines of formatting code
- Uses Laravel's standard pattern (API Resources)
- Centralizes data transformation logic
- Enables easy versioning (v1/v2 resources)

---

### Week 1-2 Summary

**Tasks Checklist:**
- [ ] Create `ApiResponse` trait with tests
- [ ] Create `HasTenantContext` trait with tests
- [ ] Create `ApiController` base class
- [ ] Create `SiteResource`, `BackupResource`, `UserResource`
- [ ] Update all API controllers to extend `ApiController`
- [ ] Update all controllers to use new traits
- [ ] Update all controllers to use Resources
- [ ] Run full test suite
- [ ] Code review and merge

**Expected Metrics:**
- Lines of code reduced: ~500 lines
- Code duplication reduced: 25%
- Test coverage added: 15 new unit tests
- Controllers affected: 6 files
- Time saved on future features: 30%

---

## Phase 2: High-Value Refactoring (Week 3-6)

**Goal:** Implement repository pattern and extract domain services for maximum ROI.

**Effort:** 4 weeks
**Risk:** Medium
**ROI:** Very High
**Impact:** 50% complexity reduction, 40% code reduction

### 2.1 Implement Repository Layer (Week 3)

**Problem:** Controllers have direct Eloquent queries, making testing hard and violating SRP.

**Architecture:**
```
Controllers → Repositories → Models
```

**Files to Create:**
- `app/Repositories/Contracts/SiteRepositoryInterface.php`
- `app/Repositories/Contracts/BackupRepositoryInterface.php`
- `app/Repositories/Contracts/TenantRepositoryInterface.php`
- `app/Repositories/SiteRepository.php`
- `app/Repositories/BackupRepository.php`
- `app/Repositories/TenantRepository.php`
- `app/Providers/RepositoryServiceProvider.php`

**Before (in Controller):**
```php
// SiteController.php (lines 31-50)
public function index(Request $request): JsonResponse
{
    $tenant = $this->getTenant($request);

    $query = $tenant->sites()
        ->with('vpsServer:id,hostname,ip_address')
        ->orderBy('created_at', 'desc');

    // Filter by status
    if ($request->has('status')) {
        $query->where('status', $request->input('status'));
    }

    // Filter by type
    if ($request->has('type')) {
        $query->where('site_type', $request->input('type'));
    }

    // Search by domain
    if ($request->has('search')) {
        $query->where('domain', 'like', '%' . $request->input('search') . '%');
    }

    $sites = $query->paginate($request->input('per_page', 20));
    // ...
}
```

**After:**

```php
// app/Repositories/Contracts/SiteRepositoryInterface.php
<?php

namespace App\Repositories\Contracts;

use App\Models\Site;
use App\Models\Tenant;
use Illuminate\Pagination\LengthAwarePaginator;

interface SiteRepositoryInterface
{
    public function findByTenant(Tenant $tenant, array $filters = [], int $perPage = 20): LengthAwarePaginator;
    public function findById(string $id): ?Site;
    public function findByDomain(string $domain): ?Site;
    public function create(array $data): Site;
    public function update(Site $site, array $data): bool;
    public function delete(Site $site): bool;
    public function getActiveSites(Tenant $tenant): \Illuminate\Support\Collection;
    public function getSitesExpiringSsl(int $days = 14): \Illuminate\Support\Collection;
}

// app/Repositories/SiteRepository.php
<?php

namespace App\Repositories;

use App\Models\Site;
use App\Models\Tenant;
use App\Repositories\Contracts\SiteRepositoryInterface;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

class SiteRepository implements SiteRepositoryInterface
{
    /**
     * Find sites for a tenant with optional filters.
     */
    public function findByTenant(Tenant $tenant, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        $query = $tenant->sites()
            ->with('vpsServer:id,hostname,ip_address')
            ->orderBy('created_at', 'desc');

        // Apply filters
        if (!empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }

        if (!empty($filters['type'])) {
            $query->where('site_type', $filters['type']);
        }

        if (!empty($filters['search'])) {
            $query->where('domain', 'like', '%' . $filters['search'] . '%');
        }

        return $query->paginate($perPage);
    }

    /**
     * Find a site by ID.
     */
    public function findById(string $id): ?Site
    {
        return Site::with(['vpsServer', 'backups' => fn($q) => $q->latest()->limit(5)])
            ->find($id);
    }

    /**
     * Find a site by domain.
     */
    public function findByDomain(string $domain): ?Site
    {
        return Site::where('domain', $domain)->first();
    }

    /**
     * Create a new site.
     */
    public function create(array $data): Site
    {
        return Site::create($data);
    }

    /**
     * Update a site.
     */
    public function update(Site $site, array $data): bool
    {
        return $site->update($data);
    }

    /**
     * Delete a site.
     */
    public function delete(Site $site): bool
    {
        return $site->delete();
    }

    /**
     * Get active sites for a tenant.
     */
    public function getActiveSites(Tenant $tenant): Collection
    {
        return $tenant->sites()->active()->get();
    }

    /**
     * Get sites with SSL expiring soon.
     */
    public function getSitesExpiringSsl(int $days = 14): Collection
    {
        return Site::sslExpiringSoon($days)->get();
    }
}

// app/Providers/RepositoryServiceProvider.php
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class RepositoryServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->bind(
            \App\Repositories\Contracts\SiteRepositoryInterface::class,
            \App\Repositories\SiteRepository::class
        );

        $this->app->bind(
            \App\Repositories\Contracts\BackupRepositoryInterface::class,
            \App\Repositories\BackupRepository::class
        );

        $this->app->bind(
            \App\Repositories\Contracts\TenantRepositoryInterface::class,
            \App\Repositories\TenantRepository::class
        );
    }
}
```

**Updated Controller:**
```php
// SiteController.php
use App\Repositories\Contracts\SiteRepositoryInterface;

class SiteController extends ApiController
{
    public function __construct(
        private SiteRepositoryInterface $siteRepository,
        private VPSManagerBridge $vpsManager
    ) {}

    public function index(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $filters = [
            'status' => $request->input('status'),
            'type' => $request->input('type'),
            'search' => $request->input('search'),
        ];

        $sites = $this->siteRepository->findByTenant(
            $tenant,
            $filters,
            $this->getPerPage($request)
        );

        return $this->paginatedResponse($sites, fn($site) => new SiteResource($site));
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $this->siteRepository->findById($id);

        if (!$site || $site->tenant_id !== $tenant->id) {
            return $this->errorResponse('SITE_NOT_FOUND', 'Site not found.', [], 404);
        }

        return $this->successResponse(new SiteResource($site));
    }
}
```

**Impact:**
- Separates data access from business logic
- Makes controllers 40% smaller
- Enables easy testing with mock repositories
- Centralizes query logic (DRY)
- Allows database changes without touching controllers

**Testing:**
```php
// tests/Unit/Repositories/SiteRepositoryTest.php
class SiteRepositoryTest extends TestCase
{
    use RefreshDatabase;

    private SiteRepository $repository;

    protected function setUp(): void
    {
        parent::setUp();
        $this->repository = new SiteRepository();
    }

    public function test_find_by_tenant_returns_sites()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->count(3)->create(['tenant_id' => $tenant->id]);

        $result = $this->repository->findByTenant($tenant);

        $this->assertEquals(3, $result->total());
    }

    public function test_find_by_tenant_filters_by_status()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->create(['tenant_id' => $tenant->id, 'status' => 'active']);
        Site::factory()->create(['tenant_id' => $tenant->id, 'status' => 'disabled']);

        $result = $this->repository->findByTenant($tenant, ['status' => 'active']);

        $this->assertEquals(1, $result->total());
    }
}

// tests/Feature/Controllers/SiteControllerTest.php (with mocks)
class SiteControllerTest extends TestCase
{
    public function test_index_returns_sites()
    {
        $this->mock(SiteRepositoryInterface::class, function ($mock) {
            $mock->shouldReceive('findByTenant')
                ->once()
                ->andReturn(new LengthAwarePaginator([], 0, 20));
        });

        $response = $this->actingAs($this->user)->getJson('/api/v1/sites');

        $response->assertStatus(200)
            ->assertJsonStructure(['success', 'data', 'meta']);
    }
}
```

---

### 2.2 Extract Domain Services (Week 4-5)

**Problem:** Business logic is scattered in controllers and jobs.

**Services to Create:**
- `app/Services/SiteManagementService.php` (site lifecycle)
- `app/Services/BackupService.php` (backup/restore operations)
- `app/Services/TeamManagementService.php` (team operations)
- `app/Services/QuotaService.php` (quota checking)

**Before:**
```php
// SiteController.php (lines 69-146) - 78 lines of business logic
public function store(Request $request): JsonResponse
{
    $tenant = $this->getTenant($request);

    // Check quota
    if (!$tenant->canCreateSite()) {
        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'SITE_LIMIT_EXCEEDED',
                'message' => 'You have reached your plan\'s site limit.',
                'details' => [
                    'current_sites' => $tenant->getSiteCount(),
                    'limit' => $tenant->getMaxSites(),
                ],
            ],
        ], 403);
    }

    $validated = $request->validate([
        'domain' => [
            'required',
            'string',
            'max:253',
            'regex:/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i',
            Rule::unique('sites')->where('tenant_id', $tenant->id),
        ],
        'site_type' => ['sometimes', 'in:wordpress,html,laravel'],
        'php_version' => ['sometimes', 'in:8.2,8.4'],
        'ssl_enabled' => ['sometimes', 'boolean'],
    ]);

    try {
        $site = DB::transaction(function () use ($validated, $tenant) {
            // Find available VPS
            $vps = $this->findAvailableVps($tenant);

            if (!$vps) {
                throw new \RuntimeException('No available VPS server found');
            }

            // Create site record
            $site = Site::create([
                'tenant_id' => $tenant->id,
                'vps_id' => $vps->id,
                'domain' => strtolower($validated['domain']),
                'site_type' => $validated['site_type'] ?? 'wordpress',
                'php_version' => $validated['php_version'] ?? '8.2',
                'ssl_enabled' => $validated['ssl_enabled'] ?? true,
                'status' => 'creating',
            ]);

            return $site;
        });

        // Dispatch async job to provision site on VPS
        ProvisionSiteJob::dispatch($site);

        return response()->json([
            'success' => true,
            'data' => $this->formatSite($site),
            'message' => 'Site is being created.',
        ], 201);

    } catch (\Exception $e) {
        Log::error('Site creation failed', [
            'domain' => $validated['domain'],
            'error' => $e->getMessage(),
        ]);

        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'SITE_CREATION_FAILED',
                'message' => 'Failed to create site. Please try again.',
            ],
        ], 500);
    }
}

private function findAvailableVps(Tenant $tenant): ?VpsServer
{
    // First check if tenant has existing allocation
    $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();

    if ($allocation && $allocation->vpsServer->isAvailable()) {
        return $allocation->vpsServer;
    }

    // Find shared VPS with capacity
    return VpsServer::active()
        ->shared()
        ->healthy()
        ->orderByRaw('(SELECT COUNT(*) FROM sites WHERE vps_id = vps_servers.id) ASC')
        ->first();
}
```

**After:**

```php
// app/Services/SiteManagementService.php
<?php

namespace App\Services;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Repositories\Contracts\SiteRepositoryInterface;
use App\Jobs\ProvisionSiteJob;
use App\Exceptions\QuotaExceededException;
use App\Exceptions\NoVpsAvailableException;
use Illuminate\Support\Facades\DB;

class SiteManagementService
{
    public function __construct(
        private SiteRepositoryInterface $siteRepository,
        private QuotaService $quotaService
    ) {}

    /**
     * Create a new site for a tenant.
     *
     * @throws QuotaExceededException
     * @throws NoVpsAvailableException
     */
    public function createSite(Tenant $tenant, array $data): Site
    {
        // Check quota
        $this->quotaService->checkSiteLimit($tenant);

        // Find available VPS
        $vps = $this->findAvailableVps($tenant);

        if (!$vps) {
            throw new NoVpsAvailableException('No available VPS server found');
        }

        // Create site in transaction
        $site = DB::transaction(function () use ($tenant, $vps, $data) {
            return $this->siteRepository->create([
                'tenant_id' => $tenant->id,
                'vps_id' => $vps->id,
                'domain' => strtolower($data['domain']),
                'site_type' => $data['site_type'] ?? 'wordpress',
                'php_version' => $data['php_version'] ?? '8.2',
                'ssl_enabled' => $data['ssl_enabled'] ?? true,
                'status' => 'creating',
            ]);
        });

        // Dispatch provisioning job
        ProvisionSiteJob::dispatch($site);

        return $site;
    }

    /**
     * Delete a site.
     */
    public function deleteSite(Site $site, bool $force = false): void
    {
        DB::transaction(function () use ($site, $force) {
            // Delete from VPS if active
            if ($site->vpsServer && $site->status === 'active') {
                $this->deleteFromVps($site, $force);
            }

            // Soft delete
            $this->siteRepository->delete($site);
        });
    }

    /**
     * Enable a site.
     */
    public function enableSite(Site $site): bool
    {
        if ($site->status === 'active') {
            return true;
        }

        // Enable on VPS
        $result = app(VPSManagerBridge::class)->enableSite($site->vpsServer, $site->domain);

        if ($result['success']) {
            $this->siteRepository->update($site, ['status' => 'active']);
        }

        return $result['success'];
    }

    /**
     * Disable a site.
     */
    public function disableSite(Site $site): bool
    {
        if ($site->status === 'disabled') {
            return true;
        }

        // Disable on VPS
        $result = app(VPSManagerBridge::class)->disableSite($site->vpsServer, $site->domain);

        if ($result['success']) {
            $this->siteRepository->update($site, ['status' => 'disabled']);
        }

        return $result['success'];
    }

    /**
     * Find available VPS for a tenant.
     */
    private function findAvailableVps(Tenant $tenant): ?VpsServer
    {
        // First check if tenant has existing allocation
        $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();

        if ($allocation && $allocation->vpsServer->isAvailable()) {
            return $allocation->vpsServer;
        }

        // Find shared VPS with capacity
        return VpsServer::active()
            ->shared()
            ->healthy()
            ->orderByRaw('(SELECT COUNT(*) FROM sites WHERE vps_id = vps_servers.id) ASC')
            ->first();
    }

    /**
     * Delete site from VPS.
     */
    private function deleteFromVps(Site $site, bool $force): void
    {
        $result = app(VPSManagerBridge::class)->deleteSite($site->vpsServer, $site->domain, $force);

        if (!$result['success']) {
            \Log::warning('VPS site deletion failed', [
                'site' => $site->domain,
                'output' => $result['output'],
            ]);
        }
    }
}

// app/Services/QuotaService.php
<?php

namespace App\Services;

use App\Models\Tenant;
use App\Exceptions\QuotaExceededException;

class QuotaService
{
    /**
     * Check if tenant can create a site.
     *
     * @throws QuotaExceededException
     */
    public function checkSiteLimit(Tenant $tenant): void
    {
        if (!$tenant->canCreateSite()) {
            throw new QuotaExceededException(
                'You have reached your plan\'s site limit.',
                [
                    'current_sites' => $tenant->getSiteCount(),
                    'limit' => $tenant->getMaxSites(),
                ]
            );
        }
    }

    /**
     * Check if tenant can create a backup.
     *
     * @throws QuotaExceededException
     */
    public function checkBackupLimit(Tenant $tenant): void
    {
        // TODO: Implement backup quota logic
    }

    /**
     * Check storage quota.
     *
     * @throws QuotaExceededException
     */
    public function checkStorageLimit(Tenant $tenant, int $additionalMb): void
    {
        $tierLimits = $tenant->tierLimits;
        if (!$tierLimits) {
            return;
        }

        $currentUsage = $tenant->getStorageUsedMb();
        $maxStorage = $tierLimits->max_storage_gb * 1024;

        if ($maxStorage !== -1 && ($currentUsage + $additionalMb) > $maxStorage) {
            throw new QuotaExceededException(
                'Storage limit exceeded.',
                [
                    'current_mb' => $currentUsage,
                    'additional_mb' => $additionalMb,
                    'limit_mb' => $maxStorage,
                ]
            );
        }
    }
}

// app/Exceptions/QuotaExceededException.php
<?php

namespace App\Exceptions;

class QuotaExceededException extends \Exception
{
    public function __construct(
        string $message = "",
        private array $details = [],
        int $code = 0,
        ?\Throwable $previous = null
    ) {
        parent::__construct($message, $code, $previous);
    }

    public function getDetails(): array
    {
        return $this->details;
    }
}
```

**Updated Controller:**
```php
// SiteController.php
use App\Services\SiteManagementService;
use App\Exceptions\QuotaExceededException;
use App\Exceptions\NoVpsAvailableException;

class SiteController extends ApiController
{
    public function __construct(
        private SiteManagementService $siteManagement
    ) {}

    public function store(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $validated = $request->validate([
            'domain' => [
                'required',
                'string',
                'max:253',
                'regex:/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i',
                Rule::unique('sites')->where('tenant_id', $tenant->id),
            ],
            'site_type' => ['sometimes', 'in:wordpress,html,laravel'],
            'php_version' => ['sometimes', 'in:8.2,8.4'],
            'ssl_enabled' => ['sometimes', 'boolean'],
        ]);

        try {
            $site = $this->siteManagement->createSite($tenant, $validated);

            return $this->successResponse(
                new SiteResource($site),
                'Site is being created.',
                201
            );

        } catch (QuotaExceededException $e) {
            return $this->errorResponse(
                'SITE_LIMIT_EXCEEDED',
                $e->getMessage(),
                $e->getDetails(),
                403
            );

        } catch (NoVpsAvailableException $e) {
            $this->logError('No VPS available for site creation', [
                'tenant_id' => $tenant->id,
                'domain' => $validated['domain'],
            ]);

            return $this->errorResponse(
                'NO_VPS_AVAILABLE',
                'No server capacity available. Please contact support.',
                [],
                503
            );

        } catch (\Exception $e) {
            $this->logError('Site creation failed', [
                'domain' => $validated['domain'],
                'error' => $e->getMessage(),
            ]);

            return $this->errorResponse(
                'SITE_CREATION_FAILED',
                'Failed to create site. Please try again.',
                [],
                500
            );
        }
    }

    public function enable(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $this->siteRepository->findById($id);

        if (!$site || $site->tenant_id !== $tenant->id) {
            return $this->errorResponse('SITE_NOT_FOUND', 'Site not found.', [], 404);
        }

        try {
            $success = $this->siteManagement->enableSite($site);

            return $this->successResponse(
                new SiteResource($site->fresh()),
                $success ? 'Site enabled.' : 'Failed to enable site.'
            );

        } catch (\Exception $e) {
            return $this->errorResponse('ENABLE_FAILED', $e->getMessage(), [], 500);
        }
    }
}
```

**Impact:**
- Controllers reduced from 439 lines to ~150 lines (66% reduction)
- Business logic now testable independently
- Easier to add features (e.g., audit logging, notifications)
- Clear separation of concerns
- Reusable services across controllers and jobs

**Testing:**
```php
// tests/Unit/Services/SiteManagementServiceTest.php
class SiteManagementServiceTest extends TestCase
{
    use RefreshDatabase;

    private SiteManagementService $service;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = new SiteManagementService(
            app(SiteRepositoryInterface::class),
            app(QuotaService::class)
        );
    }

    public function test_create_site_throws_exception_when_quota_exceeded()
    {
        $this->expectException(QuotaExceededException::class);

        $tenant = Tenant::factory()->create();
        $tenant->tierLimits()->create(['max_sites' => 0]);

        $this->service->createSite($tenant, ['domain' => 'test.com']);
    }

    public function test_create_site_succeeds_with_available_vps()
    {
        Queue::fake();

        $tenant = Tenant::factory()->create();
        $vps = VpsServer::factory()->create(['status' => 'active']);

        $site = $this->service->createSite($tenant, [
            'domain' => 'test.com',
            'site_type' => 'wordpress',
        ]);

        $this->assertEquals('creating', $site->status);
        $this->assertEquals($vps->id, $site->vps_id);
        Queue::assertPushed(ProvisionSiteJob::class);
    }
}
```

---

### 2.3 Controller Slimming (Week 6)

**Goal:** Apply repository and service patterns to all controllers.

**Controllers to Refactor:**
1. `SiteController.php` - 439 lines → ~150 lines (66% reduction)
2. `BackupController.php` - 333 lines → ~120 lines (64% reduction)
3. `TeamController.php` - 492 lines → ~180 lines (63% reduction)

**Create:**
- `BackupService.php`
- `TeamManagementService.php`
- `BackupRepository.php`
- `UserRepository.php`

**Impact Summary:**
- Total lines reduced: ~800 lines (60%)
- Business logic extracted to services: 100%
- Data access abstracted to repositories: 100%
- Controllers become thin orchestrators

---

### Week 3-6 Summary

**Tasks Checklist:**
- [ ] Create all repository interfaces and implementations
- [ ] Create `RepositoryServiceProvider`
- [ ] Write repository unit tests (15+ tests)
- [ ] Create `SiteManagementService` with tests
- [ ] Create `QuotaService` with tests
- [ ] Create custom exceptions
- [ ] Update `SiteController` to use services
- [ ] Create `BackupService` and `BackupRepository`
- [ ] Create `TeamManagementService` and `UserRepository`
- [ ] Update all controllers to use new architecture
- [ ] Run full integration tests
- [ ] Performance testing
- [ ] Code review and merge

**Expected Metrics:**
- Lines of code reduced: ~1,000 lines
- Code duplication reduced: 60%
- Test coverage: 85%+
- Cyclomatic complexity: Reduced by 50%
- Controller avg size: 150 lines (was 350)

---

## Phase 3: Architectural Improvements (Week 7-12)

**Goal:** Establish long-term architectural patterns and module boundaries.

**Effort:** 6 weeks
**Risk:** Medium-High
**ROI:** High (long-term)
**Impact:** Scalability, maintainability, team velocity

### 3.1 Module Boundaries (Week 7-8)

**Problem:** Code is organized by technical layer (Controllers, Models), not by domain.

**Target Architecture:**
```
app/
├── Modules/
│   ├── Site/
│   │   ├── Controllers/
│   │   ├── Services/
│   │   ├── Repositories/
│   │   ├── Resources/
│   │   ├── Models/
│   │   ├── Jobs/
│   │   ├── Events/
│   │   └── Policies/
│   ├── Backup/
│   ├── Team/
│   ├── Tenant/
│   └── VpsManagement/
└── Shared/
    ├── Traits/
    ├── Exceptions/
    └── Support/
```

**Benefits:**
- Clear domain boundaries
- Easier to understand and navigate
- Enables team ownership (team owns module)
- Prepares for potential microservices
- Enforces bounded contexts

**Implementation:**
```bash
# Week 7: Restructure Site module
mkdir -p app/Modules/Site/{Controllers,Services,Repositories,Resources,Models,Jobs,Events,Policies}
mv app/Http/Controllers/Api/V1/SiteController.php app/Modules/Site/Controllers/
mv app/Services/SiteManagementService.php app/Modules/Site/Services/
mv app/Repositories/SiteRepository.php app/Modules/Site/Repositories/
mv app/Http/Resources/SiteResource.php app/Modules/Site/Resources/
mv app/Models/Site.php app/Modules/Site/Models/
mv app/Jobs/ProvisionSiteJob.php app/Modules/Site/Jobs/

# Update namespaces
# Update composer.json autoload
```

**Module Interface:**
```php
// app/Modules/Site/SiteModule.php
<?php

namespace App\Modules\Site;

use Illuminate\Support\ServiceProvider;

class SiteModule extends ServiceProvider
{
    public function register(): void
    {
        // Register module bindings
        $this->app->bind(
            \App\Modules\Site\Repositories\Contracts\SiteRepositoryInterface::class,
            \App\Modules\Site\Repositories\SiteRepository::class
        );
    }

    public function boot(): void
    {
        // Load routes
        $this->loadRoutesFrom(__DIR__ . '/routes.php');

        // Load migrations
        $this->loadMigrationsFrom(__DIR__ . '/Migrations');
    }
}
```

---

### 3.2 Event-Driven Architecture (Week 9-10)

**Problem:** Tight coupling between operations (e.g., site creation triggers email, logging, metrics).

**Solution:** Introduce domain events.

**Events to Create:**
- `SiteCreated`, `SiteDeleted`, `SiteEnabled`, `SiteDisabled`
- `BackupCreated`, `BackupCompleted`, `BackupFailed`
- `TeamMemberInvited`, `TeamMemberRemoved`

**Before:**
```php
// SiteManagementService.php
public function createSite(Tenant $tenant, array $data): Site
{
    $site = $this->siteRepository->create([...]);

    // Coupled operations
    ProvisionSiteJob::dispatch($site);
    AuditLog::create(['action' => 'site_created', ...]);
    Notification::send($tenant->owner, new SiteCreatedNotification($site));

    return $site;
}
```

**After:**
```php
// app/Modules/Site/Events/SiteCreated.php
<?php

namespace App\Modules\Site\Events;

use App\Modules\Site\Models\Site;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class SiteCreated
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public Site $site
    ) {}
}

// app/Modules/Site/Listeners/ProvisionSiteOnVps.php
class ProvisionSiteOnVps
{
    public function handle(SiteCreated $event): void
    {
        ProvisionSiteJob::dispatch($event->site);
    }
}

// app/Modules/Site/Listeners/LogSiteCreation.php
class LogSiteCreation
{
    public function handle(SiteCreated $event): void
    {
        AuditLog::create([
            'tenant_id' => $event->site->tenant_id,
            'action' => 'site_created',
            'resource_type' => 'site',
            'resource_id' => $event->site->id,
            'metadata' => [
                'domain' => $event->site->domain,
            ],
        ]);
    }
}

// app/Modules/Site/Listeners/NotifyOwner.php
class NotifyOwner
{
    public function handle(SiteCreated $event): void
    {
        $owner = $event->site->tenant->organization->owner;
        Notification::send($owner, new SiteCreatedNotification($event->site));
    }
}

// SiteManagementService.php (simplified)
public function createSite(Tenant $tenant, array $data): Site
{
    $site = $this->siteRepository->create([...]);

    // Single event triggers all side effects
    event(new SiteCreated($site));

    return $site;
}

// EventServiceProvider.php
protected $listen = [
    \App\Modules\Site\Events\SiteCreated::class => [
        \App\Modules\Site\Listeners\ProvisionSiteOnVps::class,
        \App\Modules\Site\Listeners\LogSiteCreation::class,
        \App\Modules\Site\Listeners\NotifyOwner::class,
    ],
];
```

**Benefits:**
- Decouples side effects from core logic
- Easy to add new reactions (just add listener)
- Testable in isolation
- Enables async processing
- Clear audit trail

---

### 3.3 Interface Abstractions (Week 11)

**Problem:** Services depend on concrete implementations.

**Solution:** Introduce interfaces for key services.

**Interfaces to Create:**
```php
// app/Contracts/VpsProviderInterface.php
<?php

namespace App\Contracts;

interface VpsProviderInterface
{
    public function createSite(VpsServer $vps, string $domain, array $options): array;
    public function deleteSite(VpsServer $vps, string $domain, bool $force = false): array;
    public function enableSite(VpsServer $vps, string $domain): array;
    public function disableSite(VpsServer $vps, string $domain): array;
    public function issueSSL(VpsServer $vps, string $domain): array;
}

// VPSManagerBridge implements VpsProviderInterface
// Future: PleskProvider, cPanelProvider, etc.

// app/Contracts/NotificationServiceInterface.php
interface NotificationServiceInterface
{
    public function sendSiteCreated(Site $site): void;
    public function sendBackupCompleted(SiteBackup $backup): void;
    public function sendTeamInvitation(string $email, string $token): void;
}

// app/Contracts/MetricsCollectorInterface.php
interface MetricsCollectorInterface
{
    public function recordSiteCreation(Site $site): void;
    public function recordBackupDuration(SiteBackup $backup, float $seconds): void;
    public function recordApiRequest(string $endpoint, int $statusCode, float $duration): void;
}
```

**Benefits:**
- Enables swapping implementations (e.g., different VPS providers)
- Easier testing with mocks
- Enforces contracts
- Documents expected behavior

---

### 3.4 Query Objects (Week 12)

**Problem:** Complex queries scattered across repositories.

**Solution:** Extract to dedicated query objects.

```php
// app/Modules/Site/Queries/GetSitesExpiringSslQuery.php
<?php

namespace App\Modules\Site\Queries;

use Illuminate\Support\Collection;
use App\Modules\Site\Models\Site;

class GetSitesExpiringSslQuery
{
    public function __construct(
        private int $days = 14
    ) {}

    public function execute(): Collection
    {
        return Site::query()
            ->where('ssl_enabled', true)
            ->whereNotNull('ssl_expires_at')
            ->where('ssl_expires_at', '<=', now()->addDays($this->days))
            ->where('ssl_expires_at', '>', now())
            ->with(['tenant', 'vpsServer'])
            ->orderBy('ssl_expires_at')
            ->get();
    }
}

// app/Modules/Site/Queries/GetSitesForTenantQuery.php
class GetSitesForTenantQuery
{
    public function __construct(
        private Tenant $tenant,
        private array $filters = []
    ) {}

    public function execute(): LengthAwarePaginator
    {
        $query = $this->tenant->sites()
            ->with('vpsServer:id,hostname,ip_address');

        $this->applyFilters($query);
        $this->applyOrdering($query);

        return $query->paginate($this->filters['per_page'] ?? 20);
    }

    private function applyFilters($query): void
    {
        if (!empty($this->filters['status'])) {
            $query->where('status', $this->filters['status']);
        }

        if (!empty($this->filters['type'])) {
            $query->where('site_type', $this->filters['type']);
        }

        if (!empty($this->filters['search'])) {
            $query->where('domain', 'like', '%' . $this->filters['search'] . '%');
        }
    }

    private function applyOrdering($query): void
    {
        $sortBy = $this->filters['sort_by'] ?? 'created_at';
        $sortOrder = $this->filters['sort_order'] ?? 'desc';

        $query->orderBy($sortBy, $sortOrder);
    }
}

// Usage in Repository
public function findByTenant(Tenant $tenant, array $filters = [], int $perPage = 20): LengthAwarePaginator
{
    return (new GetSitesForTenantQuery($tenant, $filters))->execute();
}
```

**Benefits:**
- Reusable queries
- Testable in isolation
- Complex logic encapsulated
- Easier to optimize
- Clear naming (query intent obvious)

---

### Week 7-12 Summary

**Tasks Checklist:**
- [ ] Restructure into modules (Site, Backup, Team)
- [ ] Create module service providers
- [ ] Update namespaces and autoloading
- [ ] Create domain events (10+ events)
- [ ] Create event listeners (20+ listeners)
- [ ] Update EventServiceProvider
- [ ] Create service interfaces (5+ interfaces)
- [ ] Update service bindings
- [ ] Create query objects (10+ queries)
- [ ] Update repositories to use queries
- [ ] Full regression testing
- [ ] Performance benchmarking
- [ ] Documentation updates
- [ ] Team training

**Expected Metrics:**
- Module cohesion: 90%+
- Event coverage: 100% of domain actions
- Interface coverage: 80% of services
- Query reusability: 100%
- Code organization score: A

---

## Testing Strategy

### Unit Testing
- **Target:** 90% coverage for services, repositories, queries
- **Tools:** PHPUnit, Mockery
- **Focus:** Business logic in isolation

```php
// Example: Service test
class SiteManagementServiceTest extends TestCase
{
    public function test_create_site_with_mocked_dependencies()
    {
        $mockRepo = Mockery::mock(SiteRepositoryInterface::class);
        $mockQuota = Mockery::mock(QuotaService::class);

        $mockQuota->shouldReceive('checkSiteLimit')->once();
        $mockRepo->shouldReceive('create')->once()->andReturn(new Site());

        $service = new SiteManagementService($mockRepo, $mockQuota);
        $site = $service->createSite($tenant, $data);

        $this->assertInstanceOf(Site::class, $site);
    }
}
```

### Integration Testing
- **Target:** All API endpoints
- **Tools:** PHPUnit with RefreshDatabase
- **Focus:** Full request → response flow

```php
// Example: Controller test
class SiteControllerTest extends TestCase
{
    use RefreshDatabase;

    public function test_create_site_endpoint()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create();

        $response = $this->actingAs($user)
            ->postJson('/api/v1/sites', [
                'domain' => 'test.com',
                'site_type' => 'wordpress',
            ]);

        $response->assertStatus(201)
            ->assertJsonStructure(['success', 'data', 'message']);

        $this->assertDatabaseHas('sites', ['domain' => 'test.com']);
    }
}
```

### Feature Testing
- **Target:** Critical user flows
- **Tools:** Laravel Dusk (E2E)
- **Focus:** User experience

```php
// Example: E2E test
class SiteManagementTest extends DuskTestCase
{
    public function test_user_can_create_site_via_ui()
    {
        $this->browse(function (Browser $browser) {
            $browser->loginAs($this->user)
                ->visit('/sites')
                ->click('@create-site-button')
                ->type('domain', 'test.com')
                ->select('site_type', 'wordpress')
                ->click('@submit')
                ->assertSee('Site is being created');
        });
    }
}
```

### Regression Testing
- Run full test suite before each merge
- Automated via CI/CD
- Performance benchmarks

---

## Migration Strategy

### Approach: Strangler Fig Pattern

**Phase-by-Phase Migration:**

1. **Phase 1 (Week 1-2):** Non-breaking additions
   - Add traits, resources, base classes
   - Controllers use both old and new patterns
   - No removal of old code yet

2. **Phase 2 (Week 3-6):** Gradual replacement
   - Create repositories alongside direct Eloquent
   - Create services, gradually move logic
   - Controllers call services, which may still use old code internally
   - Test extensively

3. **Phase 3 (Week 7-12):** Complete transition
   - Remove old patterns
   - Enforce new architecture via code reviews
   - Update documentation

### Rollback Plan

**Each phase has rollback points:**
- Git tags: `refactor-phase-1-start`, `refactor-phase-1-complete`
- Feature flags for new code paths
- Database migrations are reversible
- Can run old and new code side-by-side

### Deployment Strategy

**Blue-Green Deployments:**
1. Deploy refactored code to staging
2. Run parallel testing (old vs new)
3. Monitor metrics (response time, error rate)
4. Gradual rollout (10% → 50% → 100%)
5. Keep old code for 1 sprint as fallback

---

## Risk Assessment

### High-Risk Areas

**1. Repository Pattern Introduction**
- **Risk:** Breaking existing queries, performance degradation
- **Mitigation:**
  - Extensive unit tests
  - Performance benchmarks before/after
  - Parallel implementation (old + new)
  - Code review by 2+ developers

**2. Service Layer Extraction**
- **Risk:** Incorrect business logic extraction, bugs
- **Mitigation:**
  - Incremental extraction
  - 100% test coverage for services
  - Feature flags for new code paths
  - Staged rollout

**3. Module Restructuring**
- **Risk:** Broken namespaces, autoload issues
- **Mitigation:**
  - Automated namespace updates
  - Comprehensive testing
  - Staged migration (one module at a time)

### Medium-Risk Areas

**4. Event-Driven Refactoring**
- **Risk:** Missing side effects, duplicate executions
- **Mitigation:**
  - Event listeners have idempotency checks
  - Extensive integration tests
  - Monitor event queue

**5. Interface Abstractions**
- **Risk:** Over-abstraction, complexity
- **Mitigation:**
  - Only create interfaces where swapping is likely
  - Start simple, add complexity as needed

### Low-Risk Areas

**6. Traits and Helpers**
- **Risk:** Minimal
- **Mitigation:** Simple to test and rollback

---

## Success Metrics

### Code Quality Metrics

| Metric | Current | Target (Phase 1) | Target (Phase 2) | Target (Phase 3) |
|--------|---------|------------------|------------------|------------------|
| Code Duplication | 25% | 15% | 8% | 3% |
| Avg Controller Size | 350 lines | 300 lines | 180 lines | 120 lines |
| Test Coverage | 45% | 60% | 80% | 90% |
| Cyclomatic Complexity | 15 | 12 | 8 | 5 |
| Maintainability Index | C (65) | C+ (70) | B (80) | A (90) |

### Performance Metrics

| Metric | Current | Target |
|--------|---------|--------|
| API Response Time (p95) | 450ms | <400ms |
| Database Queries per Request | 12 | <8 |
| Memory Usage per Request | 18MB | <15MB |

### Velocity Metrics

| Metric | Current | Target (Post-Refactor) |
|--------|---------|------------------------|
| Time to Add New Feature | 3 days | 1.5 days |
| Bug Fix Time | 2 hours | 1 hour |
| Onboarding Time (New Dev) | 2 weeks | 1 week |

### Business Metrics

| Metric | Target |
|--------|--------|
| Zero Downtime | 100% |
| No Data Loss | 100% |
| Performance Regression | <5% |
| Developer Satisfaction | +30% |

---

## Appendix A: File Structure

### Before Refactoring
```
app/
├── Http/
│   └── Controllers/
│       └── Api/
│           └── V1/
│               ├── SiteController.php (439 lines)
│               ├── BackupController.php (333 lines)
│               └── TeamController.php (492 lines)
├── Models/
│   ├── Site.php
│   ├── SiteBackup.php
│   ├── Tenant.php
│   └── User.php
├── Jobs/
│   ├── ProvisionSiteJob.php
│   └── IssueSslCertificateJob.php
└── Services/
    └── Integration/
        └── VPSManagerBridge.php
```

### After Refactoring (Phase 3)
```
app/
├── Modules/
│   ├── Site/
│   │   ├── Controllers/
│   │   │   └── SiteController.php (120 lines)
│   │   ├── Services/
│   │   │   └── SiteManagementService.php
│   │   ├── Repositories/
│   │   │   ├── Contracts/
│   │   │   │   └── SiteRepositoryInterface.php
│   │   │   └── SiteRepository.php
│   │   ├── Resources/
│   │   │   └── SiteResource.php
│   │   ├── Models/
│   │   │   └── Site.php
│   │   ├── Jobs/
│   │   │   └── ProvisionSiteJob.php
│   │   ├── Events/
│   │   │   ├── SiteCreated.php
│   │   │   ├── SiteDeleted.php
│   │   │   ├── SiteEnabled.php
│   │   │   └── SiteDisabled.php
│   │   ├── Listeners/
│   │   │   ├── ProvisionSiteOnVps.php
│   │   │   ├── LogSiteCreation.php
│   │   │   └── NotifyOwner.php
│   │   ├── Queries/
│   │   │   ├── GetSitesForTenantQuery.php
│   │   │   └── GetSitesExpiringSslQuery.php
│   │   └── Policies/
│   │       └── SitePolicy.php
│   ├── Backup/
│   ├── Team/
│   └── Tenant/
├── Shared/
│   ├── Traits/
│   │   ├── ApiResponse.php
│   │   └── HasTenantContext.php
│   ├── Exceptions/
│   │   ├── QuotaExceededException.php
│   │   └── NoVpsAvailableException.php
│   └── Http/
│       └── Controllers/
│           └── Api/
│               └── ApiController.php
└── Contracts/
    ├── VpsProviderInterface.php
    ├── NotificationServiceInterface.php
    └── MetricsCollectorInterface.php
```

---

## Appendix B: Key Patterns

### 1. Repository Pattern
**Purpose:** Abstract data access
**When:** Always for data retrieval/persistence
**Example:** `SiteRepository` handles all Site database operations

### 2. Service Layer Pattern
**Purpose:** Encapsulate business logic
**When:** Complex operations spanning multiple models
**Example:** `SiteManagementService` orchestrates site lifecycle

### 3. Event-Driven Pattern
**Purpose:** Decouple side effects
**When:** Actions trigger multiple reactions
**Example:** `SiteCreated` event triggers provisioning, logging, notifications

### 4. Resource Pattern
**Purpose:** Transform models to API responses
**When:** Presenting data to API consumers
**Example:** `SiteResource` formats Site for JSON API

### 5. Query Object Pattern
**Purpose:** Encapsulate complex queries
**When:** Query logic is reused or complex
**Example:** `GetSitesExpiringSslQuery` finds SSL certificates expiring soon

---

## Appendix C: Implementation Checklist

### Week 1-2: Quick Wins
- [ ] Day 1: Create `ApiResponse` trait
- [ ] Day 2: Create `HasTenantContext` trait
- [ ] Day 3: Create `ApiController` base class
- [ ] Day 4-5: Create API Resources (Site, Backup, User)
- [ ] Day 6-7: Update controllers to use new abstractions
- [ ] Day 8-9: Write tests for new abstractions
- [ ] Day 10: Code review and merge

### Week 3-4: Repository Layer
- [ ] Day 1-2: Create repository interfaces
- [ ] Day 3-4: Implement `SiteRepository`
- [ ] Day 5-6: Implement `BackupRepository`, `UserRepository`
- [ ] Day 7-8: Create `RepositoryServiceProvider`
- [ ] Day 9-10: Update controllers to use repositories
- [ ] Day 11-12: Write repository tests
- [ ] Day 13-14: Integration testing

### Week 5-6: Service Layer
- [ ] Day 1-3: Create `SiteManagementService`
- [ ] Day 4-5: Create `QuotaService`
- [ ] Day 6-7: Create `BackupService`, `TeamManagementService`
- [ ] Day 8-9: Create custom exceptions
- [ ] Day 10-11: Update controllers to use services
- [ ] Day 12-14: Write service tests

### Week 7-8: Module Boundaries
- [ ] Day 1-2: Design module structure
- [ ] Day 3-5: Restructure Site module
- [ ] Day 6-7: Restructure Backup module
- [ ] Day 8-9: Restructure Team module
- [ ] Day 10-11: Update namespaces and autoloading
- [ ] Day 12-14: Testing and fixes

### Week 9-10: Event-Driven
- [ ] Day 1-2: Identify domain events
- [ ] Day 3-5: Create events and listeners
- [ ] Day 6-7: Update services to fire events
- [ ] Day 8-9: Update `EventServiceProvider`
- [ ] Day 10-12: Testing event flows
- [ ] Day 13-14: Monitor and tune

### Week 11: Interfaces
- [ ] Day 1-2: Create service interfaces
- [ ] Day 3-4: Update implementations
- [ ] Day 5-6: Update bindings
- [ ] Day 7: Testing

### Week 12: Query Objects & Polish
- [ ] Day 1-3: Create query objects
- [ ] Day 4-5: Update repositories
- [ ] Day 6-7: Final testing
- [ ] Day 8-9: Documentation
- [ ] Day 10: Team training
- [ ] Day 11-14: Bug fixes and optimization

---

## Conclusion

This refactoring plan transforms the CHOM application from a monolithic controller-heavy architecture to a clean, modular, event-driven system following SOLID principles.

**Key Achievements:**
- 60% code reduction in controllers
- 90% test coverage
- Clear module boundaries
- Scalable architecture
- Improved developer experience

**Next Steps:**
1. Review and approve plan with team
2. Set up project tracking (Jira/Linear)
3. Allocate resources (2 developers, 12 weeks)
4. Begin Phase 1 (Week 1-2)
5. Weekly progress reviews
6. Adjust timeline as needed

**Success Criteria:**
- All tests passing
- No performance regression
- Zero production incidents
- Team can ship features 50% faster

---

**Document Version:** 1.0
**Last Updated:** January 2, 2026
**Owner:** Engineering Team
**Status:** Ready for Review
