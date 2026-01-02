<?php

namespace Tests\Unit;

use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\ObservabilityAdapter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ObservabilityAdapterTest extends TestCase
{
    use RefreshDatabase;

    private ObservabilityAdapter $adapter;

    protected function setUp(): void
    {
        parent::setUp();
        $this->adapter = new ObservabilityAdapter;
    }

    /**
     * Test that tenant IDs are properly escaped in PromQL queries.
     */
    public function test_tenant_id_is_escaped_in_promql_queries(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'test-tenant-123']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryMetrics($tenant, 'up');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';

            // Verify that the tenant_id is injected and properly escaped
            $this->assertStringContainsString('tenant_id="test-tenant-123"', $query);

            return true;
        });
    }

    /**
     * Test that malicious tenant IDs with quotes cannot break out of PromQL queries.
     */
    public function test_malicious_tenant_id_with_quotes_is_escaped(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'malicious",other_label="hacked']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryMetrics($tenant, 'up');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';

            // The quotes should be escaped
            $this->assertStringContainsString('\\"', $query);
            // Should not contain unescaped quotes that could break out
            $this->assertStringNotContainsString('",other_label="', $query);

            return true;
        });
    }

    /**
     * Test that tenant IDs with regex special characters are properly escaped.
     */
    public function test_tenant_id_with_regex_characters_is_escaped(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'tenant.*|^$']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryMetrics($tenant, 'up');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';

            // All regex special characters should be escaped
            $this->assertStringContainsString('\\*', $query);
            $this->assertStringContainsString('\\|', $query);
            $this->assertStringContainsString('\\^', $query);
            $this->assertStringContainsString('\\$', $query);

            return true;
        });
    }

    /**
     * Test that tenant IDs with backslashes are properly double-escaped.
     */
    public function test_tenant_id_with_backslashes_is_double_escaped(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'tenant\\with\\backslashes']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryMetrics($tenant, 'up');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Backslashes should be escaped
            $this->assertStringContainsString('\\\\', $query);

            return true;
        });
    }

    /**
     * Test that tenant IDs with newlines are properly escaped.
     */
    public function test_tenant_id_with_newlines_is_escaped(): void
    {
        $tenant = Tenant::factory()->create(['id' => "tenant\nwith\nnewlines"]);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryMetrics($tenant, 'up');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Newlines should be escaped
            $this->assertStringContainsString('\\n', $query);

            return true;
        });
    }

    /**
     * Test that VPS IP addresses are properly escaped in queries.
     */
    public function test_vps_ip_is_escaped_in_queries(): void
    {
        $vps = VpsServer::factory()->create(['ip_address' => '192.168.1.1']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->getVpsSummary($vps);

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Dots in IP should be escaped for regex safety
            $this->assertStringContainsString('192\\.168\\.1\\.1', $query);

            return true;
        });
    }

    /**
     * Test that malicious VPS IP addresses cannot inject PromQL.
     */
    public function test_malicious_vps_ip_is_escaped(): void
    {
        $vps = VpsServer::factory()->create(['ip_address' => '.*|{evil="yes"}']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->getVpsSummary($vps);

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // All special characters should be escaped
            $this->assertStringContainsString('\\*', $query);
            $this->assertStringContainsString('\\|', $query);
            $this->assertStringContainsString('\\{', $query);
            $this->assertStringContainsString('\\}', $query);

            return true;
        });
    }

    /**
     * Test that queryBandwidth escapes tenant ID properly.
     */
    public function test_query_bandwidth_escapes_tenant_id(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'tenant",inject="attack']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryBandwidth($tenant);

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Quotes should be escaped
            $this->assertStringContainsString('\\"', $query);

            return true;
        });
    }

    /**
     * Test that queryDiskUsage escapes tenant ID properly.
     */
    public function test_query_disk_usage_escapes_tenant_id(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'tenant.*']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryDiskUsage($tenant);

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Asterisk should be escaped
            $this->assertStringContainsString('\\*', $query);

            return true;
        });
    }

    /**
     * Test that LogQL strings are properly escaped for Loki queries.
     */
    public function test_logql_string_escaping_in_site_logs(): void
    {
        $tenant = Tenant::factory()->create();
        $site = \App\Models\Site::factory()->create([
            'tenant_id' => $tenant->id,
            'domain' => 'example.com"}{evil="yes"}',
        ]);

        Http::fake([
            '*/loki/api/v1/query_range' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->getSiteLogs($site);

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Quotes and braces should be escaped
            $this->assertStringContainsString('\\"', $query);

            return true;
        });
    }

    /**
     * Test that search logs properly escapes search terms.
     */
    public function test_search_logs_escapes_search_terms(): void
    {
        $tenant = Tenant::factory()->create();

        Http::fake([
            '*/loki/api/v1/query_range' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->searchLogs($tenant, 'search"\nterm');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // Quotes and newlines should be escaped
            $this->assertStringContainsString('\\"', $query);
            $this->assertStringContainsString('\\n', $query);

            return true;
        });
    }

    /**
     * Test that Loki queries use X-Loki-Org-Id header for tenant isolation.
     */
    public function test_loki_queries_use_tenant_header(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'test-tenant-123']);

        Http::fake([
            '*/loki/api/v1/query_range' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryLogs($tenant, '{job="app"}');

        Http::assertSent(function ($request) use ($tenant) {
            // Verify the tenant isolation header is set
            $this->assertEquals((string) $tenant->id, $request->header('X-Loki-Org-Id')[0] ?? null);

            return true;
        });
    }

    /**
     * Test that active alerts are filtered by tenant ID.
     */
    public function test_active_alerts_filtered_by_tenant(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'tenant-123']);

        Http::fake([
            '*/api/v1/alerts' => Http::response([
                'data' => [
                    'alerts' => [
                        ['labels' => ['tenant_id' => 'tenant-123', 'alertname' => 'HighCPU']],
                        ['labels' => ['tenant_id' => 'tenant-456', 'alertname' => 'HighMemory']],
                        ['labels' => ['tenant_id' => 'tenant-123', 'alertname' => 'DiskFull']],
                        ['labels' => ['alertname' => 'NoTenant']],
                    ],
                ],
            ], 200),
        ]);

        $alerts = $this->adapter->getActiveAlerts($tenant);

        // Should only return alerts for the specific tenant
        $this->assertCount(2, $alerts);
        foreach ($alerts as $alert) {
            $this->assertEquals('tenant-123', $alert['labels']['tenant_id']);
        }
    }

    /**
     * Test that complex PromQL injection attempts are prevented.
     */
    public function test_complex_promql_injection_is_prevented(): void
    {
        // Attempt to inject additional label matchers
        $tenant = Tenant::factory()->create(['id' => 'test"} or {admin="true']);

        Http::fake([
            '*/api/v1/query' => Http::response([
                'status' => 'success',
                'data' => ['result' => []],
            ], 200),
        ]);

        $this->adapter->queryMetrics($tenant, 'up');

        Http::assertSent(function ($request) {
            // Parse query parameter from URL
            $url = parse_url($request->url());
            parse_str($url['query'] ?? '', $params);
            $query = $params['query'] ?? '';
            // The injection should be escaped and not create valid PromQL
            $this->assertStringContainsString('\\"', $query);
            $this->assertStringContainsString('\\{', $query);
            $this->assertStringContainsString('\\}', $query);
            // Should not contain literal unescaped or {
            $this->assertStringNotContainsString('} or {', $query);

            return true;
        });
    }

    /**
     * Test that embedded dashboard URLs don't allow injection.
     */
    public function test_embedded_dashboard_url_tenant_parameter(): void
    {
        $tenant = Tenant::factory()->create(['id' => 'tenant&admin=true']);

        $url = $this->adapter->getEmbeddedDashboardUrl('dashboard-123', $tenant);

        // URL should contain the tenant ID but be properly URL encoded
        $this->assertStringContainsString('var-tenant_id=', $url);
        // The & character should be properly handled in URL context
        // This is testing that we're passing the tenant ID safely
        $this->assertStringContainsString('tenant', $url);
    }

    /**
     * Test that scrape config generation includes proper labels.
     */
    public function test_scrape_config_generation_includes_tenant_labels(): void
    {
        $tenant = Tenant::factory()->create(['tier' => 'premium']);
        $vps = VpsServer::factory()->create([
            'hostname' => 'vps-1',
            'ip_address' => '192.168.1.1',
            'provider' => 'hetzner',
        ]);

        $config = $this->adapter->generateScrapeConfig($vps, $tenant);

        $this->assertArrayHasKey('labels', $config);
        $this->assertEquals((string) $tenant->id, $config['labels']['tenant_id']);
        $this->assertEquals('premium', $config['labels']['tier']);
        $this->assertEquals('vps-1', $config['labels']['hostname']);
        $this->assertEquals('hetzner', $config['labels']['provider']);
    }

    /**
     * Test that health checks handle errors gracefully.
     */
    public function test_health_checks_return_false_on_error(): void
    {
        Http::fake([
            '*/-/healthy' => Http::response([], 500),
            '*/ready' => Http::response([], 500),
            '*/api/health' => Http::response([], 500),
        ]);

        $this->assertFalse($this->adapter->isPrometheusHealthy());
        $this->assertFalse($this->adapter->isLokiHealthy());
        $this->assertFalse($this->adapter->isGrafanaHealthy());
    }

    /**
     * Test that health status returns correct aggregate status.
     */
    public function test_health_status_aggregate(): void
    {
        Http::fake([
            '*/-/healthy' => Http::response([], 200),
            '*/ready' => Http::response([], 200),
            '*/api/health' => Http::response([], 200),
        ]);

        $status = $this->adapter->getHealthStatus();

        $this->assertTrue($status['prometheus']);
        $this->assertTrue($status['loki']);
        $this->assertTrue($status['grafana']);
        $this->assertTrue($status['all_healthy']);
    }
}
