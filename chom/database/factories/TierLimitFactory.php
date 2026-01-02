<?php

namespace Database\Factories;

use App\Models\TierLimit;
use Illuminate\Database\Eloquent\Factories\Factory;

class TierLimitFactory extends Factory
{
    protected $model = TierLimit::class;

    public function definition(): array
    {
        return [
            'tier' => 'starter',
            'name' => 'Starter',
            'max_sites' => 5,
            'max_storage_gb' => 10,
            'max_bandwidth_gb' => 100,
            'backup_retention_days' => 7,
            'support_level' => 'email',
            'dedicated_ip' => false,
            'staging_environments' => false,
            'white_label' => false,
            'api_rate_limit_per_hour' => 100,
            'price_monthly_cents' => 999,
        ];
    }

    public function professional(): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => 'professional',
            'name' => 'Professional',
            'max_sites' => 25,
            'max_storage_gb' => 50,
            'max_bandwidth_gb' => 500,
            'backup_retention_days' => 30,
            'support_level' => 'priority',
            'dedicated_ip' => false,
            'staging_environments' => true,
            'white_label' => false,
            'api_rate_limit_per_hour' => 500,
            'price_monthly_cents' => 4999,
        ]);
    }

    public function enterprise(): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => 'enterprise',
            'name' => 'Enterprise',
            'max_sites' => -1, // unlimited
            'max_storage_gb' => -1,
            'max_bandwidth_gb' => -1,
            'backup_retention_days' => 90,
            'support_level' => '24/7',
            'dedicated_ip' => true,
            'staging_environments' => true,
            'white_label' => true,
            'api_rate_limit_per_hour' => -1,
            'price_monthly_cents' => 29999,
        ]);
    }
}
