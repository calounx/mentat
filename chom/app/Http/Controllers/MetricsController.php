<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Services\MetricsCollector;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Metrics Controller
 *
 * Exposes Prometheus-compatible metrics endpoint.
 */
class MetricsController extends Controller
{
    private MetricsCollector $metrics;

    public function __construct(MetricsCollector $metrics)
    {
        $this->metrics = $metrics;
    }

    /**
     * Export metrics in Prometheus format.
     *
     * @param Request $request
     * @return Response
     */
    public function index(Request $request): Response
    {
        // Check if metrics endpoint is enabled
        if (!config('observability.metrics.endpoint.enabled', true)) {
            return response('Metrics endpoint is disabled', 404);
        }

        // Check IP whitelist
        if (!$this->isAllowedIp($request->ip())) {
            return response('Access denied', 403);
        }

        $metricsOutput = $this->metrics->export();

        return response($metricsOutput, 200, [
            'Content-Type' => 'text/plain; version=0.0.4; charset=utf-8',
        ]);
    }

    /**
     * Check if IP is allowed to access metrics.
     *
     * @param string $ip
     * @return bool
     */
    private function isAllowedIp(string $ip): bool
    {
        $whitelist = config('observability.metrics.endpoint.ip_whitelist', ['127.0.0.1', '::1']);

        if (empty($whitelist)) {
            return true; // No whitelist configured, allow all
        }

        return in_array($ip, $whitelist);
    }
}
