<?php

namespace Tests\Unit\Models;

use App\Models\AuditLog;
use App\Models\Invoice;
use App\Models\Organization;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class OrganizationModelTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_has_correct_fillable_attributes()
    {
        $fillable = [
            'name',
            'slug',
            'billing_email',
            'stripe_customer_id',
            'default_tenant_id',
        ];

        $organization = new Organization();
        $this->assertEquals($fillable, $organization->getFillable());
    }

    #[Test]
    public function it_hides_sensitive_attributes()
    {
        $organization = Organization::factory()->create([
            'stripe_customer_id' => 'cus_test123',
        ]);

        $array = $organization->toArray();

        $this->assertArrayNotHasKey('stripe_customer_id', $array);
    }

    #[Test]
    public function it_has_many_tenants()
    {
        $organization = Organization::factory()->create();
        Tenant::factory()->count(3)->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $organization->tenants);
        $this->assertCount(3, $organization->tenants);
        $this->assertInstanceOf(Tenant::class, $organization->tenants->first());
    }

    #[Test]
    public function it_belongs_to_a_default_tenant()
    {
        $organization = Organization::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $organization->id]);
        $organization->update(['default_tenant_id' => $tenant->id]);

        $this->assertInstanceOf(Tenant::class, $organization->defaultTenant);
        $this->assertEquals($tenant->id, $organization->defaultTenant->id);
    }

    #[Test]
    public function it_has_many_users()
    {
        $organization = Organization::factory()->create();
        User::factory()->count(5)->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $organization->users);
        $this->assertCount(5, $organization->users);
        $this->assertInstanceOf(User::class, $organization->users->first());
    }

    #[Test]
    public function it_has_one_owner()
    {
        $organization = Organization::factory()->create();
        $owner = User::factory()->create([
            'organization_id' => $organization->id,
            'role' => 'owner',
        ]);
        User::factory()->count(2)->create([
            'organization_id' => $organization->id,
            'role' => 'member',
        ]);

        $this->assertInstanceOf(User::class, $organization->owner);
        $this->assertEquals($owner->id, $organization->owner->id);
        $this->assertEquals('owner', $organization->owner->role);
    }

    #[Test]
    public function it_has_one_subscription()
    {
        $organization = Organization::factory()->create();
        $subscription = Subscription::factory()->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(Subscription::class, $organization->subscription);
        $this->assertEquals($subscription->id, $organization->subscription->id);
    }

    #[Test]
    public function it_has_many_invoices()
    {
        $organization = Organization::factory()->create();
        Invoice::factory()->count(4)->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $organization->invoices);
        $this->assertCount(4, $organization->invoices);
        $this->assertInstanceOf(Invoice::class, $organization->invoices->first());
    }

    #[Test]
    public function it_has_many_audit_logs()
    {
        $organization = Organization::factory()->create();
        AuditLog::factory()->count(6)->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $organization->auditLogs);
        $this->assertCount(6, $organization->auditLogs);
        $this->assertInstanceOf(AuditLog::class, $organization->auditLogs->first());
    }

    #[Test]
    public function it_returns_stripe_email_for_billing()
    {
        $organization = Organization::factory()->create([
            'billing_email' => 'billing@example.com',
        ]);

        $this->assertEquals('billing@example.com', $organization->stripeEmail());
    }

    #[Test]
    public function it_checks_if_organization_has_active_subscription()
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

        // Trialing subscription
        $organization->subscription->update(['status' => 'trialing']);
        $organization->refresh();
        $this->assertTrue($organization->hasActiveSubscription());

        // Cancelled subscription
        $organization->subscription->update(['status' => 'cancelled']);
        $organization->refresh();
        $this->assertFalse($organization->hasActiveSubscription());
    }

    #[Test]
    public function it_gets_current_tier()
    {
        $organization = Organization::factory()->create();

        // Default tier when no subscription
        $this->assertEquals('starter', $organization->getCurrentTier());

        // Tier from subscription
        Subscription::factory()->create([
            'organization_id' => $organization->id,
            'tier' => 'pro',
        ]);
        $organization->refresh();
        $this->assertEquals('pro', $organization->getCurrentTier());
    }

    #[Test]
    public function it_uses_uuid_as_primary_key()
    {
        $organization = Organization::factory()->create();

        $this->assertIsString($organization->id);
        $this->assertEquals(36, strlen($organization->id));
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $organization->id
        );
    }

    #[Test]
    public function it_has_timestamps()
    {
        $organization = Organization::factory()->create();

        $this->assertNotNull($organization->created_at);
        $this->assertNotNull($organization->updated_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $organization->created_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $organization->updated_at);
    }

    #[Test]
    public function it_can_mass_assign_allowed_attributes()
    {
        $data = [
            'name' => 'Test Organization',
            'slug' => 'test-org',
            'billing_email' => 'billing@test.com',
        ];

        $organization = Organization::create($data);

        $this->assertEquals('Test Organization', $organization->name);
        $this->assertEquals('test-org', $organization->slug);
        $this->assertEquals('billing@test.com', $organization->billing_email);
    }
}
