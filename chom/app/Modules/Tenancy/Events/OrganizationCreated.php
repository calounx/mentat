<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Events;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Organization Created Event
 *
 * Dispatched when a new organization (tenant) is created.
 */
class OrganizationCreated
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly Organization $organization,
        public readonly User $owner
    ) {
    }
}
