<?php

namespace Tests\Feature;

use App\Models\Organization;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Backup Tenant Isolation Test
 *
 * Verifies that multi-tenancy isolation is properly enforced for backups.
 * Tests the P0 CRITICAL fix for BackupRepository tenant filtering.
 *
 * Security Requirements:
 * - Organization A users CANNOT access Organization B backups
 * - Backup queries must be filtered at the database level
 * - No information leakage about backup existence across tenants
 */
class BackupTenantIsolationTest extends TestCase
{
    use RefreshDatabase;

    private Organization $orgA;
    private Organization $orgB;
    private Tenant $tenantA;
    private Tenant $tenantB;
    private User $userA;
    private User $userB;
    private Site $siteA;
    private Site $siteB;
    private SiteBackup $backupA;
    private SiteBackup $backupB;

    protected function setUp(): void
    {
        parent::setUp();

        // Create Organization A with tenant, user, site, and backup
        $this->orgA = Organization::factory()->create(['name' => 'Organization A']);
        $this->tenantA = Tenant::factory()->create([
            'organization_id' => $this->orgA->id,
            'status' => 'active',
        ]);
        $this->userA = User::factory()->create([
            'organization_id' => $this->orgA->id,
        ]);
        $this->userA->tenants()->attach($this->tenantA);

        $vpsA = VpsServer::factory()->create(['status' => 'active']);
        $this->siteA = Site::factory()->create([
            'tenant_id' => $this->tenantA->id,
            'vps_id' => $vpsA->id,
            'domain' => 'site-a.example.com',
        ]);
        $this->backupA = SiteBackup::factory()->create([
            'site_id' => $this->siteA->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        // Create Organization B with tenant, user, site, and backup
        $this->orgB = Organization::factory()->create(['name' => 'Organization B']);
        $this->tenantB = Tenant::factory()->create([
            'organization_id' => $this->orgB->id,
            'status' => 'active',
        ]);
        $this->userB = User::factory()->create([
            'organization_id' => $this->orgB->id,
        ]);
        $this->userB->tenants()->attach($this->tenantB);

        $vpsB = VpsServer::factory()->create(['status' => 'active']);
        $this->siteB = Site::factory()->create([
            'tenant_id' => $this->tenantB->id,
            'vps_id' => $vpsB->id,
            'domain' => 'site-b.example.com',
        ]);
        $this->backupB = SiteBackup::factory()->create([
            'site_id' => $this->siteB->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);
    }

    /** @test */
    public function org_a_user_cannot_access_org_b_backup_via_show_endpoint()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson("/api/v1/backups/{$this->backupB->id}");

        $response->assertStatus(404);
        $response->assertJson([
            'success' => false,
        ]);
    }

    /** @test */
    public function org_a_user_can_access_own_backup_via_show_endpoint()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson("/api/v1/backups/{$this->backupA->id}");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'id' => $this->backupA->id,
            ],
        ]);
    }

    /** @test */
    public function org_a_user_cannot_download_org_b_backup()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson("/api/v1/backups/{$this->backupB->id}/download");

        $response->assertStatus(404);
    }

    /** @test */
    public function org_a_user_cannot_restore_org_b_backup()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/backups/{$this->backupB->id}/restore");

        $response->assertStatus(404);
    }

    /** @test */
    public function org_a_user_cannot_delete_org_b_backup()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->deleteJson("/api/v1/backups/{$this->backupB->id}");

        $response->assertStatus(404);

        // Verify backup B still exists
        $this->assertDatabaseHas('site_backups', [
            'id' => $this->backupB->id,
        ]);
    }

    /** @test */
    public function backup_list_endpoint_only_shows_own_tenant_backups()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson('/api/v1/backups');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                '*' => ['id', 'site_id', 'backup_type'],
            ],
        ]);

        // Extract all backup IDs from response
        $backupIds = collect($response->json('data'))->pluck('id')->toArray();

        // Verify Org A backup is in the list
        $this->assertContains($this->backupA->id, $backupIds);

        // Verify Org B backup is NOT in the list
        $this->assertNotContains($this->backupB->id, $backupIds);
    }

    /** @test */
    public function repository_find_by_id_and_tenant_enforces_isolation()
    {
        $backupRepo = app(\App\Repositories\BackupRepository::class);

        // Attempt to find Org B backup with Org A tenant ID
        $result = $backupRepo->findByIdAndTenant($this->backupB->id, $this->tenantA->id);

        $this->assertNull($result, 'BackupRepository should return null for cross-tenant access');

        // Verify can find own backup
        $result = $backupRepo->findByIdAndTenant($this->backupA->id, $this->tenantA->id);

        $this->assertNotNull($result, 'BackupRepository should find own tenant backup');
        $this->assertEquals($this->backupA->id, $result->id);
    }

    /** @test */
    public function form_request_validation_blocks_cross_tenant_site_access()
    {
        Sanctum::actingAs($this->userA);

        // Attempt to create backup for Org B's site
        $response = $this->postJson('/api/v1/backups', [
            'site_id' => $this->siteB->id,
            'backup_type' => 'full',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors('site_id');
    }
}
