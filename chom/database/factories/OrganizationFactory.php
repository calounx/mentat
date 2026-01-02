<?php

namespace Database\Factories;

use App\Models\Organization;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\Organization>
 */
class OrganizationFactory extends Factory
{
    protected $model = Organization::class;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $name = fake()->company();

        return [
            'name' => $name,
            'slug' => Str::slug($name).'-'.Str::random(6),
            'billing_email' => fake()->unique()->companyEmail(),
            'stripe_customer_id' => 'cus_'.Str::random(14),
        ];
    }

    /**
     * Configure the model factory.
     */
    public function configure(): static
    {
        return $this->afterCreating(function (Organization $organization) {
            // Create default tenant for the organization if it doesn't exist
            if ($organization->tenants()->count() === 0) {
                $tenant = Tenant::factory()->create([
                    'organization_id' => $organization->id,
                ]);

                // Set the default tenant
                $organization->update(['default_tenant_id' => $tenant->id]);
            }
        });
    }

    /**
     * Indicate that the organization has no Stripe customer.
     */
    public function withoutStripeCustomer(): static
    {
        return $this->state(fn (array $attributes) => [
            'stripe_customer_id' => null,
        ]);
    }

    /**
     * Set a specific Stripe customer ID.
     */
    public function withStripeCustomer(string $customerId): static
    {
        return $this->state(fn (array $attributes) => [
            'stripe_customer_id' => $customerId,
        ]);
    }
}
