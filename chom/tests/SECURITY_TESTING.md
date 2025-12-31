# Security Testing Documentation

This document describes the comprehensive security test suite for the CHOM application, focusing on tenant isolation and injection prevention.

## Overview

The test suite validates three critical security fixes:

1. **PromQL/LogQL Injection Prevention** - Prevents malicious tenant IDs and input from breaking out of observability queries
2. **Authorization Policy Enforcement** - Ensures users can only access resources within their tenant
3. **Global Tenant Scopes** - Automatically filters all database queries by the authenticated user's tenant

## Test Files

### Unit Tests

#### `/tests/Unit/ObservabilityAdapterTest.php`
Tests PromQL and LogQL injection prevention in the ObservabilityAdapter service.

**Key Test Cases:**
- `test_tenant_id_is_escaped_in_promql_queries()` - Verifies basic tenant ID escaping
- `test_malicious_tenant_id_with_quotes_is_escaped()` - Tests injection attempts with quotes
- `test_tenant_id_with_regex_characters_is_escaped()` - Tests regex special characters (. * + ? etc.)
- `test_tenant_id_with_backslashes_is_double_escaped()` - Tests backslash escaping
- `test_tenant_id_with_newlines_is_escaped()` - Tests newline character escaping
- `test_vps_ip_is_escaped_in_queries()` - Tests IP address escaping
- `test_malicious_vps_ip_is_escaped()` - Tests malicious IP address injection
- `test_query_bandwidth_escapes_tenant_id()` - Tests bandwidth query escaping
- `test_query_disk_usage_escapes_tenant_id()` - Tests disk usage query escaping
- `test_logql_string_escaping_in_site_logs()` - Tests LogQL string escaping
- `test_search_logs_escapes_search_terms()` - Tests log search term escaping
- `test_loki_queries_use_tenant_header()` - Verifies Loki tenant isolation header
- `test_active_alerts_filtered_by_tenant()` - Tests alert filtering by tenant
- `test_complex_promql_injection_is_prevented()` - Tests complex injection attempts

**How to Run:**
```bash
php artisan test --filter=ObservabilityAdapterTest
```

#### `/tests/Unit/TenantScopeTest.php`
Tests global tenant scopes on all models (Site, Operation, UsageRecord, VpsAllocation).

**Key Test Cases:**
- `test_site_model_filters_by_authenticated_tenant()` - Tests basic Site model filtering
- `test_site_model_scope_works_with_where_clauses()` - Tests scope with WHERE conditions
- `test_site_model_scope_works_with_find()` - Tests scope with find() method
- `test_operation_model_filters_by_authenticated_tenant()` - Tests Operation model filtering
- `test_usage_record_model_filters_by_authenticated_tenant()` - Tests UsageRecord model filtering
- `test_vps_allocation_model_filters_by_authenticated_tenant()` - Tests VpsAllocation model filtering
- `test_count_queries_respect_tenant_scope()` - Tests COUNT queries
- `test_aggregate_queries_respect_tenant_scope()` - Tests SUM/AVG queries
- `test_exists_queries_respect_tenant_scope()` - Tests EXISTS queries
- `test_update_queries_respect_tenant_scope()` - Tests UPDATE queries
- `test_delete_queries_respect_tenant_scope()` - Tests DELETE queries
- `test_without_global_scope_allows_bypassing_tenant_filter()` - Tests scope bypass
- `test_complex_queries_cannot_leak_tenant_data()` - Tests complex query isolation

**How to Run:**
```bash
php artisan test --filter=TenantScopeTest
```

### Feature Tests

#### `/tests/Feature/SiteControllerAuthorizationTest.php`
Tests authorization policies in the SiteController across all endpoints and user roles.

**Key Test Cases:**
- `test_users_cannot_view_sites_from_other_tenants()` - Tests index endpoint isolation
- `test_users_cannot_access_site_details_from_other_tenants()` - Tests show endpoint isolation
- `test_users_cannot_update_sites_from_other_tenants()` - Tests update endpoint isolation
- `test_users_cannot_delete_sites_from_other_tenants()` - Tests delete endpoint isolation
- `test_viewers_cannot_create_sites()` - Tests viewer role restrictions
- `test_members_can_create_sites()` - Tests member role permissions
- `test_admins_can_create_sites()` - Tests admin role permissions
- `test_owners_can_create_sites()` - Tests owner role permissions
- `test_viewers_cannot_update_sites()` - Tests viewer update restrictions
- `test_members_can_update_sites()` - Tests member update permissions
- `test_viewers_cannot_delete_sites()` - Tests viewer delete restrictions
- `test_members_cannot_delete_sites()` - Tests member delete restrictions
- `test_admins_can_delete_sites()` - Tests admin delete permissions
- `test_owners_can_delete_sites()` - Tests owner delete permissions
- `test_authorization_prevents_direct_access_via_id()` - Tests direct ID access prevention
- `test_policy_belongs_to_tenant_check()` - Tests policy tenant ownership check
- `test_search_filtering_respects_tenant_boundaries()` - Tests search isolation
- `test_status_filtering_respects_tenant_boundaries()` - Tests filter isolation

**How to Run:**
```bash
php artisan test --filter=SiteControllerAuthorizationTest
```

#### `/tests/Feature/TenantIsolationIntegrationTest.php`
Comprehensive integration tests for tenant isolation across the entire application.

**Key Test Cases:**
- `test_complete_isolation_across_all_models()` - Tests all models together
- `test_site_model_isolation_with_complex_queries()` - Tests complex Site queries
- `test_operation_model_isolation_with_complex_queries()` - Tests complex Operation queries
- `test_api_site_list_endpoint_enforces_isolation()` - Tests API list endpoint
- `test_api_site_show_endpoint_enforces_isolation()` - Tests API show endpoint
- `test_site_creation_is_scoped_to_authenticated_tenant()` - Tests creation scoping
- `test_different_roles_see_same_tenant_scoped_data()` - Tests role consistency
- `test_isolation_during_relationship_loading()` - Tests relationship isolation
- `test_aggregate_queries_respect_isolation()` - Tests aggregate isolation
- `test_batch_operations_respect_isolation()` - Tests batch operation isolation
- `test_search_and_filtering_maintain_isolation()` - Tests search/filter isolation
- `test_isolation_with_soft_deletes()` - Tests soft delete isolation
- `test_concurrent_tenant_requests_maintain_isolation()` - Tests concurrent request isolation

**How to Run:**
```bash
php artisan test --filter=TenantIsolationIntegrationTest
```

### Test Helpers

#### `/tests/Concerns/WithTenantIsolation.php`
Reusable trait providing helper methods for tenant isolation testing.

**Helper Methods:**
- `createTenantWithUser()` - Creates a tenant with organization and user
- `createMultipleTenants()` - Creates multiple tenants for cross-tenant testing
- `assertModelFiltersByTenant()` - Asserts model filters by tenant
- `assertCannotAccessCrossTenant()` - Asserts cross-tenant access is blocked
- `assertCanAccessSameTenant()` - Asserts same-tenant access is allowed
- `createCrossTenantData()` - Creates test data across multiple tenants
- `assertNoDataLeakage()` - Asserts no data leakage across tenants
- `assertEndpointEnforcesTenantIsolation()` - Asserts endpoint enforces isolation
- `assertEndpointRejectsCrossTenantAccess()` - Asserts endpoint rejects cross-tenant access
- `createUsersWithRoles()` - Creates users with different roles
- `assertIsolatedExecution()` - Asserts callback executes with isolation

**Usage Example:**
```php
use Tests\Concerns\WithTenantIsolation;

class MyTest extends TestCase
{
    use WithTenantIsolation;

    public function test_my_feature()
    {
        // Create two tenants
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        // Create cross-tenant data
        $data = $this->createCrossTenantData(Site::class);

        // Assert no data leakage
        $this->assertNoDataLeakage(Site::class, $data);
    }
}
```

## Running the Tests

### Run All Security Tests
```bash
php artisan test --testsuite=Unit,Feature
```

### Run Only Unit Tests
```bash
php artisan test --testsuite=Unit
```

### Run Only Feature Tests
```bash
php artisan test --testsuite=Feature
```

### Run Specific Test File
```bash
php artisan test tests/Unit/ObservabilityAdapterTest.php
php artisan test tests/Unit/TenantScopeTest.php
php artisan test tests/Feature/SiteControllerAuthorizationTest.php
php artisan test tests/Feature/TenantIsolationIntegrationTest.php
```

### Run with Coverage
```bash
php artisan test --coverage --min=80
```

### Run in Parallel
```bash
php artisan test --parallel
```

## Security Vulnerabilities Tested

### 1. PromQL Injection
**Vulnerability:** Malicious tenant IDs could inject additional PromQL expressions to access other tenants' metrics.

**Example Attack:**
```
tenant_id: "123"} or {tenant_id="456
```

**Prevention:** All tenant IDs and input values are escaped using `escapePromQLLabelValue()` which escapes:
- Backslashes: `\` → `\\`
- Quotes: `"` → `\"`
- Newlines: `\n` → `\\n`
- Regex special chars: `.`, `*`, `+`, `?`, `[`, `]`, `(`, `)`, `{`, `}`, `|`, `^`, `$`

**Tests:** ObservabilityAdapterTest verifies all escape scenarios.

### 2. LogQL Injection
**Vulnerability:** Malicious input in log queries could break out of LogQL expressions.

**Prevention:** All LogQL strings are escaped using `escapeLogQLString()` which escapes:
- Backslashes: `\` → `\\`
- Quotes: `"` → `\"`
- Newlines: `\n` → `\\n`
- Carriage returns: `\r` → `\\r`
- Tabs: `\t` → `\\t`

**Tests:** ObservabilityAdapterTest includes LogQL-specific tests.

### 3. Cross-Tenant Data Access
**Vulnerability:** Users could access other tenants' data by guessing or enumerating IDs.

**Prevention:** Global scopes on all tenant-scoped models automatically filter queries:
```php
static::addGlobalScope('tenant', function ($builder) {
    if (auth()->check() && auth()->user()->currentTenant()) {
        $builder->where('tenant_id', auth()->user()->currentTenant()->id);
    }
});
```

**Tests:** TenantScopeTest and TenantIsolationIntegrationTest verify isolation.

### 4. Authorization Bypass
**Vulnerability:** Users could bypass authorization checks to perform actions on other tenants' resources.

**Prevention:** SitePolicy checks tenant ownership before allowing any action:
```php
private function belongsToTenant(User $user, Site $site): bool
{
    $userTenant = $user->currentTenant();
    return $userTenant && $site->tenant_id === $userTenant->id;
}
```

**Tests:** SiteControllerAuthorizationTest verifies all policy methods.

## Test Coverage Goals

- **Unit Tests:** 90%+ coverage of security-critical methods
- **Feature Tests:** 100% coverage of authorization policies
- **Integration Tests:** Coverage of all tenant-scoped models and endpoints

## Continuous Integration

These tests should be run:
- On every commit (pre-commit hook)
- On every pull request (CI pipeline)
- Before every deployment
- Daily as part of security regression testing

## Adding New Tests

When adding new tenant-scoped models or features:

1. Add unit tests to verify the global scope works correctly
2. Add feature tests to verify API endpoints enforce tenant isolation
3. Update TenantIsolationIntegrationTest to include the new model
4. Use the WithTenantIsolation trait for common test patterns

## Security Testing Checklist

Before deploying tenant-scoped features:

- [ ] All models have global tenant scopes
- [ ] All policies check tenant ownership
- [ ] All user input is properly escaped
- [ ] All API endpoints enforce authorization
- [ ] All queries use the global scope
- [ ] Cross-tenant access returns 404, not 403
- [ ] Soft deletes respect tenant boundaries
- [ ] Aggregate queries respect tenant isolation
- [ ] Batch operations respect tenant isolation
- [ ] Search and filtering maintain isolation

## Related Documentation

- `/app/Models/Site.php` - Site model with global scope
- `/app/Models/Operation.php` - Operation model with global scope
- `/app/Models/UsageRecord.php` - UsageRecord model with global scope
- `/app/Models/VpsAllocation.php` - VpsAllocation model with global scope
- `/app/Services/Integration/ObservabilityAdapter.php` - Observability service with injection prevention
- `/app/Policies/SitePolicy.php` - Site authorization policy
- `/app/Http/Controllers/Api/V1/SiteController.php` - Site API controller
