<?php

use App\Jobs\CheckSslRenewalJob;
use App\Jobs\OptimizeDatabasesJob;
use App\Jobs\VpsHealthCheckJob;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

/*
|--------------------------------------------------------------------------
| Scheduled Jobs
|--------------------------------------------------------------------------
|
| These scheduled jobs handle automated VPS maintenance tasks including
| SSL certificate renewals, health monitoring, and database optimization.
|
*/

// SSL Renewal Check - Daily at 2:00 AM
// Checks all sites with SSL enabled and renews certificates expiring within 14 days
Schedule::job(new CheckSslRenewalJob())
    ->daily()
    ->at('02:00')
    ->name('ssl-renewal-check')
    ->withoutOverlapping()
    ->onOneServer();

// VPS Health Check - Hourly
// Monitors all active VPS servers and updates their health status
Schedule::job(new VpsHealthCheckJob())
    ->hourly()
    ->name('vps-health-check')
    ->withoutOverlapping()
    ->onOneServer();

// Database Optimization - Weekly on Sundays at 3:00 AM
// Optimizes databases for all active sites to maintain performance
Schedule::job(new OptimizeDatabasesJob())
    ->weeklyOn(0, '03:00') // Sunday at 3:00 AM
    ->name('database-optimization')
    ->withoutOverlapping()
    ->onOneServer();
