<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Traits\ApiResponse;
use App\Http\Traits\HasTenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Base API Controller for V1
 *
 * Provides common functionality for all API V1 controllers:
 * - Consistent API responses via ApiResponse trait
 * - Tenant context resolution via HasTenantContext trait
 * - Pagination helpers
 * - Common error handling
 * - Logging utilities
 *
 * All V1 API controllers should extend this class.
 *
 * @package App\Http\Controllers\Api\V1
 */
abstract class ApiController extends Controller
{
    use ApiResponse, HasTenantContext;

    /**
     * Default number of items per page for pagination.
     *
     * @var int
     */
    protected int $defaultPerPage = 20;

    /**
     * Maximum number of items per page.
     * Prevents excessive memory usage from large page sizes.
     *
     * @var int
     */
    protected int $maxPerPage = 100;

    /**
     * Get pagination limit from request with validation.
     *
     * Ensures per_page is within acceptable bounds [1, maxPerPage].
     *
     * @param Request $request
     * @return int Validated per_page value
     */
    protected function getPaginationLimit(Request $request): int
    {
        $perPage = (int) $request->input('per_page', $this->defaultPerPage);

        // Ensure it's within bounds
        return min(max($perPage, 1), $this->maxPerPage);
    }

    /**
     * Apply common filters to a query builder.
     *
     * Supports:
     * - search: Generic search term
     * - status: Filter by status field
     * - sort_by: Field to sort by
     * - sort_order: asc or desc
     *
     * Override this method in child controllers for custom filtering.
     *
     * @param \Illuminate\Database\Eloquent\Builder $query
     * @param Request $request
     * @return \Illuminate\Database\Eloquent\Builder
     */
    protected function applyFilters($query, Request $request)
    {
        // Filter by status if provided
        if ($request->has('status') && $request->filled('status')) {
            $query->where('status', $request->input('status'));
        }

        // Apply sorting
        $sortBy = $request->input('sort_by', 'created_at');
        $sortOrder = $request->input('sort_order', 'desc');

        // Validate sort order
        $sortOrder = in_array(strtolower($sortOrder), ['asc', 'desc']) 
            ? strtolower($sortOrder) 
            : 'desc';

        $query->orderBy($sortBy, $sortOrder);

        return $query;
    }

    /**
     * Validate that a resource belongs to the current tenant.
     *
     * @param Request $request
     * @param string $resourceId Resource ID to validate
     * @param string $modelClass Fully qualified model class name
     * @param string $tenantField Field name for tenant ID (default: 'tenant_id')
     * @return mixed The validated resource
     * @throws \Illuminate\Database\Eloquent\ModelNotFoundException
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException
     */
    protected function validateTenantAccess(
        Request $request,
        string $resourceId,
        string $modelClass,
        string $tenantField = 'tenant_id'
    ) {
        $tenant = $this->getTenant($request);

        // Find the resource
        $resource = $modelClass::findOrFail($resourceId);

        // Validate ownership
        if ($resource->{$tenantField} !== $tenant->id) {
            abort(403, 'You do not have access to this resource.');
        }

        return $resource;
    }

    /**
     * Handle common exceptions in API controllers.
     *
     * Converts exceptions to consistent API error responses.
     *
     * @param \Exception $exception
     * @return \Illuminate\Http\JsonResponse
     */
    protected function handleException(\Exception $exception)
    {
        // Log the exception
        $this->logError('Exception caught in controller', [
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
            'file' => $exception->getFile(),
            'line' => $exception->getLine(),
        ]);

        // Handle specific exception types
        if ($exception instanceof \Illuminate\Database\Eloquent\ModelNotFoundException) {
            return $this->notFoundResponse('resource', 'The requested resource was not found.');
        }

        if ($exception instanceof \Illuminate\Validation\ValidationException) {
            return $this->validationErrorResponse($exception->errors());
        }

        if ($exception instanceof \Illuminate\Auth\AuthenticationException) {
            return $this->errorResponse(
                'UNAUTHENTICATED',
                'You must be authenticated to access this resource.',
                [],
                401
            );
        }

        if ($exception instanceof \Symfony\Component\HttpKernel\Exception\HttpException) {
            return $this->errorResponse(
                'HTTP_ERROR',
                $exception->getMessage(),
                [],
                $exception->getStatusCode()
            );
        }

        // Default error response for unknown exceptions
        return $this->errorResponse(
            'SERVER_ERROR',
            config('app.debug') 
                ? $exception->getMessage() 
                : 'An unexpected error occurred. Please try again later.',
            config('app.debug') ? [
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
            ] : [],
            500
        );
    }

    /**
     * Log an error with standardized context.
     *
     * @param string $message Log message
     * @param array $context Additional context data
     * @return void
     */
    protected function logError(string $message, array $context = []): void
    {
        Log::error($message, array_merge([
            'controller' => static::class,
            'user_id' => auth()->id(),
            'ip' => request()->ip(),
            'url' => request()->fullUrl(),
        ], $context));
    }

    /**
     * Log an info message with standardized context.
     *
     * @param string $message Log message
     * @param array $context Additional context data
     * @return void
     */
    protected function logInfo(string $message, array $context = []): void
    {
        Log::info($message, array_merge([
            'controller' => static::class,
            'user_id' => auth()->id(),
        ], $context));
    }

    /**
     * Log a warning with standardized context.
     *
     * @param string $message Log message
     * @param array $context Additional context data
     * @return void
     */
    protected function logWarning(string $message, array $context = []): void
    {
        Log::warning($message, array_merge([
            'controller' => static::class,
            'user_id' => auth()->id(),
        ], $context));
    }
}
