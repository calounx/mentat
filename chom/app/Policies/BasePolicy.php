<?php

namespace App\Policies;

use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Log;

/**
 * Base Policy
 *
 * Abstract base class for all authorization policies.
 * Provides common authorization logic including:
 * - Role-based access control
 * - Tenant/organization isolation
 * - Permission checking
 * - Role hierarchy validation
 *
 * All application policies should extend this class.
 *
 * @package App\Policies
 */
abstract class BasePolicy
{
    /**
     * Role hierarchy with numeric weights.
     * Higher number = more privileges.
     *
     * @var array<string, int>
     */
    protected array $roleHierarchy = [
        'owner' => 4,
        'admin' => 3,
        'member' => 2,
        'viewer' => 1,
    ];

    /**
     * Perform pre-authorization checks.
     *
     * Owners bypass all authorization checks.
     * Returns true to allow, false to deny, null to continue to individual checks.
     *
     * @param User $user
     * @param string $ability
     * @return bool|null
     */
    public function before(User $user, string $ability): ?bool
    {
        if ($this->isOwner($user)) {
            $this->logAuthorization($user, $ability, true, 'owner_bypass');
            return true;
        }

        return null;
    }

    /**
     * Check if user has owner role.
     *
     * @param User $user
     * @return bool
     */
    protected function isOwner(User $user): bool
    {
        return $user->role === 'owner';
    }

    /**
     * Check if user is admin or owner.
     *
     * @param User $user
     * @return bool
     */
    protected function isAdmin(User $user): bool
    {
        return in_array($user->role, ['owner', 'admin'], true);
    }

    /**
     * Check if user has member or higher role.
     *
     * @param User $user
     * @return bool
     */
    protected function isMember(User $user): bool
    {
        return $this->hasMinimumRole($user, 'member');
    }

    /**
     * Check if user has minimum required role.
     *
     * @param User $user
     * @param string $minimumRole
     * @return bool
     */
    protected function hasMinimumRole(User $user, string $minimumRole): bool
    {
        $userRoleWeight = $this->roleHierarchy[$user->role] ?? 0;
        $minimumRoleWeight = $this->roleHierarchy[$minimumRole] ?? 0;

        return $userRoleWeight >= $minimumRoleWeight;
    }

    /**
     * Check if model belongs to user's current tenant.
     *
     * @param User $user
     * @param Model|null $model
     * @return bool
     */
    protected function belongsToTenant(User $user, ?Model $model): bool
    {
        if ($model === null) {
            $this->logAuthorizationFailure($user, 'belongsToTenant', 'null_model');
            return false;
        }

        if (!property_exists($model, 'tenant_id') && !isset($model->tenant_id)) {
            $this->logAuthorizationFailure($user, 'belongsToTenant', 'missing_tenant_id', [
                'model' => get_class($model),
                'model_id' => $model->getKey(),
            ]);
            return false;
        }

        $belongs = $model->tenant_id === $user->current_tenant_id;

        if (!$belongs) {
            $this->logAuthorizationFailure($user, 'belongsToTenant', 'tenant_mismatch', [
                'user_tenant_id' => $user->current_tenant_id,
                'model_tenant_id' => $model->tenant_id,
                'model' => get_class($model),
                'model_id' => $model->getKey(),
            ]);
        }

        return $belongs;
    }

    /**
     * Check if model belongs to user's organization.
     *
     * @param User $user
     * @param Model|null $model
     * @return bool
     */
    protected function belongsToOrganization(User $user, ?Model $model): bool
    {
        if ($model === null) {
            $this->logAuthorizationFailure($user, 'belongsToOrganization', 'null_model');
            return false;
        }

        if (!property_exists($model, 'organization_id') && !isset($model->organization_id)) {
            $this->logAuthorizationFailure($user, 'belongsToOrganization', 'missing_organization_id', [
                'model' => get_class($model),
                'model_id' => $model->getKey(),
            ]);
            return false;
        }

        $belongs = $model->organization_id === $user->organization_id;

        if (!$belongs) {
            $this->logAuthorizationFailure($user, 'belongsToOrganization', 'organization_mismatch', [
                'user_organization_id' => $user->organization_id,
                'model_organization_id' => $model->organization_id,
                'model' => get_class($model),
                'model_id' => $model->getKey(),
            ]);
        }

        return $belongs;
    }

    /**
     * Check if user has specific permission.
     *
     * Permissions are stored as JSON array on user model.
     *
     * @param User $user
     * @param string $permission
     * @return bool
     */
    protected function hasPermission(User $user, string $permission): bool
    {
        if (!property_exists($user, 'permissions') && !isset($user->permissions)) {
            return false;
        }

        $permissions = is_string($user->permissions)
            ? json_decode($user->permissions, true)
            : $user->permissions;

        if (!is_array($permissions)) {
            return false;
        }

        $hasPermission = in_array($permission, $permissions, true);

        if (!$hasPermission) {
            $this->logAuthorizationFailure($user, 'hasPermission', 'permission_missing', [
                'required_permission' => $permission,
                'user_permissions' => $permissions,
            ]);
        }

        return $hasPermission;
    }

    /**
     * Check if user can manage team (admin or higher).
     *
     * @param User $user
     * @return bool
     */
    protected function canManageTeam(User $user): bool
    {
        return $this->isAdmin($user);
    }

    /**
     * Check if user can manage billing (admin or higher).
     *
     * @param User $user
     * @return bool
     */
    protected function canManageBilling(User $user): bool
    {
        return $this->isAdmin($user);
    }

    /**
     * Check if user can delete resources (admin or higher).
     *
     * @param User $user
     * @return bool
     */
    protected function canDeleteResource(User $user): bool
    {
        return $this->isAdmin($user);
    }

    /**
     * Check if model is soft deleted.
     *
     * @param Model $model
     * @return bool
     */
    protected function isSoftDeleted(Model $model): bool
    {
        if (!method_exists($model, 'trashed')) {
            return false;
        }

        return $model->trashed();
    }

    /**
     * Check if user can view soft-deleted models.
     *
     * @param User $user
     * @return bool
     */
    protected function canViewTrashed(User $user): bool
    {
        return $this->isAdmin($user);
    }

    /**
     * Log successful authorization.
     *
     * @param User $user
     * @param string $ability
     * @param bool $result
     * @param string $reason
     * @return void
     */
    protected function logAuthorization(User $user, string $ability, bool $result, string $reason): void
    {
        Log::debug('Authorization check', [
            'policy' => static::class,
            'user_id' => $user->id,
            'role' => $user->role,
            'ability' => $ability,
            'result' => $result,
            'reason' => $reason,
        ]);
    }

    /**
     * Log authorization failure.
     *
     * @param User $user
     * @param string $check
     * @param string $reason
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logAuthorizationFailure(User $user, string $check, string $reason, array $context = []): void
    {
        Log::debug('Authorization failed', array_merge($context, [
            'policy' => static::class,
            'user_id' => $user->id,
            'role' => $user->role,
            'check' => $check,
            'reason' => $reason,
        ]));
    }

    /**
     * Check if user and model belong to same tenant.
     *
     * @param User $user
     * @param Model|null $model
     * @return bool
     */
    protected function sameTenant(User $user, ?Model $model): bool
    {
        return $this->belongsToTenant($user, $model);
    }

    /**
     * Check if user and model belong to same organization.
     *
     * @param User $user
     * @param Model|null $model
     * @return bool
     */
    protected function sameOrganization(User $user, ?Model $model): bool
    {
        return $this->belongsToOrganization($user, $model);
    }

    /**
     * Deny with logging.
     *
     * @param User $user
     * @param string $ability
     * @param string $reason
     * @param array<string, mixed> $context
     * @return bool
     */
    protected function deny(User $user, string $ability, string $reason, array $context = []): bool
    {
        $this->logAuthorizationFailure($user, $ability, $reason, $context);
        return false;
    }

    /**
     * Allow with logging.
     *
     * @param User $user
     * @param string $ability
     * @param string $reason
     * @return bool
     */
    protected function allow(User $user, string $ability, string $reason): bool
    {
        $this->logAuthorization($user, $ability, true, $reason);
        return true;
    }
}
