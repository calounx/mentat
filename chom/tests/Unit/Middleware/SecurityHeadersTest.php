<?php

declare(strict_types=1);

namespace Tests\Unit\Middleware;

use App\Http\Middleware\SecurityHeaders;
use Illuminate\Http\Request;
use Tests\TestCase;

/**
 * Test SecurityHeaders middleware
 */
class SecurityHeadersTest extends TestCase
{
    /**
     * Test middleware adds security headers
     */
    public function test_middleware_adds_security_headers(): void
    {
        $middleware = new SecurityHeaders;
        $request = Request::create('https://example.com/'); // Use HTTPS to test HSTS

        $response = $middleware->handle($request, fn ($req) => response('OK'));

        $this->assertEquals('nosniff', $response->headers->get('X-Content-Type-Options'));
        $this->assertEquals('DENY', $response->headers->get('X-Frame-Options'));
        $this->assertNotNull($response->headers->get('Content-Security-Policy'));
        $this->assertNotNull($response->headers->get('Strict-Transport-Security'));
        $this->assertNotNull($response->headers->get('Referrer-Policy'));
    }

    /**
     * Test CSP header is properly configured
     */
    public function test_csp_header_configured_correctly(): void
    {
        $middleware = new SecurityHeaders;
        $request = Request::create('/');

        $response = $middleware->handle($request, fn ($req) => response('OK'));
        $csp = $response->headers->get('Content-Security-Policy');

        $this->assertStringContainsString("default-src 'self'", $csp);
        $this->assertStringContainsString('script-src', $csp);
        $this->assertStringContainsString('style-src', $csp);
    }

    /**
     * Test HSTS header for HTTPS
     */
    public function test_hsts_header_for_https(): void
    {
        $middleware = new SecurityHeaders;
        $request = Request::create('https://example.com');

        $response = $middleware->handle($request, fn ($req) => response('OK'));
        $hsts = $response->headers->get('Strict-Transport-Security');

        $this->assertStringContainsString('max-age=', $hsts);
        $this->assertStringContainsString('includeSubDomains', $hsts);
    }
}
