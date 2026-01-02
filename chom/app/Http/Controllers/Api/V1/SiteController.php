<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Concerns\HasTenantScoping;
use App\Http\Controllers\Controller;
use App\Http\Requests\V1\Sites\CreateSiteRequest;
use App\Http\Requests\V1\Sites\UpdateSiteRequest;
use App\Http\Resources\V1\SiteCollection;
use App\Http\Resources\V1\SiteResource;
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;

class SiteController extends Controller
{
    use HasTenantScoping;

    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {}

    /**
     * List all sites for the current tenant.
     *
     * Supports filtering, sorting, and pagination:
     * - ?type=wordpress - Filter by site type
     * - ?status=active - Filter by status
     * - ?search=example.com - Search by domain
     * - ?sort=created_at&order=desc - Sort results
     * - ?page=1&per_page=15 - Pagination
     */
    public function index(Request $request): SiteCollection
    {
        $this->authorize('viewAny', Site::class);

        $tenant = $this->getTenant($request);

        $query = $tenant->sites()
            ->with(['vpsServer:id,hostname,ip_address'])
            ->withCount('backups');

        // Filter by status
        if ($request->has('status')) {
            $query->where('status', $request->input('status'));
        }

        // Filter by type
        if ($request->has('type')) {
            $query->where('site_type', $request->input('type'));
        }

        // Search by domain
        if ($request->has('search')) {
            $query->where('domain', 'like', '%'.$request->input('search').'%');
        }

        // Sorting
        $sortField = $request->input('sort', 'created_at');
        $sortOrder = $request->input('order', 'desc');

        // Whitelist allowed sort fields
        $allowedSortFields = ['created_at', 'updated_at', 'domain', 'status', 'site_type'];
        if (!in_array($sortField, $allowedSortFields)) {
            $sortField = 'created_at';
        }

        // Validate sort order
        if (!in_array(strtolower($sortOrder), ['asc', 'desc'])) {
            $sortOrder = 'desc';
        }

        $query->orderBy($sortField, $sortOrder);

        $sites = $query->paginate($request->input('per_page', 15));

        return new SiteCollection($sites);
    }

    /**
     * Create a new site.
     */
    public function store(CreateSiteRequest $request): JsonResponse
    {
        $tenant = $request->tenant();

        // Check quota
        if (! $tenant->canCreateSite()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'SITE_LIMIT_EXCEEDED',
                    'message' => 'You have reached your plan\'s site limit.',
                    'details' => [
                        'current_sites' => $tenant->getSiteCount(),
                        'limit' => $tenant->getMaxSites(),
                    ],
                ],
            ], 403);
        }

        $validated = $request->validated();

        try {
            $site = DB::transaction(function () use ($validated, $tenant) {
                // Find available VPS
                $vps = $this->findAvailableVps($tenant);

                if (! $vps) {
                    throw new \RuntimeException('No available VPS server found');
                }

                // Create site record
                $site = Site::create([
                    'tenant_id' => $tenant->id,
                    'vps_id' => $vps->id,
                    'domain' => $validated['domain'],
                    'site_type' => $validated['site_type'],
                    'php_version' => $validated['php_version'],
                    'ssl_enabled' => $validated['ssl_enabled'],
                    'status' => 'creating',
                    'settings' => $validated['settings'] ?? [],
                ]);

                return $site;
            });

            // Dispatch async job to provision site on VPS
            ProvisionSiteJob::dispatch($site);

            return (new SiteResource($site))
                ->additional([
                    'message' => 'Site is being created.',
                ])
                ->response()
                ->setStatusCode(201);

        } catch (\Exception $e) {
            Log::error('Site creation failed', [
                'domain' => $validated['domain'] ?? 'unknown',
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'SITE_CREATION_FAILED',
                    'message' => 'Failed to create site. Please try again.',
                ],
            ], 500);
        }
    }

    /**
     * Get site details.
     */
    public function show(Request $request, string $id): SiteResource
    {
        $tenant = $this->getTenant($request);

        $site = $tenant->sites()
            ->with(['vpsServer', 'backups' => fn ($q) => $q->latest()->limit(5)])
            ->findOrFail($id);

        $this->authorize('view', $site);

        return new SiteResource($site);
    }

    /**
     * Update site settings.
     */
    public function update(UpdateSiteRequest $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->findOrFail($id);

        $validated = $request->validated();

        $site->update($validated);

        return (new SiteResource($site))
            ->additional([
                'message' => 'Site updated successfully.',
            ])
            ->response()
            ->json();
    }

    /**
     * Delete a site.
     */
    public function destroy(Request $request, string $id): Response|JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        $this->authorize('delete', $site);

        try {
            // Delete from VPS
            if ($site->vpsServer && $site->status === 'active') {
                $result = $this->vpsManager->deleteSite($site->vpsServer, $site->domain, force: true);

                if (! $result['success']) {
                    Log::warning('VPS site deletion failed', [
                        'site' => $site->domain,
                        'output' => $result['output'],
                    ]);
                }
            }

            // Capture data before deletion (for event)
            $siteId = $site->id;
            $tenantId = $site->tenant_id;
            $domain = $site->domain;

            // Soft delete
            $site->delete();

            // Emit SiteDeleted event (triggers cache update, audit log, metrics)
            \App\Events\Site\SiteDeleted::dispatch($siteId, $tenantId, $domain);

            return response()->noContent();

        } catch (\Exception $e) {
            Log::error('Site deletion failed', [
                'site' => $site->domain,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'SITE_DELETION_FAILED',
                    'message' => 'Failed to delete site.',
                ],
            ], 500);
        }
    }

    /**
     * Enable a site.
     */
    public function enable(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        $this->authorize('enable', $site);

        if ($site->status === 'active') {
            return (new SiteResource($site))
                ->additional([
                    'message' => 'Site is already enabled.',
                ])
                ->response()
                ->json();
        }

        try {
            $result = $this->vpsManager->enableSite($site->vpsServer, $site->domain);

            if ($result['success']) {
                $site->update(['status' => 'active']);
            }

            return (new SiteResource($site->fresh()))
                ->additional([
                    'message' => $result['success'] ? 'Site enabled.' : 'Failed to enable site.',
                ])
                ->response()
                ->json();

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'error' => ['code' => 'ENABLE_FAILED', 'message' => $e->getMessage()],
            ], 500);
        }
    }

    /**
     * Disable a site.
     */
    public function disable(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        $this->authorize('disable', $site);

        if ($site->status === 'disabled') {
            return (new SiteResource($site))
                ->additional([
                    'message' => 'Site is already disabled.',
                ])
                ->response()
                ->json();
        }

        try {
            $result = $this->vpsManager->disableSite($site->vpsServer, $site->domain);

            if ($result['success']) {
                $site->update(['status' => 'disabled']);
            }

            return (new SiteResource($site->fresh()))
                ->additional([
                    'message' => $result['success'] ? 'Site disabled.' : 'Failed to disable site.',
                ])
                ->response()
                ->json();

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'error' => ['code' => 'DISABLE_FAILED', 'message' => $e->getMessage()],
            ], 500);
        }
    }

    /**
     * Issue SSL certificate.
     */
    public function issueSSL(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        $this->authorize('issueSSL', $site);

        if (! $site->vpsServer) {
            return response()->json([
                'success' => false,
                'error' => ['code' => 'NO_VPS', 'message' => 'Site has no associated VPS server.'],
            ], 400);
        }

        try {
            // Dispatch async job to issue SSL certificate
            IssueSslCertificateJob::dispatch($site);

            return (new SiteResource($site))
                ->additional([
                    'message' => 'SSL certificate issuance started.',
                ])
                ->response()
                ->setStatusCode(202) // 202 Accepted for async operations
                ->json();

        } catch (\Exception $e) {
            Log::error('SSL issuance dispatch failed', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => ['code' => 'SSL_FAILED', 'message' => $e->getMessage()],
            ], 500);
        }
    }

    /**
     * Get site metrics.
     *
     * Returns site performance and resource usage metrics.
     * Returns mock data until ObservabilityAdapter is integrated.
     * Data structure matches expected format for seamless adapter integration.
     */
    public function metrics(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        $this->authorize('view', $site);

        // Generate realistic metrics data based on site type and status
        // Data varies by site type (WordPress tends to have different patterns than static sites)

        $isActive = $site->status === 'active';
        $siteTypeMultiplier = match($site->site_type) {
            'wordpress' => 1.5,  // WordPress sites typically have more traffic
            'laravel' => 1.3,    // Laravel apps have moderate traffic
            'static' => 0.6,     // Static sites have lower resource usage
            default => 1.0,
        };

        // Request metrics (higher for active sites)
        $baseRequests = $isActive ? rand(5000, 50000) : rand(0, 100);
        $totalRequests = (int) round($baseRequests * $siteTypeMultiplier);
        $perMinute = $isActive ? round($totalRequests / 1440, 2) : 0; // 24h = 1440 minutes
        $successfulRequests = (int) round($totalRequests * (rand(95, 99) / 100));
        $failedRequests = $totalRequests - $successfulRequests;

        // Performance metrics (WordPress typically slower, static sites faster)
        $baseResponseTime = match($site->site_type) {
            'wordpress' => rand(180, 450),
            'laravel' => rand(120, 300),
            'static' => rand(20, 80),
            default => rand(100, 250),
        };
        $avgResponseTime = $isActive ? $baseResponseTime : 0;
        $p95ResponseTime = $isActive ? (int) round($avgResponseTime * rand(150, 250) / 100) : 0;
        $p99ResponseTime = $isActive ? (int) round($p95ResponseTime * rand(130, 180) / 100) : 0;

        // Resource usage
        $storageUsed = $site->storage_used_mb ?? rand(50, 2000);
        $bandwidthUsed = $isActive ? round($totalRequests * rand(150, 800) / 1000, 2) : 0; // KB per request
        $cpuAvgPercent = $isActive ? round(rand(5, 35) * $siteTypeMultiplier, 2) : 0;
        $memoryAvgMb = $isActive ? (int) round(rand(64, 512) * $siteTypeMultiplier) : 0;

        // Uptime metrics
        $uptimePercent = match($site->status) {
            'active' => round(99.0 + rand(0, 99) / 100, 2),
            'disabled' => 0.0,
            default => round(rand(80, 95) + rand(0, 99) / 100, 2),
        };
        $totalDowntimeMinutes = $isActive ? rand(0, 15) : 1440; // Max 15 min downtime for active sites

        return response()->json([
            'success' => true,
            'data' => [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'site_type' => $site->site_type,
                'period' => '24h',
                'timestamp' => now()->toIso8601String(),
                'metrics' => [
                    'requests' => [
                        'total' => $totalRequests,
                        'per_minute' => $perMinute,
                        'successful' => $successfulRequests,
                        'failed' => $failedRequests,
                    ],
                    'performance' => [
                        'avg_response_time_ms' => $avgResponseTime,
                        'p95_response_time_ms' => $p95ResponseTime,
                        'p99_response_time_ms' => $p99ResponseTime,
                    ],
                    'resources' => [
                        'storage_used_mb' => $storageUsed,
                        'bandwidth_used_mb' => $bandwidthUsed,
                        'cpu_avg_percent' => $cpuAvgPercent,
                        'memory_avg_mb' => $memoryAvgMb,
                    ],
                    'uptime' => [
                        'percentage' => $uptimePercent,
                        'total_downtime_minutes' => $totalDowntimeMinutes,
                    ],
                ],
            ],
        ]);
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /**
     * Find an available VPS server for site provisioning.
     *
     * Performance Optimization:
     * - Uses withCount() instead of orderByRaw subquery to eliminate N+1 query
     * - Eager loads VPS relationship to reduce total queries
     * - Prioritizes existing tenant allocations before searching shared pool
     *
     * @param  mixed  $tenant  The tenant requiring VPS allocation
     * @return VpsServer|null Available VPS server or null if none found
     */
    private function findAvailableVps($tenant): ?VpsServer
    {
        // First check if tenant has existing allocation
        $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();

        if ($allocation && $allocation->vpsServer->isAvailable()) {
            return $allocation->vpsServer;
        }

        // Find shared VPS with capacity
        // Use withCount() instead of orderByRaw() to avoid N+1 query problem
        // This generates: SELECT *, (SELECT COUNT(*) FROM sites WHERE sites.vps_id = vps_servers.id) as sites_count
        return VpsServer::active()
            ->shared()
            ->healthy()
            ->withCount('sites')
            ->orderBy('sites_count', 'ASC')
            ->first();
    }
}
