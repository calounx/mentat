<?php

namespace App\Http\Requests\V1\TwoFactor;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Disable Two-Factor Authentication Request
 *
 * Validates password confirmation before disabling 2FA.
 * Implements step-up authentication for sensitive operation.
 */
class DisableTwoFactorRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        $user = $this->user();

        // User must be authenticated
        if (!$user) {
            return false;
        }

        // SECURITY: Prevent disabling 2FA if required for role
        if ($user->requires2FA()) {
            throw ValidationException::withMessages([
                'role' => ['Two-factor authentication is required for your role and cannot be disabled.'],
            ]);
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
        return [
            'password' => [
                'required',
                'string',
                function ($attribute, $value, $fail) {
                    if (!Hash::check($value, $this->user()->password)) {
                        $fail('The provided password is incorrect.');
                    }
                },
            ],
        ];
    }

    /**
     * Get custom messages for validator errors.
     *
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'password.required' => 'Password confirmation is required to disable two-factor authentication.',
        ];
    }

    /**
     * Get custom attributes for validator errors.
     *
     * @return array<string, string>
     */
    public function attributes(): array
    {
        return [
            'password' => 'password',
        ];
    }
}
