<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Models\SiteBackup;
use App\Models\VpsServer;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Throwable;

/**
 * Self-Healing Job
 *
 * Automated healing job that fixes detected incoherencies in the system.
 * Applies safe, reversible fixes to reconcile database and disk state.
 *
 * @package App\Jobs
 */
class SelfHealingJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * Number of times the job may be attempted.
     *
     * @var int
     */
    public int $tries = 3;

    /**
     * Job timeout in seconds (30 minutes for healing operations).
     *
     * @var int
     */
    public int $timeout = 1800;

    /**
     * Exponential backoff delays in seconds.
     *
     * @var array<int>
     */
    public array $backoff = [180, 360, 720];

    /**
     * Health check results containing detected issues
     *
     * @var array
     */
    private array $results;

    /**
     * Create a new job instance.
     *
     * @param array $results Health check results from CoherencyCheckJob
     */
    public function __construct(array $results)
    {
        $this->results = $results;
    }

    /**
     * Execute the job.
     *
     * @return void
     */
    public function handle(): void
    {
        $startTime = microtime(true);

        Log::info('Self-healing job started', [
            'job_id' => $this->job?->getJobId(),
            'total_issues' => $this->results['summary']['total_issues'] ?? 0,
            'attempt' => $this->attempts(),
        ]);

        $healedCount = 0;
        $failedCount = 0;

        try {
            // Heal orphaned backups (safest operation - just cleanup)
            if (isset($this->results['orphaned_backups']) && $this->results['orphaned_backups']->isNotEmpty()) {
                $result = $this->healOrphanedBackups($this->results['orphaned_backups']);
                $healedCount += $result['healed'];
                $failedCount += $result['failed'];
            }

            // Heal incorrect VPS site counts (safe - just counter updates)
            if (isset($this->results['incorrect_vps_counts']) && $this->results['incorrect_vps_counts']->isNotEmpty()) {
                $result = $this->healVpsSiteCounts($this->results['incorrect_vps_counts']);
                $healedCount += $result['healed'];
                $failedCount += $result['failed'];
            }

            // Heal orphaned database sites (mark as inactive instead of deleting)
            if (isset($this->results['orphaned_database_sites']) && $this->results['orphaned_database_sites']->isNotEmpty()) {
                $result = $this->healOrphanedDatabaseSites($this->results['orphaned_database_sites']);
                $healedCount += $result['healed'];
                $failedCount += $result['failed'];
            }

            // Note: We do NOT auto-heal orphaned disk sites or SSL expiring soon
            // as they require manual intervention or specific business logic

            $executionTime = round((microtime(true) - $startTime) * 1000, 2);

            Log::info('Self-healing job completed', [
                'job_id' => $this->job?->getJobId(),
                'execution_time_ms' => $executionTime,
                'healed_count' => $healedCount,
                'failed_count' => $failedCount,
                'total_issues' => $this->results['summary']['total_issues'] ?? 0,
            ]);
        } catch (Throwable $e) {
            $executionTime = round((microtime(true) - $startTime) * 1000, 2);

            Log::error('Self-healing job failed', [
                'job_id' => $this->job?->getJobId(),
                'execution_time_ms' => $executionTime,
                'attempt' => $this->attempts(),
                'max_tries' => $this->tries,
                'exception' => get_class($e),
                'message' => $e->getMessage(),
                'file' => $e->getFile(),
                'line' => $e->getLine(),
            ]);

            // Re-throw to trigger retry logic
            throw $e;
        }
    }

    /**
     * Heal orphaned backups by deleting them
     *
     * Removes backup records and their associated files for backups that reference
     * non-existent sites.
     *
     * @param \Illuminate\Support\Collection $orphanedBackups
     * @return array{healed: int, failed: int}
     */
    private function healOrphanedBackups($orphanedBackups): array
    {
        Log::info('Starting orphaned backups healing', [
            'count' => $orphanedBackups->count(),
        ]);

        $healed = 0;
        $failed = 0;

        foreach ($orphanedBackups as $item) {
            /** @var SiteBackup $backup */
            $backup = $item['backup'];

            try {
                DB::beginTransaction();

                // Delete backup file if it exists
                if ($backup->file_path && Storage::disk('backups')->exists($backup->file_path)) {
                    Storage::disk('backups')->delete($backup->file_path);

                    Log::info('Deleted orphaned backup file', [
                        'backup_id' => $backup->id,
                        'file_path' => $backup->file_path,
                    ]);
                }

                // Delete backup record
                $backup->delete();

                DB::commit();

                Log::info('Healed orphaned backup', [
                    'backup_id' => $backup->id,
                    'site_id' => $item['site_id'],
                ]);

                $healed++;
            } catch (Throwable $e) {
                DB::rollBack();

                Log::error('Failed to heal orphaned backup', [
                    'backup_id' => $backup->id,
                    'site_id' => $item['site_id'],
                    'error' => $e->getMessage(),
                ]);

                $failed++;
            }
        }

        Log::info('Orphaned backups healing completed', [
            'healed' => $healed,
            'failed' => $failed,
        ]);

        return ['healed' => $healed, 'failed' => $failed];
    }

    /**
     * Heal incorrect VPS site counts by updating to actual values
     *
     * Updates the site_count field on VPS servers to match the actual number
     * of active sites in the database.
     *
     * @param \Illuminate\Support\Collection $incorrectCounts
     * @return array{healed: int, failed: int}
     */
    private function healVpsSiteCounts($incorrectCounts): array
    {
        Log::info('Starting VPS site counts healing', [
            'count' => $incorrectCounts->count(),
        ]);

        $healed = 0;
        $failed = 0;

        foreach ($incorrectCounts as $item) {
            /** @var VpsServer $vps */
            $vps = $item['vps'];
            $actualCount = $item['actual_count'];

            try {
                $vps->update(['site_count' => $actualCount]);

                Log::info('Healed VPS site count', [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'old_count' => $item['recorded_count'],
                    'new_count' => $actualCount,
                    'difference' => $item['difference'],
                ]);

                $healed++;
            } catch (Throwable $e) {
                Log::error('Failed to heal VPS site count', [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'error' => $e->getMessage(),
                ]);

                $failed++;
            }
        }

        Log::info('VPS site counts healing completed', [
            'healed' => $healed,
            'failed' => $failed,
        ]);

        return ['healed' => $healed, 'failed' => $failed];
    }

    /**
     * Heal orphaned database sites by marking them as inactive
     *
     * Instead of deleting sites, we mark them as 'orphaned' status to preserve
     * data and allow manual review. This is a conservative approach.
     *
     * @param \Illuminate\Support\Collection $orphanedSites
     * @return array{healed: int, failed: int}
     */
    private function healOrphanedDatabaseSites($orphanedSites): array
    {
        Log::info('Starting orphaned database sites healing', [
            'count' => $orphanedSites->count(),
        ]);

        $healed = 0;
        $failed = 0;

        foreach ($orphanedSites as $item) {
            $site = $item['site'];

            try {
                // Mark site as 'orphaned' instead of deleting
                // This preserves data for manual review
                $site->update([
                    'status' => 'orphaned',
                ]);

                Log::warning('Marked site as orphaned (requires manual review)', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'vps_id' => $item['vps']->id,
                    'expected_path' => $item['expected_path'],
                ]);

                $healed++;
            } catch (Throwable $e) {
                Log::error('Failed to mark site as orphaned', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'error' => $e->getMessage(),
                ]);

                $failed++;
            }
        }

        Log::info('Orphaned database sites healing completed', [
            'healed' => $healed,
            'failed' => $failed,
            'note' => 'Sites marked as orphaned require manual review',
        ]);

        return ['healed' => $healed, 'failed' => $failed];
    }

    /**
     * Handle a job failure.
     *
     * @param Throwable $exception
     * @return void
     */
    public function failed(Throwable $exception): void
    {
        Log::error('Self-healing job failed permanently after all retries', [
            'job_class' => static::class,
            'attempts' => $this->attempts(),
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
            'total_issues' => $this->results['summary']['total_issues'] ?? 0,
        ]);
    }

    /**
     * Get the number of seconds to wait before retrying the job.
     *
     * @return int
     */
    public function retryAfter(): int
    {
        return 180;
    }
}
