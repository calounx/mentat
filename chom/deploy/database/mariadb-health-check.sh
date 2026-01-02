#!/bin/bash
################################################################################
# MariaDB Health Check and Performance Monitoring Script
# Provides comprehensive database health metrics and performance analysis
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
REPORT_DIR="${REPORT_DIR:-/var/log/mysql/health}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/health_check_${TIMESTAMP}.txt"

# Thresholds
CONN_THRESHOLD=80  # % of max_connections
BUFFER_POOL_THRESHOLD=90  # % buffer pool usage
SLOW_QUERY_THRESHOLD=100  # Number of slow queries
REPLICATION_LAG_THRESHOLD=60  # seconds

# MySQL command
MYSQL_CMD="mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -N -s"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       MariaDB Health Check & Performance Monitor             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Create report directory
mkdir -p "$REPORT_DIR"

# Prompt for password if not set
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}Enter MySQL password:${NC}"
    read -s DB_PASSWORD
    echo
fi

# Test connection
echo -e "${CYAN}Testing database connection...${NC}"
if ! mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cannot connect to database${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected${NC}"
echo

# Start report
{
    echo "================================================================================"
    echo "MARIADB HEALTH CHECK REPORT"
    echo "================================================================================"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Server: ${DB_HOST}:${DB_PORT}"
    echo "================================================================================"
    echo
} > "$REPORT_FILE"

# Function to run check
run_check() {
    local title=$1
    local query=$2

    echo -e "${CYAN}${title}${NC}"
    echo "$title" >> "$REPORT_FILE"
    echo "--------------------------------------------------------------------------------" >> "$REPORT_FILE"

    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -t -e "$query" >> "$REPORT_FILE" 2>&1 || echo "Error executing query" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
}

# 1. Server Status
echo -e "${BLUE}[1/15]${NC} Server Status..."
run_check "1. SERVER STATUS" "
SELECT
    VERSION() AS 'MariaDB Version',
    @@hostname AS 'Hostname',
    @@port AS 'Port',
    @@socket AS 'Socket',
    @@datadir AS 'Data Directory',
    NOW() AS 'Current Time',
    @@uptime AS 'Uptime (seconds)',
    CONCAT(ROUND(@@uptime / 86400, 0), ' days, ',
           ROUND((@@uptime % 86400) / 3600, 0), ' hours') AS 'Uptime (readable)'
"

# 2. Connection Status
echo -e "${BLUE}[2/15]${NC} Connection Status..."
CURRENT_CONNECTIONS=$($MYSQL_CMD -e "SHOW STATUS LIKE 'Threads_connected'" | awk '{print $2}')
MAX_CONNECTIONS=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'max_connections'" | awk '{print $2}')
CONN_PCT=$((CURRENT_CONNECTIONS * 100 / MAX_CONNECTIONS))

{
    echo "2. CONNECTION STATUS"
    echo "--------------------------------------------------------------------------------"
    echo "Current Connections: ${CURRENT_CONNECTIONS}"
    echo "Max Connections: ${MAX_CONNECTIONS}"
    echo "Usage: ${CONN_PCT}%"

    if [ "$CONN_PCT" -ge "$CONN_THRESHOLD" ]; then
        echo "⚠ WARNING: Connection usage above ${CONN_THRESHOLD}%"
        echo -e "${YELLOW}⚠ WARNING: Connection usage at ${CONN_PCT}%${NC}"
    else
        echo "✓ Connection usage healthy"
        echo -e "${GREEN}✓ Connection usage: ${CONN_PCT}%${NC}"
    fi
    echo
} >> "$REPORT_FILE"

run_check "Active Connections by User" "
SELECT
    USER,
    HOST,
    DB,
    COMMAND,
    TIME,
    STATE,
    COUNT(*) AS 'Connection Count'
FROM information_schema.PROCESSLIST
GROUP BY USER, HOST, DB, COMMAND, STATE
ORDER BY COUNT(*) DESC
LIMIT 20
"

# 3. InnoDB Buffer Pool
echo -e "${BLUE}[3/15]${NC} InnoDB Buffer Pool Status..."
run_check "3. INNODB BUFFER POOL" "
SELECT
    CONCAT(ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2), ' GB') AS 'Buffer Pool Size',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total') AS 'Total Pages',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data') AS 'Data Pages',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_free') AS 'Free Pages',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_dirty') AS 'Dirty Pages',
    CONCAT(ROUND((SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data') * 100.0 /
           (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total'), 2), '%') AS 'Usage %'
"

# 4. Query Performance
echo -e "${BLUE}[4/15]${NC} Query Performance..."
run_check "4. QUERY STATISTICS" "
SELECT
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Questions') AS 'Total Queries',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Slow_queries') AS 'Slow Queries',
    CONCAT(ROUND((SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Slow_queries') * 100.0 /
           (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Questions'), 4), '%') AS 'Slow Query %',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Com_select') AS 'SELECTs',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Com_insert') AS 'INSERTs',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Com_update') AS 'UPDATEs',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Com_delete') AS 'DELETEs'
"

SLOW_QUERIES=$($MYSQL_CMD -e "SHOW STATUS LIKE 'Slow_queries'" | awk '{print $2}')
if [ "$SLOW_QUERIES" -gt "$SLOW_QUERY_THRESHOLD" ]; then
    echo -e "${YELLOW}⚠ Found ${SLOW_QUERIES} slow queries${NC}"
fi

# 5. Table Statistics
echo -e "${BLUE}[5/15]${NC} Table Statistics..."
run_check "5. LARGEST TABLES" "
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    ENGINE,
    TABLE_ROWS,
    CONCAT(ROUND(DATA_LENGTH / 1024 / 1024, 2), ' MB') AS 'Data Size',
    CONCAT(ROUND(INDEX_LENGTH / 1024 / 1024, 2), ' MB') AS 'Index Size',
    CONCAT(ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2), ' MB') AS 'Total Size',
    CONCAT(ROUND(INDEX_LENGTH * 100.0 / (DATA_LENGTH + INDEX_LENGTH), 2), '%') AS 'Index Ratio'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 20
"

# 6. Database Sizes
echo -e "${BLUE}[6/15]${NC} Database Sizes..."
run_check "6. DATABASE SIZES" "
SELECT
    TABLE_SCHEMA AS 'Database',
    COUNT(*) AS 'Tables',
    CONCAT(ROUND(SUM(TABLE_ROWS) / 1000000, 2), 'M') AS 'Total Rows',
    CONCAT(ROUND(SUM(DATA_LENGTH) / 1024 / 1024, 2), ' MB') AS 'Data Size',
    CONCAT(ROUND(SUM(INDEX_LENGTH) / 1024 / 1024, 2), ' MB') AS 'Index Size',
    CONCAT(ROUND(SUM(DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2), ' MB') AS 'Total Size'
FROM information_schema.TABLES
GROUP BY TABLE_SCHEMA
ORDER BY SUM(DATA_LENGTH + INDEX_LENGTH) DESC
"

# 7. InnoDB Status
echo -e "${BLUE}[7/15]${NC} InnoDB I/O Status..."
run_check "7. INNODB I/O STATISTICS" "
SELECT
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_data_reads') AS 'Data Reads',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_data_writes') AS 'Data Writes',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_data_read') AS 'Data Read (bytes)',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_data_written') AS 'Data Written (bytes)',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_rows_read') AS 'Rows Read',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_rows_inserted') AS 'Rows Inserted',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_rows_updated') AS 'Rows Updated',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_rows_deleted') AS 'Rows Deleted'
"

# 8. Locks and Deadlocks
echo -e "${BLUE}[8/15]${NC} Lock Status..."
run_check "8. LOCK STATISTICS" "
SELECT
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_row_lock_current_waits') AS 'Current Lock Waits',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_row_lock_waits') AS 'Total Lock Waits',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_row_lock_time') AS 'Lock Time (ms)',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_deadlocks') AS 'Deadlocks',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Table_locks_waited') AS 'Table Lock Waits'
"

# 9. Binary Log Status
echo -e "${BLUE}[9/15]${NC} Binary Log Status..."
run_check "9. BINARY LOG STATUS" "
SELECT
    @@log_bin AS 'Binary Logging Enabled',
    @@binlog_format AS 'Binary Log Format',
    @@max_binlog_size AS 'Max Binlog Size',
    @@binlog_expire_logs_seconds AS 'Expire Logs (seconds)',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Binlog_cache_use') AS 'Binlog Cache Use',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Binlog_cache_disk_use') AS 'Binlog Cache Disk Use'
"

# 10. Replication Status (if applicable)
echo -e "${BLUE}[10/15]${NC} Replication Status..."
if mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -q "Slave_IO_State"; then
    {
        echo "10. REPLICATION STATUS"
        echo "--------------------------------------------------------------------------------"
        mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -e "SHOW SLAVE STATUS\G"
        echo
    } >> "$REPORT_FILE"

    SECONDS_BEHIND=$($MYSQL_CMD -e "SHOW SLAVE STATUS\G" | grep "Seconds_Behind_Master:" | awk '{print $2}')
    if [ "$SECONDS_BEHIND" != "NULL" ] && [ "$SECONDS_BEHIND" -gt "$REPLICATION_LAG_THRESHOLD" ]; then
        echo -e "${YELLOW}⚠ Replication lag: ${SECONDS_BEHIND} seconds${NC}"
    fi
else
    echo "10. REPLICATION STATUS: Not configured" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
fi

# 11. Temporary Tables
echo -e "${BLUE}[11/15]${NC} Temporary Table Usage..."
run_check "11. TEMPORARY TABLE STATISTICS" "
SELECT
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables') AS 'Temp Tables Created',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') AS 'Temp Tables on Disk',
    CONCAT(ROUND((SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') * 100.0 /
           (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables'), 2), '%') AS 'Disk Tmp Table %'
"

# 12. Thread Cache
echo -e "${BLUE}[12/15]${NC} Thread Cache Efficiency..."
run_check "12. THREAD CACHE STATISTICS" "
SELECT
    @@thread_cache_size AS 'Thread Cache Size',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_created') AS 'Threads Created',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_cached') AS 'Threads Cached',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') AS 'Threads Connected',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Connections') AS 'Total Connections',
    CONCAT(ROUND((SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_created') * 100.0 /
           (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Connections'), 2), '%') AS 'Thread Creation Rate'
"

# 13. Memory Usage
echo -e "${BLUE}[13/15]${NC} Memory Usage..."
run_check "13. MEMORY CONFIGURATION" "
SELECT
    CONCAT(ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2), ' GB') AS 'InnoDB Buffer Pool',
    CONCAT(ROUND(@@key_buffer_size / 1024 / 1024, 2), ' MB') AS 'Key Buffer',
    CONCAT(ROUND(@@tmp_table_size / 1024 / 1024, 2), ' MB') AS 'Tmp Table Size',
    CONCAT(ROUND(@@max_heap_table_size / 1024 / 1024, 2), ' MB') AS 'Max Heap Table',
    CONCAT(ROUND(@@sort_buffer_size / 1024 / 1024, 2), ' MB') AS 'Sort Buffer',
    CONCAT(ROUND(@@read_buffer_size / 1024 / 1024, 2), ' MB') AS 'Read Buffer',
    CONCAT(ROUND(@@join_buffer_size / 1024 / 1024, 2), ' MB') AS 'Join Buffer'
"

# 14. Slow Query Log
echo -e "${BLUE}[14/15]${NC} Slow Query Log Configuration..."
run_check "14. SLOW QUERY LOG" "
SELECT
    @@slow_query_log AS 'Slow Query Log Enabled',
    @@slow_query_log_file AS 'Log File',
    @@long_query_time AS 'Long Query Time (seconds)',
    @@log_queries_not_using_indexes AS 'Log Queries Without Indexes',
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Slow_queries') AS 'Total Slow Queries'
"

# 15. Index Usage
echo -e "${BLUE}[15/15]${NC} Index Efficiency..."
run_check "15. INDEX USAGE STATISTICS" "
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    INDEX_NAME,
    SEQ_IN_INDEX,
    COLUMN_NAME,
    CARDINALITY,
    INDEX_TYPE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
  AND CARDINALITY IS NOT NULL
ORDER BY TABLE_SCHEMA, TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX
LIMIT 50
"

# Summary and Recommendations
{
    echo "================================================================================"
    echo "HEALTH CHECK SUMMARY"
    echo "================================================================================"
    echo
    echo "Connection Usage: ${CONN_PCT}% (${CURRENT_CONNECTIONS}/${MAX_CONNECTIONS})"
    echo "Slow Queries: ${SLOW_QUERIES}"
    echo
    echo "RECOMMENDATIONS:"
    echo "--------------------------------------------------------------------------------"
} >> "$REPORT_FILE"

# Generate recommendations
if [ "$CONN_PCT" -ge "$CONN_THRESHOLD" ]; then
    echo "⚠ Consider increasing max_connections" >> "$REPORT_FILE"
fi

if [ "$SLOW_QUERIES" -gt "$SLOW_QUERY_THRESHOLD" ]; then
    echo "⚠ Review slow query log and optimize queries" >> "$REPORT_FILE"
    echo "  Command: mysqldumpslow -s t -t 10 /var/log/mysql/slow-query.log" >> "$REPORT_FILE"
fi

{
    echo
    echo "For detailed analysis, use:"
    echo "  - mysqltuner (apt install mysqltuner)"
    echo "  - pt-query-digest for slow query analysis"
    echo "  - Grafana dashboards for real-time monitoring"
    echo
    echo "================================================================================"
    echo "Report saved to: ${REPORT_FILE}"
    echo "================================================================================"
} >> "$REPORT_FILE"

echo
echo -e "${GREEN}✓ Health check complete${NC}"
echo -e "${GREEN}Report saved to: ${REPORT_FILE}${NC}"
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Key Metrics:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo "Connection Usage: ${CONN_PCT}% (${CURRENT_CONNECTIONS}/${MAX_CONNECTIONS})"
echo "Slow Queries: ${SLOW_QUERIES}"
echo
echo -e "${YELLOW}View full report? (y/n)${NC}"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    less "$REPORT_FILE"
fi
