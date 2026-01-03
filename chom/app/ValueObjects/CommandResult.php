<?php

declare(strict_types=1);

namespace App\ValueObjects;

/**
 * Command Result Value Object
 *
 * Represents the result of a command execution on a remote server.
 * Immutable value object containing exit code, output, and error streams.
 *
 * @package App\ValueObjects
 */
final class CommandResult
{
    /**
     * @param int $exitCode Command exit code (0 = success)
     * @param string $output Standard output stream
     * @param string $error Standard error stream
     * @param float $executionTime Execution time in seconds
     * @param string|null $command The command that was executed
     */
    public function __construct(
        public readonly int $exitCode,
        public readonly string $output,
        public readonly string $error,
        public readonly float $executionTime = 0.0,
        public readonly ?string $command = null
    ) {
    }

    /**
     * Create successful result
     *
     * @param string $output
     * @param float $executionTime
     * @return self
     */
    public static function success(string $output = '', float $executionTime = 0.0): self
    {
        return new self(0, $output, '', $executionTime);
    }

    /**
     * Create failed result
     *
     * @param string $error
     * @param int $exitCode
     * @param string $output
     * @param float $executionTime
     * @return self
     */
    public static function failure(
        string $error,
        int $exitCode = 1,
        string $output = '',
        float $executionTime = 0.0
    ): self {
        return new self($exitCode, $output, $error, $executionTime);
    }

    /**
     * Check if command was successful
     *
     * @return bool
     */
    public function isSuccessful(): bool
    {
        return $this->exitCode === 0;
    }

    /**
     * Check if command failed
     *
     * @return bool
     */
    public function isFailed(): bool
    {
        return $this->exitCode !== 0;
    }

    /**
     * Get combined output (stdout + stderr)
     *
     * @return string
     */
    public function getCombinedOutput(): string
    {
        $output = $this->output;
        if (!empty($this->error)) {
            $output .= "\n" . $this->error;
        }
        return trim($output);
    }

    /**
     * Get output lines as array
     *
     * @return array<string>
     */
    public function getOutputLines(): array
    {
        return array_filter(explode("\n", $this->output));
    }

    /**
     * Get error lines as array
     *
     * @return array<string>
     */
    public function getErrorLines(): array
    {
        return array_filter(explode("\n", $this->error));
    }

    /**
     * Convert to array representation
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'exit_code' => $this->exitCode,
            'output' => $this->output,
            'error' => $this->error,
            'execution_time' => $this->executionTime,
            'command' => $this->command,
            'successful' => $this->isSuccessful(),
        ];
    }

    /**
     * Convert to JSON string
     *
     * @return string
     */
    public function toJson(): string
    {
        return json_encode($this->toArray(), JSON_THROW_ON_ERROR);
    }
}
