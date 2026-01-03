<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Cache;

/**
 * Base query object providing common functionality for all query objects.
 *
 * This abstract class implements the Query Object pattern to encapsulate
 * complex database queries with reusable, testable components.
 *
 * @abstract
 */
abstract class BaseQuery
{
    /**
     * The Eloquent query builder instance.
     */
    protected Builder $query;

    /**
     * Cache key for query results (null = no caching).
     */
    protected ?string $cacheKey = null;

    /**
     * Cache TTL in seconds (default: 5 minutes).
     */
    protected int $cacheTtl = 300;

    /**
     * Whether to enable query result caching.
     */
    protected bool $enableCache = false;

    /**
     * Build the query with all filters and conditions applied.
     *
     * @return Builder
     */
    abstract protected function buildQuery(): Builder;

    /**
     * Get all results from the query.
     *
     * @return Collection
     */
    public function get(): Collection
    {
        if ($this->enableCache && $this->cacheKey) {
            return Cache::remember(
                $this->cacheKey,
                $this->cacheTtl,
                fn() => $this->buildQuery()->get()
            );
        }

        return $this->buildQuery()->get();
    }

    /**
     * Get paginated results from the query.
     *
     * @param int $perPage Number of items per page
     * @return LengthAwarePaginator
     */
    public function paginate(int $perPage = 15): LengthAwarePaginator
    {
        return $this->buildQuery()->paginate($perPage);
    }

    /**
     * Get the total count of results.
     *
     * @return int
     */
    public function count(): int
    {
        if ($this->enableCache && $this->cacheKey) {
            return Cache::remember(
                $this->cacheKey . '_count',
                $this->cacheTtl,
                fn() => $this->buildQuery()->count()
            );
        }

        return $this->buildQuery()->count();
    }

    /**
     * Check if any results exist.
     *
     * @return bool
     */
    public function exists(): bool
    {
        return $this->buildQuery()->exists();
    }

    /**
     * Get the first result.
     *
     * @return mixed
     */
    public function first(): mixed
    {
        return $this->buildQuery()->first();
    }

    /**
     * Get the SQL query string with bindings.
     *
     * @return string
     */
    public function toSql(): string
    {
        return $this->buildQuery()->toSql();
    }

    /**
     * Get the query bindings.
     *
     * @return array
     */
    public function getBindings(): array
    {
        return $this->buildQuery()->getBindings();
    }

    /**
     * Get the SQL query with bindings interpolated (for debugging).
     *
     * @return string
     */
    public function toRawSql(): string
    {
        $query = $this->buildQuery();
        $sql = $query->toSql();
        $bindings = $query->getBindings();

        foreach ($bindings as $binding) {
            $value = is_numeric($binding) ? $binding : "'" . addslashes((string)$binding) . "'";
            $sql = preg_replace('/\?/', (string)$value, $sql, 1);
        }

        return $sql;
    }

    /**
     * Enable query result caching.
     *
     * @param string $key Cache key
     * @param int $ttl Time to live in seconds
     * @return static
     */
    public function cache(string $key, int $ttl = 300): static
    {
        $this->enableCache = true;
        $this->cacheKey = $key;
        $this->cacheTtl = $ttl;

        return $this;
    }

    /**
     * Apply a search filter on a specific field.
     *
     * @param Builder $query The query builder instance
     * @param string $field The field to search
     * @param string|null $search The search term
     * @return Builder
     */
    protected function applySearch(Builder $query, string $field, ?string $search): Builder
    {
        if ($search !== null && $search !== '') {
            $query->where($field, 'like', '%' . $search . '%');
        }

        return $query;
    }

    /**
     * Apply a date range filter.
     *
     * @param Builder $query The query builder instance
     * @param string $field The date field to filter
     * @param \DateTimeInterface|null $start Start date
     * @param \DateTimeInterface|null $end End date
     * @return Builder
     */
    protected function applyDateRange(
        Builder $query,
        string $field,
        ?\DateTimeInterface $start,
        ?\DateTimeInterface $end
    ): Builder {
        if ($start !== null) {
            $query->where($field, '>=', $start);
        }

        if ($end !== null) {
            $query->where($field, '<=', $end);
        }

        return $query;
    }

    /**
     * Apply sorting to the query.
     *
     * @param Builder $query The query builder instance
     * @param string $sortBy Field to sort by
     * @param string $direction Sort direction (asc or desc)
     * @return Builder
     */
    protected function applySort(Builder $query, string $sortBy, string $direction = 'desc'): Builder
    {
        $direction = strtolower($direction);

        if (!in_array($direction, ['asc', 'desc'])) {
            $direction = 'desc';
        }

        return $query->orderBy($sortBy, $direction);
    }

    /**
     * Apply a numeric range filter.
     *
     * @param Builder $query The query builder instance
     * @param string $field The field to filter
     * @param int|float|null $min Minimum value
     * @param int|float|null $max Maximum value
     * @return Builder
     */
    protected function applyNumericRange(
        Builder $query,
        string $field,
        int|float|null $min,
        int|float|null $max
    ): Builder {
        if ($min !== null) {
            $query->where($field, '>=', $min);
        }

        if ($max !== null) {
            $query->where($field, '<=', $max);
        }

        return $query;
    }

    /**
     * Apply a filter if value is not null.
     *
     * @param Builder $query The query builder instance
     * @param string $field The field to filter
     * @param mixed $value The value to filter by
     * @param string $operator The comparison operator
     * @return Builder
     */
    protected function applyFilter(
        Builder $query,
        string $field,
        mixed $value,
        string $operator = '='
    ): Builder {
        if ($value !== null) {
            $query->where($field, $operator, $value);
        }

        return $query;
    }

    /**
     * Apply eager loading relationships.
     *
     * @param Builder $query The query builder instance
     * @param array $relations Array of relationships to eager load
     * @return Builder
     */
    protected function applyEagerLoad(Builder $query, array $relations): Builder
    {
        if (!empty($relations)) {
            $query->with($relations);
        }

        return $query;
    }
}
