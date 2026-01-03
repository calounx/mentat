<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Models\AuditLog;
use App\Models\Organization;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class AuditLoggerTest extends TestCase
{
    use RefreshDatabase;

    private AuditLogger $logger;
    private User $user;
    private Organization $organization;

    protected function setUp(): void
    {
        parent::setUp();

        $this->logger = new AuditLogger();

        $this->organization = Organization::factory()->create();
        $this->user = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);
    }

    public function test_logs_authentication_event(): void
    {
        $this->logger->logAuthentication(
            $this->user,
            'login',
            '192.168.1.100',
            ['method' => 'password']
        );

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'organization_id' => $this->organization->id,
            'action' => 'authentication.login',
            'ip_address' => '192.168.1.100',
        ]);
    }

    public function test_logs_authorization_failure(): void
    {
        $this->logger->logAuthorizationFailure(
            $this->user,
            'delete',
            'Site',
            'site-123',
            ['reason' => 'insufficient_permissions']
        );

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'authorization.failed',
            'resource_type' => 'Site',
            'resource_id' => 'site-123',
        ]);

        $log = AuditLog::where('user_id', $this->user->id)
            ->where('action', 'authorization.failed')
            ->first();

        $this->assertEquals('insufficient_permissions', $log->metadata['reason']);
    }

    public function test_logs_sensitive_operation(): void
    {
        $this->logger->logSensitiveOperation(
            $this->user,
            'password_changed',
            ['changed_at' => now()->toIso8601String()]
        );

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'sensitive.password_changed',
        ]);
    }

    public function test_logs_resource_access(): void
    {
        $this->logger->logResourceAccess(
            $this->user,
            'Site',
            'site-456',
            'view',
            ['domain' => 'example.com']
        );

        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'resource.view',
            'resource_type' => 'Site',
            'resource_id' => 'site-456',
        ]);
    }

    public function test_logs_data_modification(): void
    {
        $oldData = ['status' => 'active'];
        $newData = ['status' => 'suspended'];

        $this->logger->logDataModification(
            $this->user,
            'Site',
            'site-789',
            'update',
            $oldData,
            $newData
        );

        $log = AuditLog::where('resource_id', 'site-789')->first();

        $this->assertEquals('resource.update', $log->action);
        $this->assertEquals($oldData, $log->metadata['old_data']);
        $this->assertEquals($newData, $log->metadata['new_data']);
    }

    public function test_includes_request_metadata(): void
    {
        $request = Request::create('/api/sites', 'GET', [], [], [], [
            'REMOTE_ADDR' => '192.168.1.100',
            'HTTP_USER_AGENT' => 'Mozilla/5.0',
        ]);

        $this->logger->logFromRequest(
            $request,
            $this->user,
            'api.request',
            ['endpoint' => '/api/sites']
        );

        $this->assertDatabaseHas('audit_logs', [
            'action' => 'api.request',
            'ip_address' => '192.168.1.100',
            'user_agent' => 'Mozilla/5.0',
        ]);
    }

    public function test_captures_stack_trace_for_errors(): void
    {
        $exception = new \RuntimeException('Test error');

        $this->logger->logException(
            $exception,
            $this->user,
            ['context' => 'test']
        );

        $log = AuditLog::where('action', 'system.exception')->first();

        $this->assertNotNull($log);
        $this->assertArrayHasKey('exception_class', $log->metadata);
        $this->assertArrayHasKey('stack_trace', $log->metadata);
        $this->assertEquals(\RuntimeException::class, $log->metadata['exception_class']);
    }

    public function test_redacts_sensitive_data_in_logs(): void
    {
        $sensitiveData = [
            'password' => 'secret123',
            'api_key' => 'sk_live_123456',
            'ssn' => '123-45-6789',
            'credit_card' => '4111111111111111',
            'safe_field' => 'public_data',
        ];

        $this->logger->log(
            $this->user,
            'data.submitted',
            $sensitiveData
        );

        $log = AuditLog::where('action', 'data.submitted')->first();

        $this->assertEquals('[REDACTED]', $log->metadata['password']);
        $this->assertEquals('[REDACTED]', $log->metadata['api_key']);
        $this->assertEquals('[REDACTED]', $log->metadata['ssn']);
        $this->assertEquals('[REDACTED]', $log->metadata['credit_card']);
        $this->assertEquals('public_data', $log->metadata['safe_field']);
    }

    public function test_creates_immutable_log_chain(): void
    {
        $log1 = $this->logger->log($this->user, 'action.1', ['data' => 'first']);
        $log2 = $this->logger->log($this->user, 'action.2', ['data' => 'second']);
        $log3 = $this->logger->log($this->user, 'action.3', ['data' => 'third']);

        // Each log should contain hash of previous log
        $this->assertNotNull($log1->hash);
        $this->assertNotNull($log2->hash);
        $this->assertNotNull($log3->hash);
        $this->assertNotNull($log2->previous_hash);
        $this->assertNotNull($log3->previous_hash);

        $this->assertEquals($log1->hash, $log2->previous_hash);
        $this->assertEquals($log2->hash, $log3->previous_hash);
    }

    public function test_verifies_log_chain_integrity(): void
    {
        $log1 = $this->logger->log($this->user, 'action.1');
        $log2 = $this->logger->log($this->user, 'action.2');
        $log3 = $this->logger->log($this->user, 'action.3');

        $isValid = $this->logger->verifyChainIntegrity([
            $log1->id,
            $log2->id,
            $log3->id,
        ]);

        $this->assertTrue($isValid);
    }

    public function test_detects_tampered_logs(): void
    {
        $log1 = $this->logger->log($this->user, 'action.1');
        $log2 = $this->logger->log($this->user, 'action.2');

        // Tamper with log
        $log1->update(['metadata' => ['tampered' => true]]);

        $isValid = $this->logger->verifyChainIntegrity([
            $log1->id,
            $log2->id,
        ]);

        $this->assertFalse($isValid);
    }

    public function test_filters_logs_by_time_range(): void
    {
        $yesterday = now()->subDay();
        $today = now();

        // Create logs at different times
        $oldLog = $this->logger->log($this->user, 'old.action');
        $oldLog->update(['created_at' => $yesterday]);

        $newLog = $this->logger->log($this->user, 'new.action');

        $logs = $this->logger->getLogsByTimeRange(
            $this->organization->id,
            $today->copy()->subHour(),
            $today->copy()->addHour()
        );

        $this->assertCount(1, $logs);
        $this->assertEquals('new.action', $logs->first()->action);
    }

    public function test_filters_logs_by_user(): void
    {
        $anotherUser = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $this->logger->log($this->user, 'user1.action');
        $this->logger->log($anotherUser, 'user2.action');
        $this->logger->log($this->user, 'user1.another');

        $logs = $this->logger->getLogsByUser($this->user->id);

        $this->assertCount(2, $logs);
    }

    public function test_filters_logs_by_action_type(): void
    {
        $this->logger->log($this->user, 'authentication.login');
        $this->logger->log($this->user, 'authentication.logout');
        $this->logger->log($this->user, 'resource.create');

        $authLogs = $this->logger->getLogsByActionPattern('authentication.*');

        $this->assertCount(2, $authLogs);
    }

    public function test_filters_logs_by_resource(): void
    {
        $this->logger->logResourceAccess($this->user, 'Site', 'site-1', 'view');
        $this->logger->logResourceAccess($this->user, 'Site', 'site-1', 'update');
        $this->logger->logResourceAccess($this->user, 'Site', 'site-2', 'view');

        $logs = $this->logger->getLogsByResource('Site', 'site-1');

        $this->assertCount(2, $logs);
    }

    public function test_exports_audit_trail_for_compliance(): void
    {
        $this->logger->log($this->user, 'action.1', ['field' => 'value1']);
        $this->logger->log($this->user, 'action.2', ['field' => 'value2']);

        $export = $this->logger->exportAuditTrail(
            $this->organization->id,
            now()->subHour(),
            now()->addHour()
        );

        $this->assertIsArray($export);
        $this->assertArrayHasKey('organization_id', $export);
        $this->assertArrayHasKey('time_range', $export);
        $this->assertArrayHasKey('logs', $export);
        $this->assertCount(2, $export['logs']);
    }

    public function test_generates_compliance_report(): void
    {
        $this->logger->log($this->user, 'authentication.login');
        $this->logger->logSensitiveOperation($this->user, 'password_changed');
        $this->logger->logAuthorizationFailure($this->user, 'delete', 'Site', 'site-1');

        $report = $this->logger->generateComplianceReport(
            $this->organization->id,
            now()->subDay(),
            now()->addDay()
        );

        $this->assertArrayHasKey('total_events', $report);
        $this->assertArrayHasKey('authentication_events', $report);
        $this->assertArrayHasKey('authorization_failures', $report);
        $this->assertArrayHasKey('sensitive_operations', $report);

        $this->assertGreaterThan(0, $report['total_events']);
    }

    public function test_identifies_suspicious_patterns(): void
    {
        // Create multiple failed login attempts
        for ($i = 0; $i < 10; $i++) {
            $this->logger->logAuthentication(
                $this->user,
                'login_failed',
                '192.168.1.100',
                ['attempt' => $i + 1]
            );
        }

        $suspiciousActivity = $this->logger->detectSuspiciousPatterns(
            $this->organization->id,
            now()->subHour(),
            now()->addHour()
        );

        $this->assertArrayHasKey('repeated_failed_logins', $suspiciousActivity);
        $this->assertGreaterThan(0, $suspiciousActivity['repeated_failed_logins']);
    }

    public function test_tracks_concurrent_sessions(): void
    {
        $this->logger->logAuthentication($this->user, 'login', '192.168.1.100');
        $this->logger->logAuthentication($this->user, 'login', '10.0.0.50');

        $concurrentSessions = $this->logger->getConcurrentSessions($this->user->id);

        $this->assertGreaterThanOrEqual(2, $concurrentSessions);
    }

    public function test_logs_api_calls_with_rate_limit_info(): void
    {
        $this->logger->logApiCall(
            $this->user,
            '/api/sites',
            'GET',
            200,
            [
                'rate_limit_remaining' => 95,
                'rate_limit_limit' => 100,
                'response_time_ms' => 45,
            ]
        );

        $log = AuditLog::where('action', 'api.call')->first();

        $this->assertEquals(95, $log->metadata['rate_limit_remaining']);
        $this->assertEquals(45, $log->metadata['response_time_ms']);
    }

    public function test_handles_bulk_logging_efficiently(): void
    {
        $startTime = microtime(true);

        $events = [];
        for ($i = 0; $i < 100; $i++) {
            $events[] = [
                'user_id' => $this->user->id,
                'action' => "bulk.action.{$i}",
                'metadata' => ['index' => $i],
            ];
        }

        $this->logger->bulkLog($events);

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 logs should be created in under 500ms
        $this->assertLessThan(500, $duration);
        $this->assertEquals(100, AuditLog::where('user_id', $this->user->id)->count());
    }

    public function test_archives_old_logs(): void
    {
        // Create old logs
        $oldLog = $this->logger->log($this->user, 'old.action');
        $oldLog->update(['created_at' => now()->subDays(400)]);

        // Create recent log
        $recentLog = $this->logger->log($this->user, 'recent.action');

        $this->logger->archiveOldLogs(365); // Archive logs older than 1 year

        $this->assertDatabaseHas('audit_logs', [
            'id' => $oldLog->id,
            'archived' => true,
        ]);

        $this->assertDatabaseHas('audit_logs', [
            'id' => $recentLog->id,
            'archived' => false,
        ]);
    }

    public function test_encrypts_sensitive_metadata(): void
    {
        $sensitiveMetadata = [
            'credit_card' => '4111111111111111',
            'ssn' => '123-45-6789',
        ];

        $log = $this->logger->log($this->user, 'payment.processed', $sensitiveMetadata);

        // Raw database value should be encrypted
        $rawLog = DB::table('audit_logs')->where('id', $log->id)->first();

        $this->assertStringNotContainsString('4111111111111111', json_encode($rawLog->metadata));
        $this->assertStringNotContainsString('123-45-6789', json_encode($rawLog->metadata));
    }

    public function test_tracks_user_agent_changes(): void
    {
        $request1 = Request::create('/test', 'GET', [], [], [], [
            'HTTP_USER_AGENT' => 'Mozilla/5.0 (Windows)',
        ]);

        $request2 = Request::create('/test', 'GET', [], [], [], [
            'HTTP_USER_AGENT' => 'Mozilla/5.0 (Mobile)',
        ]);

        $this->logger->logFromRequest($request1, $this->user, 'request.1');
        $this->logger->logFromRequest($request2, $this->user, 'request.2');

        $userAgentChanges = $this->logger->getUserAgentChanges($this->user->id);

        $this->assertGreaterThan(0, $userAgentChanges);
    }

    public function test_prevents_log_injection_attacks(): void
    {
        $maliciousInput = "action\ninjected: malicious\nuser_id: 999";

        $this->logger->log($this->user, $maliciousInput, ['test' => 'data']);

        $log = AuditLog::latest()->first();

        // Should sanitize the action field
        $this->assertStringNotContainsString("\n", $log->action);
        $this->assertEquals($this->user->id, $log->user_id);
    }

    public function test_performance_under_high_load(): void
    {
        $startTime = microtime(true);

        for ($i = 0; $i < 50; $i++) {
            $this->logger->log($this->user, "load.test.{$i}", ['iteration' => $i]);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 50 logs should be created in under 1 second
        $this->assertLessThan(1000, $duration);
    }
}
