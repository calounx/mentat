<?php

declare(strict_types=1);

namespace App\Services;

use App\Events\MemberInvited;
use App\Events\MemberJoined;
use App\Events\MemberRemoved;
use App\Events\MemberRoleUpdated;
use App\Events\OwnershipTransferred;
use App\Mail\TeamInvitationMail;
use App\Models\TeamInvitation;
use App\Models\User;
use App\Repositories\UserRepository;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Team Management Service
 *
 * Handles all business logic related to team member invitations,
 * role management, and organizational permissions.
 */
class TeamManagementService
{
    private const ROLE_HIERARCHY = [
        'owner' => 4,
        'admin' => 3,
        'member' => 2,
        'viewer' => 1,
    ];

    private const INVITATION_EXPIRY_DAYS = 7;

    public function __construct(
        private readonly UserRepository $userRepository
    ) {
    }

    /**
     * Invite a new member to an organization.
     *
     * @param string $organizationId The organization ID
     * @param string $email Email address of the invitee
     * @param string $role Role to assign (owner, admin, member, viewer)
     * @param array $permissions Additional permissions
     * @return TeamInvitation The created invitation
     * @throws ValidationException
     * @throws \RuntimeException
     */
    public function inviteMember(
        string $organizationId,
        string $email,
        string $role,
        array $permissions = []
    ): TeamInvitation {
        try {
            // Validate input
            $validated = $this->validateInvitationData($email, $role, $permissions);

            // Check if user already exists in organization
            $existingUser = $this->userRepository->findByEmailAndOrganization(
                $validated['email'],
                $organizationId
            );

            if ($existingUser) {
                throw new \RuntimeException('User already exists in this organization');
            }

            // Check for pending invitation
            $pendingInvitation = TeamInvitation::where('organization_id', $organizationId)
                ->where('email', $validated['email'])
                ->pending()
                ->first();

            if ($pendingInvitation) {
                throw new \RuntimeException('A pending invitation already exists for this email');
            }

            // Create invitation
            $invitation = TeamInvitation::create([
                'organization_id' => $organizationId,
                'email' => $validated['email'],
                'role' => $validated['role'],
                'permissions' => $validated['permissions'],
                'token' => TeamInvitation::generateToken(),
                'invited_by' => auth()->id(),
                'expires_at' => now()->addDays(self::INVITATION_EXPIRY_DAYS),
            ]);

            Log::info('Team invitation created', [
                'invitation_id' => $invitation->id,
                'organization_id' => $organizationId,
                'email' => $email,
                'role' => $role,
            ]);

            // Send invitation email
            try {
                Mail::to($email)->send(new TeamInvitationMail($invitation));
            } catch (\Exception $e) {
                Log::error('Failed to send invitation email', [
                    'invitation_id' => $invitation->id,
                    'error' => $e->getMessage(),
                ]);
            }

            Event::dispatch(new MemberInvited($invitation));

            return $invitation;
        } catch (ValidationException $e) {
            Log::error('Team invitation validation failed', [
                'organization_id' => $organizationId,
                'email' => $email,
                'errors' => $e->errors(),
            ]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Team invitation failed', [
                'organization_id' => $organizationId,
                'email' => $email,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to invite member: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Accept a team invitation.
     *
     * @param string $invitationToken The invitation token
     * @param string $userId The user ID accepting the invitation
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function acceptInvitation(string $invitationToken, string $userId): bool
    {
        try {
            $invitation = TeamInvitation::where('token', $invitationToken)
                ->whereNull('accepted_at')
                ->first();

            if (!$invitation) {
                throw new \RuntimeException('Invalid or already accepted invitation');
            }

            if ($invitation->isExpired()) {
                throw new \RuntimeException('Invitation has expired');
            }

            $user = $this->userRepository->findById($userId);
            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            // Verify email matches
            if ($user->email !== $invitation->email) {
                throw new \RuntimeException('Email does not match invitation');
            }

            DB::beginTransaction();
            try {
                // Update user's organization and role
                $this->userRepository->update($userId, [
                    'organization_id' => $invitation->organization_id,
                    'role' => $invitation->role,
                ]);

                // Mark invitation as accepted
                $invitation->update([
                    'accepted_at' => now(),
                ]);

                DB::commit();

                Log::info('Team invitation accepted', [
                    'invitation_id' => $invitation->id,
                    'user_id' => $userId,
                    'organization_id' => $invitation->organization_id,
                ]);

                Event::dispatch(new MemberJoined($user, $invitation->organization));

                return true;
            } catch (\Exception $e) {
                DB::rollBack();
                throw $e;
            }
        } catch (\Exception $e) {
            Log::error('Failed to accept invitation', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to accept invitation: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Cancel a pending invitation.
     *
     * @param string $invitationId The invitation ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function cancelInvitation(string $invitationId): bool
    {
        try {
            $invitation = TeamInvitation::find($invitationId);
            if (!$invitation) {
                throw new \RuntimeException('Invitation not found');
            }

            if ($invitation->isAccepted()) {
                throw new \RuntimeException('Cannot cancel an accepted invitation');
            }

            $invitation->delete();

            Log::info('Team invitation cancelled', [
                'invitation_id' => $invitationId,
                'organization_id' => $invitation->organization_id,
                'email' => $invitation->email,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to cancel invitation', [
                'invitation_id' => $invitationId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to cancel invitation: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Update a member's role.
     *
     * @param string $userId The user ID
     * @param string $newRole New role to assign
     * @return User The updated user
     * @throws \RuntimeException
     */
    public function updateMemberRole(string $userId, string $newRole): User
    {
        try {
            $user = $this->userRepository->findById($userId);
            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            // Validate role
            if (!isset(self::ROLE_HIERARCHY[$newRole])) {
                throw new \RuntimeException('Invalid role');
            }

            $currentUser = auth()->user();
            if (!$currentUser) {
                throw new \RuntimeException('Unauthorized');
            }

            // Prevent self-demotion
            if ($userId === $currentUser->id) {
                throw new \RuntimeException('Cannot change your own role');
            }

            // Check role hierarchy - can't promote someone to a higher role than yourself
            if (self::ROLE_HIERARCHY[$newRole] >= self::ROLE_HIERARCHY[$currentUser->role]) {
                throw new \RuntimeException('Cannot assign a role equal to or higher than your own');
            }

            // Prevent removing the last owner
            if ($user->role === 'owner' && $newRole !== 'owner') {
                $ownerCount = $this->userRepository->countByRole($user->organization_id, 'owner');
                if ($ownerCount <= 1) {
                    throw new \RuntimeException('Cannot change role of the last owner');
                }
            }

            $oldRole = $user->role;

            $updatedUser = $this->userRepository->update($userId, [
                'role' => $newRole,
            ]);

            Log::info('Member role updated', [
                'user_id' => $userId,
                'old_role' => $oldRole,
                'new_role' => $newRole,
                'updated_by' => $currentUser->id,
            ]);

            Event::dispatch(new MemberRoleUpdated($updatedUser, $oldRole, $newRole));

            return $updatedUser;
        } catch (\Exception $e) {
            Log::error('Failed to update member role', [
                'user_id' => $userId,
                'new_role' => $newRole,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to update member role: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Update a member's permissions.
     *
     * @param string $userId The user ID
     * @param array $permissions Permissions to assign
     * @return User The updated user
     * @throws \RuntimeException
     */
    public function updateMemberPermissions(string $userId, array $permissions): User
    {
        try {
            $user = $this->userRepository->findById($userId);
            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            // Validate permissions
            $validated = $this->validatePermissions($permissions);

            // Store permissions in user settings or separate permissions table
            // For now, we'll use the settings JSON column if available
            $settings = $user->settings ?? [];
            $settings['permissions'] = $validated;

            $updatedUser = $this->userRepository->update($userId, [
                'settings' => $settings,
            ]);

            Log::info('Member permissions updated', [
                'user_id' => $userId,
                'permissions' => $validated,
            ]);

            return $updatedUser;
        } catch (\Exception $e) {
            Log::error('Failed to update member permissions', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to update member permissions: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Remove a member from an organization.
     *
     * @param string $userId The user ID to remove
     * @param string $organizationId The organization ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function removeMember(string $userId, string $organizationId): bool
    {
        try {
            $user = $this->userRepository->findById($userId);
            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            if ($user->organization_id !== $organizationId) {
                throw new \RuntimeException('User does not belong to this organization');
            }

            $currentUser = auth()->user();
            if (!$currentUser) {
                throw new \RuntimeException('Unauthorized');
            }

            // Prevent self-removal
            if ($userId === $currentUser->id) {
                throw new \RuntimeException('Cannot remove yourself from the organization');
            }

            // Prevent removing the last owner
            if ($user->isOwner()) {
                $ownerCount = $this->userRepository->countByRole($organizationId, 'owner');
                if ($ownerCount <= 1) {
                    throw new \RuntimeException('Cannot remove the last owner');
                }
            }

            // Remove user from organization
            $this->userRepository->update($userId, [
                'organization_id' => null,
                'role' => 'member', // Reset to default role
            ]);

            Log::warning('Member removed from organization', [
                'user_id' => $userId,
                'organization_id' => $organizationId,
                'removed_by' => $currentUser->id,
            ]);

            Event::dispatch(new MemberRemoved($user, $organizationId));

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to remove member', [
                'user_id' => $userId,
                'organization_id' => $organizationId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to remove member: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Transfer organization ownership to another member.
     *
     * @param string $organizationId The organization ID
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
        try {
            $currentOwner = $this->userRepository->findById($currentOwnerId);
            if (!$currentOwner || !$currentOwner->isOwner()) {
                throw new \RuntimeException('Current owner not found or invalid');
            }

            $newOwner = $this->userRepository->findById($newOwnerId);
            if (!$newOwner) {
                throw new \RuntimeException('New owner not found');
            }

            if ($newOwner->organization_id !== $organizationId) {
                throw new \RuntimeException('New owner does not belong to this organization');
            }

            if ($currentOwnerId === $newOwnerId) {
                throw new \RuntimeException('Cannot transfer ownership to yourself');
            }

            DB::beginTransaction();
            try {
                // Demote current owner to admin
                $this->userRepository->update($currentOwnerId, [
                    'role' => 'admin',
                ]);

                // Promote new member to owner
                $this->userRepository->update($newOwnerId, [
                    'role' => 'owner',
                ]);

                DB::commit();

                Log::warning('Ownership transferred', [
                    'organization_id' => $organizationId,
                    'from_user_id' => $currentOwnerId,
                    'to_user_id' => $newOwnerId,
                ]);

                Event::dispatch(new OwnershipTransferred(
                    $currentOwner,
                    $newOwner,
                    $organizationId
                ));

                return true;
            } catch (\Exception $e) {
                DB::rollBack();
                throw $e;
            }
        } catch (\Exception $e) {
            Log::error('Ownership transfer failed', [
                'organization_id' => $organizationId,
                'new_owner_id' => $newOwnerId,
                'current_owner_id' => $currentOwnerId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to transfer ownership: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Get pending invitations for an organization.
     *
     * @param string $organizationId The organization ID
     * @return Collection Collection of pending invitations
     */
    public function getPendingInvitations(string $organizationId): Collection
    {
        try {
            $invitations = TeamInvitation::where('organization_id', $organizationId)
                ->pending()
                ->with('inviter')
                ->orderBy('created_at', 'desc')
                ->get();

            Log::debug('Retrieved pending invitations', [
                'organization_id' => $organizationId,
                'count' => $invitations->count(),
            ]);

            return $invitations;
        } catch (\Exception $e) {
            Log::error('Failed to retrieve pending invitations', [
                'organization_id' => $organizationId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to get pending invitations: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Validate invitation data.
     *
     * @param string $email
     * @param string $role
     * @param array $permissions
     * @return array Validated data
     * @throws ValidationException
     */
    private function validateInvitationData(string $email, string $role, array $permissions): array
    {
        $validator = Validator::make([
            'email' => $email,
            'role' => $role,
            'permissions' => $permissions,
        ], [
            'email' => 'required|email|max:255',
            'role' => 'required|string|in:owner,admin,member,viewer',
            'permissions' => 'nullable|array',
        ]);

        if ($validator->fails()) {
            throw new ValidationException($validator);
        }

        return $validator->validated();
    }

    /**
     * Validate permissions array.
     *
     * @param array $permissions
     * @return array Validated permissions
     */
    private function validatePermissions(array $permissions): array
    {
        $allowedPermissions = [
            'manage_sites',
            'manage_backups',
            'manage_billing',
            'view_analytics',
            'manage_team',
        ];

        return array_filter($permissions, function ($permission) use ($allowedPermissions) {
            return in_array($permission, $allowedPermissions);
        });
    }
}
