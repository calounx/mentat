<?php

namespace Tests\Unit\Controllers;

use App\Http\Controllers\Api\V1\BackupController;
use App\Http\Requests\StoreBackupRequest;
use App\Models\Organization;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use App\Repositories\BackupRepository;
use App\Services\BackupService;
use App\Services\QuotaService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Mockery;
use Tests\TestCase;

/**
 * BackupController Unit Tests
 *
 * Tests controller methods with focus on multi-tenancy security.
 * Verifies that findByIdAndTenant() is used correctly to prevent
 * cross-tenant access in show, download, restore, and destroy methods.
 */
class BackupControllerTest extends TestCase
{
    use RefreshDatabase;

    private BackupController $controller;
    private BackupRepository $backupRepository;
    private BackupService $backupService;
    private QuotaService $quotaService;
    private User $user;
    private Tenant $tenant;
    private Site $site;
    private Tenant $otherTenant;
    private Site $otherSite;

    protected function setUp(): void
    {
        parent::setUp();

        // Create tenants and sites
        $org = Organization::factory()->create();
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $org->id,
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $this->user = User::factory()->create([
            'organization_id' => $org->id,
        ]);
        $this->user->tenants()->attach($this->tenant);

        $vps = VpsServer::factory()->create(['status' => 'active']);
        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $vps->id,
        ]);

        // Other tenant
        $otherOrg = Organization::factory()->create();
        $this->otherTenant = Tenant::factory()->create([
            'organization_id' => $otherOrg->id,
            'status' => 'active',
        ]);

        $otherVps = VpsServer::factory()->create(['status' => 'active']);
        $this->otherSite = Site::factory()->create([
            'tenant_id' => $this->otherTenant->id,
            'vps_id' => $otherVps->id,
        ]);

        // Initialize repositories and services
        $this->backupRepository = new BackupRepository(new SiteBackup());
        $this->backupService = Mockery::mock(BackupService::class);
        $this->quotaService = Mockery::mock(QuotaService::class);

        $this->controller = new BackupController(
            $this->backupRepository,
            $this->backupService,
            $this->quotaService
        );
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    // ============================================================================
    // show() Method Tests
    // ============================================================================

    public function test_show_returns_backup_for_same_tenant()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        $request = Request::create("/api/v1/backups/{$backup->id}", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->show($request, $backup->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertEquals($backup->id, $data['data']['id']);
    }

    public function test_show_returns_404_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $this->otherSite->id,
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        $request = Request::create("/api/v1/backups/{$otherBackup->id}", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->show($request, $otherBackup->id);
    }

    public function test_show_returns_404_for_nonexistent_backup()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create("/api/v1/backups/non-existent-id", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->show($request, 'non-existent-id');
    }

    public function test_show_uses_find_by_id_and_tenant_method()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        $mockRepository = Mockery::mock(BackupRepository::class);
        $mockRepository->shouldReceive('findByIdAndTenant')
            ->once()
            ->with($backup->id, $this->tenant->id)
            ->andReturn($backup);

        $controller = new BackupController(
            $mockRepository,
            $this->backupService,
            $this->quotaService
        );

        $request = Request::create("/api/v1/backups/{$backup->id}", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $controller->show($request, $backup->id);

        $this->assertEquals(200, $response->getStatusCode());
    }

    // ============================================================================
    // download() Method Tests
    // ============================================================================

    public function test_download_returns_404_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $this->otherSite->id,
            'status' => 'completed',
            'file_path' => 'backups/test.tar.gz',
        ]);

        $request = Request::create("/api/v1/backups/{$otherBackup->id}/download", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->download($request, $otherBackup->id);
    }

    public function test_download_returns_400_if_backup_not_completed()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
            'file_path' => null,
        ]);

        $request = Request::create("/api/v1/backups/{$backup->id}/download", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->download($request, $backup->id);

        $this->assertEquals(400, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertFalse($data['success']);
        $this->assertEquals('BACKUP_NOT_READY', $data['error']['code']);
    }

    public function test_download_returns_404_if_file_does_not_exist()
    {
        Sanctum::actingAs($this->user);
        Storage::fake('local');

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
            'file_path' => 'backups/nonexistent.tar.gz',
        ]);

        $request = Request::create("/api/v1/backups/{$backup->id}/download", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->download($request, $backup->id);

        $this->assertEquals(404, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertFalse($data['success']);
        $this->assertEquals('FILE_NOT_FOUND', $data['error']['code']);
    }

    public function test_download_uses_find_by_id_and_tenant_method()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
            'file_path' => 'backups/test.tar.gz',
        ]);

        $mockRepository = Mockery::mock(BackupRepository::class);
        $mockRepository->shouldReceive('findByIdAndTenant')
            ->once()
            ->with($backup->id, $this->tenant->id)
            ->andReturn($backup);

        $controller = new BackupController(
            $mockRepository,
            $this->backupService,
            $this->quotaService
        );

        $request = Request::create("/api/v1/backups/{$backup->id}/download", 'GET');
        $request->setUserResolver(fn() => $this->user);

        // Will fail at file check, but verifies the method was called
        $response = $controller->download($request, $backup->id);

        // Expect 404 because file doesn't exist, but repository method was called correctly
        $this->assertEquals(404, $response->getStatusCode());
    }

    // ============================================================================
    // restore() Method Tests
    // ============================================================================

    public function test_restore_returns_404_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $this->otherSite->id,
            'status' => 'completed',
        ]);

        $request = Request::create("/api/v1/backups/{$otherBackup->id}/restore", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->restore($request, $otherBackup->id);
    }

    public function test_restore_calls_backup_service_for_same_tenant()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        $this->backupService->shouldReceive('restoreBackup')
            ->once()
            ->with($backup->id)
            ->andReturn(true);

        $request = Request::create("/api/v1/backups/{$backup->id}/restore", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->restore($request, $backup->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertEquals('restoring', $data['data']['status']);
    }

    public function test_restore_uses_find_by_id_and_tenant_method()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        $mockRepository = Mockery::mock(BackupRepository::class);
        $mockRepository->shouldReceive('findByIdAndTenant')
            ->once()
            ->with($backup->id, $this->tenant->id)
            ->andReturn($backup);

        $this->backupService->shouldReceive('restoreBackup')
            ->once()
            ->with($backup->id)
            ->andReturn(true);

        $controller = new BackupController(
            $mockRepository,
            $this->backupService,
            $this->quotaService
        );

        $request = Request::create("/api/v1/backups/{$backup->id}/restore", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $controller->restore($request, $backup->id);

        $this->assertEquals(200, $response->getStatusCode());
    }

    // ============================================================================
    // destroy() Method Tests
    // ============================================================================

    public function test_destroy_returns_404_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $this->otherSite->id,
            'status' => 'completed',
        ]);

        $request = Request::create("/api/v1/backups/{$otherBackup->id}", 'DELETE');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->destroy($request, $otherBackup->id);
    }

    public function test_destroy_deletes_backup_for_same_tenant()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        $this->backupService->shouldReceive('deleteBackup')
            ->once()
            ->with($backup->id)
            ->andReturn(true);

        $request = Request::create("/api/v1/backups/{$backup->id}", 'DELETE');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->destroy($request, $backup->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertEquals($backup->id, $data['data']['id']);
    }

    public function test_destroy_uses_find_by_id_and_tenant_method()
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
        ]);

        $mockRepository = Mockery::mock(BackupRepository::class);
        $mockRepository->shouldReceive('findByIdAndTenant')
            ->once()
            ->with($backup->id, $this->tenant->id)
            ->andReturn($backup);

        $this->backupService->shouldReceive('deleteBackup')
            ->once()
            ->with($backup->id)
            ->andReturn(true);

        $controller = new BackupController(
            $mockRepository,
            $this->backupService,
            $this->quotaService
        );

        $request = Request::create("/api/v1/backups/{$backup->id}", 'DELETE');
        $request->setUserResolver(fn() => $this->user);

        $response = $controller->destroy($request, $backup->id);

        $this->assertEquals(200, $response->getStatusCode());
    }

    public function test_destroy_does_not_leak_information_about_other_tenant_backups()
    {
        Sanctum::actingAs($this->user);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $this->otherSite->id,
            'status' => 'completed',
        ]);

        $request = Request::create("/api/v1/backups/{$otherBackup->id}", 'DELETE');
        $request->setUserResolver(fn() => $this->user);

        try {
            $this->controller->destroy($request, $otherBackup->id);
            $this->fail('Expected NotFoundHttpException was not thrown');
        } catch (\Symfony\Component\HttpKernel\Exception\NotFoundHttpException $e) {
            // Verify backup still exists (was not deleted)
            $this->assertDatabaseHas('site_backups', [
                'id' => $otherBackup->id,
            ]);
        }
    }

    // ============================================================================
    // Multi-Method Security Tests
    // ============================================================================

    public function test_all_methods_enforce_tenant_isolation_consistently()
    {
        Sanctum::actingAs($this->user);

        $otherBackup = SiteBackup::factory()->create([
            'site_id' => $this->otherSite->id,
            'status' => 'completed',
            'file_path' => 'backups/test.tar.gz',
        ]);

        // Test show
        $request = Request::create("/api/v1/backups/{$otherBackup->id}", 'GET');
        $request->setUserResolver(fn() => $this->user);
        try {
            $this->controller->show($request, $otherBackup->id);
            $this->fail('show() should have thrown NotFoundHttpException');
        } catch (\Symfony\Component\HttpKernel\Exception\NotFoundHttpException $e) {
            $this->assertTrue(true);
        }

        // Test download
        $request = Request::create("/api/v1/backups/{$otherBackup->id}/download", 'GET');
        $request->setUserResolver(fn() => $this->user);
        try {
            $this->controller->download($request, $otherBackup->id);
            $this->fail('download() should have thrown NotFoundHttpException');
        } catch (\Symfony\Component\HttpKernel\Exception\NotFoundHttpException $e) {
            $this->assertTrue(true);
        }

        // Test restore
        $request = Request::create("/api/v1/backups/{$otherBackup->id}/restore", 'POST');
        $request->setUserResolver(fn() => $this->user);
        try {
            $this->controller->restore($request, $otherBackup->id);
            $this->fail('restore() should have thrown NotFoundHttpException');
        } catch (\Symfony\Component\HttpKernel\Exception\NotFoundHttpException $e) {
            $this->assertTrue(true);
        }

        // Test destroy
        $request = Request::create("/api/v1/backups/{$otherBackup->id}", 'DELETE');
        $request->setUserResolver(fn() => $this->user);
        try {
            $this->controller->destroy($request, $otherBackup->id);
            $this->fail('destroy() should have thrown NotFoundHttpException');
        } catch (\Symfony\Component\HttpKernel\Exception\NotFoundHttpException $e) {
            $this->assertTrue(true);
        }

        // Verify backup still exists (nothing was modified)
        $this->assertDatabaseHas('site_backups', [
            'id' => $otherBackup->id,
        ]);
    }
}
