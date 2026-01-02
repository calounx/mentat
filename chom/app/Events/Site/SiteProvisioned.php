<?php

namespace App\Events\Site;

use App\Events\AbstractDomainEvent;
use App\Models\Site;

/**
 * Fired when site provisioning succeeds on the VPS server.
 *
 * TIMING: Emitted AFTER ProvisionSiteJob updates site status to 'active'
 * LISTENERS:
 * - RecordAuditLog: Creates audit trail for successful provisioning
 * - SendNotification: Sends email notification to user
 * - RecordMetrics: Records provisioning duration and success counter
 */
class SiteProvisioned extends AbstractDomainEvent
{
    /**
     * Create a new SiteProvisioned event instance.
     *
     * @param  Site  $site  The successfully provisioned site
     * @param  array<string, mixed>  $provisioningDetails  Additional provisioning metadata (e.g., duration)
     * @param  string|null  $actorId  The ID of the actor (defaults to 'system')
     */
    public function __construct(
        public readonly Site $site,
        public readonly array $provisioningDetails = [],
        ?string $actorId = null
    ) {
        parent::__construct($actorId, 'system');
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
            'tenant_id' => $this->site->tenant_id,
            'domain' => $this->site->domain,
            'site_type' => $this->site->site_type,
            'duration_seconds' => $this->provisioningDetails['duration'] ?? null,
        ]);
    }
}
