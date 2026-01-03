<?php

declare(strict_types=1);

namespace App\ValueObjects;

use DateTimeImmutable;
use InvalidArgumentException;
use JsonSerializable;

/**
 * PHP version value object
 *
 * Represents a PHP version with support and EOL tracking.
 */
final class PhpVersion implements JsonSerializable
{
    private const SUPPORTED_VERSIONS = ['7.4', '8.0', '8.1', '8.2', '8.3'];

    private const EOL_DATES = [
        '7.4' => '2022-11-28',
        '8.0' => '2023-11-26',
        '8.1' => '2024-11-25',
        '8.2' => '2025-12-08',
        '8.3' => '2026-11-23',
    ];

    /**
     * Create a new PhpVersion instance
     *
     * @param string $major Major version (e.g., "8")
     * @param string $minor Minor version (e.g., "2")
     * @param string $patch Patch version (e.g., "15")
     * @throws InvalidArgumentException If version is invalid
     */
    public function __construct(
        public readonly string $major,
        public readonly string $minor,
        public readonly string $patch = '0'
    ) {
        $this->validate();
    }

    /**
     * Validate the version
     *
     * @throws InvalidArgumentException If version is invalid
     */
    private function validate(): void
    {
        if (!ctype_digit($this->major)) {
            throw new InvalidArgumentException("Invalid major version: {$this->major}");
        }

        if (!ctype_digit($this->minor)) {
            throw new InvalidArgumentException("Invalid minor version: {$this->minor}");
        }

        if (!ctype_digit($this->patch)) {
            throw new InvalidArgumentException("Invalid patch version: {$this->patch}");
        }

        $majorInt = (int)$this->major;
        if ($majorInt < 7 || $majorInt > 8) {
            throw new InvalidArgumentException("Unsupported PHP major version: {$this->major}");
        }
    }

    /**
     * Create from version string
     *
     * @param string $version Version string (e.g., "8.2.15")
     * @return self
     * @throws InvalidArgumentException If version string is invalid
     */
    public static function fromString(string $version): self
    {
        $parts = explode('.', trim($version));

        if (count($parts) < 2) {
            throw new InvalidArgumentException("Invalid version string: {$version}");
        }

        return new self(
            $parts[0],
            $parts[1],
            $parts[2] ?? '0'
        );
    }

    /**
     * Create PHP 7.4
     *
     * @return self
     */
    public static function php74(): self
    {
        return new self('7', '4', '0');
    }

    /**
     * Create PHP 8.0
     *
     * @return self
     */
    public static function php80(): self
    {
        return new self('8', '0', '0');
    }

    /**
     * Create PHP 8.1
     *
     * @return self
     */
    public static function php81(): self
    {
        return new self('8', '1', '0');
    }

    /**
     * Create PHP 8.2
     *
     * @return self
     */
    public static function php82(): self
    {
        return new self('8', '2', '0');
    }

    /**
     * Create PHP 8.3
     *
     * @return self
     */
    public static function php83(): self
    {
        return new self('8', '3', '0');
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function toString(): string
    {
        return "{$this->major}.{$this->minor}.{$this->patch}";
    }

    /**
     * Get major.minor version
     *
     * @return string
     */
    public function getMajorMinor(): string
    {
        return "{$this->major}.{$this->minor}";
    }

    /**
     * Check if this version is supported
     *
     * @return bool
     */
    public function isSupported(): bool
    {
        return in_array($this->getMajorMinor(), self::SUPPORTED_VERSIONS, true);
    }

    /**
     * Check if this version has reached end of life
     *
     * @return bool
     */
    public function isEol(): bool
    {
        $majorMinor = $this->getMajorMinor();

        if (!isset(self::EOL_DATES[$majorMinor])) {
            return true;
        }

        $eolDate = new DateTimeImmutable(self::EOL_DATES[$majorMinor]);
        $now = new DateTimeImmutable();

        return $now > $eolDate;
    }

    /**
     * Get the end of life date
     *
     * @return DateTimeImmutable
     * @throws InvalidArgumentException If EOL date is not known
     */
    public function getEolDate(): DateTimeImmutable
    {
        $majorMinor = $this->getMajorMinor();

        if (!isset(self::EOL_DATES[$majorMinor])) {
            throw new InvalidArgumentException("EOL date not known for version: {$majorMinor}");
        }

        return new DateTimeImmutable(self::EOL_DATES[$majorMinor]);
    }

    /**
     * Get days until EOL (negative if already EOL)
     *
     * @return int
     */
    public function daysUntilEol(): int
    {
        try {
            $eolDate = $this->getEolDate();
            $now = new DateTimeImmutable();
            $interval = $now->diff($eolDate);

            return $interval->invert ? -$interval->days : $interval->days;
        } catch (InvalidArgumentException) {
            return -999;
        }
    }

    /**
     * Check if this version equals another
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function equals(PhpVersion $other): bool
    {
        return $this->major === $other->major
            && $this->minor === $other->minor
            && $this->patch === $other->patch;
    }

    /**
     * Check if this version is newer than another
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function isNewerThan(PhpVersion $other): bool
    {
        if ($this->major !== $other->major) {
            return (int)$this->major > (int)$other->major;
        }

        if ($this->minor !== $other->minor) {
            return (int)$this->minor > (int)$other->minor;
        }

        return (int)$this->patch > (int)$other->patch;
    }

    /**
     * Check if this version is older than another
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function isOlderThan(PhpVersion $other): bool
    {
        return !$this->equals($other) && !$this->isNewerThan($other);
    }

    /**
     * Check if this version is compatible with another (same major.minor)
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function isCompatibleWith(PhpVersion $other): bool
    {
        return $this->getMajorMinor() === $other->getMajorMinor();
    }

    /**
     * Get the latest supported version
     *
     * @return self
     */
    public static function latest(): self
    {
        return self::php83();
    }

    /**
     * Get all supported versions
     *
     * @return array<int, self>
     */
    public static function allSupported(): array
    {
        return [
            self::php74(),
            self::php80(),
            self::php81(),
            self::php82(),
            self::php83(),
        ];
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->toString();
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return [
            'version' => $this->toString(),
            'major_minor' => $this->getMajorMinor(),
            'is_supported' => $this->isSupported(),
            'is_eol' => $this->isEol(),
            'days_until_eol' => $this->daysUntilEol(),
        ];
    }
}
