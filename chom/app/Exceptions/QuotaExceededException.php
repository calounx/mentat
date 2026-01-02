<?php

namespace App\Exceptions;

use Exception;

/**
 * Quota Exceeded Exception
 *
 * Thrown when a tenant attempts to exceed their quota limits.
 */
class QuotaExceededException extends Exception
{
    /**
     * Additional context data about the quota violation.
     *
     * @var array<string, mixed>
     */
    protected array $context;

    /**
     * Create a new quota exceeded exception.
     *
     * @param  string  $message  The exception message
     * @param  array<string, mixed>  $context  Additional context
     * @param  int  $code  The exception code
     * @param  \Throwable|null  $previous  Previous exception
     */
    public function __construct(
        string $message = 'Quota exceeded',
        array $context = [],
        int $code = 0,
        ?\Throwable $previous = null
    ) {
        parent::__construct($message, $code, $previous);
        $this->context = $context;
    }

    /**
     * Get the exception context.
     *
     * @return array<string, mixed>
     */
    public function getContext(): array
    {
        return $this->context;
    }

    /**
     * Render the exception as an HTTP response.
     *
     * @return \Illuminate\Http\JsonResponse
     */
    public function render()
    {
        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'QUOTA_EXCEEDED',
                'message' => $this->getMessage(),
                'details' => $this->context,
            ],
        ], 403);
    }
}
