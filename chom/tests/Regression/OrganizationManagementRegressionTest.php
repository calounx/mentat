<?php

namespace Tests\Regression;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class OrganizationManagementRegressionTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function organization_is_created_with_default_tenant(): void
    {
        $organization = Organization::factory()->create();

        $this->assertNotNull($organization->defaultTenant);
        $this->assertEquals('Default', $organization->defaultTenant->name);
        $this->assertEquals('starter', $organization->defaultTenant->tier);
    }

    #[Test]
    public function organization_has_unique_slug(): void
    {
        $org1 = Organization::factory()->create(['name' => 'Test Company']);
        $org2 = Organization::factory()->create(['name' => 'Test Company']);

        $this->assertNotEquals($org1->slug, $org2->slug);
        $this->assertStringContainsString('test-company', $org1->slug);
        $this->assertStringContainsString('test-company', $org2->slug);
    }

    #[Test]
    public function organization_can_have_multiple_users(): void
    {
        $organization = Organization::factory()->create();

        $owner = User::factory()->owner()->create(['organization_id' => $organization->id]);
        $admin = User::factory()->admin()->create(['organization_id' => $organization->id]);
        $member = User::factory()->create([
            'role' => 'member',
            'organization_id' => $organization->id,
        ]);

        $organization->refresh();

        $this->assertEquals(3, $organization->users()->count());
        $this->assertTrue($organization->users->contains($owner));
        $this->assertTrue($organization->users->contains($admin));
        $this->assertTrue($organization->users->contains($member));
    }

    #[Test]
    public function organization_has_billing_email(): void
    {
        $organization = Organization::factory()->create([
            'billing_email' => 'billing@example.com',
        ]);

        $this->assertEquals('billing@example.com', $organization->billing_email);
        $this->assertEquals('billing@example.com', $organization->stripeEmail());
    }

    #[Test]
    public function organization_can_be_updated(): void
    {
        $organization = Organization::factory()->create([
            'name' => 'Original Name',
            'billing_email' => 'old@example.com',
        ]);

        $organization->update([
            'name' => 'Updated Name',
            'billing_email' => 'new@example.com',
        ]);

        $this->assertEquals('Updated Name', $organization->name);
        $this->assertEquals('new@example.com', $organization->billing_email);
    }

    #[Test]
    public function organization_owner_can_be_identified(): void
    {
        $organization = Organization::factory()->create();
        $owner = User::factory()->owner()->create(['organization_id' => $organization->id]);
        $admin = User::factory()->admin()->create(['organization_id' => $organization->id]);

        $this->assertEquals($owner->id, $organization->owner->id);
        $this->assertEquals('owner', $organization->owner->role);
    }

    #[Test]
    public function organization_can_have_multiple_tenants(): void
    {
        $organization = Organization::factory()->create();

        $tenant1 = Tenant::factory()->create(['organization_id' => $organization->id]);
        $tenant2 = Tenant::factory()->create(['organization_id' => $organization->id]);
        $tenant3 = Tenant::factory()->create(['organization_id' => $organization->id]);

        $organization->refresh();

        $this->assertGreaterThanOrEqual(3, $organization->tenants()->count());
    }

    #[Test]
    public function organization_has_default_tenant_set(): void
    {
        $organization = Organization::factory()->create();

        $this->assertNotNull($organization->default_tenant_id);
        $this->assertNotNull($organization->defaultTenant);
        $this->assertEquals($organization->default_tenant_id, $organization->defaultTenant->id);
    }

    #[Test]
    public function organization_tracks_stripe_customer_id(): void
    {
        $organization = Organization::factory()->create([
            'stripe_customer_id' => 'cus_test123',
        ]);

        $this->assertEquals('cus_test123', $organization->stripe_customer_id);
    }

    #[Test]
    public function organization_without_stripe_customer(): void
    {
        $organization = Organization::factory()->withoutStripeCustomer()->create();

        $this->assertNull($organization->stripe_customer_id);
    }

    #[Test]
    public function organization_can_check_subscription_status(): void
    {
        $organization = Organization::factory()->create();

        // Without subscription
        $this->assertFalse($organization->hasActiveSubscription());

        // With active subscription
        \App\Models\Subscription::factory()->create([
            'organization_id' => $organization->id,
            'status' => 'active',
        ]);

        $organization->refresh();
        $this->assertTrue($organization->hasActiveSubscription());
    }

    #[Test]
    public function organization_can_determine_current_tier(): void
    {
        $organization = Organization::factory()->create();

        // Default tier when no subscription
        $this->assertEquals('starter', $organization->getCurrentTier());

        // With subscription
        \App\Models\Subscription::factory()->create([
            'organization_id' => $organization->id,
            'tier' => 'pro',
        ]);

        $organization->refresh();
        $this->assertEquals('pro', $organization->getCurrentTier());
    }

    #[Test]
    public function organization_has_audit_logs_relationship(): void
    {
        $organization = Organization::factory()->create();

        // Create audit logs would require the AuditLogFactory
        // For now, just verify the relationship exists
        $this->assertInstanceOf(
            \Illuminate\Database\Eloquent\Relations\HasMany::class,
            $organization->auditLogs()
        );
    }

    #[Test]
    public function organization_slug_is_url_safe(): void
    {
        $organization = Organization::factory()->create([
            'name' => 'Test Company & Partners LLC',
        ]);

        // Slug should be URL-safe (no special characters)
        $this->assertMatchesRegularExpression('/^[a-z0-9-]+$/', $organization->slug);
        $this->assertStringNotContainsString('&', $organization->slug);
        $this->assertStringNotContainsString(' ', $organization->slug);
    }
}
