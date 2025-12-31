<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Models\Backup;
use App\Models\Site;
use App\Models\User;
use App\Services\Backup\BackupService;
use App\Services\Backup\BackupRestoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\WithMockVpsManager;
use Tests\Concerns\WithPerformanceTesting;
use Tests\TestCase;

/**
 * Integration test for backup and restore workflows
 *
 * Tests complete backup creation, storage, and restoration flows including
 * automated backups, manual backups, point-in-time recovery, and validation.
 *
 * @package Tests\Integration
 */
class BackupRestoreFlowTest extends TestCase
{
    use RefreshDatabase;
    use WithMockVpsManager;
    use WithPerformanceTesting;

    protected User $user;
    protected Site $site;
    protected BackupService $backupService;
    protected BackupRestoreService $restoreService;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->site = Site::factory()->create(['user_id' => $this->user->id]);

        $this->setUpVpsMocks();

        Storage::fake('backups');

        $this->backupService = $this->app->make(BackupService::class);
        $this->restoreService = $this->app->make(BackupRestoreService::class);
    }

    /**
     * Test complete backup creation flow
     *
     * @return void
     */
    public function test_complete_backup_creation_flow(): void
    {
        // Arrange
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -czf', 'Backup created', 0);
        $this->mockCommandExecution('mysqldump', 'Database dumped', 0);

        // Act
        $backup = $this->assertBenchmark(
            fn() => $this->actingAs($this->user)
                ->post("/api/v1/sites/{$this->site->id}/backups", [
                    'type' => 'full',
                    'description' => 'Manual backup before update',
                ])
                ->json('data'),
            'backup_creation'
        );

        // Assert
        $this->assertDatabaseHas('backups', [
            'site_id' => $this->site->id,
            'type' => 'full',
            'status' => 'completed',
        ]);

        $this->assertCommandExecuted('tar -czf');
        $this->assertCommandExecuted('mysqldump');

        $this->assertNotNull($backup['file_path']);
        $this->assertGreaterThan(0, $backup['size_bytes']);
    }

    /**
     * Test incremental backup
     *
     * @return void
     */
    public function test_incremental_backup_only_backs_up_changes(): void
    {
        // Arrange
        $fullBackup = Backup::factory()->create([
            'site_id' => $this->site->id,
            'type' => 'full',
            'created_at' => now()->subDay(),
        ]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution(
            'rsync --archive --itemize-changes',
            'Incremental backup created',
            0
        );

        // Act
        $response = $this->actingAs($this->user)
            ->post("/api/v1/sites/{$this->site->id}/backups", [
                'type' => 'incremental',
                'base_backup_id' => $fullBackup->id,
            ]);

        // Assert
        $response->assertStatus(201);
        $backup = $response->json('data');

        $this->assertEquals('incremental', $backup['type']);
        $this->assertEquals($fullBackup->id, $backup['base_backup_id']);
        $this->assertLessThan($fullBackup->size_bytes, $backup['size_bytes']);
    }

    /**
     * Test backup restoration flow
     *
     * @return void
     */
    public function test_complete_backup_restoration_flow(): void
    {
        // Arrange
        $backup = Backup::factory()->create([
            'site_id' => $this->site->id,
            'type' => 'full',
            'status' => 'completed',
        ]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -xzf', 'Files restored', 0);
        $this->mockCommandExecution('mysql', 'Database restored', 0);
        $this->mockCommandExecution('chown -R www-data:www-data', 'Permissions set', 0);

        // Act
        $restore = $this->assertBenchmark(
            fn() => $this->actingAs($this->user)
                ->post("/api/v1/backups/{$backup->id}/restore")
                ->json('data'),
            'restore_operation'
        );

        // Assert
        $this->assertEquals('completed', $restore['status']);
        $this->assertCommandExecuted('tar -xzf');
        $this->assertCommandExecuted('mysql');
    }

    /**
     * Test automated backup scheduling
     *
     * @return void
     */
    public function test_automated_backup_runs_on_schedule(): void
    {
        // Arrange
        $this->site->update([
            'backup_schedule' => 'daily',
            'last_backup_at' => now()->subDay()->subHour(),
        ]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -czf', 'Automated backup created', 0);

        // Act - Simulate scheduled job running
        $this->artisan('backups:run-scheduled');

        // Assert
        $this->assertDatabaseHas('backups', [
            'site_id' => $this->site->id,
            'type' => 'automated',
            'status' => 'completed',
        ]);
    }

    /**
     * Test backup with encryption
     *
     * @return void
     */
    public function test_backup_with_encryption(): void
    {
        // Arrange
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('openssl enc -aes-256-cbc', 'Backup encrypted', 0);

        // Act
        $response = $this->actingAs($this->user)
            ->post("/api/v1/sites/{$this->site->id}/backups", [
                'type' => 'full',
                'encryption' => true,
            ]);

        // Assert
        $response->assertStatus(201);
        $backup = $response->json('data');

        $this->assertTrue($backup['encrypted']);
        $this->assertNotNull($backup['encryption_key_id']);
    }

    /**
     * Test backup retention policy enforcement
     *
     * @return void
     */
    public function test_backup_retention_policy_deletes_old_backups(): void
    {
        // Arrange
        $oldBackups = Backup::factory()->count(5)->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDays(31), // Older than 30-day retention
        ]);

        $recentBackups = Backup::factory()->count(3)->create([
            'site_id' => $this->site->id,
            'created_at' => now()->subDays(15),
        ]);

        // Act
        $this->artisan('backups:cleanup');

        // Assert
        foreach ($oldBackups as $backup) {
            $this->assertDatabaseMissing('backups', ['id' => $backup->id]);
        }

        foreach ($recentBackups as $backup) {
            $this->assertDatabaseHas('backups', ['id' => $backup->id]);
        }
    }

    /**
     * Test point-in-time recovery
     *
     * @return void
     */
    public function test_point_in_time_recovery(): void
    {
        // Arrange
        $targetTime = now()->subHours(2);

        $backupBefore = Backup::factory()->create([
            'site_id' => $this->site->id,
            'created_at' => $targetTime->copy()->subHour(),
        ]);

        $backupAfter = Backup::factory()->create([
            'site_id' => $this->site->id,
            'created_at' => $targetTime->copy()->addHour(),
        ]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('tar -xzf', 'Restored', 0);

        // Act
        $response = $this->actingAs($this->user)
            ->post("/api/v1/sites/{$this->site->id}/restore-to-point", [
                'target_time' => $targetTime->toIso8601String(),
            ]);

        // Assert
        $response->assertStatus(200);

        // Should use the backup just before target time
        $this->assertEquals($backupBefore->id, $response->json('data.backup_id'));
    }

    /**
     * Test backup verification
     *
     * @return void
     */
    public function test_backup_verification_ensures_integrity(): void
    {
        // Arrange
        $backup = Backup::factory()->create([
            'site_id' => $this->site->id,
            'checksum' => hash('sha256', 'backup-content'),
        ]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('sha256sum', hash('sha256', 'backup-content'), 0);

        // Act
        $response = $this->actingAs($this->user)
            ->post("/api/v1/backups/{$backup->id}/verify");

        // Assert
        $response->assertStatus(200);
        $response->assertJson([
            'verified' => true,
            'integrity' => 'valid',
        ]);
    }

    /**
     * Test backup quota enforcement
     *
     * @return void
     */
    public function test_backup_quota_prevents_excessive_backups(): void
    {
        // Arrange
        $basicUser = User::factory()->create(['subscription_tier' => 'basic']);
        $site = Site::factory()->create(['user_id' => $basicUser->id]);

        // Create backups up to quota (assume basic allows 5 backups)
        Backup::factory()->count(5)->create(['site_id' => $site->id]);

        $this->mockSuccessfulSshConnection();

        // Act
        $response = $this->actingAs($basicUser)
            ->post("/api/v1/sites/{$site->id}/backups", ['type' => 'full']);

        // Assert
        $response->assertStatus(403);
        $response->assertJson([
            'message' => 'Backup quota exceeded for your subscription tier',
        ]);
    }

    /**
     * Test rollback after failed restore
     *
     * @return void
     */
    public function test_rollback_after_failed_restore(): void
    {
        // Arrange
        $backup = Backup::factory()->create(['site_id' => $this->site->id]);

        $this->mockSuccessfulSshConnection();
        $this->mockCommandFailure('mysql', 'Database restore failed', 1);

        // Act
        $response = $this->actingAs($this->user)
            ->post("/api/v1/backups/{$backup->id}/restore");

        // Assert
        $response->assertStatus(500);

        // Site should still be in working state
        $this->site->refresh();
        $this->assertEquals('active', $this->site->status);
    }
}
