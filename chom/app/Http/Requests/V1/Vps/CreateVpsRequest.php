<?php

namespace App\Http\Requests\V1\Vps;

use App\Models\VpsServer;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Create VPS Server Request
 *
 * Validates VPS server creation with comprehensive security checks:
 * - IP address format validation (IPv4 and IPv6)
 * - Hostname validation (RFC 1123 compliant)
 * - SSH key format validation
 * - Uniqueness checks for IP and hostname
 *
 * @package App\Http\Requests\V1\Vps
 */
class CreateVpsRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return $this->user()->can('create', VpsServer::class);
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            // Required fields
            'hostname' => [
                'required',
                'string',
                'max:253',
                'regex:/^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$/',
                Rule::unique('vps_servers', 'hostname'),
            ],
            'ip_address' => [
                'required',
                'ip', // Validates both IPv4 and IPv6
                Rule::unique('vps_servers', 'ip_address'),
            ],
            'provider' => [
                'required',
                'string',
                'max:50',
                Rule::in([
                    'digitalocean',
                    'linode',
                    'vultr',
                    'aws',
                    'hetzner',
                    'ovh',
                    'custom',
                ]),
            ],

            // Optional identification
            'provider_id' => [
                'nullable',
                'string',
                'max:255',
            ],
            'region' => [
                'nullable',
                'string',
                'max:100',
            ],

            // Specifications
            'spec_cpu' => [
                'nullable',
                'integer',
                'min:1',
                'max:128',
            ],
            'spec_memory_mb' => [
                'nullable',
                'integer',
                'min:512',
                'max:1048576', // 1TB in MB
            ],
            'spec_disk_gb' => [
                'nullable',
                'integer',
                'min:10',
                'max:10240', // 10TB
            ],

            // Allocation
            'allocation_type' => [
                'sometimes',
                'string',
                Rule::in(['shared', 'dedicated']),
            ],

            // SSH Credentials (encrypted at rest via Model)
            'ssh_private_key' => [
                'nullable',
                'string',
                function ($attribute, $value, $fail) {
                    // Validate SSH private key format
                    if (!empty($value) && !$this->isValidSshPrivateKey($value)) {
                        $fail('The SSH private key format is invalid.');
                    }
                },
            ],
            'ssh_public_key' => [
                'nullable',
                'string',
                function ($attribute, $value, $fail) {
                    // Validate SSH public key format
                    if (!empty($value) && !$this->isValidSshPublicKey($value)) {
                        $fail('The SSH public key format is invalid.');
                    }
                },
            ],

            // Connection testing
            'test_connection' => [
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
            'hostname.required' => 'A hostname is required for the VPS server.',
            'hostname.unique' => 'This hostname is already registered.',
            'hostname.regex' => 'The hostname format is invalid. Use a valid domain name or hostname.',
            'ip_address.required' => 'An IP address is required.',
            'ip_address.ip' => 'The IP address format is invalid.',
            'ip_address.unique' => 'This IP address is already registered.',
            'provider.required' => 'A provider is required.',
            'provider.in' => 'Invalid provider. Choose from: digitalocean, linode, vultr, aws, hetzner, ovh, or custom.',
            'spec_cpu.integer' => 'CPU cores must be a number.',
            'spec_cpu.min' => 'CPU cores must be at least 1.',
            'spec_memory_mb.integer' => 'Memory must be a number in MB.',
            'spec_memory_mb.min' => 'Memory must be at least 512 MB.',
            'spec_disk_gb.integer' => 'Disk size must be a number in GB.',
            'spec_disk_gb.min' => 'Disk size must be at least 10 GB.',
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

        // Trim IP address
        if ($this->has('ip_address')) {
            $this->merge([
                'ip_address' => trim($this->input('ip_address')),
            ]);
        }

        // Set default allocation type
        $this->merge([
            'allocation_type' => $this->input('allocation_type', 'shared'),
            'test_connection' => $this->input('test_connection', false),
        ]);
    }

    /**
     * Validate SSH private key format.
     *
     * Supports RSA, ED25519, ECDSA formats.
     *
     * @param string $key
     * @return bool
     */
    private function isValidSshPrivateKey(string $key): bool
    {
        // Check for valid SSH private key headers
        $validHeaders = [
            '-----BEGIN RSA PRIVATE KEY-----',
            '-----BEGIN OPENSSH PRIVATE KEY-----',
            '-----BEGIN EC PRIVATE KEY-----',
            '-----BEGIN DSA PRIVATE KEY-----',
        ];

        foreach ($validHeaders as $header) {
            if (str_contains($key, $header)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Validate SSH public key format.
     *
     * @param string $key
     * @return bool
     */
    private function isValidSshPublicKey(string $key): bool
    {
        // SSH public key starts with algorithm identifier
        $validPrefixes = ['ssh-rsa', 'ssh-ed25519', 'ecdsa-sha2-nistp256', 'ssh-dss'];

        foreach ($validPrefixes as $prefix) {
            if (str_starts_with(trim($key), $prefix)) {
                return true;
            }
        }

        return false;
    }
}
