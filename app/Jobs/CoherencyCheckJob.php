<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Services\HealthCheckService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Coherency Check Job
 *
 * Queue-based job that performs system health checks to detect incoherencies
 * between database state and actual VPS disk state.
 *
 * Runs periodically via scheduler to ensure system consistency.
 *
 * @package App\Jobs
 */
class CoherencyCheckJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * Number of times the job may be attempted.
     *
     * @var int
     */
    public int $tries = 3;

    /**
     * Job timeout in seconds (15 minutes for full checks).
     *
     * @var int
     */
    public int $timeout = 900;

    /**
     * Exponential backoff delays in seconds.
     *
     * @var array<int>
     */
    public array $backoff = [120, 300, 600];

    /**
     * Create a new job instance.
     *
     * @param bool $quickCheck If true, performs only lightweight database checks
     * @param bool $autoHeal If true, dispatches self-healing jobs for detected issues
     */
    public function __construct(
        private readonly bool $quickCheck = false,
        private readonly bool $autoHeal = false
    ) {
    }

    /**
     * Execute the job.
     *
     * @param HealthCheckService $healthCheckService
     * @return void
     */
    public function handle(HealthCheckService $healthCheckService): void
    {
        $startTime = microtime(true);

        Log::info('Coherency check job started', [
            'job_id' => $this->job?->getJobId(),
            'quick_check' => $this->quickCheck,
            'auto_heal' => $this->autoHeal,
            'attempt' => $this->attempts(),
        ]);

        try {
            // Perform health check
            $results = $healthCheckService->detectIncoherencies($this->quickCheck);

            $executionTime = round((microtime(true) - $startTime) * 1000, 2);

            // Log results summary
            $this->logResults($results, $executionTime);

            // Dispatch self-healing jobs if enabled and issues found
            if ($this->autoHeal && $results['summary']['total_issues'] > 0) {
                $this->dispatchSelfHealing($results);
            }

            Log::info('Coherency check job completed successfully', [
                'job_id' => $this->job?->getJobId(),
                'execution_time_ms' => $executionTime,
                'total_issues' => $results['summary']['total_issues'],
                'auto_heal_dispatched' => $this->autoHeal && $results['summary']['total_issues'] > 0,
            ]);
        } catch (Throwable $e) {
            $executionTime = round((microtime(true) - $startTime) * 1000, 2);

            Log::error('Coherency check job failed', [
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
     * Log detailed results from the health check
     *
     * @param array $results Health check results
     * @param float $executionTime Execution time in milliseconds
     * @return void
     */
    private function logResults(array $results, float $executionTime): void
    {
        $summary = $results['summary'];

        if ($summary['total_issues'] === 0) {
            Log::info('Coherency check: No issues found', [
                'check_type' => $summary['check_type'],
                'execution_time_ms' => $executionTime,
            ]);

            return;
        }

        Log::warning('Coherency check: Issues detected', [
            'check_type' => $summary['check_type'],
            'total_issues' => $summary['total_issues'],
            'execution_time_ms' => $executionTime,
            'breakdown' => [
                'orphaned_database_sites' => $summary['orphaned_database_sites_count'],
                'orphaned_disk_sites' => $summary['orphaned_disk_sites_count'],
                'orphaned_backups' => $summary['orphaned_backups_count'],
                'incorrect_vps_counts' => $summary['incorrect_vps_counts_count'],
                'ssl_expiring_soon' => $summary['ssl_expiring_soon_count'],
            ],
        ]);

        // Log detailed issue information
        if ($results['orphaned_database_sites']->isNotEmpty()) {
            Log::warning('Orphaned database sites details', [
                'count' => $results['orphaned_database_sites']->count(),
                'sites' => $results['orphaned_database_sites']->map(function ($item) {
                    return [
                        'site_id' => $item['site']->id,
                        'domain' => $item['site']->domain,
                        'vps_id' => $item['vps']->id,
                        'expected_path' => $item['expected_path'],
                    ];
                })->toArray(),
            ]);
        }

        if ($results['orphaned_disk_sites']->isNotEmpty()) {
            Log::warning('Orphaned disk sites details', [
                'count' => $results['orphaned_disk_sites']->count(),
                'sites' => $results['orphaned_disk_sites']->map(function ($item) {
                    return [
                        'vps_id' => $item['vps']->id,
                        'domain' => $item['domain'],
                        'path' => $item['path'],
                    ];
                })->toArray(),
            ]);
        }

        if ($results['orphaned_backups']->isNotEmpty()) {
            Log::warning('Orphaned backups details', [
                'count' => $results['orphaned_backups']->count(),
                'backups' => $results['orphaned_backups']->map(function ($item) {
                    return [
                        'backup_id' => $item['backup']->id,
                        'site_id' => $item['site_id'],
                        'created_at' => $item['backup']->created_at?->toIso8601String(),
                    ];
                })->take(10)->toArray(), // Limit to first 10
            ]);
        }

        if ($results['incorrect_vps_counts']->isNotEmpty()) {
            Log::warning('Incorrect VPS site counts details', [
                'count' => $results['incorrect_vps_counts']->count(),
                'vpss' => $results['incorrect_vps_counts']->map(function ($item) {
                    return [
                        'vps_id' => $item['vps']->id,
                        'hostname' => $item['vps']->hostname,
                        'recorded_count' => $item['recorded_count'],
                        'actual_count' => $item['actual_count'],
                        'difference' => $item['difference'],
                    ];
                })->toArray(),
            ]);
        }

        if ($results['ssl_expiring_soon']->isNotEmpty()) {
            Log::warning('SSL certificates expiring soon details', [
                'count' => $results['ssl_expiring_soon']->count(),
                'sites' => $results['ssl_expiring_soon']->map(function ($item) {
                    return [
                        'site_id' => $item['site']->id,
                        'domain' => $item['site']->domain,
                        'days_until_expiry' => $item['days_until_expiry'],
                        'expires_at' => $item['site']->ssl_expires_at?->toIso8601String(),
                    ];
                })->toArray(),
            ]);
        }
    }

    /**
     * Dispatch self-healing jobs for detected issues
     *
     * @param array $results Health check results
     * @return void
     */
    private function dispatchSelfHealing(array $results): void
    {
        Log::info('Dispatching self-healing jobs', [
            'total_issues' => $results['summary']['total_issues'],
        ]);

        try {
            // Dispatch self-healing job with the results
            SelfHealingJob::dispatch($results);

            Log::info('Self-healing job dispatched successfully');
        } catch (Throwable $e) {
            Log::error('Failed to dispatch self-healing job', [
                'exception' => get_class($e),
                'message' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Handle a job failure.
     *
     * @param Throwable $exception
     * @return void
     */
    public function failed(Throwable $exception): void
    {
        Log::error('Coherency check job failed permanently after all retries', [
            'job_class' => static::class,
            'attempts' => $this->attempts(),
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
            'quick_check' => $this->quickCheck,
            'auto_heal' => $this->autoHeal,
        ]);
    }

    /**
     * Get the number of seconds to wait before retrying the job.
     *
     * @return int
     */
    public function retryAfter(): int
    {
        return 120;
    }
}
