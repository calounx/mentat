<?php

namespace Database\Factories;

use App\Models\Organization;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\Tenant>
 */
class TenantFactory extends Factory
{
    protected $model = Tenant::class;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'organization_id' => Organization::factory(),
            'name' => fake()->words(2, true),
            'slug' => Str::slug(fake()->words(2, true)).'-'.Str::random(4),
            'tier' => 'starter',
            'status' => 'active',
            'settings' => [],
            'metrics_retention_days' => 30,
        ];
    }

    /**
     * Set the tenant tier.
     */
    public function tier(string $tier): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => $tier,
        ]);
    }

    /**
     * Set the tenant status.
     */
    public function status(string $status): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => $status,
        ]);
    }

    /**
     * Make the tenant suspended.
     */
    public function suspended(): static
    {
        return $this->status('suspended');
    }

    /**
     * Make the tenant active.
     */
    public function active(): static
    {
        return $this->status('active');
    }
}
