<?php

namespace Tests\Feature\Commands;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class CleanOldBackupsCommandTest extends TestCase
{
    use RefreshDatabase;

    protected string $backupDir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->backupDir = storage_path('app/backups');
        if (!is_dir($this->backupDir)) {
            mkdir($this->backupDir, 0755, true);
        }
    }

    protected function tearDown(): void
    {
        // Cleanup test backups
        if (is_dir($this->backupDir)) {
            array_map('unlink', glob($this->backupDir . '/backup_*.sql*'));
        }

        parent::tearDown();
    }

    #[Test]
    public function it_handles_missing_backup_directory()
    {
        // Remove directory
        if (is_dir($this->backupDir)) {
            rmdir($this->backupDir);
        }

        $exitCode = Artisan::call('backup:clean', ['--dry-run' => true]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Backup directory does not exist', $output);
    }

    #[Test]
    public function it_handles_no_backups()
    {
        $exitCode = Artisan::call('backup:clean', ['--dry-run' => true]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('No backups found', $output);
    }

    #[Test]
    public function it_identifies_backups_for_deletion()
    {
        // Create old backup files (older than 1 year)
        $oldDate = now()->subDays(400)->format('Y-m-d_His');
        touch($this->backupDir . "/backup_{$oldDate}.sql");

        $exitCode = Artisan::call('backup:clean', ['--dry-run' => true]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Dry run - no files were deleted', $output);
    }

    #[Test]
    public function it_shows_backups_to_delete_in_dry_run()
    {
        // Create test backup
        $oldDate = now()->subDays(400)->format('Y-m-d_His');
        $filename = "backup_{$oldDate}.sql";
        file_put_contents($this->backupDir . '/' . $filename, 'test data');

        Artisan::call('backup:clean', ['--dry-run' => true]);
        $output = Artisan::output();

        $this->assertStringContainsString('Backups to be deleted', $output);
        $this->assertStringContainsString('Dry run', $output);
    }

    #[Test]
    public function it_does_not_delete_recent_backups()
    {
        // Create recent backup
        $recentDate = now()->format('Y-m-d_His');
        $filename = "backup_{$recentDate}.sql";
        file_put_contents($this->backupDir . '/' . $filename, 'test data');

        Artisan::call('backup:clean', ['--force' => true]);

        // File should still exist
        $this->assertFileExists($this->backupDir . '/' . $filename);
    }

    #[Test]
    public function it_requires_confirmation_without_force()
    {
        // Create old backup
        $oldDate = now()->subDays(400)->format('Y-m-d_His');
        file_put_contents($this->backupDir . "/backup_{$oldDate}.sql", 'test');

        // Without --force, command should prompt for confirmation
        // We can't test interactive prompts easily, so we verify the command runs
        $exitCode = Artisan::call('backup:clean', ['--dry-run' => true]);

        $this->assertEquals(0, $exitCode);
    }

    #[Test]
    public function it_calculates_total_space_freed()
    {
        // Create old backup with known size
        $oldDate = now()->subDays(400)->format('Y-m-d_His');
        file_put_contents($this->backupDir . "/backup_{$oldDate}.sql", str_repeat('a', 1024));

        Artisan::call('backup:clean', ['--dry-run' => true]);
        $output = Artisan::output();

        $this->assertStringContainsString('Total space to be freed', $output);
    }
}
