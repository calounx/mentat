<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Events;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Tenant Switched Event
 *
 * Dispatched when a user switches to a different tenant context.
 */
class TenantSwitched
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly User $user,
        public readonly Organization $newTenant,
        public readonly ?string $previousTenantId = null
    ) {
    }
}
