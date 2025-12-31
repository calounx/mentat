<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;
use Exception;

class CleanOldBackups extends Command
{
    protected $signature = 'backup:clean
                          {--dry-run : Show what would be deleted without actually deleting}
                          {--force : Skip confirmation prompt}';

    protected $description = 'Clean old backups based on retention policy';

    protected array $retentionPolicy = [
        'daily' => 7,     // Keep 7 daily backups
        'weekly' => 4,    // Keep 4 weekly backups
        'monthly' => 12,  // Keep 12 monthly backups
    ];

    public function handle(): int
    {
        $this->info('Analyzing backups...');

        try {
            $backupDir = storage_path('app/backups');

            if (!is_dir($backupDir)) {
                $this->warn('Backup directory does not exist');
                return Command::SUCCESS;
            }

            // Get all backup files
            $backups = $this->getBackupFiles($backupDir);

            if (empty($backups)) {
                $this->info('No backups found');
                return Command::SUCCESS;
            }

            $this->info('Found ' . count($backups) . ' backup(s)');

            // Categorize backups
            $categorized = $this->categorizeBackups($backups);

            // Determine which backups to delete
            $toDelete = $this->determineBackupsToDelete($categorized);

            if (empty($toDelete)) {
                $this->info('No backups need to be deleted');
                return Command::SUCCESS;
            }

            // Show what will be deleted
            $this->info('Backups to be deleted:');
            $totalSize = 0;

            foreach ($toDelete as $backup) {
                $size = filesize($backup['path']);
                $totalSize += $size;
                $this->line("  - {$backup['filename']} ({$this->formatBytes($size)})");
            }

            $this->info("Total space to be freed: " . $this->formatBytes($totalSize));

            // If dry-run, stop here
            if ($this->option('dry-run')) {
                $this->info('Dry run - no files were deleted');
                return Command::SUCCESS;
            }

            // Confirm deletion
            if (!$this->option('force')) {
                if (!$this->confirm('Do you want to proceed with deletion?')) {
                    $this->info('Deletion cancelled');
                    return Command::SUCCESS;
                }
            }

            // Delete backups
            $deleted = 0;
            foreach ($toDelete as $backup) {
                if (unlink($backup['path'])) {
                    $deleted++;
                    $this->line("Deleted: {$backup['filename']}");
                }
            }

            $this->info("Successfully deleted {$deleted} backup(s)");

            // Log cleanup
            logger('audit')->info('Backup cleanup completed', [
                'deleted_count' => $deleted,
                'freed_space_bytes' => $totalSize,
            ]);

            return Command::SUCCESS;

        } catch (Exception $e) {
            $this->error('Backup cleanup failed: ' . $e->getMessage());

            logger()->error('Backup cleanup failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return Command::FAILURE;
        }
    }

    protected function getBackupFiles(string $dir): array
    {
        $files = glob($dir . '/backup_*.sql*');
        $backups = [];

        foreach ($files as $file) {
            $filename = basename($file);

            // Extract date from filename (backup_YYYY-MM-DD_HHiiss.sql)
            if (preg_match('/backup_(\d{4}-\d{2}-\d{2})_(\d{6})/', $filename, $matches)) {
                $backups[] = [
                    'path' => $file,
                    'filename' => $filename,
                    'date' => $matches[1],
                    'time' => $matches[2],
                    'timestamp' => strtotime($matches[1] . ' ' . substr($matches[2], 0, 2) . ':' . substr($matches[2], 2, 2) . ':' . substr($matches[2], 4, 2)),
                ];
            }
        }

        // Sort by timestamp descending (newest first)
        usort($backups, fn($a, $b) => $b['timestamp'] <=> $a['timestamp']);

        return $backups;
    }

    protected function categorizeBackups(array $backups): array
    {
        $now = time();
        $categorized = [
            'daily' => [],
            'weekly' => [],
            'monthly' => [],
            'other' => [],
        ];

        foreach ($backups as $backup) {
            $age = ($now - $backup['timestamp']) / 86400; // age in days

            if ($age <= 7) {
                $categorized['daily'][] = $backup;
            } elseif ($age <= 28) {
                // Keep one backup per week
                $weekNum = date('W', $backup['timestamp']);
                if (!isset($categorized['weekly'][$weekNum])) {
                    $categorized['weekly'][$weekNum] = $backup;
                }
            } elseif ($age <= 365) {
                // Keep one backup per month
                $monthKey = date('Y-m', $backup['timestamp']);
                if (!isset($categorized['monthly'][$monthKey])) {
                    $categorized['monthly'][$monthKey] = $backup;
                }
            } else {
                $categorized['other'][] = $backup;
            }
        }

        // Convert weekly and monthly associative arrays to indexed arrays
        $categorized['weekly'] = array_values($categorized['weekly']);
        $categorized['monthly'] = array_values($categorized['monthly']);

        return $categorized;
    }

    protected function determineBackupsToDelete(array $categorized): array
    {
        $toDelete = [];

        // Delete excess daily backups
        if (count($categorized['daily']) > $this->retentionPolicy['daily']) {
            $toDelete = array_merge(
                $toDelete,
                array_slice($categorized['daily'], $this->retentionPolicy['daily'])
            );
        }

        // Delete excess weekly backups
        if (count($categorized['weekly']) > $this->retentionPolicy['weekly']) {
            $toDelete = array_merge(
                $toDelete,
                array_slice($categorized['weekly'], $this->retentionPolicy['weekly'])
            );
        }

        // Delete excess monthly backups
        if (count($categorized['monthly']) > $this->retentionPolicy['monthly']) {
            $toDelete = array_merge(
                $toDelete,
                array_slice($categorized['monthly'], $this->retentionPolicy['monthly'])
            );
        }

        // Delete all backups older than 1 year
        $toDelete = array_merge($toDelete, $categorized['other']);

        return $toDelete;
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
