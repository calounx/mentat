<?php

namespace App\Http\Requests\V1\Vps;

use App\Models\VpsServer;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Update VPS Server Request
 *
 * Validates VPS server updates with safety restrictions:
 * - IP address changes NOT allowed (handled separately)
 * - SSH key changes NOT allowed (use key rotation endpoint)
 * - Allows: hostname, specs, region, notes updates
 *
 * @package App\Http\Requests\V1\Vps
 */
class UpdateVpsRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        $vps = $this->route('vps');
        if (is_string($vps)) {
            $vps = VpsServer::findOrFail($vps);
        }

        return $this->user()->can('update', $vps);
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        $vpsId = $this->route('vps');

        return [
            // Hostname (optional, must be unique if changed)
            'hostname' => [
                'sometimes',
                'string',
                'max:253',
                'regex:/^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$/',
                Rule::unique('vps_servers', 'hostname')->ignore($vpsId),
            ],

            // Region
            'region' => [
                'sometimes',
                'nullable',
                'string',
                'max:100',
            ],

            // Specifications (can be updated as VPS is upgraded)
            'spec_cpu' => [
                'sometimes',
                'nullable',
                'integer',
                'min:1',
                'max:128',
            ],
            'spec_memory_mb' => [
                'sometimes',
                'nullable',
                'integer',
                'min:512',
                'max:1048576',
            ],
            'spec_disk_gb' => [
                'sometimes',
                'nullable',
                'integer',
                'min:10',
                'max:10240',
            ],

            // Allocation type
            'allocation_type' => [
                'sometimes',
                'string',
                Rule::in(['shared', 'dedicated']),
            ],

            // Status
            'status' => [
                'sometimes',
                'string',
                Rule::in(['active', 'maintenance', 'inactive']),
            ],

            // Health status
            'health_status' => [
                'sometimes',
                'string',
                Rule::in(['healthy', 'degraded', 'unhealthy', 'unknown']),
            ],

            // VPSManager version
            'vpsmanager_version' => [
                'sometimes',
                'nullable',
                'string',
                'max:50',
            ],

            // Observability
            'observability_configured' => [
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
            'hostname.unique' => 'This hostname is already registered.',
            'hostname.regex' => 'The hostname format is invalid.',
            'spec_cpu.min' => 'CPU cores must be at least 1.',
            'spec_memory_mb.min' => 'Memory must be at least 512 MB.',
            'spec_disk_gb.min' => 'Disk size must be at least 10 GB.',
            'status.in' => 'Invalid status. Choose from: active, maintenance, or inactive.',
            'health_status.in' => 'Invalid health status. Choose from: healthy, degraded, unhealthy, or unknown.',
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
                'hostname' => strtolower(trim($this->input('hostname'))),
            ]);
        }

        // Remove IP address if provided (not allowed to change)
        if ($this->has('ip_address')) {
            $data = $this->except('ip_address');
            $this->replace($data);
        }

        // Remove SSH keys if provided (use rotation endpoint)
        if ($this->has('ssh_private_key') || $this->has('ssh_public_key')) {
            $data = $this->except(['ssh_private_key', 'ssh_public_key']);
            $this->replace($data);
        }
    }

    /**
     * Get validation attributes for custom error messages.
     *
     * @return array<string, string>
     */
    public function attributes(): array
    {
        return [
            'spec_cpu' => 'CPU cores',
            'spec_memory_mb' => 'memory',
            'spec_disk_gb' => 'disk size',
            'vpsmanager_version' => 'VPSManager version',
        ];
    }
}
