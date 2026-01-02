<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Concerns\HasTenantScoping;
use App\Http\Controllers\Controller;
use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class BackupController extends Controller
{
    use HasTenantScoping;

    /**
     * List all backups for the current tenant.
     */
    public function index(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $query = SiteBackup::query()
            ->whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->with('site:id,domain')
            ->orderBy('created_at', 'desc');

        // Filter by site
        if ($request->has('site_id')) {
            $query->where('site_id', $request->input('site_id'));
        }

        // Filter by backup type
        if ($request->has('type')) {
            $query->where('backup_type', $request->input('type'));
        }

        $backups = $query->paginate($request->input('per_page', 20));

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
     */
    public function show(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $backup = SiteBackup::query()
            ->whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->with('site:id,domain,site_type')
            ->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $this->formatBackup($backup, detailed: true),
        ]);
    }

    /**
     * Create a new backup.
     */
    public function store(Request $request): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $validated = $request->validate([
            'site_id' => ['required', 'uuid'],
            'backup_type' => ['sometimes', 'in:full,database,files'],
            'retention_days' => ['sometimes', 'integer', 'min:1', 'max:365'],
        ]);

        // Verify site belongs to tenant
        $site = $tenant->sites()->findOrFail($validated['site_id']);

        // Check backup quota
        // TODO: Implement quota checking based on subscription tier

        try {
            // Create backup record (actual backup will be handled by job/service)
            $backup = SiteBackup::create([
                'site_id' => $site->id,
                'backup_type' => $validated['backup_type'] ?? 'full',
                'storage_path' => null, // Will be set when backup completes
                'size_bytes' => 0,
                'retention_days' => $validated['retention_days'] ?? 30,
                'expires_at' => now()->addDays($validated['retention_days'] ?? 30),
            ]);

            // TODO: Dispatch backup job
            // BackupSiteJob::dispatch($backup);

            return response()->json([
                'success' => true,
                'data' => $this->formatBackup($backup),
                'message' => 'Backup has been queued for processing.',
            ], 201);

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
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $backup = SiteBackup::query()
            ->whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->findOrFail($id);

        try {
            // Delete from storage if exists
            if ($backup->storage_path && Storage::exists($backup->storage_path)) {
                Storage::delete($backup->storage_path);
            }

            $backup->delete();

            return response()->json([
                'success' => true,
                'message' => 'Backup deleted successfully.',
            ]);

        } catch (\Exception $e) {
            Log::error('Backup deletion failed', [
                'backup_id' => $id,
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
     * Download a backup.
     */
    public function download(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $backup = SiteBackup::query()
            ->whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->findOrFail($id);

        if (! $backup->storage_path) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_NOT_READY',
                    'message' => 'Backup is not yet available for download.',
                ],
            ], 400);
        }

        // Generate temporary download URL
        // TODO: Implement secure download URL generation
        $downloadUrl = Storage::temporaryUrl($backup->storage_path, now()->addMinutes(15));

        return response()->json([
            'success' => true,
            'data' => [
                'download_url' => $downloadUrl,
                'expires_at' => now()->addMinutes(15)->toIso8601String(),
            ],
        ]);
    }

    /**
     * Restore from a backup.
     */
    public function restore(Request $request, string $id): JsonResponse
    {
        $tenant = $this->getTenant($request);

        $backup = SiteBackup::query()
            ->whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id))
            ->with('site')
            ->findOrFail($id);

        if (! $backup->storage_path) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_NOT_READY',
                    'message' => 'Backup is not yet available for restore.',
                ],
            ], 400);
        }

        if ($backup->isExpired()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'BACKUP_EXPIRED',
                    'message' => 'This backup has expired and cannot be restored.',
                ],
            ], 400);
        }

        try {
            // TODO: Dispatch restore job
            // RestoreSiteJob::dispatch($backup);

            return response()->json([
                'success' => true,
                'message' => 'Site restore has been queued. This may take several minutes.',
                'data' => [
                    'backup_id' => $backup->id,
                    'site_id' => $backup->site_id,
                    'site_domain' => $backup->site->domain,
                ],
            ]);

        } catch (\Exception $e) {
            Log::error('Backup restore failed', [
                'backup_id' => $id,
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

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    private function formatBackup(SiteBackup $backup, bool $detailed = false): array
    {
        $data = [
            'id' => $backup->id,
            'site_id' => $backup->site_id,
            'backup_type' => $backup->backup_type,
            'size' => $backup->getSizeFormatted(),
            'size_bytes' => $backup->size_bytes,
            'is_ready' => ! empty($backup->storage_path),
            'is_expired' => $backup->isExpired(),
            'expires_at' => $backup->expires_at?->toIso8601String(),
            'created_at' => $backup->created_at->toIso8601String(),
        ];

        if ($backup->relationLoaded('site') && $backup->site) {
            $data['site'] = [
                'id' => $backup->site->id,
                'domain' => $backup->site->domain,
            ];
        }

        if ($detailed) {
            $data['storage_path'] = $backup->storage_path;
            $data['checksum'] = $backup->checksum;
            $data['retention_days'] = $backup->retention_days;
        }

        return $data;
    }
}
