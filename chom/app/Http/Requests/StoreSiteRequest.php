<?php

namespace App\Http\Requests;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Validation\Rule;

/**
 * Store Site Request
 *
 * Validates creation of new sites with tenant access control.
 * Enforces tier limits and domain uniqueness.
 */
class StoreSiteRequest extends BaseFormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be authenticated
     * - User must have site management permissions (owner/admin/member)
     * - Tenant must be active
     * - Tenant must not exceed site limit
     */
    public function authorize(): bool
    {
        if (!$this->user() || !$this->canManageSites()) {
            return false;
        }

        $tenant = $this->user()->currentTenant();

        if (!$tenant || !$tenant->isActive()) {
            return false;
        }

        // Check if tenant can create more sites
        if (!$tenant->canCreateSite()) {
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
        $tenantId = $this->getTenantId();

        return [
            'domain' => array_merge(
                $this->domainRules(required: true),
                [
                    // Domain must be unique per tenant
                    Rule::unique('sites', 'domain')
                        ->where('tenant_id', $tenantId)
                        ->whereNull('deleted_at'),
                ]
            ),
            'site_type' => [
                'required',
                'string',
                Rule::in(['wordpress', 'laravel', 'static', 'custom']),
            ],
            'php_version' => [
                'required',
                'string',
                Rule::in(['7.4', '8.0', '8.1', '8.2', '8.3']),
            ],
            'vps_server_id' => [
                'sometimes',
                'string',
                'exists:vps_servers,id',
                function ($attribute, $value, $fail) {
                    // If VPS ID provided, verify it's available
                    $vps = VpsServer::find($value);
                    if ($vps && !$vps->isAvailable()) {
                        $fail('The selected VPS server is not available.');
                    }
                },
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
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return array_merge(parent::messages(), [
            'domain.required' => 'Please provide a domain name for your site.',
            'domain.unique' => 'A site with this domain already exists in your organization.',
            'site_type.required' => 'Please select a site type.',
            'site_type.in' => 'Invalid site type. Must be wordpress, laravel, static, or custom.',
            'php_version.required' => 'Please select a PHP version.',
            'php_version.in' => 'Invalid PHP version selected.',
            'vps_server_id.exists' => 'The selected VPS server does not exist.',
        ]);
    }

    /**
     * Get custom attributes for validator errors.
     */
    public function attributes(): array
    {
        return [
            'vps_server_id' => 'VPS server',
            'site_type' => 'site type',
            'php_version' => 'PHP version',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Set default PHP version if not provided
        if (!$this->has('php_version')) {
            $this->merge([
                'php_version' => '8.2',
            ]);
        }

        // Set default site type if not provided
        if (!$this->has('site_type')) {
            $this->merge([
                'site_type' => 'wordpress',
            ]);
        }

        // Normalize domain to lowercase
        if ($this->has('domain')) {
            $this->merge([
                'domain' => strtolower($this->input('domain')),
            ]);
        }
    }
}
