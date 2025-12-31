<?php

namespace Tests\Integration;

use App\Events\Backup\BackupCompleted;
use App\Events\Backup\BackupCreated;
use App\Events\Backup\BackupFailed;
use App\Jobs\CreateBackupJob;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\TierLimit;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

/**
 * Integration tests for Backup lifecycle events.
 *
 * Tests the complete event flow from backup creation through completion/failure,
 * verifying that all events are dispatched correctly and listeners are triggered.
 */
class BackupLifecycleEventsTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;
    protected Tenant $tenant;
    protected Site $site;
    protected VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test data
        $this->user = User::factory()->create();
        $this->tenant = Tenant::factory()->create(['owner_id' => $this->user->id]);

        TierLimit::factory()->create([
            'tier' => 'free',
            'backup_retention_days' => 7,
        ]);

        $this->vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vps->id,
            'status' => 'active',
        ]);
    }

    /**
     * Test that BackupCreated event is dispatched when creating a backup.
     */
    public function test_backup_created_event_is_dispatched(): void
    {
        Event::fake([BackupCreated::class]);

        // Mock VPS manager
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/test.tar.gz',
                    'size' => 1024000,
                    'checksum' => 'abc123',
                ],
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'full');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Assert event was dispatched
        Event::assertDispatched(BackupCreated::class, function ($event) {
            return $event->backup->site_id === $this->site->id
                && $event->site->id === $this->site->id;
        });
    }

    /**
     * Test that BackupCompleted event is dispatched on successful backup.
     */
    public function test_backup_completed_event_is_dispatched(): void
    {
        Event::fake([BackupCompleted::class]);

        // Mock VPS manager
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/test.tar.gz',
                    'size' => 2048000,
                    'checksum' => 'def456',
                ],
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'full');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Assert event was dispatched
        Event::assertDispatched(BackupCompleted::class, function ($event) {
            return $event->backup->site_id === $this->site->id
                && $event->sizeBytes === 2048000
                && $event->durationSeconds >= 0;
        });
    }

    /**
     * Test that BackupFailed event is dispatched on backup failure.
     */
    public function test_backup_failed_event_is_dispatched_on_failure(): void
    {
        Event::fake([BackupFailed::class]);

        // Mock VPS manager to return failure
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => false,
                'output' => 'Backup creation failed: insufficient disk space',
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'full');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Assert event was dispatched
        Event::assertDispatched(BackupFailed::class, function ($event) {
            return $event->siteId === $this->site->id
                && $event->backupType === 'full'
                && str_contains($event->errorMessage, 'insufficient disk space');
        });
    }

    /**
     * Test that BackupFailed event is dispatched on exception.
     */
    public function test_backup_failed_event_is_dispatched_on_exception(): void
    {
        Event::fake([BackupFailed::class]);

        // Mock VPS manager to throw exception
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andThrow(new \RuntimeException('VPS connection timeout'));

        // Dispatch backup job (should catch exception)
        $job = new CreateBackupJob($this->site, 'database');

        try {
            $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));
        } catch (\RuntimeException $e) {
            // Expected to rethrow
        }

        // Assert event was dispatched
        Event::assertDispatched(BackupFailed::class, function ($event) {
            return $event->siteId === $this->site->id
                && $event->backupType === 'database'
                && str_contains($event->errorMessage, 'VPS connection timeout');
        });
    }

    /**
     * Test complete backup lifecycle: create → complete.
     */
    public function test_complete_backup_success_lifecycle_events(): void
    {
        Event::fake();

        // Mock VPS manager
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/lifecycle-test.tar.gz',
                    'size' => 5120000,
                    'checksum' => 'ghi789',
                ],
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'full');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Verify both events were dispatched
        Event::assertDispatched(BackupCreated::class);
        Event::assertDispatched(BackupCompleted::class);
        Event::assertNotDispatched(BackupFailed::class);

        Event::assertDispatchedTimes(BackupCreated::class, 1);
        Event::assertDispatchedTimes(BackupCompleted::class, 1);
    }

    /**
     * Test complete backup lifecycle: create → fail.
     */
    public function test_complete_backup_failure_lifecycle_events(): void
    {
        Event::fake();

        // Mock VPS manager to fail
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => false,
                'output' => 'Backup failed: network error',
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'files');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Verify both created and failed events were dispatched
        Event::assertDispatched(BackupCreated::class);
        Event::assertDispatched(BackupFailed::class);
        Event::assertNotDispatched(BackupCompleted::class);

        Event::assertDispatchedTimes(BackupCreated::class, 1);
        Event::assertDispatchedTimes(BackupFailed::class, 1);
    }

    /**
     * Test that backup record is deleted on failure.
     */
    public function test_backup_record_deleted_on_failure(): void
    {
        // Mock VPS manager to fail
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn(['success' => false, 'output' => 'Failed']);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'full');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Verify backup record was NOT persisted (deleted on failure)
        $this->assertDatabaseMissing('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);
    }

    /**
     * Test that backup record persists on success.
     */
    public function test_backup_record_persists_on_success(): void
    {
        // Mock VPS manager
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/success-test.tar.gz',
                    'size' => 3072000,
                    'checksum' => 'jkl012',
                ],
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'database');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Verify backup record was persisted
        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'database',
            'size_bytes' => 3072000,
            'checksum' => 'jkl012',
        ]);
    }

    /**
     * Test that event metadata includes correct backup type.
     */
    public function test_backup_completed_event_metadata(): void
    {
        // Mock VPS manager
        $this->mock(\App\Services\Integration\VPSManagerBridge::class)
            ->shouldReceive('createBackup')
            ->andReturn([
                'success' => true,
                'data' => [
                    'path' => '/var/backups/metadata-test.tar.gz',
                    'size' => 4096000,
                    'checksum' => 'mno345',
                ],
            ]);

        // Dispatch backup job
        $job = new CreateBackupJob($this->site, 'files');
        $job->handle(app(\App\Services\Integration\VPSManagerBridge::class));

        // Fetch the created backup
        $backup = SiteBackup::where('site_id', $this->site->id)
            ->where('backup_type', 'files')
            ->first();

        $this->assertNotNull($backup);

        // Manually create and inspect event
        $event = new BackupCompleted($backup, 4096000, 10);
        $metadata = $event->getMetadata();

        $this->assertArrayHasKey('event', $metadata);
        $this->assertArrayHasKey('occurred_at', $metadata);
        $this->assertArrayHasKey('backup_id', $metadata);
        $this->assertArrayHasKey('site_id', $metadata);
        $this->assertArrayHasKey('backup_type', $metadata);
        $this->assertEquals('files', $metadata['backup_type']);
    }
}
