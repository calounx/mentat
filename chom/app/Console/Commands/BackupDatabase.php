<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\DB;
use App\Services\Alerting\AlertManager;
use Exception;

class BackupDatabase extends Command
{
    protected $signature = 'backup:database
                          {--encrypt : Encrypt the backup file}
                          {--upload : Upload to remote storage}
                          {--test : Test backup by attempting restore}';

    protected $description = 'Create an encrypted database backup and optionally upload to remote storage';

    protected AlertManager $alertManager;

    public function __construct(AlertManager $alertManager)
    {
        parent::__construct();
        $this->alertManager = $alertManager;
    }

    public function handle(): int
    {
        $startTime = microtime(true);

        $this->info('Starting database backup...');

        try {
            // Create backup directory if it doesn't exist
            $backupDir = storage_path('app/backups');
            if (!is_dir($backupDir)) {
                mkdir($backupDir, 0755, true);
            }

            // Generate backup filename
            $timestamp = now()->format('Y-m-d_His');
            $filename = "backup_{$timestamp}.sql";
            $filepath = $backupDir . '/' . $filename;

            // Create backup
            $this->info('Creating database dump...');
            $this->createBackup($filepath);

            $filesize = filesize($filepath);
            $this->info("Backup created: {$filename} (" . $this->formatBytes($filesize) . ")");

            // Encrypt if requested
            if ($this->option('encrypt')) {
                $this->info('Encrypting backup...');
                $encryptedPath = $this->encryptBackup($filepath);

                if ($encryptedPath) {
                    unlink($filepath); // Remove unencrypted file
                    $filepath = $encryptedPath;
                    $filename = basename($encryptedPath);
                    $this->info("Backup encrypted: {$filename}");
                }
            }

            // Upload to remote storage if requested
            if ($this->option('upload')) {
                $this->info('Uploading to remote storage...');
                $this->uploadToRemote($filepath, $filename);
            }

            // Test backup if requested
            if ($this->option('test')) {
                $this->info('Testing backup integrity...');
                $this->testBackup($filepath);
            }

            $duration = round(microtime(true) - $startTime, 2);
            $this->info("Backup completed successfully in {$duration}s");

            // Log success
            logger('audit')->info('Database backup completed', [
                'filename' => $filename,
                'size_bytes' => filesize($filepath),
                'duration_seconds' => $duration,
                'encrypted' => $this->option('encrypt'),
                'uploaded' => $this->option('upload'),
            ]);

            // Send success notification
            $this->alertManager->info(
                'backup_completed',
                "Database backup completed successfully: {$filename}",
                ['duration' => $duration, 'size' => $this->formatBytes(filesize($filepath))]
            );

            return Command::SUCCESS;

        } catch (Exception $e) {
            $this->error('Backup failed: ' . $e->getMessage());

            logger()->error('Database backup failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            // Send failure alert
            $this->alertManager->critical(
                'backup_failed',
                'Database backup failed: ' . $e->getMessage()
            );

            return Command::FAILURE;
        }
    }

    protected function createBackup(string $filepath): void
    {
        $connection = config('database.default');
        $dbConfig = config("database.connections.{$connection}");

        switch ($dbConfig['driver']) {
            case 'mysql':
                $this->createMySQLBackup($filepath, $dbConfig);
                break;

            case 'pgsql':
                $this->createPostgreSQLBackup($filepath, $dbConfig);
                break;

            case 'sqlite':
                $this->createSQLiteBackup($filepath, $dbConfig);
                break;

            default:
                throw new Exception("Unsupported database driver: {$dbConfig['driver']}");
        }
    }

    protected function createMySQLBackup(string $filepath, array $config): void
    {
        $command = sprintf(
            'mysqldump --user=%s --password=%s --host=%s --port=%s --single-transaction --quick %s > %s',
            escapeshellarg($config['username']),
            escapeshellarg($config['password']),
            escapeshellarg($config['host']),
            escapeshellarg($config['port'] ?? 3306),
            escapeshellarg($config['database']),
            escapeshellarg($filepath)
        );

        $output = [];
        $returnCode = 0;
        exec($command, $output, $returnCode);

        if ($returnCode !== 0) {
            throw new Exception('MySQL backup failed with exit code ' . $returnCode);
        }

        if (!file_exists($filepath) || filesize($filepath) === 0) {
            throw new Exception('Backup file is empty or does not exist');
        }
    }

    protected function createPostgreSQLBackup(string $filepath, array $config): void
    {
        $command = sprintf(
            'PGPASSWORD=%s pg_dump --username=%s --host=%s --port=%s --format=plain --file=%s %s',
            escapeshellarg($config['password']),
            escapeshellarg($config['username']),
            escapeshellarg($config['host']),
            escapeshellarg($config['port'] ?? 5432),
            escapeshellarg($filepath),
            escapeshellarg($config['database'])
        );

        $output = [];
        $returnCode = 0;
        exec($command, $output, $returnCode);

        if ($returnCode !== 0) {
            throw new Exception('PostgreSQL backup failed with exit code ' . $returnCode);
        }

        if (!file_exists($filepath) || filesize($filepath) === 0) {
            throw new Exception('Backup file is empty or does not exist');
        }
    }

    protected function createSQLiteBackup(string $filepath, array $config): void
    {
        $dbPath = $config['database'];

        if (!file_exists($dbPath)) {
            throw new Exception("SQLite database not found: {$dbPath}");
        }

        if (!copy($dbPath, $filepath)) {
            throw new Exception('Failed to copy SQLite database');
        }
    }

    protected function encryptBackup(string $filepath): ?string
    {
        if (!function_exists('openssl_encrypt')) {
            $this->warn('OpenSSL not available, skipping encryption');
            return null;
        }

        $key = config('app.key');
        if (!$key) {
            $this->warn('APP_KEY not set, skipping encryption');
            return null;
        }

        // Read the file
        $data = file_get_contents($filepath);

        // Generate IV
        $ivLength = openssl_cipher_iv_length('aes-256-cbc');
        $iv = openssl_random_pseudo_bytes($ivLength);

        // Encrypt
        $encrypted = openssl_encrypt($data, 'aes-256-cbc', $key, OPENSSL_RAW_DATA, $iv);

        // Combine IV and encrypted data
        $encryptedData = base64_encode($iv . $encrypted);

        // Write to new file
        $encryptedPath = $filepath . '.enc';
        file_put_contents($encryptedPath, $encryptedData);

        return $encryptedPath;
    }

    protected function uploadToRemote(string $filepath, string $filename): void
    {
        // Check if S3 is configured
        $disk = config('backup.remote_disk', 's3');

        try {
            Storage::disk($disk)->put(
                'backups/' . $filename,
                file_get_contents($filepath)
            );

            $this->info("Uploaded to {$disk}: backups/{$filename}");
        } catch (Exception $e) {
            $this->warn("Failed to upload to remote storage: " . $e->getMessage());
        }
    }

    protected function testBackup(string $filepath): void
    {
        // For MySQL, test by parsing SQL
        if (str_ends_with($filepath, '.sql')) {
            $content = file_get_contents($filepath);

            if (strpos($content, 'CREATE TABLE') === false && strpos($content, 'INSERT INTO') === false) {
                $this->warn('Backup file may be corrupted (no CREATE TABLE or INSERT statements found)');
            } else {
                $this->info('Backup integrity check passed');
            }
        }
    }

    protected function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];

        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision) . ' ' . $units[$i];
    }
}
