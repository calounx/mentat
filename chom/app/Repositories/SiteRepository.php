<?php

namespace App\Repositories;

use App\Models\Site;
use App\Repositories\Contracts\RepositoryInterface;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Site Repository
 *
 * Handles all database operations related to WordPress sites.
 * Ensures tenant isolation and provides query optimization through eager loading.
 */
class SiteRepository implements RepositoryInterface
{
    /**
     * Create a new repository instance
     *
     * @param Site $model
     */
    public function __construct(protected Site $model)
    {
    }

    /**
     * Find sites by tenant with optional filtering and pagination
     *
     * @param string $tenantId
     * @param array $filters Available filters: status, site_type, search, php_version
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findByTenant(string $tenantId, array $filters = [], int $perPage = 15): LengthAwarePaginator
    {
        try {
            $query = $this->model->where('tenant_id', $tenantId)
                ->with(['vpsServer', 'backups' => function ($query) {
                    $query->latest()->limit(5);
                }]);

            // Apply status filter
            if (isset($filters['status']) && !empty($filters['status'])) {
                $query->where('status', $filters['status']);
            }

            // Apply site type filter
            if (isset($filters['site_type']) && !empty($filters['site_type'])) {
                $query->where('site_type', $filters['site_type']);
            }

            // Apply PHP version filter
            if (isset($filters['php_version']) && !empty($filters['php_version'])) {
                $query->where('php_version', $filters['php_version']);
            }

            // Apply search filter (domain or name)
            if (isset($filters['search']) && !empty($filters['search'])) {
                $searchTerm = $filters['search'];
                $query->where(function ($q) use ($searchTerm) {
                    $q->where('domain', 'like', "%{$searchTerm}%")
                        ->orWhere('name', 'like', "%{$searchTerm}%");
                });
            }

            // Apply sorting
            $sortBy = $filters['sort_by'] ?? 'created_at';
            $sortOrder = $filters['sort_order'] ?? 'desc';
            $query->orderBy($sortBy, $sortOrder);

            Log::info('Finding sites by tenant', [
                'tenant_id' => $tenantId,
                'filters' => $filters,
                'per_page' => $perPage,
            ]);

            return $query->paginate($perPage);
        } catch (\Exception $e) {
            Log::error('Error finding sites by tenant', [
                'tenant_id' => $tenantId,
                'filters' => $filters,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Find a site by ID and ensure it belongs to the tenant
     *
     * @param string $id
     * @param string $tenantId
     * @return Site
     * @throws ModelNotFoundException
     */
    public function findByIdAndTenant(string $id, string $tenantId): Site
    {
        try {
            $site = $this->model->where('id', $id)
                ->where('tenant_id', $tenantId)
                ->with(['vpsServer', 'backups', 'sslCertificate'])
                ->firstOrFail();

            Log::info('Site found by ID and tenant', [
                'site_id' => $id,
                'tenant_id' => $tenantId,
                'domain' => $site->domain,
            ]);

            return $site;
        } catch (ModelNotFoundException $e) {
            Log::warning('Site not found for tenant', [
                'site_id' => $id,
                'tenant_id' => $tenantId,
            ]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error finding site by ID and tenant', [
                'site_id' => $id,
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Create a new site
     *
     * @param array $data
     * @return Site
     */
    public function create(array $data): Site
    {
        try {
            DB::beginTransaction();

            $site = $this->model->create($data);

            // Increment site count on VPS server if assigned
            if (isset($data['vps_server_id'])) {
                DB::table('vps_servers')
                    ->where('id', $data['vps_server_id'])
                    ->increment('site_count');
            }

            DB::commit();

            Log::info('Site created successfully', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'tenant_id' => $site->tenant_id,
            ]);

            return $site->load('vpsServer');
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error creating site', [
                'data' => $data,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Update an existing site
     *
     * @param string $id
     * @param array $data
     * @return Site
     * @throws ModelNotFoundException
     */
    public function update(string $id, array $data): Site
    {
        try {
            DB::beginTransaction();

            $site = $this->model->findOrFail($id);
            $oldVpsServerId = $site->vps_server_id;

            $site->update($data);

            // Handle VPS server change
            if (isset($data['vps_server_id']) && $data['vps_server_id'] !== $oldVpsServerId) {
                // Decrement old server
                if ($oldVpsServerId) {
                    DB::table('vps_servers')
                        ->where('id', $oldVpsServerId)
                        ->decrement('site_count');
                }

                // Increment new server
                if ($data['vps_server_id']) {
                    DB::table('vps_servers')
                        ->where('id', $data['vps_server_id'])
                        ->increment('site_count');
                }
            }

            DB::commit();

            Log::info('Site updated successfully', [
                'site_id' => $id,
                'updated_fields' => array_keys($data),
            ]);

            return $site->fresh(['vpsServer']);
        } catch (ModelNotFoundException $e) {
            DB::rollBack();
            Log::warning('Site not found for update', ['site_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error updating site', [
                'site_id' => $id,
                'data' => $data,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Delete a site
     *
     * @param string $id
     * @return bool
     * @throws ModelNotFoundException
     */
    public function delete(string $id): bool
    {
        try {
            DB::beginTransaction();

            $site = $this->model->findOrFail($id);
            $vpsServerId = $site->vps_server_id;

            // Delete associated backups
            $site->backups()->delete();

            // Delete the site
            $deleted = $site->delete();

            // Decrement VPS server site count
            if ($vpsServerId) {
                DB::table('vps_servers')
                    ->where('id', $vpsServerId)
                    ->decrement('site_count');
            }

            DB::commit();

            Log::info('Site deleted successfully', [
                'site_id' => $id,
                'domain' => $site->domain,
            ]);

            return $deleted;
        } catch (ModelNotFoundException $e) {
            DB::rollBack();
            Log::warning('Site not found for deletion', ['site_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error deleting site', [
                'site_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Count total sites for a tenant
     *
     * @param string $tenantId
     * @return int
     */
    public function countByTenant(string $tenantId): int
    {
        try {
            $count = $this->model->where('tenant_id', $tenantId)->count();

            Log::debug('Counted sites for tenant', [
                'tenant_id' => $tenantId,
                'count' => $count,
            ]);

            return $count;
        } catch (\Exception $e) {
            Log::error('Error counting sites by tenant', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find active sites for a tenant
     *
     * @param string $tenantId
     * @return Collection
     */
    public function findActiveByTenant(string $tenantId): Collection
    {
        try {
            $sites = $this->model->where('tenant_id', $tenantId)
                ->where('status', 'active')
                ->with('vpsServer')
                ->orderBy('domain')
                ->get();

            Log::info('Found active sites for tenant', [
                'tenant_id' => $tenantId,
                'count' => $sites->count(),
            ]);

            return $sites;
        } catch (\Exception $e) {
            Log::error('Error finding active sites', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Update site status
     *
     * @param string $id
     * @param string $status
     * @return Site
     * @throws ModelNotFoundException
     */
    public function updateStatus(string $id, string $status): Site
    {
        try {
            $site = $this->model->findOrFail($id);
            $oldStatus = $site->status;

            $site->update([
                'status' => $status,
                'status_updated_at' => now(),
            ]);

            Log::info('Site status updated', [
                'site_id' => $id,
                'old_status' => $oldStatus,
                'new_status' => $status,
            ]);

            return $site->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('Site not found for status update', ['site_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating site status', [
                'site_id' => $id,
                'status' => $status,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find a record by its ID
     *
     * @param string $id
     * @return Site|null
     */
    public function findById(string $id): ?Site
    {
        try {
            return $this->model->with(['vpsServer', 'backups'])->find($id);
        } catch (\Exception $e) {
            Log::error('Error finding site by ID', [
                'site_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Get all sites with optional pagination
     *
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findAll(int $perPage = 15): LengthAwarePaginator
    {
        try {
            return $this->model->with(['vpsServer', 'tenant'])
                ->orderBy('created_at', 'desc')
                ->paginate($perPage);
        } catch (\Exception $e) {
            Log::error('Error finding all sites', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
