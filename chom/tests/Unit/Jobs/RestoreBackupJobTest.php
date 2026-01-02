<?php

namespace Tests\Unit\Jobs;

use App\Jobs\RestoreBackupJob;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class RestoreBackupJobTest extends TestCase
{
    use RefreshDatabase;

    protected Site $site;
    protected VpsServer $vps;
    protected SiteBackup $backup;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $this->vps = VpsServer::factory()->create([
            'tenant_id' => $tenant->id,
        ]);
        $this->site = Site::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_server_id' => $this->vps->id,
            'domain' => 'test.example.com',
            'status' => 'active',
        ]);
        $this->backup = SiteBackup::create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'storage_path' => '/var/backups/test.example.com/2026-01-01-000000',
            'size_bytes' => 1024000,
            'checksum' => 'abc123',
            'retention_days' => 7,
            'expires_at' => now()->addDays(7),
        ]);
    }

    #[Test]
    public function it_can_be_dispatched_to_queue()
    {
        Queue::fake();

        dispatch(new RestoreBackupJob($this->backup));

        Queue::assertPushed(RestoreBackupJob::class, function ($job) {
            return $job->backup->id === $this->backup->id;
        });
    }

    #[Test]
    public function it_has_correct_retry_configuration()
    {
        $job = new RestoreBackupJob($this->backup);

        $this->assertEquals(2, $job->tries);
        $this->assertEquals(60, $job->backoff);
    }

    #[Test]
    public function it_restores_backup_successfully()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('restoreBackup')
            ->once()
            ->with($this->vps, '/var/backups/test.example.com/2026-01-01-000000')
            ->andReturn([
                'success' => true,
                'output' => 'Restore completed successfully',
            ]);

        $job = new RestoreBackupJob($this->backup);
        $job->handle($vpsManager);

        // Site should be back to active status
        $this->assertEquals('active', $this->site->fresh()->status);
    }

    #[Test]
    public function it_sets_site_to_restoring_status_during_restore()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('restoreBackup')
            ->once()
            ->andReturnUsing(function () {
                // Check status during restore
                $this->assertEquals('restoring', $this->site->fresh()->status);
                return ['success' => true];
            });

        $job = new RestoreBackupJob($this->backup);
        $job->handle($vpsManager);
    }

    #[Test]
    public function it_restores_previous_status_after_successful_restore()
    {
        $this->site->update(['status' => 'maintenance']);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('restoreBackup')
            ->once()
            ->andReturn(['success' => true]);

        $job = new RestoreBackupJob($this->backup);
        $job->handle($vpsManager);

        $this->assertEquals('maintenance', $this->site->fresh()->status);
    }

    #[Test]
    public function it_restores_previous_status_on_failure()
    {
        $this->site->update(['status' => 'active']);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('restoreBackup')
            ->once()
            ->andReturn([
                'success' => false,
                'output' => 'Restore failed',
            ]);

        $job = new RestoreBackupJob($this->backup);
        $job->handle($vpsManager);

        $this->assertEquals('active', $this->site->fresh()->status);
    }

    #[Test]
    public function it_returns_early_if_no_site()
    {
        $backup = SiteBackup::create([
            'site_id' => 999999,
            'backup_type' => 'full',
            'storage_path' => '/var/backups/test/backup.tar.gz',
            'size_bytes' => 1024,
            'retention_days' => 7,
            'expires_at' => now()->addDays(7),
        ]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldNotReceive('restoreBackup');

        $job = new RestoreBackupJob($backup);
        $job->handle($vpsManager);
    }

    #[Test]
    public function it_returns_early_if_no_vps_server()
    {
        $this->site->update(['vps_server_id' => null]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldNotReceive('restoreBackup');

        $job = new RestoreBackupJob($this->backup);
        $job->handle($vpsManager);
    }

    #[Test]
    public function it_sets_site_to_active_on_exception()
    {
        $this->site->update(['status' => 'active']);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('restoreBackup')
            ->once()
            ->andThrow(new \Exception('Network error'));

        $job = new RestoreBackupJob($this->backup);

        $this->expectException(\Exception::class);

        $job->handle($vpsManager);

        $this->assertEquals('active', $this->site->fresh()->status);
    }

    #[Test]
    public function it_handles_job_failure_after_all_retries()
    {
        $this->site->update(['status' => 'restoring']);

        $job = new RestoreBackupJob($this->backup);
        $exception = new \Exception('Max retries exceeded');

        $job->failed($exception);

        // Should restore site to active status
        $this->assertEquals('active', $this->site->fresh()->status);
    }

    #[Test]
    public function it_does_not_change_status_if_not_restoring_on_failure()
    {
        $this->site->update(['status' => 'active']);

        $job = new RestoreBackupJob($this->backup);
        $job->failed(new \Exception('Failed'));

        // Status should remain unchanged
        $this->assertEquals('active', $this->site->fresh()->status);
    }
}
