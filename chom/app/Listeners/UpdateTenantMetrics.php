<?php

namespace App\Listeners;

use App\Events\Site\SiteCreated;
use App\Events\Site\SiteDeleted;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Log;

/**
 * Updates tenant cached statistics when sites change.
 *
 * QUEUED: Yes (non-critical, can be async)
 * REPLACES: Manual $tenant->updateCachedStats() calls in Site model lifecycle hooks
 *
 * This listener consolidates cache invalidation logic that was previously
 * scattered in model lifecycle hooks. By handling this via events, we:
 * - Decouple cache logic from model code
 * - Can queue the update for better performance
 * - Have a single place to manage tenant metric updates
 */
class UpdateTenantMetrics implements ShouldQueue
{
    /**
     * The name of the queue the job should be sent to.
     *
     * @var string
     */
    public $queue = 'default';

    /**
     * The number of times the queued listener may be attempted.
     *
     * @var int
     */
    public $tries = 3;

    /**
     * The number of seconds to wait before retrying.
     *
     * @var int
     */
    public $backoff = 30;

    /**
     * Handle site created event.
     *
     * When a new site is created, increment the tenant's cached site count.
     */
    public function handleSiteCreated(SiteCreated $event): void
    {
        // Reload the tenant to ensure we have the latest data
        $tenant = $event->tenant->fresh();

        if ($tenant) {
            $tenant->updateCachedStats();

            Log::debug('Tenant metrics updated after site creation', [
                'tenant_id' => $tenant->id,
                'cached_sites_count' => $tenant->cached_sites_count,
                'site_id' => $event->site->id,
            ]);
        }
    }

    /**
     * Handle site deleted event.
     *
     * When a site is deleted, decrement the tenant's cached site count.
     */
    public function handleSiteDeleted(SiteDeleted $event): void
    {
        // Find tenant since we only have the ID (site model is soft-deleted)
        $tenant = \App\Models\Tenant::find($event->tenantId);

        if ($tenant) {
            $tenant->updateCachedStats();

            Log::debug('Tenant metrics updated after site deletion', [
                'tenant_id' => $tenant->id,
                'cached_sites_count' => $tenant->cached_sites_count,
                'deleted_site_id' => $event->siteId,
            ]);
        }
    }

    /**
     * Handle a job failure.
     *
     * @param  mixed  $event
     */
    public function failed($event, \Throwable $exception): void
    {
        Log::error('UpdateTenantMetrics listener failed', [
            'event' => get_class($event),
            'error' => $exception->getMessage(),
            'trace' => $exception->getTraceAsString(),
        ]);
    }
}
