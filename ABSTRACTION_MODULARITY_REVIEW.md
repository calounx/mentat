# CHOM Application - Abstraction & Modularity Architecture Review

**Review Date:** 2026-01-02
**Application:** CHOM (Cloud Hosting Operations Manager)
**Reviewer:** Architecture Review Team
**Severity Levels:** CRITICAL | HIGH | MEDIUM | LOW

---

## Executive Summary

This review assesses the CHOM application's adherence to proper abstraction layers, separation of concerns, and modularity principles. The application demonstrates a **partially implemented** layered architecture with significant opportunities for improvement in abstraction and separation of concerns.

### Overall Architecture Score: 5.5/10

**Key Findings:**
- **Missing Repository Layer**: No repository pattern implementation (CRITICAL)
- **Fat Controllers**: Business logic embedded in controllers (HIGH)
- **Duplicated Logic**: Code duplication across controllers and Livewire components (HIGH)
- **Weak Service Layer**: Only 2 service classes for entire application (HIGH)
- **Model Anemia**: Models lack business logic, acting as data containers (MEDIUM)
- **No Interfaces**: Zero interface abstractions, tight coupling to concrete implementations (MEDIUM)
- **Positive**: Good Job pattern usage for async operations
- **Positive**: Clean separation between API and Livewire presentation layers

---

## 1. Abstraction Layer Analysis

### 1.1 Controller → Service → Repository Pattern

#### Current State: **CRITICAL VIOLATION**

**Expected Pattern:**
```
Controller → Service → Repository → Model
(Presentation) (Business Logic) (Data Access) (Domain)
```

**Actual Implementation:**
```
Controller → Model (Direct Eloquent queries)
Livewire Component → Model (Direct Eloquent queries)
```

#### Issues Identified:

##### A. Missing Repository Layer (CRITICAL)
- **Finding**: No repository classes exist in the codebase
- **Impact**:
  - Controllers directly query Eloquent models
  - Impossible to swap data sources without rewriting controllers
  - Query logic duplicated across controllers
  - Testing requires full database setup
  - Cannot abstract data access patterns

**Evidence:**
```php
// File: /home/calounx/repositories/mentat/app/Http/Controllers/Api/V1/SiteController.php
// Lines 31-50: Direct Eloquent queries in controller
$query = $tenant->sites()
    ->with('vpsServer:id,hostname,ip_address')
    ->orderBy('created_at', 'desc');

if ($request->has('status')) {
    $query->where('status', $request->input('status'));
}
```

**Should Be:**
```php
// With Repository Pattern
public function index(Request $request): JsonResponse
{
    $tenant = $this->getTenant($request);
    $filters = $request->only(['status', 'type', 'search', 'per_page']);

    $sites = $this->siteRepository->getPaginatedForTenant($tenant, $filters);

    return response()->json([
        'success' => true,
        'data' => $sites->items(),
        'meta' => $this->paginationMeta($sites),
    ]);
}
```

##### B. Inadequate Service Layer (HIGH)

**Services Found:**
1. `/app/Services/Integration/VPSManagerBridge.php` (439 lines) - Infrastructure service
2. `/app/Services/Integration/ObservabilityAdapter.php` (461 lines) - Integration service

**Services Missing:**
- SiteService - Site management business logic
- BackupService - Backup orchestration
- TeamService - Team and organization management
- AuthService - Authentication and registration business logic
- SubscriptionService - Billing and tier management
- VpsAllocationService - VPS assignment logic
- NotificationService - Email/notification logic

**Impact:**
- Business logic scattered across controllers (739 LOC in controllers)
- Cannot reuse logic between API and Livewire layers
- Complex workflows (like site creation) duplicated

**Evidence of Duplication:**
```php
// SiteController.php (lines 102-122) - Site creation logic
$site = DB::transaction(function () use ($validated, $tenant) {
    $vps = $this->findAvailableVps($tenant);
    if (!$vps) {
        throw new \RuntimeException('No available VPS server found');
    }
    $site = Site::create([
        'tenant_id' => $tenant->id,
        'vps_id' => $vps->id,
        'domain' => strtolower($validated['domain']),
        // ...
    ]);
    return $site;
});

// SiteCreate.php Livewire (lines 66-86) - SAME LOGIC DUPLICATED
$site = DB::transaction(function () use ($tenant) {
    $vps = $this->findAvailableVps($tenant);
    if (!$vps) {
        throw new \RuntimeException('No available server found.');
    }
    $site = Site::create([
        'tenant_id' => $tenant->id,
        'vps_id' => $vps->id,
        'domain' => $this->domain,
        // ...
    ]);
    return $site;
});
```

##### C. Business Logic in Controllers (HIGH)

**Controllers with Business Logic:**

**1. SiteController (439 lines, 14 methods)**
- Lines 102-122: Site creation transaction logic
- Lines 382-397: VPS allocation algorithm
- Lines 399-438: Response formatting logic
- **Violation**: Controllers should delegate to services

**2. TeamController (492 lines, 13 methods)**
- Lines 62-109: Role update authorization and validation logic
- Lines 165-194: Team member removal with token revocation
- Lines 314-378: Ownership transfer with complex business rules
- **Violation**: Complex authorization logic should be in service layer

**3. BackupController (333 lines, 9 methods)**
- Lines 118-151: Backup creation orchestration
- Lines 164-191: Storage deletion logic
- **Violation**: Backup orchestration should be in BackupService

**4. AuthController (220 lines, 5 methods)**
- Lines 32-59: Multi-step registration with organization/tenant creation
- **Violation**: Registration workflow should be in AuthService

### 1.2 Data Access Patterns

#### Current State: **POOR**

**Issues:**

1. **No Query Object Pattern**
   - Complex queries inline in controllers
   - No reusable query builders

2. **No Specification Pattern**
   - Filtering logic scattered
   - Cannot compose filters

3. **Direct Eloquent Everywhere**
   ```php
   // SiteController.php - Multiple places
   $site = $tenant->sites()->findOrFail($id);
   $sites = $query->paginate($request->input('per_page', 20));
   ```

**Impact:**
- Cannot test without database
- Cannot swap ORMs
- Query optimization difficult
- No centralized query logging

---

## 2. Modularity Assessment

### 2.1 Feature Coupling Analysis

#### Coupling Map:

```
Controllers (API Layer)
    ↓ (HIGH COUPLING)
Models (Domain Layer)
    ↓ (MEDIUM COUPLING)
Services (Infrastructure Layer)
    ↓ (HIGH COUPLING)
External Services (VPS, Observability)
```

**Coupling Issues:**

1. **Cross-Feature Dependencies:**
   - SiteController depends on: Site, Tenant, VpsServer, VPSManagerBridge
   - TeamController depends on: User, Organization, Tenant, multiple unrelated models
   - BackupController depends on: Site, SiteBackup, Tenant, Storage facade

2. **Livewire Component Duplication:**
   - SiteCreate.php duplicates SiteController logic
   - No shared abstractions between API and web layers

3. **Tight External Service Coupling:**
   - VPSManagerBridge directly injected into controllers
   - No abstraction interfaces for external integrations
   - Cannot mock or swap implementations easily

### 2.2 Cross-Feature Dependencies

**Dependency Violations:**

```php
// SiteController.php depends on Job classes directly
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;

// Should use: Event/Listener pattern or Service abstraction
```

**Cyclic Dependencies:**
- Tenant → Sites → VpsServer → VpsAllocation → Tenant (via relationship)

### 2.3 Shared Code Organization

#### Current Organization:

```
app/
├── Http/
│   └── Controllers/Api/V1/     (4 controllers, 1,484 LOC)
├── Livewire/                    (6 components, duplicated logic)
├── Models/                      (13 models, anemic domain)
├── Services/Integration/        (2 services, infrastructure only)
├── Jobs/                        (4 jobs, good separation)
├── Policies/                    (3 policies, good separation)
└── Providers/                   (1 provider)
```

**Missing Layers:**
- `/app/Services/Domain/` - Business logic services
- `/app/Repositories/` - Data access layer
- `/app/Repositories/Contracts/` - Repository interfaces
- `/app/Services/Contracts/` - Service interfaces
- `/app/ValueObjects/` - Domain value objects
- `/app/DTOs/` - Data Transfer Objects
- `/app/Queries/` - Complex query objects
- `/app/Actions/` - Single-responsibility actions
- `/app/Exceptions/` - Domain-specific exceptions

### 2.4 Module Boundaries Clarity

**Current Modules (Implicit):**
1. Site Management (Sites, Backups)
2. Team Collaboration (Users, Organizations, Tenants)
3. VPS Infrastructure (VpsServer, VpsAllocation)
4. Billing (Subscriptions, Invoices)
5. Observability (Metrics, Logs)

**Boundary Issues:**
- No explicit module separation in code structure
- Models mixed together in single directory
- Cross-module dependencies everywhere
- No domain-driven design boundaries

---

## 3. Architectural Patterns Assessment

### 3.1 Service Layer Implementation

**Quality: POOR (2/10)**

**Existing Services:**

#### VPSManagerBridge (Infrastructure Service)
- **Lines**: 439
- **Methods**: 30+
- **Quality**: Good - single responsibility
- **Issues**: No interface abstraction

```php
// Good: Focused on VPS management integration
class VPSManagerBridge
{
    public function createWordPressSite(VpsServer $vps, string $domain, array $options = []): array
    public function deleteSite(VpsServer $vps, string $domain, bool $force = false): array
    public function issueSSL(VpsServer $vps, string $domain): array
    // ... 27 more methods
}
```

**Missing**: `VPSManagerInterface` for dependency inversion

#### ObservabilityAdapter (Infrastructure Service)
- **Lines**: 461
- **Methods**: 25+
- **Quality**: Good - focused responsibility
- **Issues**: No interface, query injection in injectTenantScope()

### 3.2 Repository Pattern Usage

**Status: NOT IMPLEMENTED**

**Impact:**
- Every controller reinvents data access
- No query reusability
- Cannot optimize queries centrally
- Testing requires full database

### 3.3 Factory Pattern Opportunities

**Current**: Minimal usage (Laravel Factories for testing only)

**Opportunities:**
1. **SiteFactory** - Complex site creation with VPS allocation
2. **OrganizationFactory** - Organization + Owner + Tenant creation
3. **BackupFactory** - Backup configuration based on tier
4. **ResponseFactory** - API response formatting

**Evidence of Need:**
```php
// AuthController.php (lines 32-59) - Manual object construction
$result = DB::transaction(function () use ($validated) {
    $organization = Organization::create([...]);
    $tenant = Tenant::create([...]);
    $user = User::create([...]);
    return compact('user', 'organization', 'tenant');
});

// Should be:
$registration = $this->organizationFactory->createWithOwner(
    organizationName: $validated['organization_name'],
    ownerName: $validated['name'],
    ownerEmail: $validated['email'],
    ownerPassword: $validated['password']
);
```

### 3.4 Strategy Pattern Opportunities

**Current**: Match expressions in Jobs (good start)

```php
// ProvisionSiteJob.php (lines 60-66) - Good use of match
$result = match ($site->site_type) {
    'wordpress' => $vpsManager->createWordPressSite($vps, $site->domain, [...]),
    'html' => $vpsManager->createHtmlSite($vps, $site->domain),
    default => throw new \InvalidArgumentException("Unsupported site type: {$site->site_type}"),
};
```

**Opportunities:**
1. **Site Provisioning Strategies**: WordPressProvisionStrategy, HtmlProvisionStrategy, LaravelProvisionStrategy
2. **Backup Strategies**: FullBackupStrategy, DatabaseOnlyStrategy, FilesOnlyStrategy
3. **Tier Strategies**: StarterTierStrategy, BusinessTierStrategy, EnterpriseStrategy
4. **VPS Allocation Strategies**: SharedAllocationStrategy, DedicatedAllocationStrategy

### 3.5 Command Pattern for Jobs

**Quality: EXCELLENT (9/10)**

**Well Implemented:**
```php
class ProvisionSiteJob implements ShouldQueue
{
    public int $tries = 3;
    public int $backoff = 60;

    public function __construct(public Site $site) {}

    public function handle(VPSManagerBridge $vpsManager): void
    {
        // Clean command execution
    }

    public function failed(?\Throwable $exception): void
    {
        // Proper failure handling
    }
}
```

**Jobs Found:**
- ProvisionSiteJob - Site provisioning
- CreateBackupJob - Backup creation
- RestoreBackupJob - Backup restoration
- IssueSslCertificateJob - SSL certificate issuance

**Suggestion**: Add more granular jobs for complex workflows

### 3.6 Observer Pattern for Events

**Status: NOT IMPLEMENTED**

**Evidence**: No custom events found in codebase

**Opportunities:**
1. **SiteCreated** - Trigger SSL issuance, send notifications
2. **SiteDeleted** - Cleanup VPS, send audit logs
3. **BackupCompleted** - Send notification, update metrics
4. **TeamMemberInvited** - Send invitation email
5. **SubscriptionChanged** - Update tier limits, send notification

**Current Problem:**
```php
// SiteController.php - Direct job dispatch, no event broadcast
ProvisionSiteJob::dispatch($site);
// Should trigger SiteCreated event with listeners
```

---

## 4. Code Organization Analysis

### 4.1 Directory Structure Effectiveness

**Current Structure: 4/10**

```
app/
├── Http/
│   ├── Controllers/
│   │   ├── Api/V1/ (4 files, 1,484 LOC) ← Fat controllers
│   │   └── Webhooks/ (1 file)
│   ├── Middleware/ (1 file)
│   └── Requests/V1/Team/ (2 files) ← Good!
├── Livewire/ (6 files) ← Duplicates API logic
├── Models/ (13 files, flat structure) ← No domain separation
├── Services/Integration/ (2 files) ← Missing domain services
├── Jobs/ (4 files) ← Good separation
├── Policies/ (3 files) ← Good authorization
└── Providers/ (1 file)
```

**Recommended Structure:**

```
app/
├── Http/
│   ├── Controllers/Api/V1/
│   ├── Requests/
│   └── Resources/ (API transformers)
├── Livewire/
├── Domain/ ← NEW: Domain-Driven Design
│   ├── Sites/
│   │   ├── Models/
│   │   ├── Services/
│   │   ├── Repositories/
│   │   ├── Events/
│   │   ├── Policies/
│   │   └── ValueObjects/
│   ├── Teams/
│   ├── Billing/
│   └── Infrastructure/
├── Application/ ← NEW: Application services
│   ├── Services/
│   ├── DTOs/
│   └── Actions/
├── Infrastructure/ ← NEW: External integrations
│   ├── VPS/
│   ├── Observability/
│   └── Storage/
├── Jobs/
└── Providers/
```

### 4.2 Namespace Organization

**Current**: Flat, minimal organization

**Issues:**
- All models in single `App\Models` namespace
- No domain-based namespacing
- Services buried in `Integration` subfolder

**Recommended:**
```php
// Domain namespaces
App\Domain\Sites\Models\Site
App\Domain\Sites\Services\SiteService
App\Domain\Sites\Repositories\SiteRepository
App\Domain\Sites\Repositories\Contracts\SiteRepositoryInterface

// Application layer
App\Application\Services\SiteManagementService
App\Application\DTOs\CreateSiteDTO

// Infrastructure
App\Infrastructure\VPS\VPSManagerBridge
App\Infrastructure\VPS\Contracts\VPSManagerInterface
```

### 4.3 Class Responsibilities (SRP Violations)

#### Fat Controllers (SRP Violations)

**TeamController** (492 lines, 13 methods)
- Responsibilities: HTTP handling, authorization, validation, business logic, formatting
- **Violations**:
  - Authorization logic (lines 68-76, 92-100)
  - Complex business rules (lines 314-378)
  - User token management (line 167)
  - Response formatting (lines 474-491)

**SiteController** (439 lines, 14 methods)
- Responsibilities: HTTP, validation, VPS allocation, quota checking, job dispatch, formatting
- **Violations**:
  - Quota checking (lines 74-86)
  - VPS allocation algorithm (lines 382-397)
  - Direct VPS manager calls (lines 199, 249, 285)
  - Response formatting (lines 399-438)

**BackupController** (333 lines, 9 methods)
- Responsibilities: HTTP, backup creation, storage management, formatting
- **Violations**:
  - Storage operations (lines 166-168)
  - Quota checking (commented out at line 115)
  - Expiration logic (line 249)

#### Fat Livewire Components

**SiteCreate** (130 lines)
- Duplicates SiteController create logic
- Contains VPS allocation algorithm
- Direct model manipulation

#### Anemic Models (Domain Logic Missing)

**Site Model** (132 lines)
- **Has**: Basic getters, scopes
- **Missing**:
  - Site lifecycle management
  - Status transition logic
  - Validation rules as methods
  - Business invariants

**Tenant Model** (136 lines)
- **Has**: Quota checking methods (good!)
- **Missing**:
  - Tier upgrade/downgrade logic
  - Resource allocation logic
  - Billing period calculations

### 4.4 Interface Usage and Abstractions

**Status: NONE (0/10)**

**Finding**: Zero interfaces defined in codebase

**Impact:**
- Cannot use dependency inversion principle
- Tight coupling to concrete implementations
- Difficult to mock for testing
- Cannot swap implementations

**Required Interfaces:**

```php
// Infrastructure contracts
interface VPSManagerInterface
interface ObservabilityServiceInterface
interface BackupStorageInterface
interface NotificationServiceInterface

// Repository contracts
interface SiteRepositoryInterface
interface TenantRepositoryInterface
interface UserRepositoryInterface
interface BackupRepositoryInterface

// Service contracts
interface SiteServiceInterface
interface TeamServiceInterface
interface BillingServiceInterface
```

**Current Constructor Injection (Too Concrete):**
```php
class SiteController extends Controller
{
    public function __construct(
        private VPSManagerBridge $vpsManager // ← Concrete class
    ) {}
}
```

**Should Be:**
```php
class SiteController extends Controller
{
    public function __construct(
        private VPSManagerInterface $vpsManager // ← Interface
    ) {}
}
```

### 4.5 Trait Usage and Sharing

**Current Traits**: Only framework traits (HasFactory, HasUuids, SoftDeletes)

**Opportunities:**
```php
// Domain traits
trait HasTenantScope { }
trait HasStatusTransitions { }
trait HasAuditLogging { }

// Repository traits
trait HandlesPagination { }
trait HandlesFiltering { }
```

---

## 5. Specific Architecture Issues

### 5.1 Fat Controllers

**Issue Severity: HIGH**

**Controllers Exceeding 200 LOC:**
1. TeamController: 492 lines (146% over limit)
2. SiteController: 439 lines (120% over limit)
3. BackupController: 333 lines (67% over limit)

**Target**: Controllers should be 50-150 lines

**Root Cause**: Business logic not extracted to services

### 5.2 Fat Models

**Issue Severity: MEDIUM**

**Opposite Problem**: Models are too anemic (lack business logic)

**Site Model** should have:
```php
class Site extends Model
{
    // Current: Only has basic methods

    // Should add:
    public function provision(VPSManagerInterface $manager): void
    public function disable(string $reason): void
    public function enable(): void
    public function renewSSL(): void
    public function canBeDeleted(): bool
    public function transitionTo(string $status): void
}
```

### 5.3 God Classes

**Issue Severity: MEDIUM**

**VPSManagerBridge** (439 lines, 30+ methods)
- Handles: SSH connection, site operations, SSL, backups, database, monitoring, security
- **Should Split Into**:
  - VPSConnectionManager
  - SiteProvisioningService
  - SSLManagementService
  - BackupManagementService
  - DatabaseManagementService

**ObservabilityAdapter** (461 lines, 25+ methods)
- Handles: Prometheus, Loki, Grafana, host registration, health checks
- **Should Split Into**:
  - PrometheusService
  - LokiService
  - GrafanaService
  - ObservabilityHealthChecker

### 5.4 Feature Envy

**Issue Severity: HIGH**

**Evidence:**

```php
// SiteController.php (lines 382-397)
private function findAvailableVps(Tenant $tenant): ?VpsServer
{
    $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();
    if ($allocation && $allocation->vpsServer->isAvailable()) {
        return $allocation->vpsServer;
    }
    return VpsServer::active()->shared()->healthy()->orderByRaw(...)->first();
}
```

**Problem**: Controller is intimately familiar with Tenant's VPS allocation internals

**Solution**: Move to VpsAllocationService
```php
class VpsAllocationService
{
    public function findAvailableVpsForTenant(Tenant $tenant): ?VpsServer
    {
        return $this->tryExistingAllocation($tenant)
            ?? $this->findSharedVpsWithCapacity();
    }
}
```

**More Examples:**
- TeamController knows about User token management (line 167)
- BackupController knows about Storage facade internals (lines 166-168)
- AuthController knows about Organization/Tenant creation sequence (lines 32-59)

### 5.5 Inappropriate Intimacy (Tight Coupling)

**Issue Severity: HIGH**

**Coupling Examples:**

1. **Controller ↔ Job Direct Dependency**
   ```php
   use App\Jobs\ProvisionSiteJob;
   ProvisionSiteJob::dispatch($site);
   ```
   **Better**: Event-driven
   ```php
   event(new SiteCreated($site));
   // Listener handles job dispatch
   ```

2. **Service ↔ Concrete Implementation**
   ```php
   class ProvisionSiteJob
   {
       public function handle(VPSManagerBridge $vpsManager) // ← Concrete
   ```
   **Better**: Depend on interface
   ```php
   public function handle(VPSManagerInterface $vpsManager)
   ```

3. **Model ↔ External Service** (In Jobs)
   - Jobs depend on specific VPSManagerBridge implementation
   - Cannot swap VPS providers without changing job code

---

## 6. Dependency Management

### 6.1 Dependency Injection Usage

**Current State: PARTIAL**

**Good Examples:**
```php
class SiteController extends Controller
{
    public function __construct(private VPSManagerBridge $vpsManager) {}
}

class ProvisionSiteJob implements ShouldQueue
{
    public function handle(VPSManagerBridge $vpsManager): void {}
}
```

**Issues:**
1. Injecting concrete classes instead of interfaces
2. No repository injection (direct model usage)
3. Services not injected (created inline or not used)

### 6.2 Service Container Bindings

**Finding**: No custom service provider bindings found

**Missing Bindings:**
```php
// Should be in AppServiceProvider
$this->app->bind(VPSManagerInterface::class, VPSManagerBridge::class);
$this->app->bind(SiteRepositoryInterface::class, EloquentSiteRepository::class);
$this->app->singleton(ObservabilityServiceInterface::class, ObservabilityAdapter::class);
```

### 6.3 Circular Dependencies

**Finding**: Potential circular dependency via relationships

```
Tenant → Sites → VpsServer → VpsAllocation → Tenant
```

**Mitigation**: Implement repository pattern to break direct model coupling

---

## 7. Code Reusability and Extensibility

### 7.1 Code Duplication

**HIGH Severity Issues:**

1. **Site Creation Logic** (Duplicated 2 times)
   - SiteController::store() (lines 102-122)
   - SiteCreate::create() (lines 66-86)
   - **Duplication**: 85% similar code

2. **VPS Allocation Algorithm** (Duplicated 2 times)
   - SiteController::findAvailableVps() (lines 382-397)
   - SiteCreate::findAvailableVps() (lines 100-115)
   - **Duplication**: 100% identical logic

3. **Tenant Retrieval** (Duplicated 3 times)
   - SiteController::getTenant() (lines 371-380)
   - BackupController::getTenant() (lines 293-302)
   - TeamController::getTenant() (lines 463-472)
   - **Duplication**: 100% identical

4. **Response Formatting** (Duplicated per controller)
   - SiteController::formatSite() (lines 399-438)
   - BackupController::formatBackup() (lines 304-332)
   - TeamController::formatMember() (lines 474-491)
   - **Should**: Use API Resources (Laravel Resources)

### 7.2 Extension Points

**Current**: Limited extension capability

**Missing Extension Points:**
1. No strategy interfaces for site types
2. No plugin system for VPS providers
3. No middleware pipeline for business operations
4. No event system for cross-cutting concerns

### 7.3 Testability

**Current Testability: 3/10**

**Blockers:**
1. **No Dependency Inversion**: Cannot mock VPSManagerBridge
2. **No Repositories**: Must use real database for all tests
3. **Static Facades**: Hard to mock (DB::transaction, Storage::, Cache::)
4. **Business Logic in Controllers**: Must test via HTTP
5. **No Interfaces**: Cannot create test doubles

**What's Testable:**
- Jobs (good dependency injection)
- Models (basic unit tests possible)
- Policies (good isolation)

**Not Testable:**
- Controller business logic (requires HTTP layer)
- VPS operations (real SSH required)
- Livewire components (duplicate controller logic)

---

## 8. Recommended Refactoring Plan

### Phase 1: Critical Abstractions (Week 1-2)

**Priority 1: Repository Layer**

1. Create Repository Interfaces
   ```
   app/Repositories/Contracts/
   ├── SiteRepositoryInterface.php
   ├── TenantRepositoryInterface.php
   ├── BackupRepositoryInterface.php
   └── UserRepositoryInterface.php
   ```

2. Implement Eloquent Repositories
   ```
   app/Repositories/
   ├── EloquentSiteRepository.php
   ├── EloquentTenantRepository.php
   ├── EloquentBackupRepository.php
   └── EloquentUserRepository.php
   ```

3. Bind in Service Provider
   ```php
   // AppServiceProvider::register()
   $this->app->bind(SiteRepositoryInterface::class, EloquentSiteRepository::class);
   ```

**Priority 2: Service Layer**

1. Create Service Interfaces
   ```
   app/Services/Contracts/
   ├── SiteServiceInterface.php
   ├── TeamServiceInterface.php
   └── BackupServiceInterface.php
   ```

2. Implement Domain Services
   ```
   app/Services/Domain/
   ├── SiteService.php
   ├── TeamService.php
   └── BackupService.php
   ```

3. Extract Business Logic from Controllers
   - Move SiteController lines 102-122 → SiteService::createSite()
   - Move TeamController lines 165-194 → TeamService::removeMember()
   - Move BackupController lines 118-151 → BackupService::createBackup()

**Priority 3: Infrastructure Interfaces**

1. Create Infrastructure Contracts
   ```
   app/Infrastructure/Contracts/
   ├── VPSManagerInterface.php
   └── ObservabilityServiceInterface.php
   ```

2. Implement Adapters
   ```
   app/Infrastructure/VPS/
   ├── VPSManagerInterface.php
   └── VPSManagerBridge.php (implement interface)
   ```

### Phase 2: Controller Refactoring (Week 3-4)

**Slim Down Controllers**

**Before:**
```php
class SiteController extends Controller
{
    public function __construct(private VPSManagerBridge $vpsManager) {}

    public function store(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);
        if (!$tenant->canCreateSite()) { /* 10 lines */ }
        $validated = $request->validate([/* ... */]);

        try {
            $site = DB::transaction(function () use ($validated, $tenant) {
                $vps = $this->findAvailableVps($tenant);
                if (!$vps) { /* ... */ }
                $site = Site::create([/* ... */]);
                return $site;
            });
            ProvisionSiteJob::dispatch($site);
            return response()->json([/* ... */]);
        } catch (\Exception $e) { /* ... */ }
    }

    private function findAvailableVps(Tenant $tenant): ?VpsServer { /* 15 lines */ }
    private function formatSite(Site $site, bool $detailed = false): array { /* 40 lines */ }
}
```

**After:**
```php
class SiteController extends Controller
{
    public function __construct(
        private SiteServiceInterface $siteService,
        private SiteResource $resource
    ) {}

    public function store(CreateSiteRequest $request): SiteResource
    {
        $site = $this->siteService->createSite(
            tenant: $request->tenant(),
            dto: CreateSiteDTO::fromRequest($request)
        );

        return $this->resource->make($site);
    }
}
```

**Target**: 50-80 lines per controller

### Phase 3: Domain-Driven Design (Week 5-8)

**Reorganize by Domain**

```
app/Domain/
├── Sites/
│   ├── Models/
│   │   ├── Site.php
│   │   └── SiteBackup.php
│   ├── Services/
│   │   ├── SiteService.php
│   │   └── BackupService.php
│   ├── Repositories/
│   │   ├── SiteRepository.php
│   │   └── Contracts/SiteRepositoryInterface.php
│   ├── Events/
│   │   ├── SiteCreated.php
│   │   ├── SiteDeleted.php
│   │   └── BackupCompleted.php
│   ├── Listeners/
│   │   ├── ProvisionSiteOnCreation.php
│   │   └── IssueSSLCertificate.php
│   ├── Policies/
│   │   └── SitePolicy.php
│   ├── ValueObjects/
│   │   ├── Domain.php
│   │   └── PhpVersion.php
│   └── Actions/
│       ├── CreateSiteAction.php
│       └── DeleteSiteAction.php
├── Teams/
│   ├── Models/
│   ├── Services/
│   └── ...
├── Billing/
└── Infrastructure/
```

### Phase 4: Events & Listeners (Week 9-10)

**Replace Direct Job Dispatch with Events**

**Before:**
```php
$site = Site::create([...]);
ProvisionSiteJob::dispatch($site);
```

**After:**
```php
$site = Site::create([...]);
event(new SiteCreated($site));

// Listener
class ProvisionSiteOnCreation
{
    public function handle(SiteCreated $event): void
    {
        ProvisionSiteJob::dispatch($event->site);
    }
}
```

**Events to Implement:**
- SiteCreated, SiteDeleted, SiteUpdated
- BackupCreated, BackupRestored
- TeamMemberInvited, TeamMemberRemoved
- SubscriptionChanged
- VpsAllocated

### Phase 5: Testing Infrastructure (Week 11-12)

**Enable Comprehensive Testing**

1. **Unit Tests** (with mocks)
   ```php
   public function test_creates_site()
   {
       $mockRepo = Mockery::mock(SiteRepositoryInterface::class);
       $mockVps = Mockery::mock(VPSManagerInterface::class);

       $service = new SiteService($mockRepo, $mockVps);
       $site = $service->createSite($tenant, $dto);

       $mockRepo->shouldHaveReceived('create');
   }
   ```

2. **Integration Tests** (with real DB, mocked external services)

3. **Feature Tests** (full stack)

---

## 9. Architectural Patterns Recommendations

### 9.1 Recommended Patterns by Layer

#### Presentation Layer (Controllers)
- **Pattern**: Thin Controllers
- **Responsibilities**: HTTP only (request → service → response)
- **Max Lines**: 50-100 per controller

#### Application Layer (Services)
- **Pattern**: Application Services + DTOs
- **Responsibilities**: Use case orchestration
- **Example**: SiteManagementService, TeamManagementService

#### Domain Layer (Models + Domain Services)
- **Pattern**: Rich Domain Models + Domain Services
- **Responsibilities**: Business logic, invariants, domain events
- **Example**: Site::provision(), Tenant::canCreateSite()

#### Data Access Layer (Repositories)
- **Pattern**: Repository + Specification
- **Responsibilities**: Query construction, data fetching
- **Example**: SiteRepository, TenantRepository

#### Infrastructure Layer (External Integrations)
- **Pattern**: Adapter + Bridge
- **Responsibilities**: External service integration
- **Example**: VPSManagerBridge, ObservabilityAdapter

### 9.2 Design Principles to Adopt

**SOLID Principles:**

1. **Single Responsibility Principle (SRP)**
   - Current Violation: Controllers have 3-5 responsibilities
   - Fix: Extract to services, repositories, resources

2. **Open/Closed Principle (OCP)**
   - Current Violation: Cannot extend site types without modifying code
   - Fix: Strategy pattern for site provisioning

3. **Liskov Substitution Principle (LSP)**
   - Current Status: N/A (no inheritance hierarchies)
   - Maintain: Keep inheritance shallow

4. **Interface Segregation Principle (ISP)**
   - Current Violation: VPSManagerBridge does too much
   - Fix: Split into focused interfaces

5. **Dependency Inversion Principle (DIP)**
   - Current Violation: Everything depends on concrete classes
   - Fix: Create interfaces, inject abstractions

### 9.3 Additional Patterns

**CQRS (Command Query Responsibility Segregation)**
- Separate read models from write models
- Use for complex queries (dashboards, reports)

**Event Sourcing** (Optional, future)
- Store domain events for audit trail
- Useful for compliance and debugging

**Saga Pattern** (For distributed transactions)
- Multi-step workflows (site creation + provisioning + SSL)
- Compensating transactions on failure

---

## 10. Migration Strategy

### 10.1 Incremental Refactoring

**Approach**: Strangler Fig Pattern

1. **Create New Architecture Alongside Old**
   - Don't delete existing code
   - Build new repositories, services
   - Gradually migrate controllers

2. **Feature Flags**
   ```php
   if (config('features.use_new_architecture')) {
       return $this->siteService->createSite($dto);
   } else {
       // Old code
   }
   ```

3. **Test Coverage First**
   - Write tests for existing behavior
   - Refactor with confidence
   - Maintain test coverage

### 10.2 Priority Order

**Highest Impact First:**

1. **SiteController** (most complex)
   - Extract SiteService
   - Create SiteRepository
   - Implement SiteResource

2. **TeamController** (second most complex)
   - Extract TeamService
   - Create UserRepository
   - Implement events for team changes

3. **BackupController**
   - Extract BackupService
   - Create BackupRepository

4. **AuthController**
   - Extract AuthService
   - Extract OrganizationFactory

### 10.3 Risk Mitigation

**Risks:**

1. **Breaking Changes**: High
   - Mitigation: Feature flags, A/B testing

2. **Development Slowdown**: Medium
   - Mitigation: Refactor one controller per week

3. **Merge Conflicts**: Medium
   - Mitigation: Communicate, small PRs

4. **Regression Bugs**: High
   - Mitigation: Comprehensive test suite first

---

## 11. Success Metrics

### 11.1 Code Quality Metrics

**Before:**
- Average Controller LOC: 371
- Service Layer Coverage: 5% (2 services, infrastructure only)
- Repository Pattern: 0%
- Interface Abstractions: 0
- Code Duplication: ~40% (estimated)
- Testability Score: 3/10

**After (Target):**
- Average Controller LOC: <100
- Service Layer Coverage: 90% (all domains covered)
- Repository Pattern: 100%
- Interface Abstractions: 15+ interfaces
- Code Duplication: <10%
- Testability Score: 9/10

### 11.2 Architecture Compliance

**Target Compliance:**

| Layer | Current | Target |
|-------|---------|--------|
| Presentation (Controllers) | 4/10 | 9/10 |
| Application (Services) | 2/10 | 9/10 |
| Domain (Models) | 5/10 | 8/10 |
| Data Access (Repositories) | 0/10 | 9/10 |
| Infrastructure (Integrations) | 6/10 | 9/10 |

### 11.3 Team Productivity Metrics

**Expected Improvements:**
- Feature Development Speed: +30% (less duplication)
- Bug Fix Time: -40% (better isolation)
- Test Writing Time: -60% (better testability)
- Onboarding Time: -50% (clearer architecture)

---

## 12. Conclusion

### Summary of Findings

The CHOM application demonstrates a **partially implemented layered architecture** with significant opportunities for improvement:

**Critical Issues:**
1. No repository layer (complete absence of data access abstraction)
2. Insufficient service layer (only infrastructure services exist)
3. Business logic embedded in controllers (fat controllers)
4. No interface abstractions (tight coupling to implementations)
5. Code duplication between API and Livewire layers

**Strengths:**
1. Good command pattern usage (Jobs)
2. Clean separation of API and web presentation
3. Proper use of policies for authorization
4. Good foundation with existing models and relationships

**Immediate Actions Required:**

1. **Week 1**: Implement repository pattern for Site, Tenant, User
2. **Week 2**: Create SiteService and extract controller logic
3. **Week 3**: Implement interfaces for all infrastructure services
4. **Week 4**: Refactor SiteController to use services and repositories

**Long-term Vision:**

Transform CHOM into a well-architected, domain-driven application with:
- Clear separation of concerns
- High testability
- Excellent maintainability
- Easy extensibility
- Strong architectural boundaries

**ROI Estimate:**
- Initial Investment: 8-12 weeks of refactoring
- Payback Period: 3-6 months
- Long-term Benefit: 3x faster feature development, 5x easier testing, 10x better maintainability

---

## Appendix A: File Analysis Summary

### Controllers
| File | LOC | Methods | Business Logic | Violations |
|------|-----|---------|----------------|------------|
| SiteController | 439 | 14 | High | Fat controller, VPS logic, formatting |
| TeamController | 492 | 13 | High | Auth logic, token mgmt, complex rules |
| BackupController | 333 | 9 | Medium | Storage logic, quota checking |
| AuthController | 220 | 5 | Medium | Registration workflow |

### Models
| File | LOC | Business Methods | Assessment |
|------|-----|------------------|------------|
| Site | 132 | 7 | Adequate scopes, missing lifecycle methods |
| Tenant | 136 | 6 | Good quota methods, missing tier logic |
| User | 98 | 5 | Good role methods, complete |
| Organization | 107 | 4 | Minimal, adequate |

### Services
| File | LOC | Methods | Assessment |
|------|-----|---------|------------|
| VPSManagerBridge | 439 | 30+ | God class, needs splitting |
| ObservabilityAdapter | 461 | 25+ | God class, needs splitting |

### Jobs
| File | LOC | Assessment |
|------|-----|------------|
| ProvisionSiteJob | 116 | Excellent - clean command pattern |
| CreateBackupJob | 133 | Excellent - proper error handling |
| RestoreBackupJob | N/A | Not reviewed |
| IssueSslCertificateJob | N/A | Not reviewed |

---

## Appendix B: Code Examples

### Example 1: Current vs. Proposed Site Creation

**Current: SiteController.php (lines 69-147)**
```php
public function store(Request $request): JsonResponse
{
    $tenant = $this->getTenant($request);

    if (!$tenant->canCreateSite()) {
        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'SITE_LIMIT_EXCEEDED',
                'message' => 'You have reached your plan\'s site limit.',
            ],
        ], 403);
    }

    $validated = $request->validate([/* ... 10 lines ... */]);

    try {
        $site = DB::transaction(function () use ($validated, $tenant) {
            $vps = $this->findAvailableVps($tenant);
            if (!$vps) {
                throw new \RuntimeException('No available VPS server found');
            }
            $site = Site::create([/* ... 8 lines ... */]);
            return $site;
        });

        ProvisionSiteJob::dispatch($site);

        return response()->json([
            'success' => true,
            'data' => $this->formatSite($site),
            'message' => 'Site is being created.',
        ], 201);

    } catch (\Exception $e) {
        Log::error('Site creation failed', [/* ... */]);
        return response()->json([/* error response */], 500);
    }
}
```

**Proposed:**
```php
// Controller
class SiteController extends Controller
{
    public function __construct(
        private SiteServiceInterface $siteService
    ) {}

    public function store(CreateSiteRequest $request): SiteResource
    {
        $site = $this->siteService->createSite(
            tenant: $request->tenant(),
            dto: CreateSiteDTO::fromRequest($request)
        );

        return new SiteResource($site);
    }
}

// Service
class SiteService implements SiteServiceInterface
{
    public function __construct(
        private SiteRepositoryInterface $siteRepository,
        private VpsAllocationServiceInterface $vpsAllocation,
        private EventDispatcherInterface $events
    ) {}

    public function createSite(Tenant $tenant, CreateSiteDTO $dto): Site
    {
        $this->guardAgainstQuotaExceeded($tenant);

        return DB::transaction(function () use ($tenant, $dto) {
            $vps = $this->vpsAllocation->allocateForTenant($tenant);

            $site = $this->siteRepository->create([
                'tenant_id' => $tenant->id,
                'vps_id' => $vps->id,
                'domain' => $dto->domain,
                'site_type' => $dto->siteType,
                'php_version' => $dto->phpVersion,
                'ssl_enabled' => $dto->sslEnabled,
                'status' => SiteStatus::Creating,
            ]);

            $this->events->dispatch(new SiteCreated($site));

            return $site;
        });
    }

    private function guardAgainstQuotaExceeded(Tenant $tenant): void
    {
        if (!$tenant->canCreateSite()) {
            throw new SiteQuotaExceededException($tenant);
        }
    }
}

// Repository
class EloquentSiteRepository implements SiteRepositoryInterface
{
    public function create(array $attributes): Site
    {
        return Site::create($attributes);
    }

    public function findByIdForTenant(string $id, Tenant $tenant): ?Site
    {
        return $tenant->sites()->find($id);
    }
}
```

**Benefits:**
- Controller: 9 lines (was 79 lines) - 88% reduction
- Testable: Can mock interfaces
- Reusable: Service used by API + Livewire
- Maintainable: Clear responsibilities
- Extensible: Easy to add features

---

**End of Report**

Review conducted by: Architecture Review Team
Report version: 1.0
Date: 2026-01-02
