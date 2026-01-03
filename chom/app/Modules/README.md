# CHOM Application Modules

## Overview

The CHOM application is organized into six bounded contexts following Domain-Driven Design (DDD) principles. Each module represents a distinct business domain with clear boundaries, responsibilities, and contracts.

## Module Architecture

```
app/Modules/
├── Auth/                    # Identity & Access Module
├── Tenancy/                 # Multi-Tenancy Module
├── SiteHosting/             # Site Hosting Module
├── Backup/                  # Backup Module
├── Team/                    # Team Collaboration Module
└── Infrastructure/          # Infrastructure Services Module
```

## Bounded Contexts

### 1. Identity & Access Module (Auth/)

**Purpose:** User authentication, authorization, and security

**Responsibilities:**
- User authentication (login/logout)
- Two-factor authentication (2FA)
- Password management
- Session management

**Key Contracts:**
- `AuthenticationInterface` - Core authentication operations
- `TwoFactorInterface` - 2FA operations

**Value Objects:**
- `TwoFactorSecret` - Encapsulates 2FA secret data

[Full Documentation](Auth/README.md)

---

### 2. Multi-Tenancy Module (Tenancy/)

**Purpose:** Tenant isolation and organization management

**Responsibilities:**
- Tenant identification and resolution
- Organization lifecycle management
- Tenant context switching
- Data isolation enforcement

**Key Contracts:**
- `TenantResolverInterface` - Tenant resolution and management

**Middleware:**
- `EnforceTenantIsolation` - Ensures proper tenant scoping

[Full Documentation](Tenancy/README.md)

---

### 3. Site Hosting Module (SiteHosting/)

**Purpose:** Website provisioning and management

**Responsibilities:**
- Site provisioning and deployment
- PHP version management
- SSL certificate management
- Site lifecycle operations
- Site metrics and monitoring

**Key Contracts:**
- `SiteProvisionerInterface` - Site provisioning operations

**Value Objects:**
- `PhpVersion` - Type-safe PHP version handling
- `SslCertificate` - SSL certificate data and validation

[Full Documentation](SiteHosting/README.md)

---

### 4. Backup Module (Backup/)

**Purpose:** Data backup and restoration

**Responsibilities:**
- Backup creation (full/files/database)
- Backup restoration
- Automated backup scheduling
- Retention policy enforcement
- Integrity validation

**Key Contracts:**
- `BackupStorageInterface` - Backup storage operations

**Value Objects:**
- `BackupConfiguration` - Backup settings and options
- `RetentionPolicy` - Retention rules and cleanup logic

[Full Documentation](Backup/README.md)

---

### 5. Team Collaboration Module (Team/)

**Purpose:** Team member management and collaboration

**Responsibilities:**
- Team member invitations
- Role and permission management
- Team member removal
- Ownership transfer

**Key Contracts:**
- `InvitationInterface` - Team invitation operations

**Value Objects:**
- `TeamRole` - Role hierarchy and validation
- `Permission` - Granular permission handling

[Full Documentation](Team/README.md)

---

### 6. Infrastructure Services Module (Infrastructure/)

**Purpose:** Core infrastructure operations

**Responsibilities:**
- VPS server management
- System monitoring and observability
- Multi-channel notifications
- File storage operations

**Key Contracts:**
- `VpsProviderInterface` - VPS management
- `ObservabilityInterface` - Monitoring and metrics
- `NotificationInterface` - Notification delivery
- `StorageInterface` - File storage

**Value Objects:**
- `VpsSpecification` - VPS server specifications

[Full Documentation](Infrastructure/README.md)

---

## Module Principles

### 1. Clear Boundaries

Each module has well-defined boundaries and owns its domain logic. Modules communicate through:
- **Contracts (Interfaces):** Define clear service boundaries
- **Events:** Enable loose coupling between modules
- **Value Objects:** Ensure type safety and domain consistency

### 2. Dependency Direction

Modules follow these dependency rules:

```
Application Layer (Controllers, Jobs)
         ↓
    Module Layer
         ↓
  Domain Services
         ↓
    Repositories
         ↓
      Models
```

**Cross-module communication:**
- Use contracts/interfaces (dependency injection)
- Use events for async communication
- Never access another module's internals directly

### 3. Self-Contained Modules

Each module is designed to be extractable into a standalone package:

```
Module/
├── ModuleServiceProvider.php    # Service registration
├── Contracts/                    # Public interfaces
├── Services/                     # Business logic
├── Events/                       # Domain events
├── Listeners/                    # Event handlers
├── ValueObjects/                 # Domain value objects
├── Middleware/                   # Module-specific middleware
└── README.md                     # Module documentation
```

### 4. Integration with Existing Code

Modules wrap existing services using the **Orchestrator Pattern:**

```php
// Existing service (preserved)
class SiteManagementService { ... }

// Module orchestrator (new)
class SiteProvisioningService implements SiteProvisionerInterface {
    public function __construct(
        private readonly SiteManagementService $siteManagementService
    ) {}

    public function provision(array $data, string $tenantId): Site {
        return $this->siteManagementService->provisionSite($data, $tenantId);
    }
}
```

This approach:
- Maintains backward compatibility
- Adds module context and logging
- Implements value objects for type safety
- Provides clean module boundaries

## Module Registration

All modules are registered in `App\Providers\ModuleServiceProvider`:

```php
protected array $moduleProviders = [
    AuthServiceProvider::class,
    TenancyServiceProvider::class,
    SiteHostingServiceProvider::class,
    BackupServiceProvider::class,
    TeamServiceProvider::class,
    InfrastructureServiceProvider::class,
];
```

To enable modules, register the `ModuleServiceProvider` in `bootstrap/providers.php` (Laravel 11+) or `config/app.php`:

```php
return [
    App\Providers\ModuleServiceProvider::class,
];
```

## Usage Examples

### Dependency Injection

```php
use App\Modules\SiteHosting\Contracts\SiteProvisionerInterface;
use App\Modules\Backup\Services\BackupOrchestrator;

class SiteController extends Controller
{
    public function __construct(
        private readonly SiteProvisionerInterface $siteProvisioner,
        private readonly BackupOrchestrator $backupOrchestrator
    ) {}

    public function provision(Request $request)
    {
        $site = $this->siteProvisioner->provision(
            $request->validated(),
            auth()->user()->organization_id
        );

        return response()->json($site);
    }
}
```

### Facades (Optional)

Create facades for frequently used services:

```php
// app/Facades/Tenant.php
class Tenant extends Facade
{
    protected static function getFacadeAccessor()
    {
        return TenantResolverInterface::class;
    }
}

// Usage
$tenantId = Tenant::getCurrentTenantId();
```

### Events and Listeners

Modules communicate via events:

```php
// SiteHosting module dispatches event
Event::dispatch(new SiteProvisioned($site));

// Team module listens
class NotifyTeamOfNewSite
{
    public function handle(SiteProvisioned $event)
    {
        // Notify team members
    }
}
```

## Testing Modules

Each module can be tested independently:

```bash
# Test specific module
php artisan test --filter=Auth
php artisan test --filter=Tenancy
php artisan test --filter=SiteHosting
php artisan test --filter=Backup
php artisan test --filter=Team
php artisan test --filter=Infrastructure

# Test all modules
php artisan test
```

## Module Dependencies

```
Infrastructure
     ↑
     |
Auth ← Tenancy → SiteHosting → Backup
     ↓               ↓
   Team ← ← ← ← ← ← ←
```

**Dependency Guidelines:**
- Auth has no dependencies (core module)
- Tenancy depends on Auth
- SiteHosting depends on Tenancy and Infrastructure
- Backup depends on SiteHosting and Infrastructure
- Team depends on Auth and Tenancy
- Infrastructure is a shared kernel (minimal dependencies)

## Adding New Modules

To add a new module:

1. **Create module directory:**
   ```bash
   mkdir -p app/Modules/NewModule/{Contracts,Services,Events,ValueObjects}
   ```

2. **Create ServiceProvider:**
   ```php
   namespace App\Modules\NewModule;

   class NewModuleServiceProvider extends ServiceProvider
   {
       public function register(): void
       {
           $this->app->singleton(ContractInterface::class, Service::class);
       }
   }
   ```

3. **Register in ModuleServiceProvider:**
   ```php
   protected array $moduleProviders = [
       // ...
       NewModuleServiceProvider::class,
   ];
   ```

4. **Document the module:**
   Create `app/Modules/NewModule/README.md`

## Best Practices

### DO:
- Define clear contracts for module boundaries
- Use value objects for domain concepts
- Dispatch events for cross-module communication
- Keep modules focused on single responsibility
- Document module purpose and usage
- Write comprehensive tests for each module

### DON'T:
- Access another module's internals directly
- Create circular dependencies between modules
- Mix business logic across modules
- Skip contract definitions
- Forget to register service providers
- Use placeholders or TODO comments in production code

## Migration Path

To migrate existing code to modules:

1. **Identify domain boundaries** (already done)
2. **Create module structure** (completed)
3. **Define contracts** (completed)
4. **Implement orchestrators** (completed)
5. **Update controllers to use contracts** (next step)
6. **Migrate tests** (ongoing)
7. **Refactor existing services gradually** (iterative)

## Future Enhancements

Potential module additions:
- **Billing Module** - Subscription and payment management
- **Analytics Module** - Metrics and reporting
- **API Module** - Third-party API integrations
- **Notification Module** - Advanced notification routing
- **Security Module** - Security scanning and compliance

## Support

For questions or issues with modules:
1. Check module-specific README files
2. Review module contracts for available operations
3. Check event documentation for integration points
4. Refer to usage examples in this document

---

**Last Updated:** 2026-01-03
**Module Count:** 6
**Status:** Production Ready
