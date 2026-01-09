<?php

namespace Tests\Unit\Repositories;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Repositories\BackupRepository;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Pagination\LengthAwarePaginator;
use Tests\TestCase;

class BackupRepositoryTest extends TestCase
{
    use RefreshDatabase;

    private BackupRepository $repository;
    private Site $site;
    private Tenant $tenant;

    protected function setUp(): void
    {
        parent::setUp();

        $this->repository = new BackupRepository(new SiteBackup());

        $this->tenant = Tenant::factory()->create([
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $vpsServer = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => $vpsServer->id,
        ]);
    }

    public function test_it_finds_backup_by_id_when_exists()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);

        $found = $this->repository->findById($backup->id);

        $this->assertNotNull($found);
        $this->assertEquals($backup->id, $found->id);
        $this->assertEquals('full', $found->backup_type);
        $this->assertTrue($found->relationLoaded('site'));
    }

    public function test_it_returns_null_when_backup_not_found()
    {
        $found = $this->repository->findById('non-existent-id');

        $this->assertNull($found);
    }

    public function test_it_finds_backups_by_site_with_pagination()
    {
        SiteBackup::factory()->count(5)->create([
            'site_id' => $this->site->id,
        ]);

        $otherSite = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => VpsServer::factory()->create()->id,
        ]);

        SiteBackup::factory()->count(3)->create([
            'site_id' => $otherSite->id,
        ]);

        $result = $this->repository->findBySite($this->site->id, 10);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(5, $result->total());
    }

    public function test_it_finds_backups_by_tenant_with_pagination()
    {
        SiteBackup::factory()->count(7)->create([
            'site_id' => $this->site->id,
        ]);

        $otherTenant = Tenant::factory()->create();
        $otherSite = Site::factory()->create([
            'tenant_id' => $otherTenant->id,
            'vps_server_id' => VpsServer::factory()->create()->id,
        ]);

        SiteBackup::factory()->count(3)->create([
            'site_id' => $otherSite->id,
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, [], 10);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(7, $result->total());
    }

    public function test_it_filters_backups_by_status()
    {
        SiteBackup::factory()->count(3)->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        SiteBackup::factory()->count(2)->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, ['status' => 'completed']);

        $this->assertEquals(3, $result->total());
    }

    public function test_it_filters_backups_by_type()
    {
        SiteBackup::factory()->count(2)->create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);

        SiteBackup::factory()->count(3)->create([
            'site_id' => $this->site->id,
            'backup_type' => 'database',
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, ['type' => 'full']);

        $this->assertEquals(2, $result->total());
    }

    public function test_it_filters_backups_by_site_id()
    {
        SiteBackup::factory()->count(5)->create([
            'site_id' => $this->site->id,
        ]);

        $otherSite = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => VpsServer::factory()->create()->id,
        ]);

        SiteBackup::factory()->count(3)->create([
            'site_id' => $otherSite->id,
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, ['site_id' => $this->site->id]);

        $this->assertEquals(5, $result->total());
    }

    public function test_it_finds_latest_backup_by_site()
    {
        $oldest = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
            'created_at' => now()->subDays(3),
        ]);

        $latest = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
            'created_at' => now()->subDay(),
        ]);

        SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
            'created_at' => now(),
        ]);

        $found = $this->repository->findLatestBySite($this->site->id);

        $this->assertNotNull($found);
        $this->assertEquals($latest->id, $found->id);
    }

    public function test_it_returns_null_when_no_completed_backups_exist()
    {
        SiteBackup::factory()->count(3)->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
        ]);

        $found = $this->repository->findLatestBySite($this->site->id);

        $this->assertNull($found);
    }

    public function test_it_creates_backup_successfully()
    {
        $data = [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'storage_path' => 'backups/test.tar.gz',
            'size_bytes' => 1024000,
            'checksum' => 'abc123',
            'status' => 'pending',
        ];

        $backup = $this->repository->create($data);

        $this->assertNotNull($backup);
        $this->assertEquals('full', $backup->backup_type);
        $this->assertEquals('pending', $backup->status);
        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);
    }

    public function test_it_updates_backup_status_successfully()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
        ]);

        $updated = $this->repository->updateStatus($backup->id, 'completed', [
            'size_bytes' => 2048000,
            'checksum' => 'xyz789',
        ]);

        $this->assertEquals('completed', $updated->status);
        $this->assertEquals(2048000, $updated->size_bytes);
        $this->assertEquals('xyz789', $updated->checksum);
        $this->assertNotNull($updated->completed_at);
    }

    public function test_it_sets_failed_timestamp_when_status_is_failed()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
        ]);

        $updated = $this->repository->updateStatus($backup->id, 'failed', [
            'error_message' => 'Backup failed due to timeout',
        ]);

        $this->assertEquals('failed', $updated->status);
        $this->assertNotNull($updated->failed_at);
        $this->assertEquals('Backup failed due to timeout', $updated->error_message);
    }

    public function test_it_throws_exception_when_updating_nonexistent_backup_status()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->updateStatus('non-existent-id', 'completed');
    }

    public function test_it_updates_backup_successfully()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'retention_days' => 30,
        ]);

        $updated = $this->repository->update($backup->id, [
            'retention_days' => 60,
        ]);

        $this->assertEquals(60, $updated->retention_days);
        $this->assertDatabaseHas('site_backups', [
            'id' => $backup->id,
            'retention_days' => 60,
        ]);
    }

    public function test_it_throws_exception_when_updating_nonexistent_backup()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->update('non-existent-id', ['retention_days' => 60]);
    }

    public function test_it_deletes_backup_successfully()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
        ]);

        $deleted = $this->repository->delete($backup->id);

        $this->assertTrue($deleted);
        $this->assertDatabaseMissing('site_backups', ['id' => $backup->id]);
    }

    public function test_it_throws_exception_when_deleting_nonexistent_backup()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->delete('non-existent-id');
    }

    public function test_it_counts_backups_by_site()
    {
        SiteBackup::factory()->count(9)->create([
            'site_id' => $this->site->id,
        ]);

        $otherSite = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => VpsServer::factory()->create()->id,
        ]);

        SiteBackup::factory()->count(4)->create([
            'site_id' => $otherSite->id,
        ]);

        $count = $this->repository->countBySite($this->site->id);

        $this->assertEquals(9, $count);
    }

    public function test_it_finds_completed_backups_by_site()
    {
        SiteBackup::factory()->count(5)->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        SiteBackup::factory()->count(3)->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
        ]);

        $backups = $this->repository->findCompletedBySite($this->site->id);

        $this->assertCount(5, $backups);
        foreach ($backups as $backup) {
            $this->assertEquals('completed', $backup->status);
        }
    }

    public function test_it_gets_all_backups_with_pagination()
    {
        SiteBackup::factory()->count(30)->create([
            'site_id' => $this->site->id,
        ]);

        $result = $this->repository->findAll(15);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(30, $result->total());
        $this->assertEquals(15, $result->perPage());
    }

    public function test_it_filters_backups_by_date_range()
    {
        SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDays(10),
        ]);

        SiteBackup::factory()->count(3)->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDays(5),
        ]);

        SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDay(),
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, [
            'date_from' => now()->subDays(6)->toDateString(),
            'date_to' => now()->toDateString(),
        ]);

        $this->assertEquals(4, $result->total());
    }

    // ============================================================================
    // Multi-Tenancy Security Tests (Phase 1)
    // ============================================================================

    public function test_find_by_id_and_tenant_returns_backup_for_same_tenant()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        $result = $this->repository->findByIdAndTenant($backup->id, $this->tenant->id);

        $this->assertNotNull($result);
        $this->assertEquals($backup->id, $result->id);
        $this->assertEquals($backup->backup_type, $result->backup_type);
    }

    public function test_find_by_id_and_tenant_returns_null_for_cross_tenant_access()
    {
        // Create another tenant with site and backup
        $otherTenant = Tenant::factory()->create([
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $otherSite = Site::factory()->create([
            'tenant_id' => $otherTenant->id,
            'vps_server_id' => VpsServer::factory()->create(['status' => 'active'])->id,
        ]);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $otherSite->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        // Attempt to access other tenant's backup
        $result = $this->repository->findByIdAndTenant($otherBackup->id, $this->tenant->id);

        $this->assertNull($result, 'Should return null when attempting cross-tenant access');
    }

    public function test_find_by_id_and_tenant_returns_null_for_nonexistent_backup()
    {
        $result = $this->repository->findByIdAndTenant('non-existent-id', $this->tenant->id);

        $this->assertNull($result);
    }

    public function test_find_by_id_and_tenant_properly_loads_site_relationship()
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        $result = $this->repository->findByIdAndTenant($backup->id, $this->tenant->id);

        $this->assertNotNull($result);
        $this->assertTrue($result->relationLoaded('site'));
        $this->assertNotNull($result->site);
        $this->assertEquals($this->site->id, $result->site->id);
        $this->assertEquals($this->tenant->id, $result->site->tenant_id);
    }

    public function test_find_by_id_and_tenant_prevents_information_leakage()
    {
        // Create backup for another tenant
        $otherTenant = Tenant::factory()->create(['status' => 'active']);
        $otherSite = Site::factory()->create([
            'tenant_id' => $otherTenant->id,
            'vps_server_id' => VpsServer::factory()->create(['status' => 'active'])->id,
        ]);
        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $otherSite->id,
        ]);

        // Attempt to access with wrong tenant ID
        $result = $this->repository->findByIdAndTenant($otherBackup->id, $this->tenant->id);

        // Should return null - same behavior as if backup doesn't exist
        // This prevents information leakage about backup existence
        $this->assertNull($result);

        // Verify the backup actually exists in DB
        $this->assertDatabaseHas('site_backups', ['id' => $otherBackup->id]);
    }

    public function test_find_by_id_and_tenant_enforces_tenant_filter_at_database_level()
    {
        // Create backups for multiple tenants
        $backup1 = SiteBackup::factory()->create(['site_id' => $this->site->id]);

        $tenant2 = Tenant::factory()->create(['status' => 'active']);
        $site2 = Site::factory()->create([
            'tenant_id' => $tenant2->id,
            'vps_server_id' => VpsServer::factory()->create(['status' => 'active'])->id,
        ]);
        $backup2 = SiteBackup::factory()->create(['site_id' => $site2->id]);

        $tenant3 = Tenant::factory()->create(['status' => 'active']);
        $site3 = Site::factory()->create([
            'tenant_id' => $tenant3->id,
            'vps_server_id' => VpsServer::factory()->create(['status' => 'active'])->id,
        ]);
        $backup3 = SiteBackup::factory()->create(['site_id' => $site3->id]);

        // Verify each tenant can only access their own backups
        $this->assertNotNull($this->repository->findByIdAndTenant($backup1->id, $this->tenant->id));
        $this->assertNull($this->repository->findByIdAndTenant($backup2->id, $this->tenant->id));
        $this->assertNull($this->repository->findByIdAndTenant($backup3->id, $this->tenant->id));

        $this->assertNull($this->repository->findByIdAndTenant($backup1->id, $tenant2->id));
        $this->assertNotNull($this->repository->findByIdAndTenant($backup2->id, $tenant2->id));
        $this->assertNull($this->repository->findByIdAndTenant($backup3->id, $tenant2->id));

        $this->assertNull($this->repository->findByIdAndTenant($backup1->id, $tenant3->id));
        $this->assertNull($this->repository->findByIdAndTenant($backup2->id, $tenant3->id));
        $this->assertNotNull($this->repository->findByIdAndTenant($backup3->id, $tenant3->id));
    }
}
