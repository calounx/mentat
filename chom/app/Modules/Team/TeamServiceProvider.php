<?php

declare(strict_types=1);

namespace App\Modules\Team;

use App\Modules\Team\Contracts\InvitationInterface;
use App\Modules\Team\Services\TeamOrchestrator;
use App\Modules\Team\Services\InvitationService;
use Illuminate\Support\ServiceProvider;

/**
 * Team Collaboration Module Service Provider
 *
 * Handles team member management, invitations, roles and permissions,
 * and ownership transfer operations.
 *
 * This module is responsible for:
 * - Team member invitation and onboarding
 * - Role and permission management
 * - Team member removal
 * - Ownership transfer
 * - Collaboration access control
 */
class TeamServiceProvider extends ServiceProvider
{
    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        // Register team orchestrator
        $this->app->singleton(TeamOrchestrator::class);

        // Register invitation service
        $this->app->singleton(
            InvitationInterface::class,
            InvitationService::class
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
