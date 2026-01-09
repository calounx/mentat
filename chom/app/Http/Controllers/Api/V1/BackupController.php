<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\StoreBackupRequest;
use App\Http\Resources\BackupResource;
use App\Repositories\BackupRepository;
use App\Services\BackupService;
use App\Services\QuotaService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * Backup Controller
 *
 * Handles backup management operations through repository and service patterns.
 * Controllers are kept thin - business logic delegated to services.
 *
 * @package App\Http\Controllers\Api\V1
 */
class BackupController extends ApiController
{
    public function __construct(
        private readonly BackupRepository $backupRepository,
        private readonly BackupService $backupService,
        private readonly QuotaService $quotaService
    ) {}

    /**
     * List all backups for the current tenant.
     *
     * Optionally filter by site_id.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);

            $filters = [
                'site_id' => $request->input('site_id'),
                'status' => $request->input('status'),
                'type' => $request->input('type'),
            ];

            $backups = $this->backupRepository->findByTenant(
                $tenant->id,
                $filters,
                $this->getPaginationLimit($request)
            );

            return $this->paginatedResponse(
                $backups,
                fn($backup) => new BackupResource($backup)
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * List backups for a specific site.
     *
     * @param Request $request
     * @param string $siteId
     * @return JsonResponse
     */
    public function indexForSite(Request $request, string $siteId): JsonResponse
    {
        try {
            $this->validateTenantAccess($request, $siteId, \App\Models\Site::class);

            $backups = $this->backupRepository->findBySite(
                $siteId,
                $this->getPaginationLimit($request)
            );

            return $this->paginatedResponse(
                $backups,
                fn($backup) => new BackupResource($backup)
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Create a new backup.
     *
     * @param StoreBackupRequest $request
     * @return JsonResponse
     */
    public function store(StoreBackupRequest $request): JsonResponse
    {
        try {
            $this->validateTenantAccess(
                $request,
                $request->validated()['site_id'],
                \App\Models\Site::class
            );

            $backup = $this->backupService->createBackup(
                $request->validated()['site_id'],
                $request->validated()['backup_type'] ?? 'full'
            );

            return $this->createdResponse(
                new BackupResource($backup),
                'Backup is being created.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Show backup details.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function show(Request $request, string $id): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);

            $backup = $this->backupRepository->findByIdAndTenant($id, $tenant->id);

            if (!$backup) {
                abort(404, 'Backup not found.');
            }

            return $this->successResponse(new BackupResource($backup));
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Download a backup.
     *
     * @param Request $request
     * @param string $id
     * @return mixed
     */
    public function download(Request $request, string $id)
    {
        try {
            $tenant = $this->getTenant($request);

            $backup = $this->backupRepository->findByIdAndTenant($id, $tenant->id);

            if (!$backup) {
                abort(404, 'Backup not found.');
            }

            if ($backup->status !== 'completed' || !$backup->file_path) {
                return $this->errorResponse(
                    'BACKUP_NOT_READY',
                    'Backup is not ready for download.',
                    [],
                    400
                );
            }

            if (!Storage::exists($backup->file_path)) {
                return $this->errorResponse(
                    'FILE_NOT_FOUND',
                    'Backup file not found.',
                    [],
                    404
                );
            }

            $this->logInfo('Backup download initiated', ['backup_id' => $id]);

            return Storage::download(
                $backup->file_path,
                basename($backup->file_path)
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Restore from a backup.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function restore(Request $request, string $id): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);

            $backup = $this->backupRepository->findByIdAndTenant($id, $tenant->id);

            if (!$backup) {
                abort(404, 'Backup not found.');
            }

            $this->backupService->restoreBackup($id);

            return $this->successResponse(
                ['backup_id' => $id, 'status' => 'restoring'],
                'Backup restore is in progress.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Delete a backup.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        try {
            $tenant = $this->getTenant($request);

            $backup = $this->backupRepository->findByIdAndTenant($id, $tenant->id);

            if (!$backup) {
                abort(404, 'Backup not found.');
            }

            $this->backupService->deleteBackup($id);

            return $this->successResponse(
                ['id' => $id],
                'Backup deleted successfully.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
