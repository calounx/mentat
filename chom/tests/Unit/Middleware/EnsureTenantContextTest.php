<?php

declare(strict_types=1);

namespace Tests\Unit\Middleware;

use App\Http\Middleware\EnsureTenantContext;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Tests\TestCase;

/**
 * Test EnsureTenantContext middleware
 *
 * @package Tests\Unit\Middleware
 */
class EnsureTenantContextTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test middleware sets tenant context
     *
     * @return void
     */
    public function test_middleware_sets_tenant_context(): void
    {
        $user = User::factory()->create();
        $middleware = new EnsureTenantContext();

        $request = Request::create('/api/v1/sites');
        $request->setUserResolver(fn() => $user);

        $response = $middleware->handle($request, fn($req) => response('OK'));

        $this->assertEquals(200, $response->getStatusCode());
        $this->assertEquals($user->id, app('tenant_id'));
    }

    /**
     * Test middleware rejects unauthenticated requests
     *
     * @return void
     */
    public function test_middleware_rejects_unauthenticated_requests(): void
    {
        $middleware = new EnsureTenantContext();
        $request = Request::create('/api/v1/sites');

        $response = $middleware->handle($request, fn($req) => response('OK'));

        $this->assertEquals(401, $response->getStatusCode());
    }
}
