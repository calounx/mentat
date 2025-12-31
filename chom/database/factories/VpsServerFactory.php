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
            'hostname' => 'vps-' . $this->faker->unique()->numberBetween(1, 9999),
            'ip_address' => $this->faker->unique()->ipv4(),
            'provider' => $this->faker->randomElement(['hetzner', 'digitalocean', 'vultr', 'linode']),
            'location' => $this->faker->randomElement(['us-east', 'us-west', 'eu-central', 'asia-pacific']),
            'status' => 'active',
            'allocation_mode' => $this->faker->randomElement(['shared', 'dedicated']),
            'max_sites' => $this->faker->numberBetween(10, 100),
            'total_memory_mb' => $this->faker->randomElement([2048, 4096, 8192, 16384]),
            'total_storage_gb' => $this->faker->randomElement([50, 100, 200, 500]),
            'total_bandwidth_gb' => $this->faker->randomElement([1000, 2000, 5000]),
            'cpu_cores' => $this->faker->randomElement([2, 4, 8, 16]),
            'ssh_port' => 22,
            'ssh_user' => 'root',
            'notes' => null,
            'last_health_check' => now(),
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
            'allocation_mode' => 'shared',
        ]);
    }

    /**
     * Indicate that the VPS is in dedicated mode.
     */
    public function dedicated(): static
    {
        return $this->state(fn (array $attributes) => [
            'allocation_mode' => 'dedicated',
        ]);
    }

    /**
     * Indicate that the VPS is healthy.
     */
    public function healthy(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'active',
            'last_health_check' => now(),
        ]);
    }
}
