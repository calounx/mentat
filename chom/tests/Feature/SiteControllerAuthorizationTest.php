<?php

namespace Tests\Feature;

use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SiteControllerAuthorizationTest extends TestCase
{
    use RefreshDatabase;

    private User $ownerUserTenant1;
    private User $adminUserTenant1;
    private User $memberUserTenant1;
    private User $viewerUserTenant1;
    private User $ownerUserTenant2;
    private Tenant $tenant1;
    private Tenant $tenant2;
    private Organization $org1;
    private Organization $org2;

    protected function setUp(): void
    {
        parent::setUp();

        // Create two separate organizations and tenants
        $this->org1 = Organization::factory()->create(['name' => 'Organization 1']);
        $this->org2 = Organization::factory()->create(['name' => 'Organization 2']);

        $this->tenant1 = Tenant::factory()->create([
            'organization_id' => $this->org1->id,
            'name' => 'Tenant 1',
            'status' => 'active',
        ]);
        $this->tenant2 = Tenant::factory()->create([
            'organization_id' => $this->org2->id,
            'name' => 'Tenant 2',
            'status' => 'active',
        ]);

        // Set default tenants for organizations
        $this->org1->update(['default_tenant_id' => $this->tenant1->id]);
        $this->org2->update(['default_tenant_id' => $this->tenant2->id]);

        // Create users with different roles for tenant 1
        $this->ownerUserTenant1 = User::factory()->create([
            'organization_id' => $this->org1->id,
            'role' => 'owner',
        ]);
        $this->adminUserTenant1 = User::factory()->create([
            'organization_id' => $this->org1->id,
            'role' => 'admin',
        ]);
        $this->memberUserTenant1 = User::factory()->create([
            'organization_id' => $this->org1->id,
            'role' => 'member',
        ]);
        $this->viewerUserTenant1 = User::factory()->create([
            'organization_id' => $this->org1->id,
            'role' => 'viewer',
        ]);

        // Create user for tenant 2
        $this->ownerUserTenant2 = User::factory()->create([
            'organization_id' => $this->org2->id,
            'role' => 'owner',
        ]);
    }

    /**
     * Test that users can only view sites from their own tenant.
     */
    public function test_users_cannot_view_sites_from_other_tenants(): void
    {
        // Create sites for both tenants
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // User from tenant 1 should only see their site
        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->getJson('/api/v1/sites');

        $response->assertOk();
        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals($siteTenant1->id, $data[0]['id']);

        // User from tenant 2 should only see their site
        Sanctum::actingAs($this->ownerUserTenant2);
        $response = $this->getJson('/api/v1/sites');

        $response->assertOk();
        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals($siteTenant2->id, $data[0]['id']);
    }

    /**
     * Test that users cannot access site details from another tenant.
     */
    public function test_users_cannot_access_site_details_from_other_tenants(): void
    {
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // User from tenant 1 trying to access tenant 2's site
        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->getJson("/api/v1/sites/{$siteTenant2->id}");

        $response->assertNotFound(); // Should not find due to tenant scope

        // Verify they can access their own site
        $response = $this->getJson("/api/v1/sites/{$siteTenant1->id}");
        $response->assertOk();
        $this->assertEquals($siteTenant1->id, $response->json('data.id'));
    }

    /**
     * Test that users cannot update sites from another tenant.
     */
    public function test_users_cannot_update_sites_from_other_tenants(): void
    {
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // User from tenant 1 trying to update tenant 2's site
        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->putJson("/api/v1/sites/{$siteTenant2->id}", [
            'php_version' => '8.4',
        ]);

        $response->assertNotFound(); // Should not find due to tenant scope

        // Verify they can update their own site
        $response = $this->putJson("/api/v1/sites/{$siteTenant1->id}", [
            'php_version' => '8.4',
        ]);
        $response->assertOk();
    }

    /**
     * Test that users cannot delete sites from another tenant.
     */
    public function test_users_cannot_delete_sites_from_other_tenants(): void
    {
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // User from tenant 1 trying to delete tenant 2's site
        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->deleteJson("/api/v1/sites/{$siteTenant2->id}");

        $response->assertNotFound(); // Should not find due to tenant scope

        // Verify the site still exists
        $this->assertDatabaseHas('sites', ['id' => $siteTenant2->id]);
    }

    /**
     * Test that viewers cannot create sites.
     */
    public function test_viewers_cannot_create_sites(): void
    {
        VpsServer::factory()->create(['status' => 'active', 'allocation_mode' => 'shared']);

        Sanctum::actingAs($this->viewerUserTenant1);
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'viewer-test.com',
            'site_type' => 'wordpress',
        ]);

        $response->assertForbidden();
    }

    /**
     * Test that members can create sites.
     */
    public function test_members_can_create_sites(): void
    {
        VpsServer::factory()->create(['status' => 'active', 'allocation_mode' => 'shared']);

        Sanctum::actingAs($this->memberUserTenant1);
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'member-test.com',
            'site_type' => 'wordpress',
        ]);

        $response->assertStatus(201);
        $this->assertDatabaseHas('sites', [
            'domain' => 'member-test.com',
            'tenant_id' => $this->tenant1->id,
        ]);
    }

    /**
     * Test that admins can create sites.
     */
    public function test_admins_can_create_sites(): void
    {
        VpsServer::factory()->create(['status' => 'active', 'allocation_mode' => 'shared']);

        Sanctum::actingAs($this->adminUserTenant1);
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'admin-test.com',
            'site_type' => 'wordpress',
        ]);

        $response->assertStatus(201);
        $this->assertDatabaseHas('sites', [
            'domain' => 'admin-test.com',
            'tenant_id' => $this->tenant1->id,
        ]);
    }

    /**
     * Test that owners can create sites.
     */
    public function test_owners_can_create_sites(): void
    {
        VpsServer::factory()->create(['status' => 'active', 'allocation_mode' => 'shared']);

        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'owner-test.com',
            'site_type' => 'wordpress',
        ]);

        $response->assertStatus(201);
        $this->assertDatabaseHas('sites', [
            'domain' => 'owner-test.com',
            'tenant_id' => $this->tenant1->id,
        ]);
    }

    /**
     * Test that viewers cannot update sites.
     */
    public function test_viewers_cannot_update_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id]);

        Sanctum::actingAs($this->viewerUserTenant1);
        $response = $this->putJson("/api/v1/sites/{$site->id}", [
            'php_version' => '8.4',
        ]);

        $response->assertForbidden();
    }

    /**
     * Test that members can update sites.
     */
    public function test_members_can_update_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id]);

        Sanctum::actingAs($this->memberUserTenant1);
        $response = $this->putJson("/api/v1/sites/{$site->id}", [
            'php_version' => '8.4',
        ]);

        $response->assertOk();
    }

    /**
     * Test that viewers cannot delete sites.
     */
    public function test_viewers_cannot_delete_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id]);

        Sanctum::actingAs($this->viewerUserTenant1);
        $response = $this->deleteJson("/api/v1/sites/{$site->id}");

        $response->assertForbidden();
    }

    /**
     * Test that members cannot delete sites.
     */
    public function test_members_cannot_delete_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id]);

        Sanctum::actingAs($this->memberUserTenant1);
        $response = $this->deleteJson("/api/v1/sites/{$site->id}");

        $response->assertForbidden();
    }

    /**
     * Test that admins can delete sites.
     */
    public function test_admins_can_delete_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id, 'status' => 'active']);

        Sanctum::actingAs($this->adminUserTenant1);
        $response = $this->deleteJson("/api/v1/sites/{$site->id}");

        $response->assertOk();
        $this->assertSoftDeleted('sites', ['id' => $site->id]);
    }

    /**
     * Test that owners can delete sites.
     */
    public function test_owners_can_delete_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id, 'status' => 'active']);

        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->deleteJson("/api/v1/sites/{$site->id}");

        $response->assertOk();
        $this->assertSoftDeleted('sites', ['id' => $site->id]);
    }

    /**
     * Test that users cannot enable sites from another tenant.
     */
    public function test_users_cannot_enable_sites_from_other_tenants(): void
    {
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'status' => 'disabled',
        ]);

        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$siteTenant2->id}/enable");

        $response->assertNotFound();
    }

    /**
     * Test that users cannot disable sites from another tenant.
     */
    public function test_users_cannot_disable_sites_from_other_tenants(): void
    {
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'status' => 'active',
        ]);

        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$siteTenant2->id}/disable");

        $response->assertNotFound();
    }

    /**
     * Test that users cannot issue SSL for sites from another tenant.
     */
    public function test_users_cannot_issue_ssl_for_sites_from_other_tenants(): void
    {
        $vps = VpsServer::factory()->create();
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'vps_id' => $vps->id,
        ]);

        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$siteTenant2->id}/ssl");

        $response->assertNotFound();
    }

    /**
     * Test that members can enable sites in their tenant.
     */
    public function test_members_can_enable_sites(): void
    {
        $vps = VpsServer::factory()->create();
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'vps_id' => $vps->id,
            'status' => 'disabled',
        ]);

        Sanctum::actingAs($this->memberUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$site->id}/enable");

        // Will fail due to VPS manager call, but authorization should pass
        $this->assertNotEquals(403, $response->status());
    }

    /**
     * Test that members can disable sites in their tenant.
     */
    public function test_members_can_disable_sites(): void
    {
        $vps = VpsServer::factory()->create();
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'vps_id' => $vps->id,
            'status' => 'active',
        ]);

        Sanctum::actingAs($this->memberUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$site->id}/disable");

        // Will fail due to VPS manager call, but authorization should pass
        $this->assertNotEquals(403, $response->status());
    }

    /**
     * Test that viewers cannot enable sites.
     */
    public function test_viewers_cannot_enable_sites(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'status' => 'disabled',
        ]);

        Sanctum::actingAs($this->viewerUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$site->id}/enable");

        $response->assertForbidden();
    }

    /**
     * Test that viewers cannot disable sites.
     */
    public function test_viewers_cannot_disable_sites(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'status' => 'active',
        ]);

        Sanctum::actingAs($this->viewerUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$site->id}/disable");

        $response->assertForbidden();
    }

    /**
     * Test that viewers cannot issue SSL certificates.
     */
    public function test_viewers_cannot_issue_ssl(): void
    {
        $vps = VpsServer::factory()->create();
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'vps_id' => $vps->id,
        ]);

        Sanctum::actingAs($this->viewerUserTenant1);
        $response = $this->postJson("/api/v1/sites/{$site->id}/ssl");

        $response->assertForbidden();
    }

    /**
     * Test that unauthenticated users cannot access any endpoints.
     */
    public function test_unauthenticated_users_cannot_access_sites(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->tenant1->id]);

        $this->getJson('/api/v1/sites')->assertUnauthorized();
        $this->getJson("/api/v1/sites/{$site->id}")->assertUnauthorized();
        $this->postJson('/api/v1/sites', [])->assertUnauthorized();
        $this->putJson("/api/v1/sites/{$site->id}", [])->assertUnauthorized();
        $this->deleteJson("/api/v1/sites/{$site->id}")->assertUnauthorized();
    }

    /**
     * Test that authorization is checked even with direct database access.
     */
    public function test_authorization_prevents_direct_access_via_id(): void
    {
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // Even if tenant 1 user knows the ID of tenant 2's site, they cannot access it
        Sanctum::actingAs($this->ownerUserTenant1);

        $endpoints = [
            ['method' => 'get', 'uri' => "/api/v1/sites/{$siteTenant2->id}"],
            ['method' => 'put', 'uri' => "/api/v1/sites/{$siteTenant2->id}"],
            ['method' => 'delete', 'uri' => "/api/v1/sites/{$siteTenant2->id}"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$siteTenant2->id}/enable"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$siteTenant2->id}/disable"],
            ['method' => 'get', 'uri' => "/api/v1/sites/{$siteTenant2->id}/metrics"],
        ];

        foreach ($endpoints as $endpoint) {
            $response = match($endpoint['method']) {
                'get' => $this->getJson($endpoint['uri']),
                'post' => $this->postJson($endpoint['uri']),
                'put' => $this->putJson($endpoint['uri']),
                'delete' => $this->deleteJson($endpoint['uri']),
            };

            $this->assertEquals(404, $response->status(),
                "Endpoint {$endpoint['method']} {$endpoint['uri']} should return 404 for cross-tenant access");
        }
    }

    /**
     * Test that the policy correctly checks tenant ownership.
     */
    public function test_policy_belongs_to_tenant_check(): void
    {
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // Tenant 1 user should pass policy for their own site
        Sanctum::actingAs($this->ownerUserTenant1);
        $this->assertTrue(auth()->user()->can('view', $siteTenant1));

        // Tenant 1 user should fail policy for tenant 2's site
        $this->assertFalse(auth()->user()->can('view', $siteTenant2));
    }

    /**
     * Test that search filtering respects tenant boundaries.
     */
    public function test_search_filtering_respects_tenant_boundaries(): void
    {
        $siteTenant1 = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'domain' => 'example.com',
        ]);
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'domain' => 'example.org',
        ]);

        // User from tenant 1 searching for 'example'
        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->getJson('/api/v1/sites?search=example');

        $response->assertOk();
        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals('example.com', $data[0]['domain']);
    }

    /**
     * Test that status filtering respects tenant boundaries.
     */
    public function test_status_filtering_respects_tenant_boundaries(): void
    {
        $siteTenant1Active = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'status' => 'active',
        ]);
        $siteTenant2Active = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'status' => 'active',
        ]);

        // User from tenant 1 filtering by status
        Sanctum::actingAs($this->ownerUserTenant1);
        $response = $this->getJson('/api/v1/sites?status=active');

        $response->assertOk();
        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals($siteTenant1Active->id, $data[0]['id']);
    }
}
