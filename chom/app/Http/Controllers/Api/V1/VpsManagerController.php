<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Site;
use App\Models\VpsServer;
use App\Repositories\SiteRepository;
use App\Repositories\VpsServerRepository;
use App\Services\VpsManagerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

/**
 * VPS Manager Controller
 *
 * Handles VPSManager operations through SSH command execution.
 * VPSManager is a bash-based CLI tool at /opt/vpsmanager/bin/vpsmanager
 * that provides SSL, database, cache, and monitoring operations.
 *
 * All operations enforce tenant isolation through policies and repository patterns.
 *
 * @package App\Http\Controllers\Api\V1
 */
class VpsManagerController extends ApiController
{
    public function __construct(
        private readonly VpsManagerService $vpsManagerService,
        private readonly SiteRepository $siteRepository,
        private readonly VpsServerRepository $vpsServerRepository
    ) {}

    /**
     * Issue SSL certificate for a site.
     *
     * POST /api/v1/sites/{site}/ssl/issue
     *
     * @param Request $request
     * @param string $siteId Site UUID
     * @return JsonResponse
     */
    public function issueSSL(Request $request, string $siteId): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $site = $this->siteRepository->findByIdAndTenant($siteId, $tenant->id);

            // Authorize action
            Gate::authorize('manageSSL', $site);

            $this->logInfo('Issuing SSL certificate', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            $result = $this->vpsManagerService->issueSSL($site);

            if (!$result['success']) {
                return $this->errorResponse(
                    'SSL_ISSUE_FAILED',
                    'Failed to issue SSL certificate.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse(
                [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'status' => 'issued',
                    'details' => $result['parsed'],
                ],
                'SSL certificate is being issued.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Renew SSL certificate for a site.
     *
     * POST /api/v1/sites/{site}/ssl/renew
     *
     * @param Request $request
     * @param string $siteId Site UUID
     * @return JsonResponse
     */
    public function renewSSL(Request $request, string $siteId): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $site = $this->siteRepository->findByIdAndTenant($siteId, $tenant->id);

            // Authorize action
            Gate::authorize('manageSSL', $site);

            $this->logInfo('Renewing SSL certificate', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            $result = $this->vpsManagerService->renewSSL($site);

            if (!$result['success']) {
                return $this->errorResponse(
                    'SSL_RENEW_FAILED',
                    'Failed to renew SSL certificate.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse(
                [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'status' => 'renewed',
                    'details' => $result['parsed'],
                ],
                'SSL certificate renewed successfully.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Get SSL certificate status for a site.
     *
     * GET /api/v1/sites/{site}/ssl/status
     *
     * @param Request $request
     * @param string $siteId Site UUID
     * @return JsonResponse
     */
    public function getSSLStatus(Request $request, string $siteId): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $site = $this->siteRepository->findByIdAndTenant($siteId, $tenant->id);

            // Authorize action
            Gate::authorize('view', $site);

            $this->logInfo('Getting SSL status', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            $result = $this->vpsManagerService->getSSLStatus($site);

            if (!$result['success']) {
                return $this->errorResponse(
                    'SSL_STATUS_FAILED',
                    'Failed to retrieve SSL status.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse([
                'site_id' => $site->id,
                'domain' => $site->domain,
                'ssl_status' => $result['parsed'],
            ]);
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Export database for a site.
     *
     * POST /api/v1/sites/{site}/database/export
     *
     * @param Request $request
     * @param string $siteId Site UUID
     * @return JsonResponse
     */
    public function exportDatabase(Request $request, string $siteId): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $site = $this->siteRepository->findByIdAndTenant($siteId, $tenant->id);

            // Authorize action (members can export databases)
            Gate::authorize('update', $site);

            $this->logInfo('Exporting database', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'db_name' => $site->db_name,
            ]);

            $result = $this->vpsManagerService->exportDatabase($site);

            if (!$result['success']) {
                return $this->errorResponse(
                    'DATABASE_EXPORT_FAILED',
                    'Failed to export database.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse(
                [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'export_details' => $result['parsed'],
                ],
                'Database export completed successfully.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Optimize database for a site.
     *
     * POST /api/v1/sites/{site}/database/optimize
     *
     * @param Request $request
     * @param string $siteId Site UUID
     * @return JsonResponse
     */
    public function optimizeDatabase(Request $request, string $siteId): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $site = $this->siteRepository->findByIdAndTenant($siteId, $tenant->id);

            // Authorize action
            Gate::authorize('update', $site);

            $this->logInfo('Optimizing database', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'db_name' => $site->db_name,
            ]);

            $result = $this->vpsManagerService->optimizeDatabase($site);

            if (!$result['success']) {
                return $this->errorResponse(
                    'DATABASE_OPTIMIZE_FAILED',
                    'Failed to optimize database.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse(
                [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'optimization_details' => $result['parsed'],
                ],
                'Database optimized successfully.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Clear cache for a site.
     *
     * POST /api/v1/sites/{site}/cache/clear
     *
     * @param Request $request
     * @param string $siteId Site UUID
     * @return JsonResponse
     */
    public function clearCache(Request $request, string $siteId): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);
            $site = $this->siteRepository->findByIdAndTenant($siteId, $tenant->id);

            // Authorize action
            Gate::authorize('update', $site);

            $this->logInfo('Clearing cache', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            $result = $this->vpsManagerService->clearCache($site);

            if (!$result['success']) {
                return $this->errorResponse(
                    'CACHE_CLEAR_FAILED',
                    'Failed to clear cache.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse(
                [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'cache_details' => $result['parsed'],
                ],
                'Cache cleared successfully.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Get VPS health status.
     *
     * GET /api/v1/vps/{vps}/health
     *
     * @param Request $request
     * @param string $vpsId VPS UUID
     * @return JsonResponse
     */
    public function getVpsHealth(Request $request, string $vpsId): JsonResponse
    {
        try {
            $vps = $this->vpsServerRepository->findById($vpsId);

            if (!$vps) {
                return $this->notFoundResponse('vps', 'VPS server not found.');
            }

            // Authorize action - use VpsPolicy
            Gate::authorize('view', $vps);

            $this->logInfo('Getting VPS health', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
            ]);

            $result = $this->vpsManagerService->getVpsHealth($vps);

            if (!$result['success']) {
                return $this->errorResponse(
                    'VPS_HEALTH_CHECK_FAILED',
                    'Failed to retrieve VPS health status.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse([
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'health' => $result['parsed'],
            ]);
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Get VPS statistics.
     *
     * GET /api/v1/vps/{vps}/stats
     *
     * @param Request $request
     * @param string $vpsId VPS UUID
     * @return JsonResponse
     */
    public function getVpsStats(Request $request, string $vpsId): JsonResponse
    {
        try {
            $vps = $this->vpsServerRepository->findById($vpsId);

            if (!$vps) {
                return $this->notFoundResponse('vps', 'VPS server not found.');
            }

            // Authorize action - use VpsPolicy
            Gate::authorize('view', $vps);

            $this->logInfo('Getting VPS stats', [
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
            ]);

            $result = $this->vpsManagerService->getVpsStats($vps);

            if (!$result['success']) {
                return $this->errorResponse(
                    'VPS_STATS_FAILED',
                    'Failed to retrieve VPS statistics.',
                    [
                        'output' => $result['output'],
                        'error_output' => $result['error_output'],
                        'exit_code' => $result['exit_code'],
                    ],
                    500
                );
            }

            return $this->successResponse([
                'vps_id' => $vps->id,
                'hostname' => $vps->hostname,
                'stats' => $result['parsed'],
            ]);
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
