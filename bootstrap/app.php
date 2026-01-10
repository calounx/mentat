<?php

use App\Http\Middleware\CheckPlanSelection;
use App\Http\Middleware\CheckUserApprovalStatus;
use App\Http\Middleware\EnsureHasTenant;
use App\Http\Middleware\EnsureSuperAdmin;
use App\Http\Middleware\EnsureUserIsAdmin;
use App\Http\Middleware\RequestCorrelationId;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Add correlation ID tracking to all requests
        $middleware->append(RequestCorrelationId::class);

        // Exclude Stripe webhook from CSRF verification
        $middleware->validateCsrfTokens(except: [
            'stripe/webhook',
        ]);

        // Register middleware aliases
        $middleware->alias([
            'admin' => EnsureUserIsAdmin::class,
            'super-admin' => EnsureSuperAdmin::class,
            'has-tenant' => EnsureHasTenant::class,
            'approved' => CheckUserApprovalStatus::class,
            'plan-selected' => CheckPlanSelection::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
