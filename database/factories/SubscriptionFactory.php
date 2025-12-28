<?php

namespace Database\Factories;

use App\Models\Organization;
use App\Models\Subscription;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\Subscription>
 */
class SubscriptionFactory extends Factory
{
    protected $model = Subscription::class;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'organization_id' => Organization::factory(),
            'stripe_subscription_id' => 'sub_'.Str::random(14),
            'stripe_price_id' => 'price_'.Str::random(14),
            'tier' => 'starter',
            'status' => 'active',
            'trial_ends_at' => null,
            'current_period_start' => now(),
            'current_period_end' => now()->addMonth(),
            'cancelled_at' => null,
        ];
    }

    /**
     * Set the subscription tier.
     */
    public function tier(string $tier): static
    {
        return $this->state(fn (array $attributes) => [
            'tier' => $tier,
        ]);
    }

    /**
     * Set the subscription status.
     */
    public function status(string $status): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => $status,
        ]);
    }

    /**
     * Make the subscription on trial.
     */
    public function onTrial(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'trialing',
            'trial_ends_at' => now()->addDays(14),
        ]);
    }

    /**
     * Make the subscription cancelled.
     */
    public function cancelled(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'cancelled',
            'cancelled_at' => now(),
        ]);
    }

    /**
     * Make the subscription past due.
     */
    public function pastDue(): static
    {
        return $this->status('past_due');
    }
}
