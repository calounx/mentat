<?php

declare(strict_types=1);

namespace App\Modules\Team\Contracts;

use App\Models\TeamInvitation;
use Illuminate\Database\Eloquent\Collection;

/**
 * Team Invitation Service Contract
 *
 * Defines the contract for team invitation operations.
 */
interface InvitationInterface
{
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
    public function send(string $organizationId, string $email, string $role, array $permissions = []): TeamInvitation;

    /**
     * Accept an invitation.
     *
     * @param string $token Invitation token
     * @param string $userId User ID accepting
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function accept(string $token, string $userId): bool;

    /**
     * Cancel a pending invitation.
     *
     * @param string $invitationId Invitation ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function cancel(string $invitationId): bool;

    /**
     * Resend an invitation.
     *
     * @param string $invitationId Invitation ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function resend(string $invitationId): bool;

    /**
     * Get pending invitations for organization.
     *
     * @param string $organizationId Organization ID
     * @return Collection Pending invitations
     */
    public function getPending(string $organizationId): Collection;

    /**
     * Check if invitation is valid.
     *
     * @param string $token Invitation token
     * @return bool Validity status
     */
    public function isValid(string $token): bool;
}
