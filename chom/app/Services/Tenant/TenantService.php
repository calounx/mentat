<?php

namespace App\Services\Tenant;

use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Tenant Service
 *
 * Handles tenant lifecycle operations including creation,
 * updates, status management, and metrics.
 */
class TenantService
{
    /**
     * Create a new tenant.
     *
     * @param array<string, mixed> $data Tenant data
     * @return Tenant
     */
    public function createTenant(array $data): Tenant
    {
        $tenantData = [
            'organization_id' => $data['organization_id'],
            'name' => $data['name'],
            'slug' => $data['slug'] ?? Str::slug($data['name']),
            'tier' => $data['tier'] ?? 'free',
            'status' => 'active',
            'settings' => $data['settings'] ?? [],
            'metrics_retention_days' => $data['metrics_retention_days'] ?? 30,
        ];

        $tenant = Tenant::create($tenantData);

        Log::info('Tenant created', [
            'tenant_id' => $tenant->id,
            'organization_id' => $tenant->organization_id,
            'name' => $tenant->name,
        ]);

        return $tenant;
    }

    /**
     * Update tenant settings.
     *
     * @param Tenant $tenant
     * @param array<string, mixed> $data
     * @return Tenant
     */
    public function updateTenant(Tenant $tenant, array $data): Tenant
    {
        $allowedFields = ['name', 'settings', 'metrics_retention_days'];
        $updateData = [];

        foreach ($allowedFields as $field) {
            if (array_key_exists($field, $data)) {
                $updateData[$field] = $data[$field];
            }
        }

        if (!empty($updateData)) {
            $tenant->update($updateData);

            Log::info('Tenant updated', [
                'tenant_id' => $tenant->id,
                'updated_fields' => array_keys($updateData),
            ]);
        }

        return $tenant->fresh();
    }

    /**
     * Activate a tenant.
     *
     * @param Tenant $tenant
     * @return array{success: bool, message: string}
     */
    public function activateTenant(Tenant $tenant): array
    {
        if ($tenant->status === 'active') {
            return [
                'success' => true,
                'message' => 'Tenant is already active',
            ];
        }

        $tenant->update(['status' => 'active']);

        Log::info('Tenant activated', [
            'tenant_id' => $tenant->id,
        ]);

        return [
            'success' => true,
            'message' => 'Tenant activated successfully',
        ];
    }

    /**
     * Suspend a tenant.
     *
     * This will prevent the tenant from creating new resources.
     *
     * @param Tenant $tenant
     * @param string|null $reason
     * @return array{success: bool, message: string}
     */
    public function suspendTenant(Tenant $tenant, ?string $reason = null): array
    {
        if ($tenant->status === 'suspended') {
            return [
                'success' => true,
                'message' => 'Tenant is already suspended',
            ];
        }

        $tenant->update(['status' => 'suspended']);

        Log::warning('Tenant suspended', [
            'tenant_id' => $tenant->id,
            'reason' => $reason,
        ]);

        return [
            'success' => true,
            'message' => 'Tenant suspended successfully',
        ];
    }

    /**
     * Get tenant usage metrics.
     *
     * @param Tenant $tenant
     * @return array{sites: array, storage: array, backups: array}
     */
    public function getTenantMetrics(Tenant $tenant): array
    {
        return [
            'sites' => [
                'total' => $tenant->sites()->count(),
                'active' => $tenant->sites()->where('status', 'active')->count(),
                'creating' => $tenant->sites()->where('status', 'creating')->count(),
                'disabled' => $tenant->sites()->where('status', 'disabled')->count(),
            ],
            'storage' => [
                'used_mb' => $tenant->getStorageUsedMb(),
                'sites' => $tenant->sites()->sum('storage_used_mb'),
            ],
            'backups' => [
                'total' => $tenant->sites()->withCount('backups')->get()->sum('backups_count'),
            ],
        ];
    }

    /**
     * Get tenant resource summary.
     *
     * @param Tenant $tenant
     * @return array
     */
    public function getResourceSummary(Tenant $tenant): array
    {
        $sites = $tenant->sites;
        $vpsAllocations = $tenant->vpsAllocations()->with('vpsServer')->get();

        return [
            'tenant' => [
                'id' => $tenant->id,
                'name' => $tenant->name,
                'tier' => $tenant->tier,
                'status' => $tenant->status,
            ],
            'sites' => [
                'count' => $sites->count(),
                'limit' => $tenant->getMaxSites(),
                'by_status' => $sites->groupBy('status')->map->count()->toArray(),
                'by_type' => $sites->groupBy('site_type')->map->count()->toArray(),
            ],
            'vps' => [
                'allocated_count' => $vpsAllocations->count(),
                'servers' => $vpsAllocations->map(fn($alloc) => [
                    'id' => $alloc->vpsServer->id,
                    'hostname' => $alloc->vpsServer->hostname,
                    'site_count' => $alloc->vpsServer->sites()->where('tenant_id', $tenant->id)->count(),
                ])->toArray(),
            ],
        ];
    }

    /**
     * Validate tenant can be deleted.
     *
     * @param Tenant $tenant
     * @return array{can_delete: bool, blockers: array<string>}
     */
    public function canDelete(Tenant $tenant): array
    {
        $blockers = [];

        if ($tenant->sites()->count() > 0) {
            $blockers[] = 'Tenant has active sites';
        }

        return [
            'can_delete' => empty($blockers),
            'blockers' => $blockers,
        ];
    }

    /**
     * Get tenant from user context.
     *
     * @param User $user
     * @return Tenant|null
     */
    public function getTenantForUser(User $user): ?Tenant
    {
        return $user->currentTenant();
    }

    /**
     * Validate tenant is active.
     *
     * @param Tenant $tenant
     * @throws \RuntimeException
     */
    public function ensureActive(Tenant $tenant): void
    {
        if (!$tenant->isActive()) {
            throw new \RuntimeException('Tenant is not active');
        }
    }
}
