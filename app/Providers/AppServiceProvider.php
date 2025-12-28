<?php

namespace App\Providers;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Policies\BackupPolicy;
use App\Policies\SitePolicy;
use App\Policies\TeamPolicy;
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
        //
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
    }

    /**
     * Configure the rate limiters for the application.
     */
    protected function configureRateLimiting(): void
    {
        // Strict rate limiting for authentication endpoints (login, register)
        // 5 requests per minute to prevent brute force attacks
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

        // Standard API rate limiting for authenticated routes
        // 60 requests per minute per user
        RateLimiter::for('api', function (Request $request) {
            return Limit::perMinute(60)
                ->by($request->user()?->id ?: $request->ip())
                ->response(function (Request $request, array $headers) {
                    return response()->json([
                        'success' => false,
                        'error' => [
                            'code' => 'RATE_LIMIT_EXCEEDED',
                            'message' => 'Too many requests. Please slow down.',
                            'retry_after' => $headers['Retry-After'] ?? 60,
                        ],
                    ], 429, $headers);
                });
        });

        // Stricter rate limiting for sensitive operations (backups, deletions)
        // 10 requests per minute
        RateLimiter::for('sensitive', function (Request $request) {
            return Limit::perMinute(10)
                ->by($request->user()?->id ?: $request->ip())
                ->response(function (Request $request, array $headers) {
                    return response()->json([
                        'success' => false,
                        'error' => [
                            'code' => 'RATE_LIMIT_EXCEEDED',
                            'message' => 'Too many requests for this operation. Please wait.',
                            'retry_after' => $headers['Retry-After'] ?? 60,
                        ],
                    ], 429, $headers);
                });
        });
    }
}
