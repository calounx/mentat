<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class VpsController extends Controller
{
    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {
        // All VPS management operations require admin privileges
        // These are infrastructure-level operations that could expose
        // data from other tenants or affect server security
    }

    /**
     * Ensure the current user has admin privileges.
     * Aborts with 403 if the user is not an admin.
     */
    private function ensureAdmin(): void
    {
        $user = auth()->user();

        if (!$user || !$user->isAdmin()) {
            abort(403, 'This action requires administrator privileges.');
        }
    }

    /**
     * Get VPS health status.
     * Admin-only: Infrastructure monitoring operation.
     */
    public function health(Request $request, string $id): JsonResponse
    {
        $this->ensureAdmin();

        $tenant = $this->getTenant($request);
        $vps = $this->getVpsForTenant($tenant, $id);

        try {
            $result = $this->vpsManager->healthCheck($vps);

            return response()->json([
                'success' => $result['success'],
                'data' => [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'ip_address' => $vps->ip_address,
                    'health_status' => $vps->health_status,
                    'last_health_check_at' => $vps->last_health_check_at?->toIso8601String(),
                    'health_data' => $result['data'] ?? null,
                ],
            ], $result['success'] ? 200 : 500);

        } catch (\Exception $e) {
            Log::error('Failed to get VPS health', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'HEALTH_CHECK_FAILED',
                    'message' => 'Failed to retrieve VPS health status.',
                ],
            ], 500);
        }
    }

    /**
     * Get VPS dashboard data.
     * Admin-only: Infrastructure monitoring operation.
     */
    public function dashboard(Request $request, string $id): JsonResponse
    {
        $this->ensureAdmin();

        $tenant = $this->getTenant($request);
        $vps = $this->getVpsForTenant($tenant, $id);

        try {
            $result = $this->vpsManager->getDashboard($vps);

            return response()->json([
                'success' => $result['success'],
                'data' => [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'ip_address' => $vps->ip_address,
                    'status' => $vps->status,
                    'provider' => $vps->provider,
                    'region' => $vps->region,
                    'specs' => [
                        'cpu' => $vps->spec_cpu,
                        'memory_mb' => $vps->spec_memory_mb,
                        'disk_gb' => $vps->spec_disk_gb,
                    ],
                    'utilization_percent' => $vps->getUtilizationPercent(),
                    'site_count' => $vps->getSiteCount(),
                    'dashboard' => $result['data'] ?? null,
                ],
            ], $result['success'] ? 200 : 500);

        } catch (\Exception $e) {
            Log::error('Failed to get VPS dashboard', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'DASHBOARD_FAILED',
                    'message' => 'Failed to retrieve VPS dashboard data.',
                ],
            ], 500);
        }
    }

    /**
     * Run security audit on VPS.
     * Admin-only: Security-sensitive infrastructure operation.
     */
    public function securityAudit(Request $request, string $id): JsonResponse
    {
        $this->ensureAdmin();

        $tenant = $this->getTenant($request);
        $vps = $this->getVpsForTenant($tenant, $id);

        try {
            $result = $this->vpsManager->securityAudit($vps);

            return response()->json([
                'success' => $result['success'],
                'data' => [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'audit_timestamp' => now()->toIso8601String(),
                    'audit_results' => $result['data'] ?? null,
                    'raw_output' => $result['success'] ? null : $result['output'],
                ],
            ], $result['success'] ? 200 : 500);

        } catch (\Exception $e) {
            Log::error('Failed to run security audit', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'SECURITY_AUDIT_FAILED',
                    'message' => 'Failed to run security audit.',
                ],
            ], 500);
        }
    }

    /**
     * List all sites on VPS.
     * Admin-only: Could expose other tenants' sites on shared VPS.
     */
    public function listSites(Request $request, string $id): JsonResponse
    {
        $this->ensureAdmin();

        $tenant = $this->getTenant($request);
        $vps = $this->getVpsForTenant($tenant, $id);

        try {
            $result = $this->vpsManager->listSites($vps);

            // Also get local database sites for comparison
            $localSites = $vps->sites()
                ->where('tenant_id', $tenant->id)
                ->select(['id', 'domain', 'site_type', 'status', 'ssl_enabled'])
                ->get();

            return response()->json([
                'success' => $result['success'],
                'data' => [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'local_sites' => $localSites->toArray(),
                    'vps_sites' => $result['data'] ?? null,
                ],
            ], $result['success'] ? 200 : 500);

        } catch (\Exception $e) {
            Log::error('Failed to list VPS sites', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'LIST_SITES_FAILED',
                    'message' => 'Failed to list sites on VPS.',
                ],
            ], 500);
        }
    }

    /**
     * Get VPS statistics.
     * Admin-only: Infrastructure monitoring operation.
     */
    public function stats(Request $request, string $id): JsonResponse
    {
        $this->ensureAdmin();

        $tenant = $this->getTenant($request);
        $vps = $this->getVpsForTenant($tenant, $id);

        try {
            $result = $this->vpsManager->getStats($vps);

            return response()->json([
                'success' => $result['success'],
                'data' => [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'status' => $vps->status,
                    'health_status' => $vps->health_status,
                    'specs' => [
                        'cpu' => $vps->spec_cpu,
                        'memory_mb' => $vps->spec_memory_mb,
                        'disk_gb' => $vps->spec_disk_gb,
                    ],
                    'utilization' => [
                        'percent' => $vps->getUtilizationPercent(),
                        'available_memory_mb' => $vps->getAvailableMemoryMb(),
                    ],
                    'site_count' => $vps->getSiteCount(),
                    'vpsmanager_version' => $vps->vpsmanager_version,
                    'observability_configured' => $vps->observability_configured,
                    'live_stats' => $result['data'] ?? null,
                ],
            ], $result['success'] ? 200 : 500);

        } catch (\Exception $e) {
            Log::error('Failed to get VPS stats', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'STATS_FAILED',
                    'message' => 'Failed to retrieve VPS statistics.',
                ],
            ], 500);
        }
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    private function getTenant(Request $request): Tenant
    {
        $tenant = $request->user()->currentTenant();

        if (!$tenant || !$tenant->isActive()) {
            abort(403, 'No active tenant found.');
        }

        return $tenant;
    }

    /**
     * Get VPS server that the tenant has access to.
     * A tenant has access to a VPS if they have sites on it or an allocation.
     */
    private function getVpsForTenant(Tenant $tenant, string $vpsId): VpsServer
    {
        // Check if tenant has any sites on this VPS
        $hasSites = $tenant->sites()
            ->where('vps_id', $vpsId)
            ->exists();

        // Or check if tenant has a direct allocation
        $hasAllocation = $tenant->vpsAllocations()
            ->where('vps_id', $vpsId)
            ->exists();

        if (!$hasSites && !$hasAllocation) {
            abort(403, 'You do not have access to this VPS server.');
        }

        return VpsServer::findOrFail($vpsId);
    }
}
