<?php

namespace Tests\Unit\Repositories;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Repositories\SiteRepository;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Pagination\LengthAwarePaginator;
use Tests\TestCase;

class SiteRepositoryTest extends TestCase
{
    use RefreshDatabase;

    private SiteRepository $repository;
    private Tenant $tenant;
    private VpsServer $vpsServer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->repository = new SiteRepository(new Site());

        $this->tenant = Tenant::factory()->create([
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $this->vpsServer = VpsServer::factory()->create([
            'status' => 'active',
            'site_count' => 0,
        ]);
    }

    public function test_it_finds_site_by_id_when_exists()
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'domain' => 'example.com',
        ]);

        $found = $this->repository->findById($site->id);

        $this->assertNotNull($found);
        $this->assertEquals($site->id, $found->id);
        $this->assertEquals('example.com', $found->domain);
        $this->assertTrue($found->relationLoaded('vpsServer'));
        $this->assertTrue($found->relationLoaded('backups'));
    }

    public function test_it_returns_null_when_site_not_found()
    {
        $found = $this->repository->findById('non-existent-id');

        $this->assertNull($found);
    }

    public function test_it_finds_sites_by_tenant_with_pagination()
    {
        Site::factory()->count(5)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        Site::factory()->count(3)->create([
            'tenant_id' => Tenant::factory()->create()->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, [], 10);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(5, $result->total());
        $this->assertEquals(10, $result->perPage());
    }

    public function test_it_filters_sites_by_status()
    {
        Site::factory()->count(3)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'status' => 'active',
        ]);

        Site::factory()->count(2)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'status' => 'disabled',
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, ['status' => 'active']);

        $this->assertEquals(3, $result->total());
    }

    public function test_it_filters_sites_by_site_type()
    {
        Site::factory()->count(2)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'site_type' => 'wordpress',
        ]);

        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'site_type' => 'laravel',
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, ['site_type' => 'wordpress']);

        $this->assertEquals(2, $result->total());
    }

    public function test_it_filters_sites_by_search_term()
    {
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'domain' => 'example.com',
            'name' => 'Example Site',
        ]);

        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'domain' => 'test.com',
            'name' => 'Test Site',
        ]);

        $result = $this->repository->findByTenant($this->tenant->id, ['search' => 'example']);

        $this->assertEquals(1, $result->total());
        $this->assertEquals('example.com', $result->first()->domain);
    }

    public function test_it_finds_site_by_id_and_tenant()
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $found = $this->repository->findByIdAndTenant($site->id, $this->tenant->id);

        $this->assertNotNull($found);
        $this->assertEquals($site->id, $found->id);
    }

    public function test_it_throws_exception_when_site_not_found_for_tenant()
    {
        $this->expectException(ModelNotFoundException::class);

        $otherTenant = Tenant::factory()->create();
        $site = Site::factory()->create([
            'tenant_id' => $otherTenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $this->repository->findByIdAndTenant($site->id, $this->tenant->id);
    }

    public function test_it_creates_site_successfully()
    {
        $data = [
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'domain' => 'newsite.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
            'status' => 'creating',
            'ssl_enabled' => false,
        ];

        $site = $this->repository->create($data);

        $this->assertNotNull($site);
        $this->assertEquals('newsite.com', $site->domain);
        $this->assertEquals('wordpress', $site->site_type);
        $this->assertDatabaseHas('sites', [
            'domain' => 'newsite.com',
        ]);

        $this->vpsServer->refresh();
        $this->assertEquals(1, $this->vpsServer->site_count);
    }

    public function test_it_updates_site_successfully()
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'domain' => 'original.com',
            'status' => 'creating',
        ]);

        $updated = $this->repository->update($site->id, [
            'status' => 'active',
        ]);

        $this->assertEquals('active', $updated->status);
        $this->assertDatabaseHas('sites', [
            'id' => $site->id,
            'status' => 'active',
        ]);
    }

    public function test_it_throws_exception_when_updating_nonexistent_site()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->update('non-existent-id', ['status' => 'active']);
    }

    public function test_it_updates_vps_server_count_when_changing_servers()
    {
        $oldVps = VpsServer::factory()->create(['site_count' => 1]);
        $newVps = VpsServer::factory()->create(['site_count' => 0]);

        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $oldVps->id,
        ]);

        $this->repository->update($site->id, [
            'vps_id' => $newVps->id,
        ]);

        $oldVps->refresh();
        $newVps->refresh();

        $this->assertEquals(0, $oldVps->site_count);
        $this->assertEquals(1, $newVps->site_count);
    }

    public function test_it_deletes_site_and_associated_backups()
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $backups = \App\Models\SiteBackup::factory()->count(3)->create([
            'site_id' => $site->id,
        ]);

        $deleted = $this->repository->delete($site->id);

        $this->assertTrue($deleted);
        $this->assertDatabaseMissing('sites', ['id' => $site->id]);

        foreach ($backups as $backup) {
            $this->assertDatabaseMissing('site_backups', ['id' => $backup->id]);
        }
    }

    public function test_it_decrements_vps_server_count_when_deleting_site()
    {
        $vps = VpsServer::factory()->create(['site_count' => 3]);

        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $vps->id,
        ]);

        $this->repository->delete($site->id);

        $vps->refresh();
        $this->assertEquals(2, $vps->site_count);
    }

    public function test_it_throws_exception_when_deleting_nonexistent_site()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->delete('non-existent-id');
    }

    public function test_it_counts_sites_by_tenant()
    {
        Site::factory()->count(7)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        Site::factory()->count(3)->create([
            'tenant_id' => Tenant::factory()->create()->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $count = $this->repository->countByTenant($this->tenant->id);

        $this->assertEquals(7, $count);
    }

    public function test_it_finds_active_sites_by_tenant()
    {
        Site::factory()->count(3)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'status' => 'active',
        ]);

        Site::factory()->count(2)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'status' => 'disabled',
        ]);

        $sites = $this->repository->findActiveByTenant($this->tenant->id);

        $this->assertCount(3, $sites);
        foreach ($sites as $site) {
            $this->assertEquals('active', $site->status);
        }
    }

    public function test_it_updates_site_status()
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
            'status' => 'active',
        ]);

        $updated = $this->repository->updateStatus($site->id, 'disabled');

        $this->assertEquals('disabled', $updated->status);
        $this->assertNotNull($updated->status_updated_at);
    }

    public function test_it_throws_exception_when_updating_status_of_nonexistent_site()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->updateStatus('non-existent-id', 'active');
    }

    public function test_it_gets_all_sites_with_pagination()
    {
        Site::factory()->count(25)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $result = $this->repository->findAll(15);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(25, $result->total());
        $this->assertEquals(15, $result->perPage());
    }
}
