<?php

declare(strict_types=1);

namespace App\Providers;

use App\Modules\Auth\AuthServiceProvider;
use App\Modules\Backup\BackupServiceProvider;
use App\Modules\Infrastructure\InfrastructureServiceProvider;
use App\Modules\SiteHosting\SiteHostingServiceProvider;
use App\Modules\Team\TeamServiceProvider;
use App\Modules\Tenancy\TenancyServiceProvider;
use Illuminate\Support\ServiceProvider;

/**
 * Module Service Provider
 *
 * Central registration point for all CHOM application modules.
 * This provider loads all bounded context service providers
 * following Domain-Driven Design principles.
 */
class ModuleServiceProvider extends ServiceProvider
{
    /**
     * All module service providers.
     *
     * @var array
     */
    protected array $moduleProviders = [
        // Identity & Access Module
        AuthServiceProvider::class,

        // Multi-Tenancy Module
        TenancyServiceProvider::class,

        // Site Hosting Module
        SiteHostingServiceProvider::class,

        // Backup Module
        BackupServiceProvider::class,

        // Team Collaboration Module
        TeamServiceProvider::class,

        // Infrastructure Services Module
        InfrastructureServiceProvider::class,
    ];

    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        foreach ($this->moduleProviders as $provider) {
            $this->app->register($provider);
        }
    }

    /**
     * Bootstrap module services.
     *
     * @return void
     */
    public function boot(): void
    {
        // Module bootstrapping is handled by individual providers
    }
}
