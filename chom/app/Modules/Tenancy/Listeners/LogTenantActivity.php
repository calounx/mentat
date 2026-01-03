<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Listeners;

use App\Modules\Tenancy\Events\OrganizationCreated;
use App\Modules\Tenancy\Events\TenantSwitched;
use Illuminate\Support\Facades\Log;

/**
 * Log Tenant Activity Listener
 *
 * Logs tenant-related activities for auditing.
 */
class LogTenantActivity
{
    /**
     * Handle the event.
     *
     * @param TenantSwitched|OrganizationCreated $event
     * @return void
     */
    public function handle(TenantSwitched|OrganizationCreated $event): void
    {
        if ($event instanceof TenantSwitched) {
            Log::info('Tenant switched', [
                'user_id' => $event->user->id,
                'email' => $event->user->email,
                'new_tenant_id' => $event->newTenant->id,
                'new_tenant_name' => $event->newTenant->name,
                'previous_tenant_id' => $event->previousTenantId,
            ]);
        } elseif ($event instanceof OrganizationCreated) {
            Log::info('Organization created', [
                'organization_id' => $event->organization->id,
                'name' => $event->organization->name,
                'tier' => $event->organization->tier,
                'owner_id' => $event->owner->id,
                'owner_email' => $event->owner->email,
            ]);
        }
    }
}
