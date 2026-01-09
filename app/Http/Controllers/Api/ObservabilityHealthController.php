<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ObservabilityHealthService;
use Illuminate\Http\JsonResponse;

class ObservabilityHealthController extends Controller
{
    public function __construct(
        private ObservabilityHealthService $healthService
    ) {}

    /**
     * Get overall observability stack health status
     *
     * @return JsonResponse
     */
    public function index(): JsonResponse
    {
        $health = $this->healthService->checkOverall();

        $statusCode = match ($health['status']) {
            'healthy' => 200,
            'degraded' => 503,
            'partial' => 200,
            default => 500,
        };

        return response()->json($health, $statusCode);
    }

    /**
     * Check specific component health
     *
     * @param string $component
     * @return JsonResponse
     */
    public function component(string $component): JsonResponse
    {
        $method = 'check' . ucfirst($component);

        if (!method_exists($this->healthService, $method)) {
            return response()->json([
                'error' => "Unknown component: {$component}",
                'valid_components' => ['prometheus', 'grafana', 'loki', 'alertmanager'],
            ], 404);
        }

        $health = $this->healthService->$method();

        $statusCode = match ($health['status']) {
            'healthy' => 200,
            'unhealthy' => 503,
            'unconfigured' => 424,
            default => 500,
        };

        return response()->json($health, $statusCode);
    }

    /**
     * Clear health check cache
     *
     * @return JsonResponse
     */
    public function clearCache(): JsonResponse
    {
        $this->healthService->clearCache();

        return response()->json([
            'message' => 'Health check cache cleared',
        ]);
    }
}
