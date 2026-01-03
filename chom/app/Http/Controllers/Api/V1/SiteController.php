<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\StoreSiteRequest;
use App\Http\Requests\UpdateSiteRequest;
use App\Http\Resources\SiteResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Site Controller
 *
 * Handles all site management operations:
 * - List sites with filtering/pagination
 * - Create new sites
 * - View site details
 * - Update site configuration
 * - Delete sites
 * - Enable/disable sites
 * - Issue SSL certificates
 * - View site metrics
 *
 * @package App\Http\Controllers\Api\V1
 */
class SiteController extends ApiController
{
    /**
     * List all sites for the current tenant.
     *
     * Supports filtering by:
     * - status: Filter by site status (active, disabled, creating)
     * - type: Filter by site type (wordpress, laravel, html)
     * - search: Search by domain name
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);

            // Build query with relationships
            $query = $tenant->sites()
                ->with('vpsServer:id,hostname,ip_address');

            // Apply common filters
            $this->applyFilters($query, $request);

            // Apply site-specific filters
            if ($request->filled('type')) {
                $query->where('site_type', $request->input('type'));
            }

            if ($request->filled('search')) {
                $query->where('domain', 'like', '%' . $request->input('search') . '%');
            }

            // Paginate results
            $sites = $query->paginate($this->getPaginationLimit($request));

            // Transform using SiteResource
            return $this->paginatedResponse(
                $sites,
                fn($site) => new SiteResource($site)
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Create a new site.
     *
     * @param StoreSiteRequest $request
     * @return JsonResponse
     */
    public function store(StoreSiteRequest $request): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $validated = $request->validated();

            $this->logInfo('Site creation initiated', [
                'domain' => $validated['domain'],
                'tenant_id' => $tenant->id,
            ]);

            return $this->createdResponse(
                ['domain' => $validated['domain'], 'status' => 'creating'],
                'Site is being created.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Show a specific site.
     *
     * @param Request $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function show(Request $request, string $id): JsonResponse
    {
        try {
            // Validate tenant access and get site
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            // Load relationships
            $site->load(['vpsServer', 'backups' => fn($q) => $q->latest()->limit(5)]);

            return $this->successResponse(new SiteResource($site));

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Update a site.
     *
     * @param UpdateSiteRequest $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function update(UpdateSiteRequest $request, string $id): JsonResponse
    {
        try {
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            $validated = $request->validated();

            $this->logInfo('Site updated', [
                'site_id' => $id,
                'changes' => $validated,
            ]);

            return $this->successResponse(
                new SiteResource($site),
                'Site updated successfully.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Delete a site.
     *
     * @param Request $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        try {
            // Validate tenant access
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            // TODO: Implement site deletion logic
            // This would typically:
            // 1. Backup site data
            // 2. Delete from VPS
            // 3. Soft delete record

            $this->logInfo('Site deletion initiated', [
                'site_id' => $id,
                'domain' => $site->domain,
            ]);

            return $this->successResponse(
                ['id' => $id],
                'Site is being deleted.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Enable a site.
     *
     * @param Request $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function enable(Request $request, string $id): JsonResponse
    {
        try {
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            // TODO: Implement site enable logic

            return $this->successResponse(
                new SiteResource($site),
                'Site enabled successfully.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Disable a site.
     *
     * @param Request $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function disable(Request $request, string $id): JsonResponse
    {
        try {
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            // TODO: Implement site disable logic

            return $this->successResponse(
                new SiteResource($site),
                'Site disabled successfully.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Issue SSL certificate for a site.
     *
     * @param Request $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function issueSSL(Request $request, string $id): JsonResponse
    {
        try {
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            // TODO: Implement SSL issuance logic

            $this->logInfo('SSL certificate issuance initiated', [
                'site_id' => $id,
                'domain' => $site->domain,
            ]);

            return $this->successResponse(
                new SiteResource($site),
                'SSL certificate is being issued.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Get site metrics.
     *
     * @param Request $request
     * @param string $id Site ID
     * @return JsonResponse
     */
    public function metrics(Request $request, string $id): JsonResponse
    {
        try {
            $site = $this->validateTenantAccess(
                $request,
                $id,
                \App\Models\Site::class
            );

            // TODO: Implement metrics retrieval logic
            $metrics = [
                'storage_used_mb' => $site->storage_used_mb ?? 0,
                'bandwidth_used_gb' => 0,
                'uptime_percentage' => 99.9,
            ];

            return $this->successResponse($metrics);

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
