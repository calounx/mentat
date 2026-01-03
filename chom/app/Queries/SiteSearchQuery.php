<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Site search query object with comprehensive filtering capabilities.
 *
 * Encapsulates complex site search logic with support for:
 * - Domain name searching
 * - Status filtering
 * - Site type filtering
 * - PHP version filtering
 * - SSL status filtering
 * - Tenant isolation
 * - Custom sorting
 *
 * @example
 * $sites = SiteSearchQuery::make()
 *     ->forTenant($tenantId)
 *     ->withStatus('active')
 *     ->search('example.com')
 *     ->sslEnabled()
 *     ->paginate(20);
 */
class SiteSearchQuery extends BaseQuery
{
    /**
     * Create a new site search query instance.
     *
     * @param string|null $tenantId Tenant ID for isolation
     * @param string|null $search Search term for domain name
     * @param string|null $status Site status filter
     * @param string|null $siteType Site type filter
     * @param string|null $phpVersion PHP version filter
     * @param bool|null $sslEnabled SSL enabled filter
     * @param string $sortBy Sort field
     * @param string $sortDirection Sort direction (asc or desc)
     * @param array $eagerLoad Relationships to eager load
     */
    public function __construct(
        private readonly ?string $tenantId = null,
        private readonly ?string $search = null,
        private readonly ?string $status = null,
        private readonly ?string $siteType = null,
        private readonly ?string $phpVersion = null,
        private readonly ?bool $sslEnabled = null,
        private readonly string $sortBy = 'created_at',
        private readonly string $sortDirection = 'desc',
        private readonly array $eagerLoad = ['vpsServer', 'tenant']
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
            search: $this->search,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: $this->sslEnabled,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Search by domain name.
     *
     * @param string $term Search term
     * @return static
     */
    public function search(string $term): static
    {
        return new static(
            tenantId: $this->tenantId,
            search: $term,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: $this->sslEnabled,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by status.
     *
     * @param string $status Status value (creating, active, disabled, failed, deleting)
     * @return static
     */
    public function withStatus(string $status): static
    {
        return new static(
            tenantId: $this->tenantId,
            search: $this->search,
            status: $status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: $this->sslEnabled,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by site type.
     *
     * @param string $type Site type (wordpress, html, laravel)
     * @return static
     */
    public function withType(string $type): static
    {
        return new static(
            tenantId: $this->tenantId,
            search: $this->search,
            status: $this->status,
            siteType: $type,
            phpVersion: $this->phpVersion,
            sslEnabled: $this->sslEnabled,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by PHP version.
     *
     * @param string $version PHP version
     * @return static
     */
    public function withPhpVersion(string $version): static
    {
        return new static(
            tenantId: $this->tenantId,
            search: $this->search,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $version,
            sslEnabled: $this->sslEnabled,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter sites with SSL enabled.
     *
     * @return static
     */
    public function sslEnabled(): static
    {
        return new static(
            tenantId: $this->tenantId,
            search: $this->search,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: true,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter sites with SSL disabled.
     *
     * @return static
     */
    public function sslDisabled(): static
    {
        return new static(
            tenantId: $this->tenantId,
            search: $this->search,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: false,
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
            search: $this->search,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: $this->sslEnabled,
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
            search: $this->search,
            status: $this->status,
            siteType: $this->siteType,
            phpVersion: $this->phpVersion,
            sslEnabled: $this->sslEnabled,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $relations
        );
    }

    /**
     * Get sites that have SSL expiring soon (within days).
     *
     * @param int $days Number of days
     * @return \Illuminate\Support\Collection
     */
    public function sslExpiringSoon(int $days = 30): \Illuminate\Support\Collection
    {
        return DB::table('sites')
            ->where('ssl_enabled', true)
            ->whereNotNull('ssl_expires_at')
            ->where('ssl_expires_at', '<=', now()->addDays($days))
            ->where('ssl_expires_at', '>=', now())
            ->when($this->tenantId, fn($q) => $q->where('tenant_id', $this->tenantId))
            ->get();
    }

    /**
     * Get total storage used across filtered sites.
     *
     * @return int Total storage in MB
     */
    public function totalStorageUsed(): int
    {
        return (int) $this->buildQuery()->sum('storage_used_mb');
    }

    /**
     * Get sites grouped by status with counts.
     *
     * @return array
     */
    public function countByStatus(): array
    {
        $query = DB::table('sites')
            ->select('status', DB::raw('count(*) as count'))
            ->groupBy('status');

        if ($this->tenantId) {
            $query->where('tenant_id', $this->tenantId);
        }

        return $query->pluck('count', 'status')->toArray();
    }

    /**
     * Get sites grouped by site type with counts.
     *
     * @return array
     */
    public function countByType(): array
    {
        $query = DB::table('sites')
            ->select('site_type', DB::raw('count(*) as count'))
            ->groupBy('site_type');

        if ($this->tenantId) {
            $query->where('tenant_id', $this->tenantId);
        }

        return $query->pluck('count', 'site_type')->toArray();
    }

    /**
     * Get sites grouped by PHP version with counts.
     *
     * @return array
     */
    public function countByPhpVersion(): array
    {
        $query = DB::table('sites')
            ->select('php_version', DB::raw('count(*) as count'))
            ->groupBy('php_version');

        if ($this->tenantId) {
            $query->where('tenant_id', $this->tenantId);
        }

        return $query->pluck('count', 'php_version')->toArray();
    }

    /**
     * Build the query with all filters applied.
     *
     * @return Builder
     */
    protected function buildQuery(): Builder
    {
        $query = DB::table('sites');

        if ($this->tenantId !== null) {
            $query->where('tenant_id', $this->tenantId);
        }

        if ($this->search !== null && $this->search !== '') {
            $query->where('domain', 'like', '%' . $this->search . '%');
        }

        if ($this->status !== null) {
            $query->where('status', $this->status);
        }

        if ($this->siteType !== null) {
            $query->where('site_type', $this->siteType);
        }

        if ($this->phpVersion !== null) {
            $query->where('php_version', $this->phpVersion);
        }

        if ($this->sslEnabled !== null) {
            $query->where('ssl_enabled', $this->sslEnabled);
        }

        $query->whereNull('deleted_at');

        $this->applySort($query, $this->sortBy, $this->sortDirection);

        return $query;
    }
}
