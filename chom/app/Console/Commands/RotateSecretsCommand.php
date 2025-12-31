<?php

namespace App\Console\Commands;

use App\Services\Secrets\SecretsRotationService;
use Illuminate\Console\Command;

/**
 * SECURITY: Manual Secrets Rotation Command
 *
 * Provides CLI interface for triggering secrets rotation on-demand or via cron.
 * Can rotate all due credentials or specific VPS servers.
 *
 * Usage:
 *   php artisan secrets:rotate --all        # Rotate all due credentials
 *   php artisan secrets:rotate --dry-run    # Check what needs rotation
 *   php artisan secrets:rotate --vps=123    # Rotate specific VPS
 *
 * Schedule (add to app/Console/Kernel.php):
 *   $schedule->command('secrets:rotate --all')->daily();
 */
class RotateSecretsCommand extends Command
{
    protected $signature = 'secrets:rotate
                            {--all : Rotate all VPS credentials that are due}
                            {--vps= : Rotate specific VPS server by ID}
                            {--dry-run : Show what needs rotation without executing}
                            {--force : Force rotation even if not due}';

    protected $description = 'Rotate SSH keys and other secrets for VPS servers';

    public function handle(SecretsRotationService $rotationService): int
    {
        $this->info('CHOM Security: Secrets Rotation');
        $this->info('===============================');
        $this->newLine();

        if ($this->option('dry-run')) {
            return $this->dryRun($rotationService);
        }

        if ($this->option('all')) {
            return $this->rotateAll($rotationService);
        }

        if ($vpsId = $this->option('vps')) {
            return $this->rotateSpecific($rotationService, $vpsId);
        }

        $this->error('Please specify --all or --vps=ID');
        return self::FAILURE;
    }

    protected function dryRun(SecretsRotationService $rotationService): int
    {
        $servers = $rotationService->getServersNeedingRotation();

        if ($servers->isEmpty()) {
            $this->info('✓ No VPS servers require key rotation at this time.');
            return self::SUCCESS;
        }

        $this->warn("Found {$servers->count()} VPS servers requiring key rotation:");
        $this->newLine();

        $this->table(
            ['ID', 'Name', 'IP', 'Last Rotation', 'Days Overdue'],
            $servers->map(function ($vps) {
                $daysOverdue = $vps->key_rotated_at
                    ? max(0, now()->diffInDays($vps->key_rotated_at) - 90)
                    : 'Never rotated';

                return [
                    $vps->id,
                    $vps->name,
                    $vps->ip,
                    $vps->key_rotated_at?->format('Y-m-d H:i') ?? 'Never',
                    $daysOverdue,
                ];
            })
        );

        $this->newLine();
        $this->info('Run with --all to rotate all due credentials.');

        return self::SUCCESS;
    }

    protected function rotateAll(SecretsRotationService $rotationService): int
    {
        $servers = $rotationService->getServersNeedingRotation();

        if ($servers->isEmpty()) {
            $this->info('✓ No VPS servers require key rotation.');
            return self::SUCCESS;
        }

        $this->warn("Rotating credentials for {$servers->count()} VPS servers...");
        $this->newLine();

        $bar = $this->output->createProgressBar($servers->count());
        $bar->start();

        $results = $rotationService->rotateAllDueCredentials();

        $bar->finish();
        $this->newLine(2);

        // Display results
        $this->info("Rotation Summary:");
        $this->info("  Total: {$results['total']}");
        $this->info("  ✓ Successful: {$results['successful']}");

        if ($results['failed'] > 0) {
            $this->error("  ✗ Failed: {$results['failed']}");
            $this->newLine();
            $this->error('Failed rotations:');
            foreach ($results['errors'] as $error) {
                $this->error("  - {$error['vps_name']} (ID: {$error['vps_id']}): {$error['error']}");
            }
            return self::FAILURE;
        }

        $this->newLine();
        $this->info('✓ All credential rotations completed successfully!');

        return self::SUCCESS;
    }

    protected function rotateSpecific(SecretsRotationService $rotationService, string $vpsId): int
    {
        $vps = \App\Models\VpsServer::find($vpsId);

        if (!$vps) {
            $this->error("VPS server with ID {$vpsId} not found.");
            return self::FAILURE;
        }

        $this->info("Rotating credentials for VPS: {$vps->name} ({$vps->ip})");

        if ($vps->key_rotated_at && !$this->option('force')) {
            $daysSince = now()->diffInDays($vps->key_rotated_at);
            if ($daysSince < 90) {
                $this->warn("Keys were rotated {$daysSince} days ago (policy: 90 days).");
                if (!$this->confirm('Rotate anyway?')) {
                    return self::SUCCESS;
                }
            }
        }

        try {
            $result = $rotationService->rotateVpsCredentials($vps);

            $this->newLine();
            $this->info('✓ Credentials rotated successfully!');
            $this->info("  Rotated at: {$result['rotated_at']}");
            $this->info("  Next rotation due: {$result['next_rotation_due']}");
            $this->info("  Overlap period ends: {$result['overlap_period_ends']}");

            return self::SUCCESS;

        } catch (\Exception $e) {
            $this->error("✗ Rotation failed: {$e->getMessage()}");
            return self::FAILURE;
        }
    }
}
