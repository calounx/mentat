<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Audit log query object for compliance and security tracking.
 *
 * Encapsulates audit log queries with support for:
 * - User activity tracking
 * - Entity-based filtering
 * - Action-based filtering
 * - Date range filtering
 * - IP address tracking
 * - Security event aggregation
 *
 * @example
 * $logs = AuditLogQuery::make()
 *     ->forUser($userId)
 *     ->withAction('site.created')
 *     ->between($startDate, $endDate)
 *     ->paginate(50);
 */
class AuditLogQuery extends BaseQuery
{
    /**
     * Create a new audit log query instance.
     *
     * @param string|null $userId User ID filter
     * @param string|null $organizationId Organization ID filter
     * @param string|null $resourceType Resource type filter
     * @param string|null $resourceId Resource ID filter
     * @param string|null $action Action filter
     * @param \DateTimeInterface|null $startDate Start date filter
     * @param \DateTimeInterface|null $endDate End date filter
     * @param string|null $ipAddress IP address filter
     * @param string $sortBy Sort field
     * @param string $sortDirection Sort direction (asc or desc)
     * @param array $eagerLoad Relationships to eager load
     */
    public function __construct(
        private readonly ?string $userId = null,
        private readonly ?string $organizationId = null,
        private readonly ?string $resourceType = null,
        private readonly ?string $resourceId = null,
        private readonly ?string $action = null,
        private readonly ?\DateTimeInterface $startDate = null,
        private readonly ?\DateTimeInterface $endDate = null,
        private readonly ?string $ipAddress = null,
        private readonly string $sortBy = 'created_at',
        private readonly string $sortDirection = 'desc',
        private readonly array $eagerLoad = ['user', 'organization']
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
     * Filter by user ID.
     *
     * @param string $userId
     * @return static
     */
    public function forUser(string $userId): static
    {
        return new static(
            userId: $userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by organization ID.
     *
     * @param string $organizationId
     * @return static
     */
    public function forOrganization(string $organizationId): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by resource type.
     *
     * @param string $type Resource type (e.g., 'site', 'backup', 'user')
     * @return static
     */
    public function forResourceType(string $type): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $type,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by specific resource.
     *
     * @param string $type Resource type
     * @param string $id Resource ID
     * @return static
     */
    public function forResource(string $type, string $id): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $type,
            resourceId: $id,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by action.
     *
     * @param string $action Action name (e.g., 'user.login', 'site.created')
     * @return static
     */
    public function withAction(string $action): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by IP address.
     *
     * @param string $ipAddress
     * @return static
     */
    public function fromIp(string $ipAddress): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter logs after a specific date.
     *
     * @param \DateTimeInterface $date
     * @return static
     */
    public function after(\DateTimeInterface $date): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $date,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter logs before a specific date.
     *
     * @param \DateTimeInterface $date
     * @return static
     */
    public function before(\DateTimeInterface $date): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $date,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter logs between two dates.
     *
     * @param \DateTimeInterface $start
     * @param \DateTimeInterface $end
     * @return static
     */
    public function between(\DateTimeInterface $start, \DateTimeInterface $end): static
    {
        return new static(
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $start,
            endDate: $end,
            ipAddress: $this->ipAddress,
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
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
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
            userId: $this->userId,
            organizationId: $this->organizationId,
            resourceType: $this->resourceType,
            resourceId: $this->resourceId,
            action: $this->action,
            startDate: $this->startDate,
            endDate: $this->endDate,
            ipAddress: $this->ipAddress,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $relations
        );
    }

    /**
     * Alias for forUser - chainable method.
     *
     * @param string $userId
     * @return static
     */
    public function byUser(string $userId): static
    {
        return $this->forUser($userId);
    }

    /**
     * Alias for forResource - chainable method.
     *
     * @param string $type
     * @param string $id
     * @return static
     */
    public function byEntity(string $type, string $id): static
    {
        return $this->forResource($type, $id);
    }

    /**
     * Alias for withAction - chainable method.
     *
     * @param string $action
     * @return static
     */
    public function byAction(string $action): static
    {
        return $this->withAction($action);
    }

    /**
     * Get logs for security events (login, logout, failed auth).
     *
     * @return \Illuminate\Support\Collection
     */
    public function securityEvents(): \Illuminate\Support\Collection
    {
        return $this->buildQuery()
            ->whereIn('action', [
                'user.login',
                'user.logout',
                'user.login.failed',
                'user.password.changed',
                'user.2fa.enabled',
                'user.2fa.disabled',
            ])
            ->get();
    }

    /**
     * Get logs grouped by action with counts.
     *
     * @return array
     */
    public function countByAction(): array
    {
        $query = DB::table('audit_logs')
            ->select('action', DB::raw('count(*) as count'))
            ->groupBy('action');

        if ($this->userId) {
            $query->where('user_id', $this->userId);
        }

        if ($this->organizationId) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->startDate) {
            $query->where('created_at', '>=', $this->startDate);
        }

        if ($this->endDate) {
            $query->where('created_at', '<=', $this->endDate);
        }

        return $query->pluck('count', 'action')->toArray();
    }

    /**
     * Get logs grouped by user with counts.
     *
     * @return array
     */
    public function countByUser(): array
    {
        $query = DB::table('audit_logs')
            ->select('user_id', DB::raw('count(*) as count'))
            ->whereNotNull('user_id')
            ->groupBy('user_id');

        if ($this->organizationId) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->startDate) {
            $query->where('created_at', '>=', $this->startDate);
        }

        if ($this->endDate) {
            $query->where('created_at', '<=', $this->endDate);
        }

        return $query->pluck('count', 'user_id')->toArray();
    }

    /**
     * Get logs grouped by resource type with counts.
     *
     * @return array
     */
    public function countByResourceType(): array
    {
        $query = DB::table('audit_logs')
            ->select('resource_type', DB::raw('count(*) as count'))
            ->whereNotNull('resource_type')
            ->groupBy('resource_type');

        if ($this->organizationId) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->startDate) {
            $query->where('created_at', '>=', $this->startDate);
        }

        if ($this->endDate) {
            $query->where('created_at', '<=', $this->endDate);
        }

        return $query->pluck('count', 'resource_type')->toArray();
    }

    /**
     * Get unique IP addresses from logs.
     *
     * @return array
     */
    public function uniqueIpAddresses(): array
    {
        return $this->buildQuery()
            ->whereNotNull('ip_address')
            ->distinct()
            ->pluck('ip_address')
            ->toArray();
    }

    /**
     * Get failed login attempts.
     *
     * @return \Illuminate\Support\Collection
     */
    public function failedLogins(): \Illuminate\Support\Collection
    {
        return $this->buildQuery()
            ->where('action', 'user.login.failed')
            ->get();
    }

    /**
     * Get recent activity for a user (last N hours).
     *
     * @param string $userId
     * @param int $hours
     * @return \Illuminate\Support\Collection
     */
    public function recentUserActivity(string $userId, int $hours = 24): \Illuminate\Support\Collection
    {
        return DB::table('audit_logs')
            ->where('user_id', $userId)
            ->where('created_at', '>=', now()->subHours($hours))
            ->orderBy('created_at', 'desc')
            ->get();
    }

    /**
     * Get activity timeline (daily breakdown).
     *
     * @return array
     */
    public function dailyTimeline(): array
    {
        $query = DB::table('audit_logs')
            ->select(DB::raw('DATE(created_at) as date'), DB::raw('count(*) as count'))
            ->groupBy('date')
            ->orderBy('date', 'desc');

        if ($this->userId) {
            $query->where('user_id', $this->userId);
        }

        if ($this->organizationId) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->startDate) {
            $query->where('created_at', '>=', $this->startDate);
        }

        if ($this->endDate) {
            $query->where('created_at', '<=', $this->endDate);
        }

        return $query->pluck('count', 'date')->toArray();
    }

    /**
     * Build the query with all filters applied.
     *
     * @return Builder
     */
    protected function buildQuery(): Builder
    {
        $query = DB::table('audit_logs');

        if ($this->userId !== null) {
            $query->where('user_id', $this->userId);
        }

        if ($this->organizationId !== null) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->resourceType !== null) {
            $query->where('resource_type', $this->resourceType);
        }

        if ($this->resourceId !== null) {
            $query->where('resource_id', $this->resourceId);
        }

        if ($this->action !== null) {
            $query->where('action', $this->action);
        }

        if ($this->ipAddress !== null) {
            $query->where('ip_address', $this->ipAddress);
        }

        if ($this->startDate !== null) {
            $query->where('created_at', '>=', $this->startDate);
        }

        if ($this->endDate !== null) {
            $query->where('created_at', '<=', $this->endDate);
        }

        $this->applySort($query, $this->sortBy, $this->sortDirection);

        return $query;
    }
}
