<?php

namespace Database\Factories;

use App\Models\Tenant;
use App\Models\UsageRecord;
use Illuminate\Database\Eloquent\Factories\Factory;

class UsageRecordFactory extends Factory
{
    protected $model = UsageRecord::class;

    public function definition(): array
    {
        $start = $this->faker->dateTimeBetween('-30 days', '-1 day');
        $end = (clone $start)->modify('+1 day');

        return [
            'tenant_id' => Tenant::factory(),
            'metric_type' => $this->faker->randomElement(['bandwidth', 'storage', 'compute', 'backups']),
            'quantity' => $this->faker->randomFloat(2, 1, 1000),
            'unit_price' => $this->faker->randomFloat(4, 0.0001, 0.1),
            'period_start' => $start,
            'period_end' => $end,
            'stripe_usage_record_id' => null,
        ];
    }

    /**
     * Indicate bandwidth usage.
     */
    public function bandwidth(): static
    {
        return $this->state(fn (array $attributes) => [
            'metric_type' => 'bandwidth',
            'quantity' => $this->faker->randomFloat(2, 1, 1000),
            'unit_price' => 0.01,
        ]);
    }

    /**
     * Indicate storage usage.
     */
    public function storage(): static
    {
        return $this->state(fn (array $attributes) => [
            'metric_type' => 'storage',
            'quantity' => $this->faker->randomFloat(2, 1, 500),
            'unit_price' => 0.001,
        ]);
    }

    /**
     * Indicate current month usage.
     */
    public function currentMonth(): static
    {
        return $this->state(fn (array $attributes) => [
            'period_start' => now()->startOfMonth(),
            'period_end' => now()->endOfMonth(),
        ]);
    }
}
