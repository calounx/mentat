<?php

declare(strict_types=1);

namespace App\Modules\Auth\Events;

use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Two-Factor Disabled Event
 *
 * Dispatched when two-factor authentication is disabled for a user.
 */
class TwoFactorDisabled
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly User $user,
        public readonly ?\DateTime $disabledAt = null
    ) {
    }
}
