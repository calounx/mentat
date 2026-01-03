<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Usage report query object for billing and analytics.
 *
 * Generates comprehensive usage reports including:
 * - Site usage statistics
 * - Storage usage tracking
 * - Backup usage and retention
 * - Bandwidth usage (if tracked)
 * - Cost estimation and billing data
 *
 * @example
 * $report = UsageReportQuery::make()
 *     ->forTenant($tenantId)
 *     ->between($startDate, $endDate)
 *     ->getComprehensiveReport();
 */
class UsageReportQuery extends BaseQuery
{
    /**
     * Create a new usage report query instance.
     *
     * @param string $tenantId Tenant ID for filtering
     * @param \DateTimeInterface $startDate Report start date
     * @param \DateTimeInterface $endDate Report end date
     */
    public function __construct(
        private readonly string $tenantId,
        private readonly \DateTimeInterface $startDate,
        private readonly \DateTimeInterface $endDate
    ) {}

    /**
     * Create a new query instance using fluent builder pattern.
     *
     * @param string $tenantId
     * @param \DateTimeInterface $startDate
     * @param \DateTimeInterface $endDate
     * @return static
     */
    public static function make(string $tenantId, \DateTimeInterface $startDate, \DateTimeInterface $endDate): static
    {
        return new static($tenantId, $startDate, $endDate);
    }

    /**
     * Get site usage statistics for the period.
     *
     * @return array
     */
    public function getSiteUsage(): array
    {
        $sitesCreated = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereBetween('created_at', [$this->startDate, $this->endDate])
            ->count();

        $sitesDeleted = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereBetween('deleted_at', [$this->startDate, $this->endDate])
            ->whereNotNull('deleted_at')
            ->count();

        $activeSites = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->where('status', 'active')
            ->whereNull('deleted_at')
            ->count();

        $sitesByType = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereNull('deleted_at')
            ->select('site_type', DB::raw('count(*) as count'))
            ->groupBy('site_type')
            ->pluck('count', 'site_type')
            ->toArray();

        $avgStoragePerSite = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereNull('deleted_at')
            ->avg('storage_used_mb');

        return [
            'period_start' => $this->startDate->format('Y-m-d H:i:s'),
            'period_end' => $this->endDate->format('Y-m-d H:i:s'),
            'sites_created' => $sitesCreated,
            'sites_deleted' => $sitesDeleted,
            'active_sites' => $activeSites,
            'sites_by_type' => $sitesByType,
            'average_storage_mb_per_site' => round($avgStoragePerSite ?? 0, 2),
        ];
    }

    /**
     * Get storage usage statistics for the period.
     *
     * @return array
     */
    public function getStorageUsage(): array
    {
        $totalStorage = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereNull('deleted_at')
            ->sum('storage_used_mb');

        $storageByType = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereNull('deleted_at')
            ->select('site_type', DB::raw('SUM(storage_used_mb) as total_storage'))
            ->groupBy('site_type')
            ->pluck('total_storage', 'site_type')
            ->toArray();

        $backupStorage = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->where('site_backups.status', 'completed')
            ->sum('site_backups.size_mb');

        $totalStorageGb = round($totalStorage / 1024, 2);
        $backupStorageGb = round($backupStorage / 1024, 2);

        return [
            'period_start' => $this->startDate->format('Y-m-d H:i:s'),
            'period_end' => $this->endDate->format('Y-m-d H:i:s'),
            'total_storage_mb' => (int) $totalStorage,
            'total_storage_gb' => $totalStorageGb,
            'storage_by_type_mb' => $storageByType,
            'backup_storage_mb' => (int) $backupStorage,
            'backup_storage_gb' => $backupStorageGb,
            'combined_storage_gb' => round($totalStorageGb + $backupStorageGb, 2),
        ];
    }

    /**
     * Get backup usage statistics for the period.
     *
     * @return array
     */
    public function getBackupUsage(): array
    {
        $backupsCreated = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->count();

        $backupsCompleted = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->where('site_backups.status', 'completed')
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->count();

        $backupsFailed = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->where('site_backups.status', 'failed')
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->count();

        $backupsByType = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->select('site_backups.backup_type', DB::raw('count(*) as count'))
            ->groupBy('site_backups.backup_type')
            ->pluck('count', 'backup_type')
            ->toArray();

        $totalBackupSize = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->where('site_backups.status', 'completed')
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->sum('site_backups.size_bytes');

        $avgBackupSize = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->where('site_backups.status', 'completed')
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->avg('site_backups.size_bytes');

        $successRate = $backupsCreated > 0
            ? round(($backupsCompleted / $backupsCreated) * 100, 2)
            : 0;

        return [
            'period_start' => $this->startDate->format('Y-m-d H:i:s'),
            'period_end' => $this->endDate->format('Y-m-d H:i:s'),
            'backups_created' => $backupsCreated,
            'backups_completed' => $backupsCompleted,
            'backups_failed' => $backupsFailed,
            'success_rate_percent' => $successRate,
            'backups_by_type' => $backupsByType,
            'total_backup_size_bytes' => (int) $totalBackupSize,
            'total_backup_size_gb' => round($totalBackupSize / (1024 * 1024 * 1024), 2),
            'average_backup_size_bytes' => (int) ($avgBackupSize ?? 0),
            'average_backup_size_mb' => round(($avgBackupSize ?? 0) / (1024 * 1024), 2),
        ];
    }

    /**
     * Get bandwidth usage statistics (from usage_records).
     *
     * @return array
     */
    public function getBandwidthUsage(): array
    {
        $bandwidthRecords = DB::table('usage_records')
            ->where('tenant_id', $this->tenantId)
            ->where('metric_type', 'bandwidth_gb')
            ->where(function ($q) {
                $q->whereBetween('period_start', [$this->startDate, $this->endDate])
                    ->orWhereBetween('period_end', [$this->startDate, $this->endDate]);
            })
            ->get();

        $totalBandwidth = $bandwidthRecords->sum('quantity');
        $avgBandwidth = $bandwidthRecords->avg('quantity');

        return [
            'period_start' => $this->startDate->format('Y-m-d H:i:s'),
            'period_end' => $this->endDate->format('Y-m-d H:i:s'),
            'total_bandwidth_gb' => round($totalBandwidth, 2),
            'average_bandwidth_gb' => round($avgBandwidth ?? 0, 2),
            'record_count' => $bandwidthRecords->count(),
        ];
    }

    /**
     * Get cost/billing data from usage records.
     *
     * @return array
     */
    public function getBillingData(): array
    {
        $usageRecords = DB::table('usage_records')
            ->where('tenant_id', $this->tenantId)
            ->where(function ($q) {
                $q->whereBetween('period_start', [$this->startDate, $this->endDate])
                    ->orWhereBetween('period_end', [$this->startDate, $this->endDate]);
            })
            ->get();

        $costByMetric = [];
        $totalCost = 0;

        foreach ($usageRecords as $record) {
            $recordCost = $record->quantity * ($record->unit_price ?? 0);
            $totalCost += $recordCost;

            if (!isset($costByMetric[$record->metric_type])) {
                $costByMetric[$record->metric_type] = [
                    'quantity' => 0,
                    'cost' => 0,
                ];
            }

            $costByMetric[$record->metric_type]['quantity'] += $record->quantity;
            $costByMetric[$record->metric_type]['cost'] += $recordCost;
        }

        return [
            'period_start' => $this->startDate->format('Y-m-d H:i:s'),
            'period_end' => $this->endDate->format('Y-m-d H:i:s'),
            'total_cost' => round($totalCost, 2),
            'cost_by_metric' => array_map(function ($item) {
                return [
                    'quantity' => round($item['quantity'], 2),
                    'cost' => round($item['cost'], 2),
                ];
            }, $costByMetric),
            'record_count' => $usageRecords->count(),
        ];
    }

    /**
     * Get comprehensive usage report combining all metrics.
     *
     * @return array
     */
    public function getComprehensiveReport(): array
    {
        return [
            'tenant_id' => $this->tenantId,
            'report_period' => [
                'start' => $this->startDate->format('Y-m-d H:i:s'),
                'end' => $this->endDate->format('Y-m-d H:i:s'),
                'days' => $this->startDate->diff($this->endDate)->days,
            ],
            'site_usage' => $this->getSiteUsage(),
            'storage_usage' => $this->getStorageUsage(),
            'backup_usage' => $this->getBackupUsage(),
            'bandwidth_usage' => $this->getBandwidthUsage(),
            'billing' => $this->getBillingData(),
            'generated_at' => now()->format('Y-m-d H:i:s'),
        ];
    }

    /**
     * Get daily breakdown of site creation/deletion.
     *
     * @return array
     */
    public function getDailySiteActivity(): array
    {
        $created = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereBetween('created_at', [$this->startDate, $this->endDate])
            ->select(DB::raw('DATE(created_at) as date'), DB::raw('count(*) as count'))
            ->groupBy('date')
            ->pluck('count', 'date')
            ->toArray();

        $deleted = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereBetween('deleted_at', [$this->startDate, $this->endDate])
            ->whereNotNull('deleted_at')
            ->select(DB::raw('DATE(deleted_at) as date'), DB::raw('count(*) as count'))
            ->groupBy('date')
            ->pluck('count', 'date')
            ->toArray();

        return [
            'created_by_day' => $created,
            'deleted_by_day' => $deleted,
        ];
    }

    /**
     * Get monthly summary (for year-long reports).
     *
     * @return array
     */
    public function getMonthlySummary(): array
    {
        $monthlySites = DB::table('sites')
            ->where('tenant_id', $this->tenantId)
            ->whereBetween('created_at', [$this->startDate, $this->endDate])
            ->select(
                DB::raw('YEAR(created_at) as year'),
                DB::raw('MONTH(created_at) as month'),
                DB::raw('count(*) as count')
            )
            ->groupBy('year', 'month')
            ->get()
            ->map(function ($item) {
                return [
                    'period' => sprintf('%04d-%02d', $item->year, $item->month),
                    'sites_created' => $item->count,
                ];
            })
            ->toArray();

        $monthlyBackups = DB::table('site_backups')
            ->join('sites', 'site_backups.site_id', '=', 'sites.id')
            ->where('sites.tenant_id', $this->tenantId)
            ->whereBetween('site_backups.created_at', [$this->startDate, $this->endDate])
            ->select(
                DB::raw('YEAR(site_backups.created_at) as year'),
                DB::raw('MONTH(site_backups.created_at) as month'),
                DB::raw('count(*) as count'),
                DB::raw('SUM(site_backups.size_mb) as total_size_mb')
            )
            ->groupBy('year', 'month')
            ->get()
            ->map(function ($item) {
                return [
                    'period' => sprintf('%04d-%02d', $item->year, $item->month),
                    'backups_created' => $item->count,
                    'total_size_mb' => (int) $item->total_size_mb,
                ];
            })
            ->toArray();

        return [
            'sites' => $monthlySites,
            'backups' => $monthlyBackups,
        ];
    }

    /**
     * Build the base query (required by BaseQuery, not heavily used here).
     *
     * @return Builder
     */
    protected function buildQuery(): Builder
    {
        return DB::table('usage_records')
            ->where('tenant_id', $this->tenantId)
            ->where(function ($q) {
                $q->whereBetween('period_start', [$this->startDate, $this->endDate])
                    ->orWhereBetween('period_end', [$this->startDate, $this->endDate]);
            });
    }
}
