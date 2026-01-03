<?php

namespace App\Http\Requests;

use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Validation\Rule;

/**
 * Store Backup Request
 *
 * Validates backup creation with site ownership and quota checks.
 * Enforces backup limits based on tenant tier.
 */
class StoreBackupRequest extends BaseFormRequest
{
    /**
     * Maximum backups per site based on tier.
     */
    protected const BACKUP_LIMITS = [
        'starter' => 5,
        'pro' => 20,
        'enterprise' => -1, // Unlimited
    ];

    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be authenticated
     * - User must have site management permissions
     * - Site must belong to user's tenant
     * - Backup quota must not be exceeded
     */
    public function authorize(): bool
    {
        if (!$this->user() || !$this->canManageSites()) {
            return false;
        }

        // Get site ID from request or route
        $siteId = $this->input('site_id') ?? $this->route('siteId') ?? $this->route('site');

        if (!$siteId) {
            return false;
        }

        $site = Site::find($siteId);

        if (!$site) {
            return false;
        }

        // Verify site belongs to user's tenant
        $tenantId = $this->getTenantId();

        if ($site->tenant_id !== $tenantId) {
            return false;
        }

        // Check backup quota
        if (!$this->checkBackupQuota($site)) {
            return false;
        }

        return true;
    }

    /**
     * Check if site has remaining backup quota.
     *
     * @param Site $site
     * @return bool
     */
    protected function checkBackupQuota(Site $site): bool
    {
        $tenant = $this->user()->currentTenant();

        if (!$tenant) {
            return false;
        }

        $tier = $tenant->getCurrentTier();
        $limit = self::BACKUP_LIMITS[$tier] ?? self::BACKUP_LIMITS['starter'];

        // -1 means unlimited
        if ($limit === -1) {
            return true;
        }

        $currentBackupCount = SiteBackup::where('site_id', $site->id)
            ->where('status', '!=', 'failed')
            ->count();

        return $currentBackupCount < $limit;
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
            'site_id' => [
                'sometimes',
                'required',
                'string',
                'exists:sites,id',
                function ($attribute, $value, $fail) use ($tenantId) {
                    // Verify site belongs to user's tenant
                    $site = Site::find($value);
                    if ($site && $site->tenant_id !== $tenantId) {
                        $fail('You do not have permission to backup this site.');
                    }
                },
            ],
            'backup_type' => [
                'required',
                'string',
                Rule::in(['full', 'files', 'database', 'config', 'manual']),
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
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return array_merge(parent::messages(), [
            'site_id.required' => 'Please specify which site to backup.',
            'site_id.exists' => 'The specified site does not exist.',
            'backup_type.required' => 'Please select a backup type.',
            'backup_type.in' => 'Invalid backup type. Must be full, files, database, config, or manual.',
            'retention_days.min' => 'Retention period must be at least 1 day.',
            'retention_days.max' => 'Retention period cannot exceed 365 days.',
        ]);
    }

    /**
     * Get custom attributes for validator errors.
     */
    public function attributes(): array
    {
        return [
            'site_id' => 'site',
            'backup_type' => 'backup type',
            'retention_days' => 'retention period',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Set default backup type if not provided
        if (!$this->has('backup_type')) {
            $this->merge([
                'backup_type' => 'full',
            ]);
        }

        // Set default retention days based on tier
        if (!$this->has('retention_days')) {
            $tenant = $this->user()?->currentTenant();
            $tier = $tenant?->getCurrentTier() ?? 'starter';

            $defaultRetention = match ($tier) {
                'enterprise' => 90,
                'pro' => 60,
                default => 30,
            };

            $this->merge([
                'retention_days' => $defaultRetention,
            ]);
        }

        // If site_id not in request body, try to get from route
        if (!$this->has('site_id')) {
            $siteId = $this->route('siteId') ?? $this->route('site');
            if ($siteId) {
                $this->merge([
                    'site_id' => $siteId,
                ]);
            }
        }
    }
}
