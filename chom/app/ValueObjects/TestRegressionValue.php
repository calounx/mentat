<?php

namespace App\ValueObjects;

use InvalidArgumentException;
use Stringable;

class TestRegressionValue implements Stringable
{
    /**
     * Create a new value object instance.
     */
    public function __construct(
        private readonly string $value
    ) {
        $this->validate($value);
    }

    /**
     * Validate the value.
     *
     * @throws InvalidArgumentException
     */
    protected function validate(string $value): void
    {
        if (empty($value)) {
            throw new InvalidArgumentException('Value cannot be empty');
        }

        // Add your validation logic here
    }

    /**
     * Get the string value.
     */
    public function toString(): string
    {
        return $this->value;
    }

    /**
     * Get the string representation.
     */
    public function __toString(): string
    {
        return $this->toString();
    }

    /**
     * Check equality with another value object.
     */
    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Create a new instance from a string.
     */
    public static function fromString(string $value): self
    {
        return new self($value);
    }
}
