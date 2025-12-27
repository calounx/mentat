<?php

namespace Tests\Feature;

use App\Models\Invoice;
use App\Models\Organization;
use App\Models\Subscription;
use App\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Tests\TestCase;

class StripeWebhookTest extends TestCase
{
    use RefreshDatabase;

    protected Organization $organization;

    protected Tenant $tenant;

    protected string $stripeCustomerId = 'cus_test123456789';

    protected function setUp(): void
    {
        parent::setUp();

        // Disable webhook signature verification for testing
        Config::set('cashier.webhook.secret', null);

        // Create organization with Stripe customer ID
        $this->organization = Organization::factory()
            ->withStripeCustomer($this->stripeCustomerId)
            ->create();

        // Create tenant for the organization
        $this->tenant = Tenant::factory()
            ->for($this->organization)
            ->active()
            ->create();
    }

    protected function postWebhook(string $eventType, array $object): \Illuminate\Testing\TestResponse
    {
        return $this->postJson('/stripe/webhook', [
            'id' => 'evt_'.uniqid(),
            'type' => $eventType,
            'data' => [
                'object' => $object,
            ],
        ]);
    }

    protected function createSubscriptionPayload(array $overrides = []): array
    {
        return array_merge([
            'id' => 'sub_'.uniqid(),
            'customer' => $this->stripeCustomerId,
            'status' => 'active',
            'items' => [
                'data' => [
                    [
                        'price' => [
                            'id' => 'price_starter_test',
                        ],
                    ],
                ],
            ],
            'trial_end' => null,
            'current_period_start' => now()->timestamp,
            'current_period_end' => now()->addMonth()->timestamp,
            'canceled_at' => null,
        ], $overrides);
    }

    protected function createInvoicePayload(array $overrides = []): array
    {
        return array_merge([
            'id' => 'in_'.uniqid(),
            'customer' => $this->stripeCustomerId,
            'amount_paid' => 2900,
            'amount_due' => 2900,
            'currency' => 'usd',
            'status' => 'paid',
            'period_start' => now()->timestamp,
            'period_end' => now()->addMonth()->timestamp,
            'attempt_count' => 1,
        ], $overrides);
    }

    // ==========================================
    // Subscription Created Tests
    // ==========================================

    public function test_subscription_created_creates_subscription_record(): void
    {
        $payload = $this->createSubscriptionPayload();

        $response = $this->postWebhook('customer.subscription.created', $payload);

        $response->assertStatus(200);

        $this->assertDatabaseHas('subscriptions', [
            'organization_id' => $this->organization->id,
            'stripe_subscription_id' => $payload['id'],
            'status' => 'active',
        ]);
    }

    public function test_subscription_created_updates_tenant_tier(): void
    {
        Config::set('chom.tiers.pro.stripe_price_id', 'price_pro_test');

        $payload = $this->createSubscriptionPayload([
            'items' => [
                'data' => [
                    ['price' => ['id' => 'price_pro_test']],
                ],
            ],
        ]);

        $this->postWebhook('customer.subscription.created', $payload);

        $this->tenant->refresh();
        $this->assertEquals('pro', $this->tenant->tier);
    }

    public function test_subscription_created_creates_audit_log(): void
    {
        $payload = $this->createSubscriptionPayload();

        $this->postWebhook('customer.subscription.created', $payload);

        $this->assertDatabaseHas('audit_logs', [
            'organization_id' => $this->organization->id,
            'action' => 'subscription.created',
            'resource_type' => 'subscription',
        ]);
    }

    public function test_subscription_created_handles_trial(): void
    {
        $trialEnd = now()->addDays(14)->timestamp;
        $payload = $this->createSubscriptionPayload([
            'status' => 'trialing',
            'trial_end' => $trialEnd,
        ]);

        $this->postWebhook('customer.subscription.created', $payload);

        $subscription = Subscription::where('organization_id', $this->organization->id)->first();
        $this->assertEquals('trialing', $subscription->status);
        $this->assertNotNull($subscription->trial_ends_at);
    }

    public function test_subscription_created_ignores_unknown_customer(): void
    {
        $payload = $this->createSubscriptionPayload([
            'customer' => 'cus_unknown',
        ]);

        $response = $this->postWebhook('customer.subscription.created', $payload);

        $response->assertStatus(200);
        $this->assertDatabaseMissing('subscriptions', [
            'stripe_subscription_id' => $payload['id'],
        ]);
    }

    // ==========================================
    // Subscription Updated Tests
    // ==========================================

    public function test_subscription_updated_updates_existing_subscription(): void
    {
        $subscription = Subscription::factory()
            ->for($this->organization)
            ->tier('starter')
            ->create();

        Config::set('chom.tiers.pro.stripe_price_id', 'price_pro_test');

        $payload = $this->createSubscriptionPayload([
            'id' => $subscription->stripe_subscription_id,
            'items' => [
                'data' => [
                    ['price' => ['id' => 'price_pro_test']],
                ],
            ],
        ]);

        $this->postWebhook('customer.subscription.updated', $payload);

        $subscription->refresh();
        $this->assertEquals('pro', $subscription->tier);
    }

    public function test_subscription_updated_creates_subscription_if_not_exists(): void
    {
        $payload = $this->createSubscriptionPayload();

        $response = $this->postWebhook('customer.subscription.updated', $payload);

        $response->assertStatus(200);
        $this->assertDatabaseHas('subscriptions', [
            'organization_id' => $this->organization->id,
            'stripe_subscription_id' => $payload['id'],
        ]);
    }

    public function test_subscription_updated_handles_tier_change(): void
    {
        Config::set('chom.tiers.starter.stripe_price_id', 'price_starter_test');
        Config::set('chom.tiers.enterprise.stripe_price_id', 'price_enterprise_test');

        Subscription::factory()
            ->for($this->organization)
            ->tier('starter')
            ->create();

        $payload = $this->createSubscriptionPayload([
            'items' => [
                'data' => [
                    ['price' => ['id' => 'price_enterprise_test']],
                ],
            ],
        ]);

        $this->postWebhook('customer.subscription.updated', $payload);

        $this->tenant->refresh();
        $this->assertEquals('enterprise', $this->tenant->tier);

        $this->assertDatabaseHas('audit_logs', [
            'action' => 'subscription.updated',
        ]);
    }

    public function test_subscription_updated_reactivates_tenants_when_active(): void
    {
        $this->tenant->update(['status' => 'suspended']);

        Subscription::factory()
            ->for($this->organization)
            ->status('past_due')
            ->create();

        $payload = $this->createSubscriptionPayload([
            'status' => 'active',
        ]);

        $this->postWebhook('customer.subscription.updated', $payload);

        $this->tenant->refresh();
        $this->assertEquals('active', $this->tenant->status);
    }

    public function test_subscription_updated_suspends_tenants_when_cancelled(): void
    {
        Subscription::factory()
            ->for($this->organization)
            ->status('active')
            ->create();

        $payload = $this->createSubscriptionPayload([
            'status' => 'canceled',
        ]);

        $this->postWebhook('customer.subscription.updated', $payload);

        $this->tenant->refresh();
        $this->assertEquals('suspended', $this->tenant->status);
    }

    public function test_subscription_updated_handles_cancellation(): void
    {
        Subscription::factory()
            ->for($this->organization)
            ->status('active')
            ->create();

        $cancelledAt = now()->timestamp;
        $payload = $this->createSubscriptionPayload([
            'status' => 'canceled',
            'canceled_at' => $cancelledAt,
        ]);

        $this->postWebhook('customer.subscription.updated', $payload);

        $subscription = Subscription::where('organization_id', $this->organization->id)->first();
        $this->assertEquals('cancelled', $subscription->status);
        $this->assertNotNull($subscription->cancelled_at);

        $this->tenant->refresh();
        $this->assertEquals('suspended', $this->tenant->status);
    }

    // ==========================================
    // Subscription Deleted Tests
    // ==========================================

    public function test_subscription_deleted_cancels_subscription(): void
    {
        $subscription = Subscription::factory()
            ->for($this->organization)
            ->status('active')
            ->create();

        $payload = $this->createSubscriptionPayload([
            'id' => $subscription->stripe_subscription_id,
        ]);

        $this->postWebhook('customer.subscription.deleted', $payload);

        $subscription->refresh();
        $this->assertEquals('cancelled', $subscription->status);
        $this->assertNotNull($subscription->cancelled_at);
    }

    public function test_subscription_deleted_suspends_all_tenants(): void
    {
        $tenant2 = Tenant::factory()
            ->for($this->organization)
            ->active()
            ->create();

        Subscription::factory()
            ->for($this->organization)
            ->create();

        $payload = $this->createSubscriptionPayload();

        $this->postWebhook('customer.subscription.deleted', $payload);

        $this->tenant->refresh();
        $tenant2->refresh();

        $this->assertEquals('suspended', $this->tenant->status);
        $this->assertEquals('suspended', $tenant2->status);
    }

    public function test_subscription_deleted_creates_audit_log(): void
    {
        Subscription::factory()
            ->for($this->organization)
            ->create();

        $payload = $this->createSubscriptionPayload();

        $this->postWebhook('customer.subscription.deleted', $payload);

        $this->assertDatabaseHas('audit_logs', [
            'organization_id' => $this->organization->id,
            'action' => 'subscription.cancelled',
        ]);
    }

    // ==========================================
    // Invoice Paid Tests
    // ==========================================

    public function test_invoice_paid_creates_invoice_record(): void
    {
        $payload = $this->createInvoicePayload();

        $response = $this->postWebhook('invoice.paid', $payload);

        $response->assertStatus(200);

        $this->assertDatabaseHas('invoices', [
            'organization_id' => $this->organization->id,
            'stripe_invoice_id' => $payload['id'],
            'status' => 'paid',
            'amount_cents' => 2900,
            'currency' => 'usd',
        ]);
    }

    public function test_invoice_paid_reactivates_suspended_tenants(): void
    {
        $this->tenant->update(['status' => 'suspended']);

        $payload = $this->createInvoicePayload();

        $this->postWebhook('invoice.paid', $payload);

        $this->tenant->refresh();
        $this->assertEquals('active', $this->tenant->status);
    }

    public function test_invoice_paid_updates_existing_invoice(): void
    {
        $invoice = Invoice::create([
            'organization_id' => $this->organization->id,
            'stripe_invoice_id' => 'in_existing',
            'amount_cents' => 2900,
            'currency' => 'usd',
            'status' => 'open',
        ]);

        $payload = $this->createInvoicePayload([
            'id' => 'in_existing',
        ]);

        $this->postWebhook('invoice.paid', $payload);

        $invoice->refresh();
        $this->assertEquals('paid', $invoice->status);
        $this->assertNotNull($invoice->paid_at);
    }

    public function test_invoice_paid_creates_audit_log(): void
    {
        $payload = $this->createInvoicePayload();

        $this->postWebhook('invoice.paid', $payload);

        $this->assertDatabaseHas('audit_logs', [
            'organization_id' => $this->organization->id,
            'action' => 'invoice.paid',
            'resource_type' => 'invoice',
        ]);
    }

    // ==========================================
    // Invoice Payment Failed Tests
    // ==========================================

    public function test_invoice_payment_failed_creates_failed_invoice(): void
    {
        $payload = $this->createInvoicePayload([
            'status' => 'open',
            'attempt_count' => 1,
        ]);

        $response = $this->postWebhook('invoice.payment_failed', $payload);

        $response->assertStatus(200);

        $this->assertDatabaseHas('invoices', [
            'organization_id' => $this->organization->id,
            'stripe_invoice_id' => $payload['id'],
            'status' => 'payment_failed',
        ]);
    }

    public function test_invoice_payment_failed_suspends_tenant_after_three_attempts(): void
    {
        Subscription::factory()
            ->for($this->organization)
            ->status('active')
            ->create();

        $payload = $this->createInvoicePayload([
            'attempt_count' => 3,
        ]);

        $this->postWebhook('invoice.payment_failed', $payload);

        $this->tenant->refresh();
        $this->assertEquals('suspended', $this->tenant->status);
    }

    public function test_invoice_payment_failed_updates_subscription_to_past_due(): void
    {
        $subscription = Subscription::factory()
            ->for($this->organization)
            ->status('active')
            ->create();

        $payload = $this->createInvoicePayload([
            'attempt_count' => 3,
        ]);

        $this->postWebhook('invoice.payment_failed', $payload);

        $subscription->refresh();
        $this->assertEquals('past_due', $subscription->status);
    }

    public function test_invoice_payment_failed_does_not_suspend_on_first_attempt(): void
    {
        $payload = $this->createInvoicePayload([
            'attempt_count' => 1,
        ]);

        $this->postWebhook('invoice.payment_failed', $payload);

        $this->tenant->refresh();
        $this->assertEquals('active', $this->tenant->status);
    }

    public function test_invoice_payment_failed_creates_audit_log(): void
    {
        $payload = $this->createInvoicePayload([
            'attempt_count' => 2,
        ]);

        $this->postWebhook('invoice.payment_failed', $payload);

        $this->assertDatabaseHas('audit_logs', [
            'organization_id' => $this->organization->id,
            'action' => 'invoice.payment_failed',
        ]);
    }

    // ==========================================
    // Invoice Finalized Tests
    // ==========================================

    public function test_invoice_finalized_creates_open_invoice(): void
    {
        $payload = $this->createInvoicePayload([
            'status' => 'open',
        ]);

        $response = $this->postWebhook('invoice.finalized', $payload);

        $response->assertStatus(200);

        $this->assertDatabaseHas('invoices', [
            'organization_id' => $this->organization->id,
            'stripe_invoice_id' => $payload['id'],
            'status' => 'open',
        ]);
    }

    // ==========================================
    // Customer Updated Tests
    // ==========================================

    public function test_customer_updated_syncs_billing_email(): void
    {
        $newEmail = 'new-billing@example.com';

        $response = $this->postWebhook('customer.updated', [
            'id' => $this->stripeCustomerId,
            'email' => $newEmail,
        ]);

        $response->assertStatus(200);

        $this->organization->refresh();
        $this->assertEquals($newEmail, $this->organization->billing_email);
    }

    public function test_customer_updated_ignores_unknown_customer(): void
    {
        $originalEmail = $this->organization->billing_email;

        $this->postWebhook('customer.updated', [
            'id' => 'cus_unknown',
            'email' => 'different@example.com',
        ]);

        $this->organization->refresh();
        $this->assertEquals($originalEmail, $this->organization->billing_email);
    }

    // ==========================================
    // Charge Refunded Tests
    // ==========================================

    public function test_charge_refunded_creates_audit_log(): void
    {
        $response = $this->postWebhook('charge.refunded', [
            'id' => 'ch_'.uniqid(),
            'customer' => $this->stripeCustomerId,
            'amount_refunded' => 2900,
            'currency' => 'usd',
        ]);

        $response->assertStatus(200);

        $this->assertDatabaseHas('audit_logs', [
            'organization_id' => $this->organization->id,
            'action' => 'charge.refunded',
            'resource_type' => 'charge',
        ]);
    }

    // ==========================================
    // Tier Determination Tests
    // ==========================================

    public function test_determines_starter_tier_by_default(): void
    {
        $payload = $this->createSubscriptionPayload([
            'items' => [
                'data' => [
                    ['price' => ['id' => 'price_unknown']],
                ],
            ],
        ]);

        $this->postWebhook('customer.subscription.created', $payload);

        $subscription = Subscription::where('organization_id', $this->organization->id)->first();
        $this->assertEquals('starter', $subscription->tier);
    }

    public function test_determines_correct_tier_from_config(): void
    {
        Config::set('chom.tiers.pro.stripe_price_id', 'price_pro_123');

        $payload = $this->createSubscriptionPayload([
            'items' => [
                'data' => [
                    ['price' => ['id' => 'price_pro_123']],
                ],
            ],
        ]);

        $this->postWebhook('customer.subscription.created', $payload);

        $subscription = Subscription::where('organization_id', $this->organization->id)->first();
        $this->assertEquals('pro', $subscription->tier);
    }

    // ==========================================
    // Status Mapping Tests
    // ==========================================

    public function test_maps_stripe_statuses_correctly(): void
    {
        $statusMappings = [
            'active' => 'active',
            'trialing' => 'trialing',
            'past_due' => 'past_due',
            'canceled' => 'cancelled',
            'incomplete' => 'incomplete',
        ];

        foreach ($statusMappings as $stripeStatus => $expectedStatus) {
            // Clean up previous subscription
            Subscription::where('organization_id', $this->organization->id)->delete();

            $payload = $this->createSubscriptionPayload([
                'status' => $stripeStatus,
            ]);

            $response = $this->postWebhook('customer.subscription.created', $payload);
            $response->assertStatus(200);

            $subscription = Subscription::where('organization_id', $this->organization->id)->first();
            $this->assertNotNull($subscription, "Subscription should exist for status '$stripeStatus'");
            $this->assertEquals(
                $expectedStatus,
                $subscription->status,
                "Failed asserting that Stripe status '$stripeStatus' maps to '$expectedStatus'"
            );
        }
    }

    // ==========================================
    // Edge Cases
    // ==========================================

    public function test_handles_missing_price_id_gracefully(): void
    {
        $payload = $this->createSubscriptionPayload([
            'items' => [
                'data' => [
                    ['price' => ['id' => null]],
                ],
            ],
        ]);

        $response = $this->postWebhook('customer.subscription.created', $payload);

        $response->assertStatus(200);

        $subscription = Subscription::where('organization_id', $this->organization->id)->first();
        $this->assertNotNull($subscription);
        $this->assertEquals('starter', $subscription->tier);
        $this->assertNull($subscription->stripe_price_id);
    }

    public function test_handles_concurrent_tenant_updates(): void
    {
        // Create multiple tenants
        $tenants = collect([
            $this->tenant,
            Tenant::factory()->for($this->organization)->create(),
            Tenant::factory()->for($this->organization)->create(),
        ]);

        Config::set('chom.tiers.enterprise.stripe_price_id', 'price_enterprise_test');

        $payload = $this->createSubscriptionPayload([
            'items' => [
                'data' => [
                    ['price' => ['id' => 'price_enterprise_test']],
                ],
            ],
        ]);

        $this->postWebhook('customer.subscription.created', $payload);

        // All tenants should be updated
        foreach ($tenants as $tenant) {
            $tenant->refresh();
            $this->assertEquals('enterprise', $tenant->tier);
        }
    }

    public function test_webhook_returns_200_for_unhandled_events(): void
    {
        $response = $this->postWebhook('some.unhandled.event', [
            'id' => 'obj_'.uniqid(),
        ]);

        $response->assertStatus(200);
    }
}
