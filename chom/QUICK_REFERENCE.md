# API Controller Quick Reference Guide

## For Developers: Using the Base ApiController

This guide shows you how to use the new base controller in your daily work.

---

## Basic Controller Setup

```php
<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class YourController extends ApiController
{
    // Your controller automatically has access to:
    // - ApiResponse trait methods
    // - HasTenantContext trait methods
    // - Base controller helper methods
}
```

---

## Common Patterns

### 1. List Resources (Paginated)

```php
public function index(Request $request): JsonResponse
{
    try {
        $tenant = $this->getTenant($request);
        
        $query = $tenant->resources()
            ->with('relationships');
        
        $this->applyFilters($query, $request);
        
        $resources = $query->paginate($this->getPaginationLimit($request));
        
        return $this->paginatedResponse($resources);
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

**Query Parameters:**
- `per_page` - Items per page (1-100, default: 20)
- `status` - Filter by status
- `sort_by` - Field to sort by
- `sort_order` - asc or desc

---

### 2. Show Single Resource

```php
public function show(Request $request, string $id): JsonResponse
{
    try {
        // Validates tenant access automatically
        $resource = $this->validateTenantAccess(
            $request,
            $id,
            \App\Models\YourModel::class
        );
        
        return $this->successResponse($resource);
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

### 3. Create Resource

```php
public function store(Request $request): JsonResponse
{
    try {
        $tenant = $this->getTenant($request);
        
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'type' => ['required', 'in:option1,option2'],
        ]);
        
        $resource = YourModel::create([
            'tenant_id' => $tenant->id,
            ...$validated,
        ]);
        
        $this->logInfo('Resource created', [
            'resource_id' => $resource->id,
        ]);
        
        return $this->createdResponse(
            $resource,
            'Resource created successfully.'
        );
    } catch (ValidationException $e) {
        return $this->validationErrorResponse($e->errors());
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

### 4. Update Resource

```php
public function update(Request $request, string $id): JsonResponse
{
    try {
        $resource = $this->validateTenantAccess(
            $request,
            $id,
            \App\Models\YourModel::class
        );
        
        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
        ]);
        
        $resource->update($validated);
        
        return $this->successResponse(
            $resource,
            'Resource updated successfully.'
        );
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

### 5. Delete Resource

```php
public function destroy(Request $request, string $id): JsonResponse
{
    try {
        $resource = $this->validateTenantAccess(
            $request,
            $id,
            \App\Models\YourModel::class
        );
        
        $resource->delete();
        
        $this->logInfo('Resource deleted', ['resource_id' => $id]);
        
        return $this->successResponse(
            ['id' => $id],
            'Resource deleted successfully.'
        );
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

### 6. Admin-Only Endpoint

```php
public function adminAction(Request $request): JsonResponse
{
    try {
        // Ensures user is admin or owner
        $this->requireAdmin($request);
        
        // Your admin logic here
        
        return $this->successResponse($data);
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

### 7. Owner-Only Endpoint

```php
public function ownerAction(Request $request): JsonResponse
{
    try {
        // Ensures user is owner
        $this->requireOwner($request);
        
        // Your owner logic here
        
        return $this->successResponse($data);
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

## Response Methods Cheat Sheet

### Success Responses

```php
// Simple success
return $this->successResponse($data);

// Success with message
return $this->successResponse($data, 'Action completed successfully.');

// Success with custom status
return $this->successResponse($data, 'Accepted', 202);

// Created response (201)
return $this->createdResponse($data, 'Resource created.');

// No content (204)
return $this->noContentResponse();

// Paginated response
return $this->paginatedResponse($paginator);

// Paginated with transformer
return $this->paginatedResponse($paginator, fn($item) => new ResourceClass($item));
```

### Error Responses

```php
// Generic error
return $this->errorResponse('ERROR_CODE', 'Error message', $details, 400);

// Not found
return $this->notFoundResponse('resource');
return $this->notFoundResponse('resource', 'Custom message');

// Unauthorized
return $this->unauthorizedResponse();
return $this->unauthorizedResponse('Custom message');

// Validation error
return $this->validationErrorResponse($errors);
```

---

## Tenant & Authorization Methods

```php
// Get current tenant
$tenant = $this->getTenant($request);

// Get organization
$organization = $this->getOrganization($request);

// Require specific role
$this->requireRole($request, 'admin');
$this->requireRole($request, ['admin', 'manager']);

// Require admin
$this->requireAdmin($request);

// Require owner
$this->requireOwner($request);

// Validate resource ownership
$this->validateTenantOwnership($request, $resource);

// Validate access and get resource
$resource = $this->validateTenantAccess($request, $id, YourModel::class);
```

---

## Logging Methods

```php
// Error logging
$this->logError('Error occurred', [
    'extra_context' => 'value',
]);

// Info logging
$this->logInfo('Action performed', [
    'resource_id' => $id,
]);

// Warning logging
$this->logWarning('Warning message', [
    'context' => 'value',
]);
```

**Automatic Context Included:**
- Controller class name
- User ID
- IP address
- Request URL

---

## Pagination Helpers

```php
// Get validated per_page from request (1-100)
$perPage = $this->getPaginationLimit($request);

// Use in pagination
$results = $query->paginate($this->getPaginationLimit($request));

// Override defaults in your controller
protected int $defaultPerPage = 50;  // Default: 20
protected int $maxPerPage = 200;     // Default: 100
```

---

## Filtering Helpers

```php
// Apply common filters (status, sorting)
$this->applyFilters($query, $request);

// Override for custom filtering
protected function applyFilters($query, Request $request)
{
    // Call parent for common filters
    parent::applyFilters($query, $request);
    
    // Add your custom filters
    if ($request->filled('custom_field')) {
        $query->where('custom_field', $request->input('custom_field'));
    }
    
    return $query;
}
```

---

## Exception Handling

```php
// Automatic handling of common exceptions
try {
    // Your code
} catch (\Exception $e) {
    return $this->handleException($e);
}
```

**Handles:**
- ModelNotFoundException → 404
- ValidationException → 422
- AuthenticationException → 401
- HttpException → Uses exception status code
- Other exceptions → 500

---

## Custom Response Examples

### Async Operation Response

```php
return $this->successResponse(
    ['job_id' => $jobId, 'status' => 'processing'],
    'Operation started. Check status with job ID.',
    202  // Accepted
);
```

### Conditional Response

```php
$success = $this->performAction();

return $success
    ? $this->successResponse($data, 'Action completed.')
    : $this->errorResponse('ACTION_FAILED', 'Action could not be completed.', [], 500);
```

### Response with Included Resources

```php
return $this->successResponse([
    'resource' => $resource,
    'related' => $related,
    'meta' => ['total_count' => $count],
]);
```

---

## Testing Your Controller

```php
public function test_index_returns_paginated_resources()
{
    $user = User::factory()->create();
    $tenant = Tenant::factory()->create();
    
    YourModel::factory()->count(30)->create(['tenant_id' => $tenant->id]);
    
    $response = $this->actingAs($user)
        ->getJson('/api/v1/your-resources?per_page=10');
    
    $response->assertStatus(200)
        ->assertJsonStructure([
            'success',
            'data',
            'meta' => ['pagination'],
        ]);
    
    $this->assertEquals(10, count($response->json('data')));
    $this->assertEquals(30, $response->json('meta.pagination.total'));
}

public function test_show_prevents_cross_tenant_access()
{
    $user = User::factory()->create();
    $tenant1 = Tenant::factory()->create();
    $tenant2 = Tenant::factory()->create();
    
    $resource = YourModel::factory()->create(['tenant_id' => $tenant2->id]);
    
    $response = $this->actingAs($user)
        ->getJson("/api/v1/your-resources/{$resource->id}");
    
    $response->assertStatus(403)
        ->assertJson(['success' => false]);
}
```

---

## Common Mistakes to Avoid

### Don't manually format responses

```php
// ❌ Don't do this
return response()->json(['success' => true, 'data' => $data]);

// ✅ Do this
return $this->successResponse($data);
```

### Don't duplicate getTenant()

```php
// ❌ Don't do this
private function getTenant($request) { ... }

// ✅ Do this (it's already in the base class)
$tenant = $this->getTenant($request);
```

### Don't forget tenant validation

```php
// ❌ Don't do this (allows cross-tenant access)
$resource = YourModel::findOrFail($id);

// ✅ Do this
$resource = $this->validateTenantAccess($request, $id, YourModel::class);
```

### Don't skip exception handling

```php
// ❌ Don't do this
public function index(Request $request) {
    return $this->successResponse($data);
}

// ✅ Do this
public function index(Request $request): JsonResponse {
    try {
        return $this->successResponse($data);
    } catch (\Exception $e) {
        return $this->handleException($e);
    }
}
```

---

## Need Help?

- Full documentation: `/home/calounx/repositories/mentat/PHASE1_BASE_CONTROLLER_IMPLEMENTATION.md`
- Refactoring plan: `/home/calounx/repositories/mentat/REFACTORING_IMPLEMENTATION_PLAN.md`
- Example controllers: `app/Http/Controllers/Api/V1/SiteController.php`

---

**Last Updated:** January 3, 2026  
**Version:** 1.0
