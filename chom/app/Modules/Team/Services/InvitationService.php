<?php

declare(strict_types=1);

namespace App\Modules\Team\Services;

use App\Mail\TeamInvitationMail;
use App\Models\TeamInvitation;
use App\Modules\Team\Contracts\InvitationInterface;
use App\Services\TeamManagementService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * Invitation Service
 *
 * Handles team invitation operations with extended functionality.
 */
class InvitationService implements InvitationInterface
{
    public function __construct(
        private readonly TeamManagementService $teamManagementService
    ) {
    }

    /**
     * Send invitation to join team.
     *
     * @param string $organizationId Organization ID
     * @param string $email Invitee email
     * @param string $role Role to assign
     * @param array $permissions Additional permissions
     * @return TeamInvitation Created invitation
     * @throws \RuntimeException
     */
    public function send(string $organizationId, string $email, string $role, array $permissions = []): TeamInvitation
    {
        Log::info('Team module: Sending invitation', [
            'organization_id' => $organizationId,
            'email' => $email,
            'role' => $role,
        ]);

        return $this->teamManagementService->inviteMember(
            $organizationId,
            $email,
            $role,
            $permissions
        );
    }

    /**
     * Accept an invitation.
     *
     * @param string $token Invitation token
     * @param string $userId User ID accepting
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function accept(string $token, string $userId): bool
    {
        Log::info('Team module: Accepting invitation', [
            'user_id' => $userId,
        ]);

        return $this->teamManagementService->acceptInvitation($token, $userId);
    }

    /**
     * Cancel a pending invitation.
     *
     * @param string $invitationId Invitation ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function cancel(string $invitationId): bool
    {
        Log::info('Team module: Cancelling invitation', [
            'invitation_id' => $invitationId,
        ]);

        return $this->teamManagementService->cancelInvitation($invitationId);
    }

    /**
     * Resend an invitation.
     *
     * @param string $invitationId Invitation ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function resend(string $invitationId): bool
    {
        try {
            $invitation = TeamInvitation::find($invitationId);

            if (!$invitation) {
                throw new \RuntimeException('Invitation not found');
            }

            if ($invitation->isAccepted()) {
                throw new \RuntimeException('Cannot resend an accepted invitation');
            }

            if ($invitation->isExpired()) {
                throw new \RuntimeException('Cannot resend an expired invitation');
            }

            Mail::to($invitation->email)->send(new TeamInvitationMail($invitation));

            Log::info('Invitation resent', [
                'invitation_id' => $invitationId,
                'email' => $invitation->email,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to resend invitation', [
                'invitation_id' => $invitationId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to resend invitation: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Get pending invitations for organization.
     *
     * @param string $organizationId Organization ID
     * @return Collection Pending invitations
     */
    public function getPending(string $organizationId): Collection
    {
        return $this->teamManagementService->getPendingInvitations($organizationId);
    }

    /**
     * Check if invitation is valid.
     *
     * @param string $token Invitation token
     * @return bool Validity status
     */
    public function isValid(string $token): bool
    {
        try {
            $invitation = TeamInvitation::where('token', $token)->first();

            if (!$invitation) {
                return false;
            }

            return !$invitation->isExpired() && !$invitation->isAccepted();
        } catch (\Exception $e) {
            Log::error('Invitation validation failed', [
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }
}
