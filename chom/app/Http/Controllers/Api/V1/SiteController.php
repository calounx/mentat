<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\StoreSiteRequest;
use App\Http\Requests\UpdateSiteRequest;
use App\Http\Resources\SiteResource;
use App\Repositories\SiteRepository;
use App\Services\QuotaService;
use App\Services\SiteManagementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Site Controller
 *
 * Handles all site management operations through repository and service patterns.
 * Controllers are kept thin - business logic delegated to services.
 *
 * @package App\Http\Controllers\Api\V1
 */
class SiteController extends ApiController
{
    public function __construct(
        private readonly SiteRepository $siteRepository,
        private readonly SiteManagementService $siteManagementService,
        private readonly QuotaService $quotaService
    ) {}

    /**
     * List all sites for the current tenant.
     *
     * Supports filtering by status, type, and search.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);

            $filters = [
                'status' => $request->input('status'),
                'site_type' => $request->input('type'),
                'search' => $request->input('search'),
            ];

            $sites = $this->siteRepository->findByTenant(
                $tenant->id,
                $filters,
                $this->getPaginationLimit($request)
            );

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

            $site = $this->siteManagementService->provisionSite(
                $request->validated(),
                $tenant->id
            );

            return $this->createdResponse(
                new SiteResource($site),
                'Site is being provisioned.'
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
            $tenant = $this->getTenant($request);

            $site = $this->siteRepository->findByIdAndTenant($id, $tenant->id);

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
            $tenant = $this->getTenant($request);

            $this->siteRepository->findByIdAndTenant($id, $tenant->id);

            $site = $this->siteManagementService->updateSiteConfiguration(
                $id,
                $request->validated()
            );

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
            $tenant = $this->getTenant($request);

            $this->siteRepository->findByIdAndTenant($id, $tenant->id);

            $this->siteManagementService->deleteSite($id);

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
            $tenant = $this->getTenant($request);

            $this->siteRepository->findByIdAndTenant($id, $tenant->id);

            $site = $this->siteManagementService->enableSite($id);

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
            $tenant = $this->getTenant($request);

            $this->siteRepository->findByIdAndTenant($id, $tenant->id);

            $site = $this->siteManagementService->disableSite($id);

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
            $tenant = $this->getTenant($request);

            $this->siteRepository->findByIdAndTenant($id, $tenant->id);

            $site = $this->siteManagementService->enableSSL($id);

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
            $tenant = $this->getTenant($request);

            $this->siteRepository->findByIdAndTenant($id, $tenant->id);

            $metrics = $this->siteManagementService->getSiteMetrics($id);

            return $this->successResponse($metrics);
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Get site-to-tenant mappings for observability exporters.
     *
     * Returns all sites with their tenant_id and organization_id.
     * This endpoint is used by Prometheus exporters to add proper labels.
     * Owner role only.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function tenantMappings(Request $request): JsonResponse
    {
        try {
            // Verify user is owner
            $this->requireOwner($request);

            // Get all sites with tenant and organization relationships
            $sites = \App\Models\Site::with(['tenant.organization'])
                ->select(['id', 'domain', 'tenant_id', 'vps_id'])
                ->get()
                ->map(function ($site) {
                    return [
                        'domain' => $site->domain,
                        'tenant_id' => $site->tenant_id,
                        'organization_id' => $site->tenant?->organization_id,
                        'vps_id' => $site->vps_id,
                    ];
                });

            return $this->successResponse([
                'sites' => $sites,
            ]);
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
