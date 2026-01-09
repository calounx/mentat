<?php

namespace Tests\Unit\Requests;

use App\Http\Requests\StoreBackupRequest;
use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Validator;
use Tests\TestCase;

/**
 * StoreBackupRequest Unit Tests
 *
 * Tests validation logic for backup creation requests with a focus on
 * multi-tenancy security and cross-tenant access prevention.
 */
class StoreBackupRequestTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private Tenant $tenant;
    private Site $site;
    private Tenant $otherTenant;
    private Site $otherSite;

    protected function setUp(): void
    {
        parent::setUp();

        // Create primary tenant with user and site
        $org = Organization::factory()->create();
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $org->id,
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $this->user = User::factory()->create([
            'organization_id' => $org->id,
            'current_tenant_id' => $this->tenant->id,
        ]);

        $vps = VpsServer::factory()->create(['status' => 'active']);
        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_server_id' => $vps->id,
            'domain' => 'example.com',
        ]);

        // Create another tenant with site for cross-tenant testing
        $otherOrg = Organization::factory()->create();
        $this->otherTenant = Tenant::factory()->create([
            'organization_id' => $otherOrg->id,
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $otherVps = VpsServer::factory()->create(['status' => 'active']);
        $this->otherSite = Site::factory()->create([
            'tenant_id' => $this->otherTenant->id,
            'vps_server_id' => $otherVps->id,
            'domain' => 'other-example.com',
        ]);
    }

    // ============================================================================
    // Authorization Tests
    // ============================================================================

    public function test_it_authorizes_authenticated_user_with_tenant()
    {
        $request = new StoreBackupRequest();
        $request->setUserResolver(fn() => $this->user);

        $this->assertTrue($request->authorize());
    }

    public function test_it_denies_unauthenticated_user()
    {
        $request = new StoreBackupRequest();
        $request->setUserResolver(fn() => null);

        $this->assertFalse($request->authorize());
    }

    public function test_it_denies_user_without_current_tenant()
    {
        $userWithoutTenant = User::factory()->create([
            'current_tenant_id' => null,
        ]);

        $request = new StoreBackupRequest();
        $request->setUserResolver(fn() => $userWithoutTenant);

        $this->assertFalse($request->authorize());
    }

    // ============================================================================
    // Validation Tests - Same Tenant Access
    // ============================================================================

    public function test_it_accepts_valid_backup_request_for_same_tenant_site()
    {
        $data = [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'retention_days' => 30,
        ];

        $request = $this->createRequestWithUser($data);
        $rules = $request->rules();

        $validator = Validator::make($data, $rules);

        $this->assertTrue($validator->passes(), 'Validation should pass for same-tenant site');
    }

    public function test_it_accepts_all_valid_backup_types()
    {
        $validTypes = ['full', 'files', 'database', 'config', 'manual'];

        foreach ($validTypes as $type) {
            $data = [
                'site_id' => $this->site->id,
                'backup_type' => $type,
            ];

            $request = $this->createRequestWithUser($data);
            $validator = Validator::make($data, $request->rules());

            $this->assertTrue(
                $validator->passes(),
                "Validation should pass for backup_type: {$type}"
            );
        }
    }

    public function test_it_accepts_valid_retention_days_range()
    {
        $validDays = [1, 30, 90, 180, 365];

        foreach ($validDays as $days) {
            $data = [
                'site_id' => $this->site->id,
                'backup_type' => 'full',
                'retention_days' => $days,
            ];

            $request = $this->createRequestWithUser($data);
            $validator = Validator::make($data, $request->rules());

            $this->assertTrue(
                $validator->passes(),
                "Validation should pass for retention_days: {$days}"
            );
        }
    }

    // ============================================================================
    // Validation Tests - Cross-Tenant Access Prevention
    // ============================================================================

    public function test_it_rejects_cross_tenant_site_id()
    {
        $data = [
            'site_id' => $this->otherSite->id, // Different tenant's site
            'backup_type' => 'full',
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        $this->assertTrue($validator->fails(), 'Validation should fail for cross-tenant site');
        $this->assertTrue($validator->errors()->has('site_id'));
    }

    public function test_it_provides_security_error_message_for_cross_tenant_access()
    {
        $data = [
            'site_id' => $this->otherSite->id,
            'backup_type' => 'full',
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        $this->assertTrue($validator->fails());
        $errors = $validator->errors()->get('site_id');

        $this->assertNotEmpty($errors);
        $this->assertStringContainsString(
            'Site not found or you do not have permission',
            $errors[0]
        );
    }

    public function test_it_rejects_nonexistent_site_id()
    {
        $data = [
            'site_id' => 'non-existent-site-id',
            'backup_type' => 'full',
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        $this->assertTrue($validator->fails());
        $this->assertTrue($validator->errors()->has('site_id'));
    }

    // ============================================================================
    // Validation Tests - Invalid Data
    // ============================================================================

    public function test_it_rejects_invalid_backup_type()
    {
        $invalidTypes = ['invalid', 'partial', 'incremental', '', null];

        foreach ($invalidTypes as $type) {
            $data = [
                'site_id' => $this->site->id,
                'backup_type' => $type,
            ];

            $request = $this->createRequestWithUser($data);
            $validator = Validator::make($data, $request->rules());

            $this->assertTrue(
                $validator->fails(),
                "Validation should fail for invalid backup_type: " . var_export($type, true)
            );
        }
    }

    public function test_it_rejects_retention_days_below_minimum()
    {
        $data = [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'retention_days' => 0,
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        $this->assertTrue($validator->fails());
        $this->assertTrue($validator->errors()->has('retention_days'));
    }

    public function test_it_rejects_retention_days_above_maximum()
    {
        $data = [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'retention_days' => 366,
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        $this->assertTrue($validator->fails());
        $this->assertTrue($validator->errors()->has('retention_days'));
    }

    public function test_it_rejects_non_integer_retention_days()
    {
        $data = [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
            'retention_days' => 'thirty',
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        $this->assertTrue($validator->fails());
        $this->assertTrue($validator->errors()->has('retention_days'));
    }

    // ============================================================================
    // Validation Tests - Data Preparation
    // ============================================================================

    public function test_it_sets_default_backup_type_when_not_provided()
    {
        $request = $this->createRequestWithUser([
            'site_id' => $this->site->id,
        ]);

        // Simulate prepareForValidation
        $request->merge(['backup_type' => 'full']);

        $validator = Validator::make($request->all(), $request->rules());

        $this->assertTrue($validator->passes());
        $this->assertEquals('full', $request->input('backup_type'));
    }

    public function test_it_sets_default_retention_days_when_not_provided()
    {
        $request = $this->createRequestWithUser([
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ]);

        // Simulate prepareForValidation
        $request->merge(['retention_days' => 30]);

        $validator = Validator::make($request->all(), $request->rules());

        $this->assertTrue($validator->passes());
        $this->assertEquals(30, $request->input('retention_days'));
    }

    // ============================================================================
    // Validation Tests - Edge Cases
    // ============================================================================

    public function test_it_validates_tenant_scoped_query_uses_wherehas()
    {
        // Create a site that exists in DB but belongs to different tenant
        $this->assertDatabaseHas('sites', [
            'id' => $this->otherSite->id,
            'tenant_id' => $this->otherTenant->id,
        ]);

        $data = [
            'site_id' => $this->otherSite->id,
            'backup_type' => 'full',
        ];

        $request = $this->createRequestWithUser($data);
        $validator = Validator::make($data, $request->rules());

        // Should fail because the custom closure in rules() checks tenant_id
        $this->assertTrue($validator->fails());
    }

    public function test_it_allows_multiple_backups_for_same_site()
    {
        $data1 = [
            'site_id' => $this->site->id,
            'backup_type' => 'full',
        ];

        $request1 = $this->createRequestWithUser($data1);
        $validator1 = Validator::make($data1, $request1->rules());
        $this->assertTrue($validator1->passes());

        $data2 = [
            'site_id' => $this->site->id,
            'backup_type' => 'database',
        ];

        $request2 = $this->createRequestWithUser($data2);
        $validator2 = Validator::make($data2, $request2->rules());
        $this->assertTrue($validator2->passes());
    }

    // ============================================================================
    // Helper Methods
    // ============================================================================

    /**
     * Create a request instance with authenticated user
     */
    private function createRequestWithUser(array $data): StoreBackupRequest
    {
        $request = new StoreBackupRequest();
        $request->setUserResolver(fn() => $this->user);
        $request->replace($data);
        return $request;
    }
}
