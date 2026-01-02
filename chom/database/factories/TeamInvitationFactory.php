<?php

namespace Database\Factories;

use App\Models\Organization;
use App\Models\TeamInvitation;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class TeamInvitationFactory extends Factory
{
    protected $model = TeamInvitation::class;

    public function definition(): array
    {
        return [
            'organization_id' => Organization::factory(),
            'invited_by' => User::factory(),
            'email' => fake()->unique()->safeEmail(),
            'name' => fake()->name(),
            'role' => fake()->randomElement(['admin', 'member', 'viewer']),
            'token' => Str::random(64),
            'status' => 'pending',
            'expires_at' => now()->addDays(7),
            'accepted_at' => null,
        ];
    }

    /**
     * Indicate that the invitation is accepted.
     */
    public function accepted(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'accepted',
            'accepted_at' => now(),
        ]);
    }

    /**
     * Indicate that the invitation is expired.
     */
    public function expired(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'pending',
            'expires_at' => now()->subDay(),
            'accepted_at' => null,
        ]);
    }

    /**
     * Indicate that the invitation is cancelled.
     */
    public function cancelled(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'cancelled',
        ]);
    }
}
