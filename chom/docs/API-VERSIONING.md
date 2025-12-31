# CHOM API Versioning Policy

This document outlines the versioning strategy, deprecation policy, and backward compatibility guarantees for the CHOM API.

## Table of Contents
- [Versioning Scheme](#versioning-scheme)
- [Version Support](#version-support)
- [Deprecation Policy](#deprecation-policy)
- [Breaking Changes](#breaking-changes)
- [Backward Compatibility](#backward-compatibility)
- [Version Migration](#version-migration)
- [Best Practices](#best-practices)

---

## Versioning Scheme

### URL-Based Versioning

CHOM uses URL-based API versioning for clarity and simplicity:

```
https://api.chom.example.com/api/v1/sites
                                  ^^
                                  version
```

### Version Format

We follow **Semantic Versioning** (SemVer) principles:

```
v{MAJOR}.{MINOR}.{PATCH}
```

However, only the **MAJOR** version is included in the API URL:

- **MAJOR** (`v1`, `v2`) - Breaking changes, new URL required
- **MINOR** (internal) - New features, backward compatible
- **PATCH** (internal) - Bug fixes, backward compatible

**Examples:**
- `v1.0.0` → URL: `/api/v1`
- `v1.1.0` → URL: `/api/v1` (backward compatible)
- `v1.1.5` → URL: `/api/v1` (bug fix)
- `v2.0.0` → URL: `/api/v2` (breaking change)

### Version Headers

All API responses include version information:

```http
X-API-Version: 1.0.0
X-API-Major-Version: 1
X-API-Deprecated: false
```

---

## Version Support

### Current Versions

| Version | Released | Status | End of Life |
|---------|----------|--------|-------------|
| v1.0.0 | 2024-01-15 | Current | TBD |

### Support Timeline

Each major version receives:

1. **Active Support**: Minimum 24 months
   - New features added
   - Bug fixes applied
   - Security patches provided
   - Full documentation maintained

2. **Maintenance Support**: Minimum 12 months
   - Critical bug fixes only
   - Security patches provided
   - No new features
   - Documentation archived

3. **End of Life**
   - No further updates
   - Documentation archived but available
   - Migration guide provided

**Total Support Duration**: Minimum 36 months per major version

### Support Lifecycle Example

```
v1.0.0 Released (Jan 2024)
├─ Active Support (24 months)    → Until Jan 2026
│  ├─ v1.1.0 - New features
│  ├─ v1.2.0 - New features
│  └─ v1.2.5 - Bug fixes
├─ Maintenance Support (12 months) → Jan 2026 - Jan 2027
│  ├─ v1.2.6 - Critical fixes
│  └─ v1.2.7 - Security patches
└─ End of Life (Jan 2027)
```

---

## Deprecation Policy

### Our Commitments

1. **Advance Notice**: Minimum 6 months before deprecation
2. **Clear Communication**: Multiple notification channels
3. **Sunset Period**: Minimum 12 months before removal
4. **Migration Support**: Documentation and assistance provided

### Deprecation Process

#### Phase 1: Announcement (T-12 months)

**Actions:**
- Deprecation announced in changelog
- Email notification to all API users
- Documentation updated with deprecation notice
- Alternative solutions provided

**Example Email:**
```
Subject: CHOM API Deprecation Notice - Endpoint /old-endpoint

Dear CHOM API User,

We are announcing the deprecation of the following endpoint:

Endpoint: POST /api/v1/old-endpoint
Deprecation Date: 2024-07-15
Sunset Date: 2025-07-15
Replacement: POST /api/v1/new-endpoint

What you need to do:
1. Review the migration guide: https://docs.chom.com/migrations/old-to-new
2. Update your integration before 2025-07-15
3. Test thoroughly in our staging environment

Need help? Contact support@chom.example.com

Thank you for using CHOM!
```

#### Phase 2: Deprecation Warnings (T-6 months)

**Actions:**
- Response headers added:
  ```http
  X-API-Deprecated: true
  X-API-Sunset: 2025-07-15
  X-API-Replacement: /api/v1/new-endpoint
  ```
- Warning logs generated for monitoring
- Dashboard notification for API users
- Monthly reminder emails

#### Phase 3: Sunset (T-0)

**Actions:**
- Endpoint returns `410 Gone` status
- Response body includes migration instructions
- Support available for migration assistance

**Example Response:**
```json
{
  "success": false,
  "error": {
    "code": "ENDPOINT_SUNSET",
    "message": "This endpoint has been retired as of 2025-07-15.",
    "details": {
      "replacement": "/api/v1/new-endpoint",
      "migration_guide": "https://docs.chom.com/migrations/old-to-new",
      "support_email": "support@chom.example.com"
    }
  }
}
```

### What Triggers Deprecation?

Endpoints may be deprecated for:
- **Security concerns**: Vulnerability that cannot be patched
- **Performance issues**: Better alternative available
- **Design improvements**: Cleaner, more consistent API
- **Feature evolution**: Replaced by enhanced functionality

---

## Breaking Changes

### Definition

A change is considered **breaking** if it:

1. Changes request/response schema in incompatible ways
2. Removes endpoints or fields
3. Changes authentication mechanisms
4. Modifies error codes or structures
5. Changes rate limits significantly
6. Alters business logic in incompatible ways

### Non-Breaking Changes

The following are **NOT** considered breaking changes:

1. **Adding new endpoints**
   ```
   ✓ New: POST /api/v1/databases
   ```

2. **Adding optional request fields**
   ```json
   {
     "domain": "example.com",
     "php_version": "8.2",  // Existing
     "cache_enabled": true  // New, optional
   }
   ```

3. **Adding new response fields**
   ```json
   {
     "id": "123",
     "domain": "example.com",  // Existing
     "cdn_enabled": false      // New field added
   }
   ```

4. **Adding new error codes** (existing codes unchanged)
   ```
   ✓ New error code: CACHE_INVALIDATION_FAILED
   ```

5. **Relaxing validation rules**
   ```
   ✓ Password minimum length: 12 → 8 characters
   ```

6. **Performance improvements**
   ```
   ✓ Faster response times
   ✓ Better caching
   ```

### Breaking Change Examples

The following **REQUIRE** a new major version:

1. **Removing fields from responses**
   ```json
   // v1
   {"id": "123", "legacy_field": "value"}

   // v2 - BREAKING
   {"id": "123"}  // legacy_field removed
   ```

2. **Changing field types**
   ```json
   // v1
   {"created_at": "2024-01-15T10:30:00Z"}

   // v2 - BREAKING
   {"created_at": 1705318200}  // Changed to timestamp
   ```

3. **Renaming fields**
   ```json
   // v1
   {"domain": "example.com"}

   // v2 - BREAKING
   {"site_domain": "example.com"}  // Field renamed
   ```

4. **Making optional fields required**
   ```json
   // v1
   {"domain": "example.com"}  // php_version optional

   // v2 - BREAKING
   {"domain": "example.com", "php_version": "8.2"}  // Now required
   ```

5. **Changing endpoint paths**
   ```
   // v1
   POST /api/v1/sites

   // v2 - BREAKING
   POST /api/v2/wordpress-sites  // Path changed
   ```

6. **Modifying authentication**
   ```
   // v1: Bearer token
   Authorization: Bearer token123

   // v2 - BREAKING: API key
   X-API-Key: key123  // Different auth method
   ```

---

## Backward Compatibility

### Our Guarantees

Within a major version (e.g., all `v1.x.x` releases):

1. **Existing integrations continue working** - No code changes required
2. **Field additions are additive** - New optional fields only
3. **Response structure remains stable** - Existing fields unchanged
4. **Endpoint paths stay constant** - URLs don't change
5. **Authentication methods persist** - Same auth mechanism
6. **Error codes remain consistent** - Existing codes unchanged

### Client Responsibilities

To maintain compatibility, clients should:

1. **Ignore unknown fields** in responses
   ```javascript
   // Good - Ignores unknown fields
   const { id, domain } = response.data;

   // Bad - Strict schema validation may break
   const schema = { id: String, domain: String };  // Breaks if new fields added
   ```

2. **Use flexible JSON parsing**
   ```python
   # Good
   site = response.json()
   domain = site.get('domain')

   # Bad - Breaks on new fields
   site = SiteSchema(strict=True).load(response.json())
   ```

3. **Handle new error codes gracefully**
   ```javascript
   // Good - Fallback for unknown errors
   switch (error.code) {
     case 'SITE_LIMIT_EXCEEDED':
       // Handle known error
       break;
     default:
       // Handle unknown errors gracefully
       console.error('Unknown error:', error.message);
   }
   ```

4. **Don't rely on field order**
   ```json
   // Both are valid and equivalent
   {"domain": "example.com", "id": "123"}
   {"id": "123", "domain": "example.com"}
   ```

### Stability Levels

Different API areas have different stability guarantees:

| Area | Stability | Changes Allowed |
|------|-----------|-----------------|
| **Core Endpoints** (Sites, Backups, Auth) | Stable | Additions only |
| **Experimental Features** (marked in docs) | Beta | May change without notice |
| **Deprecated Endpoints** | Legacy | Security fixes only |

---

## Version Migration

### Migration Guide Template

When releasing a new major version, we provide:

#### 1. Breaking Changes Summary
- List of all breaking changes
- Affected endpoints
- Migration complexity estimate

#### 2. Migration Steps
```markdown
## Migrating from v1 to v2

### Step 1: Update Base URL
- Old: https://api.chom.example.com/api/v1
- New: https://api.chom.example.com/api/v2

### Step 2: Update Authentication
- Old: Bearer token in Authorization header
- New: API key in X-API-Key header

### Step 3: Update Request Schemas
...
```

#### 3. Code Examples

**Before (v1):**
```javascript
const response = await fetch('https://api.chom.example.com/api/v1/sites', {
  headers: {
    'Authorization': `Bearer ${token}`,
  }
});
```

**After (v2):**
```javascript
const response = await fetch('https://api.chom.example.com/api/v2/sites', {
  headers: {
    'X-API-Key': apiKey,
  }
});
```

#### 4. Testing Checklist
- [ ] Update base URL in configuration
- [ ] Update authentication mechanism
- [ ] Update request schemas
- [ ] Update response parsing
- [ ] Test error handling
- [ ] Update monitoring/logging
- [ ] Deploy to staging
- [ ] Run integration tests
- [ ] Deploy to production

### Dual Version Support

During migration periods, you can support both versions:

```javascript
const API_VERSION = process.env.API_VERSION || 'v1';
const BASE_URL = `https://api.chom.example.com/api/${API_VERSION}`;

// Use feature flags
if (API_VERSION === 'v2') {
  // Use v2 features
} else {
  // Use v1 features
}
```

---

## Best Practices

### For API Consumers

1. **Always specify Accept header**
   ```http
   Accept: application/json
   ```

2. **Handle version headers**
   ```javascript
   const apiVersion = response.headers.get('X-API-Version');
   const isDeprecated = response.headers.get('X-API-Deprecated') === 'true';

   if (isDeprecated) {
     console.warn('Using deprecated API version');
   }
   ```

3. **Monitor deprecation warnings**
   ```javascript
   if (response.headers.has('X-API-Sunset')) {
     const sunsetDate = response.headers.get('X-API-Sunset');
     alert(`API sunset scheduled for ${sunsetDate}`);
   }
   ```

4. **Use SDK libraries** (when available)
   - Automatic version management
   - Built-in migration support
   - Better error handling

5. **Subscribe to API updates**
   - Join our mailing list
   - Follow changelog
   - Monitor status page

### For CHOM Developers

1. **Never break existing endpoints** in minor versions
2. **Add, don't modify** existing functionality
3. **Use feature flags** for gradual rollouts
4. **Version control schemas** in separate files
5. **Write migration guides** before releasing
6. **Test backward compatibility** thoroughly

---

## Version Negotiation

### Future: Content Negotiation

We may support content negotiation in the future:

```http
GET /api/sites/123
Accept: application/vnd.chom.v2+json
```

This is not currently implemented but reserved for future use.

---

## FAQ

### Q: Can I use multiple API versions simultaneously?

**A:** Yes! Each version has its own URL path, so you can use different versions for different features during migration.

### Q: What happens if I don't migrate before sunset?

**A:** The endpoint will return `410 Gone` with migration instructions. Your integration will break until updated.

### Q: How do I know which version I'm using?

**A:** Check the `X-API-Version` response header, or look at your request URL (`/api/v1` vs `/api/v2`).

### Q: Are there any costs associated with version changes?

**A:** No, all API versions are included in your subscription at no extra cost.

### Q: Can I request features in older versions?

**A:** New features are only added to the current major version. Older versions receive security patches only.

### Q: How can I test against newer versions?

**A:** Use our staging environment:
```
https://staging.chom.example.com/api/v2
```

---

## Contact & Support

### General Questions
- Email: support@chom.example.com
- Documentation: https://docs.chom.example.com

### Migration Assistance
- Email: migrations@chom.example.com
- Schedule consultation: https://chom.example.com/api-consultation

### Security Issues
- Email: security@chom.example.com
- PGP Key: https://chom.example.com/pgp-key

---

## Useful Links

- [API Changelog](./API-CHANGELOG.md)
- [API Quick Start Guide](./API-QUICKSTART.md)
- [OpenAPI Specification](../openapi.yaml)
- [Postman Collection](../postman_collection.json)

---

**Document Version**: 1.0
**Last Updated**: 2024-01-15
**Current API Version**: v1.0.0
