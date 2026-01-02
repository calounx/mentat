<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Services\Backup\BackupService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\WithMockVpsManager;
use Tests\TestCase;

/**
 * Unit tests for Backup Service
 */
class BackupServiceTest extends TestCase
{
    use RefreshDatabase;
    use WithMockVpsManager;

    protected BackupService $service;

    protected Site $site;

    protected function setUp(): void
    {
        parent::setUp();

        $this->site = Site::factory()->create();
        $this->setUpVpsMocks();

        Storage::fake('backups');

        $this->service = $this->app->make(BackupService::class);
    }

    /**
     * Test backup creation
     */
    public function test_creates_backup_successfully(): void
    {
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -czf', 'Backup created', 0);

        $backup = $this->service->createBackup($this->site, 'full');

        $this->assertInstanceOf(SiteBackup::class, $backup);
        $this->assertEquals('full', $backup->backup_type);
        $this->assertEquals($this->site->id, $backup->site_id);
    }

    /**
     * Test backup with custom retention
     */
    public function test_creates_backup_with_custom_retention(): void
    {
        $backup = $this->service->createBackup($this->site, 'full', 60);

        $this->assertEquals(60, $backup->retention_days);
        $this->assertNotNull($backup->expires_at);
        $this->assertEquals(now()->addDays(60)->format('Y-m-d'), $backup->expires_at->format('Y-m-d'));
    }

    /**
     * Test backup execution
     */
    public function test_executes_backup_successfully(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'storage_path' => null,
        ]);

        // Mock VPS manager's createBackup method
        $this->vpsManager
            ->shouldReceive('createBackup')
            ->once()
            ->andReturn([
                'success' => true,
                'path' => '/backups/test.tar.gz',
                'size' => 1024000,
                'checksum' => 'abc123',
            ]);

        $result = $this->service->executeBackup($backup);

        $this->assertTrue($result['success']);
        $this->assertEquals('/backups/test.tar.gz', $result['path']);
        $backup->refresh();
        $this->assertNotNull($backup->storage_path);
    }

    /**
     * Test backup cleanup removes expired backups
     */
    public function test_cleanup_removes_expired_backups(): void
    {
        $expiredBackup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'expires_at' => now()->subDays(1),
            'storage_path' => '/tmp/old-backup.tar.gz',
        ]);

        $activeBackup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'expires_at' => now()->addDays(15),
            'storage_path' => '/tmp/recent-backup.tar.gz',
        ]);

        $count = $this->service->cleanupExpiredBackups($this->site);

        $this->assertEquals(1, $count);
        $this->assertDatabaseMissing('site_backups', ['id' => $expiredBackup->id]);
        $this->assertDatabaseHas('site_backups', ['id' => $activeBackup->id]);
    }
}
