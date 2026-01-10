<?php

declare(strict_types=1);

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

/**
 * Base TestCase for all application tests.
 * Each test should declare RefreshDatabase if needed.
 *
 * @package Tests
 */
abstract class TestCase extends BaseTestCase
{
    /**
     * Creates the application.
     *
     * @return \Illuminate\Foundation\Application
     */
    public function createApplication()
    {
        $app = require __DIR__ . '/../../bootstrap/app.php';

        $app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

        return $app;
    }

    /**
     * Set up the test case.
     * Clean up any lingering transactions to prevent nesting issues.
     *
     * @return void
     */
    protected function setUp(): void
    {
        parent::setUp();

        // Clean up any lingering transactions from previous tests
        // This prevents transaction nesting issues with RefreshDatabase + manual transactions
        if (isset($this->app)) {
            $db = $this->app->make('db');
            $connection = $db->connection();

            while ($connection->transactionLevel() > 0) {
                $connection->rollBack();
            }
        }
    }
}
