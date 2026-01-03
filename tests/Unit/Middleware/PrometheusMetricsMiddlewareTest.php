<?php

declare(strict_types=1);

namespace Tests\Unit\Middleware;

use App\Http\Middleware\PrometheusMetricsMiddleware;
use App\Models\User;
use App\Services\MetricsCollector;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Mockery;
use Tests\TestCase;

class PrometheusMetricsMiddlewareTest extends TestCase
{
    use RefreshDatabase;

    private PrometheusMetricsMiddleware $middleware;
    private $metricsCollector;

    protected function setUp(): void
    {
        parent::setUp();

        $this->metricsCollector = Mockery::mock(MetricsCollector::class);
        $this->middleware = new PrometheusMetricsMiddleware($this->metricsCollector);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_records_http_request_metrics(): void
    {
        $request = Request::create('/api/sites', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return $tags['method'] === 'GET'
                    && $tags['endpoint'] === '/api/sites'
                    && $tags['status'] === 200;
            }));

        $this->metricsCollector->shouldReceive('recordTiming')
            ->once()
            ->with('http_request_duration_ms', Mockery::type('float'), Mockery::type('array'));

        $this->middleware->handle($request, $next);
    }

    public function test_tracks_request_duration_accurately(): void
    {
        $request = Request::create('/api/sites', 'GET');
        $next = function ($req) {
            usleep(50000); // 50ms delay
            return new Response('OK', 200);
        };

        $this->metricsCollector->shouldReceive('incrementCounter')->once();

        $this->metricsCollector->shouldReceive('recordTiming')
            ->once()
            ->with('http_request_duration_ms', Mockery::on(function ($duration) {
                // Should be approximately 50ms
                return $duration >= 45 && $duration <= 100;
            }), Mockery::type('array'));

        $this->middleware->handle($request, $next);
    }

    public function test_records_different_http_methods(): void
    {
        $methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

        foreach ($methods as $method) {
            $request = Request::create('/api/sites', $method);
            $next = fn($req) => new Response('OK', 200);

            $this->metricsCollector->shouldReceive('incrementCounter')
                ->once()
                ->with('http_requests_total', 1, Mockery::on(function ($tags) use ($method) {
                    return $tags['method'] === $method;
                }));

            $this->metricsCollector->shouldReceive('recordTiming')->once();

            $this->middleware->handle($request, $next);
        }
    }

    public function test_records_different_status_codes(): void
    {
        $statusCodes = [200, 201, 400, 401, 403, 404, 500];

        foreach ($statusCodes as $statusCode) {
            $request = Request::create('/api/test', 'GET');
            $next = fn($req) => new Response('Response', $statusCode);

            $this->metricsCollector->shouldReceive('incrementCounter')
                ->once()
                ->with('http_requests_total', 1, Mockery::on(function ($tags) use ($statusCode) {
                    return $tags['status'] === $statusCode;
                }));

            $this->metricsCollector->shouldReceive('recordTiming')->once();

            $this->middleware->handle($request, $next);
        }
    }

    public function test_groups_similar_endpoints(): void
    {
        $request1 = Request::create('/api/sites/123', 'GET');
        $request2 = Request::create('/api/sites/456', 'GET');

        $next = fn($req) => new Response('OK', 200);

        // Both should be grouped as /api/sites/{id}
        $this->metricsCollector->shouldReceive('incrementCounter')
            ->twice()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return str_contains($tags['endpoint'], '/api/sites');
            }));

        $this->metricsCollector->shouldReceive('recordTiming')->twice();

        $this->middleware->handle($request1, $next);
        $this->middleware->handle($request2, $next);
    }

    public function test_includes_user_context_when_authenticated(): void
    {
        $user = User::factory()->create();
        $request = Request::create('/api/sites', 'GET');
        $request->setUserResolver(fn() => $user);

        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return isset($tags['authenticated']) && $tags['authenticated'] === true;
            }));

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->middleware->handle($request, $next);
    }

    public function test_tracks_unauthenticated_requests(): void
    {
        $request = Request::create('/api/public', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return isset($tags['authenticated']) && $tags['authenticated'] === false;
            }));

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->middleware->handle($request, $next);
    }

    public function test_tracks_response_size(): void
    {
        $largeContent = str_repeat('a', 10000);
        $request = Request::create('/api/data', 'GET');
        $next = fn($req) => new Response($largeContent, 200);

        $this->metricsCollector->shouldReceive('incrementCounter')->once();

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->metricsCollector->shouldReceive('recordMetric')
            ->once()
            ->with('http_response_size_bytes', Mockery::on(function ($size) {
                return $size >= 10000;
            }), Mockery::type('array'));

        $this->middleware->handle($request, $next);
    }

    public function test_records_error_metrics(): void
    {
        $request = Request::create('/api/error', 'GET');
        $next = fn($req) => new Response('Internal Server Error', 500);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return $tags['status'] === 500;
            }));

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_errors_total', 1, Mockery::type('array'));

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->middleware->handle($request, $next);
    }

    public function test_handles_exceptions_during_request(): void
    {
        $request = Request::create('/api/exception', 'GET');
        $next = function ($req) {
            throw new \RuntimeException('Test exception');
        };

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->with('http_exceptions_total', 1, Mockery::type('array'))
            ->once();

        $this->expectException(\RuntimeException::class);

        $this->middleware->handle($request, $next);
    }

    public function test_tracks_slow_requests(): void
    {
        $request = Request::create('/api/slow', 'GET');
        $next = function ($req) {
            usleep(200000); // 200ms delay
            return new Response('OK', 200);
        };

        $this->metricsCollector->shouldReceive('incrementCounter')->once();

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_slow_requests_total', 1, Mockery::on(function ($tags) {
                return isset($tags['threshold']) && $tags['threshold'] === 'slow';
            }));

        $this->middleware->handle($request, $next);
    }

    public function test_excludes_health_check_endpoints(): void
    {
        $healthCheckPaths = ['/health', '/health/liveness', '/health/readiness'];

        foreach ($healthCheckPaths as $path) {
            $request = Request::create($path, 'GET');
            $next = fn($req) => new Response('OK', 200);

            $this->metricsCollector->shouldReceive('incrementCounter')
                ->never();

            $this->metricsCollector->shouldReceive('recordTiming')
                ->never();

            $this->middleware->handle($request, $next);
        }
    }

    public function test_records_api_version_metrics(): void
    {
        $request = Request::create('/api/v1/sites', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return isset($tags['api_version']) && $tags['api_version'] === 'v1';
            }));

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->middleware->handle($request, $next);
    }

    public function test_tracks_request_content_type(): void
    {
        $request = Request::create('/api/data', 'POST', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
        ]);
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                return isset($tags['content_type']) && str_contains($tags['content_type'], 'json');
            }));

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->middleware->handle($request, $next);
    }

    public function test_performance_overhead_is_minimal(): void
    {
        $request = Request::create('/api/test', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')->times(100);
        $this->metricsCollector->shouldReceive('recordTiming')->times(100);

        $startTime = microtime(true);

        for ($i = 0; $i < 100; $i++) {
            $this->middleware->handle($request, $next);
        }

        $endTime = microtime(true);
        $overhead = ($endTime - $startTime) * 1000;

        // Metrics collection overhead should be less than 100ms for 100 requests
        $this->assertLessThan(100, $overhead);
    }

    public function test_records_request_payload_size(): void
    {
        $largePayload = json_encode(['data' => str_repeat('x', 5000)]);
        $request = Request::create('/api/data', 'POST', [], [], [], [
            'CONTENT_LENGTH' => strlen($largePayload),
        ]);
        $request->setContent($largePayload);

        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')->once();
        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->metricsCollector->shouldReceive('recordMetric')
            ->once()
            ->with('http_request_size_bytes', Mockery::on(function ($size) {
                return $size >= 5000;
            }), Mockery::type('array'));

        $this->middleware->handle($request, $next);
    }

    public function test_tracks_concurrent_requests(): void
    {
        $request = Request::create('/api/concurrent', 'GET');
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')->times(10);
        $this->metricsCollector->shouldReceive('recordTiming')->times(10);

        $this->metricsCollector->shouldReceive('gauge')
            ->with('http_concurrent_requests', Mockery::type('int'), Mockery::type('array'))
            ->times(20); // increment and decrement for each request

        for ($i = 0; $i < 10; $i++) {
            $this->middleware->handle($request, $next);
        }
    }

    public function test_sanitizes_sensitive_data_in_metrics(): void
    {
        $request = Request::create('/api/users/123/password', 'PUT');
        $next = fn($req) => new Response('OK', 200);

        $this->metricsCollector->shouldReceive('incrementCounter')
            ->once()
            ->with('http_requests_total', 1, Mockery::on(function ($tags) {
                // Should not include sensitive path segments
                return !str_contains($tags['endpoint'], 'password');
            }));

        $this->metricsCollector->shouldReceive('recordTiming')->once();

        $this->middleware->handle($request, $next);
    }
}
