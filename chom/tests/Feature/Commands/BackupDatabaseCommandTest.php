<?php

namespace Tests\Feature\Commands;

use App\Services\Alerting\AlertManager;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class BackupDatabaseCommandTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Create backup directory
        $backupDir = storage_path('app/backups');
        if (!is_dir($backupDir)) {
            mkdir($backupDir, 0755, true);
        }
    }

    protected function tearDown(): void
    {
        // Cleanup backup files
        $backupDir = storage_path('app/backups');
        if (is_dir($backupDir)) {
            array_map('unlink', glob($backupDir . '/backup_*.sql*'));
        }

        parent::tearDown();
    }

    #[Test]
    public function it_creates_database_backup()
    {
        if (Config::get('database.default') !== 'sqlite') {
            $this->markTestSkipped('This test requires SQLite database');
        }

        $exitCode = Artisan::call('backup:database');

        $this->assertEquals(0, $exitCode);

        // Verify backup file was created
        $backupDir = storage_path('app/backups');
        $files = glob($backupDir . '/backup_*.sql');

        $this->assertNotEmpty($files, 'No backup file was created');
    }

    #[Test]
    public function it_creates_encrypted_backup()
    {
        if (Config::get('database.default') !== 'sqlite') {
            $this->markTestSkipped('This test requires SQLite database');
        }

        if (!function_exists('openssl_encrypt')) {
            $this->markTestSkipped('OpenSSL extension not available');
        }

        Config::set('app.key', 'base64:' . base64_encode(random_bytes(32)));

        $exitCode = Artisan::call('backup:database', ['--encrypt' => true]);

        $this->assertEquals(0, $exitCode);

        // Verify encrypted backup file was created
        $backupDir = storage_path('app/backups');
        $files = glob($backupDir . '/backup_*.sql.enc');

        $this->assertNotEmpty($files, 'No encrypted backup file was created');
    }

    #[Test]
    public function it_skips_encryption_if_no_app_key()
    {
        if (Config::get('database.default') !== 'sqlite') {
            $this->markTestSkipped('This test requires SQLite database');
        }

        Config::set('app.key', null);

        $exitCode = Artisan::call('backup:database', ['--encrypt' => true]);

        $this->assertEquals(0, $exitCode);

        // Should create unencrypted backup
        $backupDir = storage_path('app/backups');
        $files = glob($backupDir . '/backup_*.sql');

        $this->assertNotEmpty($files, 'No backup file was created');
    }

    #[Test]
    public function it_handles_missing_backup_directory()
    {
        // Remove backup directory
        $backupDir = storage_path('app/backups');
        if (is_dir($backupDir)) {
            rmdir($backupDir);
        }

        if (Config::get('database.default') !== 'sqlite') {
            $this->markTestSkipped('This test requires SQLite database');
        }

        $exitCode = Artisan::call('backup:database');

        $this->assertEquals(0, $exitCode);

        // Directory should be created
        $this->assertDirectoryExists($backupDir);
    }

    #[Test]
    public function it_outputs_backup_information()
    {
        if (Config::get('database.default') !== 'sqlite') {
            $this->markTestSkipped('This test requires SQLite database');
        }

        Artisan::call('backup:database');
        $output = Artisan::output();

        $this->assertStringContainsString('Starting database backup', $output);
        $this->assertStringContainsString('Backup completed successfully', $output);
    }

    #[Test]
    public function it_tests_backup_integrity()
    {
        if (Config::get('database.default') !== 'sqlite') {
            $this->markTestSkipped('This test requires SQLite database');
        }

        $exitCode = Artisan::call('backup:database', ['--test' => true]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Testing backup integrity', $output);
    }
}
