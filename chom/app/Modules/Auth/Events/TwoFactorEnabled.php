<?php

declare(strict_types=1);

namespace App\Modules\Auth\Events;

use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Two-Factor Enabled Event
 *
 * Dispatched when two-factor authentication is enabled for a user.
 */
class TwoFactorEnabled
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly User $user,
        public readonly ?\DateTime $enabledAt = null
    ) {
    }
}
