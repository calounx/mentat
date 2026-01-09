# Site-to-Tenant Mappings API Implementation

## Overview

Implemented a new API endpoint for retrieving site-to-tenant mappings required by observability exporters (Prometheus) to add proper tenant and organization labels to metrics.

## Implementation Date
2026-01-09

## Changes Made

### 1. API Endpoint

**File**: `/home/calounx/repositories/mentat/chom/routes/api.php` (created)

- Route: `GET /api/v1/sites/tenant-mappings`
- Middleware: `auth:sanctum`
- Controller: `SiteController@tenantMappings`
- Authorization: Owner role only (enforced in controller)

### 2. Controller Method

**File**: `/home/calounx/repositories/mentat/chom/app/Http/Controllers/Api/V1/SiteController.php` (modified)

Added `tenantMappings()` method that:
- Validates user has owner role (uses `requireOwner()` from `HasTenantContext` trait)
- Retrieves ALL sites across ALL tenants (not tenant-scoped)
- Eager loads tenant and organization relationships
- Returns data in format: `{sites: [{domain, tenant_id, organization_id, vps_id}]}`

**Response Format**:
```json
{
  "success": true,
  "data": {
    "sites": [
      {
        "domain": "example.com",
        "tenant_id": "uuid",
        "organization_id": "uuid",
        "vps_id": "uuid"
      }
    ]
  }
}
```

### 3. Route Service Provider

**File**: `/home/calounx/repositories/mentat/chom/app/Providers/RouteServiceProvider.php` (created)

- Loads API routes from `routes/api.php` with `api` middleware and `/api` prefix
- Loads health check routes from `routes/health.php` with `web` middleware
- Configures rate limiting: 60 requests per minute per user/IP

**Registration**: Added to `ModuleServiceProvider` provider array

### 4. Models

Created comprehensive Eloquent models in `/home/calounx/repositories/mentat/chom/app/Models/`:

- **Site.php**: Main site model with tenant, vpsServer, backups, and sslCertificate relationships
- **Tenant.php**: Tenant model with organization and sites relationships
- **Organization.php**: Organization model with tenants and users relationships
- **User.php**: User authenticatable model with isOwner() and isAdmin() helper methods
- **VpsServer.php**: VPS server model
- **SiteBackup.php**: Site backup model
- **SslCertificate.php**: SSL certificate model

All models use:
- UUID primary keys (`HasUuids` trait)
- Factory support (`HasFactory` trait)
- Proper type casting
- Relationship definitions

### 5. Feature Tests

**File**: `/home/calounx/repositories/mentat/chom/tests/Feature/SiteTenantMappingsTest.php` (created)

Comprehensive test suite covering:

1. **Authorization Tests**:
   - ✅ Owner can access endpoint
   - ✅ Admin cannot access endpoint (403)
   - ✅ Member cannot access endpoint (403)
   - ✅ Unauthenticated user cannot access endpoint (401)

2. **Data Tests**:
   - ✅ Response includes correct data structure
   - ✅ Response includes all sites with correct tenant_id and organization_id
   - ✅ Endpoint returns sites from ALL tenants (not scoped to user's tenant)
   - ✅ Response format matches specification

3. **Multi-Tenancy Tests**:
   - ✅ Verified owner sees sites from multiple organizations
   - ✅ Verified correct mapping data for each site

## Authorization Model

**Note**: The original requirement specified "super admin" role, but this codebase uses:
- `owner` - Highest privilege level (replaces "super admin")
- `admin` - Administrative privileges (tenant/organization scoped)
- `member` - Standard user privileges
- `viewer` - Read-only privileges

The implementation uses **owner** role as the equivalent of "super admin" since:
1. No separate "super admin" role exists in the migration schema
2. Owner role has highest privileges per the `BasePolicy` role hierarchy
3. Owner can bypass all authorization checks per `BasePolicy::before()`

## Usage

### For Prometheus Exporters

```bash
# Request site mappings (requires owner token)
curl -H "Authorization: Bearer {owner_token}" \
     https://chom.example.com/api/v1/sites/tenant-mappings

# Response used for labeling metrics
{
  "success": true,
  "data": {
    "sites": [
      {
        "domain": "customer1.com",
        "tenant_id": "tenant-uuid-1",
        "organization_id": "org-uuid-1",
        "vps_id": "vps-uuid-1"
      }
    ]
  }
}
```

### For Testing

```bash
cd /home/calounx/repositories/mentat/chom
php artisan test tests/Feature/SiteTenantMappingsTest.php
```

## Security Considerations

1. **Owner-only access**: Only users with owner role can access this endpoint
2. **Authentication required**: Sanctum authentication enforced via middleware
3. **Rate limiting**: 60 requests/minute per user to prevent abuse
4. **No sensitive data**: Endpoint only returns IDs and domains (no passwords, secrets, or PII)

## Integration Points

This endpoint is designed to be consumed by:

1. **Prometheus Exporters** (Phase 3):
   - Periodically fetch site mappings
   - Cache mappings locally
   - Add tenant_id and organization_id labels to metrics
   - Enable multi-tenant metric filtering in Grafana

2. **Future Observability Tools**:
   - Loki log aggregation (tenant labeling)
   - Tempo distributed tracing (tenant context)
   - Any tool requiring site→tenant→organization mapping

## Files Created

```
chom/
├── routes/
│   └── api.php                                    (new)
├── app/
│   ├── Models/
│   │   ├── Site.php                               (new)
│   │   ├── Tenant.php                             (new)
│   │   ├── Organization.php                       (new)
│   │   ├── User.php                               (new)
│   │   ├── VpsServer.php                          (new)
│   │   ├── SiteBackup.php                         (new)
│   │   └── SslCertificate.php                     (new)
│   ├── Providers/
│   │   ├── RouteServiceProvider.php               (new)
│   │   └── ModuleServiceProvider.php              (modified)
│   └── Http/Controllers/Api/V1/
│       └── SiteController.php                     (modified - added tenantMappings method)
└── tests/Feature/
    └── SiteTenantMappingsTest.php                 (new)
```

## Next Steps

1. **Phase 3 Integration**: Update Prometheus exporter to consume this endpoint
2. **Caching**: Consider adding response caching (5-15 minute TTL)
3. **Monitoring**: Add metrics for endpoint usage and performance
4. **Documentation**: Update API documentation with new endpoint details

## References

- Original requirement: `PHASE_1_2_COMPLETE.md`
- Related: Prometheus exporter labeling (Phase 3)
- Security pattern: Based on `BackupTenantIsolationTest.php`
- Controller pattern: Based on existing `SiteController` methods
