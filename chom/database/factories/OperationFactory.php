<?php

namespace Database\Factories;

use App\Models\Operation;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class OperationFactory extends Factory
{
    protected $model = Operation::class;

    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'user_id' => User::factory(),
            'operation_type' => $this->faker->randomElement([
                'site_create',
                'site_delete',
                'site_update',
                'ssl_issue',
                'backup_create',
            ]),
            'target_type' => 'App\\Models\\Site',
            'target_id' => $this->faker->uuid(),
            'status' => $this->faker->randomElement(['pending', 'running', 'completed', 'failed']),
            'input_data' => [],
            'output_data' => [],
            'error_message' => null,
            'started_at' => null,
            'completed_at' => null,
        ];
    }

    /**
     * Indicate that the operation is pending.
     */
    public function pending(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'pending',
            'started_at' => null,
            'completed_at' => null,
        ]);
    }

    /**
     * Indicate that the operation is running.
     */
    public function running(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'running',
            'started_at' => now()->subMinutes($this->faker->numberBetween(1, 30)),
            'completed_at' => null,
        ]);
    }

    /**
     * Indicate that the operation is completed.
     */
    public function completed(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'completed',
            'started_at' => now()->subHour(),
            'completed_at' => now()->subMinutes(30),
        ]);
    }

    /**
     * Indicate that the operation has failed.
     */
    public function failed(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'failed',
            'error_message' => 'Operation failed: ' . $this->faker->sentence(),
            'started_at' => now()->subHour(),
            'completed_at' => now()->subMinutes(30),
        ]);
    }
}
