<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Backup search query object with comprehensive filtering capabilities.
 *
 * Encapsulates complex backup search logic with support for:
 * - Tenant and site filtering
 * - Status filtering
 * - Backup type filtering
 * - Date range filtering
 * - Size range filtering
 * - Retention and expiration queries
 *
 * @example
 * $backups = BackupSearchQuery::make()
 *     ->forSite($siteId)
 *     ->withStatus('completed')
 *     ->createdBetween($startDate, $endDate)
 *     ->minimumSize(100 * 1024 * 1024)
 *     ->paginate(20);
 */
class BackupSearchQuery extends BaseQuery
{
    /**
     * Create a new backup search query instance.
     *
     * @param string|null $tenantId Tenant ID for filtering
     * @param string|null $siteId Site ID for filtering
     * @param string|null $status Backup status filter
     * @param string|null $type Backup type filter
     * @param \DateTimeInterface|null $createdAfter Created after date
     * @param \DateTimeInterface|null $createdBefore Created before date
     * @param int|null $minSize Minimum size in bytes
     * @param int|null $maxSize Maximum size in bytes
     * @param string $sortBy Sort field
     * @param string $sortDirection Sort direction (asc or desc)
     * @param array $eagerLoad Relationships to eager load
     */
    public function __construct(
        private readonly ?string $tenantId = null,
        private readonly ?string $siteId = null,
        private readonly ?string $status = null,
        private readonly ?string $type = null,
        private readonly ?\DateTimeInterface $createdAfter = null,
        private readonly ?\DateTimeInterface $createdBefore = null,
        private readonly ?int $minSize = null,
        private readonly ?int $maxSize = null,
        private readonly string $sortBy = 'created_at',
        private readonly string $sortDirection = 'desc',
        private readonly array $eagerLoad = ['site']
    ) {}

    /**
     * Create a new query instance using fluent builder pattern.
     *
     * @return static
     */
    public static function make(): static
    {
        return new static();
    }

    /**
     * Filter by tenant ID.
     *
     * @param string $tenantId
     * @return static
     */
    public function forTenant(string $tenantId): static
    {
        return new static(
            tenantId: $tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by site ID.
     *
     * @param string $siteId
     * @return static
     */
    public function forSite(string $siteId): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by backup status.
     *
     * @param string $status Status value (pending, in_progress, completed, failed)
     * @return static
     */
    public function withStatus(string $status): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by backup type.
     *
     * @param string $type Backup type (full, files, database, config, manual, scheduled)
     * @return static
     */
    public function withType(string $type): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter backups created after a specific date.
     *
     * @param \DateTimeInterface $date
     * @return static
     */
    public function createdAfter(\DateTimeInterface $date): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $date,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter backups created before a specific date.
     *
     * @param \DateTimeInterface $date
     * @return static
     */
    public function createdBefore(\DateTimeInterface $date): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $date,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter backups created between two dates.
     *
     * @param \DateTimeInterface $start
     * @param \DateTimeInterface $end
     * @return static
     */
    public function createdBetween(\DateTimeInterface $start, \DateTimeInterface $end): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $start,
            createdBefore: $end,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter backups with minimum size in bytes.
     *
     * @param int $bytes
     * @return static
     */
    public function minimumSize(int $bytes): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $bytes,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter backups with maximum size in bytes.
     *
     * @param int $bytes
     * @return static
     */
    public function maximumSize(int $bytes): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $bytes,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Sort by specified field and direction.
     *
     * @param string $field Field to sort by
     * @param string $direction Sort direction (asc or desc)
     * @return static
     */
    public function sortBy(string $field, string $direction = 'desc'): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $field,
            sortDirection: $direction,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Specify relationships to eager load.
     *
     * @param array $relations
     * @return static
     */
    public function with(array $relations): static
    {
        return new static(
            tenantId: $this->tenantId,
            siteId: $this->siteId,
            status: $this->status,
            type: $this->type,
            createdAfter: $this->createdAfter,
            createdBefore: $this->createdBefore,
            minSize: $this->minSize,
            maxSize: $this->maxSize,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $relations
        );
    }

    /**
     * Get the oldest backup.
     *
     * @return mixed
     */
    public function oldest(): mixed
    {
        return $this->buildQuery()->orderBy('created_at', 'asc')->first();
    }

    /**
     * Get the latest backup.
     *
     * @return mixed
     */
    public function latest(): mixed
    {
        return $this->buildQuery()->orderBy('created_at', 'desc')->first();
    }

    /**
     * Get total size of all matching backups in bytes.
     *
     * @return int
     */
    public function totalSize(): int
    {
        return (int) $this->buildQuery()->sum('size_bytes');
    }

    /**
     * Get total size of all matching backups in MB.
     *
     * @return int
     */
    public function totalSizeMb(): int
    {
        return (int) $this->buildQuery()->sum('size_mb');
    }

    /**
     * Get backups that are expired.
     *
     * @return \Illuminate\Support\Collection
     */
    public function expired(): \Illuminate\Support\Collection
    {
        return $this->buildQuery()
            ->whereNotNull('expires_at')
            ->where('expires_at', '<=', now())
            ->get();
    }

    /**
     * Get backups expiring soon (within days).
     *
     * @param int $days Number of days
     * @return \Illuminate\Support\Collection
     */
    public function expiringSoon(int $days = 7): \Illuminate\Support\Collection
    {
        return $this->buildQuery()
            ->whereNotNull('expires_at')
            ->where('expires_at', '<=', now()->addDays($days))
            ->where('expires_at', '>', now())
            ->get();
    }

    /**
     * Get backups grouped by status with counts.
     *
     * @return array
     */
    public function countByStatus(): array
    {
        $query = DB::table('site_backups')
            ->select('status', DB::raw('count(*) as count'))
            ->groupBy('status');

        if ($this->siteId) {
            $query->where('site_id', $this->siteId);
        }

        if ($this->tenantId) {
            $query->join('sites', 'site_backups.site_id', '=', 'sites.id')
                ->where('sites.tenant_id', $this->tenantId);
        }

        return $query->pluck('count', 'status')->toArray();
    }

    /**
     * Get backups grouped by type with counts.
     *
     * @return array
     */
    public function countByType(): array
    {
        $query = DB::table('site_backups')
            ->select('backup_type', DB::raw('count(*) as count'))
            ->groupBy('backup_type');

        if ($this->siteId) {
            $query->where('site_id', $this->siteId);
        }

        if ($this->tenantId) {
            $query->join('sites', 'site_backups.site_id', '=', 'sites.id')
                ->where('sites.tenant_id', $this->tenantId);
        }

        return $query->pluck('count', 'backup_type')->toArray();
    }

    /**
     * Get average backup size in bytes.
     *
     * @return float
     */
    public function averageSize(): float
    {
        return (float) $this->buildQuery()->avg('size_bytes');
    }

    /**
     * Build the query with all filters applied.
     *
     * @return Builder
     */
    protected function buildQuery(): Builder
    {
        $query = DB::table('site_backups');

        if ($this->siteId !== null) {
            $query->where('site_id', $this->siteId);
        }

        if ($this->tenantId !== null) {
            $query->join('sites', 'site_backups.site_id', '=', 'sites.id')
                ->where('sites.tenant_id', $this->tenantId)
                ->select('site_backups.*');
        }

        if ($this->status !== null) {
            $query->where('site_backups.status', $this->status);
        }

        if ($this->type !== null) {
            $query->where('backup_type', $this->type);
        }

        if ($this->createdAfter !== null) {
            $query->where('site_backups.created_at', '>=', $this->createdAfter);
        }

        if ($this->createdBefore !== null) {
            $query->where('site_backups.created_at', '<=', $this->createdBefore);
        }

        if ($this->minSize !== null) {
            $query->where('size_bytes', '>=', $this->minSize);
        }

        if ($this->maxSize !== null) {
            $query->where('size_bytes', '<=', $this->maxSize);
        }

        $this->applySort($query, 'site_backups.' . $this->sortBy, $this->sortDirection);

        return $query;
    }
}
