<?php

namespace App\Http\Controllers;

use App\Models\Tenant;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Http\Request;

abstract class Controller
{
    use AuthorizesRequests;

    /**
     * Get the current tenant from the request.
     *
     * This method retrieves the tenant set by the EnsureTenantContext middleware.
     *
     * @throws \RuntimeException if tenant is not set
     */
    protected function getTenant(Request $request): Tenant
    {
        $tenant = $request->attributes->get('tenant');

        if (! $tenant) {
            // Fallback: try to get from user
            $tenant = $request->user()?->currentTenant();
        }

        if (! $tenant) {
            throw new \RuntimeException('No tenant context found');
        }

        return $tenant;
    }
}
