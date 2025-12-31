<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Concerns\HasTenantScoping;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class TeamController extends Controller
{
    use HasTenantScoping;
    /**
     * List all team members in the organization.
     */
    public function index(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);

        $members = $organization->users()
            ->orderByRaw("FIELD(role, 'owner', 'admin', 'member', 'viewer')")
            ->orderBy('name')
            ->paginate($request->input('per_page', 20));

        return response()->json([
            'success' => true,
            'data' => collect($members->items())->map(fn($user) => $this->formatMember($user)),
            'meta' => [
                'pagination' => [
                    'current_page' => $members->currentPage(),
                    'per_page' => $members->perPage(),
                    'total' => $members->total(),
                    'total_pages' => $members->lastPage(),
                ],
            ],
        ]);
    }

    /**
     * Get specific team member details.
     */
    public function show(Request $request, string $id): JsonResponse
    {
        $organization = $this->getOrganization($request);

        $member = $organization->users()->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $this->formatMember($member, detailed: true),
        ]);
    }

    /**
     * Update team member role.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only owners and admins can update roles
        if (!$currentUser->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'You do not have permission to update team members.',
                ],
            ], 403);
        }

        $member = $organization->users()->findOrFail($id);

        // Cannot modify the owner's role
        if ($member->isOwner()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANNOT_MODIFY_OWNER',
                    'message' => 'Cannot modify the organization owner\'s role.',
                ],
            ], 400);
        }

        // Admins cannot promote to owner or admin
        if (!$currentUser->isOwner()) {
            $validated = $request->validate([
                'role' => ['required', 'in:member,viewer'],
            ]);
        } else {
            $validated = $request->validate([
                'role' => ['required', 'in:admin,member,viewer'],
            ]);
        }

        $member->update(['role' => $validated['role']]);

        return response()->json([
            'success' => true,
            'data' => $this->formatMember($member->fresh()),
            'message' => 'Team member role updated successfully.',
        ]);
    }

    /**
     * Remove team member from organization.
     */
    public function destroy(Request $request, string $id): JsonResponse
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

        $member = $organization->users()->findOrFail($id);

        // Cannot remove yourself
        if ($member->id === $currentUser->id) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'CANNOT_REMOVE_SELF',
                    'message' => 'You cannot remove yourself from the organization.',
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
                    'code' => 'CANNOT_REMOVE_ADMIN',
                    'message' => 'Only the organization owner can remove administrators.',
                ],
            ], 403);
        }

        try {
            // Revoke all tokens
            $member->tokens()->delete();

            // Remove from organization
            $member->update([
                'organization_id' => null,
                'role' => 'viewer',
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Team member removed successfully.',
            ]);

        } catch (\Exception $e) {
            Log::error('Failed to remove team member', [
                'member_id' => $id,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'REMOVAL_FAILED',
                    'message' => 'Failed to remove team member.',
                ],
            ], 500);
        }
    }

    /**
     * Invite a new team member.
     */
    public function invite(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        // Only owners and admins can invite
        if (!$currentUser->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'You do not have permission to invite team members.',
                ],
            ], 403);
        }

        // Admins cannot invite as admin or owner
        if ($currentUser->isOwner()) {
            $validated = $request->validate([
                'email' => ['required', 'email', 'max:255'],
                'role' => ['required', 'in:admin,member,viewer'],
                'name' => ['sometimes', 'string', 'max:255'],
            ]);
        } else {
            $validated = $request->validate([
                'email' => ['required', 'email', 'max:255'],
                'role' => ['required', 'in:member,viewer'],
                'name' => ['sometimes', 'string', 'max:255'],
            ]);
        }

        // Check if user already exists in organization
        $existingUser = User::where('email', $validated['email'])
            ->where('organization_id', $organization->id)
            ->first();

        if ($existingUser) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'ALREADY_MEMBER',
                    'message' => 'This user is already a member of your organization.',
                ],
            ], 400);
        }

        // TODO: Implement invitation system with email verification
        // For now, return a placeholder response

        return response()->json([
            'success' => true,
            'message' => 'Invitation sent successfully.',
            'data' => [
                'email' => $validated['email'],
                'role' => $validated['role'],
                'expires_at' => now()->addDays(7)->toIso8601String(),
            ],
        ], 201);
    }

    /**
     * List pending invitations.
     */
    public function invitations(Request $request): JsonResponse
    {
        $organization = $this->getOrganization($request);

        // TODO: Implement invitation listing from database
        // For now, return empty list

        return response()->json([
            'success' => true,
            'data' => [],
            'meta' => [
                'pagination' => [
                    'current_page' => 1,
                    'per_page' => 20,
                    'total' => 0,
                    'total_pages' => 0,
                ],
            ],
        ]);
    }

    /**
     * Cancel a pending invitation.
     */
    public function cancelInvitation(Request $request, string $id): JsonResponse
    {
        $organization = $this->getOrganization($request);
        $currentUser = $request->user();

        if (!$currentUser->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'You do not have permission to cancel invitations.',
                ],
            ], 403);
        }

        // TODO: Implement invitation cancellation
        // For now, return success

        return response()->json([
            'success' => true,
            'message' => 'Invitation cancelled successfully.',
        ]);
    }

    /**
     * Transfer organization ownership.
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
            'user_id' => ['required', 'uuid'],
            'password' => ['required', 'string'], // Require password confirmation
        ]);

        // Verify password
        if (!\Hash::check($validated['password'], $currentUser->password)) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVALID_PASSWORD',
                    'message' => 'The password you entered is incorrect.',
                ],
            ], 401);
        }

        $newOwner = $organization->users()->findOrFail($validated['user_id']);

        try {
            DB::transaction(function () use ($currentUser, $newOwner) {
                // Transfer ownership
                $newOwner->update(['role' => 'owner']);
                $currentUser->update(['role' => 'admin']);
            });

            return response()->json([
                'success' => true,
                'message' => 'Ownership transferred successfully.',
                'data' => [
                    'new_owner' => $this->formatMember($newOwner->fresh()),
                    'previous_owner' => $this->formatMember($currentUser->fresh()),
                ],
            ]);

        } catch (\Exception $e) {
            Log::error('Ownership transfer failed', [
                'from' => $currentUser->id,
                'to' => $newOwner->id,
                'error' => $e->getMessage(),
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

    /**
     * Get organization details.
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
        ]);
    }

    /**
     * Update organization settings.
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

        $organization->update($validated);

        return response()->json([
            'success' => true,
            'data' => [
                'id' => $organization->id,
                'name' => $organization->name,
                'slug' => $organization->slug,
                'billing_email' => $organization->billing_email,
            ],
            'message' => 'Organization updated successfully.',
        ]);
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    private function getOrganization(Request $request): Organization
    {
        $organization = $request->user()->organization;

        if (!$organization) {
            abort(403, 'No organization found.');
        }

        return $organization;
    }

    private function formatMember(User $user, bool $detailed = false): array
    {
        $data = [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'role' => $user->role,
            'email_verified' => !is_null($user->email_verified_at),
            'created_at' => $user->created_at->toIso8601String(),
        ];

        if ($detailed) {
            $data['two_factor_enabled'] = $user->two_factor_enabled;
            $data['updated_at'] = $user->updated_at->toIso8601String();
        }

        return $data;
    }
}
