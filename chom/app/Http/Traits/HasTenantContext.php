<?php

namespace App\Http\Traits;

use Illuminate\Http\Request;

/**
 * Has Tenant Context Trait
 *
 * Provides tenant resolution and authorization helpers for multi-tenant controllers.
 * Centralizes tenant context logic to avoid duplication across controllers.
 *
 * Note: This assumes your User model has currentTenant() and organization relationships.
 * Adjust the implementation based on your actual tenant/organization structure.
 *
 * @package App\Http\Traits
 */
trait HasTenantContext
{
    /**
     * Get the current tenant from the authenticated user.
     *
     * Validates that the tenant exists and is active.
     *
     * @param Request $request
     * @return mixed The tenant instance
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function getTenant(Request $request)
    {
        $user = $request->user();

        if (!$user) {
            abort(401, 'Unauthenticated.');
        }

        // Assuming User model has a currentTenant() method
        // Adjust based on your actual implementation
        $tenant = method_exists($user, 'currentTenant') 
            ? $user->currentTenant() 
            : ($user->tenant ?? null);

        if (!$tenant) {
            abort(403, 'No active tenant found.');
        }

        // Check if tenant is active (if your tenant model has a status field)
        if (method_exists($tenant, 'isActive') && !$tenant->isActive()) {
            abort(403, 'Tenant is not active.');
        }

        return $tenant;
    }

    /**
     * Get the current organization from the authenticated user.
     *
     * @param Request $request
     * @return mixed The organization instance
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function getOrganization(Request $request)
    {
        $user = $request->user();

        if (!$user) {
            abort(401, 'Unauthenticated.');
        }

        $organization = $user->organization ?? null;

        if (!$organization) {
            abort(403, 'No organization found.');
        }

        return $organization;
    }

    /**
     * Ensure the current user has a specific role.
     *
     * @param Request $request
     * @param string|array $roles Required role(s)
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function requireRole(Request $request, $roles): void
    {
        $user = $request->user();
        $roles = (array) $roles;

        if (!$user) {
            abort(401, 'Unauthenticated.');
        }

        $userRole = $user->role ?? null;

        if (!in_array($userRole, $roles, true)) {
            abort(403, 'You do not have permission to perform this action.');
        }
    }

    /**
     * Ensure the current user is an admin or owner.
     *
     * @param Request $request
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function requireAdmin(Request $request): void
    {
        $user = $request->user();

        if (!$user) {
            abort(401, 'Unauthenticated.');
        }

        // Assuming User model has isAdmin() method
        // Adjust based on your actual implementation
        $isAdmin = method_exists($user, 'isAdmin') 
            ? $user->isAdmin() 
            : in_array($user->role ?? '', ['admin', 'owner'], true);

        if (!$isAdmin) {
            abort(403, 'You do not have permission to perform this action.');
        }
    }

    /**
     * Ensure the current user is the owner.
     *
     * @param Request $request
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function requireOwner(Request $request): void
    {
        $user = $request->user();

        if (!$user) {
            abort(401, 'Unauthenticated.');
        }

        // Assuming User model has isOwner() method
        // Adjust based on your actual implementation
        $isOwner = method_exists($user, 'isOwner') 
            ? $user->isOwner() 
            : ($user->role ?? '') === 'owner';

        if (!$isOwner) {
            abort(403, 'Only the organization owner can perform this action.');
        }
    }

    /**
     * Validate that a resource belongs to the current tenant.
     *
     * @param Request $request
     * @param mixed $resource The resource to validate
     * @param string $tenantIdField The field name for tenant ID (default: 'tenant_id')
     * @return void
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function validateTenantOwnership(Request $request, $resource, string $tenantIdField = 'tenant_id'): void
    {
        $tenant = $this->getTenant($request);

        $resourceTenantId = is_object($resource) 
            ? ($resource->{$tenantIdField} ?? null)
            : ($resource[$tenantIdField] ?? null);

        if ($resourceTenantId !== $tenant->id) {
            abort(403, 'You do not have access to this resource.');
        }
    }
}
