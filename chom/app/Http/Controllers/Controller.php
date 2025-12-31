<?php

namespace App\Http\Controllers;

use App\Models\Tenant;
use Illuminate\Http\Request;

abstract class Controller
{
    /**
     * Get the current tenant from the request.
     *
     * This method retrieves the tenant set by the EnsureTenantContext middleware.
     *
     * @param Request $request
     * @return Tenant
     * @throws \RuntimeException if tenant is not set
     */
    protected function getTenant(Request $request): Tenant
    {
        $tenant = $request->attributes->get('tenant');

        if (!$tenant) {
            // Fallback: try to get from user
            $tenant = $request->user()?->currentTenant();
        }

        if (!$tenant) {
            throw new \RuntimeException('No tenant context found');
        }

        return $tenant;
    }
}
