#!/bin/bash
################################################################################
# Point-in-Time Recovery (PITR) Script
# Restores database to a specific point in time using backups and binary logs
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-chom}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
BINLOG_DIR="${BINLOG_DIR:-/var/log/mysql}"
RECOVERY_TIME="${RECOVERY_TIME:-}"  # Format: YYYY-MM-DD HH:MM:SS
BACKUP_FILE="${BACKUP_FILE:-}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Point-in-Time Recovery (PITR)                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Display warning
echo -e "${RED}⚠⚠⚠  WARNING  ⚠⚠⚠${NC}"
echo -e "${RED}This script will restore the database to a previous point in time.${NC}"
echo -e "${RED}ALL CURRENT DATA will be replaced with the restored data.${NC}"
echo -e "${RED}This operation CANNOT be undone.${NC}"
echo
echo -e "${YELLOW}Prerequisites:${NC}"
echo "1. Binary logging must be enabled (log_bin=ON)"
echo "2. A full backup exists before the recovery time"
echo "3. Binary logs exist from backup time to recovery time"
echo
echo -e "${YELLOW}Press CTRL+C to abort, or Enter to continue...${NC}"
read

# Prompt for recovery time if not set
if [ -z "$RECOVERY_TIME" ]; then
    echo -e "${YELLOW}Enter recovery time (YYYY-MM-DD HH:MM:SS):${NC}"
    read RECOVERY_TIME
fi

# Prompt for password if not set
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}Enter MySQL root password:${NC}"
    read -s DB_PASSWORD
    echo
fi

# Step 1: Find appropriate backup
echo -e "${BLUE}[1/8]${NC} Finding appropriate backup..."

if [ -z "$BACKUP_FILE" ]; then
    # Convert recovery time to timestamp
    RECOVERY_TIMESTAMP=$(date -d "$RECOVERY_TIME" +%s)

    # Find the most recent backup before recovery time
    BACKUP_FILE=$(find "${BACKUP_DIR}" -name "*.sql.gz*" -type f | while read file; do
        FILE_TIMESTAMP=$(stat -c %Y "$file")
        if [ "$FILE_TIMESTAMP" -lt "$RECOVERY_TIMESTAMP" ]; then
            echo "$FILE_TIMESTAMP:$file"
        fi
    done | sort -rn | head -1 | cut -d: -f2)

    if [ -z "$BACKUP_FILE" ]; then
        echo -e "${RED}✗ No backup found before ${RECOVERY_TIME}${NC}"
        exit 1
    fi
fi

BACKUP_TIME=$(stat -c %y "$BACKUP_FILE")
echo -e "${GREEN}✓ Using backup: ${BACKUP_FILE}${NC}"
echo -e "${GREEN}  Backup time: ${BACKUP_TIME}${NC}"
echo

# Step 2: Create recovery workspace
echo -e "${BLUE}[2/8]${NC} Preparing recovery workspace..."
RECOVERY_DIR="/tmp/mysql_recovery_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RECOVERY_DIR"
echo -e "${GREEN}✓ Recovery workspace: ${RECOVERY_DIR}${NC}"
echo

# Step 3: Extract and decrypt backup
echo -e "${BLUE}[3/8]${NC} Extracting backup..."

EXTRACTED_FILE="${RECOVERY_DIR}/backup.sql"

# Decrypt if encrypted
if [[ "${BACKUP_FILE}" == *.enc ]]; then
    if [ -z "$ENCRYPTION_KEY" ]; then
        echo -e "${YELLOW}Enter encryption key:${NC}"
        read -s ENCRYPTION_KEY
        echo
    fi

    echo "Decrypting backup..."
    openssl enc -aes-256-cbc -d -pbkdf2 \
        -in "${BACKUP_FILE}" \
        -out "${BACKUP_FILE%.enc}" \
        -k "$ENCRYPTION_KEY"

    BACKUP_FILE="${BACKUP_FILE%.enc}"
fi

# Decompress
if [[ "${BACKUP_FILE}" == *.gz ]]; then
    echo "Decompressing backup..."
    gunzip -c "${BACKUP_FILE}" > "${EXTRACTED_FILE}"
else
    cp "${BACKUP_FILE}" "${EXTRACTED_FILE}"
fi

echo -e "${GREEN}✓ Backup extracted to: ${EXTRACTED_FILE}${NC}"
echo

# Step 4: Stop application (important!)
echo -e "${BLUE}[4/8]${NC} Stopping application..."
echo -e "${YELLOW}Ensure your application is stopped before proceeding!${NC}"
echo -e "${YELLOW}Press Enter when application is stopped...${NC}"
read

# Step 5: Restore full backup
echo -e "${BLUE}[5/8]${NC} Restoring full backup..."

# Create new database or drop existing
mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} <<EOF
DROP DATABASE IF EXISTS ${DB_NAME}_backup;
CREATE DATABASE ${DB_NAME}_backup;
EOF

# Rename current database
mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} <<EOF
RENAME TABLE ${DB_NAME}.* TO ${DB_NAME}_backup.*;
EOF

# Restore backup
echo "Restoring database from backup..."
mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} < "${EXTRACTED_FILE}"

echo -e "${GREEN}✓ Full backup restored${NC}"
echo

# Step 6: Extract binary log position from backup
echo -e "${BLUE}[6/8]${NC} Identifying binary log position..."

# Find CHANGE MASTER statement in backup
BINLOG_FILE=$(grep -m1 "^-- CHANGE MASTER TO" "${EXTRACTED_FILE}" | sed -n "s/.*MASTER_LOG_FILE='\([^']*\)'.*/\1/p" || echo "")
BINLOG_POS=$(grep -m1 "^-- CHANGE MASTER TO" "${EXTRACTED_FILE}" | sed -n "s/.*MASTER_LOG_POS=\([0-9]*\).*/\1/p" || echo "")

if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POS" ]; then
    echo -e "${YELLOW}⚠ Could not find binary log position in backup${NC}"
    echo -e "${YELLOW}  You will need to specify binary log file and position manually${NC}"

    echo -e "${YELLOW}Enter binary log file (e.g., mysql-bin.000001):${NC}"
    read BINLOG_FILE

    echo -e "${YELLOW}Enter binary log position:${NC}"
    read BINLOG_POS
fi

echo -e "${GREEN}✓ Starting position: ${BINLOG_FILE} at ${BINLOG_POS}${NC}"
echo

# Step 7: Apply binary logs
echo -e "${BLUE}[7/8]${NC} Applying binary logs to recovery point..."

# Convert recovery time to proper format
STOP_TIME=$(date -d "$RECOVERY_TIME" '+%Y-%m-%d %H:%M:%S')

# Find all binary logs from backup time to recovery time
BINLOG_FILES=$(ls -1 ${BINLOG_DIR}/mysql-bin.* 2>/dev/null | grep -v ".index" | sort)

echo "Applying binary logs from ${BINLOG_FILE}:${BINLOG_POS} to ${STOP_TIME}"
echo

# Extract and apply relevant binary log events
TEMP_SQL="${RECOVERY_DIR}/binlog_events.sql"

for log_file in $BINLOG_FILES; do
    # Check if this log file is after our starting point
    log_basename=$(basename "$log_file")

    if [[ "$log_basename" > "$BINLOG_FILE" ]] || [[ "$log_basename" == "$BINLOG_FILE" ]]; then
        echo "Processing $log_file..."

        if [[ "$log_basename" == "$BINLOG_FILE" ]]; then
            # Start from specific position
            mysqlbinlog \
                --start-position="$BINLOG_POS" \
                --stop-datetime="$STOP_TIME" \
                --database="$DB_NAME" \
                "$log_file" >> "$TEMP_SQL"
        else
            # Process entire file
            mysqlbinlog \
                --stop-datetime="$STOP_TIME" \
                --database="$DB_NAME" \
                "$log_file" >> "$TEMP_SQL"
        fi
    fi
done

# Apply the extracted events
if [ -s "$TEMP_SQL" ]; then
    echo "Applying binary log events..."
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} < "$TEMP_SQL"
    echo -e "${GREEN}✓ Binary logs applied successfully${NC}"
else
    echo -e "${YELLOW}⚠ No binary log events found for the specified time range${NC}"
fi
echo

# Step 8: Verify recovery
echo -e "${BLUE}[8/8]${NC} Verifying recovery..."

# Compare table counts
CURRENT_TABLES=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")
BACKUP_TABLES=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}_backup'")

echo "Recovered tables: ${CURRENT_TABLES}"
echo "Original tables: ${BACKUP_TABLES}"

if [ "$CURRENT_TABLES" -eq "$BACKUP_TABLES" ]; then
    echo -e "${GREEN}✓ Table count matches${NC}"
else
    echo -e "${YELLOW}⚠ Table count mismatch${NC}"
fi
echo

# Generate recovery report
REPORT_FILE="${RECOVERY_DIR}/recovery_report.txt"
cat > "$REPORT_FILE" <<EOF
================================================================================
POINT-IN-TIME RECOVERY REPORT
================================================================================
Recovery Time: ${RECOVERY_TIME}
Backup Used: ${BACKUP_FILE}
Backup Time: ${BACKUP_TIME}
Binary Log Start: ${BINLOG_FILE}:${BINLOG_POS}
Binary Log Stop: ${STOP_TIME}

DATABASE STATUS
================================================================================
Database: ${DB_NAME}
Tables Recovered: ${CURRENT_TABLES}
Original Tables: ${BACKUP_TABLES}

BACKUP DATABASE
================================================================================
The original database has been renamed to: ${DB_NAME}_backup
You can drop it with: DROP DATABASE ${DB_NAME}_backup;

NEXT STEPS
================================================================================
1. Verify data integrity:
   - Check critical tables
   - Verify record counts
   - Test application functionality

2. If recovery is successful:
   - Start application
   - Drop backup database: DROP DATABASE ${DB_NAME}_backup;
   - Clean up recovery directory: rm -rf ${RECOVERY_DIR}

3. If recovery failed:
   - Restore original database:
     RENAME TABLE ${DB_NAME}_backup.* TO ${DB_NAME}.*;
   - Review logs: ${RECOVERY_DIR}

RECOVERY WORKSPACE
================================================================================
Directory: ${RECOVERY_DIR}
Extracted Backup: ${EXTRACTED_FILE}
Binary Log Events: ${TEMP_SQL}

================================================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================
EOF

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Point-in-Time Recovery Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo
echo "Recovery Time: ${RECOVERY_TIME}"
echo "Backup Used: ${BACKUP_FILE}"
echo "Tables Recovered: ${CURRENT_TABLES}"
echo
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "1. The original database has been renamed to: ${DB_NAME}_backup"
echo "2. Verify the recovered data before dropping the backup"
echo "3. Recovery report: ${REPORT_FILE}"
echo
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${YELLOW}View recovery report? (y/n)${NC}"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cat "$REPORT_FILE"
fi

exit 0
