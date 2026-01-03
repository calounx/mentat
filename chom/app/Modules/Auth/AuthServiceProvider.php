<?php

declare(strict_types=1);

namespace App\Modules\Auth;

use App\Modules\Auth\Contracts\AuthenticationInterface;
use App\Modules\Auth\Contracts\TwoFactorInterface;
use App\Modules\Auth\Events\UserAuthenticated;
use App\Modules\Auth\Events\UserLoggedOut;
use App\Modules\Auth\Events\TwoFactorEnabled;
use App\Modules\Auth\Events\TwoFactorDisabled;
use App\Modules\Auth\Listeners\LogAuthenticationAttempt;
use App\Modules\Auth\Listeners\NotifyTwoFactorChange;
use App\Modules\Auth\Services\AuthenticationService;
use App\Modules\Auth\Services\TwoFactorService;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;

/**
 * Identity & Access Module Service Provider
 *
 * Handles user authentication, authorization, two-factor authentication,
 * and session management within the CHOM application.
 *
 * This module is responsible for:
 * - User authentication and login flows
 * - Two-factor authentication (2FA)
 * - Password management and reset
 * - Session management and security
 */
class AuthServiceProvider extends ServiceProvider
{
    /**
     * Register module services.
     *
     * @return void
     */
    public function register(): void
    {
        // Register authentication service
        $this->app->singleton(
            AuthenticationInterface::class,
            AuthenticationService::class
        );

        // Register two-factor authentication service
        $this->app->singleton(
            TwoFactorInterface::class,
            TwoFactorService::class
        );
    }

    /**
     * Bootstrap module services.
     *
     * @return void
     */
    public function boot(): void
    {
        // Register event listeners
        Event::listen(UserAuthenticated::class, LogAuthenticationAttempt::class);
        Event::listen(UserLoggedOut::class, LogAuthenticationAttempt::class);
        Event::listen(TwoFactorEnabled::class, NotifyTwoFactorChange::class);
        Event::listen(TwoFactorDisabled::class, NotifyTwoFactorChange::class);
    }
}
