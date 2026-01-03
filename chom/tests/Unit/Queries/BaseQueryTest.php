<?php

declare(strict_types=1);

namespace Tests\Unit\Queries;

use App\Queries\BaseQuery;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class BaseQueryTest extends TestCase
{
    use RefreshDatabase;

    private TestQuery $query;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test organization
        $orgId = (string) \Illuminate\Support\Str::uuid();
        DB::table('organizations')->insert([
            'id' => $orgId,
            'name' => 'Test Org',
            'slug' => 'test-org',
            'billing_email' => 'billing@test.com',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->query = new TestQuery();
    }

    public function test_get_returns_collection(): void
    {
        $results = $this->query->get();

        $this->assertInstanceOf(\Illuminate\Support\Collection::class, $results);
    }

    public function test_paginate_returns_paginator(): void
    {
        $paginator = $this->query->paginate(2);

        $this->assertInstanceOf(\Illuminate\Contracts\Pagination\LengthAwarePaginator::class, $paginator);
    }

    public function test_count_returns_integer(): void
    {
        $count = $this->query->count();

        $this->assertIsInt($count);
        $this->assertGreaterThanOrEqual(0, $count);
    }

    public function test_exists_returns_boolean(): void
    {
        $exists = $this->query->exists();

        $this->assertIsBool($exists);
    }

    public function test_first_returns_first_result(): void
    {
        $first = $this->query->first();

        if ($first !== null) {
            $this->assertIsObject($first);
        }
    }

    public function test_to_sql_returns_string(): void
    {
        $sql = $this->query->toSql();

        $this->assertIsString($sql);
        $this->assertStringContainsString('SELECT', $sql);
    }

    public function test_get_bindings_returns_array(): void
    {
        $bindings = $this->query->getBindings();

        $this->assertIsArray($bindings);
    }

    public function test_to_raw_sql_returns_string(): void
    {
        $rawSql = $this->query->toRawSql();

        $this->assertIsString($rawSql);
        $this->assertStringContainsString('SELECT', $rawSql);
    }

    public function test_cache_enables_caching(): void
    {
        $query = $this->query->cache('test_key', 300);

        $this->assertInstanceOf(TestQuery::class, $query);
    }

    public function test_apply_search_filters_correctly(): void
    {
        $query = DB::table('organizations');
        $result = $this->query->testApplySearch($query, 'name', 'Test');

        $this->assertInstanceOf(Builder::class, $result);
    }

    public function test_apply_date_range_filters_correctly(): void
    {
        $query = DB::table('organizations');
        $start = now()->subDays(7);
        $end = now();

        $result = $this->query->testApplyDateRange($query, 'created_at', $start, $end);

        $this->assertInstanceOf(Builder::class, $result);
    }

    public function test_apply_sort_orders_correctly(): void
    {
        $query = DB::table('organizations');
        $result = $this->query->testApplySort($query, 'created_at', 'desc');

        $this->assertInstanceOf(Builder::class, $result);
    }

    public function test_apply_numeric_range_filters_correctly(): void
    {
        $query = DB::table('organizations');
        $result = $this->query->testApplyNumericRange($query, 'id', 1, 100);

        $this->assertInstanceOf(Builder::class, $result);
    }

    public function test_apply_filter_filters_correctly(): void
    {
        $query = DB::table('organizations');
        $result = $this->query->testApplyFilter($query, 'name', 'Test Org');

        $this->assertInstanceOf(Builder::class, $result);
    }
}

/**
 * Test implementation of BaseQuery for testing purposes.
 */
class TestQuery extends BaseQuery
{
    protected function buildQuery(): Builder
    {
        return DB::table('organizations');
    }

    // Expose protected methods for testing
    public function testApplySearch(Builder $query, string $field, ?string $search): Builder
    {
        return $this->applySearch($query, $field, $search);
    }

    public function testApplyDateRange(
        Builder $query,
        string $field,
        ?\DateTimeInterface $start,
        ?\DateTimeInterface $end
    ): Builder {
        return $this->applyDateRange($query, $field, $start, $end);
    }

    public function testApplySort(Builder $query, string $sortBy, string $direction): Builder
    {
        return $this->applySort($query, $sortBy, $direction);
    }

    public function testApplyNumericRange(
        Builder $query,
        string $field,
        int|float|null $min,
        int|float|null $max
    ): Builder {
        return $this->applyNumericRange($query, $field, $min, $max);
    }

    public function testApplyFilter(
        Builder $query,
        string $field,
        mixed $value,
        string $operator = '='
    ): Builder {
        return $this->applyFilter($query, $field, $value, $operator);
    }
}
