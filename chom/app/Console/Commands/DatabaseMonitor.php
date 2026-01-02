<?php

namespace App\Console\Commands;

use Exception;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Database monitoring command for performance tracking and health checks.
 *
 * Features:
 * - Real-time query performance monitoring
 * - Slow query detection and analysis
 * - Index usage statistics
 * - Table size and growth trending
 * - Connection pool monitoring
 * - Lock contention detection
 * - Backup status tracking
 */
class DatabaseMonitor extends Command
{
    protected $signature = 'db:monitor
                          {--type=overview : Type of monitoring (overview, queries, indexes, tables, locks, backups)}
                          {--slow=1000 : Slow query threshold in milliseconds}
                          {--watch : Continuous monitoring mode (refresh every 5s)}
                          {--json : Output in JSON format}';

    protected $description = 'Monitor database performance and health metrics';

    protected array $metrics = [];

    public function handle(): int
    {
        $type = $this->option('type');

        if ($this->option('watch')) {
            return $this->watchMode();
        }

        return $this->runMonitoring($type);
    }

    /**
     * Continuous monitoring mode.
     */
    protected function watchMode(): int
    {
        $type = $this->option('type');

        while (true) {
            // Clear screen
            if (PHP_OS_FAMILY !== 'Windows') {
                system('clear');
            }

            $this->line('Database Monitor (Press Ctrl+C to exit)');
            $this->line('Updated: '.now()->format('Y-m-d H:i:s'));
            $this->newLine();

            $this->runMonitoring($type, false);

            sleep(5);
        }

        return Command::SUCCESS;
    }

    /**
     * Run monitoring based on type.
     */
    protected function runMonitoring(string $type, bool $showHeader = true): int
    {
        try {
            if ($showHeader) {
                $this->info('========================================');
                $this->info('  Database Performance Monitor');
                $this->info('========================================');
                $this->newLine();
            }

            match ($type) {
                'overview' => $this->monitorOverview(),
                'queries' => $this->monitorQueries(),
                'indexes' => $this->monitorIndexes(),
                'tables' => $this->monitorTables(),
                'locks' => $this->monitorLocks(),
                'backups' => $this->monitorBackups(),
                default => $this->monitorOverview(),
            };

            if ($this->option('json')) {
                $this->line(json_encode($this->metrics, JSON_PRETTY_PRINT));
            }

            return Command::SUCCESS;

        } catch (Exception $e) {
            $this->error('Monitoring failed: '.$e->getMessage());

            return Command::FAILURE;
        }
    }

    /**
     * Display database overview.
     */
    protected function monitorOverview(): void
    {
        $driver = DB::connection()->getDriverName();

        $this->info('Database Overview');
        $this->line('Driver: '.$driver);
        $this->line('Connection: '.config('database.default'));
        $this->newLine();

        if ($driver === 'mysql' || $driver === 'mariadb') {
            $this->mysqlOverview();
        } elseif ($driver === 'sqlite') {
            $this->sqliteOverview();
        } elseif ($driver === 'pgsql') {
            $this->postgresqlOverview();
        }
    }

    /**
     * MySQL/MariaDB overview metrics.
     */
    protected function mysqlOverview(): void
    {
        // Database size
        $size = DB::selectOne("
            SELECT
                ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb,
                ROUND(SUM(data_length) / 1024 / 1024, 2) AS data_mb,
                ROUND(SUM(index_length) / 1024 / 1024, 2) AS index_mb
            FROM information_schema.TABLES
            WHERE table_schema = DATABASE()
        ");

        $this->table(
            ['Metric', 'Value'],
            [
                ['Total Size', $size->size_mb.' MB'],
                ['Data Size', $size->data_mb.' MB'],
                ['Index Size', $size->index_mb.' MB'],
            ]
        );

        $this->metrics['database_size'] = [
            'total_mb' => $size->size_mb,
            'data_mb' => $size->data_mb,
            'index_mb' => $size->index_mb,
        ];

        $this->newLine();

        // Connection stats
        $this->info('Connection Statistics');
        $connections = DB::select('SHOW STATUS LIKE "Threads_%"');
        $connectionData = [];
        foreach ($connections as $conn) {
            $connectionData[] = [$conn->Variable_name, $conn->Value];
            $this->metrics['connections'][strtolower($conn->Variable_name)] = $conn->Value;
        }
        $this->table(['Variable', 'Value'], $connectionData);

        $this->newLine();

        // Query cache stats (if enabled)
        $this->info('Query Performance');
        $queryStats = DB::select('SHOW GLOBAL STATUS LIKE "Questions"');
        $uptime = DB::selectOne('SHOW GLOBAL STATUS LIKE "Uptime"');

        $questions = $queryStats[0]->Value ?? 0;
        $uptimeSeconds = $uptime->Value ?? 1;
        $qps = round($questions / $uptimeSeconds, 2);

        $this->table(
            ['Metric', 'Value'],
            [
                ['Total Queries', number_format($questions)],
                ['Uptime', $this->formatDuration($uptimeSeconds)],
                ['Queries/Second', $qps],
            ]
        );

        $this->metrics['query_performance'] = [
            'total_queries' => $questions,
            'uptime_seconds' => $uptimeSeconds,
            'queries_per_second' => $qps,
        ];

        $this->newLine();

        // InnoDB buffer pool
        $this->info('InnoDB Buffer Pool');
        $bufferPool = DB::select('SHOW GLOBAL STATUS LIKE "Innodb_buffer_pool_%"');
        $bufferData = [];
        foreach (array_slice($bufferPool, 0, 5) as $stat) {
            $bufferData[] = [$stat->Variable_name, $this->formatValue($stat->Value)];
        }
        $this->table(['Variable', 'Value'], $bufferData);
    }

    /**
     * SQLite overview metrics.
     */
    protected function sqliteOverview(): void
    {
        $dbPath = DB::connection()->getDatabaseName();

        if (file_exists($dbPath)) {
            $size = filesize($dbPath);
            $sizeMB = round($size / 1024 / 1024, 2);

            $this->table(
                ['Metric', 'Value'],
                [
                    ['Database File', basename($dbPath)],
                    ['File Size', $sizeMB.' MB'],
                    ['Path', $dbPath],
                ]
            );

            $this->metrics['database_size'] = [
                'total_mb' => $sizeMB,
                'path' => $dbPath,
            ];
        }

        // Get table count
        $tables = DB::select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
        $this->newLine();
        $this->info('Tables: '.count($tables));

        $this->metrics['table_count'] = count($tables);
    }

    /**
     * PostgreSQL overview metrics.
     */
    protected function postgresqlOverview(): void
    {
        $size = DB::selectOne("
            SELECT
                pg_database_size(current_database()) as size_bytes
        ");

        $sizeMB = round($size->size_bytes / 1024 / 1024, 2);

        $this->table(
            ['Metric', 'Value'],
            [
                ['Database Size', $sizeMB.' MB'],
            ]
        );

        $this->metrics['database_size'] = [
            'total_mb' => $sizeMB,
        ];
    }

    /**
     * Monitor slow queries.
     */
    protected function monitorQueries(): void
    {
        $this->info('Slow Query Analysis');
        $this->newLine();

        $driver = DB::connection()->getDriverName();

        if ($driver === 'mysql' || $driver === 'mariadb') {
            // Check if slow query log is enabled
            $slowLogStatus = DB::selectOne("SHOW VARIABLES LIKE 'slow_query_log'");

            if ($slowLogStatus->Value === 'OFF') {
                $this->warn('Slow query log is disabled.');
                $this->line('Enable with: SET GLOBAL slow_query_log = 1;');
                $this->line('Set threshold: SET GLOBAL long_query_time = '.($this->option('slow') / 1000).';');

                return;
            }

            // Get slow query log file path
            $slowLogFile = DB::selectOne("SHOW VARIABLES LIKE 'slow_query_log_file'");
            $this->line('Slow query log: '.$slowLogFile->Value);
            $this->newLine();

            // Show processlist for currently running queries
            $this->info('Currently Running Queries');
            $processes = DB::select('SHOW FULL PROCESSLIST');

            $runningQueries = collect($processes)
                ->filter(fn ($p) => $p->Command !== 'Sleep' && ! empty($p->Info))
                ->map(fn ($p) => [
                    'ID' => $p->Id,
                    'User' => $p->User,
                    'Time' => $p->Time.'s',
                    'Query' => substr($p->Info, 0, 60).'...',
                ])
                ->toArray();

            if (! empty($runningQueries)) {
                $this->table(['ID', 'User', 'Time', 'Query'], $runningQueries);
                $this->metrics['running_queries'] = count($runningQueries);
            } else {
                $this->line('No active queries');
                $this->metrics['running_queries'] = 0;
            }
        }
    }

    /**
     * Monitor index usage.
     */
    protected function monitorIndexes(): void
    {
        $this->info('Index Usage Statistics');
        $this->newLine();

        $driver = DB::connection()->getDriverName();

        if ($driver === 'mysql' || $driver === 'mariadb') {
            // Get index statistics
            $indexes = DB::select("
                SELECT
                    TABLE_NAME,
                    INDEX_NAME,
                    NON_UNIQUE,
                    SEQ_IN_INDEX,
                    COLUMN_NAME,
                    CARDINALITY
                FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND INDEX_NAME != 'PRIMARY'
                ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX
                LIMIT 20
            ");

            $indexData = [];
            foreach ($indexes as $index) {
                $indexData[] = [
                    $index->TABLE_NAME,
                    $index->INDEX_NAME,
                    $index->NON_UNIQUE ? 'No' : 'Yes',
                    $index->COLUMN_NAME,
                    number_format($index->CARDINALITY ?? 0),
                ];
            }

            $this->table(
                ['Table', 'Index', 'Unique', 'Column', 'Cardinality'],
                $indexData
            );

            $this->metrics['index_count'] = count($indexes);

            // Find unused indexes (requires performance_schema)
            $this->newLine();
            $this->info('Index Efficiency Analysis');

            try {
                $unusedIndexes = DB::select("
                    SELECT
                        OBJECT_SCHEMA,
                        OBJECT_NAME,
                        INDEX_NAME
                    FROM performance_schema.table_io_waits_summary_by_index_usage
                    WHERE INDEX_NAME IS NOT NULL
                      AND INDEX_NAME != 'PRIMARY'
                      AND COUNT_STAR = 0
                      AND OBJECT_SCHEMA = DATABASE()
                    LIMIT 10
                ");

                if (! empty($unusedIndexes)) {
                    $this->warn('Potentially unused indexes detected:');
                    foreach ($unusedIndexes as $idx) {
                        $this->line("  - {$idx->OBJECT_NAME}.{$idx->INDEX_NAME}");
                    }
                    $this->metrics['unused_indexes'] = count($unusedIndexes);
                } else {
                    $this->line('✓ All indexes are being used');
                    $this->metrics['unused_indexes'] = 0;
                }
            } catch (Exception $e) {
                $this->warn('Performance schema not available for index analysis');
            }
        }
    }

    /**
     * Monitor table statistics.
     */
    protected function monitorTables(): void
    {
        $this->info('Table Statistics & Growth Trending');
        $this->newLine();

        $driver = DB::connection()->getDriverName();

        if ($driver === 'mysql' || $driver === 'mariadb') {
            $tables = DB::select("
                SELECT
                    TABLE_NAME,
                    TABLE_ROWS,
                    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb,
                    ROUND(DATA_LENGTH / 1024 / 1024, 2) AS data_mb,
                    ROUND(INDEX_LENGTH / 1024 / 1024, 2) AS index_mb,
                    ENGINE,
                    TABLE_COLLATION
                FROM information_schema.TABLES
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_TYPE = 'BASE TABLE'
                ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
                LIMIT 20
            ");

            $tableData = [];
            foreach ($tables as $table) {
                $tableData[] = [
                    $table->TABLE_NAME,
                    number_format($table->TABLE_ROWS ?? 0),
                    $table->size_mb.' MB',
                    $table->data_mb.' MB',
                    $table->index_mb.' MB',
                    $table->ENGINE,
                ];

                $this->metrics['tables'][$table->TABLE_NAME] = [
                    'rows' => $table->TABLE_ROWS,
                    'size_mb' => $table->size_mb,
                    'engine' => $table->ENGINE,
                ];
            }

            $this->table(
                ['Table', 'Rows', 'Total Size', 'Data', 'Indexes', 'Engine'],
                $tableData
            );

            // Fragmentation analysis
            $this->newLine();
            $this->info('Table Fragmentation');

            $fragmented = DB::select("
                SELECT
                    TABLE_NAME,
                    ROUND(DATA_FREE / 1024 / 1024, 2) AS fragmented_mb
                FROM information_schema.TABLES
                WHERE TABLE_SCHEMA = DATABASE()
                  AND DATA_FREE > 0
                ORDER BY DATA_FREE DESC
                LIMIT 10
            ");

            if (! empty($fragmented)) {
                foreach ($fragmented as $frag) {
                    $this->line("  {$frag->TABLE_NAME}: {$frag->fragmented_mb} MB fragmented");
                    if ($frag->fragmented_mb > 100) {
                        $this->warn("    ⚠ Consider running: OPTIMIZE TABLE {$frag->TABLE_NAME};");
                    }
                }
            } else {
                $this->line('✓ No significant fragmentation detected');
            }
        } elseif ($driver === 'sqlite') {
            $tables = DB::select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");

            $tableData = [];
            foreach ($tables as $table) {
                $count = DB::table($table->name)->count();
                $tableData[] = [$table->name, number_format($count)];
            }

            $this->table(['Table', 'Rows'], $tableData);
        }
    }

    /**
     * Monitor database locks.
     */
    protected function monitorLocks(): void
    {
        $this->info('Lock Contention Monitor');
        $this->newLine();

        $driver = DB::connection()->getDriverName();

        if ($driver === 'mysql' || $driver === 'mariadb') {
            // Show locked tables
            $locks = DB::select('SHOW OPEN TABLES WHERE In_use > 0');

            if (! empty($locks)) {
                $this->warn('Locked tables detected:');
                $lockData = [];
                foreach ($locks as $lock) {
                    $lockData[] = [
                        $lock->Database,
                        $lock->Table,
                        $lock->In_use,
                    ];
                }
                $this->table(['Database', 'Table', 'Locks'], $lockData);
                $this->metrics['locked_tables'] = count($locks);
            } else {
                $this->line('✓ No table locks detected');
                $this->metrics['locked_tables'] = 0;
            }

            $this->newLine();

            // InnoDB lock waits
            try {
                $lockWaits = DB::select('SHOW ENGINE INNODB STATUS');
                // Parse lock information from status output
                $this->line('InnoDB Status: '.substr($lockWaits[0]->Status, 0, 200).'...');
            } catch (Exception $e) {
                $this->warn('Could not retrieve InnoDB lock status');
            }
        }
    }

    /**
     * Monitor backup status.
     */
    protected function monitorBackups(): void
    {
        $this->info('Backup Status Monitor');
        $this->newLine();

        $backupDir = storage_path('app/backups');

        if (! is_dir($backupDir)) {
            $this->warn('Backup directory does not exist');

            return;
        }

        // Get all backup files
        $backups = glob($backupDir.'/*.{sql,sql.gz,sql.bz2,sql.xz,db,db.gz}', GLOB_BRACE);

        if (empty($backups)) {
            $this->warn('No backups found');

            return;
        }

        // Sort by modification time (newest first)
        usort($backups, fn ($a, $b) => filemtime($b) <=> filemtime($a));

        // Display recent backups
        $backupData = [];
        foreach (array_slice($backups, 0, 10) as $backup) {
            $filename = basename($backup);
            $size = filesize($backup);
            $age = time() - filemtime($backup);

            $backupData[] = [
                $filename,
                $this->formatBytes($size),
                $this->formatDuration($age).' ago',
                date('Y-m-d H:i:s', filemtime($backup)),
            ];
        }

        $this->table(['File', 'Size', 'Age', 'Created'], $backupData);

        // Backup summary
        $this->newLine();
        $totalSize = array_sum(array_map('filesize', $backups));
        $this->line('Total backups: '.count($backups));
        $this->line('Total size: '.$this->formatBytes($totalSize));
        $this->line('Latest backup: '.$this->formatDuration(time() - filemtime($backups[0])).' ago');

        // Check backup frequency
        $lastBackupAge = time() - filemtime($backups[0]);
        if ($lastBackupAge > 86400) { // > 24 hours
            $this->warn('⚠ Last backup is older than 24 hours!');
        } else {
            $this->line('✓ Backup is current');
        }

        $this->metrics['backups'] = [
            'count' => count($backups),
            'total_size_bytes' => $totalSize,
            'last_backup_age_seconds' => $lastBackupAge,
        ];
    }

    /**
     * Format bytes to human readable.
     */
    protected function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];

        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision).' '.$units[$i];
    }

    /**
     * Format duration to human readable.
     */
    protected function formatDuration(int $seconds): string
    {
        if ($seconds < 60) {
            return $seconds.'s';
        }

        if ($seconds < 3600) {
            return floor($seconds / 60).'m';
        }

        if ($seconds < 86400) {
            return floor($seconds / 3600).'h';
        }

        return floor($seconds / 86400).'d';
    }

    /**
     * Format value for display.
     */
    protected function formatValue($value): string
    {
        if (is_numeric($value) && $value > 1000000) {
            return number_format($value);
        }

        return $value;
    }
}
