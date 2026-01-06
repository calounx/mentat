<?php

namespace App\Policies;

use App\Models\Tenant;
use App\Models\User;
use Illuminate\Auth\Access\Response;

class TenantPolicy
{
    /**
     * Determine whether the user can view the tenant.
     * User must have access to the tenant or be a super admin.
     */
    public function view(User $user, Tenant $tenant): Response
    {
        if ($user->is_super_admin) {
            return Response::allow();
        }

        if ($user->organization_id === $tenant->organization_id &&
            $user->hasAccessToTenant($tenant)) {
            return Response::allow();
        }

        return Response::deny('You do not have access to this tenant.');
    }

    /**
     * Determine whether the user can manage users for this tenant.
     * Organization admins and super admins can manage tenant users.
     */
    public function manageUsers(User $user, Tenant $tenant): Response
    {
        if ($user->is_super_admin) {
            return Response::allow();
        }

        if ($user->organization_id !== $tenant->organization_id) {
            return Response::deny('You can only manage users within your organization.');
        }

        return $user->isAdmin()
            ? Response::allow()
            : Response::deny('Only admins can manage tenant users.');
    }
}
