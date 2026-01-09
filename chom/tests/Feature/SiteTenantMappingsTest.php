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

/**
 * Site Tenant Mappings Test
 *
 * Verifies that the site-to-tenant mappings endpoint works correctly
 * and is properly restricted to owner role only.
 *
 * This endpoint is used by observability exporters (Prometheus)
 * to get site→tenant→organization mappings for proper labeling.
 */
class SiteTenantMappingsTest extends TestCase
{
    use RefreshDatabase;

    private Organization $org;
    private Tenant $tenant;
    private User $ownerUser;
    private User $adminUser;
    private User $memberUser;
    private Site $site1;
    private Site $site2;
    private VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        // Create organization and tenant
        $this->org = Organization::factory()->create(['name' => 'Test Organization']);
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $this->org->id,
            'status' => 'active',
        ]);

        // Create users with different roles
        $this->ownerUser = User::factory()->create([
            'organization_id' => $this->org->id,
            'current_tenant_id' => $this->tenant->id,
            'role' => 'owner',
        ]);

        $this->adminUser = User::factory()->create([
            'organization_id' => $this->org->id,
            'current_tenant_id' => $this->tenant->id,
            'role' => 'admin',
        ]);

        $this->memberUser = User::factory()->create([
            'organization_id' => $this->org->id,
            'current_tenant_id' => $this->tenant->id,
            'role' => 'member',
        ]);

        // Create VPS server and sites
        $this->vps = VpsServer::factory()->create(['status' => 'active']);

        $this->site1 = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => $this->vps->id,
            'domain' => 'site1.example.com',
        ]);

        $this->site2 = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => $this->vps->id,
            'domain' => 'site2.example.com',
        ]);
    }

    /** @test */
    public function owner_can_access_tenant_mappings_endpoint()
    {
        Sanctum::actingAs($this->ownerUser);

        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'sites' => [
                    '*' => [
                        'domain',
                        'tenant_id',
                        'organization_id',
                        'vps_id',
                    ],
                ],
            ],
        ]);

        $response->assertJson([
            'success' => true,
        ]);
    }

    /** @test */
    public function admin_cannot_access_tenant_mappings_endpoint()
    {
        Sanctum::actingAs($this->adminUser);

        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(403);
        $response->assertJson([
            'success' => false,
        ]);
    }

    /** @test */
    public function member_cannot_access_tenant_mappings_endpoint()
    {
        Sanctum::actingAs($this->memberUser);

        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(403);
        $response->assertJson([
            'success' => false,
        ]);
    }

    /** @test */
    public function unauthenticated_user_cannot_access_tenant_mappings_endpoint()
    {
        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(401);
    }

    /** @test */
    public function tenant_mappings_response_includes_all_sites_with_correct_data()
    {
        Sanctum::actingAs($this->ownerUser);

        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(200);

        $sites = $response->json('data.sites');
        $this->assertIsArray($sites);
        $this->assertGreaterThanOrEqual(2, count($sites));

        // Find our test sites in the response
        $site1Data = collect($sites)->firstWhere('domain', 'site1.example.com');
        $site2Data = collect($sites)->firstWhere('domain', 'site2.example.com');

        $this->assertNotNull($site1Data);
        $this->assertNotNull($site2Data);

        // Verify site1 data
        $this->assertEquals($this->tenant->id, $site1Data['tenant_id']);
        $this->assertEquals($this->org->id, $site1Data['organization_id']);
        $this->assertEquals($this->vps->id, $site1Data['vps_id']);

        // Verify site2 data
        $this->assertEquals($this->tenant->id, $site2Data['tenant_id']);
        $this->assertEquals($this->org->id, $site2Data['organization_id']);
        $this->assertEquals($this->vps->id, $site2Data['vps_id']);
    }

    /** @test */
    public function tenant_mappings_includes_sites_from_all_tenants()
    {
        // Create a second organization with its own tenant and site
        $org2 = Organization::factory()->create(['name' => 'Organization 2']);
        $tenant2 = Tenant::factory()->create([
            'organization_id' => $org2->id,
            'status' => 'active',
        ]);

        $site3 = Site::factory()->create([
            'tenant_id' => $tenant2->id,
            'vps_server_id' => $this->vps->id,
            'domain' => 'site3.example.com',
        ]);

        Sanctum::actingAs($this->ownerUser);

        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(200);

        $sites = $response->json('data.sites');
        $domains = collect($sites)->pluck('domain')->toArray();

        // Owner should see ALL sites across all organizations
        $this->assertContains('site1.example.com', $domains);
        $this->assertContains('site2.example.com', $domains);
        $this->assertContains('site3.example.com', $domains);

        // Verify the second org's site has correct mappings
        $site3Data = collect($sites)->firstWhere('domain', 'site3.example.com');
        $this->assertEquals($tenant2->id, $site3Data['tenant_id']);
        $this->assertEquals($org2->id, $site3Data['organization_id']);
    }

    /** @test */
    public function tenant_mappings_response_format_matches_specification()
    {
        Sanctum::actingAs($this->ownerUser);

        $response = $this->getJson('/api/v1/sites/tenant-mappings');

        $response->assertStatus(200);

        $data = $response->json('data');

        // Verify response has 'sites' key
        $this->assertArrayHasKey('sites', $data);

        // Verify each site has required fields
        foreach ($data['sites'] as $site) {
            $this->assertArrayHasKey('domain', $site);
            $this->assertArrayHasKey('tenant_id', $site);
            $this->assertArrayHasKey('organization_id', $site);
            $this->assertArrayHasKey('vps_id', $site);

            // Verify data types
            $this->assertIsString($site['domain']);
            $this->assertIsString($site['tenant_id']);
            $this->assertIsString($site['organization_id']);
            $this->assertIsString($site['vps_id']);
        }
    }
}
