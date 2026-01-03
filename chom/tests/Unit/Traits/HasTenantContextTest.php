<?php

declare(strict_types=1);

namespace Tests\Unit\Traits;

use App\Http\Traits\HasTenantContext;
use Illuminate\Http\Request;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;
use Mockery;

/**
 * HasTenantContextTest
 *
 * Comprehensive test suite for the HasTenantContext trait.
 * Tests tenant/organization resolution, caching, authorization helpers, and edge cases.
 *
 * @package Tests\Unit\Traits
 * @covers  \App\Http\Traits\HasTenantContext
 */
class HasTenantContextTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test class that uses the trait for testing purposes.
     */
    private object $traitUser;

    /**
     * Setup before each test.
     */
    protected function setUp(): void
    {
        parent::setUp();

        // Create an anonymous class that uses the trait for testing
        $this->traitUser = new class {
            use HasTenantContext;

            // Expose protected methods for testing
            public function callGetTenant(Request $request)
            {
                return $this->getTenant($request);
            }

            public function callGetOrganization(Request $request)
            {
                return $this->getOrganization($request);
            }

            public function callRequireRole(Request $request, $roles): void
            {
                $this->requireRole($request, $roles);
            }

            public function callRequireAdmin(Request $request): void
            {
                $this->requireAdmin($request);
            }

            public function callRequireOwner(Request $request): void
            {
                $this->requireOwner($request);
            }

            public function callValidateTenantOwnership(Request $request, $resource, string $field = 'tenant_id'): void
            {
                $this->validateTenantOwnership($request, $resource, $field);
            }
        };
    }

    /**
     * Cleanup after each test.
     */
    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    // ========================================================================
    // getTenant() Tests
    // ========================================================================

    /**
     * Test that getTenant() throws 401 when user is not authenticated.
     */
    public function test_get_tenant_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        $request = Request::create('/test');
        $request->setUserResolver(fn() => null);

        $this->traitUser->callGetTenant($request);
    }

    /**
     * Test that getTenant() throws 403 when tenant is not found.
     */
    public function test_get_tenant_throws_403_when_tenant_not_found(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('No active tenant found.');

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn(null);
        $user->tenant = null;

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callGetTenant($request);
    }

    /**
     * Test that getTenant() throws 403 when tenant is inactive.
     */
    public function test_get_tenant_throws_403_when_tenant_inactive(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Tenant is not active.');

        $tenant = Mockery::mock();
        $tenant->shouldReceive('isActive')->andReturn(false);

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn($tenant);

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callGetTenant($request);
    }

    /**
     * Test that getTenant() returns active tenant successfully.
     */
    public function test_get_tenant_returns_active_tenant(): void
    {
        $tenant = Mockery::mock();
        $tenant->id = 'tenant-uuid-123';
        $tenant->name = 'Test Tenant';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn($tenant);

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $result = $this->traitUser->callGetTenant($request);

        $this->assertSame($tenant, $result);
        $this->assertEquals('tenant-uuid-123', $result->id);
    }

    /**
     * Test that getTenant() falls back to user->tenant property.
     */
    public function test_get_tenant_uses_fallback_property(): void
    {
        $tenant = Mockery::mock();
        $tenant->id = 'tenant-uuid-456';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = new class {
            public $tenant;
        };
        $user->tenant = $tenant;

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $result = $this->traitUser->callGetTenant($request);

        $this->assertSame($tenant, $result);
    }

    // ========================================================================
    // getOrganization() Tests
    // ========================================================================

    /**
     * Test that getOrganization() throws 401 when unauthenticated.
     */
    public function test_get_organization_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        $request = Request::create('/test');
        $request->setUserResolver(fn() => null);

        $this->traitUser->callGetOrganization($request);
    }

    /**
     * Test that getOrganization() throws 403 when organization not found.
     */
    public function test_get_organization_throws_403_when_not_found(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('No organization found.');

        $user = new class {
            public $organization = null;
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callGetOrganization($request);
    }

    /**
     * Test that getOrganization() returns organization successfully.
     */
    public function test_get_organization_returns_organization(): void
    {
        $organization = Mockery::mock();
        $organization->id = 'org-uuid-789';
        $organization->name = 'Test Organization';

        $user = new class {
            public $organization;
        };
        $user->organization = $organization;

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $result = $this->traitUser->callGetOrganization($request);

        $this->assertSame($organization, $result);
        $this->assertEquals('org-uuid-789', $result->id);
    }

    // ========================================================================
    // requireRole() Tests
    // ========================================================================

    /**
     * Test requireRole() throws 401 when unauthenticated.
     */
    public function test_require_role_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        $request = Request::create('/test');
        $request->setUserResolver(fn() => null);

        $this->traitUser->callRequireRole($request, 'admin');
    }

    /**
     * Test requireRole() throws 403 when user doesn't have required role.
     */
    public function test_require_role_throws_403_when_role_missing(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('You do not have permission to perform this action.');

        $user = new class {
            public $role = 'viewer';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callRequireRole($request, 'admin');
    }

    /**
     * Test requireRole() passes when user has required role.
     */
    public function test_require_role_passes_with_correct_role(): void
    {
        $user = new class {
            public $role = 'admin';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        // Should not throw exception
        $this->traitUser->callRequireRole($request, 'admin');
        $this->assertTrue(true); // Assert test reached this point
    }

    /**
     * Test requireRole() accepts multiple roles as array.
     */
    public function test_require_role_accepts_array_of_roles(): void
    {
        $user = new class {
            public $role = 'member';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        // Should not throw exception when user role matches one of the allowed roles
        $this->traitUser->callRequireRole($request, ['admin', 'member', 'viewer']);
        $this->assertTrue(true);
    }

    // ========================================================================
    // requireAdmin() Tests
    // ========================================================================

    /**
     * Test requireAdmin() throws 401 when unauthenticated.
     */
    public function test_require_admin_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        $request = Request::create('/test');
        $request->setUserResolver(fn() => null);

        $this->traitUser->callRequireAdmin($request);
    }

    /**
     * Test requireAdmin() throws 403 when user is not admin.
     */
    public function test_require_admin_throws_403_when_not_admin(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('You do not have permission to perform this action.');

        $user = new class {
            public $role = 'viewer';

            public function isAdmin(): bool
            {
                return false;
            }
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callRequireAdmin($request);
    }

    /**
     * Test requireAdmin() passes when user is admin.
     */
    public function test_require_admin_passes_when_user_is_admin(): void
    {
        $user = new class {
            public $role = 'admin';

            public function isAdmin(): bool
            {
                return true;
            }
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callRequireAdmin($request);
        $this->assertTrue(true);
    }

    /**
     * Test requireAdmin() falls back to role check.
     */
    public function test_require_admin_falls_back_to_role_check(): void
    {
        $user = new class {
            public $role = 'owner';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callRequireAdmin($request);
        $this->assertTrue(true);
    }

    // ========================================================================
    // requireOwner() Tests
    // ========================================================================

    /**
     * Test requireOwner() throws 401 when unauthenticated.
     */
    public function test_require_owner_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        $request = Request::create('/test');
        $request->setUserResolver(fn() => null);

        $this->traitUser->callRequireOwner($request);
    }

    /**
     * Test requireOwner() throws 403 when user is not owner.
     */
    public function test_require_owner_throws_403_when_not_owner(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Only the organization owner can perform this action.');

        $user = new class {
            public $role = 'admin';

            public function isOwner(): bool
            {
                return false;
            }
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callRequireOwner($request);
    }

    /**
     * Test requireOwner() passes when user is owner.
     */
    public function test_require_owner_passes_when_user_is_owner(): void
    {
        $user = new class {
            public $role = 'owner';

            public function isOwner(): bool
            {
                return true;
            }
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callRequireOwner($request);
        $this->assertTrue(true);
    }

    // ========================================================================
    // validateTenantOwnership() Tests
    // ========================================================================

    /**
     * Test validateTenantOwnership() throws 403 when resource doesn't belong to tenant.
     */
    public function test_validate_tenant_ownership_throws_403_for_wrong_tenant(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('You do not have access to this resource.');

        $tenant = Mockery::mock();
        $tenant->id = 'tenant-123';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn($tenant);

        $resource = new class {
            public $tenant_id = 'different-tenant-456';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callValidateTenantOwnership($request, $resource);
    }

    /**
     * Test validateTenantOwnership() passes when resource belongs to tenant.
     */
    public function test_validate_tenant_ownership_passes_for_correct_tenant(): void
    {
        $tenant = Mockery::mock();
        $tenant->id = 'tenant-123';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn($tenant);

        $resource = new class {
            public $tenant_id = 'tenant-123';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callValidateTenantOwnership($request, $resource);
        $this->assertTrue(true);
    }

    /**
     * Test validateTenantOwnership() works with array resources.
     */
    public function test_validate_tenant_ownership_works_with_arrays(): void
    {
        $tenant = Mockery::mock();
        $tenant->id = 'tenant-123';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn($tenant);

        $resource = ['tenant_id' => 'tenant-123', 'name' => 'Test Resource'];

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callValidateTenantOwnership($request, $resource);
        $this->assertTrue(true);
    }

    /**
     * Test validateTenantOwnership() works with custom field name.
     */
    public function test_validate_tenant_ownership_works_with_custom_field(): void
    {
        $tenant = Mockery::mock();
        $tenant->id = 'tenant-999';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = Mockery::mock();
        $user->shouldReceive('currentTenant')->andReturn($tenant);

        $resource = new class {
            public $owner_id = 'tenant-999';
        };

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        $this->traitUser->callValidateTenantOwnership($request, $resource, 'owner_id');
        $this->assertTrue(true);
    }

    // ========================================================================
    // Edge Cases and Integration Tests
    // ========================================================================

    /**
     * Test that multiple calls to getTenant() use cached value.
     *
     * Note: This test verifies caching behavior by ensuring currentTenant()
     * is only called once even when getTenant() is called multiple times.
     */
    public function test_get_tenant_caches_result_for_request_lifecycle(): void
    {
        $tenant = Mockery::mock();
        $tenant->id = 'tenant-cached';
        $tenant->shouldReceive('isActive')->andReturn(true);

        $user = Mockery::mock();
        // Should only be called once due to caching
        $user->shouldReceive('currentTenant')->once()->andReturn($tenant);

        $request = Request::create('/test');
        $request->setUserResolver(fn() => $user);

        // First call - should invoke currentTenant()
        $result1 = $this->traitUser->callGetTenant($request);

        // Second call - should use cached value
        $result2 = $this->traitUser->callGetTenant($request);

        $this->assertSame($result1, $result2);
        $this->assertEquals('tenant-cached', $result1->id);
    }

    /**
     * Test error messages are descriptive and helpful.
     */
    public function test_error_messages_are_descriptive(): void
    {
        try {
            $request = Request::create('/test');
            $request->setUserResolver(fn() => null);
            $this->traitUser->callGetTenant($request);
            $this->fail('Expected HttpException was not thrown');
        } catch (HttpException $e) {
            $this->assertStringContainsString('Unauthenticated', $e->getMessage());
            $this->assertEquals(401, $e->getStatusCode());
        }
    }
}
