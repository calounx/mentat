<?php

namespace Tests\Unit\Models;

use App\Models\AuditLog;
use App\Models\Invoice;
use App\Models\Operation;
use App\Models\Organization;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\TierLimit;
use App\Models\UsageRecord;
use App\Models\User;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class ModelRelationshipsTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function organization_user_relationship_works_bidirectionally()
    {
        $organization = Organization::factory()->create();
        $users = User::factory()->count(3)->create(['organization_id' => $organization->id]);

        // Organization -> Users
        $this->assertCount(3, $organization->users);
        $this->assertEquals($users->pluck('id')->sort()->values(), $organization->users->pluck('id')->sort()->values());

        // User -> Organization
        $this->assertEquals($organization->id, $users->first()->organization->id);
    }

    #[Test]
    public function organization_tenant_relationship_works_bidirectionally()
    {
        $organization = Organization::factory()->create();
        $tenants = Tenant::factory()->count(2)->create(['organization_id' => $organization->id]);

        // Organization -> Tenants
        $this->assertCount(2, $organization->tenants);

        // Tenant -> Organization
        $this->assertEquals($organization->id, $tenants->first()->organization->id);
    }

    #[Test]
    public function organization_has_default_tenant()
    {
        $organization = Organization::factory()->create();
        $defaultTenant = Tenant::factory()->create(['organization_id' => $organization->id]);
        $organization->update(['default_tenant_id' => $defaultTenant->id]);

        $this->assertEquals($defaultTenant->id, $organization->defaultTenant->id);
    }

    #[Test]
    public function tenant_site_relationship_works_bidirectionally()
    {
        $tenant = Tenant::factory()->create();
        $sites = Site::factory()->count(5)->create(['tenant_id' => $tenant->id]);

        // Tenant -> Sites
        $this->assertCount(5, $tenant->sites);

        // Site -> Tenant
        $site = Site::withoutGlobalScopes()->find($sites->first()->id);
        $this->assertEquals($tenant->id, $site->tenant->id);
    }

    #[Test]
    public function site_backup_relationship_works_bidirectionally()
    {
        $site = Site::factory()->create();
        $backups = SiteBackup::factory()->count(4)->create(['site_id' => $site->id]);

        // Site -> Backups
        $site = Site::withoutGlobalScopes()->find($site->id);
        $this->assertCount(4, $site->backups);

        // Backup -> Site
        $this->assertEquals($site->id, $backups->first()->site->id);
    }

    #[Test]
    public function vps_server_site_relationship_works_bidirectionally()
    {
        $vpsServer = VpsServer::factory()->create();
        $sites = Site::factory()->count(3)->create(['vps_id' => $vpsServer->id]);

        // VPS -> Sites
        $this->assertCount(3, $vpsServer->sites);

        // Site -> VPS
        $site = Site::withoutGlobalScopes()->find($sites->first()->id);
        $this->assertEquals($vpsServer->id, $site->vpsServer->id);
    }

    #[Test]
    public function vps_allocation_relationships_work_correctly()
    {
        $vpsServer = VpsServer::factory()->create();
        $tenant = Tenant::factory()->create();
        $allocation = VpsAllocation::factory()->create([
            'vps_id' => $vpsServer->id,
            'tenant_id' => $tenant->id,
        ]);

        // Allocation -> VPS
        $allocation = VpsAllocation::withoutGlobalScopes()->find($allocation->id);
        $this->assertEquals($vpsServer->id, $allocation->vpsServer->id);

        // Allocation -> Tenant
        $this->assertEquals($tenant->id, $allocation->tenant->id);

        // VPS -> Allocations
        $this->assertCount(1, $vpsServer->allocations);

        // Tenant -> Allocations
        $this->assertCount(1, $tenant->vpsAllocations);
    }

    #[Test]
    public function tenant_vps_has_many_through_relationship_works()
    {
        $tenant = Tenant::factory()->create();
        $vps1 = VpsServer::factory()->create();
        $vps2 = VpsServer::factory()->create();
        $vps3 = VpsServer::factory()->create();

        VpsAllocation::factory()->create(['tenant_id' => $tenant->id, 'vps_id' => $vps1->id]);
        VpsAllocation::factory()->create(['tenant_id' => $tenant->id, 'vps_id' => $vps2->id]);
        VpsAllocation::factory()->create(['tenant_id' => $tenant->id, 'vps_id' => $vps3->id]);

        $vpsServers = $tenant->vpsServers;

        $this->assertCount(3, $vpsServers);
        $this->assertTrue($vpsServers->contains($vps1));
        $this->assertTrue($vpsServers->contains($vps2));
        $this->assertTrue($vpsServers->contains($vps3));
    }

    #[Test]
    public function organization_subscription_relationship_works()
    {
        $organization = Organization::factory()->create();
        $subscription = Subscription::factory()->create(['organization_id' => $organization->id]);

        $this->assertEquals($subscription->id, $organization->subscription->id);
        $this->assertEquals($organization->id, $subscription->organization->id);
    }

    #[Test]
    public function organization_invoice_relationship_works()
    {
        $organization = Organization::factory()->create();
        $invoices = Invoice::factory()->count(3)->create(['organization_id' => $organization->id]);

        $this->assertCount(3, $organization->invoices);
        $this->assertEquals($organization->id, $invoices->first()->organization->id);
    }

    #[Test]
    public function tenant_usage_record_relationship_works()
    {
        $tenant = Tenant::factory()->create();
        $usageRecords = UsageRecord::factory()->count(5)->create(['tenant_id' => $tenant->id]);

        $this->assertCount(5, $tenant->usageRecords);
        $tenant->usageRecords->each(function ($record) use ($tenant) {
            $record = UsageRecord::withoutGlobalScopes()->find($record->id);
            $this->assertEquals($tenant->id, $record->tenant->id);
        });
    }

    #[Test]
    public function user_operation_relationship_works()
    {
        $user = User::factory()->create();
        $operations = Operation::factory()->count(4)->create(['user_id' => $user->id]);

        $this->assertCount(4, $user->operations);
        $operations->each(function ($operation) use ($user) {
            $operation = Operation::withoutGlobalScopes()->find($operation->id);
            $this->assertEquals($user->id, $operation->user->id);
        });
    }

    #[Test]
    public function tenant_operation_relationship_works()
    {
        $tenant = Tenant::factory()->create();
        $operations = Operation::factory()->count(3)->create(['tenant_id' => $tenant->id]);

        $this->assertCount(3, $tenant->operations);
        $operations->each(function ($operation) use ($tenant) {
            $operation = Operation::withoutGlobalScopes()->find($operation->id);
            $this->assertEquals($tenant->id, $operation->tenant->id);
        });
    }

    #[Test]
    public function organization_audit_log_relationship_works()
    {
        $organization = Organization::factory()->create();
        $auditLogs = AuditLog::factory()->count(6)->create(['organization_id' => $organization->id]);

        $this->assertCount(6, $organization->auditLogs);
        $this->assertEquals($organization->id, $auditLogs->first()->organization->id);
    }

    #[Test]
    public function user_audit_log_relationship_works()
    {
        $user = User::factory()->create();
        $auditLogs = AuditLog::factory()->count(4)->create(['user_id' => $user->id]);

        $auditLogs->each(function ($log) use ($user) {
            $this->assertEquals($user->id, $log->user->id);
        });
    }

    #[Test]
    public function tenant_tier_limit_relationship_works()
    {
        $tierLimit = TierLimit::factory()->create(['tier' => 'enterprise']);
        $tenant = Tenant::factory()->create(['tier' => 'enterprise']);

        $this->assertInstanceOf(TierLimit::class, $tenant->tierLimits);
        $this->assertEquals('enterprise', $tenant->tierLimits->tier);
        $this->assertCount(1, $tierLimit->tenants);
    }

    #[Test]
    public function eager_loading_prevents_n_plus_1_queries()
    {
        $organization = Organization::factory()->create();
        Site::factory()->count(10)->create();

        DB::enableQueryLog();

        // Without eager loading - causes N+1
        $sitesWithout = Site::withoutGlobalScopes()->all();
        foreach ($sitesWithout as $site) {
            $site->tenant->name;
        }
        $queriesWithoutEager = count(DB::getQueryLog());

        DB::flushQueryLog();

        // With eager loading
        $sitesWith = Site::withoutGlobalScopes()->with('tenant')->get();
        foreach ($sitesWith as $site) {
            $site->tenant->name;
        }
        $queriesWithEager = count(DB::getQueryLog());

        // Eager loading should use fewer queries
        $this->assertLessThan($queriesWithoutEager, $queriesWithEager);
    }

    #[Test]
    public function complex_nested_eager_loading_works()
    {
        $organization = Organization::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $organization->id]);
        $vpsServer = VpsServer::factory()->create();
        $site = Site::factory()->create(['tenant_id' => $tenant->id, 'vps_id' => $vpsServer->id]);
        SiteBackup::factory()->count(3)->create(['site_id' => $site->id]);

        $loadedTenant = Tenant::with([
            'sites.backups',
            'sites.vpsServer',
            'organization',
        ])->find($tenant->id);

        $this->assertTrue($loadedTenant->relationLoaded('sites'));
        $this->assertTrue($loadedTenant->sites->first()->relationLoaded('backups'));
        $this->assertTrue($loadedTenant->sites->first()->relationLoaded('vpsServer'));
        $this->assertTrue($loadedTenant->relationLoaded('organization'));
    }
}
