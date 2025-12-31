<?php

namespace App\Events\Site;

use App\Events\AbstractDomainEvent;

/**
 * Fired when a site is soft-deleted.
 *
 * TIMING: Emitted AFTER $site->delete() succeeds
 * LISTENERS:
 * - UpdateTenantMetrics: Decrements cached site count for tenant
 * - RecordAuditLog: Creates audit trail for deletion
 * - RecordMetrics: Records site_deleted_total counter
 *
 * NOTE: We pass primitive data (strings) instead of the Site model because
 * the site is soft-deleted and may not be accessible via normal queries.
 *
 * @package App\Events\Site
 */
class SiteDeleted extends AbstractDomainEvent
{
    /**
     * Create a new SiteDeleted event instance.
     *
     * @param string $siteId The UUID of the deleted site
     * @param string $tenantId The UUID of the tenant who owned the site
     * @param string $domain The domain name of the deleted site
     * @param string|null $actorId The ID of the user who deleted the site
     */
    public function __construct(
        public readonly string $siteId,
        public readonly string $tenantId,
        public readonly string $domain,
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
            'site_id' => $this->siteId,
            'tenant_id' => $this->tenantId,
            'domain' => $this->domain,
        ]);
    }
}
