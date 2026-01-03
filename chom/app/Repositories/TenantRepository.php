<?php

namespace App\Repositories;

use App\Models\Tenant;
use App\Repositories\Contracts\RepositoryInterface;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Tenant Repository
 *
 * Manages tenant (organization) data access operations.
 * Handles tenant creation, updates, and retrieval with proper relationship loading.
 */
class TenantRepository implements RepositoryInterface
{
    /**
     * Create a new repository instance
     *
     * @param Tenant $model
     */
    public function __construct(protected Tenant $model)
    {
    }

    /**
     * Find a tenant by its ID
     *
     * @param string $id
     * @return Tenant|null
     */
    public function findById(string $id): ?Tenant
    {
        try {
            $tenant = $this->model->with(['users', 'sites'])->find($id);

            if ($tenant) {
                Log::debug('Tenant found by ID', [
                    'tenant_id' => $id,
                    'name' => $tenant->name,
                ]);
            }

            return $tenant;
        } catch (\Exception $e) {
            Log::error('Error finding tenant by ID', [
                'tenant_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find tenants by user ID
     *
     * @param string $userId
     * @return Collection
     */
    public function findByUserId(string $userId): Collection
    {
        try {
            $tenants = $this->model->whereHas('users', function ($query) use ($userId) {
                $query->where('users.id', $userId);
            })
                ->with(['users', 'sites'])
                ->orderBy('name')
                ->get();

            Log::info('Found tenants by user ID', [
                'user_id' => $userId,
                'count' => $tenants->count(),
            ]);

            return $tenants;
        } catch (\Exception $e) {
            Log::error('Error finding tenants by user ID', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find active tenants by organization ID
     *
     * @param string $organizationId
     * @return Collection
     */
    public function findActiveByOrganization(string $organizationId): Collection
    {
        try {
            $tenants = $this->model->where('organization_id', $organizationId)
                ->where('status', 'active')
                ->with(['users', 'sites'])
                ->orderBy('name')
                ->get();

            Log::info('Found active tenants by organization', [
                'organization_id' => $organizationId,
                'count' => $tenants->count(),
            ]);

            return $tenants;
        } catch (\Exception $e) {
            Log::error('Error finding active tenants by organization', [
                'organization_id' => $organizationId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Create a new tenant
     *
     * @param array $data
     * @return Tenant
     */
    public function create(array $data): Tenant
    {
        try {
            DB::beginTransaction();

            $tenant = $this->model->create(array_merge($data, [
                'status' => $data['status'] ?? 'active',
                'created_at' => now(),
            ]));

            // If owner user ID is provided, attach the user to the tenant
            if (isset($data['owner_user_id'])) {
                DB::table('tenant_user')->insert([
                    'tenant_id' => $tenant->id,
                    'user_id' => $data['owner_user_id'],
                    'role' => 'owner',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            DB::commit();

            Log::info('Tenant created successfully', [
                'tenant_id' => $tenant->id,
                'name' => $tenant->name,
                'owner_user_id' => $data['owner_user_id'] ?? null,
            ]);

            return $tenant->load('users');
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error creating tenant', [
                'data' => $data,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Update an existing tenant
     *
     * @param string $id
     * @param array $data
     * @return Tenant
     * @throws ModelNotFoundException
     */
    public function update(string $id, array $data): Tenant
    {
        try {
            $tenant = $this->model->findOrFail($id);

            $tenant->update($data);

            Log::info('Tenant updated successfully', [
                'tenant_id' => $id,
                'updated_fields' => array_keys($data),
            ]);

            return $tenant->fresh(['users', 'sites']);
        } catch (ModelNotFoundException $e) {
            Log::warning('Tenant not found for update', ['tenant_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating tenant', [
                'tenant_id' => $id,
                'data' => $data,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Update tenant status
     *
     * @param string $id
     * @param string $status
     * @return Tenant
     * @throws ModelNotFoundException
     */
    public function updateStatus(string $id, string $status): Tenant
    {
        try {
            $tenant = $this->model->findOrFail($id);
            $oldStatus = $tenant->status;

            $tenant->update([
                'status' => $status,
                'status_updated_at' => now(),
            ]);

            Log::info('Tenant status updated', [
                'tenant_id' => $id,
                'old_status' => $oldStatus,
                'new_status' => $status,
            ]);

            return $tenant->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('Tenant not found for status update', ['tenant_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating tenant status', [
                'tenant_id' => $id,
                'status' => $status,
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
    public function countSites(string $tenantId): int
    {
        try {
            $count = DB::table('sites')
                ->where('tenant_id', $tenantId)
                ->count();

            Log::debug('Counted sites for tenant', [
                'tenant_id' => $tenantId,
                'count' => $count,
            ]);

            return $count;
        } catch (\Exception $e) {
            Log::error('Error counting sites for tenant', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Delete a tenant
     *
     * @param string $id
     * @return bool
     * @throws ModelNotFoundException
     */
    public function delete(string $id): bool
    {
        try {
            DB::beginTransaction();

            $tenant = $this->model->findOrFail($id);

            // Check if tenant has sites
            $siteCount = $this->countSites($id);
            if ($siteCount > 0) {
                throw new \RuntimeException("Cannot delete tenant with existing sites. Please delete all sites first.");
            }

            // Detach all users
            DB::table('tenant_user')->where('tenant_id', $id)->delete();

            // Delete the tenant
            $deleted = $tenant->delete();

            DB::commit();

            Log::info('Tenant deleted successfully', [
                'tenant_id' => $id,
                'name' => $tenant->name,
            ]);

            return $deleted;
        } catch (ModelNotFoundException $e) {
            DB::rollBack();
            Log::warning('Tenant not found for deletion', ['tenant_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error deleting tenant', [
                'tenant_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Get all tenants with pagination
     *
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findAll(int $perPage = 15): LengthAwarePaginator
    {
        try {
            return $this->model->withCount(['users', 'sites'])
                ->orderBy('created_at', 'desc')
                ->paginate($perPage);
        } catch (\Exception $e) {
            Log::error('Error finding all tenants', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find tenant with statistics
     *
     * @param string $id
     * @return Tenant|null
     */
    public function findWithStats(string $id): ?Tenant
    {
        try {
            $tenant = $this->model->withCount(['users', 'sites'])
                ->with(['sites' => function ($query) {
                    $query->select('id', 'tenant_id', 'domain', 'status', 'storage_used_mb')
                        ->orderBy('created_at', 'desc')
                        ->limit(5);
                }])
                ->find($id);

            if ($tenant) {
                // Calculate total storage used
                $totalStorage = DB::table('sites')
                    ->where('tenant_id', $id)
                    ->sum('storage_used_mb');

                $tenant->total_storage_used_mb = $totalStorage;

                Log::info('Tenant found with stats', [
                    'tenant_id' => $id,
                    'users_count' => $tenant->users_count,
                    'sites_count' => $tenant->sites_count,
                    'total_storage_mb' => $totalStorage,
                ]);
            }

            return $tenant;
        } catch (\Exception $e) {
            Log::error('Error finding tenant with stats', [
                'tenant_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
