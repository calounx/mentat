<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure;

use App\Modules\Infrastructure\Contracts\NotificationInterface;
use App\Modules\Infrastructure\Contracts\ObservabilityInterface;
use App\Modules\Infrastructure\Contracts\StorageInterface;
use App\Modules\Infrastructure\Contracts\VpsProviderInterface;
use App\Modules\Infrastructure\Services\NotificationService;
use App\Modules\Infrastructure\Services\ObservabilityService;
use App\Modules\Infrastructure\Services\StorageService;
use App\Modules\Infrastructure\Services\VpsManager;
use Illuminate\Support\ServiceProvider;

/**
 * Infrastructure Services Module Service Provider
 *
 * Handles VPS server management, observability, notifications,
 * and storage operations.
 *
 * This module is responsible for:
 * - VPS server provisioning and management
 * - Observability (monitoring, logging, metrics)
 * - Notification delivery (email, slack, etc.)
 * - Storage management and file operations
 */
class InfrastructureServiceProvider extends ServiceProvider
{
    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        // Register VPS provider
        $this->app->singleton(
            VpsProviderInterface::class,
            VpsManager::class
        );

        // Register observability service
        $this->app->singleton(
            ObservabilityInterface::class,
            ObservabilityService::class
        );

        // Register notification service
        $this->app->singleton(
            NotificationInterface::class,
            NotificationService::class
        );

        // Register storage service
        $this->app->singleton(
            StorageInterface::class,
            StorageService::class
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
    }
}
