<?php

declare(strict_types=1);

namespace App\Modules\SiteHosting\ValueObjects;

/**
 * PHP Version Value Object
 *
 * Encapsulates PHP version information with validation.
 */
final readonly class PhpVersion
{
    private const SUPPORTED_VERSIONS = ['7.4', '8.0', '8.1', '8.2', '8.3'];

    public function __construct(
        private string $version
    ) {
        $this->validate();
    }

    /**
     * Create from string version.
     *
     * @param string $version Version string (e.g., '8.2')
     * @return self
     * @throws \InvalidArgumentException
     */
    public static function fromString(string $version): self
    {
        return new self($version);
    }

    /**
     * Get the version string.
     *
     * @return string
     */
    public function toString(): string
    {
        return $this->version;
    }

    /**
     * Get major version.
     *
     * @return int
     */
    public function getMajor(): int
    {
        return (int) explode('.', $this->version)[0];
    }

    /**
     * Get minor version.
     *
     * @return int
     */
    public function getMinor(): int
    {
        return (int) explode('.', $this->version)[1];
    }

    /**
     * Check if this version is newer than another.
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function isNewerThan(PhpVersion $other): bool
    {
        return version_compare($this->version, $other->version, '>');
    }

    /**
     * Check if this version is older than another.
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function isOlderThan(PhpVersion $other): bool
    {
        return version_compare($this->version, $other->version, '<');
    }

    /**
     * Check if version is supported.
     *
     * @return bool
     */
    public function isSupported(): bool
    {
        return in_array($this->version, self::SUPPORTED_VERSIONS, true);
    }

    /**
     * Get all supported versions.
     *
     * @return array
     */
    public static function getSupportedVersions(): array
    {
        return self::SUPPORTED_VERSIONS;
    }

    /**
     * Validate the version.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (!$this->isSupported()) {
            throw new \InvalidArgumentException(
                sprintf(
                    'Unsupported PHP version: %s. Supported versions: %s',
                    $this->version,
                    implode(', ', self::SUPPORTED_VERSIONS)
                )
            );
        }

        if (!preg_match('/^\d+\.\d+$/', $this->version)) {
            throw new \InvalidArgumentException(
                'PHP version must be in format: major.minor (e.g., 8.2)'
            );
        }
    }

    /**
     * String representation.
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->version;
    }

    /**
     * Check equality.
     *
     * @param PhpVersion $other
     * @return bool
     */
    public function equals(PhpVersion $other): bool
    {
        return $this->version === $other->version;
    }
}
