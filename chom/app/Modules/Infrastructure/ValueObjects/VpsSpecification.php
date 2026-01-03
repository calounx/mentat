<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\ValueObjects;

/**
 * VPS Specification Value Object
 *
 * Encapsulates VPS server specifications.
 */
final readonly class VpsSpecification
{
    public function __construct(
        private string $provider,
        private string $region,
        private int $memoryMb,
        private int $diskGb,
        private int $cpuCores,
        private ?string $ipAddress = null
    ) {
        $this->validate();
    }

    /**
     * Create a small VPS specification.
     *
     * @param string $provider Provider name
     * @param string $region Region code
     * @return self
     */
    public static function small(string $provider = 'digitalocean', string $region = 'nyc1'): self
    {
        return new self(
            provider: $provider,
            region: $region,
            memoryMb: 2048,
            diskGb: 50,
            cpuCores: 1
        );
    }

    /**
     * Create a medium VPS specification.
     *
     * @param string $provider Provider name
     * @param string $region Region code
     * @return self
     */
    public static function medium(string $provider = 'digitalocean', string $region = 'nyc1'): self
    {
        return new self(
            provider: $provider,
            region: $region,
            memoryMb: 4096,
            diskGb: 100,
            cpuCores: 2
        );
    }

    /**
     * Create a large VPS specification.
     *
     * @param string $provider Provider name
     * @param string $region Region code
     * @return self
     */
    public static function large(string $provider = 'digitalocean', string $region = 'nyc1'): self
    {
        return new self(
            provider: $provider,
            region: $region,
            memoryMb: 8192,
            diskGb: 200,
            cpuCores: 4
        );
    }

    /**
     * Get provider.
     *
     * @return string
     */
    public function getProvider(): string
    {
        return $this->provider;
    }

    /**
     * Get region.
     *
     * @return string
     */
    public function getRegion(): string
    {
        return $this->region;
    }

    /**
     * Get memory in MB.
     *
     * @return int
     */
    public function getMemoryMb(): int
    {
        return $this->memoryMb;
    }

    /**
     * Get memory in GB.
     *
     * @return float
     */
    public function getMemoryGb(): float
    {
        return round($this->memoryMb / 1024, 2);
    }

    /**
     * Get disk size in GB.
     *
     * @return int
     */
    public function getDiskGb(): int
    {
        return $this->diskGb;
    }

    /**
     * Get CPU cores.
     *
     * @return int
     */
    public function getCpuCores(): int
    {
        return $this->cpuCores;
    }

    /**
     * Get IP address.
     *
     * @return string|null
     */
    public function getIpAddress(): ?string
    {
        return $this->ipAddress;
    }

    /**
     * Create with IP address.
     *
     * @param string $ipAddress
     * @return self
     */
    public function withIpAddress(string $ipAddress): self
    {
        return new self(
            $this->provider,
            $this->region,
            $this->memoryMb,
            $this->diskGb,
            $this->cpuCores,
            $ipAddress
        );
    }

    /**
     * Validate the specification.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->provider)) {
            throw new \InvalidArgumentException('VPS provider cannot be empty');
        }

        if (empty($this->region)) {
            throw new \InvalidArgumentException('VPS region cannot be empty');
        }

        if ($this->memoryMb < 512) {
            throw new \InvalidArgumentException('VPS memory must be at least 512MB');
        }

        if ($this->diskGb < 10) {
            throw new \InvalidArgumentException('VPS disk must be at least 10GB');
        }

        if ($this->cpuCores < 1) {
            throw new \InvalidArgumentException('VPS must have at least 1 CPU core');
        }

        if ($this->ipAddress !== null && !filter_var($this->ipAddress, FILTER_VALIDATE_IP)) {
            throw new \InvalidArgumentException('Invalid IP address format');
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
            'provider' => $this->provider,
            'region' => $this->region,
            'memory_mb' => $this->memoryMb,
            'memory_gb' => $this->getMemoryGb(),
            'disk_gb' => $this->diskGb,
            'cpu_cores' => $this->cpuCores,
            'ip_address' => $this->ipAddress,
        ];
    }
}
