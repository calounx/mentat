<?php

declare(strict_types=1);

namespace App\Modules\SiteHosting\ValueObjects;

use App\Models\Site;

/**
 * SSL Certificate Value Object
 *
 * Encapsulates SSL certificate information.
 */
final readonly class SslCertificate
{
    public function __construct(
        private string $domain,
        private bool $enabled,
        private ?\DateTime $issuedAt = null,
        private ?\DateTime $expiresAt = null,
        private ?string $issuer = null
    ) {
        $this->validate();
    }

    /**
     * Create from Site model.
     *
     * @param Site $site
     * @return self
     */
    public static function fromSite(Site $site): self
    {
        return new self(
            domain: $site->domain,
            enabled: $site->ssl_enabled ?? false,
            issuedAt: $site->ssl_issued_at ? new \DateTime($site->ssl_issued_at) : null,
            expiresAt: $site->ssl_expires_at ? new \DateTime($site->ssl_expires_at) : null,
            issuer: $site->ssl_issuer ?? null
        );
    }

    /**
     * Create for new certificate.
     *
     * @param string $domain
     * @param string $issuer
     * @return self
     */
    public static function create(string $domain, string $issuer = "Let's Encrypt"): self
    {
        $issuedAt = new \DateTime();
        $expiresAt = (clone $issuedAt)->modify('+90 days');

        return new self(
            domain: $domain,
            enabled: true,
            issuedAt: $issuedAt,
            expiresAt: $expiresAt,
            issuer: $issuer
        );
    }

    /**
     * Get domain.
     *
     * @return string
     */
    public function getDomain(): string
    {
        return $this->domain;
    }

    /**
     * Check if SSL is enabled.
     *
     * @return bool
     */
    public function isEnabled(): bool
    {
        return $this->enabled;
    }

    /**
     * Get issue date.
     *
     * @return \DateTime|null
     */
    public function getIssuedAt(): ?\DateTime
    {
        return $this->issuedAt;
    }

    /**
     * Get expiration date.
     *
     * @return \DateTime|null
     */
    public function getExpiresAt(): ?\DateTime
    {
        return $this->expiresAt;
    }

    /**
     * Get issuer.
     *
     * @return string|null
     */
    public function getIssuer(): ?string
    {
        return $this->issuer;
    }

    /**
     * Check if certificate is expiring soon (within 30 days).
     *
     * @return bool
     */
    public function isExpiringSoon(): bool
    {
        if (!$this->enabled || !$this->expiresAt) {
            return false;
        }

        $now = new \DateTime();
        $daysUntilExpiry = $now->diff($this->expiresAt)->days;

        return $daysUntilExpiry <= 30;
    }

    /**
     * Check if certificate is expired.
     *
     * @return bool
     */
    public function isExpired(): bool
    {
        if (!$this->enabled || !$this->expiresAt) {
            return false;
        }

        return $this->expiresAt < new \DateTime();
    }

    /**
     * Get days until expiration.
     *
     * @return int|null
     */
    public function getDaysUntilExpiration(): ?int
    {
        if (!$this->enabled || !$this->expiresAt) {
            return null;
        }

        $now = new \DateTime();

        if ($this->isExpired()) {
            return 0;
        }

        return $now->diff($this->expiresAt)->days;
    }

    /**
     * Validate the certificate data.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->domain)) {
            throw new \InvalidArgumentException('SSL certificate domain cannot be empty');
        }

        if ($this->enabled && !$this->expiresAt) {
            throw new \InvalidArgumentException('Enabled SSL certificate must have expiration date');
        }

        if ($this->issuedAt && $this->expiresAt && $this->issuedAt >= $this->expiresAt) {
            throw new \InvalidArgumentException('SSL certificate issue date must be before expiration date');
        }
    }

    /**
     * Convert to array.
     *
     * @return array
     */
    public function toArray(): array
    {
        return [
            'domain' => $this->domain,
            'enabled' => $this->enabled,
            'issued_at' => $this->issuedAt?->format('Y-m-d H:i:s'),
            'expires_at' => $this->expiresAt?->format('Y-m-d H:i:s'),
            'issuer' => $this->issuer,
            'is_expiring_soon' => $this->isExpiringSoon(),
            'is_expired' => $this->isExpired(),
            'days_until_expiration' => $this->getDaysUntilExpiration(),
        ];
    }
}
