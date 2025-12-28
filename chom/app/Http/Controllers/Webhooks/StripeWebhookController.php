<?php

namespace App\Http\Controllers\Webhooks;

use App\Models\AuditLog;
use App\Models\Invoice;
use App\Models\Organization;
use App\Models\Subscription;
use App\Models\Tenant;
use Illuminate\Support\Facades\Log;
use Laravel\Cashier\Http\Controllers\WebhookController as CashierController;
use Stripe\Subscription as StripeSubscription;

class StripeWebhookController extends CashierController
{
    /**
     * Handle customer subscription created.
     */
    protected function handleCustomerSubscriptionCreated(array $payload): void
    {
        $stripeSubscription = $payload['data']['object'];
        $stripeCustomerId = $stripeSubscription['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            Log::warning('Stripe webhook: Organization not found for customer', [
                'stripe_customer_id' => $stripeCustomerId,
            ]);

            return;
        }

        $tier = $this->determineTierFromPriceId($stripeSubscription['items']['data'][0]['price']['id'] ?? null);

        $subscription = Subscription::updateOrCreate(
            ['organization_id' => $organization->id],
            [
                'stripe_subscription_id' => $stripeSubscription['id'],
                'stripe_price_id' => $stripeSubscription['items']['data'][0]['price']['id'] ?? null,
                'tier' => $tier,
                'status' => $this->mapStripeStatus($stripeSubscription['status']),
                'trial_ends_at' => $stripeSubscription['trial_end']
                    ? now()->setTimestamp($stripeSubscription['trial_end'])
                    : null,
                'current_period_start' => now()->setTimestamp($stripeSubscription['current_period_start']),
                'current_period_end' => now()->setTimestamp($stripeSubscription['current_period_end']),
            ]
        );

        // Update tenant tier
        $this->updateTenantTiers($organization, $tier);

        AuditLog::log(
            action: 'subscription.created',
            organization: $organization,
            resourceType: 'subscription',
            resourceId: $subscription->id,
            metadata: [
                'tier' => $tier,
                'status' => $subscription->status,
                'stripe_subscription_id' => $stripeSubscription['id'],
            ]
        );

        Log::info('Stripe webhook: Subscription created', [
            'organization_id' => $organization->id,
            'tier' => $tier,
        ]);
    }

    /**
     * Handle customer subscription updated.
     */
    protected function handleCustomerSubscriptionUpdated(array $payload): void
    {
        $stripeSubscription = $payload['data']['object'];
        $stripeCustomerId = $stripeSubscription['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            Log::warning('Stripe webhook: Organization not found for subscription update', [
                'stripe_customer_id' => $stripeCustomerId,
            ]);

            return;
        }

        $subscription = Subscription::where('organization_id', $organization->id)->first();

        if (! $subscription) {
            // Subscription doesn't exist yet, create it
            $this->handleCustomerSubscriptionCreated($payload);

            return;
        }

        $previousTier = $subscription->tier;
        $previousStatus = $subscription->status;

        $newTier = $this->determineTierFromPriceId($stripeSubscription['items']['data'][0]['price']['id'] ?? null);
        $newStatus = $this->mapStripeStatus($stripeSubscription['status']);

        $subscription->update([
            'stripe_subscription_id' => $stripeSubscription['id'],
            'stripe_price_id' => $stripeSubscription['items']['data'][0]['price']['id'] ?? null,
            'tier' => $newTier,
            'status' => $newStatus,
            'trial_ends_at' => $stripeSubscription['trial_end']
                ? now()->setTimestamp($stripeSubscription['trial_end'])
                : null,
            'current_period_start' => now()->setTimestamp($stripeSubscription['current_period_start']),
            'current_period_end' => now()->setTimestamp($stripeSubscription['current_period_end']),
            'cancelled_at' => $stripeSubscription['canceled_at']
                ? now()->setTimestamp($stripeSubscription['canceled_at'])
                : null,
        ]);

        // Update tenant tier if changed
        if ($previousTier !== $newTier) {
            $this->updateTenantTiers($organization, $newTier);
        }

        // Handle status transitions
        if ($previousStatus !== $newStatus) {
            $this->handleStatusTransition($organization, $previousStatus, $newStatus);
        }

        AuditLog::log(
            action: 'subscription.updated',
            organization: $organization,
            resourceType: 'subscription',
            resourceId: $subscription->id,
            metadata: [
                'previous_tier' => $previousTier,
                'new_tier' => $newTier,
                'previous_status' => $previousStatus,
                'new_status' => $newStatus,
            ]
        );

        Log::info('Stripe webhook: Subscription updated', [
            'organization_id' => $organization->id,
            'tier_change' => $previousTier !== $newTier,
            'status_change' => $previousStatus !== $newStatus,
        ]);
    }

    /**
     * Handle customer subscription deleted.
     */
    protected function handleCustomerSubscriptionDeleted(array $payload): void
    {
        $stripeSubscription = $payload['data']['object'];
        $stripeCustomerId = $stripeSubscription['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            Log::warning('Stripe webhook: Organization not found for subscription deletion', [
                'stripe_customer_id' => $stripeCustomerId,
            ]);

            return;
        }

        $subscription = Subscription::where('organization_id', $organization->id)->first();

        if ($subscription) {
            $subscription->update([
                'status' => 'cancelled',
                'cancelled_at' => now(),
            ]);

            // Update tenants to suspended status
            $organization->tenants()->update(['status' => 'suspended']);

            AuditLog::log(
                action: 'subscription.cancelled',
                organization: $organization,
                resourceType: 'subscription',
                resourceId: $subscription->id,
                metadata: [
                    'cancelled_at' => now()->toIso8601String(),
                    'stripe_subscription_id' => $stripeSubscription['id'],
                ]
            );
        }

        Log::info('Stripe webhook: Subscription deleted', [
            'organization_id' => $organization->id,
        ]);
    }

    /**
     * Handle invoice paid.
     */
    protected function handleInvoicePaid(array $payload): void
    {
        $stripeInvoice = $payload['data']['object'];
        $stripeCustomerId = $stripeInvoice['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            Log::warning('Stripe webhook: Organization not found for invoice', [
                'stripe_customer_id' => $stripeCustomerId,
            ]);

            return;
        }

        $invoice = Invoice::updateOrCreate(
            [
                'organization_id' => $organization->id,
                'stripe_invoice_id' => $stripeInvoice['id'],
            ],
            [
                'amount_cents' => $stripeInvoice['amount_paid'],
                'currency' => $stripeInvoice['currency'],
                'status' => 'paid',
                'paid_at' => now(),
                'period_start' => isset($stripeInvoice['period_start'])
                    ? now()->setTimestamp($stripeInvoice['period_start'])->toDateString()
                    : null,
                'period_end' => isset($stripeInvoice['period_end'])
                    ? now()->setTimestamp($stripeInvoice['period_end'])->toDateString()
                    : null,
            ]
        );

        // Ensure tenant is active after successful payment
        $organization->tenants()
            ->where('status', 'suspended')
            ->update(['status' => 'active']);

        AuditLog::log(
            action: 'invoice.paid',
            organization: $organization,
            resourceType: 'invoice',
            resourceId: $invoice->id,
            metadata: [
                'amount_cents' => $stripeInvoice['amount_paid'],
                'currency' => $stripeInvoice['currency'],
                'stripe_invoice_id' => $stripeInvoice['id'],
            ]
        );

        Log::info('Stripe webhook: Invoice paid', [
            'organization_id' => $organization->id,
            'invoice_id' => $invoice->id,
            'amount_cents' => $stripeInvoice['amount_paid'],
        ]);
    }

    /**
     * Handle invoice payment failed.
     */
    protected function handleInvoicePaymentFailed(array $payload): void
    {
        $stripeInvoice = $payload['data']['object'];
        $stripeCustomerId = $stripeInvoice['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            Log::warning('Stripe webhook: Organization not found for failed payment', [
                'stripe_customer_id' => $stripeCustomerId,
            ]);

            return;
        }

        $invoice = Invoice::updateOrCreate(
            [
                'organization_id' => $organization->id,
                'stripe_invoice_id' => $stripeInvoice['id'],
            ],
            [
                'amount_cents' => $stripeInvoice['amount_due'],
                'currency' => $stripeInvoice['currency'],
                'status' => 'payment_failed',
                'period_start' => isset($stripeInvoice['period_start'])
                    ? now()->setTimestamp($stripeInvoice['period_start'])->toDateString()
                    : null,
                'period_end' => isset($stripeInvoice['period_end'])
                    ? now()->setTimestamp($stripeInvoice['period_end'])->toDateString()
                    : null,
            ]
        );

        // Update subscription status if this is a recurring payment failure
        $attemptCount = $stripeInvoice['attempt_count'] ?? 1;

        if ($attemptCount >= 3) {
            // After 3 failed attempts, suspend the tenant
            $organization->tenants()->update(['status' => 'suspended']);

            $subscription = $organization->subscription;
            if ($subscription) {
                $subscription->update(['status' => 'past_due']);
            }
        }

        AuditLog::log(
            action: 'invoice.payment_failed',
            organization: $organization,
            resourceType: 'invoice',
            resourceId: $invoice->id,
            metadata: [
                'amount_cents' => $stripeInvoice['amount_due'],
                'attempt_count' => $attemptCount,
                'stripe_invoice_id' => $stripeInvoice['id'],
            ]
        );

        Log::warning('Stripe webhook: Invoice payment failed', [
            'organization_id' => $organization->id,
            'invoice_id' => $invoice->id,
            'attempt_count' => $attemptCount,
        ]);
    }

    /**
     * Handle invoice finalized (sent to customer).
     */
    protected function handleInvoiceFinalized(array $payload): void
    {
        $stripeInvoice = $payload['data']['object'];
        $stripeCustomerId = $stripeInvoice['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            return;
        }

        Invoice::updateOrCreate(
            [
                'organization_id' => $organization->id,
                'stripe_invoice_id' => $stripeInvoice['id'],
            ],
            [
                'amount_cents' => $stripeInvoice['amount_due'],
                'currency' => $stripeInvoice['currency'],
                'status' => 'open',
                'period_start' => isset($stripeInvoice['period_start'])
                    ? now()->setTimestamp($stripeInvoice['period_start'])->toDateString()
                    : null,
                'period_end' => isset($stripeInvoice['period_end'])
                    ? now()->setTimestamp($stripeInvoice['period_end'])->toDateString()
                    : null,
            ]
        );

        Log::info('Stripe webhook: Invoice finalized', [
            'organization_id' => $organization->id,
            'stripe_invoice_id' => $stripeInvoice['id'],
        ]);
    }

    /**
     * Handle customer created.
     */
    protected function handleCustomerCreated(array $payload): void
    {
        // Customer creation is typically handled during registration
        // This handler is for logging/auditing purposes
        $customer = $payload['data']['object'];

        Log::info('Stripe webhook: Customer created', [
            'stripe_customer_id' => $customer['id'],
            'email' => $customer['email'] ?? null,
        ]);
    }

    /**
     * Handle customer updated.
     */
    protected function handleCustomerUpdated(array $payload): void
    {
        $customer = $payload['data']['object'];

        $organization = Organization::where('stripe_customer_id', $customer['id'])->first();

        if ($organization && isset($customer['email'])) {
            $organization->update([
                'billing_email' => $customer['email'],
            ]);

            Log::info('Stripe webhook: Customer updated', [
                'organization_id' => $organization->id,
                'billing_email' => $customer['email'],
            ]);
        }
    }

    /**
     * Handle charge refunded.
     */
    protected function handleChargeRefunded(array $payload): void
    {
        $charge = $payload['data']['object'];
        $stripeCustomerId = $charge['customer'];

        $organization = Organization::where('stripe_customer_id', $stripeCustomerId)->first();

        if (! $organization) {
            return;
        }

        AuditLog::log(
            action: 'charge.refunded',
            organization: $organization,
            resourceType: 'charge',
            metadata: [
                'charge_id' => $charge['id'],
                'amount_refunded' => $charge['amount_refunded'],
                'currency' => $charge['currency'],
            ]
        );

        Log::info('Stripe webhook: Charge refunded', [
            'organization_id' => $organization->id,
            'amount_refunded' => $charge['amount_refunded'],
        ]);
    }

    /**
     * Handle payment intent succeeded (for one-time payments).
     */
    protected function handlePaymentIntentSucceeded(array $payload): void
    {
        $paymentIntent = $payload['data']['object'];

        Log::info('Stripe webhook: Payment intent succeeded', [
            'payment_intent_id' => $paymentIntent['id'],
            'amount' => $paymentIntent['amount'],
        ]);
    }

    /**
     * Determine tier from Stripe price ID.
     */
    protected function determineTierFromPriceId(?string $priceId): string
    {
        if (! $priceId) {
            return 'starter';
        }

        $tiers = config('chom.tiers', []);

        foreach ($tiers as $tierName => $tierConfig) {
            if (($tierConfig['stripe_price_id'] ?? null) === $priceId) {
                return $tierName;
            }
        }

        // Default to starter if price ID not found
        return 'starter';
    }

    /**
     * Map Stripe subscription status to internal status.
     */
    protected function mapStripeStatus(string $stripeStatus): string
    {
        return match ($stripeStatus) {
            StripeSubscription::STATUS_ACTIVE => 'active',
            StripeSubscription::STATUS_TRIALING => 'trialing',
            StripeSubscription::STATUS_PAST_DUE => 'past_due',
            StripeSubscription::STATUS_CANCELED => 'cancelled',
            StripeSubscription::STATUS_UNPAID => 'unpaid',
            StripeSubscription::STATUS_INCOMPLETE => 'incomplete',
            StripeSubscription::STATUS_INCOMPLETE_EXPIRED => 'incomplete_expired',
            StripeSubscription::STATUS_PAUSED => 'paused',
            default => $stripeStatus,
        };
    }

    /**
     * Update all tenant tiers for an organization.
     */
    protected function updateTenantTiers(Organization $organization, string $tier): void
    {
        $organization->tenants()->update(['tier' => $tier]);
    }

    /**
     * Handle subscription status transitions.
     */
    protected function handleStatusTransition(Organization $organization, string $previousStatus, string $newStatus): void
    {
        // Reactivate suspended tenants when subscription becomes active
        if ($newStatus === 'active' && in_array($previousStatus, ['past_due', 'unpaid', 'incomplete'])) {
            $organization->tenants()
                ->where('status', 'suspended')
                ->update(['status' => 'active']);

            Log::info('Stripe webhook: Tenants reactivated after subscription activation', [
                'organization_id' => $organization->id,
            ]);
        }

        // Suspend tenants when subscription enters problem state
        if (in_array($newStatus, ['past_due', 'unpaid', 'cancelled']) && $previousStatus === 'active') {
            // Give grace period for past_due, immediate suspend for cancelled/unpaid
            if ($newStatus !== 'past_due') {
                $organization->tenants()->update(['status' => 'suspended']);

                Log::info('Stripe webhook: Tenants suspended due to subscription status', [
                    'organization_id' => $organization->id,
                    'new_status' => $newStatus,
                ]);
            }
        }
    }
}
