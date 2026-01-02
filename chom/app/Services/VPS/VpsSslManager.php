<?php

namespace App\Services\VPS;

use App\Models\VpsServer;

/**
 * VPS SSL Manager.
 *
 * Manages SSL certificates on VPS servers.
 * Follows Single Responsibility Principle - only handles SSL operations.
 */
class VpsSslManager
{
    public function __construct(
        private VpsCommandExecutor $commandExecutor
    ) {}

    /**
     * Issue SSL certificate for a domain.
     */
    public function issueSSL(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'ssl:issue', [$domain]);
    }

    /**
     * Renew SSL certificates.
     *
     * @param  string|null  $domain  Specific domain or null for all
     */
    public function renewSSL(VpsServer $vps, ?string $domain = null): array
    {
        $args = [];
        if ($domain) {
            $args[] = $domain;
        }

        return $this->commandExecutor->execute($vps, 'ssl:renew', $args);
    }

    /**
     * Get SSL status for a domain.
     */
    public function getSSLStatus(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'ssl:status', [$domain]);
    }
}
