<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Contracts;

use App\Models\Organization;
use App\Models\User;

/**
 * Tenant Resolver Service Contract
 *
 * Defines the contract for tenant resolution and management operations.
 */
interface TenantResolverInterface
{
    /**
     * Resolve current tenant from request context.
     *
     * @return Organization|null Current tenant
     */
    public function resolve(): ?Organization;

    /**
     * Get current tenant ID.
     *
     * @return string|null Tenant ID
     */
    public function getCurrentTenantId(): ?string;

    /**
     * Switch to a different tenant context.
     *
     * @param string $tenantId Target tenant ID
     * @param string $userId User performing the switch
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function switchTenant(string $tenantId, string $userId): bool;

    /**
     * Create a new organization (tenant).
     *
     * @param array $data Organization data
     * @param string $ownerId Owner user ID
     * @return Organization Created organization
     * @throws \RuntimeException
     */
    public function createOrganization(array $data, string $ownerId): Organization;

    /**
     * Check if user belongs to tenant.
     *
     * @param string $userId User ID
     * @param string $tenantId Tenant ID
     * @return bool Membership status
     */
    public function userBelongsToTenant(string $userId, string $tenantId): bool;

    /**
     * Get all users in a tenant.
     *
     * @param string $tenantId Tenant ID
     * @return \Illuminate\Database\Eloquent\Collection
     */
    public function getTenantUsers(string $tenantId): \Illuminate\Database\Eloquent\Collection;

    /**
     * Enforce tenant isolation for a query.
     *
     * @param \Illuminate\Database\Eloquent\Builder $query
     * @param string|null $tenantId Optional tenant ID (uses current if null)
     * @return \Illuminate\Database\Eloquent\Builder
     */
    public function scopeToTenant(\Illuminate\Database\Eloquent\Builder $query, ?string $tenantId = null): \Illuminate\Database\Eloquent\Builder;
}
