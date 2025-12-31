<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ensure Tenant Context Middleware
 *
 * This middleware ensures that authenticated users have an active tenant context.
 * It replaces the duplicated getTenant() methods in controllers by setting
 * the tenant in request attributes for easy access throughout the request lifecycle.
 *
 * Usage in routes:
 * Route::middleware(['auth:sanctum', 'tenant'])->group(function () {
 *     // Your routes here
 * });
 *
 * Access tenant in controllers:
 * $tenant = $request->get('tenant');
 */
class EnsureTenantContext
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // Skip if user is not authenticated
        if (!$request->user()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'UNAUTHENTICATED',
                    'message' => 'User is not authenticated.',
                ],
            ], 401);
        }

        // Get current tenant for user
        $tenant = $request->user()->currentTenant();

        // Ensure tenant exists
        if (!$tenant) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'NO_TENANT',
                    'message' => 'No active tenant found. Please create or select a tenant.',
                ],
            ], 403);
        }

        // Ensure tenant is active
        if (!$tenant->isActive()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'TENANT_INACTIVE',
                    'message' => 'Your tenant account is not active. Please contact support.',
                    'details' => [
                        'tenant_id' => $tenant->id,
                        'status' => $tenant->status,
                    ],
                ],
            ], 403);
        }

        // Set tenant in request attributes for easy access
        $request->attributes->set('tenant', $tenant);

        // Also make it available via request->tenant for convenience
        $request->merge(['_tenant' => $tenant]);

        return $next($request);
    }
}
