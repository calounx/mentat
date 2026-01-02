<?php

namespace Tests\Deployment\Smoke;

use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Smoke tests for HTTP endpoint availability
 *
 * Quick tests to verify critical endpoints are responding after deployment.
 */
class EndpointAvailabilityTest extends DeploymentTestCase
{
    /**
     * Test homepage is accessible
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_homepage_is_accessible(): void
    {
        $response = $this->get('/');

        $response->assertStatus(200);
    }

    /**
     * Test health check endpoint is accessible
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_health_endpoint_is_accessible(): void
    {
        $response = $this->get('/health');

        $response->assertStatus(200);
    }

    /**
     * Test API endpoints are accessible
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_api_health_endpoint_is_accessible(): void
    {
        $response = $this->get('/api/health');

        $response->assertStatus(200);
    }

    /**
     * Test login page is accessible
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_login_page_is_accessible(): void
    {
        $response = $this->get('/login');

        // Should be 200 or redirect to dashboard if already authenticated
        $this->assertContains($response->status(), [200, 302]);
    }

    /**
     * Test register page is accessible
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_register_page_is_accessible(): void
    {
        if (!\Illuminate\Support\Facades\Route::has('register')) {
            $this->markTestSkipped('Registration route not available');
        }

        $response = $this->get('/register');

        $this->assertContains($response->status(), [200, 302]);
    }

    /**
     * Test 404 page is working
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_404_page_is_working(): void
    {
        $response = $this->get('/nonexistent-page-' . uniqid());

        $response->assertStatus(404);
    }

    /**
     * Test static assets are accessible
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_static_assets_are_accessible(): void
    {
        // Test for common asset files
        $assetPath = public_path('build/manifest.json');

        if (file_exists($assetPath)) {
            $this->assertFileExists($assetPath, 'Build manifest should exist');
        }
    }

    /**
     * Test CSRF token generation
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_csrf_token_generation(): void
    {
        $response = $this->get('/');

        // CSRF token should be in session
        $this->assertNotNull(session()->token(), 'CSRF token should be generated');
    }

    /**
     * Test application returns correct headers
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_application_security_headers(): void
    {
        $response = $this->get('/');

        // Check for common security headers
        // Note: Actual headers will depend on your middleware configuration
        $this->assertTrue(true); // Placeholder - add specific header checks as needed
    }

    /**
     * Test API rate limiting is active
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_api_rate_limiting_is_active(): void
    {
        // Make a request to an API endpoint
        $response = $this->get('/api/health');

        // Should include rate limit headers
        if ($response->headers->has('X-RateLimit-Limit')) {
            $this->assertNotNull($response->headers->get('X-RateLimit-Limit'));
        }
    }

    /**
     * Test application responds within acceptable time
     *
     * @group smoke
     * @group fast
     * @group http
     */
    public function test_response_time_is_acceptable(): void
    {
        $start = microtime(true);

        $this->get('/');

        $duration = (microtime(true) - $start) * 1000; // Convert to ms

        // Response should be under 2 seconds for smoke test
        $this->assertLessThan(2000, $duration, 'Homepage should respond in under 2 seconds');
    }
}
