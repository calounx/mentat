<?php

declare(strict_types=1);

namespace Tests\Database;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Database migration tests
 *
 * Tests all migrations can be run and rolled back successfully
 *
 * @package Tests\Database
 */
class MigrationTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test all migrations run successfully
     *
     * @return void
     */
    public function test_all_migrations_run_successfully(): void
    {
        Artisan::call('migrate:fresh');

        $this->assertTrue(Schema::hasTable('users'));
        $this->assertTrue(Schema::hasTable('sites'));
        $this->assertTrue(Schema::hasTable('backups'));
    }

    /**
     * Test all migrations can be rolled back
     *
     * @return void
     */
    public function test_all_migrations_can_be_rolled_back(): void
    {
        Artisan::call('migrate:fresh');
        Artisan::call('migrate:rollback', ['--step' => 999]);

        $this->assertFalse(Schema::hasTable('sites'));
    }

    /**
     * Test critical indexes exist
     *
     * @return void
     */
    public function test_critical_indexes_exist(): void
    {
        $indexes = Schema::getIndexes('sites');
        $indexColumns = collect($indexes)->pluck('columns')->flatten();

        $this->assertTrue($indexColumns->contains('user_id'));
        $this->assertTrue($indexColumns->contains('domain'));
    }

    /**
     * Test foreign keys are properly set
     *
     * @return void
     */
    public function test_foreign_keys_are_properly_configured(): void
    {
        $foreignKeys = Schema::getForeignKeys('sites');

        $this->assertNotEmpty($foreignKeys);

        $userIdFk = collect($foreignKeys)->first(
            fn($fk) => in_array('user_id', $fk['columns'])
        );

        $this->assertNotNull($userIdFk);
        $this->assertEquals('users', $userIdFk['foreign_table']);
    }
}
