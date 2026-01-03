<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Middleware;

use App\Modules\Tenancy\Contracts\TenantResolverInterface;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * Enforce Tenant Isolation Middleware
 *
 * Ensures that all requests are properly scoped to the current tenant
 * and prevents cross-tenant data access.
 */
class EnforceTenantIsolation
{
    public function __construct(
        private readonly TenantResolverInterface $tenantResolver
    ) {
    }

    /**
     * Handle an incoming request.
     *
     * @param Request $request
     * @param Closure $next
     * @return Response
     */
    public function handle(Request $request, Closure $next): Response
    {
        $tenant = $this->tenantResolver->resolve();

        if (!$tenant) {
            Log::warning('Request without valid tenant context', [
                'url' => $request->url(),
                'user_id' => auth()->id(),
            ]);

            return response()->json([
                'error' => 'No valid tenant context',
                'message' => 'You must be associated with an organization to access this resource.',
            ], 403);
        }

        if (!$tenant->isActive()) {
            Log::warning('Request to inactive tenant', [
                'tenant_id' => $tenant->id,
                'url' => $request->url(),
            ]);

            return response()->json([
                'error' => 'Tenant inactive',
                'message' => 'Your organization is currently inactive.',
            ], 403);
        }

        // Store tenant ID in request for easy access
        $request->attributes->set('tenant_id', $tenant->id);

        return $next($request);
    }
}
