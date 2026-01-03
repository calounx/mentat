<?php

declare(strict_types=1);

namespace App\Modules\Backup;

use App\Modules\Backup\Contracts\BackupStorageInterface;
use App\Modules\Backup\Services\BackupOrchestrator;
use App\Modules\Backup\Services\BackupStorageService;
use Illuminate\Support\ServiceProvider;

/**
 * Backup Module Service Provider
 *
 * Handles backup creation, restoration, scheduling, retention policies,
 * and integrity validation.
 *
 * This module is responsible for:
 * - Backup creation and restoration
 * - Backup scheduling and automation
 * - Retention policy enforcement
 * - Backup integrity validation
 * - Backup storage management
 */
class BackupServiceProvider extends ServiceProvider
{
    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        // Register backup orchestrator
        $this->app->singleton(BackupOrchestrator::class);

        // Register backup storage service
        $this->app->singleton(
            BackupStorageInterface::class,
            BackupStorageService::class
        );
    }

    /**
     * Bootstrap module services.
     *
     * @return void
     */
    public function boot(): void
    {
        // Module-specific bootstrapping
        // Event listeners are registered in individual services
    }
}
