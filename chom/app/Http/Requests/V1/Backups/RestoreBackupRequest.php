<?php

namespace App\Http\Requests\V1\Backups;

use App\Models\SiteBackup;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Restore Backup Request
 *
 * Handles validation and authorization for backup restoration.
 */
class RestoreBackupRequest extends FormRequest
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

        // Get backup from route parameter
        $backup = $this->route('backup');

        if (! $backup instanceof SiteBackup) {
            return false;
        }

        // Verify backup's site belongs to tenant
        $site = $backup->site;
        if (! $site || $site->tenant_id !== $tenant->id) {
            return false;
        }

        // Check if user can restore backups for this site
        return $this->user()->can('restore', $backup);
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'restore_type' => [
                'sometimes',
                'string',
                Rule::in(['full', 'database', 'files']),
            ],
            'force' => [
                'sometimes',
                'boolean',
            ],
            'skip_verify' => [
                'sometimes',
                'boolean',
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
            'restore_type.in' => 'The restore type must be full, database, or files.',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        $backup = $this->route('backup');

        // Default restore_type to the backup's type
        $this->merge([
            'restore_type' => $this->input('restore_type', $backup?->backup_type ?? 'full'),
            'force' => $this->boolean('force', false),
            'skip_verify' => $this->boolean('skip_verify', false),
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
     * Get the backup from the route.
     *
     * @return \App\Models\SiteBackup|null
     */
    public function backup(): ?SiteBackup
    {
        return $this->route('backup');
    }
}
