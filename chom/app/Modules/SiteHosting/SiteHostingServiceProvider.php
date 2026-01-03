<?php

declare(strict_types=1);

namespace App\Modules\SiteHosting;

use App\Modules\SiteHosting\Contracts\SiteProvisionerInterface;
use App\Modules\SiteHosting\Services\SiteProvisioningService;
use App\Policies\SitePolicy;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

/**
 * Site Hosting Module Service Provider
 *
 * Handles site provisioning, management, PHP version control,
 * SSL certificate management, and site metrics.
 *
 * This module is responsible for:
 * - Site provisioning and deployment
 * - PHP version management
 * - SSL certificate management
 * - Site lifecycle (enable/disable/delete)
 * - Site metrics and monitoring
 */
class SiteHostingServiceProvider extends ServiceProvider
{
    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        // Register site provisioner
        $this->app->singleton(
            SiteProvisionerInterface::class,
            SiteProvisioningService::class
        );
    }

    /**
     * Bootstrap module services.
     *
     * @return void
     */
    public function boot(): void
    {
        // Register policies
        Gate::policy(\App\Models\Site::class, SitePolicy::class);

        // Event listeners are registered in the service
        // to maintain module encapsulation
    }
}
