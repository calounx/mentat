<?php

namespace App\Http\Requests;

use App\Models\Organization;
use Illuminate\Validation\Rule;

/**
 * Update Organization Request
 *
 * Validates organization updates with owner/admin-only access.
 * Controls billing information and organization settings.
 */
class UpdateOrganizationRequest extends BaseFormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be owner or admin
     * - User must belong to the organization being updated
     */
    public function authorize(): bool
    {
        if (!$this->user() || !$this->isAdmin()) {
            return false;
        }

        // Get organization ID from route or user's organization
        $organizationId = $this->route('organization') ?? $this->getOrganizationId();

        if (!$organizationId) {
            return false;
        }

        // Verify user belongs to this organization
        return $this->getOrganizationId() === $organizationId;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        $organizationId = $this->route('organization') ?? $this->getOrganizationId();

        return [
            'name' => [
                'sometimes',
                'required',
                'string',
                'max:255',
                'min:2',
            ],
            'slug' => [
                'sometimes',
                'required',
                'string',
                'max:100',
                'alpha_dash',
                Rule::unique('organizations', 'slug')->ignore($organizationId),
            ],
            'billing_email' => [
                'sometimes',
                'required',
                'email',
                'max:255',
            ],
            'settings' => [
                'sometimes',
                'array',
            ],
            'settings.timezone' => [
                'sometimes',
                'string',
                'timezone',
            ],
            'settings.notifications_enabled' => [
                'sometimes',
                'boolean',
            ],
            'settings.two_factor_required' => [
                'sometimes',
                'boolean',
            ],
            'settings.allowed_domains' => [
                'sometimes',
                'array',
            ],
            'settings.allowed_domains.*' => [
                'string',
                'max:255',
            ],
        ];
    }

    /**
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return array_merge(parent::messages(), [
            'name.required' => 'Organization name is required.',
            'name.min' => 'Organization name must be at least 2 characters.',
            'slug.required' => 'Organization slug is required.',
            'slug.alpha_dash' => 'Organization slug may only contain letters, numbers, dashes, and underscores.',
            'slug.unique' => 'This organization slug is already taken.',
            'billing_email.required' => 'Billing email is required.',
            'billing_email.email' => 'Please provide a valid billing email address.',
            'settings.timezone.timezone' => 'Please provide a valid timezone.',
        ]);
    }

    /**
     * Get custom attributes for validator errors.
     */
    public function attributes(): array
    {
        return [
            'billing_email' => 'billing email',
            'settings.timezone' => 'timezone',
            'settings.notifications_enabled' => 'notifications',
            'settings.two_factor_required' => 'two-factor authentication requirement',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Normalize slug to lowercase and replace spaces with dashes
        if ($this->has('slug')) {
            $slug = strtolower($this->input('slug'));
            $slug = preg_replace('/\s+/', '-', $slug);
            $slug = preg_replace('/[^a-z0-9\-_]/', '', $slug);

            $this->merge([
                'slug' => $slug,
            ]);
        }

        // Normalize billing email to lowercase
        if ($this->has('billing_email')) {
            $this->merge([
                'billing_email' => strtolower($this->input('billing_email')),
            ]);
        }

        // Set default timezone if not provided
        if ($this->has('settings') && !isset($this->input('settings')['timezone'])) {
            $settings = $this->input('settings');
            $settings['timezone'] = $settings['timezone'] ?? 'UTC';
            $this->merge(['settings' => $settings]);
        }
    }

    /**
     * Configure the validator instance.
     */
    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            // Only owners can enable/disable two-factor requirement
            if ($this->has('settings.two_factor_required') && !$this->isOwner()) {
                $validator->errors()->add(
                    'settings.two_factor_required',
                    'Only organization owners can change two-factor authentication requirements.'
                );
            }
        });
    }
}
