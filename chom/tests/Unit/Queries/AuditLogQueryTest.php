<?php

declare(strict_types=1);

namespace Tests\Unit\Queries;

use App\Queries\AuditLogQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class AuditLogQueryTest extends TestCase
{
    use RefreshDatabase;

    private string $userId;
    private string $organizationId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->organizationId = (string) \Illuminate\Support\Str::uuid();
        $this->userId = (string) \Illuminate\Support\Str::uuid();

        // Create test organization
        DB::table('organizations')->insert([
            'id' => $this->organizationId,
            'name' => 'Test Org',
            'slug' => 'test-org',
            'billing_email' => 'billing@test.com',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test user
        DB::table('users')->insert([
            'id' => $this->userId,
            'organization_id' => $this->organizationId,
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => bcrypt('password'),
            'role' => 'admin',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test audit logs
        DB::table('audit_logs')->insert([
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'organization_id' => $this->organizationId,
                'user_id' => $this->userId,
                'action' => 'user.login',
                'resource_type' => 'user',
                'resource_id' => $this->userId,
                'ip_address' => '192.168.1.1',
                'metadata' => json_encode(['browser' => 'Chrome']),
                'created_at' => now()->subDays(5),
                'updated_at' => now()->subDays(5),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'organization_id' => $this->organizationId,
                'user_id' => $this->userId,
                'action' => 'site.created',
                'resource_type' => 'site',
                'resource_id' => \Illuminate\Support\Str::uuid(),
                'ip_address' => '192.168.1.1',
                'metadata' => json_encode(['domain' => 'example.com']),
                'created_at' => now()->subDays(3),
                'updated_at' => now()->subDays(3),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'organization_id' => $this->organizationId,
                'user_id' => $this->userId,
                'action' => 'user.login.failed',
                'resource_type' => 'user',
                'resource_id' => $this->userId,
                'ip_address' => '192.168.1.2',
                'metadata' => json_encode(['reason' => 'invalid_password']),
                'created_at' => now()->subDays(1),
                'updated_at' => now()->subDays(1),
            ],
        ]);
    }

    public function test_filters_by_user(): void
    {
        $results = AuditLogQuery::make()
            ->forUser($this->userId)
            ->get();

        $this->assertCount(3, $results);
    }

    public function test_filters_by_organization(): void
    {
        $results = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->get();

        $this->assertCount(3, $results);
    }

    public function test_filters_by_action(): void
    {
        $results = AuditLogQuery::make()
            ->withAction('user.login')
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_filters_by_resource_type(): void
    {
        $results = AuditLogQuery::make()
            ->forResourceType('user')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_resource(): void
    {
        $siteResourceId = DB::table('audit_logs')
            ->where('action', 'site.created')
            ->value('resource_id');

        $results = AuditLogQuery::make()
            ->forResource('site', $siteResourceId)
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_filters_by_ip_address(): void
    {
        $results = AuditLogQuery::make()
            ->fromIp('192.168.1.1')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_date_range(): void
    {
        $results = AuditLogQuery::make()
            ->between(now()->subDays(4), now()->subDays(2))
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_gets_security_events(): void
    {
        $results = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->securityEvents();

        $this->assertCount(2, $results); // login and login.failed
    }

    public function test_gets_failed_logins(): void
    {
        $results = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->failedLogins();

        $this->assertCount(1, $results);
    }

    public function test_counts_by_action(): void
    {
        $counts = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->countByAction();

        $this->assertEquals(1, $counts['user.login'] ?? 0);
        $this->assertEquals(1, $counts['site.created'] ?? 0);
        $this->assertEquals(1, $counts['user.login.failed'] ?? 0);
    }

    public function test_counts_by_user(): void
    {
        $counts = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->countByUser();

        $this->assertEquals(3, $counts[$this->userId] ?? 0);
    }

    public function test_counts_by_resource_type(): void
    {
        $counts = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->countByResourceType();

        $this->assertEquals(2, $counts['user'] ?? 0);
        $this->assertEquals(1, $counts['site'] ?? 0);
    }

    public function test_gets_unique_ip_addresses(): void
    {
        $ips = AuditLogQuery::make()
            ->forUser($this->userId)
            ->uniqueIpAddresses();

        $this->assertCount(2, $ips);
        $this->assertContains('192.168.1.1', $ips);
        $this->assertContains('192.168.1.2', $ips);
    }

    public function test_gets_daily_timeline(): void
    {
        $timeline = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->dailyTimeline();

        $this->assertIsArray($timeline);
        $this->assertGreaterThan(0, count($timeline));
    }

    public function test_combines_multiple_filters(): void
    {
        $results = AuditLogQuery::make()
            ->forUser($this->userId)
            ->forResourceType('user')
            ->withAction('user.login')
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_paginates_results(): void
    {
        $paginator = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->paginate(2);

        $this->assertCount(2, $paginator->items());
        $this->assertEquals(3, $paginator->total());
    }

    public function test_counts_total(): void
    {
        $count = AuditLogQuery::make()
            ->forOrganization($this->organizationId)
            ->count();

        $this->assertEquals(3, $count);
    }

    public function test_alias_methods(): void
    {
        $byUser = AuditLogQuery::make()
            ->byUser($this->userId)
            ->get();

        $this->assertCount(3, $byUser);

        $byAction = AuditLogQuery::make()
            ->byAction('user.login')
            ->get();

        $this->assertCount(1, $byAction);
    }

    public function test_constructor_pattern(): void
    {
        $query = new AuditLogQuery(
            userId: $this->userId,
            action: 'user.login'
        );

        $results = $query->get();

        $this->assertCount(1, $results);
    }

    public function test_fluent_builder_pattern(): void
    {
        $results = AuditLogQuery::make()
            ->forUser($this->userId)
            ->withAction('user.login')
            ->get();

        $this->assertCount(1, $results);
    }
}
