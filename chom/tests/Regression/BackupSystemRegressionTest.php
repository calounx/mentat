<?php

namespace Tests\Regression;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class BackupSystemRegressionTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;
    protected Site $site;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $tenant = $this->user->currentTenant();
        $this->site = Site::factory()->create([
            'tenant_id' => $tenant->id,
        ]);
    }

    #[Test]
    public function backup_can_be_created(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'filename' => 'backup-2024-01-01.tar.gz',
            'backup_type' => 'full',
            'status' => 'completed',
        ]);

        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'filename' => 'backup-2024-01-01.tar.gz',
            'backup_type' => 'full',
        ]);
    }

    #[Test]
    public function backup_belongs_to_site(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
        ]);

        $this->assertEquals($this->site->id, $backup->site_id);
        $this->assertInstanceOf(Site::class, $backup->site);
    }

    #[Test]
    public function backup_has_different_types(): void
    {
        $full = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);

        $database = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'database',
        ]);

        $files = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'backup_type' => 'files',
        ]);

        $this->assertEquals('full', $full->backup_type);
        $this->assertEquals('database', $database->backup_type);
        $this->assertEquals('files', $files->backup_type);
    }

    #[Test]
    public function backup_tracks_file_size(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'size_bytes' => 524288000, // ~500 MB
            'size_mb' => 500,
        ]);

        $this->assertEquals(524288000, $backup->size_bytes);
        $this->assertEquals(500, $backup->size_mb);
    }

    #[Test]
    public function backup_formats_size_correctly(): void
    {
        $kb = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'size_bytes' => 10240, // 10 KB
        ]);

        $mb = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'size_bytes' => 10485760, // 10 MB
        ]);

        $gb = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'size_bytes' => 10737418240, // 10 GB
        ]);

        $this->assertStringContainsString('KB', $kb->getSizeFormatted());
        $this->assertStringContainsString('MB', $mb->getSizeFormatted());
        $this->assertStringContainsString('GB', $gb->getSizeFormatted());
    }

    #[Test]
    public function backup_has_retention_policy(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'retention_days' => 30,
            'expires_at' => now()->addDays(30),
        ]);

        $this->assertEquals(30, $backup->retention_days);
        $this->assertNotNull($backup->expires_at);
    }

    #[Test]
    public function backup_can_detect_if_expired(): void
    {
        $expired = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'expires_at' => now()->subDay(),
        ]);

        $valid = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'expires_at' => now()->addDays(30),
        ]);

        $this->assertTrue($expired->isExpired());
        $this->assertFalse($valid->isExpired());
    }

    #[Test]
    public function backup_has_checksum_for_integrity(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'checksum' => hash('sha256', 'backup-content'),
        ]);

        $this->assertNotNull($backup->checksum);
        $this->assertEquals(64, strlen($backup->checksum)); // SHA-256 length
    }

    #[Test]
    public function backup_tracks_completion_time(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'completed',
            'completed_at' => now(),
        ]);

        $this->assertEquals('completed', $backup->status);
        $this->assertNotNull($backup->completed_at);
    }

    #[Test]
    public function backup_can_have_error_message(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'failed',
            'error_message' => 'Disk space full',
        ]);

        $this->assertEquals('failed', $backup->status);
        $this->assertEquals('Disk space full', $backup->error_message);
    }

    #[Test]
    public function site_can_have_multiple_backups(): void
    {
        SiteBackup::factory(5)->create([
            'site_id' => $this->site->id,
        ]);

        $this->assertEquals(5, $this->site->backups()->count());
    }

    #[Test]
    public function backup_stores_storage_path(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'storage_path' => '/backups/sites/example-com/backup-2024-01-01.tar.gz',
        ]);

        $this->assertEquals('/backups/sites/example-com/backup-2024-01-01.tar.gz', $backup->storage_path);
    }

    #[Test]
    public function user_can_list_backups_via_api(): void
    {
        Sanctum::actingAs($this->user);

        SiteBackup::factory(3)->create([
            'site_id' => $this->site->id,
        ]);

        $response = $this->getJson('/api/v1/backups');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data' => [
                '*' => ['id', 'filename', 'backup_type', 'status', 'size_mb'],
            ],
        ]);
    }

    #[Test]
    public function user_can_create_backup_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->postJson('/api/v1/backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);

        $response->assertStatus(201);
        $this->assertDatabaseHas('site_backups', [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);
    }

    #[Test]
    public function user_can_view_backup_details_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
        ]);

        $response = $this->getJson("/api/v1/backups/{$backup->id}");

        $response->assertStatus(200);
        $response->assertJson([
            'id' => $backup->id,
            'site_id' => $this->site->id,
        ]);
    }

    #[Test]
    public function user_can_delete_backup_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
        ]);

        $response = $this->deleteJson("/api/v1/backups/{$backup->id}");

        $response->assertStatus(200);
        $this->assertDatabaseMissing('site_backups', [
            'id' => $backup->id,
        ]);
    }

    #[Test]
    public function user_can_list_backups_for_specific_site(): void
    {
        Sanctum::actingAs($this->user);

        $tenant = $this->user->currentTenant();
        $site2 = Site::factory()->create(['tenant_id' => $tenant->id]);

        SiteBackup::factory(2)->create(['site_id' => $this->site->id]);
        SiteBackup::factory(3)->create(['site_id' => $site2->id]);

        $response = $this->getJson("/api/v1/sites/{$this->site->id}/backups");

        $response->assertStatus(200);
        $response->assertJsonCount(2, 'data');
    }

    #[Test]
    public function backup_status_can_be_pending(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'pending',
            'completed_at' => null,
        ]);

        $this->assertEquals('pending', $backup->status);
        $this->assertNull($backup->completed_at);
    }

    #[Test]
    public function backup_status_can_be_in_progress(): void
    {
        $backup = SiteBackup::factory()->create([
            'site_id' => $this->site->id,
            'status' => 'in_progress',
            'completed_at' => null,
        ]);

        $this->assertEquals('in_progress', $backup->status);
        $this->assertNull($backup->completed_at);
    }
}
