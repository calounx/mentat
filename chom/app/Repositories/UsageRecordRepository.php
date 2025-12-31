<?php

namespace App\Repositories;

use App\Models\Tenant;
use App\Models\UsageRecord;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;

/**
 * Usage Record Repository.
 *
 * Handles complex usage record queries and billing calculations.
 * Implements Repository pattern to separate data access from business logic.
 */
class UsageRecordRepository
{
    /**
     * Get usage records for tenant in a specific period.
     *
     * @param Tenant $tenant
     * @param Carbon $startDate
     * @param Carbon $endDate
     * @return Collection
     */
    public function getByTenantAndPeriod(
        Tenant $tenant,
        Carbon $startDate,
        Carbon $endDate
    ): Collection {
        return UsageRecord::where('tenant_id', $tenant->id)
            ->whereBetween('recorded_at', [$startDate, $endDate])
            ->orderBy('recorded_at', 'desc')
            ->get();
    }

    /**
     * Calculate billing totals for a tenant in a period.
     *
     * @param Tenant $tenant
     * @param Carbon $startDate
     * @param Carbon $endDate
     * @return array
     */
    public function calculateBillingTotals(
        Tenant $tenant,
        Carbon $startDate,
        Carbon $endDate
    ): array {
        $records = $this->getByTenantAndPeriod($tenant, $startDate, $endDate);

        $totals = [
            'bandwidth_gb' => 0,
            'storage_gb' => 0,
            'compute_hours' => 0,
            'total_cost' => 0,
            'record_count' => $records->count(),
        ];

        foreach ($records as $record) {
            $totals['bandwidth_gb'] += $record->bandwidth_gb ?? 0;
            $totals['storage_gb'] += $record->storage_gb ?? 0;
            $totals['compute_hours'] += $record->compute_hours ?? 0;
            $totals['total_cost'] += $record->cost ?? 0;
        }

        // Round values
        $totals['bandwidth_gb'] = round($totals['bandwidth_gb'], 2);
        $totals['storage_gb'] = round($totals['storage_gb'], 2);
        $totals['compute_hours'] = round($totals['compute_hours'], 2);
        $totals['total_cost'] = round($totals['total_cost'], 2);

        return $totals;
    }

    /**
     * Get usage summary by resource type for tenant.
     *
     * @param Tenant $tenant
     * @param Carbon $startDate
     * @param Carbon $endDate
     * @return array
     */
    public function getUsageSummaryByType(
        Tenant $tenant,
        Carbon $startDate,
        Carbon $endDate
    ): array {
        $records = $this->getByTenantAndPeriod($tenant, $startDate, $endDate);

        return [
            'bandwidth' => [
                'total_gb' => round($records->sum('bandwidth_gb'), 2),
                'average_gb' => round($records->avg('bandwidth_gb'), 2),
                'peak_gb' => round($records->max('bandwidth_gb'), 2),
            ],
            'storage' => [
                'total_gb' => round($records->sum('storage_gb'), 2),
                'average_gb' => round($records->avg('storage_gb'), 2),
                'peak_gb' => round($records->max('storage_gb'), 2),
            ],
            'compute' => [
                'total_hours' => round($records->sum('compute_hours'), 2),
                'average_hours' => round($records->avg('compute_hours'), 2),
                'peak_hours' => round($records->max('compute_hours'), 2),
            ],
        ];
    }

    /**
     * Get daily usage aggregates for a tenant.
     *
     * @param Tenant $tenant
     * @param Carbon $startDate
     * @param Carbon $endDate
     * @return Collection
     */
    public function getDailyAggregates(
        Tenant $tenant,
        Carbon $startDate,
        Carbon $endDate
    ): Collection {
        return UsageRecord::where('tenant_id', $tenant->id)
            ->whereBetween('recorded_at', [$startDate, $endDate])
            ->select([
                DB::raw('DATE(recorded_at) as date'),
                DB::raw('SUM(bandwidth_gb) as total_bandwidth_gb'),
                DB::raw('AVG(storage_gb) as avg_storage_gb'),
                DB::raw('SUM(compute_hours) as total_compute_hours'),
                DB::raw('SUM(cost) as total_cost'),
            ])
            ->groupBy(DB::raw('DATE(recorded_at)'))
            ->orderBy('date', 'asc')
            ->get();
    }

    /**
     * Get current month usage for tenant.
     *
     * @param Tenant $tenant
     * @return array
     */
    public function getCurrentMonthUsage(Tenant $tenant): array
    {
        $startDate = Carbon::now()->startOfMonth();
        $endDate = Carbon::now()->endOfMonth();

        return $this->calculateBillingTotals($tenant, $startDate, $endDate);
    }

    /**
     * Get previous month usage for tenant.
     *
     * @param Tenant $tenant
     * @return array
     */
    public function getPreviousMonthUsage(Tenant $tenant): array
    {
        $startDate = Carbon::now()->subMonth()->startOfMonth();
        $endDate = Carbon::now()->subMonth()->endOfMonth();

        return $this->calculateBillingTotals($tenant, $startDate, $endDate);
    }

    /**
     * Record new usage.
     *
     * @param array $data
     * @return UsageRecord
     */
    public function record(array $data): UsageRecord
    {
        return UsageRecord::create($data);
    }

    /**
     * Get usage trend (comparing current to previous period).
     *
     * @param Tenant $tenant
     * @param Carbon $startDate
     * @param Carbon $endDate
     * @return array
     */
    public function getUsageTrend(
        Tenant $tenant,
        Carbon $startDate,
        Carbon $endDate
    ): array {
        $currentPeriod = $this->calculateBillingTotals($tenant, $startDate, $endDate);

        $periodDuration = $startDate->diffInDays($endDate);
        $previousStart = $startDate->copy()->subDays($periodDuration);
        $previousEnd = $endDate->copy()->subDays($periodDuration);

        $previousPeriod = $this->calculateBillingTotals($tenant, $previousStart, $previousEnd);

        return [
            'current' => $currentPeriod,
            'previous' => $previousPeriod,
            'trends' => [
                'bandwidth_change_percent' => $this->calculatePercentChange(
                    $previousPeriod['bandwidth_gb'],
                    $currentPeriod['bandwidth_gb']
                ),
                'storage_change_percent' => $this->calculatePercentChange(
                    $previousPeriod['storage_gb'],
                    $currentPeriod['storage_gb']
                ),
                'cost_change_percent' => $this->calculatePercentChange(
                    $previousPeriod['total_cost'],
                    $currentPeriod['total_cost']
                ),
            ],
        ];
    }

    /**
     * Calculate percent change between two values.
     *
     * @param float $old
     * @param float $new
     * @return float
     */
    private function calculatePercentChange(float $old, float $new): float
    {
        if ($old == 0) {
            return $new > 0 ? 100 : 0;
        }

        return round((($new - $old) / $old) * 100, 2);
    }

    /**
     * Get top resource consumers.
     *
     * @param Carbon $startDate
     * @param Carbon $endDate
     * @param string $resourceType (bandwidth, storage, compute)
     * @param int $limit
     * @return Collection
     */
    public function getTopConsumers(
        Carbon $startDate,
        Carbon $endDate,
        string $resourceType = 'bandwidth',
        int $limit = 10
    ): Collection {
        $column = match ($resourceType) {
            'bandwidth' => 'bandwidth_gb',
            'storage' => 'storage_gb',
            'compute' => 'compute_hours',
            default => 'bandwidth_gb',
        };

        return UsageRecord::whereBetween('recorded_at', [$startDate, $endDate])
            ->select([
                'tenant_id',
                DB::raw("SUM({$column}) as total"),
            ])
            ->groupBy('tenant_id')
            ->orderBy('total', 'desc')
            ->limit($limit)
            ->with('tenant:id,name')
            ->get();
    }

    /**
     * Check if tenant exceeds quota.
     *
     * @param Tenant $tenant
     * @param string $resourceType
     * @param float $quota
     * @param Carbon|null $startDate
     * @return bool
     */
    public function exceedsQuota(
        Tenant $tenant,
        string $resourceType,
        float $quota,
        ?Carbon $startDate = null
    ): bool {
        $startDate = $startDate ?? Carbon::now()->startOfMonth();
        $endDate = Carbon::now();

        $usage = $this->calculateBillingTotals($tenant, $startDate, $endDate);

        $usedAmount = match ($resourceType) {
            'bandwidth' => $usage['bandwidth_gb'],
            'storage' => $usage['storage_gb'],
            'compute' => $usage['compute_hours'],
            default => 0,
        };

        return $usedAmount > $quota;
    }
}
