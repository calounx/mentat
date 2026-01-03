<?php

namespace Database\Factories;

use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class TenantFactory extends Factory
{
    protected $model = Tenant::class;

    public function definition(): array
    {
        return [
            'id' => Str::uuid()->toString(),
            'name' => $this->faker->company(),
            'tier' => $this->faker->randomElement(['free', 'starter', 'professional', 'enterprise']),
            'status' => 'active',
            'settings' => [],
            'created_at' => now(),
            'updated_at' => now(),
        ];
    }

    public function free(): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => 'free',
        ]);
    }

    public function professional(): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => 'professional',
        ]);
    }

    public function enterprise(): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => 'enterprise',
        ]);
    }

    public function suspended(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'suspended',
        ]);
    }
}
