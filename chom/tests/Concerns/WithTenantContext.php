<?php

declare(strict_types=1);

namespace Tests\Concerns;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;

/**
 * Provides helper methods for creating sites with proper tenant context
 */
trait WithTenantContext
{
    /**
     * Create a user with organization and tenant
     */
    protected function createUserWithTenant(array $userAttributes = [], array $tenantAttributes = []): User
    {
        $organization = Organization::factory()->create();

        $tenant = Tenant::factory()->create(array_merge([
            'organization_id' => $organization->id,
        ], $tenantAttributes));

        return User::factory()->create(array_merge([
            'organization_id' => $organization->id,
        ], $userAttributes));
    }

    /**
     * Get the tenant for a user
     */
    protected function getTenantForUser(User $user): ?Tenant
    {
        return $user->currentTenant();
    }
}
