<?php

declare(strict_types=1);

namespace App\Modules\Auth\Events;

use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * User Authenticated Event
 *
 * Dispatched when a user successfully authenticates.
 */
class UserAuthenticated
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly User $user,
        public readonly string $ipAddress,
        public readonly ?\DateTime $authenticatedAt = null
    ) {
    }
}
