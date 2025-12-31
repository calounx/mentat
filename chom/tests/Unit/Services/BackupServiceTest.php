<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Models\Backup;
use App\Models\Site;
use App\Services\Backup\BackupService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\WithMockVpsManager;
use Tests\TestCase;

/**
 * Unit tests for Backup Service
 *
 * @package Tests\Unit\Services
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
     *
     * @return void
     */
    public function test_creates_backup_successfully(): void
    {
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -czf', 'Backup created', 0);

        $backup = $this->service->createBackup($this->site, 'full');

        $this->assertInstanceOf(Backup::class, $backup);
        $this->assertEquals('full', $backup->type);
        $this->assertEquals($this->site->id, $backup->site_id);
    }

    /**
     * Test backup with encryption
     *
     * @return void
     */
    public function test_creates_encrypted_backup(): void
    {
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -czf', 'Backup created', 0);
        $this->mockCommandExecution('openssl enc', 'Encrypted', 0);

        $backup = $this->service->createBackup($this->site, 'full', true);

        $this->assertTrue($backup->encrypted);
        $this->assertNotNull($backup->encryption_key_id);
    }

    /**
     * Test backup verification
     *
     * @return void
     */
    public function test_verifies_backup_integrity(): void
    {
        $backup = Backup::factory()->create([
            'site_id' => $this->site->id,
            'checksum' => 'abc123',
        ]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('sha256sum', 'abc123', 0);

        $verified = $this->service->verifyBackup($backup);

        $this->assertTrue($verified);
    }

    /**
     * Test backup cleanup removes old backups
     *
     * @return void
     */
    public function test_cleanup_removes_old_backups(): void
    {
        $oldBackup = Backup::factory()->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDays(31),
        ]);

        $recentBackup = Backup::factory()->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDays(15),
        ]);

        $this->service->cleanup(30);

        $this->assertDatabaseMissing('backups', ['id' => $oldBackup->id]);
        $this->assertDatabaseHas('backups', ['id' => $recentBackup->id]);
    }
}
