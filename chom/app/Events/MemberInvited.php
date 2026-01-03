<?php

declare(strict_types=1);

namespace App\Events;

use App\Models\TeamInvitation;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class MemberInvited
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly TeamInvitation $invitation
    ) {
    }
}
