<?php

declare(strict_types=1);

namespace App\Modules\Team\Services;

use App\Models\User;
use App\Modules\Team\ValueObjects\Permission;
use App\Modules\Team\ValueObjects\TeamRole;
use App\Services\TeamManagementService;
use Illuminate\Support\Facades\Log;

/**
 * Team Orchestrator Service
 *
 * Orchestrates team collaboration operations by wrapping the existing
 * TeamManagementService with module-specific context and value objects.
 */
class TeamOrchestrator
{
    public function __construct(
        private readonly TeamManagementService $teamManagementService
    ) {
    }

    /**
     * Update member role.
     *
     * @param string $userId User ID
     * @param TeamRole $newRole New role
     * @return User Updated user
     * @throws \RuntimeException
     */
    public function updateMemberRole(string $userId, TeamRole $newRole): User
    {
        Log::info('Team module: Updating member role', [
            'user_id' => $userId,
            'new_role' => $newRole->toString(),
        ]);

        return $this->teamManagementService->updateMemberRole($userId, $newRole->toString());
    }

    /**
     * Update member permissions.
     *
     * @param string $userId User ID
     * @param array $permissions Array of Permission objects
     * @return User Updated user
     * @throws \RuntimeException
     */
    public function updateMemberPermissions(string $userId, array $permissions): User
    {
        Log::info('Team module: Updating member permissions', [
            'user_id' => $userId,
            'permission_count' => count($permissions),
        ]);

        $permissionStrings = array_map(
            fn(Permission $p) => $p->toString(),
            $permissions
        );

        return $this->teamManagementService->updateMemberPermissions($userId, $permissionStrings);
    }

    /**
     * Remove member from team.
     *
     * @param string $userId User ID to remove
     * @param string $organizationId Organization ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function removeMember(string $userId, string $organizationId): bool
    {
        Log::info('Team module: Removing member', [
            'user_id' => $userId,
            'organization_id' => $organizationId,
        ]);

        return $this->teamManagementService->removeMember($userId, $organizationId);
    }

    /**
     * Transfer ownership.
     *
     * @param string $organizationId Organization ID
     * @param string $newOwnerId New owner user ID
     * @param string $currentOwnerId Current owner user ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function transferOwnership(
        string $organizationId,
        string $newOwnerId,
        string $currentOwnerId
    ): bool {
        Log::info('Team module: Transferring ownership', [
            'organization_id' => $organizationId,
            'from_user_id' => $currentOwnerId,
            'to_user_id' => $newOwnerId,
        ]);

        return $this->teamManagementService->transferOwnership(
            $organizationId,
            $newOwnerId,
            $currentOwnerId
        );
    }

    /**
     * Get team statistics.
     *
     * @param string $organizationId Organization ID
     * @return array Team statistics
     */
    public function getStatistics(string $organizationId): array
    {
        $users = app(\App\Repositories\UserRepository::class)
            ->findByOrganization($organizationId);

        $roleDistribution = $users->groupBy('role')->map->count();

        return [
            'total_members' => $users->count(),
            'owners' => $roleDistribution['owner'] ?? 0,
            'admins' => $roleDistribution['admin'] ?? 0,
            'members' => $roleDistribution['member'] ?? 0,
            'viewers' => $roleDistribution['viewer'] ?? 0,
            'active_members' => $users->where('is_active', true)->count(),
            'inactive_members' => $users->where('is_active', false)->count(),
        ];
    }
}
