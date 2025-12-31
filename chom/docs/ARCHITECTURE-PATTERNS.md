# Architecture Design Patterns Implementation

This document describes the critical design patterns implemented to fix architectural issues and improve code maintainability, following SOLID principles.

## Overview

The following design patterns have been implemented to address architectural issues:

1. **Strategy Pattern** for site provisioning
2. **Facade Pattern** with service decomposition for VPSManagerBridge
3. **Adapter Pattern** with focused services for observability
4. **Repository Pattern** for complex data access
5. **Trait Extraction** for shared controller logic
6. **Value Objects** for domain primitives
7. **Custom Validation Rules** for data integrity

## 1. Strategy Pattern for Site Provisioning

### Problem
The original `ProvisionSiteJob` used a hard-coded `match` statement, violating the Open/Closed Principle. Adding new site types required modifying existing code.

### Solution
Implemented the Strategy Pattern with:

- **Interface**: `SiteProvisionerInterface` - Defines the contract for all provisioners
- **Concrete Strategies**:
  - `WordPressSiteProvisioner` - WordPress site provisioning logic
  - `HtmlSiteProvisioner` - Static HTML site provisioning logic
  - `LaravelSiteProvisioner` - Laravel application provisioning logic
- **Factory**: `ProvisionerFactory` - Creates appropriate provisioner based on site type

### Benefits
- **Open/Closed Principle**: New site types can be added without modifying existing code
- **Single Responsibility**: Each provisioner handles only one site type
- **Testability**: Each provisioner can be tested independently
- **Extensibility**: Adding support for new site types only requires:
  1. Creating a new provisioner class
  2. Adding it to the factory map

### Usage Example

```php
// In ProvisionSiteJob
$provisioner = $provisionerFactory->make($site->site_type);

if (!$provisioner->validate($site)) {
    throw new \InvalidArgumentException("Invalid site configuration");
}

$result = $provisioner->provision($site, $vps);
```

### File Locations
- `/app/Contracts/SiteProvisionerInterface.php`
- `/app/Services/Sites/Provisioners/WordPressSiteProvisioner.php`
- `/app/Services/Sites/Provisioners/HtmlSiteProvisioner.php`
- `/app/Services/Sites/Provisioners/LaravelSiteProvisioner.php`
- `/app/Services/Sites/Provisioners/ProvisionerFactory.php`
- `/app/Jobs/ProvisionSiteJob.php` (refactored)

## 2. VPSManagerBridge Decomposition

### Problem
The original `VPSManagerBridge` was a God Class with 439 lines handling multiple responsibilities:
- SSH connection management
- Command execution
- Site management
- SSL management
- Backup operations
- Database operations

### Solution
Split into focused, single-responsibility classes:

#### **VpsConnectionManager**
Handles SSH connections only.

**Responsibilities**:
- Establish SSH connections
- Manage connection lifecycle
- Validate SSH key permissions
- Test connections

#### **VpsCommandExecutor**
Executes commands on VPS servers.

**Responsibilities**:
- Build and execute VPSManager commands
- Parse JSON output
- Validate and execute whitelisted raw commands
- Security validation

#### **VpsSiteManager**
Manages site operations.

**Responsibilities**:
- Create sites (WordPress, HTML, Laravel)
- Delete, enable, disable sites
- List sites and get site information
- Clear site cache

#### **VpsSslManager**
Manages SSL certificates.

**Responsibilities**:
- Issue SSL certificates
- Renew SSL certificates
- Get SSL status

#### **VPSManagerBridgeRefactored** (Facade)
Coordinates the specialized services and maintains backward compatibility.

### Benefits
- **Single Responsibility Principle**: Each class has one reason to change
- **Dependency Inversion**: Services depend on abstractions (injected dependencies)
- **Testability**: Each service can be mocked and tested independently
- **Maintainability**: Changes to one concern don't affect others
- **Reusability**: Services can be used independently without the full bridge

### File Locations
- `/app/Services/VPS/VpsConnectionManager.php`
- `/app/Services/VPS/VpsCommandExecutor.php`
- `/app/Services/VPS/VpsSiteManager.php`
- `/app/Services/VPS/VpsSslManager.php`
- `/app/Services/Integration/VPSManagerBridgeRefactored.php`

## 3. ObservabilityAdapter Decomposition

### Problem
The original `ObservabilityAdapter` handled three different observability systems in one class:
- Prometheus (metrics)
- Loki (logs)
- Grafana (dashboards)

### Solution
Split into focused adapters:

#### **PrometheusAdapter**
Handles Prometheus metrics queries.

**Responsibilities**:
- Query metrics with tenant scoping
- Query metric ranges
- Get active alerts
- Calculate bandwidth and disk usage
- Escape PromQL to prevent injection

#### **LokiAdapter**
Handles Loki log queries.

**Responsibilities**:
- Query logs with tenant isolation
- Search logs
- Get site-specific logs
- Escape LogQL to prevent injection

#### **GrafanaAdapter**
Handles Grafana dashboard operations.

**Responsibilities**:
- List and get dashboards
- Create and update dashboards
- Generate embedded dashboard URLs
- Delete dashboards

#### **ObservabilityAdapterRefactored** (Coordinator)
Facade that delegates to specialized adapters.

### Benefits
- **Separation of Concerns**: Each adapter handles one observability system
- **Single Responsibility**: Changes to Prometheus don't affect Loki or Grafana
- **Testability**: Each adapter can be tested with its own mocked dependencies
- **Security**: Injection prevention is isolated per query language

### File Locations
- `/app/Services/Observability/PrometheusAdapter.php`
- `/app/Services/Observability/LokiAdapter.php`
- `/app/Services/Observability/GrafanaAdapter.php`
- `/app/Services/Integration/ObservabilityAdapterRefactored.php`

## 4. Repository Pattern

### Problem
Complex queries and data access logic scattered throughout controllers and services.

### Solution
Implemented repositories for complex data operations:

#### **SiteRepository**
Handles site-related queries.

**Methods**:
- `getActiveForTenant()` - Get active sites for a tenant
- `getStorageStatsByTenant()` - Calculate storage statistics
- `findAvailableVpsServers()` - Find VPS servers with capacity
- `getSitesWithExpiringSsl()` - Get sites with expiring SSL
- `countByStatusForTenant()` - Count sites by status
- `searchByDomain()` - Search sites by domain

#### **UsageRecordRepository**
Handles usage tracking and billing calculations.

**Methods**:
- `getByTenantAndPeriod()` - Get usage records for period
- `calculateBillingTotals()` - Calculate billing totals
- `getUsageSummaryByType()` - Get usage summary by resource type
- `getDailyAggregates()` - Get daily usage aggregates
- `getUsageTrend()` - Compare current to previous period
- `exceedsQuota()` - Check if tenant exceeds quota

### Benefits
- **Separation of Concerns**: Data access logic separated from business logic
- **Reusability**: Complex queries can be reused across the application
- **Testability**: Repositories can be mocked for testing
- **Maintainability**: Database changes are isolated to repositories
- **Performance**: Query optimization centralized in one place

### File Locations
- `/app/Repositories/SiteRepository.php`
- `/app/Repositories/UsageRecordRepository.php`

## 5. Controller Trait Extraction

### Problem
Duplicate `getTenant()` method across multiple controllers:
- `SiteController`
- `BackupController`
- `TeamController`

### Solution
Created `HasTenantScoping` trait with shared functionality.

**Provides**:
- `getTenant()` - Get current tenant from request
- `getTenantId()` - Get current tenant ID
- `tenantCan()` - Check tenant permissions
- `belongsToTenant()` - Verify resource ownership

### Benefits
- **DRY Principle**: Eliminates code duplication
- **Consistency**: Ensures uniform tenant scoping behavior
- **Maintainability**: Changes to tenant scoping logic in one place
- **Reusability**: Easily add tenant scoping to new controllers

### File Locations
- `/app/Http/Controllers/Concerns/HasTenantScoping.php`
- Updated: `SiteController`, `BackupController`, `TeamController`

## 6. Value Objects

### Problem
Domain primitives (domains, IP addresses) treated as primitive strings without validation or behavior.

### Solution
Implemented immutable value objects:

#### **Domain Value Object**
Represents a valid domain name.

**Features**:
- Format validation
- SQL injection detection
- Reserved domain detection
- TLD extraction
- Subdomain detection
- Immutability

#### **IpAddress Value Object**
Represents a valid IP address (IPv4/IPv6).

**Features**:
- IPv4 and IPv6 support
- Public/private detection
- Subnet checking
- Version detection
- Localhost prevention
- Immutability

### Benefits
- **Domain-Driven Design**: Models domain concepts explicitly
- **Validation**: Ensures data validity at creation
- **Immutability**: Prevents accidental modifications
- **Behavior**: Encapsulates domain logic with the data
- **Type Safety**: Prevents mixing domain names with other strings

### File Locations
- `/app/Domain/ValueObjects/Domain.php`
- `/app/Domain/ValueObjects/IpAddress.php`

## 7. Custom Validation Rules

### Problem
Complex validation logic embedded in controllers and form requests.

### Solution
Created reusable validation rules:

#### **ValidDomain**
Validates domain format using the Domain value object.

**Features**:
- Domain format validation
- SQL injection detection
- Suspicious pattern logging

#### **ValidSiteType**
Validates site type against supported provisioners.

**Features**:
- Extensible (automatically supports new provisioners)
- Clear error messages
- Integration with ProvisionerFactory

#### **ValidIpAddress**
Validates IP addresses using the IpAddress value object.

**Features**:
- IPv4/IPv6 validation
- Public/private IP filtering
- Version-specific validation
- Static factory methods (`publicOnly()`, `ipv4Only()`, `ipv6Only()`)

### Benefits
- **Reusability**: Rules can be used across multiple requests
- **Consistency**: Same validation logic everywhere
- **Separation of Concerns**: Validation logic separated from controllers
- **Extensibility**: New rules can be added easily

### File Locations
- `/app/Rules/ValidDomain.php`
- `/app/Rules/ValidSiteType.php`
- `/app/Rules/ValidIpAddress.php`

## Migration Strategy

To migrate to the new architecture:

### 1. Update Service Provider Bindings

```php
// In AppServiceProvider
use App\Services\VPS\VpsConnectionManager;
use App\Services\VPS\VpsCommandExecutor;
use App\Services\VPS\VpsSiteManager;
use App\Services\VPS\VpsSslManager;

public function register(): void
{
    // Register VPS services
    $this->app->singleton(VpsConnectionManager::class);
    $this->app->singleton(VpsCommandExecutor::class);
    $this->app->singleton(VpsSiteManager::class);
    $this->app->singleton(VpsSslManager::class);

    // Bind the refactored bridge
    $this->app->bind(
        VPSManagerBridge::class,
        VPSManagerBridgeRefactored::class
    );
}
```

### 2. Update Validation Rules

```php
// In site creation request
public function rules(): array
{
    return [
        'domain' => [
            'required',
            new ValidDomain(),
            Rule::unique('sites')->where('tenant_id', $this->user()->currentTenant()->id),
        ],
        'site_type' => ['required', new ValidSiteType(app(ProvisionerFactory::class))],
        'ip_address' => ['sometimes', ValidIpAddress::publicOnly()],
    ];
}
```

### 3. Use Repositories

```php
// In controllers or services
use App\Repositories\SiteRepository;

class SomeService
{
    public function __construct(
        private SiteRepository $siteRepository
    ) {}

    public function getActiveSites(Tenant $tenant)
    {
        return $this->siteRepository->getActiveForTenant($tenant);
    }
}
```

## Testing

Comprehensive tests included:

### Unit Tests
- `/tests/Unit/Domain/ValueObjects/DomainTest.php` - Domain value object tests
- `/tests/Unit/Services/ProvisionerFactoryTest.php` - Factory pattern tests

### Test Coverage
- Value object validation
- Factory pattern creation
- Provisioner behavior
- Rule validation

### Running Tests

```bash
# Run all tests
php artisan test

# Run specific test file
php artisan test tests/Unit/Domain/ValueObjects/DomainTest.php

# Run with coverage
php artisan test --coverage
```

## Performance Improvements

### Before
- N+1 queries in VPS allocation
- Complex subqueries in site listing
- Duplicate tenant scope validation

### After
- Repository pattern with optimized queries
- Query builder with `withCount()` for efficiency
- Shared trait for consistent tenant scoping

## Security Improvements

1. **SQL Injection Prevention**: Value objects validate and reject suspicious patterns
2. **PromQL/LogQL Injection Prevention**: Adapters escape query parameters
3. **SSH Command Whitelist**: Only allowed commands can be executed
4. **Tenant Isolation**: Consistent tenant scoping via trait
5. **Audit Logging**: Suspicious validation attempts are logged

## SOLID Principles Compliance

### Single Responsibility Principle (SRP)
- Each class has one reason to change
- VPS services split by concern
- Observability adapters split by system
- Repositories handle only data access

### Open/Closed Principle (OCP)
- Strategy pattern allows adding site types without modification
- Validation rules are extensible
- Factory pattern makes system open for extension

### Liskov Substitution Principle (LSP)
- All provisioners implement the same interface
- Value objects are interchangeable
- Adapters can be swapped

### Interface Segregation Principle (ISP)
- Small, focused interfaces (SiteProvisionerInterface)
- Clients depend only on methods they use
- No fat interfaces

### Dependency Inversion Principle (DIP)
- High-level modules depend on abstractions (interfaces)
- Dependencies injected via constructor
- No direct instantiation of concrete classes

## Conclusion

These architectural improvements provide:

1. **Better Maintainability**: Code is easier to understand and modify
2. **Improved Testability**: Components can be tested in isolation
3. **Enhanced Extensibility**: New features can be added with minimal changes
4. **Stronger Type Safety**: Value objects prevent invalid data
5. **Better Security**: Input validation and injection prevention
6. **SOLID Compliance**: Adherence to software design principles

The refactored architecture is production-ready and follows industry best practices for enterprise Laravel applications.
