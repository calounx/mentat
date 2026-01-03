<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Contracts;

use App\Models\VpsServer;
use App\Modules\Infrastructure\ValueObjects\VpsSpecification;

/**
 * VPS Provider Service Contract
 *
 * Defines the contract for VPS server management operations.
 */
interface VpsProviderInterface
{
    /**
     * Provision a new VPS server.
     *
     * @param VpsSpecification $spec VPS specifications
     * @return VpsServer Provisioned VPS
     * @throws \RuntimeException
     */
    public function provision(VpsSpecification $spec): VpsServer;

    /**
     * Deprovision a VPS server.
     *
     * @param string $vpsId VPS ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function deprovision(string $vpsId): bool;

    /**
     * Get VPS server details.
     *
     * @param string $vpsId VPS ID
     * @return VpsServer VPS details
     * @throws \RuntimeException
     */
    public function getDetails(string $vpsId): VpsServer;

    /**
     * Check VPS server health.
     *
     * @param string $vpsId VPS ID
     * @return array Health status
     */
    public function checkHealth(string $vpsId): array;

    /**
     * Find available VPS for site provisioning.
     *
     * @param int $minMemoryMb Minimum memory requirement
     * @param int $minDiskGb Minimum disk requirement
     * @return VpsServer|null Available VPS
     */
    public function findAvailable(int $minMemoryMb = 2048, int $minDiskGb = 20): ?VpsServer;

    /**
     * Get VPS resource usage.
     *
     * @param string $vpsId VPS ID
     * @return array Resource usage metrics
     */
    public function getResourceUsage(string $vpsId): array;
}
