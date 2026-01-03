<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\StoreBackupRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Backup Controller
 *
 * Handles backup management operations:
 * - List backups (all or for specific site)
 * - Create new backup
 * - View backup details
 * - Download backup
 * - Restore from backup
 * - Delete backup
 *
 * @package App\Http\Controllers\Api\V1
 */
class BackupController extends ApiController
{
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

            // Build query
            $query = \App\Models\SiteBackup::whereHas('site', function ($q) use ($tenant) {
                $q->where('tenant_id', $tenant->id);
            })->with(['site:id,domain']);

            // Filter by site if provided
            if ($request->filled('site_id')) {
                $query->where('site_id', $request->input('site_id'));
            }

            // Apply common filters
            $this->applyFilters($query, $request);

            // Paginate
            $backups = $query->paginate($this->getPaginationLimit($request));

            return $this->paginatedResponse($backups);

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
            // Validate site access
            $site = $this->validateTenantAccess(
                $request,
                $siteId,
                \App\Models\Site::class
            );

            // Get backups for this site
            $backups = $site->backups()
                ->orderBy('created_at', 'desc')
                ->paginate($this->getPaginationLimit($request));

            return $this->paginatedResponse($backups);

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
            $validated = $request->validated();

            $site = $this->validateTenantAccess(
                $request,
                $validated['site_id'],
                \App\Models\Site::class
            );

            $this->logInfo('Backup creation initiated', [
                'site_id' => $site->id,
                'backup_type' => $validated['backup_type'],
            ]);

            return $this->createdResponse(
                ['site_id' => $site->id, 'status' => 'pending'],
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

            // Find backup and validate access
            $backup = \App\Models\SiteBackup::with('site')->findOrFail($id);

            if ($backup->site->tenant_id !== $tenant->id) {
                abort(403, 'You do not have access to this backup.');
            }

            return $this->successResponse($backup);

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

            // Find backup and validate access
            $backup = \App\Models\SiteBackup::with('site')->findOrFail($id);

            if ($backup->site->tenant_id !== $tenant->id) {
                abort(403, 'You do not have access to this backup.');
            }

            // TODO: Implement download logic
            // return Storage::download($backup->file_path);

            $this->logInfo('Backup download initiated', ['backup_id' => $id]);

            return $this->errorResponse(
                'NOT_IMPLEMENTED',
                'Backup download not yet implemented.',
                [],
                501
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

            // Find backup and validate access
            $backup = \App\Models\SiteBackup::with('site')->findOrFail($id);

            if ($backup->site->tenant_id !== $tenant->id) {
                abort(403, 'You do not have access to this backup.');
            }

            // TODO: Implement restore logic
            // This would typically:
            // 1. Validate backup integrity
            // 2. Dispatch restore job
            // 3. Return job status

            $this->logInfo('Backup restore initiated', [
                'backup_id' => $id,
                'site_id' => $backup->site_id,
            ]);

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

            // Find backup and validate access
            $backup = \App\Models\SiteBackup::with('site')->findOrFail($id);

            if ($backup->site->tenant_id !== $tenant->id) {
                abort(403, 'You do not have access to this backup.');
            }

            // TODO: Implement backup deletion logic
            // $backup->delete();

            $this->logInfo('Backup deleted', ['backup_id' => $id]);

            return $this->successResponse(
                ['id' => $id],
                'Backup deleted successfully.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
