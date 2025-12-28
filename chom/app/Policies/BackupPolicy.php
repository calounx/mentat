<?php

namespace App\Policies;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\User;
use Illuminate\Auth\Access\Response;

class BackupPolicy
{
    /**
     * Determine whether the user can view any backups.
     * All authenticated users in the tenant can view backups.
     */
    public function viewAny(User $user): Response
    {
        return Response::allow();
    }

    /**
     * Determine whether the user can view a specific backup.
     * User must belong to the same tenant as the backup's site.
     */
    public function view(User $user, SiteBackup $backup): Response
    {
        return $this->belongsToTenant($user, $backup)
            ? Response::allow()
            : Response::deny('You do not have access to this backup.');
    }

    /**
     * Determine whether the user can create backups.
     * Only owner, admin, and member roles can create backups.
     */
    public function create(User $user, Site $site): Response
    {
        if (!$this->siteBelongsToTenant($user, $site)) {
            return Response::deny('You do not have access to this site.');
        }

        if ($user->canManageSites()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to create backups.');
    }

    /**
     * Determine whether the user can restore a backup.
     * Only owner and admin roles can restore backups (destructive operation).
     */
    public function restore(User $user, SiteBackup $backup): Response
    {
        if (!$this->belongsToTenant($user, $backup)) {
            return Response::deny('You do not have access to this backup.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to restore backups.');
    }

    /**
     * Determine whether the user can delete a backup.
     * Only owner and admin roles can delete backups.
     */
    public function delete(User $user, SiteBackup $backup): Response
    {
        if (!$this->belongsToTenant($user, $backup)) {
            return Response::deny('You do not have access to this backup.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to delete backups.');
    }

    /**
     * Check if user belongs to the same tenant as the backup's site.
     */
    private function belongsToTenant(User $user, SiteBackup $backup): bool
    {
        $userTenant = $user->currentTenant();
        $backup->loadMissing('site');

        return $userTenant && $backup->site && $backup->site->tenant_id === $userTenant->id;
    }

    /**
     * Check if site belongs to the user's tenant.
     */
    private function siteBelongsToTenant(User $user, Site $site): bool
    {
        $userTenant = $user->currentTenant();

        return $userTenant && $site->tenant_id === $userTenant->id;
    }
}
