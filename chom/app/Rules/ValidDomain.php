<?php

namespace App\Rules;

use App\Domain\ValueObjects\Domain;
use Illuminate\Contracts\Validation\Rule;
use Illuminate\Support\Facades\Log;

/**
 * Valid Domain Validation Rule.
 *
 * Validates domain format and detects suspicious patterns.
 * Uses the Domain value object for validation logic.
 */
class ValidDomain implements Rule
{
    private string $message = 'The :attribute must be a valid domain name.';

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

        // Use the Domain value object for validation
        if (!Domain::isValid($value)) {
            // Try to get more specific error message
            try {
                Domain::fromString($value);
            } catch (\InvalidArgumentException $e) {
                $this->message = $e->getMessage();

                // Log suspicious domain attempts
                if (str_contains($e->getMessage(), 'suspicious')) {
                    Log::warning('Suspicious domain validation attempt detected', [
                        'domain' => $value,
                        'attribute' => $attribute,
                        'error' => $e->getMessage(),
                        'ip' => request()->ip(),
                        'user_agent' => request()->userAgent(),
                    ]);
                }
            }

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
}
