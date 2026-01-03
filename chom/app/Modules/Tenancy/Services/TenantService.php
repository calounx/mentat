<?php

declare(strict_types=1);

namespace App\Modules\Tenancy\Services;

use App\Models\Organization;
use App\Models\User;
use App\Modules\Tenancy\Contracts\TenantResolverInterface;
use App\Modules\Tenancy\Events\OrganizationCreated;
use App\Modules\Tenancy\Events\TenantSwitched;
use App\Repositories\TenantRepository;
use App\Repositories\UserRepository;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Tenant Service
 *
 * Handles tenant resolution, organization management, and tenant isolation.
 */
class TenantService implements TenantResolverInterface
{
    private ?Organization $currentTenant = null;

    public function __construct(
        private readonly TenantRepository $tenantRepository,
        private readonly UserRepository $userRepository
    ) {
    }

    /**
     * Resolve current tenant from request context.
     *
     * @return Organization|null Current tenant
     */
    public function resolve(): ?Organization
    {
        if ($this->currentTenant !== null) {
            return $this->currentTenant;
        }

        $user = auth()->user();

        if (!$user instanceof User || !$user->organization_id) {
            return null;
        }

        $this->currentTenant = $this->tenantRepository->findById($user->organization_id);

        return $this->currentTenant;
    }

    /**
     * Get current tenant ID.
     *
     * @return string|null Tenant ID
     */
    public function getCurrentTenantId(): ?string
    {
        $tenant = $this->resolve();

        return $tenant?->id;
    }

    /**
     * Switch to a different tenant context.
     *
     * @param string $tenantId Target tenant ID
     * @param string $userId User performing the switch
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function switchTenant(string $tenantId, string $userId): bool
    {
        try {
            $user = $this->userRepository->findById($userId);

            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            $tenant = $this->tenantRepository->findById($tenantId);

            if (!$tenant) {
                throw new \RuntimeException('Tenant not found');
            }

            if (!$tenant->isActive()) {
                throw new \RuntimeException('Tenant is not active');
            }

            // Verify user has access to this tenant
            if (!$this->userBelongsToTenant($userId, $tenantId)) {
                throw new \RuntimeException('User does not have access to this tenant');
            }

            $oldTenantId = $user->organization_id;

            // Update user's current organization
            $this->userRepository->update($userId, [
                'organization_id' => $tenantId,
            ]);

            // Update current tenant cache
            $this->currentTenant = $tenant;

            Log::info('Tenant switched', [
                'user_id' => $userId,
                'old_tenant_id' => $oldTenantId,
                'new_tenant_id' => $tenantId,
            ]);

            Event::dispatch(new TenantSwitched($user, $tenant, $oldTenantId));

            return true;
        } catch (\Exception $e) {
            Log::error('Tenant switch failed', [
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to switch tenant: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Create a new organization (tenant).
     *
     * @param array $data Organization data
     * @param string $ownerId Owner user ID
     * @return Organization Created organization
     * @throws \RuntimeException
     */
    public function createOrganization(array $data, string $ownerId): Organization
    {
        try {
            $validated = $this->validateOrganizationData($data);

            $owner = $this->userRepository->findById($ownerId);

            if (!$owner) {
                throw new \RuntimeException('Owner user not found');
            }

            DB::beginTransaction();

            try {
                // Create organization
                $organization = $this->tenantRepository->create([
                    'name' => $validated['name'],
                    'tier' => $validated['tier'] ?? 'starter',
                    'settings' => $validated['settings'] ?? [],
                    'is_active' => true,
                ]);

                // Assign owner to organization
                $this->userRepository->update($ownerId, [
                    'organization_id' => $organization->id,
                    'role' => 'owner',
                ]);

                DB::commit();

                Log::info('Organization created', [
                    'organization_id' => $organization->id,
                    'name' => $organization->name,
                    'owner_id' => $ownerId,
                    'tier' => $organization->tier,
                ]);

                Event::dispatch(new OrganizationCreated($organization, $owner));

                return $organization;
            } catch (\Exception $e) {
                DB::rollBack();
                throw $e;
            }
        } catch (ValidationException $e) {
            Log::error('Organization creation validation failed', [
                'owner_id' => $ownerId,
                'errors' => $e->errors(),
            ]);
            throw new \RuntimeException('Validation failed: ' . json_encode($e->errors()));
        } catch (\Exception $e) {
            Log::error('Organization creation failed', [
                'owner_id' => $ownerId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to create organization: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Check if user belongs to tenant.
     *
     * @param string $userId User ID
     * @param string $tenantId Tenant ID
     * @return bool Membership status
     */
    public function userBelongsToTenant(string $userId, string $tenantId): bool
    {
        try {
            $user = $this->userRepository->findById($userId);

            return $user && $user->organization_id === $tenantId;
        } catch (\Exception $e) {
            Log::error('Tenant membership check failed', [
                'user_id' => $userId,
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Get all users in a tenant.
     *
     * @param string $tenantId Tenant ID
     * @return Collection
     */
    public function getTenantUsers(string $tenantId): Collection
    {
        try {
            return $this->userRepository->findByOrganization($tenantId);
        } catch (\Exception $e) {
            Log::error('Failed to get tenant users', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);

            return new Collection();
        }
    }

    /**
     * Enforce tenant isolation for a query.
     *
     * @param Builder $query
     * @param string|null $tenantId Optional tenant ID (uses current if null)
     * @return Builder
     */
    public function scopeToTenant(Builder $query, ?string $tenantId = null): Builder
    {
        $tenantId = $tenantId ?? $this->getCurrentTenantId();

        if (!$tenantId) {
            Log::warning('Tenant scope applied without tenant ID');
            return $query->whereRaw('1 = 0'); // Return empty result
        }

        return $query->where('tenant_id', $tenantId);
    }

    /**
     * Validate organization data.
     *
     * @param array $data Organization data
     * @return array Validated data
     * @throws ValidationException
     */
    private function validateOrganizationData(array $data): array
    {
        $validator = Validator::make($data, [
            'name' => 'required|string|max:255',
            'tier' => 'nullable|string|in:starter,professional,enterprise',
            'settings' => 'nullable|array',
        ]);

        if ($validator->fails()) {
            throw new ValidationException($validator);
        }

        return $validator->validated();
    }
}
