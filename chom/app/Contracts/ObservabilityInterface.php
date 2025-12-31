<?php

namespace App\Contracts;

use App\Models\Site;
use App\Models\VpsServer;

/**
 * Interface for observability and monitoring operations.
 *
 * This interface defines the contract for collecting and querying metrics,
 * logs, and traces from sites and VPS servers.
 */
interface ObservabilityInterface
{
    /**
     * Send a custom metric.
     *
     * @param string $metricName The name of the metric
     * @param float $value The metric value
     * @param array<string, string> $tags Additional tags/labels
     * @return void
     */
    public function sendMetric(string $metricName, float $value, array $tags = []): void;

    /**
     * Get site performance metrics.
     *
     * @param Site $site The site to get metrics for
     * @param \DateTimeInterface $from Start time
     * @param \DateTimeInterface $to End time
     * @return array{requests_per_minute?: float, response_time_ms?: float, error_rate?: float, bandwidth_mb?: float}
     */
    public function getSiteMetrics(Site $site, \DateTimeInterface $from, \DateTimeInterface $to): array;

    /**
     * Get VPS server metrics.
     *
     * @param VpsServer $vps The VPS server
     * @param \DateTimeInterface $from Start time
     * @param \DateTimeInterface $to End time
     * @return array{cpu_percent?: float, memory_percent?: float, disk_percent?: float, network_in_mb?: float, network_out_mb?: float}
     */
    public function getVpsMetrics(VpsServer $vps, \DateTimeInterface $from, \DateTimeInterface $to): array;

    /**
     * Get recent logs for a site.
     *
     * @param Site $site The site to get logs for
     * @param int $limit Maximum number of log entries
     * @param string|null $level Filter by log level (error, warning, info, debug)
     * @return array<array{timestamp: string, level: string, message: string}>
     */
    public function getSiteLogs(Site $site, int $limit = 100, ?string $level = null): array;

    /**
     * Log an event for audit purposes.
     *
     * @param string $eventType The type of event
     * @param string $entityType The type of entity (site, vps, tenant)
     * @param string $entityId The entity ID
     * @param array<string, mixed> $metadata Additional event metadata
     * @return void
     */
    public function logEvent(string $eventType, string $entityType, string $entityId, array $metadata = []): void;

    /**
     * Create an alert/notification.
     *
     * @param string $severity The alert severity (critical, warning, info)
     * @param string $title The alert title
     * @param string $message The alert message
     * @param array<string, mixed> $context Additional context
     * @return void
     */
    public function createAlert(string $severity, string $title, string $message, array $context = []): void;

    /**
     * Check if observability is configured and working.
     *
     * @return bool
     */
    public function isConfigured(): bool;
}
