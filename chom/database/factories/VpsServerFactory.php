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
        $providers = ['digitalocean', 'linode', 'vultr', 'hetzner'];
        $regions = ['nyc1', 'nyc3', 'sfo3', 'lon1', 'fra1', 'tor1'];
        $hostname = $this->faker->domainWord() . '-' . Str::random(4);

        return [
            'hostname' => $hostname . '.example.com',
            'ip_address' => $this->faker->ipv4(),
            'provider' => $this->faker->randomElement($providers),
            'provider_id' => Str::random(16),
            'region' => $this->faker->randomElement($regions),
            'spec_cpu' => $this->faker->numberBetween(1, 8),
            'spec_memory_mb' => $this->faker->randomElement([1024, 2048, 4096, 8192, 16384]),
            'spec_disk_gb' => $this->faker->randomElement([25, 50, 80, 160, 320]),
            'status' => 'active',
            'allocation_type' => 'shared',
            'vpsmanager_version' => '2.0.0',
            'observability_configured' => true,
            'ssh_key_id' => null,
            'ssh_user' => 'root',
            'ssh_port' => 22,
            'last_health_check_at' => now(),
            'health_status' => 'healthy',
            'health_error' => null,
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
