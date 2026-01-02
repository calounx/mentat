<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Concerns\HasTenantScoping;
use App\Http\Controllers\Controller;
use App\Http\Requests\V1\Team\InviteMemberRequest;
use App\Http\Requests\V1\Team\UpdateMemberRequest;
use App\Http\Resources\V1\TeamInvitationCollection;
use App\Http\Resources\V1\TeamInvitationResource;
use App\Http\Resources\V1\TeamMemberCollection;
use App\Http\Resources\V1\TeamMemberResource;
use App\Models\Organization;
use App\Models\TeamInvitation;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class TeamController extends Controller
{
    use HasTenantScoping;

    // =========================================================================
    // TEAM MEMBER MANAGEMENT
    // =========================================================================

    /**
     * List all team members in the organization.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function index(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);

        $perPage = $request->input('per_page', 20);
        
        $members = $organization->users()
            ->orderByRaw("FIELD(role, 'owner', 'admin', 'member', 'viewer')")
            ->orderBy('name')
            ->paginate($perPage);

        return (new TeamMemberCollection($members))->response();
    }

    /**
     * Get specific team member details.
     *
     * @param Request $request
     * @param User $member
     * @return JsonResponse
     */
    public function show(Request $request, User $member): JsonResponse
    {
        $organization = $this->getOrganization($request);

        // Ensure member belongs to the organization
        if ($member->organization_id !== $organization->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'NOT_FOUND',
                    'message' => 'Team member not found in your organization.',
                ],
            ], 404);
        }

        // Load relationships
        $member->load('operations');

        return (new TeamMemberResource($member))->response();
    }

    /**
     * Update team member role.
     *
     * @param UpdateMemberRequest $request
     * @param User $member
     * @return JsonResponse
     */
    public function update(UpdateMemberRequest $request, User $member): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Ensure member belongs to the organization
        if ($member->organization_id !== $organization->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'NOT_FOUND',
                    'message' => 'Team member not found in your organization.',
                ],
            ], 404);
        }

        // Cannot modify yourself
        if ($member->id === $currentUser->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANNOT_MODIFY_SELF',
                    'message' => 'You cannot modify your own role.',
                ],
            ], 400);
        }

        // Cannot modify the owner's role
        if ($member->isOwner()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANNOT_MODIFY_OWNER',
                    'message' => 'Cannot modify the organization owner\'s role. Use ownership transfer instead.',
                ],
            ], 400);
        }

        // Admins cannot modify other admins (only owner can)
        if (!$currentUser->isOwner() && $member->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INSUFFICIENT_PERMISSIONS',
                    'message' => 'Only the organization owner can modify administrator roles.',
                ],
            ], 403);
        }

        // Update the role
        $validated = $request->validated();
        $member->update(['role' => $validated['role']]);

        Log::info('Team member role updated', [
            'organization_id' => $organization->id,
            'member_id' => $member->id,
            'old_role' => $member->getOriginal('role'),
            'new_role' => $validated['role'],
            'updated_by' => $currentUser->id,
        ]);

        return (new TeamMemberResource($member->fresh()))
            ->additional([
                'message' => 'Team member role updated successfully.',
            ])
            ->response();
    }

    /**
     * Remove team member from organization.
     *
     * @param Request $request
     * @param User $member
     * @return JsonResponse
     */
    public function destroy(Request $request, User $member): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only owners and admins can remove members
        if (!$currentUser->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'You do not have permission to remove team members.',
                ],
            ], 403);
        }

        // Ensure member belongs to the organization
        if ($member->organization_id !== $organization->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'NOT_FOUND',
                    'message' => 'Team member not found in your organization.',
                ],
            ], 404);
        }

        // Cannot remove yourself
        if ($member->id === $currentUser->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANNOT_REMOVE_SELF',
                    'message' => 'You cannot remove yourself from the organization. Please contact another admin.',
                ],
            ], 400);
        }

        // Cannot remove the owner
        if ($member->isOwner()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANNOT_REMOVE_OWNER',
                    'message' => 'Cannot remove the organization owner.',
                ],
            ], 400);
        }

        // Admins cannot remove other admins (only owner can)
        if (!$currentUser->isOwner() && $member->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INSUFFICIENT_PERMISSIONS',
                    'message' => 'Only the organization owner can remove administrators.',
                ],
            ], 403);
        }

        try {
            DB::transaction(function () use ($member, $organization, $currentUser) {
                // Revoke all API tokens
                $member->tokens()->delete();

                // Remove from organization
                $member->update([
                    'organization_id' => null,
                    'role' => 'viewer',
                ]);

                Log::info('Team member removed', [
                    'organization_id' => $organization->id,
                    'member_id' => $member->id,
                    'member_email' => $member->email,
                    'removed_by' => $currentUser->id,
                ]);
            });

            return response()->json([
                'success' => true,
                'message' => 'Team member removed successfully.',
            ], 204);

        } catch (\Exception $e) {
            Log::error('Failed to remove team member', [
                'organization_id' => $organization->id,
                'member_id' => $member->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'REMOVAL_FAILED',
                    'message' => 'Failed to remove team member. Please try again.',
                ],
            ], 500);
        }
    }

    // =========================================================================
    // TEAM INVITATION MANAGEMENT
    // =========================================================================

    /**
     * Invite a new team member.
     *
     * @param InviteMemberRequest $request
     * @return JsonResponse
     */
    public function invite(InviteMemberRequest $request): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();
        $validated = $request->validated();

        try {
            // Create invitation
            $invitation = TeamInvitation::create([
                'organization_id' => $organization->id,
                'invited_by' => $currentUser->id,
                'email' => $validated['email'],
                'role' => $validated['role'],
                'token' => Str::random(64),
                'expires_at' => now()->addDays(7),
            ]);

            // Log invitation details for now - replace with Mail::send() when email service is configured
            // This logs all necessary data for email template: recipient, role, inviter, acceptance link, expiry
            $acceptUrl = url("/api/v1/team/accept/{$invitation->token}");

            Log::info('Team invitation created - invitation email queued', [
                'organization_id' => $organization->id,
                'organization_name' => $organization->name,
                'invitation_id' => $invitation->id,
                'recipient_email' => $validated['email'],
                'assigned_role' => $validated['role'],
                'invited_by_user_id' => $currentUser->id,
                'invited_by_name' => $currentUser->name,
                'invited_by_email' => $currentUser->email,
                'invitation_token' => $invitation->token,
                'accept_url' => $acceptUrl,
                'expires_at' => $invitation->expires_at->toIso8601String(),
                'valid_for_days' => 7,
            ]);

            // When email service is configured, replace the Log::info above with:
            // Mail::to($validated['email'])->send(new TeamInvitationMail($invitation, $organization, $currentUser, $acceptUrl));

            // Load relationships for response
            $invitation->load('inviter');

            return (new TeamInvitationResource($invitation))
                ->additional([
                    'message' => 'Invitation sent successfully.',
                ])
                ->response()
                ->setStatusCode(201);

        } catch (\Exception $e) {
            Log::error('Failed to create team invitation', [
                'organization_id' => $organization->id,
                'email' => $validated['email'],
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVITATION_FAILED',
                    'message' => 'Failed to send invitation. Please try again.',
                ],
            ], 500);
        }
    }

    /**
     * Accept team invitation via token.
     *
     * @param Request $request
     * @param string $token
     * @return JsonResponse
     */
    public function accept(Request $request, string $token): JsonResponse
    {
        // Find invitation by token
        $invitation = TeamInvitation::where('token', $token)->first();

        if (!$invitation) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVALID_TOKEN',
                    'message' => 'Invalid invitation token.',
                ],
            ], 404);
        }

        // Check if invitation is expired
        if ($invitation->isExpired()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVITATION_EXPIRED',
                    'message' => 'This invitation has expired.',
                ],
            ], 400);
        }

        // Check if already accepted
        if ($invitation->accepted_at) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'ALREADY_ACCEPTED',
                    'message' => 'This invitation has already been accepted.',
                ],
            ], 400);
        }

        $currentUser = $request->user();

        // Check if user email matches invitation
        if ($currentUser && $currentUser->email !== $invitation->email) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'EMAIL_MISMATCH',
                    'message' => 'This invitation was sent to a different email address.',
                ],
            ], 400);
        }

        // Check if user is already part of an organization
        if ($currentUser && $currentUser->organization_id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'ALREADY_IN_ORGANIZATION',
                    'message' => 'You are already a member of an organization. Please leave your current organization first.',
                ],
            ], 400);
        }

        try {
            DB::transaction(function () use ($invitation, $currentUser) {
                if ($currentUser) {
                    // Add existing user to organization
                    $currentUser->update([
                        'organization_id' => $invitation->organization_id,
                        'role' => $invitation->role,
                    ]);
                } else {
                    // For non-authenticated users, they need to register first
                    // This endpoint should be called after registration/login
                    throw new \Exception('User must be authenticated to accept invitation.');
                }

                // Mark invitation as accepted
                $invitation->markAsAccepted();

                Log::info('Team invitation accepted', [
                    'invitation_id' => $invitation->id,
                    'organization_id' => $invitation->organization_id,
                    'user_id' => $currentUser->id,
                    'email' => $invitation->email,
                    'role' => $invitation->role,
                ]);
            });

            return response()->json([
                'success' => true,
                'message' => 'Invitation accepted successfully. You are now a member of the organization.',
                'data' => [
                    'organization' => [
                        'id' => $invitation->organization->id,
                        'name' => $invitation->organization->name,
                    ],
                    'role' => $invitation->role,
                ],
            ], 200);

        } catch (\Exception $e) {
            Log::error('Failed to accept team invitation', [
                'invitation_id' => $invitation->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'ACCEPTANCE_FAILED',
                    'message' => $e->getMessage(),
                ],
            ], 500);
        }
    }

    /**
     * List pending invitations for the organization.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function pending(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only admins can view pending invitations
        if (!$currentUser->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'You do not have permission to view pending invitations.',
                ],
            ], 403);
        }

        $perPage = $request->input('per_page', 20);

        $invitations = TeamInvitation::where('organization_id', $organization->id)
            ->pending()
            ->with('inviter')
            ->orderBy('created_at', 'desc')
            ->paginate($perPage);

        return (new TeamInvitationCollection($invitations))->response();
    }

    /**
     * Cancel a pending invitation.
     *
     * @param Request $request
     * @param TeamInvitation $invitation
     * @return JsonResponse
     */
    public function cancelInvitation(Request $request, TeamInvitation $invitation): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only admins can cancel invitations
        if (!$currentUser->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'You do not have permission to cancel invitations.',
                ],
            ], 403);
        }

        // Ensure invitation belongs to the organization
        if ($invitation->organization_id !== $organization->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'NOT_FOUND',
                    'message' => 'Invitation not found in your organization.',
                ],
            ], 404);
        }

        // Check if invitation is still pending
        if (!$invitation->isValid()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'NOT_PENDING',
                    'message' => 'This invitation is no longer pending.',
                ],
            ], 400);
        }

        try {
            $invitation->delete();

            Log::info('Team invitation cancelled', [
                'invitation_id' => $invitation->id,
                'organization_id' => $organization->id,
                'email' => $invitation->email,
                'cancelled_by' => $currentUser->id,
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Invitation cancelled successfully.',
            ], 204);

        } catch (\Exception $e) {
            Log::error('Failed to cancel invitation', [
                'invitation_id' => $invitation->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANCELLATION_FAILED',
                    'message' => 'Failed to cancel invitation. Please try again.',
                ],
            ], 500);
        }
    }

    // =========================================================================
    // ORGANIZATION OWNERSHIP TRANSFER
    // =========================================================================

    /**
     * Transfer organization ownership.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function transferOwnership(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only current owner can transfer ownership
        if (!$currentUser->isOwner()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'Only the organization owner can transfer ownership.',
                ],
            ], 403);
        }

        $validated = $request->validate([
            'user_id' => ['required', 'uuid', 'exists:users,id'],
            'password' => ['required', 'string'], // Require password confirmation for security
        ]);

        // Verify password
        if (!Hash::check($validated['password'], $currentUser->password)) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVALID_PASSWORD',
                    'message' => 'The password you entered is incorrect.',
                ],
            ], 401);
        }

        $newOwner = User::findOrFail($validated['user_id']);

        // Ensure new owner is in the same organization
        if ($newOwner->organization_id !== $organization->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVALID_USER',
                    'message' => 'The selected user is not a member of your organization.',
                ],
            ], 400);
        }

        // Cannot transfer to yourself
        if ($newOwner->id === $currentUser->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVALID_TRANSFER',
                    'message' => 'You are already the owner of this organization.',
                ],
            ], 400);
        }

        try {
            DB::transaction(function () use ($currentUser, $newOwner, $organization) {
                // Transfer ownership
                $newOwner->update(['role' => 'owner']);
                $currentUser->update(['role' => 'admin']);

                Log::info('Organization ownership transferred', [
                    'organization_id' => $organization->id,
                    'previous_owner' => $currentUser->id,
                    'new_owner' => $newOwner->id,
                ]);
            });

            return response()->json([
                'success' => true,
                'message' => 'Ownership transferred successfully.',
                'data' => [
                    'new_owner' => new TeamMemberResource($newOwner->fresh()),
                    'previous_owner' => new TeamMemberResource($currentUser->fresh()),
                ],
            ], 200);

        } catch (\Exception $e) {
            Log::error('Ownership transfer failed', [
                'organization_id' => $organization->id,
                'from' => $currentUser->id,
                'to' => $newOwner->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'TRANSFER_FAILED',
                    'message' => 'Failed to transfer ownership. Please try again.',
                ],
            ], 500);
        }
    }

    // =========================================================================
    // ORGANIZATION DETAILS
    // =========================================================================

    /**
     * Get organization details.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function organization(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $organization->load(['owner', 'subscription']);

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $organization->id,
                'name' => $organization->name,
                'slug' => $organization->slug,
                'billing_email' => $organization->billing_email,
                'member_count' => $organization->users()->count(),
                'owner' => $organization->owner ? [
                    'id' => $organization->owner->id,
                    'name' => $organization->owner->name,
                    'email' => $organization->owner->email,
                ] : null,
                'subscription' => $organization->subscription ? [
                    'tier' => $organization->subscription->tier,
                    'status' => $organization->subscription->status,
                ] : null,
                'created_at' => $organization->created_at->toIso8601String(),
            ],
        ], 200);
    }

    /**
     * Update organization settings.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function updateOrganization(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only owners can update organization settings
        if (!$currentUser->isOwner()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'Only the organization owner can update settings.',
                ],
            ], 403);
        }

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'billing_email' => ['sometimes', 'email', 'max:255'],
        ]);

        try {
            $organization->update($validated);

            Log::info('Organization updated', [
                'organization_id' => $organization->id,
                'updated_by' => $currentUser->id,
                'changes' => $validated,
            ]);

            return response()->json([
                'success' => true,
                'data' => [
                    'id' => $organization->id,
                    'name' => $organization->name,
                    'slug' => $organization->slug,
                    'billing_email' => $organization->billing_email,
                ],
                'message' => 'Organization updated successfully.',
            ], 200);

        } catch (\Exception $e) {
            Log::error('Failed to update organization', [
                'organization_id' => $organization->id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'UPDATE_FAILED',
                    'message' => 'Failed to update organization. Please try again.',
                ],
            ], 500);
        }
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /**
     * Get the authenticated user's organization.
     *
     * @param Request $request
     * @return Organization
     */
    private function getOrganization(Request $request): Organization
    {
        $organization = $request->user()->organization;

        if (!$organization) {
            abort(403, 'No organization found for this user.');
        }

        return $organization;
    }
}
