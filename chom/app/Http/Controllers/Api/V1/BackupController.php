<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Concerns\HasTenantScoping;
use App\Http\Controllers\Controller;
use App\Http\Requests\V1\Backups\CreateBackupRequest;
use App\Http\Requests\V1\Backups\RestoreBackupRequest;
use App\Http\Resources\V1\BackupCollection;
use App\Http\Resources\V1\BackupResource;
use App\Jobs\CreateBackupJob;
use App\Jobs\RestoreBackupJob;
use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class BackupController extends Controller
{
    use HasTenantScoping;

    /**
     * List all backups for the current tenant.
     *
     * Supports filtering by site_id, type, and status.
     * Returns paginated collection with metadata.
     */
    public function index(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $query = SiteBackup::query()
            ->whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->with('site:id,domain,site_type')
            ->orderBy('created_at', 'desc');

        // Filter by site
        if ($request->filled('site_id')) {
            $query->where('site_id', $request->input('site_id'));
        }

        // Filter by backup type
        if ($request->filled('type')) {
            $query->where('backup_type', $request->input('type'));
        }

        // Filter by status
        if ($request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        $backups = $query->paginate($request->input('per_page', 20));

        return (new BackupCollection($backups))->response()->setStatusCode(200);
    }

    /**
     * List backups for a specific site.
     */
    public function indexForSite(Request $request, string $siteId): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $site = $tenant->sites()->findOrFail($siteId);

        $backups = $site->backups()
            ->orderBy('created_at', 'desc')
            ->paginate($request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => collect($backups->items())->map(fn ($backup) => $this->formatBackup($backup)),
            'meta' => [
                'pagination' => [
                    'current_page' => $backups->currentPage(),
                    'per_page' => $backups->perPage(),
                    'total' => $backups->total(),
                    'total_pages' => $backups->lastPage(),
                ],
            ],
        ]);
    }

    /**
     * Get backup details.
     *
     * Returns a single backup with full site relationship.
     * Checks tenant authorization via global scope.
     */
    public function show(Request $request, SiteBackup $backup): JsonResponse
    {
        $tenant = $this->getTenant($request);

        // Verify backup belongs to tenant
        if ($backup->site->tenant_id !== $tenant->id) {
            abort(403, 'Unauthorized access to this backup.');
        }

        // Load site relationship if not already loaded
        $backup->loadMissing('site:id,domain,site_type,status');

        return (new BackupResource($backup))->response()->setStatusCode(200);
    }

    /**
     * Create a new backup.
     *
     * Validates input, dispatches CreateBackupJob, and returns pending backup.
     * Returns 202 Accepted status to indicate async processing.
     */
    public function store(CreateBackupRequest $request): JsonResponse
    {
        $site = $request->site();
        $validated = $request->validated();

        try {
            // Dispatch backup job (job creates the backup record)
            CreateBackupJob::dispatch(
                $site,
                $validated['backup_type'] ?? 'full',
                $validated['retention_days'] ?? null
            );

            Log::info('Backup job dispatched', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'backup_type' => $validated['backup_type'] ?? 'full',
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Backup has been queued for processing.',
                'data' => [
                    'site_id' => $site->id,
                    'backup_type' => $validated['backup_type'] ?? 'full',
                    'status' => 'pending',
                ],
            ], 202);

        } catch (\Exception $e) {
            Log::error('Backup creation failed', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_CREATION_FAILED',
                    'message' => 'Failed to create backup. Please try again.',
                ],
            ], 500);
        }
    }

    /**
     * Delete a backup.
     *
     * Removes backup record and optionally deletes backup file from storage.
     * Returns 204 No Content on success.
     */
    public function destroy(Request $request, SiteBackup $backup): JsonResponse
    {
        $tenant = $this->getTenant($request);

        // Verify backup belongs to tenant
        if ($backup->site->tenant_id !== $tenant->id) {
            abort(403, 'Unauthorized access to this backup.');
        }

        try {
            // Delete from storage if exists
            if ($backup->storage_path && Storage::exists($backup->storage_path)) {
                Storage::delete($backup->storage_path);
                Log::info('Backup file deleted from storage', [
                    'backup_id' => $backup->id,
                    'storage_path' => $backup->storage_path,
                ]);
            }

            $backupId = $backup->id;
            $backup->delete();

            Log::info('Backup deleted successfully', [
                'backup_id' => $backupId,
            ]);

            return response()->json(null, 204);

        } catch (\Exception $e) {
            Log::error('Backup deletion failed', [
                'backup_id' => $backup->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_DELETION_FAILED',
                    'message' => 'Failed to delete backup.',
                ],
            ], 500);
        }
    }

    /**
     * Download a backup file.
     *
     * CRITICAL: Production-ready streaming download for large backup files.
     * Checks authorization, file existence, and returns efficient streaming response.
     */
    public function download(Request $request, SiteBackup $backup): BinaryFileResponse
    {
        $tenant = $this->getTenant($request);

        // Verify backup belongs to tenant
        if ($backup->site->tenant_id !== $tenant->id) {
            abort(403, 'Unauthorized access to this backup.');
        }

        // Check backup is ready for download
        if (! $backup->storage_path || $backup->status !== 'completed') {
            abort(400, 'Backup is not yet available for download.');
        }

        // Check if file exists
        if (! Storage::exists($backup->storage_path)) {
            Log::error('Backup file not found', [
                'backup_id' => $backup->id,
                'storage_path' => $backup->storage_path,
            ]);
            abort(404, 'Backup file not found.');
        }

        // Get absolute path for streaming
        $filePath = Storage::path($backup->storage_path);

        // Generate safe filename
        $filename = $backup->filename ?? sprintf(
            '%s_%s_%s.tar.gz',
            $backup->site->domain,
            $backup->backup_type,
            $backup->created_at->format('Y-m-d_His')
        );

        Log::info('Backup download initiated', [
            'backup_id' => $backup->id,
            'site_id' => $backup->site_id,
            'user_id' => auth()->id(),
            'filename' => $filename,
        ]);

        // Return streaming download response with proper headers
        return response()->download($filePath, $filename, [
            'Content-Type' => 'application/gzip',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
            'Cache-Control' => 'no-cache, no-store, must-revalidate',
            'Pragma' => 'no-cache',
            'Expires' => '0',
        ]);
    }

    /**
     * Restore from a backup.
     *
     * CRITICAL: Production-ready restore functionality.
     * Validates backup state, dispatches RestoreBackupJob, updates site status.
     * Returns 202 Accepted to indicate async processing.
     */
    public function restore(RestoreBackupRequest $request, SiteBackup $backup): JsonResponse
    {
        $tenant = $this->getTenant($request);
        $validated = $request->validated();

        // Load site relationship
        $backup->loadMissing('site');
        $site = $backup->site;

        // Verify backup belongs to tenant
        if ($site->tenant_id !== $tenant->id) {
            abort(403, 'Unauthorized access to this backup.');
        }

        // Check backup is ready for restore
        if (! $backup->storage_path || $backup->status !== 'completed') {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_NOT_READY',
                    'message' => 'Backup is not yet available for restore.',
                ],
            ], 400);
        }

        // Check backup has not expired (unless force flag is set)
        if (! $validated['force'] && $backup->isExpired()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_EXPIRED',
                    'message' => 'This backup has expired and cannot be restored. Use force=true to override.',
                ],
            ], 400);
        }

        // Check site is not already in a transitional state
        if (in_array($site->status, ['restoring', 'provisioning', 'deleting'])) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'SITE_BUSY',
                    'message' => "Site is currently {$site->status}. Please wait for the current operation to complete.",
                ],
            ], 409);
        }

        try {
            // Dispatch restore job
            RestoreBackupJob::dispatch(
                $backup,
                $validated['restore_type'] ?? 'full',
                $validated['force'] ?? false,
                $validated['skip_verify'] ?? false,
                auth()->id()
            );

            // Update site status to restoring
            $site->update(['status' => 'restoring']);

            Log::info('Restore job dispatched', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
                'domain' => $site->domain,
                'restore_type' => $validated['restore_type'] ?? 'full',
                'user_id' => auth()->id(),
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Site restore has been queued. This may take several minutes.',
                'data' => [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'site_domain' => $site->domain,
                    'restore_type' => $validated['restore_type'] ?? 'full',
                    'status' => 'restoring',
                ],
            ], 202);

        } catch (\Exception $e) {
            Log::error('Backup restore failed', [
                'backup_id' => $backup->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'RESTORE_FAILED',
                    'message' => 'Failed to initiate restore. Please try again.',
                ],
            ], 500);
        }
    }

}
