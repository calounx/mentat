<?php

namespace App\Http\Requests;

use Illuminate\Validation\Rule;

/**
 * Invite Team Member Request
 *
 * Validates team member invitations with role-based permissions.
 * Enforces organization ownership and role hierarchy.
 */
class InviteTeamMemberRequest extends BaseFormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be admin or owner to invite members
     * - User must belong to an organization
     */
    public function authorize(): bool
    {
        return $this->user() && $this->isAdmin() && $this->getOrganizationId();
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        $user = $this->user();
        $organizationId = $user->organization_id;

        // Owners can invite as admin, member, or viewer
        // Admins can only invite as member or viewer
        $allowedRoles = $this->isOwner()
            ? ['admin', 'member', 'viewer']
            : ['member', 'viewer'];

        return [
            'email' => [
                'required',
                'email',
                'max:255',
                // Ensure email is not already a member of this organization
                Rule::unique('users', 'email')->where(function ($query) use ($organizationId) {
                    return $query->where('organization_id', $organizationId);
                }),
                // Ensure email doesn't have pending invitation
                Rule::unique('team_invitations', 'email')->where(function ($query) use ($organizationId) {
                    return $query->where('organization_id', $organizationId)
                        ->whereNull('accepted_at')
                        ->where('expires_at', '>', now());
                }),
            ],
            'role' => [
                'required',
                Rule::in($allowedRoles),
            ],
            'name' => ['sometimes', 'string', 'max:255'],
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
            'email.required' => 'Please provide an email address for the team member.',
            'email.email' => 'Please provide a valid email address.',
            'email.unique' => 'This email is already a member of your organization or has a pending invitation.',
            'role.required' => 'Please select a role for the team member.',
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
            'email' => 'email address',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Normalize email to lowercase
        if ($this->has('email')) {
            $this->merge([
                'email' => strtolower($this->input('email')),
            ]);
        }

        // Set default permissions based on role if not provided
        if (!$this->has('permissions') && $this->has('role')) {
            $defaultPermissions = $this->getDefaultPermissionsForRole($this->input('role'));
            $this->merge([
                'permissions' => $defaultPermissions,
            ]);
        }
    }

    /**
     * Get default permissions for a role.
     *
     * @param string $role
     * @return array
     */
    protected function getDefaultPermissionsForRole(string $role): array
    {
        return match ($role) {
            'admin' => [
                'sites.view', 'sites.create', 'sites.update', 'sites.delete',
                'backups.view', 'backups.create', 'backups.restore', 'backups.delete',
                'team.view', 'team.invite', 'team.manage',
                'billing.view', 'settings.view', 'settings.update',
            ],
            'member' => [
                'sites.view', 'sites.create', 'sites.update',
                'backups.view', 'backups.create', 'backups.restore',
                'team.view',
            ],
            'viewer' => [
                'sites.view',
                'backups.view',
                'team.view',
            ],
            default => [],
        };
    }
}
