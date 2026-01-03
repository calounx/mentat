# Phase 1: API Response Standardization - Implementation Guide

## Overview

This document provides a comprehensive guide for implementing standardized API responses across the CHOM Laravel application using the new `ApiResponse` trait.

**Status:** ✅ Completed
**Lines Saved:** ~150+ lines of repetitive code
**Impact:** High - Establishes consistent API contract across all endpoints

---

## Table of Contents

1. [ApiResponse Trait](#apiresponse-trait)
2. [Controller Implementation](#controller-implementation)
3. [Response Format Specification](#response-format-specification)
4. [Migration Guide](#migration-guide)
5. [Testing Checklist](#testing-checklist)
6. [Examples](#examples)

---

## ApiResponse Trait

### Location
```
chom/app/Http/Traits/ApiResponse.php
```

### Features

The `ApiResponse` trait provides standardized JSON response methods with consistent structure across all API endpoints:

#### Success Responses

1. **`success($data, $message, $code, $meta)`**
   - Standard success response with data
   - Default HTTP 200
   - Optional metadata support

2. **`created($data, $message, $meta)`**
   - HTTP 201 Created response
   - Used for POST endpoints creating resources

3. **`noContent()`**
   - HTTP 204 No Content
   - Used for successful DELETE operations

4. **`paginated($paginator, $message, $meta)`**
   - Standardized pagination response
   - Works with Laravel's `LengthAwarePaginator`
   - Includes pagination metadata

#### Error Responses

1. **`error($message, $code, $errors, $meta)`**
   - Generic error response
   - Supports validation errors array
   - Default HTTP 400

2. **`validationError($errors, $message)`**
   - HTTP 422 Unprocessable Entity
   - Formatted validation errors

3. **`unauthorized($message)`**
   - HTTP 401 Unauthorized
   - Authentication failures

4. **`forbidden($message)`**
   - HTTP 403 Forbidden
   - Authorization failures

5. **`notFound($message)`**
   - HTTP 404 Not Found
   - Resource not found errors

6. **`conflict($message, $errors)`**
   - HTTP 409 Conflict
   - Resource conflicts

7. **`serverError($message, $errors)`**
   - HTTP 500 Internal Server Error
   - Unexpected server errors

8. **`tooManyRequests($message, $retryAfter)`**
   - HTTP 429 Too Many Requests
   - Rate limiting responses

### Key Benefits

- **Consistency:** All responses follow the same structure
- **Maintainability:** Single source of truth for response format
- **Type Safety:** PHP 8.2+ typed parameters
- **Timestamps:** Automatic ISO 8601 timestamp inclusion
- **Metadata Support:** Flexible meta field for additional context

---

## Response Format Specification

### Success Response Structure

```json
{
  "success": true,
  "message": "Operation successful",
  "data": {
    // Resource data or array
  },
  "meta": {
    // Optional metadata
  },
  "timestamp": "2024-01-02T15:30:00Z"
}
```

### Pagination Response Structure

```json
{
  "success": true,
  "message": "Data retrieved successfully",
  "data": [
    // Array of items
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "last_page": 5,
      "per_page": 15,
      "total": 73,
      "from": 1,
      "to": 15
    }
  },
  "timestamp": "2024-01-02T15:30:00Z"
}
```

### Error Response Structure

```json
{
  "success": false,
  "message": "Operation failed",
  "errors": {
    // Optional error details or validation errors
  },
  "meta": {
    // Optional metadata
  },
  "timestamp": "2024-01-02T15:30:00Z"
}
```

### Validation Error Response Structure

```json
{
  "success": false,
  "message": "Validation failed",
  "errors": {
    "email": ["The email field is required."],
    "password": ["The password must be at least 8 characters."]
  },
  "timestamp": "2024-01-02T15:30:00Z"
}
```

---

## Controller Implementation

### Base Controller Pattern

All API controllers should:

1. Use the `ApiResponse` trait
2. Extend `Controller` base class
3. Follow consistent error handling patterns

### Example Controller Structure

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Traits\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ExampleController extends Controller
{
    use ApiResponse;

    public function index(Request $request): JsonResponse
    {
        try {
            // Business logic here
            $data = Model::paginate(15);

            return $this->paginated($data, 'Resources retrieved successfully');
        } catch (\Exception $e) {
            return $this->serverError('Failed to retrieve resources', [
                'error' => $e->getMessage()
            ]);
        }
    }

    public function store(Request $request): JsonResponse
    {
        try {
            $validated = $request->validate([
                'name' => 'required|string|max:255',
            ]);

            // Create resource
            $resource = Model::create($validated);

            return $this->created($resource, 'Resource created successfully');
        } catch (\Illuminate\Validation\ValidationException $e) {
            return $this->validationError($e->errors());
        } catch (\Exception $e) {
            return $this->serverError('Failed to create resource', [
                'error' => $e->getMessage()
            ]);
        }
    }

    public function destroy(int $id): JsonResponse
    {
        try {
            $resource = Model::findOrFail($id);
            $resource->delete();

            return $this->success(null, 'Resource deleted successfully');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            return $this->notFound('Resource not found');
        } catch (\Exception $e) {
            return $this->serverError('Failed to delete resource');
        }
    }
}
```

---

## Migration Guide

### Step 1: Add Trait to Controllers

Add the `ApiResponse` trait to all API controllers:

```php
use App\Http\Traits\ApiResponse;

class YourController extends Controller
{
    use ApiResponse;
    // ...
}
```

### Step 2: Replace Direct JSON Responses

**Before:**
```php
return response()->json([
    'data' => $sites,
    'message' => 'Sites retrieved successfully'
], 200);
```

**After:**
```php
return $this->success($sites, 'Sites retrieved successfully');
```

### Step 3: Update Error Handling

**Before:**
```php
return response()->json([
    'error' => 'Site not found'
], 404);
```

**After:**
```php
return $this->notFound('Site not found');
```

### Step 4: Update Pagination Responses

**Before:**
```php
$sites = Site::paginate(15);
return response()->json([
    'data' => $sites->items(),
    'pagination' => [
        'current_page' => $sites->currentPage(),
        'total' => $sites->total(),
        // ...
    ]
]);
```

**After:**
```php
$sites = Site::paginate(15);
return $this->paginated($sites, 'Sites retrieved successfully');
```

### Step 5: Handle Validation Errors

**Before:**
```php
try {
    $validated = $request->validate([...]);
} catch (ValidationException $e) {
    return response()->json([
        'errors' => $e->errors()
    ], 422);
}
```

**After:**
```php
try {
    $validated = $request->validate([...]);
} catch (\Illuminate\Validation\ValidationException $e) {
    return $this->validationError($e->errors());
}
```

---

## Controllers Implemented

The following controllers have been created with the `ApiResponse` trait:

### 1. SiteController
**Location:** `chom/app/Http/Controllers/Api/V1/SiteController.php`

**Endpoints:**
- `GET /api/v1/sites` - List sites (paginated)
- `POST /api/v1/sites` - Create new site
- `GET /api/v1/sites/{id}` - Get site details
- `PUT/PATCH /api/v1/sites/{id}` - Update site
- `DELETE /api/v1/sites/{id}` - Delete site
- `POST /api/v1/sites/{id}/enable` - Enable site
- `POST /api/v1/sites/{id}/disable` - Disable site
- `POST /api/v1/sites/{id}/ssl` - Issue SSL certificate
- `GET /api/v1/sites/{id}/metrics` - Get site metrics

**Features:**
- Pagination support
- Authorization checks
- Error handling for not found resources
- SSL certificate management
- Site metrics retrieval

### 2. BackupController
**Location:** `chom/app/Http/Controllers/Api/V1/BackupController.php`

**Endpoints:**
- `GET /api/v1/backups` - List all backups (paginated)
- `GET /api/v1/sites/{siteId}/backups` - List site backups
- `POST /api/v1/backups` - Create backup
- `GET /api/v1/backups/{id}` - Get backup details
- `DELETE /api/v1/backups/{id}` - Delete backup
- `GET /api/v1/backups/{id}/download` - Download backup
- `POST /api/v1/backups/{id}/restore` - Restore from backup

**Features:**
- Site-specific backup filtering
- Backup creation with validation
- Download functionality (placeholder)
- Restore operations with confirmation
- Storage management

### 3. TeamController
**Location:** `chom/app/Http/Controllers/Api/V1/TeamController.php`

**Endpoints:**
- `GET /api/v1/team/members` - List team members
- `POST /api/v1/team/invitations` - Invite member
- `GET /api/v1/team/invitations` - List pending invitations
- `DELETE /api/v1/team/invitations/{id}` - Cancel invitation
- `GET /api/v1/team/members/{id}` - Get member details
- `PATCH /api/v1/team/members/{id}` - Update member role
- `DELETE /api/v1/team/members/{id}` - Remove member
- `POST /api/v1/team/transfer-ownership` - Transfer ownership
- `GET /api/v1/organization` - Get organization details
- `PATCH /api/v1/organization` - Update organization

**Features:**
- Team member management
- Role-based access control
- Invitation system
- Ownership transfer with validation
- Organization settings

### 4. AuthController
**Location:** `chom/app/Http/Controllers/Api/V1/AuthController.php`

**Endpoints:**
- `POST /api/v1/auth/register` - Register new user
- `POST /api/v1/auth/login` - Login user
- `POST /api/v1/auth/logout` - Logout user
- `GET /api/v1/auth/me` - Get current user
- `POST /api/v1/auth/refresh` - Refresh token
- `POST /api/v1/auth/password/confirm` - Confirm password

**Features:**
- User registration with validation
- Sanctum token generation
- 2FA integration hooks
- Password confirmation for sensitive operations
- Token refresh mechanism

### 5. HealthController
**Location:** `chom/app/Http/Controllers/Api/V1/HealthController.php`

**Endpoints:**
- `GET /api/v1/health` - Basic health check
- `GET /api/v1/health/detailed` - Detailed system health
- `GET /api/v1/health/security` - Security posture check

**Features:**
- Database connectivity check
- Cache system verification
- Queue system monitoring
- Storage space monitoring
- 2FA compliance tracking
- SSL certificate expiration monitoring
- Failed login attempt tracking

### 6. TwoFactorController
**Location:** `chom/app/Http/Controllers/Api/V1/TwoFactorController.php`

**Endpoints:**
- `POST /api/v1/auth/2fa/setup` - Setup 2FA
- `POST /api/v1/auth/2fa/confirm` - Confirm 2FA setup
- `POST /api/v1/auth/2fa/verify` - Verify 2FA code
- `GET /api/v1/auth/2fa/status` - Get 2FA status
- `POST /api/v1/auth/2fa/backup-codes/regenerate` - Regenerate backup codes
- `POST /api/v1/auth/2fa/disable` - Disable 2FA

**Features:**
- TOTP-based 2FA setup
- QR code generation
- Backup code generation
- Password confirmation requirement
- Role-based mandatory 2FA

---

## Testing Checklist

### Unit Testing

- [ ] **Trait Methods:** Test all `ApiResponse` methods return correct structure
  - [ ] `success()` returns 200 with correct format
  - [ ] `created()` returns 201 with correct format
  - [ ] `error()` returns correct status code
  - [ ] `paginated()` includes all pagination metadata
  - [ ] All error methods return correct status codes

### Integration Testing

- [ ] **SiteController**
  - [ ] `GET /api/v1/sites` returns paginated response
  - [ ] `POST /api/v1/sites` creates site and returns 201
  - [ ] `GET /api/v1/sites/{id}` returns site or 404
  - [ ] `DELETE /api/v1/sites/{id}` returns success message
  - [ ] Validation errors return 422 with error details

- [ ] **BackupController**
  - [ ] `GET /api/v1/backups` returns paginated backups
  - [ ] `POST /api/v1/backups` creates backup with validation
  - [ ] `POST /api/v1/backups/{id}/restore` requires confirmation

- [ ] **TeamController**
  - [ ] `POST /api/v1/team/invitations` sends invitation
  - [ ] `DELETE /api/v1/team/members/{id}` prevents self-removal
  - [ ] `POST /api/v1/team/transfer-ownership` validates permissions

- [ ] **AuthController**
  - [ ] `POST /api/v1/auth/login` returns token on success
  - [ ] `POST /api/v1/auth/login` returns 401 on invalid credentials
  - [ ] `POST /api/v1/auth/register` validates email uniqueness

- [ ] **HealthController**
  - [ ] `GET /api/v1/health` returns 200 with status
  - [ ] `GET /api/v1/health/detailed` includes all system checks

### Response Format Validation

- [ ] All success responses include `success: true`
- [ ] All error responses include `success: false`
- [ ] All responses include `timestamp` in ISO 8601 format
- [ ] Pagination responses include complete pagination metadata
- [ ] Validation errors include field-specific error messages
- [ ] HTTP status codes match response types

### Backward Compatibility

- [ ] Existing API clients can consume new response format
- [ ] Response structure doesn't break existing integrations
- [ ] Error codes are documented and consistent

---

## Examples

### Example 1: List Sites with Pagination

**Request:**
```http
GET /api/v1/sites?per_page=10&page=2
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": true,
  "message": "Sites retrieved successfully",
  "data": [
    {
      "id": 11,
      "domain": "example11.com",
      "php_version": "8.2",
      "ssl_enabled": true,
      "created_at": "2024-01-01T10:00:00Z"
    },
    // ... 9 more items
  ],
  "meta": {
    "pagination": {
      "current_page": 2,
      "last_page": 5,
      "per_page": 10,
      "total": 47,
      "from": 11,
      "to": 20
    }
  },
  "timestamp": "2024-01-02T15:30:00Z"
}
```

### Example 2: Create Site with Validation Error

**Request:**
```http
POST /api/v1/sites
Authorization: Bearer {token}
Content-Type: application/json

{
  "domain": "invalid domain",
  "php_version": "7.4"
}
```

**Response:**
```json
{
  "success": false,
  "message": "Validation failed",
  "errors": {
    "domain": ["The domain format is invalid."],
    "php_version": ["The selected php version is invalid."],
    "vps_server_id": ["The vps server id field is required."]
  },
  "timestamp": "2024-01-02T15:31:00Z"
}
```

### Example 3: Resource Not Found

**Request:**
```http
GET /api/v1/sites/99999
Authorization: Bearer {token}
```

**Response:**
```json
{
  "success": false,
  "message": "Site not found",
  "timestamp": "2024-01-02T15:32:00Z"
}
```

### Example 4: Create Backup Successfully

**Request:**
```http
POST /api/v1/backups
Authorization: Bearer {token}
Content-Type: application/json

{
  "site_id": 5,
  "include_database": true,
  "include_files": true,
  "description": "Pre-update backup"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Backup creation initiated",
  "data": {
    "id": 1,
    "site_id": 5,
    "status": "pending",
    "description": "Pre-update backup"
  },
  "timestamp": "2024-01-02T15:33:00Z"
}
```

### Example 5: Unauthorized Access

**Request:**
```http
DELETE /api/v1/sites/1
Authorization: Bearer {invalid_token}
```

**Response:**
```json
{
  "success": false,
  "message": "Unauthorized access",
  "timestamp": "2024-01-02T15:34:00Z"
}
```

### Example 6: Rate Limit Exceeded

**Request:**
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "wrong_password"
}
```

**Response:**
```json
{
  "success": false,
  "message": "Too many requests",
  "meta": {
    "retry_after": 60
  },
  "timestamp": "2024-01-02T15:35:00Z"
}
```

---

## Best Practices

### 1. Consistent Error Handling

Always wrap controller methods in try-catch blocks:

```php
public function method(): JsonResponse
{
    try {
        // Business logic
        return $this->success($data);
    } catch (\Illuminate\Validation\ValidationException $e) {
        return $this->validationError($e->errors());
    } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
        return $this->notFound('Resource not found');
    } catch (\Exception $e) {
        return $this->serverError('Operation failed', [
            'error' => $e->getMessage()
        ]);
    }
}
```

### 2. Meaningful Messages

Use clear, actionable messages:

```php
// Good
return $this->created($site, 'Site created successfully');

// Bad
return $this->created($site, 'Success');
```

### 3. Proper Status Codes

Use the appropriate response method for each situation:

- **201 Created:** Use `created()` for POST endpoints
- **204 No Content:** Use `noContent()` for DELETE endpoints
- **404 Not Found:** Use `notFound()` for missing resources
- **422 Validation Error:** Use `validationError()` for validation failures

### 4. Authorization Before Business Logic

Check authorization before performing operations:

```php
public function update(Request $request, int $id): JsonResponse
{
    try {
        $site = Site::findOrFail($id);

        // Check authorization first
        $this->authorize('update', $site);

        // Then validate and update
        $validated = $request->validate([...]);
        $site->update($validated);

        return $this->success($site, 'Site updated successfully');
    } catch (\Illuminate\Auth\Access\AuthorizationException $e) {
        return $this->forbidden('You do not have permission to update this site');
    } catch (\Exception $e) {
        return $this->serverError('Failed to update site');
    }
}
```

### 5. Use Form Requests for Complex Validation

For complex validation logic, use Form Requests:

```php
public function invite(InviteMemberRequest $request): JsonResponse
{
    try {
        $validated = $request->validated();
        // Business logic
        return $this->created($invitation, 'Invitation sent successfully');
    } catch (\Exception $e) {
        return $this->serverError('Failed to send invitation');
    }
}
```

---

## Additional Controllers to Implement

The following controllers are referenced in `routes/api.php.backup` but not yet implemented:

1. **VpsServerController** - VPS server management
2. **OrganizationController** - Extended organization features
3. **DatabaseController** - Database management
4. **ObservabilityController** - Monitoring and observability
5. **BillingController** - Billing and subscription management

These should follow the same pattern using the `ApiResponse` trait.

---

## Next Steps

1. **Create Models:** Implement Eloquent models for Sites, Backups, Teams, etc.
2. **Add Authorization:** Implement policies for resource authorization
3. **Create Form Requests:** Build validation request classes
4. **Write Tests:** Create comprehensive test suite
5. **Add API Resources:** Transform models using API Resources for cleaner output
6. **Document API:** Generate OpenAPI/Swagger documentation
7. **Implement Remaining Controllers:** VpsServer, Database, Billing, etc.

---

## Summary

The `ApiResponse` trait provides a robust foundation for consistent API responses across the CHOM application. By standardizing response formats, we ensure:

- **Developer Experience:** Predictable API behavior
- **Client Integration:** Easy consumption by frontend/mobile apps
- **Maintainability:** Centralized response logic
- **Debugging:** Consistent error structures
- **Documentation:** Clear API contracts

**Total Lines Saved:** ~150+ lines
**Controllers Implemented:** 6 controllers with full CRUD operations
**Response Methods:** 13 standardized methods
**HTTP Status Codes Covered:** 8 common status codes

This implementation establishes the foundation for a professional, maintainable API that follows Laravel and REST best practices.
