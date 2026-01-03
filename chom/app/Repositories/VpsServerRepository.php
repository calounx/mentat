<?php

namespace App\Repositories;

use App\Models\VpsServer;
use App\Repositories\Contracts\RepositoryInterface;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * VPS Server Repository
 *
 * Manages VPS server data operations including server provisioning,
 * load balancing, and site count tracking.
 */
class VpsServerRepository implements RepositoryInterface
{
    /**
     * Create a new repository instance
     *
     * @param VpsServer $model
     */
    public function __construct(protected VpsServer $model)
    {
    }

    /**
     * Get all VPS servers with pagination
     *
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findAll(int $perPage = 15): LengthAwarePaginator
    {
        try {
            $servers = $this->model->withCount('sites')
                ->orderBy('created_at', 'desc')
                ->paginate($perPage);

            Log::info('Retrieved all VPS servers', [
                'count' => $servers->total(),
            ]);

            return $servers;
        } catch (\Exception $e) {
            Log::error('Error finding all VPS servers', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find a VPS server by its ID
     *
     * @param string $id
     * @return VpsServer|null
     */
    public function findById(string $id): ?VpsServer
    {
        try {
            $server = $this->model->withCount('sites')
                ->with(['sites' => function ($query) {
                    $query->select('id', 'vps_server_id', 'domain', 'status')
                        ->orderBy('created_at', 'desc')
                        ->limit(10);
                }])
                ->find($id);

            if ($server) {
                Log::debug('VPS server found by ID', [
                    'server_id' => $id,
                    'hostname' => $server->hostname,
                    'site_count' => $server->sites_count ?? 0,
                ]);
            }

            return $server;
        } catch (\Exception $e) {
            Log::error('Error finding VPS server by ID', [
                'server_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find available VPS servers (active and not at capacity)
     *
     * @return Collection
     */
    public function findAvailable(): Collection
    {
        try {
            $servers = $this->model->where('status', 'active')
                ->where(function ($query) {
                    $query->whereNull('max_sites')
                        ->orWhereRaw('site_count < max_sites');
                })
                ->withCount('sites')
                ->orderBy('site_count', 'asc')
                ->get();

            Log::info('Found available VPS servers', [
                'count' => $servers->count(),
            ]);

            return $servers;
        } catch (\Exception $e) {
            Log::error('Error finding available VPS servers', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find VPS server with least load (fewest sites)
     *
     * @return VpsServer|null
     */
    public function findByLeastLoad(): ?VpsServer
    {
        try {
            $server = $this->model->where('status', 'active')
                ->where(function ($query) {
                    $query->whereNull('max_sites')
                        ->orWhereRaw('site_count < max_sites');
                })
                ->orderBy('site_count', 'asc')
                ->orderBy('cpu_usage', 'asc')
                ->orderBy('memory_usage', 'asc')
                ->first();

            if ($server) {
                Log::info('Found VPS server with least load', [
                    'server_id' => $server->id,
                    'hostname' => $server->hostname,
                    'site_count' => $server->site_count,
                    'cpu_usage' => $server->cpu_usage,
                    'memory_usage' => $server->memory_usage,
                ]);
            } else {
                Log::warning('No available VPS servers found');
            }

            return $server;
        } catch (\Exception $e) {
            Log::error('Error finding VPS server by least load', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Create a new VPS server
     *
     * @param array $data
     * @return VpsServer
     */
    public function create(array $data): VpsServer
    {
        try {
            DB::beginTransaction();

            $server = $this->model->create(array_merge($data, [
                'status' => $data['status'] ?? 'pending',
                'site_count' => 0,
                'cpu_usage' => $data['cpu_usage'] ?? 0,
                'memory_usage' => $data['memory_usage'] ?? 0,
                'disk_usage' => $data['disk_usage'] ?? 0,
                'created_at' => now(),
            ]));

            DB::commit();

            Log::info('VPS server created successfully', [
                'server_id' => $server->id,
                'hostname' => $server->hostname,
                'ip_address' => $server->ip_address,
            ]);

            return $server;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error creating VPS server', [
                'data' => $data,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Update an existing VPS server
     *
     * @param string $id
     * @param array $data
     * @return VpsServer
     * @throws ModelNotFoundException
     */
    public function update(string $id, array $data): VpsServer
    {
        try {
            $server = $this->model->findOrFail($id);

            $server->update($data);

            Log::info('VPS server updated successfully', [
                'server_id' => $id,
                'updated_fields' => array_keys($data),
            ]);

            return $server->fresh(['sites']);
        } catch (ModelNotFoundException $e) {
            Log::warning('VPS server not found for update', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating VPS server', [
                'server_id' => $id,
                'data' => $data,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Update VPS server status
     *
     * @param string $id
     * @param string $status
     * @return VpsServer
     * @throws ModelNotFoundException
     */
    public function updateStatus(string $id, string $status): VpsServer
    {
        try {
            $server = $this->model->findOrFail($id);
            $oldStatus = $server->status;

            $server->update([
                'status' => $status,
                'status_updated_at' => now(),
            ]);

            Log::info('VPS server status updated', [
                'server_id' => $id,
                'old_status' => $oldStatus,
                'new_status' => $status,
            ]);

            return $server->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('VPS server not found for status update', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating VPS server status', [
                'server_id' => $id,
                'status' => $status,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Increment site count for a VPS server
     *
     * @param string $id
     * @return VpsServer
     * @throws ModelNotFoundException
     */
    public function incrementSiteCount(string $id): VpsServer
    {
        try {
            $server = $this->model->findOrFail($id);

            $server->increment('site_count');

            Log::info('VPS server site count incremented', [
                'server_id' => $id,
                'new_count' => $server->fresh()->site_count,
            ]);

            return $server->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('VPS server not found for site count increment', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error incrementing VPS server site count', [
                'server_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Decrement site count for a VPS server
     *
     * @param string $id
     * @return VpsServer
     * @throws ModelNotFoundException
     */
    public function decrementSiteCount(string $id): VpsServer
    {
        try {
            $server = $this->model->findOrFail($id);

            // Prevent negative counts
            if ($server->site_count > 0) {
                $server->decrement('site_count');
            }

            Log::info('VPS server site count decremented', [
                'server_id' => $id,
                'new_count' => $server->fresh()->site_count,
            ]);

            return $server->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('VPS server not found for site count decrement', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error decrementing VPS server site count', [
                'server_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Delete a VPS server
     *
     * @param string $id
     * @return bool
     * @throws ModelNotFoundException
     */
    public function delete(string $id): bool
    {
        try {
            DB::beginTransaction();

            $server = $this->model->findOrFail($id);

            // Check if server has sites
            if ($server->site_count > 0) {
                throw new \RuntimeException("Cannot delete VPS server with existing sites. Please migrate all sites first.");
            }

            $deleted = $server->delete();

            DB::commit();

            Log::info('VPS server deleted successfully', [
                'server_id' => $id,
                'hostname' => $server->hostname,
            ]);

            return $deleted;
        } catch (ModelNotFoundException $e) {
            DB::rollBack();
            Log::warning('VPS server not found for deletion', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error deleting VPS server', [
                'server_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Update server metrics (CPU, memory, disk usage)
     *
     * @param string $id
     * @param array $metrics
     * @return VpsServer
     * @throws ModelNotFoundException
     */
    public function updateMetrics(string $id, array $metrics): VpsServer
    {
        try {
            $server = $this->model->findOrFail($id);

            $updateData = [];

            if (isset($metrics['cpu_usage'])) {
                $updateData['cpu_usage'] = $metrics['cpu_usage'];
            }

            if (isset($metrics['memory_usage'])) {
                $updateData['memory_usage'] = $metrics['memory_usage'];
            }

            if (isset($metrics['disk_usage'])) {
                $updateData['disk_usage'] = $metrics['disk_usage'];
            }

            if (!empty($updateData)) {
                $updateData['metrics_updated_at'] = now();
                $server->update($updateData);

                Log::info('VPS server metrics updated', [
                    'server_id' => $id,
                    'metrics' => $updateData,
                ]);
            }

            return $server->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('VPS server not found for metrics update', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating VPS server metrics', [
                'server_id' => $id,
                'metrics' => $metrics,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find servers by status
     *
     * @param string $status
     * @return Collection
     */
    public function findByStatus(string $status): Collection
    {
        try {
            $servers = $this->model->where('status', $status)
                ->withCount('sites')
                ->orderBy('hostname')
                ->get();

            Log::info('Found VPS servers by status', [
                'status' => $status,
                'count' => $servers->count(),
            ]);

            return $servers;
        } catch (\Exception $e) {
            Log::error('Error finding VPS servers by status', [
                'status' => $status,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Get server statistics
     *
     * @param string $id
     * @return array
     * @throws ModelNotFoundException
     */
    public function getStatistics(string $id): array
    {
        try {
            $server = $this->model->findOrFail($id);

            $stats = [
                'total_sites' => $server->site_count,
                'active_sites' => DB::table('sites')
                    ->where('vps_server_id', $id)
                    ->where('status', 'active')
                    ->count(),
                'total_storage_used_mb' => DB::table('sites')
                    ->where('vps_server_id', $id)
                    ->sum('storage_used_mb'),
                'total_backups' => DB::table('site_backups')
                    ->whereIn('site_id', function ($query) use ($id) {
                        $query->select('id')
                            ->from('sites')
                            ->where('vps_server_id', $id);
                    })
                    ->count(),
                'cpu_usage' => $server->cpu_usage,
                'memory_usage' => $server->memory_usage,
                'disk_usage' => $server->disk_usage,
                'capacity_used_percentage' => $server->max_sites > 0
                    ? round(($server->site_count / $server->max_sites) * 100, 2)
                    : 0,
            ];

            Log::info('Retrieved VPS server statistics', [
                'server_id' => $id,
                'stats' => $stats,
            ]);

            return $stats;
        } catch (ModelNotFoundException $e) {
            Log::warning('VPS server not found for statistics', ['server_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error getting VPS server statistics', [
                'server_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
