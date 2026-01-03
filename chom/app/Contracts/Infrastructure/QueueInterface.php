<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

/**
 * Queue Interface
 *
 * Defines the contract for queue operations.
 * Provides abstraction over queue backends (Redis, Database, SQS, etc.)
 *
 * Design Pattern: Command Pattern - queue stores commands for later execution
 * SOLID Principle: Interface Segregation - focused queue interface
 *
 * @package App\Contracts\Infrastructure
 */
interface QueueInterface
{
    /**
     * Push a job onto the queue
     *
     * @param string $job Job class name
     * @param array<string, mixed> $data Job data
     * @param string|null $queue Queue name
     * @return string|int Job ID
     */
    public function push(string $job, array $data = [], ?string $queue = null): string|int;

    /**
     * Push a job onto the queue with delay
     *
     * @param int $delay Delay in seconds
     * @param string $job Job class name
     * @param array<string, mixed> $data Job data
     * @param string|null $queue Queue name
     * @return string|int Job ID
     */
    public function later(int $delay, string $job, array $data = [], ?string $queue = null): string|int;

    /**
     * Push a job onto a specific queue
     *
     * @param string $queue Queue name
     * @param string $job Job class name
     * @param array<string, mixed> $data Job data
     * @return string|int Job ID
     */
    public function pushOn(string $queue, string $job, array $data = []): string|int;

    /**
     * Get the size of a queue
     *
     * @param string|null $queue Queue name
     * @return int Number of jobs in queue
     */
    public function size(?string $queue = null): int;

    /**
     * Delete a job from the queue
     *
     * @param string|int $id Job ID
     * @param string|null $queue Queue name
     * @return bool True if deletion was successful
     */
    public function delete(string|int $id, ?string $queue = null): bool;

    /**
     * Release a job back to the queue
     *
     * @param string|int $id Job ID
     * @param int $delay Delay in seconds before re-attempting
     * @param string|null $queue Queue name
     * @return bool True if release was successful
     */
    public function release(string|int $id, int $delay = 0, ?string $queue = null): bool;

    /**
     * Get queue connection name
     *
     * @return string Connection name
     */
    public function getConnectionName(): string;

    /**
     * Set queue connection
     *
     * @param string $connection Connection name
     * @return self
     */
    public function setConnection(string $connection): self;
}
