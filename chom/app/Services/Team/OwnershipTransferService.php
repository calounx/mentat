<?php

namespace App\Services\Team;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

/**
 * Ownership Transfer Service
 *
 * Handles the critical operation of transferring organization ownership.
 * Requires password confirmation and performs atomic transaction.
 */
class OwnershipTransferService
{
    /**
     * Transfer organization ownership to a new owner.
     *
     * This is a critical operation that:
     * 1. Validates current owner's password
     * 2. Validates new owner is a member
     * 3. Transfers ownership in atomic transaction
     * 4. Demotes current owner to admin
     *
     * @param Organization $organization
     * @param User $currentOwner
     * @param User $newOwner
     * @param string $password Current owner's password for confirmation
     * @return array{success: bool, message: string, data?: array}
     */
    public function transferOwnership(
        Organization $organization,
        User $currentOwner,
        User $newOwner,
        string $password
    ): array {
        // Validate current owner
        if (!$currentOwner->isOwner()) {
            return [
                'success' => false,
                'message' => 'Only the organization owner can transfer ownership',
            ];
        }

        // Verify password
        if (!Hash::check($password, $currentOwner->password)) {
            return [
                'success' => false,
                'message' => 'The password you entered is incorrect',
            ];
        }

        // Validate new owner is in organization
        if ($newOwner->organization_id !== $organization->id) {
            return [
                'success' => false,
                'message' => 'New owner must be a member of the organization',
            ];
        }

        // Cannot transfer to self
        if ($currentOwner->id === $newOwner->id) {
            return [
                'success' => false,
                'message' => 'Cannot transfer ownership to yourself',
            ];
        }

        try {
            DB::transaction(function () use ($currentOwner, $newOwner, $organization) {
                // Transfer ownership
                $newOwner->update(['role' => 'owner']);
                $currentOwner->update(['role' => 'admin']);

                // Log the transfer
                Log::warning('Organization ownership transferred', [
                    'organization_id' => $organization->id,
                    'from_user_id' => $currentOwner->id,
                    'to_user_id' => $newOwner->id,
                    'from_email' => $currentOwner->email,
                    'to_email' => $newOwner->email,
                ]);
            });

            return [
                'success' => true,
                'message' => 'Ownership transferred successfully',
                'data' => [
                    'new_owner' => [
                        'id' => $newOwner->id,
                        'name' => $newOwner->name,
                        'email' => $newOwner->email,
                        'role' => 'owner',
                    ],
                    'previous_owner' => [
                        'id' => $currentOwner->id,
                        'name' => $currentOwner->name,
                        'email' => $currentOwner->email,
                        'role' => 'admin',
                    ],
                ],
            ];

        } catch (\Exception $e) {
            Log::error('Ownership transfer failed', [
                'organization_id' => $organization->id,
                'from_user_id' => $currentOwner->id,
                'to_user_id' => $newOwner->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => 'Failed to transfer ownership. Please try again.',
            ];
        }
    }

    /**
     * Validate ownership transfer before execution.
     *
     * Useful for pre-flight checks in the UI.
     *
     * @param Organization $organization
     * @param User $currentOwner
     * @param User $newOwner
     * @return array{valid: bool, errors: array<string>}
     */
    public function validateTransfer(
        Organization $organization,
        User $currentOwner,
        User $newOwner
    ): array {
        $errors = [];

        if (!$currentOwner->isOwner()) {
            $errors[] = 'You are not the organization owner';
        }

        if ($newOwner->organization_id !== $organization->id) {
            $errors[] = 'New owner must be a member of the organization';
        }

        if ($currentOwner->id === $newOwner->id) {
            $errors[] = 'Cannot transfer ownership to yourself';
        }

        if ($newOwner->isOwner()) {
            $errors[] = 'User is already an owner';
        }

        return [
            'valid' => empty($errors),
            'errors' => $errors,
        ];
    }

    /**
     * Get eligible members for ownership transfer.
     *
     * Returns members who can receive ownership.
     * Typically admins and members, but not viewers.
     *
     * @param Organization $organization
     * @param User $currentOwner
     * @return \Illuminate\Database\Eloquent\Collection
     */
    public function getEligibleMembers(Organization $organization, User $currentOwner)
    {
        return $organization->users()
            ->where('id', '!=', $currentOwner->id)
            ->whereIn('role', ['admin', 'member'])
            ->orderBy('role', 'asc')
            ->orderBy('name', 'asc')
            ->get();
    }

    /**
     * Create an ownership transfer request.
     *
     * For future implementation: could create a pending transfer
     * that requires acceptance from the new owner.
     *
     * @param Organization $organization
     * @param User $currentOwner
     * @param User $newOwner
     * @return array{success: bool, message: string, request_id?: string}
     */
    public function createTransferRequest(
        Organization $organization,
        User $currentOwner,
        User $newOwner
    ): array {
        // TODO: Implement transfer request system
        // This would:
        // 1. Create a transfer request record
        // 2. Send notification to new owner
        // 3. Require acceptance from new owner
        // 4. Expire after certain time

        return [
            'success' => false,
            'message' => 'Transfer request system not yet implemented',
        ];
    }
}
