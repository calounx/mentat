<?php

namespace App\Http\Controllers\Concerns;

use App\Models\Tenant;
use Illuminate\Http\Request;

/**
 * Has Tenant Scoping Trait.
 *
 * Provides tenant scoping functionality for controllers.
 * Eliminates code duplication across controllers that need tenant context.
 */
trait HasTenantScoping
{
    /**
     * Get the current tenant from the authenticated user.
     *
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function getTenant(Request $request): Tenant
    {
        $tenant = $request->user()->currentTenant();

        if (! $tenant || ! $tenant->isActive()) {
            abort(403, 'No active tenant found.');
        }

        return $tenant;
    }

    /**
     * Get the current tenant ID.
     */
    protected function getTenantId(Request $request): string
    {
        return $this->getTenant($request)->id;
    }

    /**
     * Check if tenant can perform action (quota check helper).
     */
    protected function tenantCan(Tenant $tenant, string $action): bool
    {
        return match ($action) {
            'create_site' => $tenant->canCreateSite(),
            'create_backup' => $tenant->canCreateBackup(),
            default => true,
        };
    }

    /**
     * Verify resource belongs to tenant.
     *
     * @param  mixed  $resource
     */
    protected function belongsToTenant($resource, Tenant $tenant, string $tenantIdField = 'tenant_id'): bool
    {
        if (is_object($resource) && isset($resource->{$tenantIdField})) {
            return $resource->{$tenantIdField} === $tenant->id;
        }

        if (is_array($resource) && isset($resource[$tenantIdField])) {
            return $resource[$tenantIdField] === $tenant->id;
        }

        return false;
    }
}
