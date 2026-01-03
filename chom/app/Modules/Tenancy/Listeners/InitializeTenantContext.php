<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Listeners;

use App\Modules\Tenancy\Events\TenantSwitched;
use Illuminate\Support\Facades\Log;

/**
 * Initialize Tenant Context Listener
 *
 * Initializes tenant-specific configurations when tenant is switched.
 */
class InitializeTenantContext
{
    /**
     * Handle the event.
     *
     * @param TenantSwitched $event
     * @return void
     */
    public function handle(TenantSwitched $event): void
    {
        // Clear any tenant-specific caches
        cache()->tags(['tenant:' . ($event->previousTenantId ?? '')])->flush();

        // Set tenant-specific configuration
        config(['app.current_tenant' => $event->newTenant->id]);

        Log::debug('Tenant context initialized', [
            'tenant_id' => $event->newTenant->id,
            'user_id' => $event->user->id,
        ]);
    }
}
