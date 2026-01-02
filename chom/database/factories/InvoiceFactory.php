<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Models\Invoice;
use App\Models\Organization;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * Invoice Factory
 *
 * Generates realistic invoice test data for Laravel testing and seeding.
 *
 * Design Pattern: Factory Pattern
 * - Encapsulates test data generation logic
 * - Provides fluent state methods for different invoice scenarios
 * - Ensures consistent, valid invoice data across tests
 *
 * States:
 * - paid(): Invoice with paid status and payment timestamp
 * - pending(): Invoice with pending/open status
 * - overdue(): Invoice with open status and past due date
 *
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\Invoice>
 */
class InvoiceFactory extends Factory
{
    protected $model = Invoice::class;

    /**
     * Define the model's default state.
     *
     * Generates realistic invoice data with:
     * - Unique invoice identifiers (Stripe format)
     * - Random amounts between $10-$500 (stored as cents)
     * - Billing periods (monthly intervals)
     * - Random status (paid/open)
     * - Appropriate payment timestamps for paid invoices
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $status = fake()->randomElement(['paid', 'open']);
        $amountCents = fake()->numberBetween(1000, 50000); // $10.00 to $500.00
        $periodStart = fake()->dateTimeBetween('-60 days', '-30 days');
        $periodEnd = (clone $periodStart)->modify('+30 days');

        return [
            'organization_id' => Organization::factory(),
            'stripe_invoice_id' => 'in_'.Str::random(24), // Stripe invoice ID format
            'amount_cents' => $amountCents,
            'currency' => 'usd',
            'status' => $status,
            'paid_at' => $status === 'paid' ? fake()->dateTimeBetween($periodStart, 'now') : null,
            'period_start' => $periodStart,
            'period_end' => $periodEnd,
        ];
    }

    /**
     * Indicate that the invoice has been paid.
     *
     * State: Paid Invoice
     * - Status set to 'paid'
     * - Includes payment timestamp
     * - Payment date is after period start
     *
     * @return static
     */
    public function paid(): static
    {
        return $this->state(function (array $attributes) {
            $periodStart = $attributes['period_start'] ?? fake()->dateTimeBetween('-60 days', '-30 days');

            return [
                'status' => 'paid',
                'paid_at' => fake()->dateTimeBetween($periodStart, 'now'),
            ];
        });
    }

    /**
     * Indicate that the invoice is pending payment.
     *
     * State: Pending Invoice
     * - Status set to 'open'
     * - No payment timestamp
     * - Due date in the future
     *
     * @return static
     */
    public function pending(): static
    {
        return $this->state(function (array $attributes) {
            return [
                'status' => 'open',
                'paid_at' => null,
                'period_end' => fake()->dateTimeBetween('now', '+30 days'),
            ];
        });
    }

    /**
     * Indicate that the invoice is overdue.
     *
     * State: Overdue Invoice
     * - Status set to 'open'
     * - No payment timestamp
     * - Period end date in the past (invoice is overdue)
     *
     * @return static
     */
    public function overdue(): static
    {
        return $this->state(function (array $attributes) {
            return [
                'status' => 'open',
                'paid_at' => null,
                'period_start' => fake()->dateTimeBetween('-90 days', '-60 days'),
                'period_end' => fake()->dateTimeBetween('-30 days', '-1 days'),
            ];
        });
    }

    /**
     * Set a specific amount for the invoice.
     *
     * Helper method to create invoices with exact amounts.
     *
     * @param  float  $amount  Amount in dollars (converted to cents)
     * @return static
     */
    public function withAmount(float $amount): static
    {
        return $this->state(fn (array $attributes) => [
            'amount_cents' => (int) ($amount * 100),
        ]);
    }

    /**
     * Create invoice without Stripe integration.
     *
     * State: Manual Invoice
     * - No Stripe invoice ID
     * - Useful for testing non-Stripe billing scenarios
     *
     * @return static
     */
    public function withoutStripeInvoice(): static
    {
        return $this->state(fn (array $attributes) => [
            'stripe_invoice_id' => null,
        ]);
    }

    /**
     * Set specific currency.
     *
     * @param  string  $currency  Currency code (usd, eur, gbp, etc.)
     * @return static
     */
    public function withCurrency(string $currency): static
    {
        return $this->state(fn (array $attributes) => [
            'currency' => $currency,
        ]);
    }

    /**
     * Create invoice for current billing period.
     *
     * State: Current Period Invoice
     * - Period start is 30 days ago
     * - Period end is today
     * - Useful for testing current subscription billing
     *
     * @return static
     */
    public function forCurrentPeriod(): static
    {
        return $this->state(fn (array $attributes) => [
            'period_start' => now()->subDays(30),
            'period_end' => now(),
        ]);
    }
}
