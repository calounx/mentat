<?php

declare(strict_types=1);

namespace Tests\Unit\Middleware;

use App\Http\Middleware\SecurityHeadersMiddleware;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Tests\TestCase;

class SecurityHeadersMiddlewareTest extends TestCase
{
    private SecurityHeadersMiddleware $middleware;

    protected function setUp(): void
    {
        parent::setUp();
        $this->middleware = new SecurityHeadersMiddleware();
    }

    public function test_adds_all_required_security_headers(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $requiredHeaders = [
            'X-Content-Type-Options',
            'X-Frame-Options',
            'X-XSS-Protection',
            'Strict-Transport-Security',
            'Referrer-Policy',
            'Permissions-Policy',
            'Content-Security-Policy',
        ];

        foreach ($requiredHeaders as $header) {
            $this->assertTrue(
                $response->headers->has($header),
                "Missing required security header: {$header}"
            );
        }
    }

    public function test_sets_correct_x_content_type_options(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals(
            'nosniff',
            $response->headers->get('X-Content-Type-Options')
        );
    }

    public function test_sets_correct_x_frame_options(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals(
            'DENY',
            $response->headers->get('X-Frame-Options')
        );
    }

    public function test_sets_correct_x_xss_protection(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals(
            '1; mode=block',
            $response->headers->get('X-XSS-Protection')
        );
    }

    public function test_sets_strict_transport_security_with_correct_max_age(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $hsts = $response->headers->get('Strict-Transport-Security');

        $this->assertStringContainsString('max-age=', $hsts);
        $this->assertStringContainsString('includeSubDomains', $hsts);

        // Extract max-age value
        preg_match('/max-age=(\d+)/', $hsts, $matches);
        $maxAge = (int) ($matches[1] ?? 0);

        // Should be at least 1 year (31536000 seconds)
        $this->assertGreaterThanOrEqual(31536000, $maxAge);
    }

    public function test_includes_preload_in_hsts_header(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $hsts = $response->headers->get('Strict-Transport-Security');

        $this->assertStringContainsString('preload', $hsts);
    }

    public function test_sets_referrer_policy(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $referrerPolicy = $response->headers->get('Referrer-Policy');

        $this->assertContains($referrerPolicy, [
            'strict-origin-when-cross-origin',
            'strict-origin',
            'no-referrer-when-downgrade',
        ]);
    }

    public function test_sets_permissions_policy(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $permissionsPolicy = $response->headers->get('Permissions-Policy');

        // Check for restricted features
        $restrictedFeatures = [
            'geolocation',
            'microphone',
            'camera',
            'payment',
        ];

        foreach ($restrictedFeatures as $feature) {
            $this->assertStringContainsString(
                $feature,
                $permissionsPolicy,
                "Permissions-Policy should restrict {$feature}"
            );
        }
    }

    public function test_sets_comprehensive_content_security_policy(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        // Required CSP directives
        $requiredDirectives = [
            "default-src 'self'",
            "script-src",
            "style-src",
            "img-src",
            "font-src",
            "connect-src",
            "frame-ancestors 'none'",
            "base-uri 'self'",
            "form-action 'self'",
        ];

        foreach ($requiredDirectives as $directive) {
            $this->assertStringContainsString(
                $directive,
                $csp,
                "CSP should contain directive: {$directive}"
            );
        }
    }

    public function test_csp_disallows_unsafe_inline_by_default(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        // Should use nonce or hash instead of 'unsafe-inline'
        $this->assertStringNotContainsString(
            "script-src 'unsafe-inline'",
            $csp,
            'CSP should not allow unsafe-inline for scripts'
        );
    }

    public function test_csp_includes_nonce_for_scripts(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        // Should include nonce for inline scripts
        $this->assertMatchesRegularExpression(
            "/'nonce-[A-Za-z0-9+\/=]+'/",
            $csp,
            'CSP should include nonce for scripts'
        );
    }

    public function test_csp_prevents_frame_embedding(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        $this->assertStringContainsString(
            "frame-ancestors 'none'",
            $csp,
            'CSP should prevent frame embedding'
        );
    }

    public function test_does_not_override_existing_headers(): void
    {
        $request = Request::create('/test', 'GET');
        $existingResponse = new Response('OK', 200);
        $existingResponse->headers->set('X-Custom-Header', 'custom-value');

        $next = fn($req) => $existingResponse;

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals('custom-value', $response->headers->get('X-Custom-Header'));
    }

    public function test_headers_are_case_insensitive(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        // Laravel normalizes header names
        $this->assertTrue($response->headers->has('x-content-type-options'));
        $this->assertTrue($response->headers->has('X-Content-Type-Options'));
    }

    public function test_applies_headers_to_all_response_types(): void
    {
        $request = Request::create('/test', 'GET');

        // Test with JSON response
        $jsonNext = fn($req) => response()->json(['data' => 'test']);
        $jsonResponse = $this->middleware->handle($request, $jsonNext);

        $this->assertTrue($jsonResponse->headers->has('X-Content-Type-Options'));
        $this->assertTrue($jsonResponse->headers->has('Content-Security-Policy'));

        // Test with redirect response
        $redirectNext = fn($req) => redirect('/other');
        $redirectResponse = $this->middleware->handle($request, $redirectNext);

        $this->assertTrue($redirectResponse->headers->has('X-Content-Type-Options'));
        $this->assertTrue($redirectResponse->headers->has('Content-Security-Policy'));
    }

    public function test_headers_applied_to_error_responses(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('Not Found', 404);

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals(404, $response->getStatusCode());
        $this->assertTrue($response->headers->has('X-Content-Type-Options'));
        $this->assertTrue($response->headers->has('Content-Security-Policy'));
    }

    public function test_csp_allows_trusted_cdn_sources(): void
    {
        config(['app.cdn_hosts' => ['cdn.example.com', 'fonts.googleapis.com']]);

        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        // Should include configured CDN hosts
        $this->assertStringContainsString('cdn.example.com', $csp);
        $this->assertStringContainsString('fonts.googleapis.com', $csp);
    }

    public function test_strict_csp_for_production_environment(): void
    {
        app()->detectEnvironment(fn() => 'production');

        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        // Production should have stricter CSP
        $this->assertStringContainsString("default-src 'self'", $csp);
        $this->assertStringNotContainsString('unsafe-eval', $csp);
    }

    public function test_performance_impact_is_minimal(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $startTime = microtime(true);

        for ($i = 0; $i < 1000; $i++) {
            $this->middleware->handle($request, $next);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000; // Convert to milliseconds

        // Adding headers should take less than 100ms for 1000 requests
        $this->assertLessThan(100, $duration, "Security headers middleware took {$duration}ms for 1000 requests");
    }

    public function test_no_information_leakage_in_headers(): void
    {
        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        // Should not reveal framework version
        $this->assertFalse($response->headers->has('X-Powered-By'));

        // Should not reveal server information
        $serverHeader = $response->headers->get('Server', '');
        $this->assertStringNotContainsString('PHP', $serverHeader);
        $this->assertStringNotContainsString('Laravel', $serverHeader);
    }

    public function test_csp_report_uri_configured_in_production(): void
    {
        app()->detectEnvironment(fn() => 'production');
        config(['security.csp_report_uri' => 'https://example.com/csp-report']);

        $request = Request::create('/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $csp = $response->headers->get('Content-Security-Policy');

        $this->assertStringContainsString(
            'report-uri https://example.com/csp-report',
            $csp
        );
    }
}
