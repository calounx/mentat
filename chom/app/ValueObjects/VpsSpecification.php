<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * VPS specification value object
 *
 * Encapsulates VPS server specifications with validation and cost calculation.
 */
final class VpsSpecification implements JsonSerializable
{
    private const MIN_CPU = 1;
    private const MAX_CPU = 32;
    private const MIN_RAM_MB = 512;
    private const MAX_RAM_MB = 65536;
    private const MIN_DISK_GB = 10;
    private const MAX_DISK_GB = 1024;

    private const AVAILABLE_REGIONS = [
        'us-east-1' => 'US East (N. Virginia)',
        'us-west-1' => 'US West (N. California)',
        'us-west-2' => 'US West (Oregon)',
        'eu-west-1' => 'EU (Ireland)',
        'eu-central-1' => 'EU (Frankfurt)',
        'ap-southeast-1' => 'Asia Pacific (Singapore)',
        'ap-northeast-1' => 'Asia Pacific (Tokyo)',
    ];

    private const SUPPORTED_OS = [
        'debian-12' => 'Debian 12 (Bookworm)',
        'debian-11' => 'Debian 11 (Bullseye)',
        'ubuntu-22.04' => 'Ubuntu 22.04 LTS',
        'ubuntu-20.04' => 'Ubuntu 20.04 LTS',
        'centos-8' => 'CentOS 8',
        'rocky-9' => 'Rocky Linux 9',
    ];

    private const BASE_COST_PER_HOUR = 0.007;
    private const CPU_COST_PER_CORE = 0.01;
    private const RAM_COST_PER_GB = 0.005;
    private const DISK_COST_PER_GB = 0.0001;

    /**
     * Create a new VpsSpecification instance
     *
     * @param int $cpuCores Number of CPU cores
     * @param int $ramMb RAM in megabytes
     * @param int $diskGb Disk space in gigabytes
     * @param string $region Cloud region
     * @param string $os Operating system
     * @throws InvalidArgumentException If any specification is invalid
     */
    public function __construct(
        public readonly int $cpuCores,
        public readonly int $ramMb,
        public readonly int $diskGb,
        public readonly string $region,
        public readonly string $os = 'debian-12'
    ) {
        $this->validate();
    }

    /**
     * Validate all specifications
     *
     * @throws InvalidArgumentException If any specification is invalid
     */
    private function validate(): void
    {
        if ($this->cpuCores < self::MIN_CPU || $this->cpuCores > self::MAX_CPU) {
            throw new InvalidArgumentException(
                "CPU cores must be between " . self::MIN_CPU . " and " . self::MAX_CPU
            );
        }

        if ($this->ramMb < self::MIN_RAM_MB || $this->ramMb > self::MAX_RAM_MB) {
            throw new InvalidArgumentException(
                "RAM must be between " . self::MIN_RAM_MB . "MB and " . self::MAX_RAM_MB . "MB"
            );
        }

        if ($this->diskGb < self::MIN_DISK_GB || $this->diskGb > self::MAX_DISK_GB) {
            throw new InvalidArgumentException(
                "Disk space must be between " . self::MIN_DISK_GB . "GB and " . self::MAX_DISK_GB . "GB"
            );
        }

        if (!isset(self::AVAILABLE_REGIONS[$this->region])) {
            throw new InvalidArgumentException("Invalid region: {$this->region}");
        }

        if (!isset(self::SUPPORTED_OS[$this->os])) {
            throw new InvalidArgumentException("Unsupported operating system: {$this->os}");
        }
    }

    /**
     * Create from array
     *
     * @param array<string, mixed> $data
     * @return self
     */
    public static function fromArray(array $data): self
    {
        return new self(
            cpuCores: (int)($data['cpu_cores'] ?? $data['cpuCores'] ?? 1),
            ramMb: (int)($data['ram_mb'] ?? $data['ramMb'] ?? 1024),
            diskGb: (int)($data['disk_gb'] ?? $data['diskGb'] ?? 25),
            region: (string)($data['region'] ?? 'us-east-1'),
            os: (string)($data['os'] ?? 'debian-12')
        );
    }

    /**
     * Create a small VPS specification
     *
     * @param string $region
     * @return self
     */
    public static function small(string $region = 'us-east-1'): self
    {
        return new self(
            cpuCores: 1,
            ramMb: 1024,
            diskGb: 25,
            region: $region
        );
    }

    /**
     * Create a medium VPS specification
     *
     * @param string $region
     * @return self
     */
    public static function medium(string $region = 'us-east-1'): self
    {
        return new self(
            cpuCores: 2,
            ramMb: 4096,
            diskGb: 50,
            region: $region
        );
    }

    /**
     * Create a large VPS specification
     *
     * @param string $region
     * @return self
     */
    public static function large(string $region = 'us-east-1'): self
    {
        return new self(
            cpuCores: 4,
            ramMb: 8192,
            diskGb: 100,
            region: $region
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
            'cpu_cores' => $this->cpuCores,
            'ram_mb' => $this->ramMb,
            'ram_gb' => $this->getRamGb(),
            'disk_gb' => $this->diskGb,
            'region' => $this->region,
            'region_name' => $this->getRegionName(),
            'os' => $this->os,
            'os_name' => $this->getOsName(),
        ];
    }

    /**
     * Check if this specification equals another
     *
     * @param VpsSpecification $other
     * @return bool
     */
    public function equals(VpsSpecification $other): bool
    {
        return $this->cpuCores === $other->cpuCores
            && $this->ramMb === $other->ramMb
            && $this->diskGb === $other->diskGb
            && $this->region === $other->region
            && $this->os === $other->os;
    }

    /**
     * Check if this specification meets or exceeds minimum requirements
     *
     * @param VpsSpecification $minimum
     * @return bool
     */
    public function isAtLeast(VpsSpecification $minimum): bool
    {
        return $this->cpuCores >= $minimum->cpuCores
            && $this->ramMb >= $minimum->ramMb
            && $this->diskGb >= $minimum->diskGb;
    }

    /**
     * Calculate monthly cost in dollars
     *
     * @return float
     */
    public function getMonthlyCost(): float
    {
        return $this->getHourlyCost() * 730;
    }

    /**
     * Calculate hourly cost in dollars
     *
     * @return float
     */
    public function getHourlyCost(): float
    {
        $baseCost = self::BASE_COST_PER_HOUR;
        $cpuCost = $this->cpuCores * self::CPU_COST_PER_CORE;
        $ramCost = $this->getRamGb() * self::RAM_COST_PER_GB;
        $diskCost = $this->diskGb * self::DISK_COST_PER_GB;

        return $baseCost + $cpuCost + $ramCost + $diskCost;
    }

    /**
     * Get RAM in gigabytes
     *
     * @return float
     */
    public function getRamGb(): float
    {
        return $this->ramMb / 1024;
    }

    /**
     * Get region name
     *
     * @return string
     */
    public function getRegionName(): string
    {
        return self::AVAILABLE_REGIONS[$this->region];
    }

    /**
     * Get OS name
     *
     * @return string
     */
    public function getOsName(): string
    {
        return self::SUPPORTED_OS[$this->os];
    }

    /**
     * Create a new specification with different CPU
     *
     * @param int $cpuCores
     * @return self
     */
    public function withCpuCores(int $cpuCores): self
    {
        return new self(
            cpuCores: $cpuCores,
            ramMb: $this->ramMb,
            diskGb: $this->diskGb,
            region: $this->region,
            os: $this->os
        );
    }

    /**
     * Create a new specification with different RAM
     *
     * @param int $ramMb
     * @return self
     */
    public function withRamMb(int $ramMb): self
    {
        return new self(
            cpuCores: $this->cpuCores,
            ramMb: $ramMb,
            diskGb: $this->diskGb,
            region: $this->region,
            os: $this->os
        );
    }

    /**
     * Create a new specification with different disk
     *
     * @param int $diskGb
     * @return self
     */
    public function withDiskGb(int $diskGb): self
    {
        return new self(
            cpuCores: $this->cpuCores,
            ramMb: $this->ramMb,
            diskGb: $diskGb,
            region: $this->region,
            os: $this->os
        );
    }

    /**
     * Create a new specification with different region
     *
     * @param string $region
     * @return self
     */
    public function withRegion(string $region): self
    {
        return new self(
            cpuCores: $this->cpuCores,
            ramMb: $this->ramMb,
            diskGb: $this->diskGb,
            region: $region,
            os: $this->os
        );
    }

    /**
     * Create a new specification with different OS
     *
     * @param string $os
     * @return self
     */
    public function withOs(string $os): self
    {
        return new self(
            cpuCores: $this->cpuCores,
            ramMb: $this->ramMb,
            diskGb: $this->diskGb,
            region: $this->region,
            os: $os
        );
    }

    /**
     * Get all available regions
     *
     * @return array<string, string>
     */
    public static function availableRegions(): array
    {
        return self::AVAILABLE_REGIONS;
    }

    /**
     * Get all supported operating systems
     *
     * @return array<string, string>
     */
    public static function supportedOs(): array
    {
        return self::SUPPORTED_OS;
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        return sprintf(
            '%d vCPU, %dGB RAM, %dGB Disk (%s)',
            $this->cpuCores,
            (int)$this->getRamGb(),
            $this->diskGb,
            $this->region
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
            'hourly_cost' => $this->getHourlyCost(),
            'monthly_cost' => $this->getMonthlyCost(),
            'formatted_cost' => '$' . number_format($this->getMonthlyCost(), 2) . '/mo',
        ]);
    }
}
