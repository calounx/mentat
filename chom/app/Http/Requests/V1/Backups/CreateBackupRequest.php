<?php

namespace App\Http\Requests\V1\Backups;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Create Backup Request
 *
 * Handles validation and authorization for backup creation.
 */
class CreateBackupRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        $tenant = $this->user()->currentTenant();

        if (! $tenant || ! $tenant->isActive()) {
            return false;
        }

        // Verify site belongs to tenant
        $siteId = $this->input('site_id');
        if ($siteId) {
            $site = $tenant->sites()->find($siteId);
            if (! $site) {
                return false;
            }

            // Check if user can create backups for this site
            return $this->user()->can('create', [\App\Models\SiteBackup::class, $site]);
        }

        return false;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'site_id' => [
                'required',
                'uuid',
                'exists:sites,id',
            ],
            'backup_type' => [
                'sometimes',
                'string',
                Rule::in(['full', 'database', 'files']),
            ],
            'retention_days' => [
                'sometimes',
                'integer',
                'min:1',
                'max:365',
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
            'site_id.required' => 'A site ID is required.',
            'site_id.uuid' => 'Invalid site ID format.',
            'site_id.exists' => 'The specified site does not exist.',
            'backup_type.in' => 'The backup type must be full, database, or files.',
            'retention_days.min' => 'Retention days must be at least 1.',
            'retention_days.max' => 'Retention days cannot exceed 365.',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Set defaults
        $this->merge([
            'backup_type' => $this->input('backup_type', 'full'),
            'retention_days' => $this->input('retention_days', 30),
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

    /**
     * Get the site from the request.
     *
     * @return \App\Models\Site|null
     */
    public function site()
    {
        $tenant = $this->tenant();
        if (! $tenant) {
            return null;
        }

        return $tenant->sites()->find($this->input('site_id'));
    }
}
