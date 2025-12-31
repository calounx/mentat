<?php

namespace App\Http\Requests\V1\Sites;

use App\Models\Site;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Create Site Request
 *
 * Handles validation and authorization for site creation.
 */
class CreateSiteRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return $this->user()->can('create', Site::class);
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        $tenant = $this->user()->currentTenant();

        return [
            'domain' => [
                'required',
                'string',
                'max:253',
                'regex:/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i',
                Rule::unique('sites')->where('tenant_id', $tenant?->id),
            ],
            'site_type' => [
                'sometimes',
                'string',
                Rule::in(['wordpress', 'html', 'laravel']),
            ],
            'php_version' => [
                'sometimes',
                'string',
                Rule::in(['8.2', '8.4']),
            ],
            'ssl_enabled' => [
                'sometimes',
                'boolean',
            ],
            'settings' => [
                'sometimes',
                'array',
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
            'domain.required' => 'A domain name is required.',
            'domain.unique' => 'This domain already exists for your account.',
            'domain.regex' => 'The domain format is invalid.',
            'site_type.in' => 'The site type must be wordpress, html, or laravel.',
            'php_version.in' => 'The PHP version must be 8.2 or 8.4.',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Normalize domain to lowercase
        if ($this->has('domain')) {
            $this->merge([
                'domain' => strtolower(trim($this->input('domain'))),
            ]);
        }

        // Set defaults if not provided
        $this->merge([
            'site_type' => $this->input('site_type', 'wordpress'),
            'php_version' => $this->input('php_version', '8.2'),
            'ssl_enabled' => $this->input('ssl_enabled', true),
        ]);
    }

    /**
     * Get the tenant from the request.
     *
     * @return \App\Models\Tenant|null
     */
    public function tenant()
    {
        return $this->user()->currentTenant();
    }
}
