<?php

namespace Tests\Concerns;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;

/**
 * Trait to help with tenant isolation testing.
 *
 * This trait provides helper methods to quickly set up multi-tenant test scenarios
 * and verify tenant isolation is working correctly.
 */
trait WithTenantIsolation
{
    /**
     * Create a tenant with an organization and user.
     *
     * @return array{tenant: Tenant, organization: Organization, user: User}
     */
    protected function createTenantWithUser(
        array $tenantAttributes = [],
        array $userAttributes = [],
        string $userRole = 'owner'
    ): array {
        $organization = Organization::factory()->create();

        $tenant = Tenant::factory()->create(array_merge([
            'organization_id' => $organization->id,
            'status' => 'active',
        ], $tenantAttributes));

        $organization->update(['default_tenant_id' => $tenant->id]);

        $user = User::factory()->create(array_merge([
            'organization_id' => $organization->id,
            'role' => $userRole,
        ], $userAttributes));

        return [
            'tenant' => $tenant,
            'organization' => $organization,
            'user' => $user,
        ];
    }

    /**
     * Create multiple tenants with users for testing cross-tenant isolation.
     */
    protected function createMultipleTenants(int $count = 2): array
    {
        $tenants = [];

        for ($i = 0; $i < $count; $i++) {
            $tenants[] = $this->createTenantWithUser([
                'name' => "Tenant {$i}",
                'slug' => "tenant-{$i}",
            ]);
        }

        return $tenants;
    }

    /**
     * Assert that a model query only returns records for the specified tenant.
     */
    protected function assertModelFiltersByTenant(string $modelClass, Tenant $tenant, User $user): void
    {
        $this->actingAs($user);

        $records = $modelClass::all();

        foreach ($records as $record) {
            $this->assertEquals(
                $tenant->id,
                $record->tenant_id,
                "Model {$modelClass} returned record from wrong tenant"
            );
        }
    }

    /**
     * Assert that a user cannot access a specific record from another tenant.
     */
    protected function assertCannotAccessCrossTenant(User $user, object $record): void
    {
        $this->actingAs($user);

        $modelClass = get_class($record);
        $found = $modelClass::find($record->id);

        $this->assertNull(
            $found,
            "User was able to access {$modelClass} record from another tenant"
        );
    }

    /**
     * Assert that a user can access a specific record from their own tenant.
     */
    protected function assertCanAccessSameTenant(User $user, object $record): void
    {
        $this->actingAs($user);

        $modelClass = get_class($record);
        $found = $modelClass::find($record->id);

        $this->assertNotNull(
            $found,
            "User could not access {$modelClass} record from their own tenant"
        );
        $this->assertEquals(
            $record->id,
            $found->id,
            'Found record ID does not match expected record'
        );
    }

    /**
     * Create test data in multiple tenants and verify isolation.
     */
    protected function createCrossTenantData(string $modelClass, array $attributes = []): array
    {
        $tenants = $this->createMultipleTenants(2);

        $data = [];
        foreach ($tenants as $index => $tenantData) {
            $data[$index] = [
                'tenant' => $tenantData['tenant'],
                'user' => $tenantData['user'],
                'records' => $modelClass::factory()
                    ->count(3)
                    ->create(array_merge([
                        'tenant_id' => $tenantData['tenant']->id,
                    ], $attributes)),
            ];
        }

        return $data;
    }

    /**
     * Assert that queries cannot leak data across tenants.
     */
    protected function assertNoDataLeakage(string $modelClass, array $crossTenantData): void
    {
        foreach ($crossTenantData as $index => $data) {
            $this->actingAs($data['user']);

            $records = $modelClass::all();

            // Should only see own tenant's records
            $this->assertCount(
                $data['records']->count(),
                $records,
                "Data leakage detected for {$modelClass}"
            );

            // All returned records should belong to the current tenant
            foreach ($records as $record) {
                $this->assertEquals(
                    $data['tenant']->id,
                    $record->tenant_id,
                    "Found record from wrong tenant in {$modelClass}"
                );
            }

            // Should not see other tenants' records
            foreach ($crossTenantData as $otherIndex => $otherData) {
                if ($otherIndex !== $index) {
                    foreach ($otherData['records'] as $otherRecord) {
                        $this->assertCannotAccessCrossTenant($data['user'], $otherRecord);
                    }
                }
            }
        }
    }

    /**
     * Test that a specific endpoint enforces tenant isolation.
     *
     * @param  string  $method  HTTP method (get, post, put, delete)
     * @param  string  $uri  Endpoint URI
     * @param  User  $authenticatedUser  User making the request
     * @param  string  $expectedTenantId  Expected tenant ID in response data
     * @param  array  $payload  Optional request payload
     */
    protected function assertEndpointEnforcesTenantIsolation(
        string $method,
        string $uri,
        User $authenticatedUser,
        string $expectedTenantId,
        array $payload = []
    ): void {
        $this->actingAs($authenticatedUser);

        $response = match (strtolower($method)) {
            'get' => $this->getJson($uri),
            'post' => $this->postJson($uri, $payload),
            'put' => $this->putJson($uri, $payload),
            'patch' => $this->patchJson($uri, $payload),
            'delete' => $this->deleteJson($uri),
            default => throw new \InvalidArgumentException("Unsupported HTTP method: {$method}"),
        };

        if ($response->status() === 200 || $response->status() === 201) {
            $data = $response->json('data');

            if (is_array($data)) {
                // For list endpoints, check all items
                if (isset($data[0])) {
                    foreach ($data as $item) {
                        if (isset($item['tenant_id'])) {
                            $this->assertEquals(
                                $expectedTenantId,
                                $item['tenant_id'],
                                "Endpoint {$uri} returned data from wrong tenant"
                            );
                        }
                    }
                } elseif (isset($data['tenant_id'])) {
                    // Single item response
                    $this->assertEquals(
                        $expectedTenantId,
                        $data['tenant_id'],
                        "Endpoint {$uri} returned data from wrong tenant"
                    );
                }
            }
        }
    }

    /**
     * Assert that an endpoint returns 404 for cross-tenant resource access.
     */
    protected function assertEndpointRejectsCrossTenantAccess(
        string $method,
        string $uri,
        User $authenticatedUser
    ): void {
        $this->actingAs($authenticatedUser);

        $response = match (strtolower($method)) {
            'get' => $this->getJson($uri),
            'post' => $this->postJson($uri),
            'put' => $this->putJson($uri),
            'patch' => $this->patchJson($uri),
            'delete' => $this->deleteJson($uri),
            default => throw new \InvalidArgumentException("Unsupported HTTP method: {$method}"),
        };

        $this->assertEquals(
            404,
            $response->status(),
            "Endpoint {$uri} should return 404 for cross-tenant access but returned {$response->status()}"
        );
    }

    /**
     * Create users with different roles for a tenant.
     */
    protected function createUsersWithRoles(Tenant $tenant, Organization $organization): array
    {
        return [
            'owner' => User::factory()->create([
                'organization_id' => $organization->id,
                'role' => 'owner',
            ]),
            'admin' => User::factory()->create([
                'organization_id' => $organization->id,
                'role' => 'admin',
            ]),
            'member' => User::factory()->create([
                'organization_id' => $organization->id,
                'role' => 'member',
            ]),
            'viewer' => User::factory()->create([
                'organization_id' => $organization->id,
                'role' => 'viewer',
            ]),
        ];
    }

    /**
     * Assert that a callback runs without cross-tenant data leakage.
     */
    protected function assertIsolatedExecution(callable $callback, User $user, Tenant $tenant): void
    {
        $this->actingAs($user);

        $result = $callback();

        // If result is a collection, verify all items belong to the correct tenant
        if (is_iterable($result)) {
            foreach ($result as $item) {
                if (isset($item->tenant_id)) {
                    $this->assertEquals(
                        $tenant->id,
                        $item->tenant_id,
                        'Callback returned data from wrong tenant'
                    );
                }
            }
        }

        // If result is a single model with tenant_id
        if (is_object($result) && isset($result->tenant_id)) {
            $this->assertEquals(
                $tenant->id,
                $result->tenant_id,
                'Callback returned model from wrong tenant'
            );
        }
    }
}
