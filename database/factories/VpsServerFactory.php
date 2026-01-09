<?php

namespace Database\Factories;

use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\VpsServer>
 */
class VpsServerFactory extends Factory
{
    protected $model = VpsServer::class;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $providers = ['digitalocean', 'linode', 'vultr', 'hetzner'];
        $regions = ['nyc1', 'nyc3', 'sfo3', 'lon1', 'fra1', 'tor1'];
        $hostname = fake()->domainWord() . '-' . Str::random(4);

        return [
            'hostname' => $hostname . '.example.com',
            'ip_address' => fake()->ipv4(),
            'provider' => fake()->randomElement($providers),
            'provider_id' => Str::random(16),
            'region' => fake()->randomElement($regions),
            'spec_cpu' => fake()->numberBetween(1, 8),
            'spec_memory_mb' => fake()->randomElement([1024, 2048, 4096, 8192, 16384]),
            'spec_disk_gb' => fake()->randomElement([25, 50, 80, 160, 320]),
            'status' => 'active',
            'allocation_type' => 'shared',
            'vpsmanager_version' => '2.0.0',
            'observability_configured' => true,
            'ssh_key_id' => null,
            'last_health_check_at' => now(),
            'health_status' => 'healthy',
            'health_error' => null,
        ];
    }

    /**
     * Indicate that the VPS is provisioning.
     */
    public function provisioning(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'provisioning',
            'health_status' => 'unknown',
        ]);
    }

    /**
     * Indicate that the VPS is unhealthy.
     */
    public function unhealthy(): static
    {
        return $this->state(fn (array $attributes) => [
            'health_status' => 'unhealthy',
            'health_error' => 'High memory usage detected',
        ]);
    }

    /**
     * Indicate that the VPS is dedicated (not shared).
     */
    public function dedicated(): static
    {
        return $this->state(fn (array $attributes) => [
            'allocation_type' => 'dedicated',
        ]);
    }

    /**
     * Indicate that the VPS has no observability configured.
     */
    public function withoutObservability(): static
    {
        return $this->state(fn (array $attributes) => [
            'observability_configured' => false,
        ]);
    }

    /**
     * Specify VPS specifications.
     */
    public function withSpecs(int $cpu, int $memoryMb, int $diskGb): static
    {
        return $this->state(fn (array $attributes) => [
            'spec_cpu' => $cpu,
            'spec_memory_mb' => $memoryMb,
            'spec_disk_gb' => $diskGb,
        ]);
    }

    /**
     * Set VPS to a specific provider and region.
     */
    public function provider(string $provider, string $region): static
    {
        return $this->state(fn (array $attributes) => [
            'provider' => $provider,
            'region' => $region,
        ]);
    }
}
