<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * Money value object
 *
 * Represents a monetary amount with currency. Stores amounts in cents to avoid
 * floating-point precision issues.
 */
final class Money implements JsonSerializable
{
    /**
     * Create a new Money instance
     *
     * @param int $cents Amount in cents (e.g., 1000 = $10.00)
     * @param string $currency ISO 4217 currency code
     * @throws InvalidArgumentException If currency is invalid
     */
    public function __construct(
        public readonly int $cents,
        public readonly string $currency = 'USD'
    ) {
        if (!preg_match('/^[A-Z]{3}$/', $this->currency)) {
            throw new InvalidArgumentException("Invalid currency code: {$this->currency}");
        }
    }

    /**
     * Create Money from dollar amount
     *
     * @param float $dollars Dollar amount
     * @param string $currency ISO 4217 currency code
     * @return self
     */
    public static function fromDollars(float $dollars, string $currency = 'USD'): self
    {
        return new self((int)round($dollars * 100), $currency);
    }

    /**
     * Create Money from zero
     *
     * @param string $currency ISO 4217 currency code
     * @return self
     */
    public static function zero(string $currency = 'USD'): self
    {
        return new self(0, $currency);
    }

    /**
     * Convert to dollars
     *
     * @return float
     */
    public function toDollars(): float
    {
        return $this->cents / 100;
    }

    /**
     * Get amount in cents
     *
     * @return int
     */
    public function toCents(): int
    {
        return $this->cents;
    }

    /**
     * Format as currency string
     *
     * @return string
     */
    public function format(): string
    {
        $symbol = match ($this->currency) {
            'USD' => '$',
            'EUR' => '€',
            'GBP' => '£',
            'JPY' => '¥',
            default => $this->currency . ' ',
        };

        $amount = number_format(abs($this->toDollars()), 2);
        $formatted = $symbol . $amount;

        return $this->cents < 0 ? '-' . $formatted : $formatted;
    }

    /**
     * Add another money amount
     *
     * @param Money $other
     * @return self
     * @throws InvalidArgumentException If currencies don't match
     */
    public function add(Money $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->cents + $other->cents, $this->currency);
    }

    /**
     * Subtract another money amount
     *
     * @param Money $other
     * @return self
     * @throws InvalidArgumentException If currencies don't match
     */
    public function subtract(Money $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->cents - $other->cents, $this->currency);
    }

    /**
     * Multiply by a factor
     *
     * @param int|float $factor
     * @return self
     */
    public function multiply(int|float $factor): self
    {
        return new self((int)round($this->cents * $factor), $this->currency);
    }

    /**
     * Divide by a divisor
     *
     * @param int|float $divisor
     * @return self
     * @throws InvalidArgumentException If divisor is zero
     */
    public function divide(int|float $divisor): self
    {
        if ($divisor == 0) {
            throw new InvalidArgumentException('Cannot divide by zero');
        }
        return new self((int)round($this->cents / $divisor), $this->currency);
    }

    /**
     * Check if this amount equals another
     *
     * @param Money $other
     * @return bool
     */
    public function equals(Money $other): bool
    {
        return $this->cents === $other->cents && $this->currency === $other->currency;
    }

    /**
     * Check if this amount is greater than another
     *
     * @param Money $other
     * @return bool
     * @throws InvalidArgumentException If currencies don't match
     */
    public function isGreaterThan(Money $other): bool
    {
        $this->assertSameCurrency($other);
        return $this->cents > $other->cents;
    }

    /**
     * Check if this amount is greater than or equal to another
     *
     * @param Money $other
     * @return bool
     * @throws InvalidArgumentException If currencies don't match
     */
    public function isGreaterThanOrEqual(Money $other): bool
    {
        $this->assertSameCurrency($other);
        return $this->cents >= $other->cents;
    }

    /**
     * Check if this amount is less than another
     *
     * @param Money $other
     * @return bool
     * @throws InvalidArgumentException If currencies don't match
     */
    public function isLessThan(Money $other): bool
    {
        $this->assertSameCurrency($other);
        return $this->cents < $other->cents;
    }

    /**
     * Check if this amount is less than or equal to another
     *
     * @param Money $other
     * @return bool
     * @throws InvalidArgumentException If currencies don't match
     */
    public function isLessThanOrEqual(Money $other): bool
    {
        $this->assertSameCurrency($other);
        return $this->cents <= $other->cents;
    }

    /**
     * Check if amount is zero
     *
     * @return bool
     */
    public function isZero(): bool
    {
        return $this->cents === 0;
    }

    /**
     * Check if amount is positive
     *
     * @return bool
     */
    public function isPositive(): bool
    {
        return $this->cents > 0;
    }

    /**
     * Check if amount is negative
     *
     * @return bool
     */
    public function isNegative(): bool
    {
        return $this->cents < 0;
    }

    /**
     * Get absolute value
     *
     * @return self
     */
    public function abs(): self
    {
        return new self(abs($this->cents), $this->currency);
    }

    /**
     * Get negative value
     *
     * @return self
     */
    public function negate(): self
    {
        return new self(-$this->cents, $this->currency);
    }

    /**
     * Assert that currencies match
     *
     * @param Money $other
     * @throws InvalidArgumentException If currencies don't match
     */
    private function assertSameCurrency(Money $other): void
    {
        if ($this->currency !== $other->currency) {
            throw new InvalidArgumentException(
                "Cannot operate on different currencies: {$this->currency} and {$other->currency}"
            );
        }
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->format();
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return [
            'cents' => $this->cents,
            'dollars' => $this->toDollars(),
            'currency' => $this->currency,
            'formatted' => $this->format(),
        ];
    }
}
