<?php

declare(strict_types=1);

namespace App\Modules\Auth\Events;

use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * User Logged Out Event
 *
 * Dispatched when a user logs out.
 */
class UserLoggedOut
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly User $user,
        public readonly ?\DateTime $loggedOutAt = null
    ) {
    }
}
