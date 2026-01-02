<?php

namespace Tests\Regression;

use App\Models\Invoice;
use App\Models\Organization;
use App\Models\Subscription;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class BillingSubscriptionRegressionTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function organization_can_have_subscription(): void
    {
        $organization = Organization::factory()->create();
        $subscription = Subscription::factory()->create([
            'organization_id' => $organization->id,
            'tier' => 'pro',
            'status' => 'active',
        ]);

        $this->assertInstanceOf(Subscription::class, $organization->subscription);
        $this->assertEquals('pro', $organization->subscription->tier);
    }

    #[Test]
    public function subscription_has_different_tiers(): void
    {
        $starter = Subscription::factory()->create(['tier' => 'starter']);
        $pro = Subscription::factory()->create(['tier' => 'pro']);
        $enterprise = Subscription::factory()->create(['tier' => 'enterprise']);

        $this->assertEquals('starter', $starter->tier);
        $this->assertEquals('pro', $pro->tier);
        $this->assertEquals('enterprise', $enterprise->tier);
    }

    #[Test]
    public function subscription_has_different_statuses(): void
    {
        $active = Subscription::factory()->create(['status' => 'active']);
        $trialing = Subscription::factory()->create(['status' => 'trialing']);
        $canceled = Subscription::factory()->create(['status' => 'canceled']);
        $pastDue = Subscription::factory()->create(['status' => 'past_due']);

        $this->assertEquals('active', $active->status);
        $this->assertEquals('trialing', $trialing->status);
        $this->assertEquals('canceled', $canceled->status);
        $this->assertEquals('past_due', $pastDue->status);
    }

    #[Test]
    public function organization_can_check_active_subscription(): void
    {
        $organization = Organization::factory()->create();

        // No subscription
        $this->assertFalse($organization->hasActiveSubscription());

        // Active subscription
        Subscription::factory()->create([
            'organization_id' => $organization->id,
            'status' => 'active',
        ]);

        $organization->refresh();
        $this->assertTrue($organization->hasActiveSubscription());
    }

    #[Test]
    public function trialing_subscription_is_considered_active(): void
    {
        $organization = Organization::factory()->create();

        Subscription::factory()->create([
            'organization_id' => $organization->id,
            'status' => 'trialing',
        ]);

        $organization->refresh();
        $this->assertTrue($organization->hasActiveSubscription());
    }

    #[Test]
    public function canceled_subscription_is_not_active(): void
    {
        $organization = Organization::factory()->create();

        Subscription::factory()->create([
            'organization_id' => $organization->id,
            'status' => 'canceled',
        ]);

        $organization->refresh();
        $this->assertFalse($organization->hasActiveSubscription());
    }

    #[Test]
    public function subscription_tracks_stripe_subscription_id(): void
    {
        $subscription = Subscription::factory()->create([
            'stripe_subscription_id' => 'sub_test123456',
        ]);

        $this->assertEquals('sub_test123456', $subscription->stripe_subscription_id);
    }

    #[Test]
    public function subscription_has_trial_period(): void
    {
        $subscription = Subscription::factory()->create([
            'trial_ends_at' => now()->addDays(14),
        ]);

        $this->assertNotNull($subscription->trial_ends_at);
        $this->assertTrue($subscription->trial_ends_at->isFuture());
    }

    #[Test]
    public function invoice_belongs_to_organization(): void
    {
        $organization = Organization::factory()->create();
        $invoice = Invoice::factory()->create([
            'organization_id' => $organization->id,
        ]);

        $this->assertEquals($organization->id, $invoice->organization_id);
        $this->assertInstanceOf(Organization::class, $invoice->organization);
    }

    #[Test]
    public function invoice_tracks_amount_in_cents(): void
    {
        $invoice = Invoice::factory()->create([
            'amount_cents' => 9900, // $99.00
            'currency' => 'usd',
        ]);

        $this->assertEquals(9900, $invoice->amount_cents);
        $this->assertEquals(99.00, $invoice->getAmountInDollars());
    }

    #[Test]
    public function invoice_formats_amount_with_currency(): void
    {
        $usd = Invoice::factory()->create([
            'amount_cents' => 9900,
            'currency' => 'usd',
        ]);

        $eur = Invoice::factory()->eur()->create([
            'amount_cents' => 9900,
        ]);

        $gbp = Invoice::factory()->gbp()->create([
            'amount_cents' => 9900,
        ]);

        $this->assertEquals('$99.00', $usd->getFormattedAmount());
        $this->assertEquals('€99.00', $eur->getFormattedAmount());
        $this->assertEquals('£99.00', $gbp->getFormattedAmount());
    }

    #[Test]
    public function invoice_has_different_statuses(): void
    {
        $paid = Invoice::factory()->create(['status' => 'paid']);
        $open = Invoice::factory()->unpaid()->create();
        $void = Invoice::factory()->void()->create();

        $this->assertTrue($paid->isPaid());
        $this->assertTrue($open->isOpen());
        $this->assertEquals('void', $void->status);
    }

    #[Test]
    public function invoice_tracks_payment_date(): void
    {
        $paid = Invoice::factory()->create([
            'status' => 'paid',
            'paid_at' => now(),
        ]);

        $unpaid = Invoice::factory()->unpaid()->create();

        $this->assertNotNull($paid->paid_at);
        $this->assertNull($unpaid->paid_at);
    }

    #[Test]
    public function invoice_has_billing_period(): void
    {
        $invoice = Invoice::factory()->create([
            'period_start' => now()->startOfMonth(),
            'period_end' => now()->endOfMonth(),
        ]);

        $this->assertNotNull($invoice->period_start);
        $this->assertNotNull($invoice->period_end);
        $this->assertTrue($invoice->period_end->greaterThan($invoice->period_start));
    }

    #[Test]
    public function invoice_tracks_stripe_invoice_id(): void
    {
        $invoice = Invoice::factory()->create([
            'stripe_invoice_id' => 'in_test123456',
        ]);

        $this->assertEquals('in_test123456', $invoice->stripe_invoice_id);
    }

    #[Test]
    public function organization_can_have_multiple_invoices(): void
    {
        $organization = Organization::factory()->create();

        Invoice::factory(5)->create([
            'organization_id' => $organization->id,
        ]);

        $this->assertEquals(5, $organization->invoices()->count());
    }

    #[Test]
    public function organization_uses_billing_email_for_stripe(): void
    {
        $organization = Organization::factory()->create([
            'billing_email' => 'billing@company.com',
        ]);

        $this->assertEquals('billing@company.com', $organization->stripeEmail());
    }

    #[Test]
    public function organization_can_determine_current_tier(): void
    {
        $organization = Organization::factory()->create();

        // Default tier without subscription
        $this->assertEquals('starter', $organization->getCurrentTier());

        // Tier from subscription
        Subscription::factory()->create([
            'organization_id' => $organization->id,
            'tier' => 'enterprise',
        ]);

        $organization->refresh();
        $this->assertEquals('enterprise', $organization->getCurrentTier());
    }

    #[Test]
    public function subscription_can_be_upgraded(): void
    {
        $subscription = Subscription::factory()->create([
            'tier' => 'starter',
            'status' => 'active',
        ]);

        $subscription->update(['tier' => 'pro']);

        $this->assertEquals('pro', $subscription->tier);
    }

    #[Test]
    public function subscription_can_be_downgraded(): void
    {
        $subscription = Subscription::factory()->create([
            'tier' => 'enterprise',
            'status' => 'active',
        ]);

        $subscription->update(['tier' => 'pro']);

        $this->assertEquals('pro', $subscription->tier);
    }

    #[Test]
    public function subscription_can_be_canceled(): void
    {
        $subscription = Subscription::factory()->create([
            'status' => 'active',
        ]);

        $subscription->update([
            'status' => 'canceled',
            'canceled_at' => now(),
        ]);

        $this->assertEquals('canceled', $subscription->status);
        $this->assertNotNull($subscription->canceled_at);
    }

    #[Test]
    public function subscription_tracks_cancellation_date(): void
    {
        $subscription = Subscription::factory()->create([
            'status' => 'canceled',
            'canceled_at' => now(),
        ]);

        $this->assertNotNull($subscription->canceled_at);
        $this->assertTrue($subscription->canceled_at->isToday());
    }
}
