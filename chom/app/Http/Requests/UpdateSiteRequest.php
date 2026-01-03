<?php

namespace App\Http\Requests;

use App\Models\Site;
use App\Models\VpsServer;
use Illuminate\Validation\Rule;

/**
 * Update Site Request
 *
 * Validates updates to existing sites with ownership verification.
 * All fields are optional as this is a partial update (PATCH).
 */
class UpdateSiteRequest extends BaseFormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be authenticated
     * - User must have site management permissions
     * - Site must belong to user's tenant
     */
    public function authorize(): bool
    {
        if (!$this->user() || !$this->canManageSites()) {
            return false;
        }

        // Get the site from route parameter
        $siteId = $this->route('id') ?? $this->route('site');

        if (!$siteId) {
            return false;
        }

        $site = Site::find($siteId);

        if (!$site) {
            return false;
        }

        // Verify site belongs to user's tenant
        $tenantId = $this->getTenantId();

        return $site->tenant_id === $tenantId;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        $tenantId = $this->getTenantId();
        $siteId = $this->route('id') ?? $this->route('site');

        return [
            'domain' => array_merge(
                $this->domainRules(required: false),
                [
                    // Domain must be unique per tenant, excluding current site
                    Rule::unique('sites', 'domain')
                        ->where('tenant_id', $tenantId)
                        ->ignore($siteId)
                        ->whereNull('deleted_at'),
                ]
            ),
            'site_type' => [
                'sometimes',
                'string',
                Rule::in(['wordpress', 'laravel', 'static', 'custom']),
            ],
            'php_version' => [
                'sometimes',
                'string',
                Rule::in(['7.4', '8.0', '8.1', '8.2', '8.3']),
            ],
            'vps_server_id' => [
                'sometimes',
                'nullable',
                'string',
                'exists:vps_servers,id',
                function ($attribute, $value, $fail) {
                    if ($value) {
                        $vps = VpsServer::find($value);
                        if ($vps && !$vps->isAvailable()) {
                            $fail('The selected VPS server is not available.');
                        }
                    }
                },
            ],
            'ssl_enabled' => [
                'sometimes',
                'boolean',
            ],
            'status' => [
                'sometimes',
                'string',
                Rule::in(['creating', 'active', 'disabled', 'failed', 'migrating']),
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
            'domain.unique' => 'A site with this domain already exists in your organization.',
            'site_type.in' => 'Invalid site type. Must be wordpress, laravel, static, or custom.',
            'php_version.in' => 'Invalid PHP version selected.',
            'vps_server_id.exists' => 'The selected VPS server does not exist.',
            'status.in' => 'Invalid site status.',
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
        // Normalize domain to lowercase if provided
        if ($this->has('domain')) {
            $this->merge([
                'domain' => strtolower($this->input('domain')),
            ]);
        }
    }
}
