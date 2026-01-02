<?php

namespace App\Events\Site;

use App\Events\AbstractDomainEvent;
use App\Models\Site;

/**
 * Fired when site provisioning fails on the VPS server.
 *
 * TIMING: Emitted AFTER ProvisionSiteJob updates site status to 'failed'
 * LISTENERS:
 * - RecordAuditLog: Creates high-severity audit trail for failure
 * - SendNotification: Sends error notification email to user
 * - RecordMetrics: Records provisioning failure counter
 */
class SiteProvisioningFailed extends AbstractDomainEvent
{
    /**
     * Create a new SiteProvisioningFailed event instance.
     *
     * @param  Site  $site  The site that failed to provision
     * @param  string  $errorMessage  The error message describing what went wrong
     * @param  string|null  $errorTrace  Optional stack trace for debugging
     * @param  string|null  $actorId  The ID of the actor (defaults to 'system')
     */
    public function __construct(
        public readonly Site $site,
        public readonly string $errorMessage,
        public readonly ?string $errorTrace = null,
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
            'error' => $this->errorMessage,
            'has_trace' => ! empty($this->errorTrace),
        ]);
    }
}
