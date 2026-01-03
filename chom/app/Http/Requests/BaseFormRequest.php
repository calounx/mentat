<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Base Form Request
 *
 * Provides common validation rules and utilities for all form requests.
 * Centralizes domain validation, tenant access checks, and error messages.
 */
abstract class BaseFormRequest extends FormRequest
{
    /**
     * Common domain validation rules.
     *
     * @param bool $required Whether domain is required
     * @return array
     */
    protected function domainRules(bool $required = true): array
    {
        $rules = [
            $required ? 'required' : 'sometimes',
            'string',
            'max:255',
            'regex:/^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/i',
        ];

        return array_filter($rules);
    }

    /**
     * Common PHP version validation rules.
     *
     * @return array
     */
    protected function phpVersionRules(): array
    {
        return [
            'sometimes',
            'string',
            Rule::in(['7.4', '8.0', '8.1', '8.2', '8.3']),
        ];
    }

    /**
     * Common site type validation rules.
     *
     * @return array
     */
    protected function siteTypeRules(): array
    {
        return [
            'sometimes',
            'string',
            Rule::in(['wordpress', 'laravel', 'static', 'custom']),
        ];
    }

    /**
     * Get the tenant ID for the current user.
     *
     * @return string|null
     */
    protected function getTenantId(): ?string
    {
        return $this->user()?->currentTenant()?->id;
    }

    /**
     * Get the organization ID for the current user.
     *
     * @return string|null
     */
    protected function getOrganizationId(): ?string
    {
        return $this->user()?->organization_id;
    }

    /**
     * Check if user can manage sites.
     *
     * @return bool
     */
    protected function canManageSites(): bool
    {
        return $this->user() && $this->user()->canManageSites();
    }

    /**
     * Check if user is admin or owner.
     *
     * @return bool
     */
    protected function isAdmin(): bool
    {
        return $this->user() && $this->user()->isAdmin();
    }

    /**
     * Check if user is owner.
     *
     * @return bool
     */
    protected function isOwner(): bool
    {
        return $this->user() && $this->user()->isOwner();
    }

    /**
     * Common error messages.
     *
     * @return array
     */
    public function messages(): array
    {
        return [
            'domain.required' => 'Domain name is required.',
            'domain.regex' => 'Please enter a valid domain name (e.g., example.com).',
            'domain.unique' => 'This domain is already in use.',
            'php_version.in' => 'Please select a valid PHP version.',
            'site_type.in' => 'Please select a valid site type.',
        ];
    }
}
