<?php

declare(strict_types=1);

namespace Tests\Database;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Test database index usage
 *
 * Ensures queries use appropriate indexes for performance
 *
 * @package Tests\Database
 */
class IndexUsageTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test sites table has required indexes
     *
     * @return void
     */
    public function test_sites_table_has_required_indexes(): void
    {
        $indexes = Schema::getIndexes('sites');
        $indexColumns = collect($indexes)->pluck('columns')->flatten();

        $requiredIndexes = ['user_id', 'domain', 'status'];

        foreach ($requiredIndexes as $column) {
            $this->assertTrue(
                $indexColumns->contains($column),
                "Missing index on sites.{$column}"
            );
        }
    }

    /**
     * Test backups table has required indexes
     *
     * @return void
     */
    public function test_backups_table_has_required_indexes(): void
    {
        $indexes = Schema::getIndexes('backups');
        $indexColumns = collect($indexes)->pluck('columns')->flatten();

        $this->assertTrue($indexColumns->contains('site_id'));
        $this->assertTrue($indexColumns->contains('created_at'));
    }

    /**
     * Test composite indexes exist where needed
     *
     * @return void
     */
    public function test_composite_indexes_exist(): void
    {
        $indexes = Schema::getIndexes('sites');

        // Check for composite index on (user_id, status)
        $compositeIndex = collect($indexes)->first(function ($index) {
            return count($index['columns']) > 1
                && in_array('user_id', $index['columns'])
                && in_array('status', $index['columns']);
        });

        $this->assertNotNull($compositeIndex, 'Missing composite index on (user_id, status)');
    }

    /**
     * Test queries actually use indexes
     *
     * @return void
     */
    public function test_queries_use_indexes(): void
    {
        // Skip if not MySQL/PostgreSQL
        if (!in_array(DB::connection()->getDriverName(), ['mysql', 'pgsql'])) {
            $this->markTestSkipped('Index usage testing requires MySQL or PostgreSQL');
        }

        $query = 'SELECT * FROM sites WHERE user_id = ?';
        $explain = DB::select("EXPLAIN {$query}", [1]);

        $usesIndex = collect($explain)->contains(function ($row) {
            $key = $row->key ?? $row->KEY ?? null;
            return $key !== null && $key !== '';
        });

        $this->assertTrue($usesIndex, 'Query does not use index on user_id');
    }
}
