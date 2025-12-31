<?php

declare(strict_types=1);

namespace Tests\Concerns;

use App\Services\Observability\GrafanaAdapter;
use App\Services\Observability\LokiAdapter;
use App\Services\Observability\PrometheusAdapter;
use Mockery;
use Mockery\MockInterface;

/**
 * Provides mock observability services for testing
 *
 * This trait provides pre-configured mocks for Prometheus, Loki, and Grafana,
 * allowing tests to simulate observability operations without actual service connections.
 *
 * @package Tests\Concerns
 */
trait WithMockObservability
{
    /**
     * Mock Prometheus adapter
     */
    protected PrometheusAdapter|MockInterface $mockPrometheus;

    /**
     * Mock Loki adapter
     */
    protected LokiAdapter|MockInterface $mockLoki;

    /**
     * Mock Grafana adapter
     */
    protected GrafanaAdapter|MockInterface $mockGrafana;

    /**
     * Set up observability mocks
     *
     * @return void
     */
    protected function setUpObservabilityMocks(): void
    {
        $this->mockPrometheus = Mockery::mock(PrometheusAdapter::class);
        $this->mockLoki = Mockery::mock(LokiAdapter::class);
        $this->mockGrafana = Mockery::mock(GrafanaAdapter::class);

        $this->app->instance(PrometheusAdapter::class, $this->mockPrometheus);
        $this->app->instance(LokiAdapter::class, $this->mockLoki);
        $this->app->instance(GrafanaAdapter::class, $this->mockGrafana);
    }

    /**
     * Mock successful Prometheus query
     *
     * @param string $query
     * @param array $result
     * @return void
     */
    protected function mockPrometheusQuery(string $query, array $result = []): void
    {
        $defaultResult = [
            'status' => 'success',
            'data' => [
                'resultType' => 'vector',
                'result' => [
                    [
                        'metric' => ['__name__' => 'test_metric'],
                        'value' => [time(), '42'],
                    ],
                ],
            ],
        ];

        $this->mockPrometheus
            ->shouldReceive('query')
            ->with($query)
            ->andReturn(array_merge($defaultResult, $result));
    }

    /**
     * Mock Prometheus query with sanitization check
     *
     * @param string $expectedSanitizedQuery
     * @return void
     */
    protected function mockPrometheusQueryWithSanitization(string $expectedSanitizedQuery): void
    {
        $this->mockPrometheus
            ->shouldReceive('sanitizeQuery')
            ->andReturn($expectedSanitizedQuery);

        $this->mockPrometheus
            ->shouldReceive('query')
            ->with($expectedSanitizedQuery)
            ->andReturn([
                'status' => 'success',
                'data' => ['result' => []],
            ]);
    }

    /**
     * Mock Prometheus metric recording
     *
     * @param string $metric
     * @param float $value
     * @param array $labels
     * @return void
     */
    protected function mockPrometheusMetric(string $metric, float $value, array $labels = []): void
    {
        $this->mockPrometheus
            ->shouldReceive('recordMetric')
            ->with($metric, $value, $labels)
            ->andReturnNull();
    }

    /**
     * Mock Loki log push
     *
     * @param string $stream
     * @param string $message
     * @param array $labels
     * @return void
     */
    protected function mockLokiLogPush(string $stream, string $message, array $labels = []): void
    {
        $this->mockLoki
            ->shouldReceive('push')
            ->with(Mockery::on(function ($arg) use ($stream, $message, $labels) {
                return $arg['stream'] === $stream
                    && $arg['message'] === $message
                    && $arg['labels'] === $labels;
            }))
            ->andReturn(['status' => 'success']);
    }

    /**
     * Mock Loki query with sanitization
     *
     * @param string $expectedSanitizedQuery
     * @param array $results
     * @return void
     */
    protected function mockLokiQuery(string $expectedSanitizedQuery, array $results = []): void
    {
        $defaultResults = [
            'status' => 'success',
            'data' => [
                'resultType' => 'streams',
                'result' => [
                    [
                        'stream' => ['job' => 'test'],
                        'values' => [
                            [time() * 1e9, 'log message'],
                        ],
                    ],
                ],
            ],
        ];

        $this->mockLoki
            ->shouldReceive('sanitizeQuery')
            ->andReturn($expectedSanitizedQuery);

        $this->mockLoki
            ->shouldReceive('query')
            ->with($expectedSanitizedQuery)
            ->andReturn(array_merge($defaultResults, $results));
    }

    /**
     * Mock Grafana dashboard creation
     *
     * @param string $dashboardTitle
     * @param int $dashboardId
     * @return void
     */
    protected function mockGrafanaDashboardCreation(
        string $dashboardTitle = 'Test Dashboard',
        int $dashboardId = 1
    ): void {
        $this->mockGrafana
            ->shouldReceive('createDashboard')
            ->with(Mockery::on(fn($config) => $config['title'] === $dashboardTitle))
            ->andReturn([
                'id' => $dashboardId,
                'uid' => 'test-' . uniqid(),
                'url' => "/d/test-{$dashboardId}/{$dashboardTitle}",
                'status' => 'success',
            ]);
    }

    /**
     * Mock Grafana user provisioning
     *
     * @param string $email
     * @param int $userId
     * @return void
     */
    protected function mockGrafanaUserProvisioning(string $email, int $userId = 1): void
    {
        $this->mockGrafana
            ->shouldReceive('createUser')
            ->with(Mockery::on(fn($data) => $data['email'] === $email))
            ->andReturn([
                'id' => $userId,
                'email' => $email,
                'login' => explode('@', $email)[0],
                'apiKey' => 'grafana-api-' . bin2hex(random_bytes(16)),
            ]);
    }

    /**
     * Mock Grafana organization creation
     *
     * @param string $orgName
     * @param int $orgId
     * @return void
     */
    protected function mockGrafanaOrgCreation(string $orgName, int $orgId = 1): void
    {
        $this->mockGrafana
            ->shouldReceive('createOrganization')
            ->with($orgName)
            ->andReturn([
                'orgId' => $orgId,
                'name' => $orgName,
                'message' => 'Organization created',
            ]);
    }

    /**
     * Mock PromQL injection prevention
     *
     * Ensures that malicious queries are sanitized
     *
     * @param string $maliciousQuery
     * @param string $sanitizedQuery
     * @return void
     */
    protected function mockPromQLInjectionPrevention(
        string $maliciousQuery,
        string $sanitizedQuery
    ): void {
        $this->mockPrometheus
            ->shouldReceive('sanitizeQuery')
            ->with($maliciousQuery)
            ->andReturn($sanitizedQuery);

        $this->mockPrometheus
            ->shouldReceive('query')
            ->with($sanitizedQuery)
            ->andReturn(['status' => 'success', 'data' => ['result' => []]]);
    }

    /**
     * Mock LogQL injection prevention
     *
     * @param string $maliciousQuery
     * @param string $sanitizedQuery
     * @return void
     */
    protected function mockLogQLInjectionPrevention(
        string $maliciousQuery,
        string $sanitizedQuery
    ): void {
        $this->mockLoki
            ->shouldReceive('sanitizeQuery')
            ->with($maliciousQuery)
            ->andReturn($sanitizedQuery);

        $this->mockLoki
            ->shouldReceive('query')
            ->with($sanitizedQuery)
            ->andReturn(['status' => 'success', 'data' => ['result' => []]]);
    }

    /**
     * Assert Prometheus metric was recorded
     *
     * @param string $metric
     * @return void
     */
    protected function assertPrometheusMetricRecorded(string $metric): void
    {
        $this->mockPrometheus
            ->shouldHaveReceived('recordMetric')
            ->with($metric, Mockery::any(), Mockery::any())
            ->atLeast()
            ->once();
    }

    /**
     * Assert Loki log was pushed
     *
     * @param string $stream
     * @return void
     */
    protected function assertLokiLogPushed(string $stream): void
    {
        $this->mockLoki
            ->shouldHaveReceived('push')
            ->with(Mockery::on(fn($arg) => $arg['stream'] === $stream))
            ->atLeast()
            ->once();
    }

    /**
     * Assert Grafana dashboard was created
     *
     * @return void
     */
    protected function assertGrafanaDashboardCreated(): void
    {
        $this->mockGrafana
            ->shouldHaveReceived('createDashboard')
            ->once();
    }

    /**
     * Assert query was sanitized before execution
     *
     * @param string $service Either 'prometheus' or 'loki'
     * @return void
     */
    protected function assertQueryWasSanitized(string $service = 'prometheus'): void
    {
        $mock = $service === 'prometheus' ? $this->mockPrometheus : $this->mockLoki;

        $mock->shouldHaveReceived('sanitizeQuery')
            ->once();
    }
}
