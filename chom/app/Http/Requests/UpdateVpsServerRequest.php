<?php

namespace App\Http\Requests;

use App\Models\VpsServer;
use Illuminate\Validation\Rule;

/**
 * Update VPS Server Request
 *
 * Validates VPS server updates with admin-only authorization.
 * Platform administrators only - not tenant-scoped.
 */
class UpdateVpsServerRequest extends BaseFormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     *
     * Authorization checks:
     * - User must be admin or owner (platform-level)
     * - VPS server must exist
     *
     * NOTE: This is admin-only functionality, not tenant-scoped
     */
    public function authorize(): bool
    {
        // Only platform admins can update VPS servers
        if (!$this->user() || !$this->isAdmin()) {
            return false;
        }

        // Verify VPS server exists
        $vpsId = $this->route('id') ?? $this->route('vps_server') ?? $this->route('vps');

        if (!$vpsId) {
            return false;
        }

        $vps = VpsServer::find($vpsId);

        return $vps !== null;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        $vpsId = $this->route('id') ?? $this->route('vps_server') ?? $this->route('vps');

        return [
            'hostname' => [
                'sometimes',
                'required',
                'string',
                'max:255',
                'regex:/^[a-zA-Z0-9][a-zA-Z0-9\-\.]*[a-zA-Z0-9]$/',
                Rule::unique('vps_servers', 'hostname')->ignore($vpsId),
            ],
            'ip_address' => [
                'sometimes',
                'required',
                'ip',
                Rule::unique('vps_servers', 'ip_address')->ignore($vpsId),
            ],
            'provider' => [
                'sometimes',
                'required',
                'string',
                Rule::in(['digitalocean', 'linode', 'vultr', 'aws', 'custom']),
            ],
            'provider_id' => [
                'sometimes',
                'nullable',
                'string',
                'max:255',
            ],
            'region' => [
                'sometimes',
                'nullable',
                'string',
                'max:100',
            ],
            'status' => [
                'sometimes',
                'required',
                'string',
                Rule::in(['provisioning', 'active', 'maintenance', 'failed', 'decommissioned']),
            ],
            'allocation_type' => [
                'sometimes',
                'required',
                'string',
                Rule::in(['shared', 'dedicated']),
            ],
            'spec_cpu' => [
                'sometimes',
                'integer',
                'min:1',
                'max:128',
            ],
            'spec_memory_mb' => [
                'sometimes',
                'integer',
                'min:512',
                'max:524288', // 512 GB
            ],
            'spec_disk_gb' => [
                'sometimes',
                'integer',
                'min:10',
                'max:10240', // 10 TB
            ],
            'vpsmanager_version' => [
                'sometimes',
                'nullable',
                'string',
                'max:50',
            ],
            'observability_configured' => [
                'sometimes',
                'boolean',
            ],
            'health_status' => [
                'sometimes',
                'string',
                Rule::in(['healthy', 'degraded', 'unhealthy', 'unknown']),
            ],
        ];
    }

    /**
     * Get custom error messages for validator errors.
     */
    public function messages(): array
    {
        return array_merge(parent::messages(), [
            'hostname.required' => 'Hostname is required.',
            'hostname.regex' => 'Please provide a valid hostname.',
            'hostname.unique' => 'A VPS server with this hostname already exists.',
            'ip_address.required' => 'IP address is required.',
            'ip_address.ip' => 'Please provide a valid IP address.',
            'ip_address.unique' => 'A VPS server with this IP address already exists.',
            'provider.required' => 'Provider is required.',
            'provider.in' => 'Invalid provider selected.',
            'status.required' => 'Status is required.',
            'status.in' => 'Invalid status selected.',
            'allocation_type.required' => 'Allocation type is required.',
            'allocation_type.in' => 'Invalid allocation type. Must be shared or dedicated.',
            'spec_cpu.min' => 'CPU count must be at least 1.',
            'spec_cpu.max' => 'CPU count cannot exceed 128.',
            'spec_memory_mb.min' => 'Memory must be at least 512 MB.',
            'spec_memory_mb.max' => 'Memory cannot exceed 512 GB.',
            'spec_disk_gb.min' => 'Disk space must be at least 10 GB.',
            'spec_disk_gb.max' => 'Disk space cannot exceed 10 TB.',
            'health_status.in' => 'Invalid health status.',
        ]);
    }

    /**
     * Get custom attributes for validator errors.
     */
    public function attributes(): array
    {
        return [
            'ip_address' => 'IP address',
            'spec_cpu' => 'CPU cores',
            'spec_memory_mb' => 'memory',
            'spec_disk_gb' => 'disk space',
            'allocation_type' => 'allocation type',
            'vpsmanager_version' => 'VPS Manager version',
            'observability_configured' => 'observability status',
            'health_status' => 'health status',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Normalize hostname to lowercase
        if ($this->has('hostname')) {
            $this->merge([
                'hostname' => strtolower($this->input('hostname')),
            ]);
        }
    }

    /**
     * Configure the validator instance.
     */
    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            // Prevent changing status to active if VPS is unhealthy
            if ($this->input('status') === 'active' && $this->input('health_status') === 'unhealthy') {
                $validator->errors()->add(
                    'status',
                    'Cannot set status to active while health status is unhealthy.'
                );
            }

            // Prevent decommissioning VPS with active sites
            if ($this->input('status') === 'decommissioned') {
                $vpsId = $this->route('id') ?? $this->route('vps_server') ?? $this->route('vps');
                $vps = VpsServer::find($vpsId);

                if ($vps && $vps->getSiteCount() > 0) {
                    $validator->errors()->add(
                        'status',
                        'Cannot decommission VPS server with active sites. Please migrate sites first.'
                    );
                }
            }
        });
    }
}
