<?php

declare(strict_types=1);

namespace App\Modules\Auth\Listeners;

use App\Modules\Auth\Events\TwoFactorDisabled;
use App\Modules\Auth\Events\TwoFactorEnabled;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * Notify Two-Factor Change Listener
 *
 * Sends notifications when 2FA settings change.
 */
class NotifyTwoFactorChange
{
    /**
     * Handle the event.
     *
     * @param TwoFactorEnabled|TwoFactorDisabled $event
     * @return void
     */
    public function handle(TwoFactorEnabled|TwoFactorDisabled $event): void
    {
        $action = $event instanceof TwoFactorEnabled ? 'enabled' : 'disabled';

        Log::info("Two-factor authentication {$action}", [
            'user_id' => $event->user->id,
            'email' => $event->user->email,
            'timestamp' => $event->enabledAt ?? $event->disabledAt ?? now(),
        ]);
    }
}
