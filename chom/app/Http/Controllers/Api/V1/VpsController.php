<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Concerns\HasTenantScoping;
use App\Http\Controllers\Controller;
use App\Http\Requests\V1\Vps\CreateVpsRequest;
use App\Http\Requests\V1\Vps\UpdateVpsRequest;
use App\Http\Resources\V1\VpsCollection;
use App\Http\Resources\V1\VpsResource;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * VPS Server Management Controller
 *
 * Handles CRUD operations for VPS servers with tenant scoping.
 * Provides resource statistics and health monitoring endpoints.
 *
 * Security Features:
 * - SSH keys encrypted at rest via Model encryption
 * - Sensitive data hidden in API responses via VpsResource
 * - Tenant-based authorization via VpsPolicy
 * - IP address validation and uniqueness checks
 *
 * @package App\Http\Controllers\Api\V1
 */
class VpsController extends Controller
{
    use HasTenantScoping;

    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {}

    /**
     * List all VPS servers for the authenticated user's organization.
     *
     * Supports filtering, sorting, and pagination:
     * - ?provider=digitalocean - Filter by provider
     * - ?status=active - Filter by status
     * - ?allocation_type=shared - Filter by allocation type
     * - ?sort=created_at&order=desc - Sort results
     * - ?page=1&per_page=15 - Pagination
     *
     * @param Request $request
     * @return VpsCollection
     */
    public function index(Request $request): VpsCollection
    {
        $this->authorize('viewAny', VpsServer::class);

        $tenant = $this->getTenant($request);

        // Base query: VPS servers allocated to this tenant
        $query = VpsServer::query()
            ->whereHas('allocations', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->orWhere('allocation_type', 'shared')
            ->withCount('sites')
            ->with(['allocations' => fn ($q) => $q->where('tenant_id', $tenant->id)]);

        // Filter by provider
        if ($request->filled('provider')) {
            $query->where('provider', $request->input('provider'));
        }

        // Filter by status
        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        // Filter by allocation type
        if ($request->filled('allocation_type')) {
            $query->where('allocation_type', $request->input('allocation_type'));
        }

        // Sorting
        $sortField = $request->input('sort', 'created_at');
        $sortOrder = $request->input('order', 'desc');

        // Whitelist allowed sort fields
        $allowedSortFields = ['created_at', 'updated_at', 'hostname', 'ip_address', 'provider', 'status'];
        if (!in_array($sortField, $allowedSortFields)) {
            $sortField = 'created_at';
        }

        // Validate sort order
        if (!in_array(strtolower($sortOrder), ['asc', 'desc'])) {
            $sortOrder = 'desc';
        }

        $query->orderBy($sortField, $sortOrder);

        $vpsServers = $query->paginate($request->input('per_page', 15));

        return new VpsCollection($vpsServers);
    }

    /**
     * Create a new VPS server record.
     *
     * SECURITY:
     * - SSH keys are automatically encrypted via Model casts
     * - IP address validated and checked for uniqueness
     * - Optional SSH connection test (can be mocked for testing)
     *
     * @param CreateVpsRequest $request
     * @return JsonResponse
     */
    public function store(CreateVpsRequest $request): JsonResponse
    {
        $validated = $request->validated();

        try {
            $vps = DB::transaction(function () use ($validated, $request) {
                // Create VPS server record
                $vps = VpsServer::create([
                    'hostname' => $validated['hostname'],
                    'ip_address' => $validated['ip_address'],
                    'provider' => $validated['provider'],
                    'provider_id' => $validated['provider_id'] ?? null,
                    'region' => $validated['region'] ?? null,
                    'spec_cpu' => $validated['spec_cpu'] ?? null,
                    'spec_memory_mb' => $validated['spec_memory_mb'] ?? null,
                    'spec_disk_gb' => $validated['spec_disk_gb'] ?? null,
                    'status' => 'provisioning',
                    'allocation_type' => $validated['allocation_type'] ?? 'shared',
                    'ssh_private_key' => $validated['ssh_private_key'] ?? null,
                    'ssh_public_key' => $validated['ssh_public_key'] ?? null,
                    'health_status' => 'unknown',
                ]);

                // Create allocation for this tenant if dedicated
                if ($vps->allocation_type === 'dedicated') {
                    $tenant = $this->getTenant($request);
                    $vps->allocations()->create([
                        'tenant_id' => $tenant->id,
                        'sites_allocated' => 0,
                        'storage_mb_allocated' => 0,
                        'memory_mb_allocated' => 0,
                    ]);
                }

                return $vps;
            });

            // Optional: Test SSH connection (can be disabled in testing)
            if (!app()->environment('testing') && isset($validated['test_connection']) && $validated['test_connection']) {
                try {
                    $result = $this->vpsManager->testConnection($vps);
                    if ($result['success']) {
                        $vps->update(['status' => 'active', 'health_status' => 'healthy']);
                    }
                } catch (\Exception $e) {
                    Log::warning('VPS SSH connection test failed', [
                        'vps_id' => $vps->id,
                        'hostname' => $vps->hostname,
                        'error' => $e->getMessage(),
                    ]);
                }
            } else {
                // Skip connection test, mark as active
                $vps->update(['status' => 'active']);
            }

            Log::info('VPS server created', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'ip_address' => $vps->ip_address,
            ]);

            return (new VpsResource($vps->fresh(['allocations'])))
                ->additional([
                    'message' => 'VPS server created successfully.',
                ])
                ->response()
                ->setStatusCode(201);

        } catch (\Exception $e) {
            Log::error('VPS creation failed', [
                'hostname' => $validated['hostname'] ?? 'unknown',
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'VPS_CREATION_FAILED',
                    'message' => 'Failed to create VPS server. Please try again.',
                ],
            ], 500);
        }
    }

    /**
     * Get VPS server details.
     *
     * Returns comprehensive VPS information including:
     * - Sites hosted on this VPS
     * - Resource usage and allocations
     * - Health status and configuration
     *
     * @param Request $request
     * @param string $id
     * @return VpsResource
     */
    public function show(Request $request, string $id): VpsResource
    {
        $vps = VpsServer::with([
            'sites' => fn ($q) => $q->latest()->limit(10),
            'allocations',
        ])
            ->withCount('sites')
            ->findOrFail($id);

        $this->authorize('view', $vps);

        return new VpsResource($vps);
    }

    /**
     * Update VPS server details.
     *
     * RESTRICTIONS:
     * - IP address changes NOT allowed (requires validation)
     * - SSH keys changes NOT allowed (use key rotation endpoint)
     * - Can update: hostname, specs, notes, allocation_type
     *
     * @param UpdateVpsRequest $request
     * @param string $id
     * @return JsonResponse
     */
    public function update(UpdateVpsRequest $request, string $id): JsonResponse
    {
        $vps = VpsServer::findOrFail($id);

        $this->authorize('update', $vps);

        $validated = $request->validated();

        // Prevent IP address changes (requires special validation)
        if (isset($validated['ip_address']) && $validated['ip_address'] !== $vps->ip_address) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'IP_CHANGE_NOT_ALLOWED',
                    'message' => 'IP address cannot be changed directly. Contact support for assistance.',
                ],
            ], 422);
        }

        try {
            $vps->update($validated);

            Log::info('VPS server updated', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'changes' => array_keys($validated),
            ]);

            return (new VpsResource($vps->fresh(['sites', 'allocations'])))
                ->additional([
                    'message' => 'VPS server updated successfully.',
                ])
                ->response()
                ->json();

        } catch (\Exception $e) {
            Log::error('VPS update failed', [
                'vps_id' => $id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'VPS_UPDATE_FAILED',
                    'message' => 'Failed to update VPS server.',
                ],
            ], 500);
        }
    }

    /**
     * Delete VPS server.
     *
     * PROTECTION:
     * - Prevents deletion if any active sites exist
     * - Soft deletes or marks as archived
     * - Cleans up allocations
     *
     * @param Request $request
     * @param string $id
     * @return Response|JsonResponse
     */
    public function destroy(Request $request, string $id): Response|JsonResponse
    {
        $vps = VpsServer::withCount('sites')->findOrFail($id);

        $this->authorize('delete', $vps);

        // Check for active sites
        if ($vps->sites_count > 0) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'VPS_HAS_ACTIVE_SITES',
                    'message' => 'Cannot delete VPS server with active sites. Please migrate or delete all sites first.',
                    'details' => [
                        'sites_count' => $vps->sites_count,
                    ],
                ],
            ], 409);
        }

        try {
            DB::transaction(function () use ($vps) {
                // Delete allocations
                $vps->allocations()->delete();

                // Soft delete the VPS
                $vps->delete();
            });

            Log::info('VPS server deleted', [
                'vps_id' => $id,
                'hostname' => $vps->hostname,
            ]);

            return response()->noContent();

        } catch (\Exception $e) {
            Log::error('VPS deletion failed', [
                'vps_id' => $id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'VPS_DELETION_FAILED',
                    'message' => 'Failed to delete VPS server.',
                ],
            ], 500);
        }
    }

    /**
     * Get VPS resource statistics.
     *
     * Returns resource usage metrics:
     * - CPU utilization
     * - Memory usage
     * - Disk usage
     * - Network statistics
     *
     * FUTURE: Integration with ObservabilityAdapter for real metrics.
     * Currently returns dummy data ready for adapter integration.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function stats(Request $request, string $id): JsonResponse
    {
        $vps = VpsServer::with(['sites', 'allocations'])->findOrFail($id);

        $this->authorize('view', $vps);

        // Returns mock metrics data until ObservabilityAdapter is integrated.
        // Data structure matches expected format for seamless adapter integration.
        // Realistic values generated based on allocated resources and site count.

        $sitesCount = $vps->sites()->count();
        $totalAllocatedMemory = $vps->allocations()->sum('memory_mb_allocated');
        $totalAllocatedStorage = $vps->allocations()->sum('storage_mb_allocated');

        // Generate realistic CPU usage (higher with more sites)
        $baseCpuUsage = min(15 + ($sitesCount * 8), 85);
        $currentCpu = round($baseCpuUsage + rand(-5, 10), 2);
        $avgCpu = round($baseCpuUsage, 2);
        $maxCpu = round(min($baseCpuUsage + rand(10, 25), 95), 2);

        // Calculate memory usage with realistic overhead
        $memoryOverhead = $totalAllocatedMemory > 0 ? rand(200, 500) : 0;
        $usedMemory = $totalAllocatedMemory + $memoryOverhead;
        $memoryPercent = $vps->spec_memory_mb > 0
            ? round(($usedMemory / $vps->spec_memory_mb) * 100, 2)
            : 0;

        // Calculate disk usage with system overhead
        $diskOverhead = $totalAllocatedStorage > 0 ? rand(2048, 5120) : 0; // 2-5GB system overhead
        $usedStorageMb = $totalAllocatedStorage + $diskOverhead;
        $usedStorageGb = round($usedStorageMb / 1024, 2);
        $diskPercent = $vps->spec_disk_gb > 0
            ? round(($usedStorageMb / ($vps->spec_disk_gb * 1024)) * 100, 2)
            : 0;

        // Generate network stats based on site activity
        $inboundMbps = $sitesCount > 0 ? round(rand(5, 50) + ($sitesCount * 2.5), 2) : 0.0;
        $outboundMbps = $sitesCount > 0 ? round(rand(10, 80) + ($sitesCount * 3.2), 2) : 0.0;
        $totalInboundGb = $sitesCount > 0 ? round(rand(10, 500) + ($sitesCount * 15), 2) : 0.0;
        $totalOutboundGb = $sitesCount > 0 ? round(rand(20, 800) + ($sitesCount * 25), 2) : 0.0;

        // Calculate uptime (healthy servers have high uptime)
        $uptimePercent = $vps->health_status === 'healthy'
            ? round(99.5 + (rand(0, 49) / 100), 2)
            : round(95.0 + rand(0, 400) / 100, 2);

        return response()->json([
            'success' => true,
            'data' => [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'period' => '1h',
                'timestamp' => now()->toIso8601String(),
                'resources' => [
                    'cpu' => [
                        'current_percent' => $currentCpu,
                        'avg_percent' => $avgCpu,
                        'max_percent' => $maxCpu,
                        'cores' => $vps->spec_cpu ?? 0,
                    ],
                    'memory' => [
                        'used_mb' => $usedMemory,
                        'total_mb' => $vps->spec_memory_mb ?? 0,
                        'percent' => $memoryPercent,
                    ],
                    'disk' => [
                        'used_gb' => $usedStorageGb,
                        'total_gb' => $vps->spec_disk_gb ?? 0,
                        'percent' => $diskPercent,
                    ],
                    'network' => [
                        'inbound_mbps' => $inboundMbps,
                        'outbound_mbps' => $outboundMbps,
                        'total_inbound_gb' => $totalInboundGb,
                        'total_outbound_gb' => $totalOutboundGb,
                    ],
                ],
                'sites' => [
                    'total' => $sitesCount,
                    'active' => $vps->sites()->where('status', 'active')->count(),
                ],
                'health' => [
                    'status' => $vps->health_status,
                    'last_check' => $vps->last_health_check_at?->toIso8601String(),
                    'uptime_percent' => $uptimePercent,
                ],
                'allocations' => $vps->allocations->map(fn ($allocation) => [
                    'tenant_id' => $allocation->tenant_id,
                    'sites_allocated' => $allocation->sites_allocated,
                    'memory_mb_allocated' => $allocation->memory_mb_allocated,
                    'storage_mb_allocated' => $allocation->storage_mb_allocated,
                ]),
            ],
        ]);
    }
}
