<?php

namespace App\Http\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Pagination\LengthAwarePaginator;

/**
 * API Response Trait
 *
 * Provides consistent JSON response formatting across all API controllers.
 * Centralizes response structure to ensure API contract consistency.
 *
 * @package App\Http\Traits
 */
trait ApiResponse
{
    /**
     * Return a success response with data.
     *
     * @param mixed $data The data to return
     * @param string|null $message Optional success message
     * @param int $status HTTP status code (default: 200)
     * @return JsonResponse
     */
    protected function successResponse($data, ?string $message = null, int $status = 200): JsonResponse
    {
        $response = [
            'success' => true,
            'data' => $data,
        ];

        if ($message !== null) {
            $response['message'] = $message;
        }

        return response()->json($response, $status);
    }

    /**
     * Return a paginated success response.
     *
     * Formats paginated data with consistent metadata structure.
     *
     * @param LengthAwarePaginator $paginator Laravel paginator instance
     * @param callable|null $transformer Optional data transformer function
     * @return JsonResponse
     */
    protected function paginatedResponse(
        LengthAwarePaginator $paginator,
        ?callable $transformer = null
    ): JsonResponse {
        $data = $transformer
            ? collect($paginator->items())->map($transformer)->all()
            : $paginator->items();

        return response()->json([
            'success' => true,
            'data' => $data,
            'meta' => [
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                    'total_pages' => $paginator->lastPage(),
                    'from' => $paginator->firstItem(),
                    'to' => $paginator->lastItem(),
                ],
            ],
        ]);
    }

    /**
     * Return an error response.
     *
     * @param string $code Error code (e.g., 'VALIDATION_ERROR', 'NOT_FOUND')
     * @param string $message Human-readable error message
     * @param array $details Additional error details/context
     * @param int $status HTTP status code (default: 400)
     * @return JsonResponse
     */
    protected function errorResponse(
        string $code,
        string $message,
        array $details = [],
        int $status = 400
    ): JsonResponse {
        $response = [
            'success' => false,
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
        ];

        if (!empty($details)) {
            $response['error']['details'] = $details;
        }

        return response()->json($response, $status);
    }

    /**
     * Return a validation error response.
     *
     * @param array $errors Validation errors keyed by field name
     * @return JsonResponse
     */
    protected function validationErrorResponse(array $errors): JsonResponse
    {
        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'VALIDATION_ERROR',
                'message' => 'The given data was invalid.',
                'details' => $errors,
            ],
        ], 422);
    }

    /**
     * Return a not found error response.
     *
     * @param string $resource Resource type that was not found
     * @param string|null $message Optional custom message
     * @return JsonResponse
     */
    protected function notFoundResponse(string $resource, ?string $message = null): JsonResponse
    {
        return $this->errorResponse(
            strtoupper($resource) . '_NOT_FOUND',
            $message ?? ucfirst($resource) . ' not found.',
            [],
            404
        );
    }

    /**
     * Return an unauthorized error response.
     *
     * @param string|null $message Optional custom message
     * @return JsonResponse
     */
    protected function unauthorizedResponse(?string $message = null): JsonResponse
    {
        return $this->errorResponse(
            'UNAUTHORIZED',
            $message ?? 'You are not authorized to perform this action.',
            [],
            403
        );
    }

    /**
     * Return a created response (HTTP 201).
     *
     * @param mixed $data The created resource data
     * @param string|null $message Optional success message
     * @return JsonResponse
     */
    protected function createdResponse($data, ?string $message = null): JsonResponse
    {
        return $this->successResponse(
            $data,
            $message ?? 'Resource created successfully.',
            201
        );
    }

    /**
     * Return a no content response (HTTP 204).
     *
     * Used for successful DELETE operations.
     *
     * @return JsonResponse
     */
    protected function noContentResponse(): JsonResponse
    {
        return response()->json(null, 204);
    }
}
