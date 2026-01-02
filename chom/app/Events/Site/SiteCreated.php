<?php

namespace App\Events\Site;

use App\Events\AbstractDomainEvent;
use App\Models\Site;
use App\Models\Tenant;

/**
 * Fired when a new site record is created in the database.
 *
 * TIMING: Emitted AFTER Site::create() succeeds within the database transaction
 * LISTENERS:
 * - UpdateTenantMetrics: Invalidates and updates cached site count for tenant
 * - RecordAuditLog: Creates audit trail for site creation
 * - RecordMetrics: Records site_created_total counter in Prometheus
 */
class SiteCreated extends AbstractDomainEvent
{
    /**
     * Create a new SiteCreated event instance.
     *
     * @param  Site  $site  The newly created site
     * @param  Tenant  $tenant  The tenant who owns the site
     * @param  string|null  $actorId  The ID of the user who created the site
     */
    public function __construct(
        public readonly Site $site,
        public readonly Tenant $tenant,
        ?string $actorId = null
    ) {
        parent::__construct($actorId);
    }

    /**
     * Get event metadata for logging and auditing.
     *
     * @return array<string, mixed>
     */
    public function getMetadata(): array
    {
        return array_merge(parent::getMetadata(), [
            'site_id' => $this->site->id,
            'tenant_id' => $this->tenant->id,
            'domain' => $this->site->domain,
            'site_type' => $this->site->site_type,
            'php_version' => $this->site->php_version,
            'ssl_enabled' => $this->site->ssl_enabled,
        ]);
    }
}
