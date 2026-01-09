<?php

declare(strict_types=1);

use App\Jobs\CoherencyCheckJob;
use Illuminate\Support\Facades\Schedule;

/*
|--------------------------------------------------------------------------
| Console Routes
|--------------------------------------------------------------------------
|
| This file is where you may define all of your Closure based console
| commands and task scheduling. Each Closure is bound to a command instance
| allowing a simple approach to interacting with each command's IO methods.
|
*/

// Schedule full health check every hour with auto-healing
Schedule::job(new CoherencyCheckJob(quickCheck: false, autoHeal: true))
    ->hourly()
    ->name('coherency-check-full')
    ->withoutOverlapping(1800) // 30 minutes max overlap protection
    ->runInBackground()
    ->onSuccess(function () {
        Log::info('Scheduled full coherency check completed successfully');
    })
    ->onFailure(function () {
        Log::error('Scheduled full coherency check failed');
    });

// Schedule quick health check every 15 minutes (database-only, no disk scans)
Schedule::job(new CoherencyCheckJob(quickCheck: true, autoHeal: true))
    ->everyFifteenMinutes()
    ->name('coherency-check-quick')
    ->withoutOverlapping(600) // 10 minutes max overlap protection
    ->runInBackground()
    ->onSuccess(function () {
        Log::info('Scheduled quick coherency check completed successfully');
    })
    ->onFailure(function () {
        Log::error('Scheduled quick coherency check failed');
    });
