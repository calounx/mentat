<?php

namespace App\Repositories;

use App\Models\User;
use App\Repositories\Contracts\RepositoryInterface;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

/**
 * User Repository
 *
 * Handles all user-related database operations.
 * Manages user authentication, authorization, and organization membership.
 */
class UserRepository implements RepositoryInterface
{
    /**
     * Create a new repository instance
     *
     * @param User $model
     */
    public function __construct(protected User $model)
    {
    }

    /**
     * Find a user by their ID
     *
     * @param string $id
     * @return User|null
     */
    public function findById(string $id): ?User
    {
        try {
            $user = $this->model->with(['tenants', 'currentTeam'])->find($id);

            if ($user) {
                Log::debug('User found by ID', [
                    'user_id' => $id,
                    'email' => $user->email,
                ]);
            }

            return $user;
        } catch (\Exception $e) {
            Log::error('Error finding user by ID', [
                'user_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find a user by their email address
     *
     * @param string $email
     * @return User|null
     */
    public function findByEmail(string $email): ?User
    {
        try {
            $user = $this->model->where('email', $email)
                ->with(['tenants', 'currentTeam'])
                ->first();

            if ($user) {
                Log::debug('User found by email', [
                    'user_id' => $user->id,
                    'email' => $email,
                ]);
            }

            return $user;
        } catch (\Exception $e) {
            Log::error('Error finding user by email', [
                'email' => $email,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find users by organization with pagination
     *
     * @param string $organizationId
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findByOrganization(string $organizationId, int $perPage = 15): LengthAwarePaginator
    {
        try {
            $users = $this->model->whereHas('tenants', function ($query) use ($organizationId) {
                $query->where('tenants.organization_id', $organizationId);
            })
                ->with(['tenants' => function ($query) use ($organizationId) {
                    $query->where('organization_id', $organizationId);
                }])
                ->orderBy('name')
                ->paginate($perPage);

            Log::info('Found users by organization', [
                'organization_id' => $organizationId,
                'count' => $users->total(),
            ]);

            return $users;
        } catch (\Exception $e) {
            Log::error('Error finding users by organization', [
                'organization_id' => $organizationId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Create a new user
     *
     * @param array $data
     * @return User
     */
    public function create(array $data): User
    {
        try {
            DB::beginTransaction();

            // Hash password if provided
            if (isset($data['password'])) {
                $data['password'] = Hash::make($data['password']);
            }

            $user = $this->model->create(array_merge($data, [
                'email_verified_at' => $data['email_verified_at'] ?? null,
                'created_at' => now(),
            ]));

            // Attach to tenant if provided
            if (isset($data['tenant_id'])) {
                DB::table('tenant_user')->insert([
                    'tenant_id' => $data['tenant_id'],
                    'user_id' => $user->id,
                    'role' => $data['role'] ?? 'member',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            DB::commit();

            Log::info('User created successfully', [
                'user_id' => $user->id,
                'email' => $user->email,
                'tenant_id' => $data['tenant_id'] ?? null,
            ]);

            return $user->load('tenants');
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error creating user', [
                'email' => $data['email'] ?? 'unknown',
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            throw $e;
        }
    }

    /**
     * Update an existing user
     *
     * @param string $id
     * @param array $data
     * @return User
     * @throws ModelNotFoundException
     */
    public function update(string $id, array $data): User
    {
        try {
            $user = $this->model->findOrFail($id);

            // Hash password if being updated
            if (isset($data['password'])) {
                $data['password'] = Hash::make($data['password']);
            }

            $user->update($data);

            Log::info('User updated successfully', [
                'user_id' => $id,
                'updated_fields' => array_keys($data),
            ]);

            return $user->fresh(['tenants', 'currentTeam']);
        } catch (ModelNotFoundException $e) {
            Log::warning('User not found for update', ['user_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating user', [
                'user_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Update user role in a tenant
     *
     * @param string $id
     * @param string $role
     * @return User
     * @throws ModelNotFoundException
     */
    public function updateRole(string $id, string $role): User
    {
        try {
            $user = $this->model->findOrFail($id);

            // Update role in pivot table for current tenant
            if ($user->currentTeam) {
                DB::table('tenant_user')
                    ->where('user_id', $id)
                    ->where('tenant_id', $user->currentTeam->id)
                    ->update([
                        'role' => $role,
                        'updated_at' => now(),
                    ]);

                Log::info('User role updated', [
                    'user_id' => $id,
                    'tenant_id' => $user->currentTeam->id,
                    'new_role' => $role,
                ]);
            }

            return $user->fresh(['tenants']);
        } catch (ModelNotFoundException $e) {
            Log::warning('User not found for role update', ['user_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error updating user role', [
                'user_id' => $id,
                'role' => $role,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Delete a user
     *
     * @param string $id
     * @return bool
     * @throws ModelNotFoundException
     */
    public function delete(string $id): bool
    {
        try {
            DB::beginTransaction();

            $user = $this->model->findOrFail($id);

            // Detach from all tenants
            DB::table('tenant_user')->where('user_id', $id)->delete();

            // Delete user tokens
            DB::table('personal_access_tokens')->where('tokenable_id', $id)->delete();

            // Delete the user
            $deleted = $user->delete();

            DB::commit();

            Log::info('User deleted successfully', [
                'user_id' => $id,
                'email' => $user->email,
            ]);

            return $deleted;
        } catch (ModelNotFoundException $e) {
            DB::rollBack();
            Log::warning('User not found for deletion', ['user_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error deleting user', [
                'user_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Get all users with pagination
     *
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findAll(int $perPage = 15): LengthAwarePaginator
    {
        try {
            return $this->model->withCount('tenants')
                ->orderBy('created_at', 'desc')
                ->paginate($perPage);
        } catch (\Exception $e) {
            Log::error('Error finding all users', [
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Find users by tenant
     *
     * @param string $tenantId
     * @param int $perPage
     * @return LengthAwarePaginator
     */
    public function findByTenant(string $tenantId, int $perPage = 15): LengthAwarePaginator
    {
        try {
            $users = $this->model->whereHas('tenants', function ($query) use ($tenantId) {
                $query->where('tenants.id', $tenantId);
            })
                ->with(['tenants' => function ($query) use ($tenantId) {
                    $query->where('tenants.id', $tenantId);
                }])
                ->orderBy('name')
                ->paginate($perPage);

            Log::info('Found users by tenant', [
                'tenant_id' => $tenantId,
                'count' => $users->total(),
            ]);

            return $users;
        } catch (\Exception $e) {
            Log::error('Error finding users by tenant', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Attach user to tenant with role
     *
     * @param string $userId
     * @param string $tenantId
     * @param string $role
     * @return bool
     */
    public function attachToTenant(string $userId, string $tenantId, string $role = 'member'): bool
    {
        try {
            DB::beginTransaction();

            // Check if already attached
            $exists = DB::table('tenant_user')
                ->where('user_id', $userId)
                ->where('tenant_id', $tenantId)
                ->exists();

            if ($exists) {
                Log::warning('User already attached to tenant', [
                    'user_id' => $userId,
                    'tenant_id' => $tenantId,
                ]);
                DB::rollBack();
                return false;
            }

            DB::table('tenant_user')->insert([
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'role' => $role,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            DB::commit();

            Log::info('User attached to tenant', [
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'role' => $role,
            ]);

            return true;
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error attaching user to tenant', [
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Detach user from tenant
     *
     * @param string $userId
     * @param string $tenantId
     * @return bool
     */
    public function detachFromTenant(string $userId, string $tenantId): bool
    {
        try {
            $deleted = DB::table('tenant_user')
                ->where('user_id', $userId)
                ->where('tenant_id', $tenantId)
                ->delete();

            Log::info('User detached from tenant', [
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'success' => $deleted > 0,
            ]);

            return $deleted > 0;
        } catch (\Exception $e) {
            Log::error('Error detaching user from tenant', [
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Verify user email
     *
     * @param string $id
     * @return User
     * @throws ModelNotFoundException
     */
    public function verifyEmail(string $id): User
    {
        try {
            $user = $this->model->findOrFail($id);

            $user->update([
                'email_verified_at' => now(),
            ]);

            Log::info('User email verified', [
                'user_id' => $id,
                'email' => $user->email,
            ]);

            return $user->fresh();
        } catch (ModelNotFoundException $e) {
            Log::warning('User not found for email verification', ['user_id' => $id]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Error verifying user email', [
                'user_id' => $id,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
