<?php

namespace Database\Factories;

use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class VpsServerFactory extends Factory
{
    protected $model = VpsServer::class;

    public function definition(): array
    {
        return [
            'id' => Str::uuid()->toString(),
            'hostname' => 'vps' . $this->faker->numberBetween(1, 999) . '.example.com',
            'ip_address' => $this->faker->ipv4(),
            'status' => 'active',
            'health_status' => 'healthy',
            'provider' => $this->faker->randomElement(['digitalocean', 'vultr', 'linode']),
            'region' => $this->faker->randomElement(['nyc1', 'sfo1', 'lon1']),
            'cpu_cores' => $this->faker->randomElement([2, 4, 8]),
            'memory_mb' => $this->faker->randomElement([2048, 4096, 8192]),
            'disk_gb' => $this->faker->randomElement([50, 100, 200]),
            'site_count' => 0,
            'max_sites' => 50,
            'ssh_user' => 'root',
            'ssh_port' => 22,
            'created_at' => now(),
            'updated_at' => now(),
        ];
    }

    public function inactive(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'inactive',
        ]);
    }

    public function unhealthy(): static
    {
        return $this->state(fn (array $attributes) => [
            'health_status' => 'unhealthy',
        ]);
    }

    public function maintenance(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'maintenance',
        ]);
    }
}
