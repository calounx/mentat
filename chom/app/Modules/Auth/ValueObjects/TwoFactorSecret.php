<?php

declare(strict_types=1);

namespace App\Modules\Auth\ValueObjects;

/**
 * Two-Factor Secret Value Object
 *
 * Encapsulates a two-factor authentication secret.
 */
final readonly class TwoFactorSecret
{
    public function __construct(
        private string $secret,
        private string $qrCodeUrl,
        private array $recoveryCodes
    ) {
        $this->validate();
    }

    /**
     * Create from secret string.
     *
     * @param string $secret
     * @param string $appName
     * @param string $email
     * @param array $recoveryCodes
     * @return self
     */
    public static function create(string $secret, string $appName, string $email, array $recoveryCodes): self
    {
        $qrCodeUrl = sprintf(
            'otpauth://totp/%s:%s?secret=%s&issuer=%s',
            urlencode($appName),
            urlencode($email),
            $secret,
            urlencode($appName)
        );

        return new self($secret, $qrCodeUrl, $recoveryCodes);
    }

    /**
     * Get the secret.
     *
     * @return string
     */
    public function getSecret(): string
    {
        return $this->secret;
    }

    /**
     * Get the QR code URL.
     *
     * @return string
     */
    public function getQrCodeUrl(): string
    {
        return $this->qrCodeUrl;
    }

    /**
     * Get recovery codes.
     *
     * @return array
     */
    public function getRecoveryCodes(): array
    {
        return $this->recoveryCodes;
    }

    /**
     * Validate the secret.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->secret)) {
            throw new \InvalidArgumentException('Two-factor secret cannot be empty');
        }

        if (strlen($this->secret) < 16) {
            throw new \InvalidArgumentException('Two-factor secret must be at least 16 characters');
        }

        if (count($this->recoveryCodes) < 1) {
            throw new \InvalidArgumentException('At least one recovery code is required');
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
            'secret' => $this->secret,
            'qr_code_url' => $this->qrCodeUrl,
            'recovery_codes' => $this->recoveryCodes,
        ];
    }
}
