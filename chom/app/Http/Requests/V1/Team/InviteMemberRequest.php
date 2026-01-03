<?php

namespace App\Http\Requests\V1\Team;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class InviteMemberRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        // User must be admin or owner to invite members
        return $this->user() && $this->user()->isAdmin();
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
        $allowedRoles = $user->isOwner() 
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
        ];
    }

    /**
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return [
            'email.unique' => 'This email is already a member of your organization or has a pending invitation.',
            'role.in' => 'Invalid role specified. You do not have permission to assign this role.',
        ];
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
}
