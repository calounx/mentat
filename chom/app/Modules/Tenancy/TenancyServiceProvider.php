<?php

declare(strict_types=1);

namespace App\Modules\Tenancy;

use App\Modules\Tenancy\Contracts\TenantResolverInterface;
use App\Modules\Tenancy\Events\OrganizationCreated;
use App\Modules\Tenancy\Events\TenantSwitched;
use App\Modules\Tenancy\Listeners\InitializeTenantContext;
use App\Modules\Tenancy\Listeners\LogTenantActivity;
use App\Modules\Tenancy\Middleware\EnforceTenantIsolation;
use App\Modules\Tenancy\Services\TenantService;
use Illuminate\Routing\Router;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;

/**
 * Multi-Tenancy Module Service Provider
 *
 * Handles multi-tenant operations including tenant resolution,
 * organization management, and data isolation enforcement.
 *
 * This module is responsible for:
 * - Tenant identification and resolution
 * - Organization lifecycle management
 * - Tenant isolation enforcement
 * - Tenant switching and context management
 */
class TenancyServiceProvider extends ServiceProvider
{
    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        // Register tenant resolver
        $this->app->singleton(
            TenantResolverInterface::class,
            TenantService::class
        );

        // Register tenant service alias
        $this->app->alias(TenantResolverInterface::class, 'tenant');
    }

    /**
     * Bootstrap module services.
     *
     * @return void
     */
    public function boot(): void
    {
        // Register middleware
        $router = $this->app->make(Router::class);
        $router->aliasMiddleware('tenant.isolation', EnforceTenantIsolation::class);

        // Register event listeners
        Event::listen(TenantSwitched::class, InitializeTenantContext::class);
        Event::listen(TenantSwitched::class, LogTenantActivity::class);
        Event::listen(OrganizationCreated::class, LogTenantActivity::class);
    }
}
