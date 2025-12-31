<?php

namespace App\Http\Requests\V1\Sites;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Update Site Request
 *
 * Handles validation and authorization for site updates.
 */
class UpdateSiteRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        $tenant = $this->user()->currentTenant();
        $site = $tenant->sites()->find($this->route('id'));

        if (!$site) {
            return false;
        }

        return $this->user()->can('update', $site);
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'php_version' => [
                'sometimes',
                'string',
                Rule::in(['8.2', '8.4']),
            ],
            'settings' => [
                'sometimes',
                'array',
            ],
            'settings.auto_update' => [
                'sometimes',
                'boolean',
            ],
            'settings.cache_enabled' => [
                'sometimes',
                'boolean',
            ],
            'settings.debug_mode' => [
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
            'php_version.in' => 'The PHP version must be 8.2 or 8.4.',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Sanitize settings if present
        if ($this->has('settings')) {
            $settings = $this->input('settings');

            // Ensure boolean values are properly typed
            if (isset($settings['auto_update'])) {
                $settings['auto_update'] = filter_var($settings['auto_update'], FILTER_VALIDATE_BOOLEAN);
            }
            if (isset($settings['cache_enabled'])) {
                $settings['cache_enabled'] = filter_var($settings['cache_enabled'], FILTER_VALIDATE_BOOLEAN);
            }
            if (isset($settings['debug_mode'])) {
                $settings['debug_mode'] = filter_var($settings['debug_mode'], FILTER_VALIDATE_BOOLEAN);
            }

            $this->merge(['settings' => $settings]);
        }
    }
}
