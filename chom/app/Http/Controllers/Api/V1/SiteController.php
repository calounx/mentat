<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;

class SiteController extends Controller
{
    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {}

    /**
     * List all sites for the current tenant.
     */
    public function index(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $query = $tenant->sites()
            ->with('vpsServer:id,hostname,ip_address')
            ->orderBy('created_at', 'desc');

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
            $query->where('domain', 'like', '%' . $request->input('search') . '%');
        }

        $sites = $query->paginate($request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => $sites->items(),
            'meta' => [
                'pagination' => [
                    'current_page' => $sites->currentPage(),
                    'per_page' => $sites->perPage(),
                    'total' => $sites->total(),
                    'total_pages' => $sites->lastPage(),
                ],
            ],
        ]);
    }

    /**
     * Create a new site.
     */
    public function store(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        // Check quota
        if (!$tenant->canCreateSite()) {
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

        $validated = $request->validate([
            'domain' => [
                'required',
                'string',
                'max:253',
                'regex:/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i',
                Rule::unique('sites')->where('tenant_id', $tenant->id),
            ],
            'site_type' => ['sometimes', 'in:wordpress,html,laravel'],
            'php_version' => ['sometimes', 'in:8.2,8.4'],
            'ssl_enabled' => ['sometimes', 'boolean'],
        ]);

        try {
            $site = DB::transaction(function () use ($validated, $tenant) {
                // Find available VPS
                $vps = $this->findAvailableVps($tenant);

                if (!$vps) {
                    throw new \RuntimeException('No available VPS server found');
                }

                // Create site record
                $site = Site::create([
                    'tenant_id' => $tenant->id,
                    'vps_id' => $vps->id,
                    'domain' => strtolower($validated['domain']),
                    'site_type' => $validated['site_type'] ?? 'wordpress',
                    'php_version' => $validated['php_version'] ?? '8.2',
                    'ssl_enabled' => $validated['ssl_enabled'] ?? true,
                    'status' => 'creating',
                ]);

                return $site;
            });

            // Dispatch async job to provision site on VPS
            ProvisionSiteJob::dispatch($site);

            return response()->json([
                'success' => true,
                'data' => $this->formatSite($site),
                'message' => 'Site is being created.',
            ], 201);

        } catch (\Exception $e) {
            Log::error('Site creation failed', [
                'domain' => $validated['domain'],
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
    public function show(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $site = $tenant->sites()
            ->with(['vpsServer', 'backups' => fn($q) => $q->latest()->limit(5)])
            ->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $this->formatSite($site, detailed: true),
        ]);
    }

    /**
     * Update site settings.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->findOrFail($id);

        $validated = $request->validate([
            'php_version' => ['sometimes', 'in:8.2,8.4'],
            'settings' => ['sometimes', 'array'],
        ]);

        $site->update($validated);

        return response()->json([
            'success' => true,
            'data' => $this->formatSite($site),
            'message' => 'Site updated successfully.',
        ]);
    }

    /**
     * Delete a site.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        try {
            // Delete from VPS
            if ($site->vpsServer && $site->status === 'active') {
                $result = $this->vpsManager->deleteSite($site->vpsServer, $site->domain, force: true);

                if (!$result['success']) {
                    Log::warning('VPS site deletion failed', [
                        'site' => $site->domain,
                        'output' => $result['output'],
                    ]);
                }
            }

            // Soft delete
            $site->delete();

            return response()->json([
                'success' => true,
                'message' => 'Site deleted successfully.',
            ]);

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

        if ($site->status === 'active') {
            return response()->json([
                'success' => true,
                'message' => 'Site is already enabled.',
            ]);
        }

        try {
            $result = $this->vpsManager->enableSite($site->vpsServer, $site->domain);

            if ($result['success']) {
                $site->update(['status' => 'active']);
            }

            return response()->json([
                'success' => $result['success'],
                'data' => $this->formatSite($site->fresh()),
                'message' => $result['success'] ? 'Site enabled.' : 'Failed to enable site.',
            ]);

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

        if ($site->status === 'disabled') {
            return response()->json([
                'success' => true,
                'message' => 'Site is already disabled.',
            ]);
        }

        try {
            $result = $this->vpsManager->disableSite($site->vpsServer, $site->domain);

            if ($result['success']) {
                $site->update(['status' => 'disabled']);
            }

            return response()->json([
                'success' => $result['success'],
                'data' => $this->formatSite($site->fresh()),
                'message' => $result['success'] ? 'Site disabled.' : 'Failed to disable site.',
            ]);

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

        if (!$site->vpsServer) {
            return response()->json([
                'success' => false,
                'error' => ['code' => 'NO_VPS', 'message' => 'Site has no associated VPS server.'],
            ], 400);
        }

        try {
            // Dispatch async job to issue SSL certificate
            IssueSslCertificateJob::dispatch($site);

            return response()->json([
                'success' => true,
                'data' => $this->formatSite($site),
                'message' => 'SSL certificate issuance started.',
            ]);

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
     */
    public function metrics(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->with('vpsServer')->findOrFail($id);

        // TODO: Integrate with ObservabilityAdapter
        return response()->json([
            'success' => true,
            'data' => [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'metrics' => [
                    'requests_per_minute' => 0,
                    'response_time_ms' => 0,
                    'storage_used_mb' => $site->storage_used_mb,
                ],
            ],
        ]);
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

    private function findAvailableVps(Tenant $tenant): ?VpsServer
    {
        // First check if tenant has existing allocation
        $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();

        if ($allocation && $allocation->vpsServer->isAvailable()) {
            return $allocation->vpsServer;
        }

        // Find shared VPS with capacity
        return VpsServer::active()
            ->shared()
            ->healthy()
            ->orderByRaw('(SELECT COUNT(*) FROM sites WHERE vps_id = vps_servers.id) ASC')
            ->first();
    }

    private function formatSite(Site $site, bool $detailed = false): array
    {
        $data = [
            'id' => $site->id,
            'domain' => $site->domain,
            'url' => $site->getUrl(),
            'site_type' => $site->site_type,
            'php_version' => $site->php_version,
            'ssl_enabled' => $site->ssl_enabled,
            'ssl_expires_at' => $site->ssl_expires_at?->toIso8601String(),
            'status' => $site->status,
            'storage_used_mb' => $site->storage_used_mb,
            'created_at' => $site->created_at->toIso8601String(),
            'updated_at' => $site->updated_at->toIso8601String(),
        ];

        if ($site->relationLoaded('vpsServer') && $site->vpsServer) {
            $data['vps'] = [
                'id' => $site->vpsServer->id,
                'hostname' => $site->vpsServer->hostname,
            ];
        }

        if ($detailed) {
            $data['db_name'] = $site->db_name;
            $data['document_root'] = $site->document_root;
            $data['settings'] = $site->settings;

            if ($site->relationLoaded('backups')) {
                $data['recent_backups'] = $site->backups->map(fn($b) => [
                    'id' => $b->id,
                    'type' => $b->backup_type,
                    'size' => $b->getSizeFormatted(),
                    'created_at' => $b->created_at->toIso8601String(),
                ])->toArray();
            }
        }

        return $data;
    }
}
