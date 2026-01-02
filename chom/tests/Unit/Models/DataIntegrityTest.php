<?php

namespace Tests\Unit\Models;

use App\Models\Organization;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class DataIntegrityTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_enforces_unique_email_constraint_on_users()
    {
        User::factory()->create(['email' => 'test@example.com']);

        $this->expectException(\Illuminate\Database\QueryException::class);
        User::factory()->create(['email' => 'test@example.com']);
    }

    #[Test]
    public function it_enforces_unique_domain_per_tenant_constraint_on_sites()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->create(['domain' => 'example.com', 'tenant_id' => $tenant->id]);

        $this->expectException(\Illuminate\Database\QueryException::class);
        // Same domain in same tenant should fail
        Site::factory()->create(['domain' => 'example.com', 'tenant_id' => $tenant->id]);
    }

    #[Test]
    public function it_allows_same_domain_in_different_tenants()
    {
        $tenant1 = Tenant::factory()->create();
        $tenant2 = Tenant::factory()->create();

        $site1 = Site::factory()->create(['domain' => 'example.com', 'tenant_id' => $tenant1->id]);
        $site2 = Site::factory()->create(['domain' => 'example.com', 'tenant_id' => $tenant2->id]);

        $this->assertNotEquals($site1->id, $site2->id);
        $this->assertEquals('example.com', $site1->domain);
        $this->assertEquals('example.com', $site2->domain);
    }

    #[Test]
    public function it_enforces_foreign_key_constraint_user_organization()
    {
        $this->expectException(\Illuminate\Database\QueryException::class);

        // Try to create user with non-existent organization
        User::factory()->create(['organization_id' => '99999999-9999-9999-9999-999999999999']);
    }

    #[Test]
    public function it_enforces_foreign_key_constraint_site_tenant()
    {
        $this->expectException(\Illuminate\Database\QueryException::class);

        // Try to create site with non-existent tenant
        Site::factory()->create(['tenant_id' => '99999999-9999-9999-9999-999999999999']);
    }

    #[Test]
    public function it_enforces_foreign_key_constraint_site_vps()
    {
        $this->expectException(\Illuminate\Database\QueryException::class);

        // Try to create site with non-existent VPS
        Site::factory()->create(['vps_id' => '99999999-9999-9999-9999-999999999999']);
    }

    #[Test]
    public function soft_delete_preserves_data_in_database()
    {
        $site = Site::factory()->create();
        $siteId = $site->id;

        $site = Site::withoutGlobalScopes()->find($siteId);
        $site->delete();

        // Should still exist in database
        $deletedSite = DB::table('sites')->where('id', $siteId)->first();
        $this->assertNotNull($deletedSite);
        $this->assertNotNull($deletedSite->deleted_at);
    }

    #[Test]
    public function soft_deleted_sites_are_excluded_from_default_queries()
    {
        $site = Site::factory()->create();
        $siteId = $site->id;

        $site = Site::withoutGlobalScopes()->find($siteId);
        $site->delete();

        // Should not find with default query
        $this->assertNull(Site::withoutGlobalScopes()->find($siteId));

        // Should find with withTrashed
        $this->assertNotNull(Site::withoutGlobalScopes()->withTrashed()->find($siteId));
    }

    #[Test]
    public function force_delete_removes_data_permanently()
    {
        $site = Site::factory()->create();
        $siteId = $site->id;

        $site = Site::withoutGlobalScopes()->find($siteId);
        $site->forceDelete();

        // Should not exist in database
        $deletedSite = DB::table('sites')->where('id', $siteId)->first();
        $this->assertNull($deletedSite);
    }

    #[Test]
    public function restore_brings_back_soft_deleted_records()
    {
        $site = Site::factory()->create();
        $siteId = $site->id;

        $site = Site::withoutGlobalScopes()->find($siteId);
        $site->delete();

        // Restore
        $site->restore();

        // Should be accessible again
        $this->assertNotNull(Site::withoutGlobalScopes()->find($siteId));
        $this->assertNull(Site::withoutGlobalScopes()->find($siteId)->deleted_at);
    }

    #[Test]
    public function database_transaction_rollback_works()
    {
        DB::beginTransaction();

        $organization = Organization::factory()->create(['name' => 'Test Org']);

        DB::rollBack();

        // Should not exist after rollback
        $this->assertNull(Organization::where('name', 'Test Org')->first());
    }

    #[Test]
    public function database_transaction_commit_persists_data()
    {
        DB::beginTransaction();

        $organization = Organization::factory()->create(['name' => 'Test Org 2']);

        DB::commit();

        // Should exist after commit
        $this->assertNotNull(Organization::where('name', 'Test Org 2')->first());
    }

    #[Test]
    public function cascading_soft_delete_preserves_related_data()
    {
        $site = Site::factory()->create();
        $backup = SiteBackup::factory()->create(['site_id' => $site->id]);

        $site = Site::withoutGlobalScopes()->find($site->id);
        $site->delete();

        // Backup should still exist (no cascade delete)
        $this->assertNotNull(SiteBackup::find($backup->id));
    }

    #[Test]
    public function deleting_organization_with_users_is_prevented()
    {
        $organization = Organization::factory()->create();
        User::factory()->create(['organization_id' => $organization->id]);

        try {
            $organization->delete();
            $this->fail('Expected foreign key constraint exception');
        } catch (\Illuminate\Database\QueryException $e) {
            // Expected behavior - foreign key constraint prevents deletion
            $this->assertTrue(true);
        }
    }

    #[Test]
    public function deleting_tenant_with_sites_is_prevented()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->create(['tenant_id' => $tenant->id]);

        try {
            $tenant->delete();
            $this->fail('Expected foreign key constraint exception');
        } catch (\Illuminate\Database\QueryException $e) {
            // Expected behavior - foreign key constraint prevents deletion
            $this->assertTrue(true);
        }
    }

    #[Test]
    public function deleting_vps_with_sites_is_prevented()
    {
        $vpsServer = VpsServer::factory()->create();
        Site::factory()->create(['vps_id' => $vpsServer->id]);

        try {
            $vpsServer->delete();
            $this->fail('Expected foreign key constraint exception');
        } catch (\Illuminate\Database\QueryException $e) {
            // Expected behavior - foreign key constraint prevents deletion
            $this->assertTrue(true);
        }
    }

    #[Test]
    public function uuid_is_automatically_generated_on_creation()
    {
        $user = User::factory()->create();

        $this->assertNotNull($user->id);
        $this->assertIsString($user->id);
        $this->assertEquals(36, strlen($user->id));
    }

    #[Test]
    public function timestamps_are_automatically_set()
    {
        $organization = Organization::factory()->create();

        $this->assertNotNull($organization->created_at);
        $this->assertNotNull($organization->updated_at);
    }

    #[Test]
    public function updated_at_changes_on_model_update()
    {
        $organization = Organization::factory()->create();
        $originalUpdatedAt = $organization->updated_at;

        sleep(1);

        $organization->update(['name' => 'Updated Name']);

        $this->assertNotEquals($originalUpdatedAt, $organization->updated_at);
        $this->assertTrue($organization->updated_at->greaterThan($originalUpdatedAt));
    }

    #[Test]
    public function created_at_does_not_change_on_update()
    {
        $organization = Organization::factory()->create();
        $originalCreatedAt = $organization->created_at;

        sleep(1);

        $organization->update(['name' => 'Updated Name']);

        $this->assertEquals($originalCreatedAt->timestamp, $organization->created_at->timestamp);
    }

    #[Test]
    public function json_fields_are_properly_stored_and_retrieved()
    {
        $settings = ['theme' => 'dark', 'notifications' => true];
        $tenant = Tenant::factory()->create(['settings' => $settings]);

        $tenant->refresh();

        $this->assertEquals($settings, $tenant->settings);
        $this->assertIsArray($tenant->settings);
    }

    #[Test]
    public function encrypted_fields_are_encrypted_at_rest()
    {
        $vpsServer = VpsServer::factory()->create([
            'ssh_private_key' => 'secret-key',
        ]);

        // Check raw database value is encrypted
        $rawValue = DB::table('vps_servers')
            ->where('id', $vpsServer->id)
            ->value('ssh_private_key');

        $this->assertNotEquals('secret-key', $rawValue);
        $this->assertNotEmpty($rawValue);
    }

    #[Test]
    public function encrypted_fields_are_decrypted_on_retrieval()
    {
        $vpsServer = VpsServer::factory()->create([
            'ssh_private_key' => 'secret-key',
        ]);

        $vpsServer->refresh();

        $this->assertEquals('secret-key', $vpsServer->ssh_private_key);
    }

    #[Test]
    public function boolean_casts_convert_database_values()
    {
        $site = Site::factory()->create(['ssl_enabled' => 1]);

        $site = Site::withoutGlobalScopes()->find($site->id);

        $this->assertTrue($site->ssl_enabled);
        $this->assertIsBool($site->ssl_enabled);
    }

    #[Test]
    public function datetime_casts_convert_to_carbon_instances()
    {
        $user = User::factory()->create([
            'email_verified_at' => '2024-01-15 10:30:00',
        ]);

        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->email_verified_at);
    }

    #[Test]
    public function mass_assignment_protects_against_unauthorized_fields()
    {
        $data = [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'password',
            'id' => 'custom-id', // Not fillable
        ];

        $user = User::create($data);

        // ID should be auto-generated, not the one we provided
        $this->assertNotEquals('custom-id', $user->id);
    }
}
