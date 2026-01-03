<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Team member query object for organization and team queries.
 *
 * Encapsulates team member queries with support for:
 * - Organization-based filtering
 * - Role-based filtering
 * - User search
 * - Active/inactive status
 * - Role aggregation and statistics
 *
 * @example
 * $members = TeamMemberQuery::make()
 *     ->forOrganization($orgId)
 *     ->withRole('admin')
 *     ->active()
 *     ->paginate(20);
 */
class TeamMemberQuery extends BaseQuery
{
    /**
     * Create a new team member query instance.
     *
     * @param string|null $organizationId Organization ID for filtering
     * @param string|null $role Role filter (owner, admin, member)
     * @param string|null $search Search term for user name/email
     * @param bool|null $active Active status filter
     * @param string $sortBy Sort field
     * @param string $sortDirection Sort direction (asc or desc)
     * @param array $eagerLoad Relationships to eager load
     */
    public function __construct(
        private readonly ?string $organizationId = null,
        private readonly ?string $role = null,
        private readonly ?string $search = null,
        private readonly ?bool $active = true,
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
     * Filter by organization ID.
     *
     * @param string $organizationId
     * @return static
     */
    public function forOrganization(string $organizationId): static
    {
        return new static(
            organizationId: $organizationId,
            role: $this->role,
            search: $this->search,
            active: $this->active,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by role.
     *
     * @param string $role Role value (owner, admin, member)
     * @return static
     */
    public function withRole(string $role): static
    {
        return new static(
            organizationId: $this->organizationId,
            role: $role,
            search: $this->search,
            active: $this->active,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Search by user name or email.
     *
     * @param string $term Search term
     * @return static
     */
    public function search(string $term): static
    {
        return new static(
            organizationId: $this->organizationId,
            role: $this->role,
            search: $term,
            active: $this->active,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter active members only.
     *
     * @return static
     */
    public function active(): static
    {
        return new static(
            organizationId: $this->organizationId,
            role: $this->role,
            search: $this->search,
            active: true,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter inactive members only.
     *
     * @return static
     */
    public function inactive(): static
    {
        return new static(
            organizationId: $this->organizationId,
            role: $this->role,
            search: $this->search,
            active: false,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Include both active and inactive members.
     *
     * @return static
     */
    public function all(): static
    {
        return new static(
            organizationId: $this->organizationId,
            role: $this->role,
            search: $this->search,
            active: null,
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
            organizationId: $this->organizationId,
            role: $this->role,
            search: $this->search,
            active: $this->active,
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
            organizationId: $this->organizationId,
            role: $this->role,
            search: $this->search,
            active: $this->active,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $relations
        );
    }

    /**
     * Get count of members grouped by role.
     *
     * @return array
     */
    public function countByRole(): array
    {
        $query = DB::table('users')
            ->select('role', DB::raw('count(*) as count'))
            ->groupBy('role');

        if ($this->organizationId) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->active !== null) {
            $query->where('is_active', $this->active);
        }

        return $query->pluck('count', 'role')->toArray();
    }

    /**
     * Get all owners.
     *
     * @return \Illuminate\Support\Collection
     */
    public function owners(): \Illuminate\Support\Collection
    {
        return $this->withRole('owner')->get();
    }

    /**
     * Get all admins.
     *
     * @return \Illuminate\Support\Collection
     */
    public function admins(): \Illuminate\Support\Collection
    {
        return $this->withRole('admin')->get();
    }

    /**
     * Get all members (non-admin, non-owner).
     *
     * @return \Illuminate\Support\Collection
     */
    public function members(): \Illuminate\Support\Collection
    {
        return $this->withRole('member')->get();
    }

    /**
     * Get members who joined recently (within days).
     *
     * @param int $days Number of days
     * @return \Illuminate\Support\Collection
     */
    public function recentlyJoined(int $days = 30): \Illuminate\Support\Collection
    {
        $query = $this->buildQuery();
        $query->where('users.created_at', '>=', now()->subDays($days));

        return $query->get();
    }

    /**
     * Get members who haven't logged in recently (within days).
     *
     * @param int $days Number of days
     * @return \Illuminate\Support\Collection
     */
    public function inactiveSince(int $days = 90): \Illuminate\Support\Collection
    {
        $query = DB::table('users');

        if ($this->organizationId) {
            $query->where('organization_id', $this->organizationId);
        }

        $query->where(function ($q) use ($days) {
            $q->whereNull('last_login_at')
                ->orWhere('last_login_at', '<', now()->subDays($days));
        });

        if ($this->active !== null) {
            $query->where('is_active', $this->active);
        }

        return $query->get();
    }

    /**
     * Get total active members count.
     *
     * @return int
     */
    public function activeCount(): int
    {
        return $this->active()->count();
    }

    /**
     * Get total inactive members count.
     *
     * @return int
     */
    public function inactiveCount(): int
    {
        return $this->inactive()->count();
    }

    /**
     * Build the query with all filters applied.
     *
     * @return Builder
     */
    protected function buildQuery(): Builder
    {
        $query = DB::table('users');

        if ($this->organizationId !== null) {
            $query->where('organization_id', $this->organizationId);
        }

        if ($this->role !== null) {
            $query->where('role', $this->role);
        }

        if ($this->search !== null && $this->search !== '') {
            $query->where(function ($q) {
                $q->where('name', 'like', '%' . $this->search . '%')
                    ->orWhere('email', 'like', '%' . $this->search . '%');
            });
        }

        if ($this->active !== null) {
            $query->where('is_active', $this->active);
        }

        $query->whereNull('deleted_at');

        $this->applySort($query, $this->sortBy, $this->sortDirection);

        return $query;
    }
}
