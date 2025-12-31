<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        then: function () {
            Route::middleware('api')
                ->prefix('')
                ->group(base_path('routes/health.php'));
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Exclude Stripe webhook from CSRF verification
        $middleware->validateCsrfTokens(except: [
            'stripe/webhook',
        ]);

        // PERFORMANCE: Monitor request performance and log slow requests
        // Adds X-Response-Time header and logs requests over 1 second
        $middleware->append(\App\Http\Middleware\PerformanceMonitoring::class);

        // SECURITY: Apply security headers to all responses
        // This protects against XSS, clickjacking, MIME sniffing, and other attacks
        $middleware->append(\App\Http\Middleware\SecurityHeaders::class);

        // SECURITY: Audit all security-relevant events for compliance and threat detection
        // Logs authentication, authorization, and sensitive operations
        $middleware->append(\App\Http\Middleware\AuditSecurityEvents::class);

        // SECURITY: Register token rotation middleware for API routes
        // This ensures tokens are automatically rotated before expiration
        $middleware->api(append: [
            \App\Http\Middleware\RotateTokenMiddleware::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
