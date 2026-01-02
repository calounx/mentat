<?php

declare(strict_types=1);

namespace Tests\Database;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Database migration tests
 *
 * Tests all migrations can be run and rolled back successfully
 */
class MigrationTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test all migrations run successfully
     *
     * Note: Skipped to avoid VACUUM transaction issues with SQLite
     */
    public function test_all_migrations_run_successfully(): void
    {
        if (DB::connection()->getDriverName() === 'sqlite') {
            $this->markTestSkipped('Skipping migrate:fresh test on SQLite to avoid VACUUM transaction issues');
        }

        Artisan::call('migrate:fresh', ['--force' => true]);

        $this->assertTrue(Schema::hasTable('users'));
        $this->assertTrue(Schema::hasTable('sites'));
        $this->assertTrue(Schema::hasTable('site_backups'));
    }

    /**
     * Test all migrations can be rolled back
     *
     * Note: Skipped to avoid VACUUM transaction issues with SQLite
     */
    public function test_all_migrations_can_be_rolled_back(): void
    {
        if (DB::connection()->getDriverName() === 'sqlite') {
            $this->markTestSkipped('Skipping migrate:rollback test on SQLite to avoid VACUUM transaction issues');
        }

        Artisan::call('migrate:fresh', ['--force' => true]);
        Artisan::call('migrate:rollback', ['--step' => 999, '--force' => true]);

        $this->assertFalse(Schema::hasTable('sites'));
    }

    /**
     * Test critical indexes exist
     */
    public function test_critical_indexes_exist(): void
    {
        $indexes = Schema::getIndexes('sites');
        $indexColumns = collect($indexes)->pluck('columns')->flatten();

        $this->assertTrue($indexColumns->contains('tenant_id'));
        $this->assertTrue($indexColumns->contains('domain'));
    }

    /**
     * Test foreign keys are properly set
     */
    public function test_foreign_keys_are_properly_configured(): void
    {
        $foreignKeys = Schema::getForeignKeys('sites');

        $this->assertNotEmpty($foreignKeys);

        $tenantIdFk = collect($foreignKeys)->first(
            fn ($fk) => in_array('tenant_id', $fk['columns'])
        );

        $this->assertNotNull($tenantIdFk);
        $this->assertEquals('tenants', $tenantIdFk['foreign_table']);
    }
}
