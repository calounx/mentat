<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\InviteTeamMemberRequest;
use App\Http\Requests\UpdateOrganizationRequest;
use App\Http\Requests\UpdateTeamMemberRequest;
use App\Http\Resources\TeamMemberResource;
use App\Repositories\TenantRepository;
use App\Repositories\UserRepository;
use App\Services\TeamManagementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Team Controller
 *
 * Handles team/organization management through repository and service patterns.
 * Controllers are kept thin - business logic delegated to services.
 *
 * @package App\Http\Controllers\Api\V1
 */
class TeamController extends ApiController
{
    public function __construct(
        private readonly UserRepository $userRepository,
        private readonly TenantRepository $tenantRepository,
        private readonly TeamManagementService $teamManagementService
    ) {}

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

            $members = $this->userRepository->findByOrganization(
                $organization->id,
                $this->getPaginationLimit($request)
            );

            return $this->paginatedResponse(
                $members,
                fn($member) => new TeamMemberResource($member)
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Invite a new team member.
     *
     * @param InviteTeamMemberRequest $request
     * @return JsonResponse
     */
    public function invite(InviteTeamMemberRequest $request): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            $invitation = $this->teamManagementService->inviteMember(
                $organization->id,
                $request->validated()['email'],
                $request->validated()['role'],
                $request->user()->id
            );

            return $this->createdResponse(
                $invitation,
                'Invitation sent successfully.'
            );
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

            $invitations = $this->teamManagementService->getPendingInvitations(
                $organization->id,
                $this->getPaginationLimit($request)
            );

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
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            $this->teamManagementService->cancelInvitation($id, $organization->id);

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

            $member = $this->userRepository->findById($id);

            if (!$member || $member->organization_id !== $organization->id) {
                abort(404, 'Team member not found.');
            }

            return $this->successResponse(new TeamMemberResource($member));
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }

    /**
     * Update team member role.
     *
     * @param UpdateTeamMemberRequest $request
     * @param string $id
     * @return JsonResponse
     */
    public function update(UpdateTeamMemberRequest $request, string $id): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            $member = $this->teamManagementService->updateMemberRole(
                $id,
                $organization->id,
                $request->validated()['role']
            );

            return $this->successResponse(
                new TeamMemberResource($member),
                'Member role updated successfully.'
            );
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
            $this->requireAdmin($request);

            $organization = $this->getOrganization($request);

            if ($id === $request->user()->id) {
                return $this->errorResponse(
                    'CANNOT_REMOVE_SELF',
                    'Cannot remove yourself from the organization.',
                    [],
                    403
                );
            }

            $this->teamManagementService->removeMember($id, $organization->id);

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
            $this->requireOwner($request);

            $organization = $this->getOrganization($request);

            $validated = $request->validate([
                'new_owner_id' => ['required', 'exists:users,id'],
            ]);

            $this->teamManagementService->transferOwnership(
                $organization->id,
                $request->user()->id,
                $validated['new_owner_id']
            );

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
     * @param UpdateOrganizationRequest $request
     * @return JsonResponse
     */
    public function updateOrganization(UpdateOrganizationRequest $request): JsonResponse
    {
        try {
            $organization = $this->getOrganization($request);

            $updatedOrganization = $this->tenantRepository->update(
                $organization->id,
                $request->validated()
            );

            return $this->successResponse(
                $updatedOrganization,
                'Organization updated successfully.'
            );
        } catch (\Exception $e) {
            return $this->handleException($e);
        }
    }
}
