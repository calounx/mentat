<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Jobs\SelfHealingJob;
use App\Services\HealthCheckService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Symfony\Component\Console\Helper\Table;
use Symfony\Component\Console\Helper\TableSeparator;

/**
 * Health Check Command
 *
 * CLI command for running system health checks and detecting incoherencies.
 * Supports various modes: full check, quick check, report only, and auto-fix.
 *
 * @package App\Console\Commands
 */
class HealthCheckCommand extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'health:check
                            {--full : Run full health check including disk scans (default)}
                            {--quick : Run quick health check (database-only, no disk scans)}
                            {--report : Generate detailed report without fixing issues}
                            {--fix : Automatically fix detected issues using self-healing}
                            {--json : Output results in JSON format}';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Check system health and detect incoherencies between database and disk state';

    /**
     * Execute the console command.
     *
     * @param HealthCheckService $healthCheckService
     * @return int
     */
    public function handle(HealthCheckService $healthCheckService): int
    {
        $startTime = microtime(true);

        // Determine check type
        $quickCheck = $this->option('quick');
        $reportOnly = $this->option('report');
        $autoFix = $this->option('fix');
        $jsonOutput = $this->option('json');

        $checkType = $quickCheck ? 'quick' : 'full';

        if (!$jsonOutput) {
            $this->info("Running {$checkType} health check...");
            $this->newLine();
        }

        try {
            // Perform health check
            $results = $healthCheckService->detectIncoherencies($quickCheck);
            $executionTime = round((microtime(true) - $startTime) * 1000, 2);

            // Output results
            if ($jsonOutput) {
                $this->outputJson($results, $executionTime);
            } else {
                $this->outputFormatted($results, $executionTime, $checkType);
            }

            // Apply fixes if requested and issues found
            if ($autoFix && $results['summary']['total_issues'] > 0) {
                $this->applyFixes($results);
            } elseif ($results['summary']['total_issues'] > 0 && !$reportOnly && !$jsonOutput) {
                $this->newLine();
                $this->warn('Issues detected. Run with --fix to automatically resolve them.');
                $this->info('Or use --report for a detailed report.');
            }

            Log::info('Health check command completed', [
                'check_type' => $checkType,
                'total_issues' => $results['summary']['total_issues'],
                'execution_time_ms' => $executionTime,
                'auto_fix' => $autoFix,
            ]);

            // Return exit code based on issues found
            return $results['summary']['total_issues'] > 0 ? self::FAILURE : self::SUCCESS;
        } catch (\Exception $e) {
            if ($jsonOutput) {
                $this->error(json_encode([
                    'error' => true,
                    'message' => $e->getMessage(),
                ], JSON_THROW_ON_ERROR));
            } else {
                $this->error('Health check failed: ' . $e->getMessage());
            }

            Log::error('Health check command failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return self::FAILURE;
        }
    }

    /**
     * Output results in JSON format
     *
     * @param array $results Health check results
     * @param float $executionTime Execution time in milliseconds
     * @return void
     */
    private function outputJson(array $results, float $executionTime): void
    {
        $output = [
            'status' => $results['summary']['total_issues'] === 0 ? 'healthy' : 'issues_detected',
            'timestamp' => now()->toIso8601String(),
            'execution_time_ms' => $executionTime,
            'summary' => $results['summary'],
            'issues' => [
                'orphaned_database_sites' => $results['orphaned_database_sites']->map(function ($item) {
                    return [
                        'site_id' => $item['site']->id,
                        'domain' => $item['site']->domain,
                        'vps_id' => $item['vps']->id,
                        'vps_hostname' => $item['vps']->hostname,
                        'expected_path' => $item['expected_path'],
                    ];
                })->values()->toArray(),
                'orphaned_disk_sites' => $results['orphaned_disk_sites']->map(function ($item) {
                    return [
                        'vps_id' => $item['vps']->id,
                        'vps_hostname' => $item['vps']->hostname,
                        'domain' => $item['domain'],
                        'path' => $item['path'],
                    ];
                })->values()->toArray(),
                'orphaned_backups' => $results['orphaned_backups']->map(function ($item) {
                    return [
                        'backup_id' => $item['backup']->id,
                        'site_id' => $item['site_id'],
                        'created_at' => $item['backup']->created_at?->toIso8601String(),
                    ];
                })->values()->toArray(),
                'incorrect_vps_counts' => $results['incorrect_vps_counts']->map(function ($item) {
                    return [
                        'vps_id' => $item['vps']->id,
                        'hostname' => $item['vps']->hostname,
                        'recorded_count' => $item['recorded_count'],
                        'actual_count' => $item['actual_count'],
                        'difference' => $item['difference'],
                    ];
                })->values()->toArray(),
                'ssl_expiring_soon' => $results['ssl_expiring_soon']->map(function ($item) {
                    return [
                        'site_id' => $item['site']->id,
                        'domain' => $item['site']->domain,
                        'days_until_expiry' => $item['days_until_expiry'],
                        'expires_at' => $item['site']->ssl_expires_at?->toIso8601String(),
                    ];
                })->values()->toArray(),
            ],
        ];

        $this->line(json_encode($output, JSON_THROW_ON_ERROR | JSON_PRETTY_PRINT));
    }

    /**
     * Output results in formatted console output
     *
     * @param array $results Health check results
     * @param float $executionTime Execution time in milliseconds
     * @param string $checkType Type of check performed
     * @return void
     */
    private function outputFormatted(array $results, float $executionTime, string $checkType): void
    {
        $summary = $results['summary'];

        // Display summary
        $this->displaySummary($summary, $executionTime, $checkType);
        $this->newLine();

        // Display detailed results for each issue type
        if ($summary['total_issues'] > 0) {
            if ($results['orphaned_database_sites']->isNotEmpty()) {
                $this->displayOrphanedDatabaseSites($results['orphaned_database_sites']);
                $this->newLine();
            }

            if ($results['orphaned_disk_sites']->isNotEmpty()) {
                $this->displayOrphanedDiskSites($results['orphaned_disk_sites']);
                $this->newLine();
            }

            if ($results['orphaned_backups']->isNotEmpty()) {
                $this->displayOrphanedBackups($results['orphaned_backups']);
                $this->newLine();
            }

            if ($results['incorrect_vps_counts']->isNotEmpty()) {
                $this->displayIncorrectVpsCounts($results['incorrect_vps_counts']);
                $this->newLine();
            }

            if ($results['ssl_expiring_soon']->isNotEmpty()) {
                $this->displaySslExpiringSoon($results['ssl_expiring_soon']);
                $this->newLine();
            }
        } else {
            $this->info('No issues detected. System is healthy!');
        }
    }

    /**
     * Display summary table
     *
     * @param array $summary Summary data
     * @param float $executionTime Execution time in milliseconds
     * @param string $checkType Type of check
     * @return void
     */
    private function displaySummary(array $summary, float $executionTime, string $checkType): void
    {
        $this->line('<options=bold>Health Check Summary</>');

        $table = new Table($this->output);
        $table->setHeaders(['Metric', 'Value']);
        $table->setRows([
            ['Check Type', strtoupper($checkType)],
            ['Total Issues', $summary['total_issues'] > 0 ? "<fg=red>{$summary['total_issues']}</>" : '<fg=green>0</>'],
            ['Orphaned DB Sites', $summary['orphaned_database_sites_count']],
            ['Orphaned Disk Sites', $summary['orphaned_disk_sites_count']],
            ['Orphaned Backups', $summary['orphaned_backups_count']],
            ['VPS Count Mismatches', $summary['incorrect_vps_counts_count']],
            ['SSL Expiring Soon', $summary['ssl_expiring_soon_count']],
            new TableSeparator(),
            ['Execution Time', round($executionTime, 2) . ' ms'],
            ['Timestamp', $summary['timestamp']],
        ]);
        $table->render();
    }

    /**
     * Display orphaned database sites table
     *
     * @param \Illuminate\Support\Collection $sites
     * @return void
     */
    private function displayOrphanedDatabaseSites($sites): void
    {
        $this->warn('Orphaned Database Sites (in DB but not on disk):');

        $table = new Table($this->output);
        $table->setHeaders(['Site ID', 'Domain', 'VPS', 'Expected Path']);

        foreach ($sites->take(20) as $item) {
            $table->addRow([
                substr($item['site']->id, 0, 8),
                $item['site']->domain,
                $item['vps']->hostname,
                $item['expected_path'],
            ]);
        }

        if ($sites->count() > 20) {
            $table->addRow(new TableSeparator());
            $table->addRow(['...', 'And ' . ($sites->count() - 20) . ' more', '', '']);
        }

        $table->render();
    }

    /**
     * Display orphaned disk sites table
     *
     * @param \Illuminate\Support\Collection $sites
     * @return void
     */
    private function displayOrphanedDiskSites($sites): void
    {
        $this->warn('Orphaned Disk Sites (on disk but not in DB):');

        $table = new Table($this->output);
        $table->setHeaders(['VPS', 'Domain', 'Path']);

        foreach ($sites->take(20) as $item) {
            $table->addRow([
                $item['vps']->hostname,
                $item['domain'],
                $item['path'],
            ]);
        }

        if ($sites->count() > 20) {
            $table->addRow(new TableSeparator());
            $table->addRow(['...', 'And ' . ($sites->count() - 20) . ' more', '']);
        }

        $table->render();
    }

    /**
     * Display orphaned backups table
     *
     * @param \Illuminate\Support\Collection $backups
     * @return void
     */
    private function displayOrphanedBackups($backups): void
    {
        $this->warn('Orphaned Backups (referencing deleted sites):');

        $table = new Table($this->output);
        $table->setHeaders(['Backup ID', 'Site ID', 'Created At']);

        foreach ($backups->take(20) as $item) {
            $table->addRow([
                substr($item['backup']->id, 0, 8),
                substr($item['site_id'], 0, 8),
                $item['backup']->created_at?->format('Y-m-d H:i'),
            ]);
        }

        if ($backups->count() > 20) {
            $table->addRow(new TableSeparator());
            $table->addRow(['...', 'And ' . ($backups->count() - 20) . ' more', '']);
        }

        $table->render();
    }

    /**
     * Display incorrect VPS counts table
     *
     * @param \Illuminate\Support\Collection $vpss
     * @return void
     */
    private function displayIncorrectVpsCounts($vpss): void
    {
        $this->warn('Incorrect VPS Site Counts:');

        $table = new Table($this->output);
        $table->setHeaders(['VPS', 'Recorded', 'Actual', 'Difference']);

        foreach ($vpss as $item) {
            $diff = $item['difference'];
            $diffStr = $diff > 0 ? "+{$diff}" : (string)$diff;

            $table->addRow([
                $item['vps']->hostname,
                $item['recorded_count'],
                $item['actual_count'],
                $diffStr,
            ]);
        }

        $table->render();
    }

    /**
     * Display SSL expiring soon table
     *
     * @param \Illuminate\Support\Collection $sites
     * @return void
     */
    private function displaySslExpiringSoon($sites): void
    {
        $this->warn('SSL Certificates Expiring Soon:');

        $table = new Table($this->output);
        $table->setHeaders(['Domain', 'Days Until Expiry', 'Expires At']);

        foreach ($sites as $item) {
            $days = $item['days_until_expiry'];
            $daysStr = $days <= 7 ? "<fg=red>{$days}</>" : ($days <= 14 ? "<fg=yellow>{$days}</>" : (string)$days);

            $table->addRow([
                $item['site']->domain,
                $daysStr,
                $item['site']->ssl_expires_at?->format('Y-m-d H:i'),
            ]);
        }

        $table->render();
    }

    /**
     * Apply fixes using self-healing job
     *
     * @param array $results Health check results
     * @return void
     */
    private function applyFixes(array $results): void
    {
        $this->newLine();
        $this->info('Applying automatic fixes...');

        try {
            // Dispatch self-healing job
            SelfHealingJob::dispatch($results);

            $this->info('Self-healing job dispatched successfully.');
            $this->info('Check logs for detailed healing results.');
        } catch (\Exception $e) {
            $this->error('Failed to dispatch self-healing job: ' . $e->getMessage());

            Log::error('Failed to dispatch self-healing job from command', [
                'error' => $e->getMessage(),
            ]);
        }
    }
}
