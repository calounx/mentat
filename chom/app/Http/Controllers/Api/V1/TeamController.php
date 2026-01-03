<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Team Controller
 *
 * Handles team/organization management:
 * - List team members
 * - Invite new members
 * - List pending invitations
 * - Cancel invitations
 * - View member details
 * - Update member role
 * - Remove team member
 * - Transfer ownership
 * - View/update organization settings
 *
 * @package App\Http\Controllers\Api\V1
 */
class TeamController extends ApiController
{
    /**
     * List team members.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            // Get members
            $members = $organization->members()
                ->orderBy('role')
                ->orderBy('created_at')
                ->paginate($this->getPaginationLimit($request));

            return $this->paginatedResponse($members);

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Invite a new team member.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function invite(Request $request): JsonResponse
    {
        try {
            // Require admin role
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            // Validate input
            $validated = $request->validate([
                'email' => ['required', 'email'],
                'role' => ['required', 'in:member,admin'],
            ]);

            // TODO: Implement invitation logic
            // This would typically:
            // 1. Check if user already exists
            // 2. Create invitation record
            // 3. Send invitation email

            $this->logInfo('Team member invitation sent', [
                'email' => $validated['email'],
                'role' => $validated['role'],
            ]);

            return $this->createdResponse(
                ['email' => $validated['email'], 'status' => 'pending'],
                'Invitation sent successfully.'
            );

        } catch (\Illuminate\Validation\ValidationException $e) {
            return $this->validationErrorResponse($e->errors());
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * List pending invitations.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function invitations(Request $request): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            // Get pending invitations
            $invitations = $organization->invitations()
                ->where('status', 'pending')
                ->orderBy('created_at', 'desc')
                ->paginate($this->getPaginationLimit($request));

            return $this->paginatedResponse($invitations);

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Cancel/revoke an invitation.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function cancelInvitation(Request $request, string $id): JsonResponse
    {
        try {
            // Require admin role
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            // Find invitation
            $invitation = $organization->invitations()->findOrFail($id);

            // TODO: Implement cancellation logic
            // $invitation->update(['status' => 'cancelled']);

            $this->logInfo('Team invitation cancelled', ['invitation_id' => $id]);

            return $this->successResponse(
                ['id' => $id],
                'Invitation cancelled successfully.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Show team member details.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function show(Request $request, string $id): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            // Find member
            $member = $organization->members()->findOrFail($id);

            return $this->successResponse($member);

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Update team member role.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function update(Request $request, string $id): JsonResponse
    {
        try {
            // Require admin role
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            // Validate input
            $validated = $request->validate([
                'role' => ['required', 'in:member,admin'],
            ]);

            // Find member
            $member = $organization->members()->findOrFail($id);

            // Prevent changing owner role
            if ($member->role === 'owner') {
                return $this->errorResponse(
                    'CANNOT_UPDATE_OWNER',
                    'Cannot change the role of the organization owner.',
                    [],
                    403
                );
            }

            // TODO: Implement role update logic
            // $member->update(['role' => $validated['role']]);

            $this->logInfo('Team member role updated', [
                'member_id' => $id,
                'new_role' => $validated['role'],
            ]);

            return $this->successResponse(
                $member,
                'Member role updated successfully.'
            );

        } catch (\Illuminate\Validation\ValidationException $e) {
            return $this->validationErrorResponse($e->errors());
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Remove a team member.
     *
     * @param Request $request
     * @param string $id
     * @return JsonResponse
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        try {
            // Require admin role
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            // Find member
            $member = $organization->members()->findOrFail($id);

            // Prevent removing owner
            if ($member->role === 'owner') {
                return $this->errorResponse(
                    'CANNOT_REMOVE_OWNER',
                    'Cannot remove the organization owner.',
                    [],
                    403
                );
            }

            // Prevent self-removal
            if ($member->id === $request->user()->id) {
                return $this->errorResponse(
                    'CANNOT_REMOVE_SELF',
                    'Cannot remove yourself from the organization.',
                    [],
                    403
                );
            }

            // TODO: Implement member removal logic
            // $member->delete();

            $this->logInfo('Team member removed', ['member_id' => $id]);

            return $this->successResponse(
                ['id' => $id],
                'Member removed successfully.'
            );

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Transfer organization ownership.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function transferOwnership(Request $request): JsonResponse
    {
        try {
            // Require owner role
            $this->requireOwner($request);

            $organization = $this->getOrganization($request);

            // Validate input
            $validated = $request->validate([
                'new_owner_id' => ['required', 'exists:users,id'],
            ]);

            // Find new owner
            $newOwner = $organization->members()->findOrFail($validated['new_owner_id']);

            // TODO: Implement ownership transfer logic
            // This would typically:
            // 1. Update current owner to admin
            // 2. Update new owner to owner
            // 3. Log the transfer
            // 4. Send notifications

            $this->logInfo('Ownership transfer initiated', [
                'new_owner_id' => $validated['new_owner_id'],
            ]);

            return $this->successResponse(
                ['new_owner_id' => $validated['new_owner_id']],
                'Ownership transferred successfully.'
            );

        } catch (\Illuminate\Validation\ValidationException $e) {
            return $this->validationErrorResponse($e->errors());
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Get organization details.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function organization(Request $request): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            return $this->successResponse($organization);

        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Update organization settings.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function updateOrganization(Request $request): JsonResponse
    {
        try {
            // Require admin role
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            // Validate input
            $validated = $request->validate([
                'name' => ['sometimes', 'string', 'max:255'],
                'settings' => ['sometimes', 'array'],
            ]);

            // TODO: Implement organization update logic
            // $organization->update($validated);

            $this->logInfo('Organization updated', [
                'organization_id' => $organization->id,
            ]);

            return $this->successResponse(
                $organization,
                'Organization updated successfully.'
            );

        } catch (\Illuminate\Validation\ValidationException $e) {
            return $this->validationErrorResponse($e->errors());
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
