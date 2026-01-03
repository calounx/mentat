<?php

declare(strict_types=1);

namespace App\ValueObjects;

use App\ValueObjects\Enums\SslProvider;
use DateTimeImmutable;
use InvalidArgumentException;
use JsonSerializable;

/**
 * SSL certificate value object
 *
 * Represents an SSL/TLS certificate with expiration tracking.
 */
final class SslCertificate implements JsonSerializable
{
    private const RENEWAL_THRESHOLD_DAYS = 30;
    private const CRITICAL_THRESHOLD_DAYS = 7;

    /**
     * Create a new SslCertificate instance
     *
     * @param string $domain Domain name for the certificate
     * @param SslProvider $provider SSL provider
     * @param DateTimeImmutable $issuedAt When the certificate was issued
     * @param DateTimeImmutable $expiresAt When the certificate expires
     * @param string $issuer Certificate issuer
     * @param string|null $certificatePath Path to certificate file
     * @param string|null $privateKeyPath Path to private key file
     * @throws InvalidArgumentException If certificate is invalid
     */
    public function __construct(
        public readonly string $domain,
        public readonly SslProvider $provider,
        public readonly DateTimeImmutable $issuedAt,
        public readonly DateTimeImmutable $expiresAt,
        public readonly string $issuer,
        public readonly ?string $certificatePath = null,
        public readonly ?string $privateKeyPath = null
    ) {
        $this->validate();
    }

    /**
     * Validate the certificate
     *
     * @throws InvalidArgumentException If certificate is invalid
     */
    private function validate(): void
    {
        if (empty($this->domain)) {
            throw new InvalidArgumentException('Domain cannot be empty');
        }

        if ($this->expiresAt <= $this->issuedAt) {
            throw new InvalidArgumentException('Expiration date must be after issue date');
        }

        if (empty($this->issuer)) {
            throw new InvalidArgumentException('Issuer cannot be empty');
        }

        if ($this->certificatePath !== null && empty($this->certificatePath)) {
            throw new InvalidArgumentException('Certificate path cannot be empty string');
        }

        if ($this->privateKeyPath !== null && empty($this->privateKeyPath)) {
            throw new InvalidArgumentException('Private key path cannot be empty string');
        }
    }

    /**
     * Create a Let's Encrypt certificate
     *
     * @param string $domain
     * @param DateTimeImmutable|null $issuedAt
     * @return self
     */
    public static function fromLetsEncrypt(string $domain, ?DateTimeImmutable $issuedAt = null): self
    {
        $issuedAt = $issuedAt ?? new DateTimeImmutable();
        $expiresAt = $issuedAt->modify('+90 days');

        return new self(
            domain: $domain,
            provider: SslProvider::LETS_ENCRYPT,
            issuedAt: $issuedAt,
            expiresAt: $expiresAt,
            issuer: "Let's Encrypt"
        );
    }

    /**
     * Create a Cloudflare certificate
     *
     * @param string $domain
     * @param DateTimeImmutable|null $issuedAt
     * @return self
     */
    public static function fromCloudflare(string $domain, ?DateTimeImmutable $issuedAt = null): self
    {
        $issuedAt = $issuedAt ?? new DateTimeImmutable();
        $expiresAt = $issuedAt->modify('+90 days');

        return new self(
            domain: $domain,
            provider: SslProvider::CLOUDFLARE,
            issuedAt: $issuedAt,
            expiresAt: $expiresAt,
            issuer: 'Cloudflare Inc'
        );
    }

    /**
     * Create a custom certificate
     *
     * @param string $domain
     * @param DateTimeImmutable $issuedAt
     * @param DateTimeImmutable $expiresAt
     * @param string $issuer
     * @param string|null $certificatePath
     * @param string|null $privateKeyPath
     * @return self
     */
    public static function custom(
        string $domain,
        DateTimeImmutable $issuedAt,
        DateTimeImmutable $expiresAt,
        string $issuer,
        ?string $certificatePath = null,
        ?string $privateKeyPath = null
    ): self {
        return new self(
            domain: $domain,
            provider: SslProvider::CUSTOM,
            issuedAt: $issuedAt,
            expiresAt: $expiresAt,
            issuer: $issuer,
            certificatePath: $certificatePath,
            privateKeyPath: $privateKeyPath
        );
    }

    /**
     * Check if the certificate is expired
     *
     * @param DateTimeImmutable|null $now Current time (for testing)
     * @return bool
     */
    public function isExpired(?DateTimeImmutable $now = null): bool
    {
        $now = $now ?? new DateTimeImmutable();
        return $now > $this->expiresAt;
    }

    /**
     * Check if the certificate is expiring soon
     *
     * @param int $days Number of days threshold
     * @param DateTimeImmutable|null $now Current time (for testing)
     * @return bool
     */
    public function isExpiringSoon(int $days = self::RENEWAL_THRESHOLD_DAYS, ?DateTimeImmutable $now = null): bool
    {
        $now = $now ?? new DateTimeImmutable();
        $threshold = $now->modify("+{$days} days");
        return $this->expiresAt <= $threshold;
    }

    /**
     * Check if the certificate is in critical state (very close to expiry)
     *
     * @param DateTimeImmutable|null $now Current time (for testing)
     * @return bool
     */
    public function isCritical(?DateTimeImmutable $now = null): bool
    {
        return $this->isExpiringSoon(self::CRITICAL_THRESHOLD_DAYS, $now);
    }

    /**
     * Get days until expiration (negative if expired)
     *
     * @param DateTimeImmutable|null $now Current time (for testing)
     * @return int
     */
    public function daysUntilExpiration(?DateTimeImmutable $now = null): int
    {
        $now = $now ?? new DateTimeImmutable();
        $interval = $now->diff($this->expiresAt);

        return $interval->invert ? -$interval->days : $interval->days;
    }

    /**
     * Check if the certificate needs renewal
     *
     * @param DateTimeImmutable|null $now Current time (for testing)
     * @return bool
     */
    public function needsRenewal(?DateTimeImmutable $now = null): bool
    {
        return $this->isExpiringSoon(self::RENEWAL_THRESHOLD_DAYS, $now);
    }

    /**
     * Get the recommended renewal date
     *
     * @return DateTimeImmutable
     */
    public function getRenewalDate(): DateTimeImmutable
    {
        return $this->expiresAt->modify('-' . self::RENEWAL_THRESHOLD_DAYS . ' days');
    }

    /**
     * Get the certificate validity period in days
     *
     * @return int
     */
    public function getValidityPeriodDays(): int
    {
        $interval = $this->issuedAt->diff($this->expiresAt);
        return $interval->days;
    }

    /**
     * Check if auto-renewal is supported
     *
     * @return bool
     */
    public function supportsAutoRenewal(): bool
    {
        return $this->provider->supportsAutoRenewal();
    }

    /**
     * Get the certificate status
     *
     * @param DateTimeImmutable|null $now Current time (for testing)
     * @return string
     */
    public function getStatus(?DateTimeImmutable $now = null): string
    {
        if ($this->isExpired($now)) {
            return 'expired';
        }

        if ($this->isCritical($now)) {
            return 'critical';
        }

        if ($this->needsRenewal($now)) {
            return 'renewal_needed';
        }

        return 'valid';
    }

    /**
     * Check if this certificate equals another
     *
     * @param SslCertificate $other
     * @return bool
     */
    public function equals(SslCertificate $other): bool
    {
        return $this->domain === $other->domain
            && $this->provider === $other->provider
            && $this->issuedAt == $other->issuedAt
            && $this->expiresAt == $other->expiresAt
            && $this->issuer === $other->issuer;
    }

    /**
     * Create a new certificate with updated paths
     *
     * @param string $certificatePath
     * @param string $privateKeyPath
     * @return self
     */
    public function withPaths(string $certificatePath, string $privateKeyPath): self
    {
        return new self(
            domain: $this->domain,
            provider: $this->provider,
            issuedAt: $this->issuedAt,
            expiresAt: $this->expiresAt,
            issuer: $this->issuer,
            certificatePath: $certificatePath,
            privateKeyPath: $privateKeyPath
        );
    }

    /**
     * Convert to array
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'domain' => $this->domain,
            'provider' => $this->provider->value,
            'issued_at' => $this->issuedAt->format('Y-m-d H:i:s'),
            'expires_at' => $this->expiresAt->format('Y-m-d H:i:s'),
            'issuer' => $this->issuer,
            'certificate_path' => $this->certificatePath,
            'private_key_path' => $this->privateKeyPath,
        ];
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        return sprintf(
            '%s certificate for %s (expires %s)',
            $this->provider->label(),
            $this->domain,
            $this->expiresAt->format('Y-m-d')
        );
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return array_merge($this->toArray(), [
            'provider_label' => $this->provider->label(),
            'is_expired' => $this->isExpired(),
            'is_expiring_soon' => $this->isExpiringSoon(),
            'is_critical' => $this->isCritical(),
            'needs_renewal' => $this->needsRenewal(),
            'days_until_expiration' => $this->daysUntilExpiration(),
            'renewal_date' => $this->getRenewalDate()->format('Y-m-d H:i:s'),
            'status' => $this->getStatus(),
            'supports_auto_renewal' => $this->supportsAutoRenewal(),
            'validity_period_days' => $this->getValidityPeriodDays(),
        ]);
    }
}
