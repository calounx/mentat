<?php

namespace App\Http\Requests\V1\Team;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateMemberRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        // User must be admin or owner to update member roles
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

        // Owners can set any role except owner
        // Admins can only set member or viewer
        $allowedRoles = $user->isOwner() 
            ? ['admin', 'member', 'viewer']
            : ['member', 'viewer'];

        return [
            'role' => [
                'required',
                Rule::in($allowedRoles),
            ],
        ];
    }

    /**
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return [
            'role.required' => 'A role must be specified.',
            'role.in' => 'Invalid role specified. You do not have permission to assign this role.',
        ];
    }
}
