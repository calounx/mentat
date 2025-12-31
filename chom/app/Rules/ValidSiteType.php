<?php

namespace App\Rules;

use App\Services\Sites\Provisioners\ProvisionerFactory;
use Illuminate\Contracts\Validation\Rule;

/**
 * Valid Site Type Validation Rule.
 *
 * Validates that the site type is supported by the provisioner factory.
 * Extensible - automatically supports new site types when provisioners are added.
 */
class ValidSiteType implements Rule
{
    private string $message = 'The :attribute must be a valid site type.';
    private array $supportedTypes = [];

    public function __construct(
        private ProvisionerFactory $provisionerFactory
    ) {
        $this->supportedTypes = $this->provisionerFactory->getSupportedTypes();
    }

    /**
     * Determine if the validation rule passes.
     *
     * @param string $attribute
     * @param mixed $value
     * @return bool
     */
    public function passes($attribute, $value): bool
    {
        if (!is_string($value)) {
            $this->message = 'The :attribute must be a string.';
            return false;
        }

        if (!$this->provisionerFactory->supports($value)) {
            $this->message = "The :attribute must be one of: " .
                implode(', ', $this->supportedTypes) . '.';
            return false;
        }

        return true;
    }

    /**
     * Get the validation error message.
     *
     * @return string
     */
    public function message(): string
    {
        return $this->message;
    }

    /**
     * Get supported site types.
     *
     * @return array
     */
    public function getSupportedTypes(): array
    {
        return $this->supportedTypes;
    }
}
