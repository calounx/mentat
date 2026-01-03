# Form Requests Quick Reference

## Files Created (Phase 1)

### Core Files
1. **BaseFormRequest.php** (2.9 KB)
   - Common validation rules
   - Helper methods for authorization
   - Shared error messages

### Site Management
2. **StoreSiteRequest.php** (4.4 KB)
   - Site creation validation
   - Tenant quota enforcement
   - Domain uniqueness check

3. **UpdateSiteRequest.php** (4.3 KB)
   - Site update validation
   - Ownership verification
   - Partial update support

### Backup Management
4. **StoreBackupRequest.php** (5.4 KB)
   - Backup creation validation
   - Tier-based quota limits
   - Retention period defaults

### Team Management
5. **InviteTeamMemberRequest.php** (5.4 KB)
   - Team invitation validation
   - Role-based permissions
   - Default permission sets

6. **UpdateTeamMemberRequest.php** (5.4 KB)
   - Team member updates
   - Self-demotion protection
   - Role hierarchy enforcement

### Organization Management
7. **UpdateOrganizationRequest.php** (5.4 KB)
   - Organization settings
   - Owner-only restrictions
   - Slug normalization

### Infrastructure Management
8. **UpdateVpsServerRequest.php** (7.1 KB)
   - VPS server updates
   - Admin-only access
   - Safety checks for decommissioning

## Usage Examples

### In Controllers

```php
// Before
public function store(Request $request)
{
    $request->validate(['domain' => 'required']);
    if (!$request->user()->canManageSites()) abort(403);
    // ... more validation
}

// After
public function store(StoreSiteRequest $request)
{
    // All validation done!
    $data = $request->validated();
}
```

### Common Patterns

```php
// Get validated data
$validated = $request->validated();

// Access helper methods
$tenantId = $request->getTenantId();
$canManage = $request->canManageSites();

// All authorization already checked in authorize() method
```

## File Locations

```
/home/calounx/repositories/mentat/chom/app/Http/Requests/
├── BaseFormRequest.php
├── StoreSiteRequest.php
├── UpdateSiteRequest.php
├── StoreBackupRequest.php
├── InviteTeamMemberRequest.php
├── UpdateTeamMemberRequest.php
├── UpdateOrganizationRequest.php
└── UpdateVpsServerRequest.php
```

## Documentation

Full implementation details: `/home/calounx/repositories/mentat/chom/PHASE1_FORM_REQUESTS_IMPLEMENTATION.md`

## Next Steps

1. Update controllers to use Form Requests
2. Remove manual validation from controllers
3. Create unit tests for Form Requests
4. Add integration tests
