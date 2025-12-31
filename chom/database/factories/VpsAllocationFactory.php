<?php

namespace Database\Factories;

use App\Models\Tenant;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;

class VpsAllocationFactory extends Factory
{
    protected $model = VpsAllocation::class;

    public function definition(): array
    {
        return [
            'vps_id' => VpsServer::factory(),
            'tenant_id' => Tenant::factory(),
            'sites_allocated' => $this->faker->numberBetween(0, 10),
            'storage_mb_allocated' => $this->faker->numberBetween(1000, 50000),
            'memory_mb_allocated' => $this->faker->numberBetween(512, 4096),
        ];
    }

    /**
     * Indicate minimal allocation.
     */
    public function minimal(): static
    {
        return $this->state(fn (array $attributes) => [
            'sites_allocated' => 0,
            'storage_mb_allocated' => 1000,
            'memory_mb_allocated' => 512,
        ]);
    }

    /**
     * Indicate full allocation.
     */
    public function full(): static
    {
        return $this->state(fn (array $attributes) => [
            'sites_allocated' => 10,
            'storage_mb_allocated' => 50000,
            'memory_mb_allocated' => 4096,
        ]);
    }
}
