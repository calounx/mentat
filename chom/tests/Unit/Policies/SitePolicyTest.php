<?php

namespace Tests\Unit\Policies;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Policies\SitePolicy;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class SitePolicyTest extends TestCase
{
    use RefreshDatabase;

    private SitePolicy $policy;
    private Tenant $tenant;

    protected function setUp(): void
    {
        parent::setUp();

        $this->policy = new SitePolicy();

        $this->tenant = Tenant::factory()->create([
            'tier' => 'professional',
            'status' => 'active',
        ]);

        DB::table('tier_limits')->insert([
            'tier' => 'professional',
            'max_sites' => 20,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function test_owner_bypasses_all_checks()
    {
        $owner = User::factory()->make(['role' => 'owner']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $this->assertTrue($this->policy->before($owner, 'viewAny'));
        $this->assertTrue($this->policy->before($owner, 'view'));
        $this->assertTrue($this->policy->before($owner, 'create'));
        $this->assertTrue($this->policy->before($owner, 'update'));
        $this->assertTrue($this->policy->before($owner, 'delete'));
    }

    public function test_member_can_view_any_sites()
    {
        $member = User::factory()->make(['role' => 'member']);

        $result = $this->policy->viewAny($member);

        $this->assertTrue($result);
    }

    public function test_viewer_cannot_view_any_sites()
    {
        $viewer = User::factory()->make(['role' => 'viewer']);

        $result = $this->policy->viewAny($viewer);

        $this->assertFalse($result);
    }

    public function test_member_can_view_site_in_same_tenant()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->view($member, $site);

        $this->assertTrue($result);
    }

    public function test_member_cannot_view_site_in_different_tenant()
    {
        $otherTenant = Tenant::factory()->create();

        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $otherTenant->id,
        ]);

        $result = $this->policy->view($member, $site);

        $this->assertFalse($result);
    }

    public function test_viewer_cannot_view_site_even_in_same_tenant()
    {
        $viewer = User::factory()->make(['role' => 'viewer']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->view($viewer, $site);

        $this->assertFalse($result);
    }

    public function test_member_can_create_site_when_within_quota()
    {
        $member = User::factory()->make(['role' => 'member']);

        DB::table('sites')->insert([
            'id' => 'site-1',
            'tenant_id' => $this->tenant->id,
            'domain' => 'test1.com',
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $result = $this->policy->create($member);

        $this->assertTrue($result);
    }

    public function test_member_cannot_create_site_when_quota_exceeded()
    {
        $member = User::factory()->make(['role' => 'member']);

        for ($i = 0; $i < 20; $i++) {
            DB::table('sites')->insert([
                'id' => "site-{$i}",
                'tenant_id' => $this->tenant->id,
                'domain' => "test{$i}.com",
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        $result = $this->policy->create($member);

        $this->assertFalse($result);
    }

    public function test_viewer_cannot_create_site()
    {
        $viewer = User::factory()->make(['role' => 'viewer']);

        $result = $this->policy->create($viewer);

        $this->assertFalse($result);
    }

    public function test_member_can_update_site_in_same_tenant()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->update($member, $site);

        $this->assertTrue($result);
    }

    public function test_member_cannot_update_site_in_different_tenant()
    {
        $otherTenant = Tenant::factory()->create();

        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $otherTenant->id,
        ]);

        $result = $this->policy->update($member, $site);

        $this->assertFalse($result);
    }

    public function test_admin_can_delete_site_in_same_tenant()
    {
        $admin = User::factory()->make(['role' => 'admin']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->delete($admin, $site);

        $this->assertTrue($result);
    }

    public function test_member_cannot_delete_site()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->delete($member, $site);

        $this->assertFalse($result);
    }

    public function test_admin_cannot_delete_site_in_different_tenant()
    {
        $otherTenant = Tenant::factory()->create();

        $admin = User::factory()->make(['role' => 'admin']);

        $site = Site::factory()->make([
            'tenant_id' => $otherTenant->id,
        ]);

        $result = $this->policy->delete($admin, $site);

        $this->assertFalse($result);
    }

    public function test_owner_can_force_delete_site()
    {
        $owner = User::factory()->make(['role' => 'owner']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->forceDelete($owner, $site);

        $this->assertTrue($result);
    }

    public function test_admin_cannot_force_delete_site()
    {
        $admin = User::factory()->make(['role' => 'admin']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->forceDelete($admin, $site);

        $this->assertFalse($result);
    }

    public function test_member_can_toggle_site_status_in_same_tenant()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->toggleStatus($member, $site);

        $this->assertTrue($result);
    }

    public function test_viewer_cannot_toggle_site_status()
    {
        $viewer = User::factory()->make(['role' => 'viewer']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->toggleStatus($viewer, $site);

        $this->assertFalse($result);
    }

    public function test_member_can_manage_ssl_in_same_tenant()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->manageSSL($member, $site);

        $this->assertTrue($result);
    }

    public function test_member_can_view_metrics_in_same_tenant()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
        ]);

        $result = $this->policy->viewMetrics($member, $site);

        $this->assertTrue($result);
    }

    public function test_admin_can_restore_soft_deleted_site_within_quota()
    {
        $admin = User::factory()->make(['role' => 'admin']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
            'deleted_at' => now(),
        ]);

        $site->shouldReceive('trashed')->andReturn(true);

        $result = $this->policy->restore($admin, $site);

        $this->assertTrue($result);
    }

    public function test_member_cannot_restore_site()
    {
        $member = User::factory()->make(['role' => 'member']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
            'deleted_at' => now(),
        ]);

        $site->shouldReceive('trashed')->andReturn(true);

        $result = $this->policy->restore($member, $site);

        $this->assertFalse($result);
    }

    public function test_admin_cannot_restore_site_not_deleted()
    {
        $admin = User::factory()->make(['role' => 'admin']);

        $site = Site::factory()->make([
            'tenant_id' => $this->tenant->id,
            'deleted_at' => null,
        ]);

        $site->shouldReceive('trashed')->andReturn(false);

        $result = $this->policy->restore($admin, $site);

        $this->assertFalse($result);
    }

    public function test_enterprise_tier_has_unlimited_quota()
    {
        DB::table('tier_limits')->insert([
            'tier' => 'enterprise',
            'max_sites' => -1,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $enterpriseTenant = Tenant::factory()->create([
            'tier' => 'enterprise',
        ]);

        $member = User::factory()->make([
            'role' => 'member',
            
        ]);

        for ($i = 0; $i < 100; $i++) {
            DB::table('sites')->insert([
                'id' => "ent-site-{$i}",
                'tenant_id' => $enterpriseTenant->id,
                'domain' => "enterprise{$i}.com",
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        $result = $this->policy->create($member);

        $this->assertTrue($result);
    }
}
