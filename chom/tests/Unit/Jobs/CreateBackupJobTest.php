<?php

namespace Tests\Unit\Jobs;

use App\Events\Backup\BackupCompleted;
use App\Events\Backup\BackupCreated;
use App\Events\Backup\BackupFailed;
use App\Jobs\CreateBackupJob;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class CreateBackupJobTest extends TestCase
{
    use RefreshDatabase;

    protected Site $site;
    protected VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $this->vps = VpsServer::factory()->create();
        $this->site = Site::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_server_id' => $this->vps->id,
            'domain' => 'test.example.com',
        ]);
    }

    #[Test]
    public function it_can_be_dispatched_to_queue()
    {
        Queue::fake();

        dispatch(new CreateBackupJob($this->site));

        Queue::assertPushed(CreateBackupJob::class, function ($job) {
            return $job->site->id === $this->site->id;
        });
    }

    #[Test]
    public function it_has_correct_retry_configuration()
    {
        $job = new CreateBackupJob($this->site);

        $this->assertEquals(3, $job->tries);
        $this->assertEquals(120, $job->backoff);
    }

    #[Test]
    public function it_can_be_serialized_and_unserialized()
    {
        $job = new CreateBackupJob($this->site, 'full', 30);

        $serialized = serialize($job);
        $unserialized = unserialize($serialized);

        $this->assertInstanceOf(CreateBackupJob::class, $unserialized);
        $this->assertEquals($this->site->id, $unserialized->site->id);
        $this->assertEquals('full', $unserialized->backupType);
        $this->assertEquals(30, $unserialized->retentionDays);
    }

    #[Test]
    public function it_creates_backup_successfully()
    {
        Event::fake([BackupCreated::class, BackupCompleted::class]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('createBackup')
            ->once()
            ->with($this->vps, 'test.example.com', ['files', 'database'])
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/test.example.com/2026-01-02-120000',
                    'size' => 1024000,
                    'checksum' => 'abc123def456',
                ],
            ]);

        $job = new CreateBackupJob($this->site, 'full');
        $job->handle($vpsManager);

        // Verify backup was created
        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);

        $backup = SiteBackup::where('site_id', $this->site->id)->first();
        $this->assertEquals(1024000, $backup->size_bytes);
        $this->assertEquals('abc123def456', $backup->checksum);

        // Verify events were dispatched
        Event::assertDispatched(BackupCreated::class);
        Event::assertDispatched(BackupCompleted::class, function ($event) use ($backup) {
            return $event->backup->id === $backup->id;
        });
    }

    #[Test]
    public function it_handles_backup_failure_gracefully()
    {
        Event::fake([BackupCreated::class, BackupFailed::class]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('createBackup')
            ->once()
            ->andReturn([
                'success' => false,
                'output' => 'Disk full error',
            ]);

        $job = new CreateBackupJob($this->site);
        $job->handle($vpsManager);

        // Verify backup was deleted after failure
        $this->assertDatabaseMissing('site_backups', [
            'site_id' => $this->site->id,
        ]);

        // Verify failure event was dispatched
        Event::assertDispatched(BackupFailed::class);
    }

    #[Test]
    public function it_creates_files_only_backup()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('createBackup')
            ->once()
            ->with($this->vps, 'test.example.com', ['files'])
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/test.example.com/2026-01-02-120000',
                    'size' => 512000,
                    'checksum' => 'files123',
                ],
            ]);

        $job = new CreateBackupJob($this->site, 'files');
        $job->handle($vpsManager);

        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'files',
        ]);
    }

    #[Test]
    public function it_creates_database_only_backup()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('createBackup')
            ->once()
            ->with($this->vps, 'test.example.com', ['database'])
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/test.example.com/2026-01-02-120000',
                    'size' => 256000,
                    'checksum' => 'db123',
                ],
            ]);

        $job = new CreateBackupJob($this->site, 'database');
        $job->handle($vpsManager);

        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'database',
        ]);
    }

    #[Test]
    public function it_returns_early_if_no_vps_server()
    {
        $siteWithoutVps = Site::factory()->create([
            'tenant_id' => $this->site->tenant_id,
            'vps_server_id' => null,
        ]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldNotReceive('createBackup');

        $job = new CreateBackupJob($siteWithoutVps);
        $job->handle($vpsManager);

        $this->assertDatabaseMissing('site_backups', [
            'site_id' => $siteWithoutVps->id,
        ]);
    }

    #[Test]
    public function it_respects_custom_retention_days()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('createBackup')
            ->once()
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/test.example.com/2026-01-02-120000',
                    'size' => 1024000,
                    'checksum' => 'abc123',
                ],
            ]);

        $job = new CreateBackupJob($this->site, 'full', 14);
        $job->handle($vpsManager);

        $backup = SiteBackup::where('site_id', $this->site->id)->first();
        $this->assertEquals(14, $backup->retention_days);
    }

    #[Test]
    public function it_throws_exception_on_unexpected_error()
    {
        Event::fake();

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('createBackup')
            ->once()
            ->andThrow(new \Exception('Network timeout'));

        $job = new CreateBackupJob($this->site);

        $this->expectException(\Exception::class);
        $this->expectExceptionMessage('Network timeout');

        $job->handle($vpsManager);

        // Verify backup was deleted
        $this->assertDatabaseMissing('site_backups', [
            'site_id' => $this->site->id,
        ]);

        // Verify failure event was dispatched
        Event::assertDispatched(BackupFailed::class);
    }

    #[Test]
    public function it_handles_job_failure_after_all_retries()
    {
        Event::fake();

        $job = new CreateBackupJob($this->site);
        $exception = new \Exception('Max retries exceeded');

        $job->failed($exception);

        Event::assertDispatched(BackupFailed::class, function ($event) use ($exception) {
            return $event->siteId === $this->site->id &&
                   str_contains($event->errorMessage, 'Max retries exceeded');
        });
    }
}
