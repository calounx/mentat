<?php

namespace Database\Factories;

use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;

class VpsServerFactory extends Factory
{
    protected $model = VpsServer::class;

    public function definition(): array
    {
        return [
            'hostname' => 'vps-'.$this->faker->unique()->numberBetween(1, 9999),
            'ip_address' => $this->faker->unique()->ipv4(),
            'provider' => $this->faker->randomElement(['hetzner', 'digitalocean', 'vultr', 'linode']),
            'region' => $this->faker->randomElement(['us-east', 'us-west', 'eu-central', 'asia-pacific']),
            'spec_cpu' => $this->faker->randomElement([2, 4, 8, 16]),
            'spec_memory_mb' => $this->faker->randomElement([2048, 4096, 8192, 16384]),
            'spec_disk_gb' => $this->faker->randomElement([50, 100, 200, 500]),
            'status' => 'active',
            'allocation_type' => $this->faker->randomElement(['shared', 'dedicated']),
            'vpsmanager_version' => null,
            'observability_configured' => false,
            'ssh_key_id' => null,
            'last_health_check_at' => now(),
            'health_status' => 'healthy',
        ];
    }

    /**
     * Indicate that the VPS is active.
     */
    public function active(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'active',
        ]);
    }

    /**
     * Indicate that the VPS is in shared mode.
     */
    public function shared(): static
    {
        return $this->state(fn (array $attributes) => [
            'allocation_type' => 'shared',
        ]);
    }

    /**
     * Indicate that the VPS is in dedicated mode.
     */
    public function dedicated(): static
    {
        return $this->state(fn (array $attributes) => [
            'allocation_type' => 'dedicated',
        ]);
    }

    /**
     * Indicate that the VPS is healthy.
     */
    public function healthy(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'active',
            'health_status' => 'healthy',
            'last_health_check_at' => now(),
        ]);
    }
}
