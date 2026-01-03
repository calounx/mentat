<?php

namespace Tests\Unit\Services;

use App\Events\BackupCreated;
use App\Events\BackupDeleted;
use App\Events\BackupRestored;
use App\Jobs\CreateBackupJob;
use App\Jobs\RestoreBackupJob;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Repositories\BackupRepository;
use App\Repositories\SiteRepository;
use App\Services\BackupService;
use App\Services\QuotaService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Mockery;
use Tests\TestCase;

class BackupServiceTest extends TestCase
{
    use RefreshDatabase;

    private BackupService $service;
    private $backupRepo;
    private $siteRepo;
    private $quotaService;

    protected function setUp(): void
    {
        parent::setUp();

        $this->backupRepo = Mockery::mock(BackupRepository::class);
        $this->siteRepo = Mockery::mock(SiteRepository::class);
        $this->quotaService = Mockery::mock(QuotaService::class);

        $this->service = new BackupService(
            $this->backupRepo,
            $this->siteRepo,
            $this->quotaService
        );

        Event::fake();
        Queue::fake();
        Storage::fake('backups');
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_it_creates_backup_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'domain' => 'test.com',
            'tenant_id' => 'tenant-123',
            'storage_used_mb' => 200,
        ]);

        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'site_id' => 'site-123',
            'backup_type' => 'full',
            'status' => 'pending',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->with('site-123')
            ->andReturn($site);

        $this->quotaService->shouldReceive('canCreateBackup')
            ->once()
            ->with('site-123')
            ->andReturn(true);

        $this->quotaService->shouldReceive('checkStorageQuota')
            ->once()
            ->with('tenant-123')
            ->andReturn(['available' => true]);

        $this->backupRepo->shouldReceive('create')
            ->once()
            ->andReturn($backup);

        $result = $this->service->createBackup('site-123', 'full', 30);

        $this->assertNotNull($result);
        $this->assertEquals('backup-123', $result->id);
        Queue::assertPushed(CreateBackupJob::class);
        Event::assertDispatched(BackupCreated::class);
    }

    public function test_it_throws_exception_when_site_not_found()
    {
        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn(null);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Site not found');

        $this->service->createBackup('site-123');
    }

    public function test_it_throws_exception_when_backup_quota_exceeded()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->quotaService->shouldReceive('canCreateBackup')
            ->once()
            ->andReturn(false);

        $this->quotaService->shouldReceive('checkBackupQuota')
            ->once()
            ->andReturn(['current' => 5, 'limit' => 5]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Backup quota exceeded');

        $this->service->createBackup('site-123');
    }

    public function test_it_throws_exception_when_storage_quota_exceeded()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'tenant_id' => 'tenant-123',
            'storage_used_mb' => 500,
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->quotaService->shouldReceive('canCreateBackup')
            ->once()
            ->andReturn(true);

        $this->quotaService->shouldReceive('checkStorageQuota')
            ->once()
            ->andReturn(['available' => false]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Storage quota exceeded');

        $this->service->createBackup('site-123');
    }

    public function test_it_throws_exception_for_invalid_backup_type()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'tenant_id' => 'tenant-123',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->quotaService->shouldReceive('canCreateBackup')
            ->once()
            ->andReturn(true);

        $this->quotaService->shouldReceive('checkStorageQuota')
            ->once()
            ->andReturn(['available' => true]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Invalid backup type');

        $this->service->createBackup('site-123', 'invalid_type');
    }

    public function test_it_restores_backup_to_original_site_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'active',
        ]);

        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'site_id' => 'site-123',
            'status' => 'completed',
            'backup_type' => 'full',
        ]);

        $backup->shouldReceive('getAttribute')
            ->with('site')
            ->andReturn($site);

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->with('backup-123')
            ->andReturn($backup);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->with('site-123', ['status' => 'restoring'])
            ->andReturn($site);

        $result = $this->service->restoreBackup('backup-123');

        $this->assertTrue($result);
        Queue::assertPushed(RestoreBackupJob::class);
        Event::assertDispatched(BackupRestored::class);
    }

    public function test_it_restores_backup_to_different_site_successfully()
    {
        $sourceSite = Site::factory()->make([
            'id' => 'site-123',
        ]);

        $targetSite = Site::factory()->make([
            'id' => 'site-456',
            'status' => 'active',
        ]);

        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'site_id' => 'site-123',
            'status' => 'completed',
        ]);

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->with('site-456')
            ->andReturn($targetSite);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->with('site-456', ['status' => 'restoring'])
            ->andReturn($targetSite);

        $result = $this->service->restoreBackup('backup-123', 'site-456');

        $this->assertTrue($result);
        Queue::assertPushed(RestoreBackupJob::class);
    }

    public function test_it_throws_exception_when_restoring_nonexistent_backup()
    {
        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn(null);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Backup not found');

        $this->service->restoreBackup('backup-123');
    }

    public function test_it_throws_exception_when_restoring_incomplete_backup()
    {
        $backup = SiteBackup::factory()->make([
            'status' => 'pending',
        ]);

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot restore backup with status: pending');

        $this->service->restoreBackup('backup-123');
    }

    public function test_it_throws_exception_when_target_site_is_deleting()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'deleting',
        ]);

        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'site_id' => 'site-123',
            'status' => 'completed',
        ]);

        $backup->shouldReceive('getAttribute')
            ->with('site')
            ->andReturn($site);

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot restore to a site being deleted');

        $this->service->restoreBackup('backup-123');
    }

    public function test_it_deletes_backup_successfully()
    {
        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'site_id' => 'site-123',
            'storage_path' => 'backups/test.tar.gz',
        ]);

        Storage::disk('backups')->put('backups/test.tar.gz', 'test content');

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $this->backupRepo->shouldReceive('delete')
            ->once()
            ->with('backup-123')
            ->andReturn(true);

        $result = $this->service->deleteBackup('backup-123');

        $this->assertTrue($result);
        Storage::disk('backups')->assertMissing('backups/test.tar.gz');
        Event::assertDispatched(BackupDeleted::class);
    }

    public function test_it_deletes_backup_even_when_file_not_found()
    {
        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'storage_path' => 'backups/nonexistent.tar.gz',
        ]);

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $this->backupRepo->shouldReceive('delete')
            ->once()
            ->andReturn(true);

        $result = $this->service->deleteBackup('backup-123');

        $this->assertTrue($result);
    }

    public function test_it_cleans_up_expired_backups()
    {
        $expiredBackup1 = SiteBackup::factory()->make([
            'id' => 'backup-1',
            'expires_at' => now()->subDay(),
            'storage_path' => 'backups/expired1.tar.gz',
        ]);

        $expiredBackup1->shouldReceive('isExpired')->andReturn(true);

        $expiredBackup2 = SiteBackup::factory()->make([
            'id' => 'backup-2',
            'expires_at' => now()->subDays(5),
            'storage_path' => 'backups/expired2.tar.gz',
        ]);

        $expiredBackup2->shouldReceive('isExpired')->andReturn(true);

        $validBackup = SiteBackup::factory()->make([
            'id' => 'backup-3',
            'expires_at' => now()->addDays(10),
        ]);

        $validBackup->shouldReceive('isExpired')->andReturn(false);

        $backups = new Collection([$expiredBackup1, $expiredBackup2, $validBackup]);

        $this->backupRepo->shouldReceive('findBySiteId')
            ->once()
            ->with('site-123')
            ->andReturn($backups);

        $this->backupRepo->shouldReceive('findById')
            ->twice()
            ->andReturnValues([$expiredBackup1, $expiredBackup2]);

        $this->backupRepo->shouldReceive('delete')
            ->twice()
            ->andReturn(true);

        $deletedCount = $this->service->cleanupExpiredBackups('site-123');

        $this->assertEquals(2, $deletedCount);
    }

    public function test_it_validates_backup_integrity_successfully()
    {
        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'storage_path' => 'backups/test.tar.gz',
            'size_bytes' => 1024,
            'checksum' => md5('test content'),
            'expires_at' => now()->addDays(10),
        ]);

        $backup->shouldReceive('isExpired')->andReturn(false);

        Storage::disk('backups')->put('backups/test.tar.gz', 'test content');

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $result = $this->service->validateBackupIntegrity('backup-123');

        $this->assertIsArray($result);
        $this->assertTrue($result['valid']);
        $this->assertTrue($result['checks']['file_exists']);
        $this->assertTrue($result['checks']['not_expired']);
    }

    public function test_it_detects_corrupted_backup()
    {
        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'storage_path' => 'backups/corrupted.tar.gz',
            'size_bytes' => 999999,
            'checksum' => 'wrong_checksum',
            'expires_at' => now()->addDays(10),
        ]);

        $backup->shouldReceive('isExpired')->andReturn(false);

        Storage::disk('backups')->put('backups/corrupted.tar.gz', 'test');

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $result = $this->service->validateBackupIntegrity('backup-123');

        $this->assertFalse($result['valid']);
        $this->assertFalse($result['checks']['size_match']);
    }

    public function test_it_detects_missing_backup_file()
    {
        $backup = SiteBackup::factory()->make([
            'id' => 'backup-123',
            'storage_path' => 'backups/missing.tar.gz',
            'expires_at' => now()->addDays(10),
        ]);

        $backup->shouldReceive('isExpired')->andReturn(false);

        $this->backupRepo->shouldReceive('findById')
            ->once()
            ->andReturn($backup);

        $result = $this->service->validateBackupIntegrity('backup-123');

        $this->assertFalse($result['valid']);
        $this->assertFalse($result['checks']['file_exists']);
    }
}
