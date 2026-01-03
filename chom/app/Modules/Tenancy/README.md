# Multi-Tenancy Module

## Overview

The Multi-Tenancy module is a bounded context responsible for managing multi-tenant operations within the CHOM application. It handles tenant resolution, organization management, tenant switching, and enforces strict data isolation between tenants.

## Responsibilities

- Tenant identification and resolution
- Organization (tenant) lifecycle management
- Tenant context switching
- Data isolation enforcement
- Multi-tenant access control

## Architecture

### Service Contracts

- `TenantResolverInterface` - Tenant resolution and management operations

### Services

- `TenantService` - Implements tenant resolution and management logic

### Middleware

- `EnforceTenantIsolation` - Ensures all requests are properly scoped to current tenant

### Events

- `TenantSwitched` - Dispatched when user switches tenant context
- `OrganizationCreated` - Dispatched when new organization is created

## Usage Examples

### Tenant Resolution

```php
use App\Modules\Tenancy\Contracts\TenantResolverInterface;

$tenantService = app(TenantResolverInterface::class);

// Resolve current tenant
$tenant = $tenantService->resolve();

// Get current tenant ID
$tenantId = $tenantService->getCurrentTenantId();
```

### Organization Management

```php
// Create new organization
$organization = $tenantService->createOrganization([
    'name' => 'Acme Corp',
    'tier' => 'professional',
    'settings' => ['timezone' => 'UTC']
], $ownerId);

// Switch tenant context
$tenantService->switchTenant($newTenantId, $userId);
```

### Tenant Isolation

```php
// Apply tenant scope to query
$query = Site::query();
$scopedQuery = $tenantService->scopeToTenant($query);
$sites = $scopedQuery->get(); // Only returns sites for current tenant
```

### Middleware Usage

```php
// In routes/api.php
Route::middleware(['auth', 'tenant.isolation'])->group(function () {
    Route::get('/sites', [SiteController::class, 'index']);
});
```

## Data Isolation Strategy

This module implements a shared database, discriminator column strategy:

1. All tenant-specific tables have a `tenant_id` column
2. Queries are automatically scoped using the `scopeToTenant` method
3. Middleware enforces tenant context on all protected routes
4. Cross-tenant access attempts are logged and rejected

## Module Dependencies

- User model and repository
- Organization (Tenant) model and repository
- Laravel authentication system

## Security Considerations

1. All queries must be scoped to current tenant
2. Tenant switching requires user membership verification
3. Inactive tenants are rejected at middleware level
4. All tenant operations are logged for auditing
5. Cross-tenant data access is prevented at multiple layers

## Testing

Test the module using:

```bash
php artisan test --filter=Tenancy
```

## Future Enhancements

- Tenant-level feature flags
- Resource quotas per tenant
- Tenant analytics and metrics
- Multi-database tenant isolation option
- Tenant data export capabilities
