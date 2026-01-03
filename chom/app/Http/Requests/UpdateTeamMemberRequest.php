<?php

namespace App\Http\Requests;

use App\Models\User;
use Illuminate\Validation\Rule;

/**
 * Update Team Member Request
 *
 * Validates team member updates with self-demotion protection.
 * Prevents users from demoting themselves or escalating beyond their authority.
 */
class UpdateTeamMemberRequest extends BaseFormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be admin or owner to update member roles
     * - User cannot demote themselves
     * - Admins cannot update owners
     */
    public function authorize(): bool
    {
        if (!$this->user() || !$this->isAdmin()) {
            return false;
        }

        // Get the member being updated
        $memberId = $this->route('id') ?? $this->route('member');

        if (!$memberId) {
            return false;
        }

        // Prevent self-demotion
        if ($memberId === $this->user()->id) {
            // Users can only update their own permissions, not role
            if ($this->has('role')) {
                return false;
            }
        }

        // Get the member being updated
        $member = User::find($memberId);

        if (!$member) {
            return false;
        }

        // Verify member belongs to same organization
        if ($member->organization_id !== $this->getOrganizationId()) {
            return false;
        }

        // Admins cannot update owners
        if (!$this->isOwner() && $member->role === 'owner') {
            return false;
        }

        return true;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        // Owners can set any role except owner
        // Admins can only set member or viewer
        $allowedRoles = $this->isOwner()
            ? ['admin', 'member', 'viewer']
            : ['member', 'viewer'];

        return [
            'role' => [
                'sometimes',
                'required',
                Rule::in($allowedRoles),
            ],
            'permissions' => [
                'sometimes',
                'array',
            ],
            'permissions.*' => [
                'string',
                Rule::in([
                    'sites.view',
                    'sites.create',
                    'sites.update',
                    'sites.delete',
                    'backups.view',
                    'backups.create',
                    'backups.restore',
                    'backups.delete',
                    'team.view',
                    'team.invite',
                    'team.manage',
                    'team.remove',
                    'billing.view',
                    'billing.manage',
                    'settings.view',
                    'settings.update',
                ]),
            ],
        ];
    }

    /**
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return array_merge(parent::messages(), [
            'role.required' => 'A role must be specified.',
            'role.in' => 'Invalid role specified. You do not have permission to assign this role.',
            'permissions.array' => 'Permissions must be provided as an array.',
            'permissions.*.in' => 'One or more permissions are invalid.',
        ]);
    }

    /**
     * Get custom attributes for validator errors.
     */
    public function attributes(): array
    {
        return [
            'role' => 'member role',
        ];
    }

    /**
     * Configure the validator instance.
     */
    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            // Additional check: prevent self-demotion via custom validation
            $memberId = $this->route('id') ?? $this->route('member');

            if ($memberId === $this->user()->id && $this->has('role')) {
                $currentRole = $this->user()->role;
                $newRole = $this->input('role');

                // Define role hierarchy
                $roleHierarchy = ['owner' => 4, 'admin' => 3, 'member' => 2, 'viewer' => 1];

                if (isset($roleHierarchy[$currentRole]) && isset($roleHierarchy[$newRole])) {
                    if ($roleHierarchy[$newRole] < $roleHierarchy[$currentRole]) {
                        $validator->errors()->add(
                            'role',
                            'You cannot demote yourself. Please have another administrator update your role.'
                        );
                    }
                }
            }

            // Prevent changing role of the only owner
            if ($this->has('role')) {
                $member = User::find($memberId);
                if ($member && $member->role === 'owner') {
                    $ownerCount = User::where('organization_id', $this->getOrganizationId())
                        ->where('role', 'owner')
                        ->count();

                    if ($ownerCount === 1) {
                        $validator->errors()->add(
                            'role',
                            'Cannot change the role of the only owner. Transfer ownership first.'
                        );
                    }
                }
            }
        });
    }
}
