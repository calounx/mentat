<?php

namespace App\Providers;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Policies\BackupPolicy;
use App\Policies\SitePolicy;
use App\Policies\TeamPolicy;
use App\Services\VPS\VpsConnectionPool;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // Register VPS Connection Pool as singleton for connection reuse
        $this->app->singleton(VpsConnectionPool::class, function ($app) {
            return new VpsConnectionPool;
        });

        // Bind VPS Manager interface to implementation
        $this->app->bind(
            \App\Contracts\VpsManagerInterface::class,
            \App\Services\Integration\VPSManagerBridge::class
        );

        // Bind Observability interface to implementation
        $this->app->bind(
            \App\Contracts\ObservabilityInterface::class,
            \App\Services\Integration\ObservabilityAdapter::class
        );

        // Register service layer classes
        // These will be auto-resolved via constructor injection
        $this->app->bind(\App\Services\Sites\SiteQuotaService::class);
        $this->app->bind(\App\Services\Sites\SiteCreationService::class);
        $this->app->bind(\App\Services\Sites\SiteManagementService::class);
        $this->app->bind(\App\Services\Backup\BackupService::class);
        $this->app->bind(\App\Services\Backup\BackupRestoreService::class);
        $this->app->bind(\App\Services\Team\TeamMemberService::class);
        $this->app->bind(\App\Services\Team\InvitationService::class);
        $this->app->bind(\App\Services\Team\OwnershipTransferService::class);
        $this->app->bind(\App\Services\VPS\VpsAllocationService::class);
        $this->app->bind(\App\Services\VPS\VpsHealthService::class);
        $this->app->bind(\App\Services\Tenant\TenantService::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->configureRateLimiting();
        $this->registerPolicies();
    }

    /**
     * Register authorization policies.
     */
    protected function registerPolicies(): void
    {
        // Register model policies
        Gate::policy(Site::class, SitePolicy::class);
        Gate::policy(SiteBackup::class, BackupPolicy::class);

        // Team policy uses User model for member operations
        Gate::define('team.viewAny', [TeamPolicy::class, 'viewAny']);
        Gate::define('team.invite', [TeamPolicy::class, 'invite']);
        Gate::define('team.update', [TeamPolicy::class, 'update']);
        Gate::define('team.remove', [TeamPolicy::class, 'remove']);

        // Admin access gate
        Gate::define('admin', function ($user) {
            return in_array($user->role, ['admin', 'owner']);
        });
    }

    /**
     * Configure the rate limiters for the application.
     *
     * SECURITY: Tier-Based Rate Limiting
     * Implements adaptive rate limiting based on subscription tier and user behavior.
     * Higher tiers get higher rate limits as a service feature.
     *
     * OWASP Reference: A04:2021 – Insecure Design
     * - Rate limiting prevents DoS, brute force, and resource exhaustion
     * - Per-user limits prevent abuse by single actors
     * - Tier-based limits provide fair resource allocation
     */
    protected function configureRateLimiting(): void
    {
        // SECURITY: Strict rate limiting for authentication endpoints
        // 5 requests per minute per IP to prevent brute force attacks
        RateLimiter::for('auth', function (Request $request) {
            return Limit::perMinute(5)
                ->by($request->ip())
                ->response(function (Request $request, array $headers) {
                    return response()->json([
                        'success' => false,
                        'error' => [
                            'code' => 'RATE_LIMIT_EXCEEDED',
                            'message' => 'Too many authentication attempts. Please try again later.',
                            'retry_after' => $headers['Retry-After'] ?? 60,
                        ],
                    ], 429, $headers);
                });
        });

        // SECURITY: Tier-based API rate limiting for authenticated routes
        // Different limits per subscription tier (enterprise > professional > starter > free)
        RateLimiter::for('api', function (Request $request) {
            $user = $request->user();

            // Unauthenticated requests: 60/min by IP
            if (! $user) {
                return Limit::perMinute(60)->by($request->ip());
            }

            // Get subscription tier
            $tier = $user->organization->subscription->tier ?? 'free';

            // Tier-based rate limits
            $limit = match ($tier) {
                'enterprise' => Limit::perMinute(1000)->by($user->id),
                'professional' => Limit::perMinute(500)->by($user->id),
                'starter' => Limit::perMinute(100)->by($user->id),
                default => Limit::perMinute(60)->by($user->id),
            };

            return $limit->response(function (Request $request, array $headers) use ($tier) {
                return response()->json([
                    'success' => false,
                    'error' => [
                        'code' => 'RATE_LIMIT_EXCEEDED',
                        'message' => 'API rate limit exceeded for your tier.',
                        'retry_after' => $headers['Retry-After'] ?? 60,
                        'current_tier' => $tier,
                        'upgrade_info' => 'Upgrade your subscription for higher rate limits.',
                    ],
                ], 429, $headers);
            });
        });

        // SECURITY: Stricter rate limiting for sensitive operations
        // 10 requests per minute regardless of tier
        RateLimiter::for('sensitive', function (Request $request) {
            return Limit::perMinute(10)
                ->by($request->user()?->id ?: $request->ip())
                ->response(function (Request $request, array $headers) {
                    return response()->json([
                        'success' => false,
                        'error' => [
                            'code' => 'RATE_LIMIT_EXCEEDED',
                            'message' => 'Too many requests for this sensitive operation. Please wait.',
                            'retry_after' => $headers['Retry-After'] ?? 60,
                        ],
                    ], 429, $headers);
                });
        });

        // SECURITY: 2FA verification rate limiting
        // 5 attempts per minute to prevent brute force of 2FA codes
        RateLimiter::for('2fa', function (Request $request) {
            return Limit::perMinute(5)
                ->by($request->user()?->id ?: $request->ip())
                ->response(function (Request $request, array $headers) {
                    return response()->json([
                        'success' => false,
                        'error' => [
                            'code' => 'RATE_LIMIT_EXCEEDED',
                            'message' => 'Too many 2FA verification attempts. Please wait.',
                            'retry_after' => $headers['Retry-After'] ?? 60,
                        ],
                    ], 429, $headers);
                });
        });
    }
}
