<?php

namespace Tests\Unit\Events;

use App\Events\Backup\BackupCompleted;
use App\Events\Backup\BackupCreated;
use App\Events\Backup\BackupFailed;
use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BackupEventTest extends TestCase
{
    use RefreshDatabase;

    public function test_backup_created_event_contains_required_data(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'backup_type' => 'full',
        ]);

        $event = new BackupCreated($backup, 'test-user-id');

        $this->assertSame($backup->id, $event->backup->id);
        $this->assertEquals('test-user-id', $event->actorId);
        $this->assertEquals('user', $event->actorType);

        $metadata = $event->getMetadata();
        $this->assertArrayHasKey('backup_id', $metadata);
        $this->assertArrayHasKey('site_id', $metadata);
        $this->assertArrayHasKey('backup_type', $metadata);
        $this->assertEquals('full', $metadata['backup_type']);
    }

    public function test_backup_created_event_has_correct_name(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create(['site_id' => $site->id]);

        $event = new BackupCreated($backup);

        $this->assertEquals('BackupCreated', $event->getEventName());
    }

    public function test_backup_completed_event_includes_size_and_duration(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'size_bytes' => 1024 * 1024 * 50, // 50 MB
        ]);

        $event = new BackupCompleted($backup, 52428800, 120);

        $this->assertEquals(52428800, $event->sizeBytes);
        $this->assertEquals(120, $event->durationSeconds);
        $this->assertEquals('system', $event->actorType);

        $metadata = $event->getMetadata();
        $this->assertEquals(52428800, $metadata['size_bytes']);
        $this->assertEquals(120, $metadata['duration_seconds']);
        $this->assertArrayHasKey('size_formatted', $metadata);
    }

    public function test_backup_completed_event_includes_backup_data(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'backup_type' => 'database',
        ]);

        $event = new BackupCompleted($backup, 1024, 30);

        $metadata = $event->getMetadata();
        $this->assertEquals($backup->id, $metadata['backup_id']);
        $this->assertEquals($site->id, $metadata['site_id']);
        $this->assertEquals('database', $metadata['backup_type']);
    }

    public function test_backup_failed_event_uses_primitive_data(): void
    {
        $event = new BackupFailed(
            'site-uuid-123',
            'full',
            'Disk space insufficient'
        );

        $this->assertEquals('site-uuid-123', $event->siteId);
        $this->assertEquals('full', $event->backupType);
        $this->assertEquals('Disk space insufficient', $event->errorMessage);
        $this->assertEquals('system', $event->actorType);

        $metadata = $event->getMetadata();
        $this->assertEquals('site-uuid-123', $metadata['site_id']);
        $this->assertEquals('full', $metadata['backup_type']);
        $this->assertEquals('Disk space insufficient', $metadata['error']);
    }

    public function test_backup_failed_event_has_correct_name(): void
    {
        $event = new BackupFailed('site-id', 'full', 'Error');

        $this->assertEquals('BackupFailed', $event->getEventName());
    }

    public function test_all_backup_events_have_occurred_at_timestamp(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create(['site_id' => $site->id]);

        $events = [
            new BackupCreated($backup),
            new BackupCompleted($backup, 1024, 60),
            new BackupFailed($site->id, 'full', 'Error'),
        ];

        foreach ($events as $event) {
            $this->assertInstanceOf(\DateTimeInterface::class, $event->occurredAt);
            $this->assertNotNull($event->occurredAt);

            $metadata = $event->getMetadata();
            $this->assertArrayHasKey('occurred_at', $metadata);
        }
    }

    public function test_backup_events_track_actor_information(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create(['site_id' => $site->id]);

        // User-triggered event (manual backup)
        $userEvent = new BackupCreated($backup, 'user-123');
        $this->assertEquals('user-123', $userEvent->actorId);
        $this->assertEquals('user', $userEvent->actorType);

        // System-triggered event (scheduled backup)
        $systemEvent = new BackupCompleted($backup, 1024, 60);
        $this->assertEquals('system', $systemEvent->actorType);
    }

    public function test_backup_events_include_event_class_in_metadata(): void
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create(['site_id' => $site->id]);

        $event = new BackupCreated($backup);
        $metadata = $event->getMetadata();

        $this->assertArrayHasKey('event', $metadata);
        $this->assertEquals(BackupCreated::class, $metadata['event']);
    }
}
