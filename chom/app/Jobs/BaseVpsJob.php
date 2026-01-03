<?php

namespace App\Jobs;

use App\Models\VpsServer;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Base VPS Job
 *
 * Abstract base class for all VPS-related jobs.
 * Provides common functionality for VPS operations including:
 * - VPS server validation
 * - Consistent error handling
 * - Structured logging
 * - Retry logic with exponential backoff
 * - Job execution tracking
 *
 * @package App\Jobs
 */
abstract class BaseVpsJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * Number of times the job may be attempted.
     *
     * @var int
     */
    public int $tries = 3;

    /**
     * Job timeout in seconds (5 minutes).
     *
     * @var int
     */
    public int $timeout = 300;

    /**
     * Exponential backoff delays in seconds.
     *
     * @var array<int>
     */
    public array $backoff = [60, 120, 300];

    /**
     * Job start time for execution tracking.
     *
     * @var float|null
     */
    protected ?float $startTime = null;

    /**
     * Handle the job execution.
     *
     * This method must be implemented by all child classes.
     *
     * @return void
     */
    abstract public function handle(): void;

    /**
     * Validate that VPS server is online and reachable.
     *
     * Checks VPS server status and health before executing operations.
     *
     * @param VpsServer $vps
     * @return bool
     * @throws \RuntimeException if VPS is not available for operations
     */
    protected function validateVpsServer(VpsServer $vps): bool
    {
        $this->logInfo('Validating VPS server', [
            'vps_id' => $vps->id,
            'hostname' => $vps->hostname,
            'status' => $vps->status,
            'health_status' => $vps->health_status,
        ]);

        if (!in_array($vps->status, ['active', 'provisioning'], true)) {
            $message = sprintf(
                'VPS server is not available for operations. Current status: %s',
                $vps->status
            );

            $this->logError('VPS validation failed', [
                'vps_id' => $vps->id,
                'status' => $vps->status,
                'reason' => 'invalid_status',
            ]);

            throw new \RuntimeException($message);
        }

        if ($vps->health_status === 'unhealthy') {
            $message = sprintf(
                'VPS server health check failed. Cannot proceed with operations on unhealthy server: %s',
                $vps->hostname
            );

            $this->logWarning('VPS health check warning', [
                'vps_id' => $vps->id,
                'health_status' => $vps->health_status,
            ]);

            throw new \RuntimeException($message);
        }

        $this->logInfo('VPS server validation passed', [
            'vps_id' => $vps->id,
        ]);

        return true;
    }

    /**
     * Log job start with context.
     *
     * @param string $operation
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logJobStart(string $operation, array $context = []): void
    {
        $this->startTime = microtime(true);

        $this->logInfo("Job started: {$operation}", array_merge($context, [
            'job_class' => static::class,
            'attempt' => $this->attempts(),
            'queue' => $this->queue,
        ]));
    }

    /**
     * Log successful job completion.
     *
     * @param string $operation
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logJobSuccess(string $operation, array $context = []): void
    {
        $executionTime = $this->getExecutionTime();

        $this->logInfo("Job completed successfully: {$operation}", array_merge($context, [
            'job_class' => static::class,
            'execution_time_ms' => $executionTime,
            'attempt' => $this->attempts(),
        ]));
    }

    /**
     * Log job failure with stack trace.
     *
     * @param string $operation
     * @param Throwable $e
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logJobFailure(string $operation, Throwable $e, array $context = []): void
    {
        $executionTime = $this->getExecutionTime();

        $this->logError("Job failed: {$operation}", array_merge($context, [
            'job_class' => static::class,
            'execution_time_ms' => $executionTime,
            'attempt' => $this->attempts(),
            'max_tries' => $this->tries,
            'exception' => get_class($e),
            'message' => $e->getMessage(),
            'file' => $e->getFile(),
            'line' => $e->getLine(),
            'trace' => $e->getTraceAsString(),
        ]));
    }

    /**
     * Handle VPS-specific errors with user-friendly messages.
     *
     * Parses common VPS errors and provides appropriate handling.
     *
     * @param Throwable $e
     * @return void
     * @throws Throwable
     */
    protected function handleVpsError(Throwable $e): void
    {
        $message = $e->getMessage();
        $errorType = $this->categorizeVpsError($e);

        $this->logError('VPS operation error', [
            'error_type' => $errorType,
            'message' => $message,
            'exception' => get_class($e),
        ]);

        switch ($errorType) {
            case 'connection_timeout':
                $userMessage = 'Failed to connect to VPS server. The server may be unreachable or experiencing network issues.';
                break;

            case 'auth_failure':
                $userMessage = 'Authentication failed. SSH credentials may be invalid or expired.';
                break;

            case 'permission_denied':
                $userMessage = 'Permission denied. The SSH user may not have sufficient privileges.';
                break;

            case 'host_key_verification':
                $userMessage = 'SSH host key verification failed. The server fingerprint may have changed.';
                break;

            case 'network_unreachable':
                $userMessage = 'Network unreachable. Please check VPS server network configuration.';
                break;

            case 'disk_full':
                $userMessage = 'VPS disk is full. Please free up space before retrying.';
                break;

            default:
                $userMessage = 'An error occurred during VPS operation: ' . $message;
                break;
        }

        throw new \RuntimeException($userMessage, $e->getCode(), $e);
    }

    /**
     * Categorize VPS error type based on exception.
     *
     * @param Throwable $e
     * @return string
     */
    protected function categorizeVpsError(Throwable $e): string
    {
        $message = strtolower($e->getMessage());

        if (str_contains($message, 'timeout') || str_contains($message, 'timed out')) {
            return 'connection_timeout';
        }

        if (str_contains($message, 'authentication') || str_contains($message, 'auth failed')) {
            return 'auth_failure';
        }

        if (str_contains($message, 'permission denied')) {
            return 'permission_denied';
        }

        if (str_contains($message, 'host key verification')) {
            return 'host_key_verification';
        }

        if (str_contains($message, 'network unreachable') || str_contains($message, 'no route to host')) {
            return 'network_unreachable';
        }

        if (str_contains($message, 'disk full') || str_contains($message, 'no space left')) {
            return 'disk_full';
        }

        return 'unknown';
    }

    /**
     * Get the number of seconds to wait before retrying the job.
     *
     * @return int
     */
    public function retryAfter(): int
    {
        return 60;
    }

    /**
     * Calculate job execution time in milliseconds.
     *
     * @return float
     */
    protected function getExecutionTime(): float
    {
        if ($this->startTime === null) {
            return 0.0;
        }

        return round((microtime(true) - $this->startTime) * 1000, 2);
    }

    /**
     * Log info level message.
     *
     * @param string $message
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logInfo(string $message, array $context = []): void
    {
        Log::channel('stack')->info($message, array_merge($context, [
            'channel' => 'jobs',
            'job_id' => $this->job?->getJobId(),
        ]));
    }

    /**
     * Log warning level message.
     *
     * @param string $message
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logWarning(string $message, array $context = []): void
    {
        Log::channel('stack')->warning($message, array_merge($context, [
            'channel' => 'jobs',
            'job_id' => $this->job?->getJobId(),
        ]));
    }

    /**
     * Log error level message.
     *
     * @param string $message
     * @param array<string, mixed> $context
     * @return void
     */
    protected function logError(string $message, array $context = []): void
    {
        Log::channel('stack')->error($message, array_merge($context, [
            'channel' => 'jobs',
            'job_id' => $this->job?->getJobId(),
        ]));
    }

    /**
     * Handle a job failure.
     *
     * @param Throwable $exception
     * @return void
     */
    public function failed(Throwable $exception): void
    {
        $this->logError('Job failed permanently after all retries', [
            'job_class' => static::class,
            'attempts' => $this->attempts(),
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
        ]);
    }
}
