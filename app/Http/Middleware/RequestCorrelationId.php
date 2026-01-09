<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class RequestCorrelationId
{
    public const HEADER_NAME = 'X-Correlation-ID';
    public const CONTEXT_KEY = 'correlation_id';

    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        // Get or generate correlation ID
        $correlationId = $request->header(self::HEADER_NAME) ?? $this->generateCorrelationId();

        // Store in request attributes for easy access
        $request->attributes->set(self::CONTEXT_KEY, $correlationId);

        // Add to log context so all logs include correlation ID
        Log::withContext([
            self::CONTEXT_KEY => $correlationId,
            'user_id' => $request->user()?->id,
            'ip' => $request->ip(),
            'method' => $request->method(),
            'uri' => $request->getRequestUri(),
        ]);

        // Process request
        $response = $next($request);

        // Add correlation ID to response headers
        if ($response instanceof Response) {
            $response->headers->set(self::HEADER_NAME, $correlationId);
        }

        return $response;
    }

    /**
     * Generate a new correlation ID
     */
    private function generateCorrelationId(): string
    {
        // Format: timestamp-random
        // Example: 1704844800-7f3d9b2e
        return now()->timestamp . '-' . Str::random(8);
    }
}
