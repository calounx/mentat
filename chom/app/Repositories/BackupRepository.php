<?php

namespace App\Repositories;

use App\Models\SiteBackup;
use App\Repositories\Contracts\RepositoryInterface;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Backup Repository
 *
 * Manages all database operations for site backups.
 * Handles backup creation, status updates, and retrieval with proper tenant isolation.
 */
class BackupRepository implements RepositoryInterface
{
    /**
     * Create a new repository instance
     *
     * @param SiteBackup $model
     */
    public function __construct(protected SiteBackup $model)
    {
    }

    /**
     * Find backups by site with pagination
     *
     * @param string $siteId
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findBySite(string $siteId, int $perPage = 15): LengthAwarePaginator
    {
        try {
            $backups = $this->model->where('site_id', $siteId)
                ->with('site')
                ->orderBy('created_at', 'desc')
                ->paginate($perPage);

            Log::info('Found backups by site', [
                'site_id' => $siteId,
                'count' => $backups->total(),
            ]);

            return $backups;
        } catch (\Exception $e) {
            Log::error('Error finding backups by site', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Find backups by tenant with optional filtering
     *
     * @param string $tenantId
     * @param array $filters Available filters: status, type, site_id, date_from, date_to
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findByTenant(string $tenantId, array $filters = [], int $perPage = 15): LengthAwarePaginator
    {
        try {
            $query = $this->model->whereHas('site', function ($query) use ($tenantId) {
                $query->where('tenant_id', $tenantId);
            })->with(['site']);

            // Apply status filter
            if (isset($filters['status']) && !empty($filters['status'])) {
                $query->where('status', $filters['status']);
            }

            // Apply backup type filter
            if (isset($filters['type']) && !empty($filters['type'])) {
                $query->where('type', $filters['type']);
            }

            // Apply site filter
            if (isset($filters['site_id']) && !empty($filters['site_id'])) {
                $query->where('site_id', $filters['site_id']);
            }

            // Apply date range filter
            if (isset($filters['date_from']) && !empty($filters['date_from'])) {
                $query->where('created_at', '>=', $filters['date_from']);
            }

            if (isset($filters['date_to']) && !empty($filters['date_to'])) {
                $query->where('created_at', '<=', $filters['date_to']);
            }

            // Apply sorting
            $sortBy = $filters['sort_by'] ?? 'created_at';
            $sortOrder = $filters['sort_order'] ?? 'desc';
            $query->orderBy($sortBy, $sortOrder);

            Log::info('Finding backups by tenant', [
                'tenant_id' => $tenantId,
                'filters' => $filters,
                'per_page' => $perPage,
            ]);

            return $query->paginate($perPage);
        } catch (\Exception $e) {
            Log::error('Error finding backups by tenant', [
                'tenant_id' => $tenantId,
                'filters' => $filters,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find the latest backup for a site
     *
     * @param string $siteId
     * @return SiteBackup|null
     */
    public function findLatestBySite(string $siteId): ?SiteBackup
    {
        try {
            $backup = $this->model->where('site_id', $siteId)
                ->where('status', 'completed')
                ->orderBy('created_at', 'desc')
                ->first();

            if ($backup) {
                Log::info('Latest backup found for site', [
                    'site_id' => $siteId,
                    'backup_id' => $backup->id,
                    'created_at' => $backup->created_at,
                ]);
            } else {
                Log::info('No completed backups found for site', [
                    'site_id' => $siteId,
                ]);
            }

            return $backup;
        } catch (\Exception $e) {
            Log::error('Error finding latest backup by site', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Create a new backup record
     *
     * @param array $data
     * @return SiteBackup
     */
    public function create(array $data): SiteBackup
    {
        try {
            $backup = $this->model->create(array_merge($data, [
                'status' => $data['status'] ?? 'pending',
                'created_at' => now(),
            ]));

            Log::info('Backup record created', [
                'backup_id' => $backup->id,
                'site_id' => $backup->site_id,
                'type' => $backup->type,
                'status' => $backup->status,
            ]);

            return $backup->load('site');
        } catch (\Exception $e) {
            Log::error('Error creating backup record', [
                'data' => $data,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Update backup status with optional metadata
     *
     * @param string $id
     * @param string $status
     * @param array $metadata Additional metadata to update (size, file_path, error_message, etc.)
     * @return SiteBackup
     * @throws ModelNotFoundException
     */
    public function updateStatus(string $id, string $status, array $metadata = []): SiteBackup
    {
        try {
            $backup = $this->model->findOrFail($id);
            $oldStatus = $backup->status;

            $updateData = array_merge($metadata, [
                'status' => $status,
            ]);

            // Add completion timestamp if status is completed
            if ($status === 'completed') {
                $updateData['completed_at'] = now();
            }

            // Add failure timestamp if status is failed
            if ($status === 'failed') {
                $updateData['failed_at'] = now();
            }

            $backup->update($updateData);

            Log::info('Backup status updated', [
                'backup_id' => $id,
                'old_status' => $oldStatus,
                'new_status' => $status,
                'metadata' => $metadata,
            ]);

            return $backup->fresh(['site']);
        } catch (ModelNotFoundException $e) {
            Log::warning('Backup not found for status update', ['backup_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating backup status', [
                'backup_id' => $id,
                'status' => $status,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Delete a backup record
     *
     * @param string $id
     * @return bool
     * @throws ModelNotFoundException
     */
    public function delete(string $id): bool
    {
        try {
            $backup = $this->model->findOrFail($id);
            $filePath = $backup->file_path;

            $deleted = $backup->delete();

            Log::info('Backup record deleted', [
                'backup_id' => $id,
                'file_path' => $filePath,
            ]);

            return $deleted;
        } catch (ModelNotFoundException $e) {
            Log::warning('Backup not found for deletion', ['backup_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error deleting backup', [
                'backup_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Count total backups for a site
     *
     * @param string $siteId
     * @return int
     */
    public function countBySite(string $siteId): int
    {
        try {
            $count = $this->model->where('site_id', $siteId)->count();

            Log::debug('Counted backups for site', [
                'site_id' => $siteId,
                'count' => $count,
            ]);

            return $count;
        } catch (\Exception $e) {
            Log::error('Error counting backups by site', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find completed backups for a site
     *
     * @param string $siteId
     * @return Collection
     */
    public function findCompletedBySite(string $siteId): Collection
    {
        try {
            $backups = $this->model->where('site_id', $siteId)
                ->where('status', 'completed')
                ->orderBy('created_at', 'desc')
                ->get();

            Log::info('Found completed backups for site', [
                'site_id' => $siteId,
                'count' => $backups->count(),
            ]);

            return $backups;
        } catch (\Exception $e) {
            Log::error('Error finding completed backups', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find a backup by its ID
     *
     * @param string $id
     * @return SiteBackup|null
     */
    public function findById(string $id): ?SiteBackup
    {
        try {
            return $this->model->with('site')->find($id);
        } catch (\Exception $e) {
            Log::error('Error finding backup by ID', [
                'backup_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find a backup by its ID with tenant filtering (SECURE)
     *
     * This method ensures tenant isolation by filtering backups at the database level.
     * Use this instead of findById() when handling user requests to prevent
     * unauthorized access to backups from other tenants.
     *
     * @param string $id
     * @param string $tenantId
     * @return SiteBackup|null
     */
    public function findByIdAndTenant(string $id, string $tenantId): ?SiteBackup
    {
        try {
            $backup = $this->model
                ->with('site')
                ->whereHas('site', function ($query) use ($tenantId) {
                    $query->where('tenant_id', $tenantId);
                })
                ->where('id', $id)
                ->first();

            if ($backup) {
                Log::info('Backup found with tenant filter', [
                    'backup_id' => $id,
                    'tenant_id' => $tenantId,
                ]);
            } else {
                Log::info('Backup not found or access denied', [
                    'backup_id' => $id,
                    'tenant_id' => $tenantId,
                ]);
            }

            return $backup;
        } catch (\Exception $e) {
            Log::error('Error finding backup by ID and tenant', [
                'backup_id' => $id,
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Update a backup record
     *
     * @param string $id
     * @param array $data
     * @return SiteBackup
     * @throws ModelNotFoundException
     */
    public function update(string $id, array $data): SiteBackup
    {
        try {
            $backup = $this->model->findOrFail($id);
            $backup->update($data);

            Log::info('Backup updated', [
                'backup_id' => $id,
                'updated_fields' => array_keys($data),
            ]);

            return $backup->fresh(['site']);
        } catch (ModelNotFoundException $e) {
            Log::warning('Backup not found for update', ['backup_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating backup', [
                'backup_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Get all backups with pagination
     *
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findAll(int $perPage = 15): LengthAwarePaginator
    {
        try {
            return $this->model->with(['site'])
                ->orderBy('created_at', 'desc')
                ->paginate($perPage);
        } catch (\Exception $e) {
            Log::error('Error finding all backups', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
