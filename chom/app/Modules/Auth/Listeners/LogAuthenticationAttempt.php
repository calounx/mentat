<?php

declare(strict_types=1);

namespace App\Modules\Auth\Listeners;

use App\Modules\Auth\Events\UserAuthenticated;
use App\Modules\Auth\Events\UserLoggedOut;
use Illuminate\Support\Facades\Log;

/**
 * Log Authentication Attempt Listener
 *
 * Logs authentication events for security auditing.
 */
class LogAuthenticationAttempt
{
    /**
     * Handle the event.
     *
     * @param UserAuthenticated|UserLoggedOut $event
     * @return void
     */
    public function handle(UserAuthenticated|UserLoggedOut $event): void
    {
        if ($event instanceof UserAuthenticated) {
            Log::info('User authenticated', [
                'user_id' => $event->user->id,
                'email' => $event->user->email,
                'ip_address' => $event->ipAddress,
                'authenticated_at' => $event->authenticatedAt ?? now(),
            ]);
        } elseif ($event instanceof UserLoggedOut) {
            Log::info('User logged out', [
                'user_id' => $event->user->id,
                'email' => $event->user->email,
                'logged_out_at' => $event->loggedOutAt ?? now(),
            ]);
        }
    }
}
