#!/bin/bash
################################################################################
# Database User Privilege Audit Script
# Comprehensive audit of database users, privileges, and security settings
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
DB_ROOT_USER="${DB_ROOT_USER:-root}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
REPORT_DIR="${REPORT_DIR:-/var/log/mysql/audits}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/privilege_audit_${TIMESTAMP}.txt"

# MySQL command alias
MYSQL_CMD="mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Database User Privilege Audit                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Create report directory
mkdir -p "$REPORT_DIR"

# Prompt for password if not set
if [ -z "$DB_ROOT_PASSWORD" ]; then
    echo -e "${YELLOW}Enter MariaDB root password:${NC}"
    read -s DB_ROOT_PASSWORD
    echo
fi

# Test connection
echo -e "${BLUE}Testing database connection...${NC}"
if ! mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cannot connect to database${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected to database${NC}"
echo

# Start report
cat > "$REPORT_FILE" <<EOF
================================================================================
DATABASE USER PRIVILEGE AUDIT REPORT
================================================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Server: ${DB_HOST}:${DB_PORT}
================================================================================

EOF

echo -e "${BLUE}Running comprehensive audit...${NC}"
echo

# 1. List all users
echo -e "${BLUE}[1/12]${NC} Auditing user accounts..."
cat >> "$REPORT_FILE" <<EOF
1. USER ACCOUNTS
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    CASE
        WHEN authentication_string = '' THEN 'BLANK PASSWORD'
        ELSE 'PASSWORD SET'
    END AS 'Password Status',
    ssl_type AS 'SSL Requirement',
    password_expired AS 'Password Expired',
    password_lifetime AS 'Lifetime (days)',
    password_last_changed AS 'Last Changed',
    account_locked AS 'Locked',
    max_connections AS 'Max Connections',
    max_questions AS 'Max Queries/Hour'
FROM mysql.user
ORDER BY User, Host;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 2. Check for insecure users
echo -e "${BLUE}[2/12]${NC} Checking for security issues..."
cat >> "$REPORT_FILE" <<EOF
2. SECURITY ISSUES
================================================================================
EOF

# Anonymous users
ANON_COUNT=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.user WHERE User=''")
if [ "$ANON_COUNT" -gt 0 ]; then
    echo -e "${RED}✗ Found ${ANON_COUNT} anonymous users${NC}"
    echo "CRITICAL: Found ${ANON_COUNT} anonymous users" >> "$REPORT_FILE"
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t -e "SELECT User, Host FROM mysql.user WHERE User=''" >> "$REPORT_FILE"
else
    echo -e "${GREEN}✓ No anonymous users${NC}"
    echo "PASS: No anonymous users found" >> "$REPORT_FILE"
fi

# Users without password
NO_PASS_COUNT=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.user WHERE authentication_string='' AND User!=''")
if [ "$NO_PASS_COUNT" -gt 0 ]; then
    echo -e "${RED}✗ Found ${NO_PASS_COUNT} users without passwords${NC}"
    echo "CRITICAL: Found ${NO_PASS_COUNT} users without passwords" >> "$REPORT_FILE"
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t -e "SELECT User, Host FROM mysql.user WHERE authentication_string='' AND User!=''" >> "$REPORT_FILE"
else
    echo -e "${GREEN}✓ All users have passwords${NC}"
    echo "PASS: All users have passwords" >> "$REPORT_FILE"
fi

# Remote root access
REMOTE_ROOT=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')")
if [ "$REMOTE_ROOT" -gt 0 ]; then
    echo -e "${RED}✗ Root user accessible remotely${NC}"
    echo "CRITICAL: Root user accessible remotely" >> "$REPORT_FILE"
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t -e "SELECT User, Host FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')" >> "$REPORT_FILE"
else
    echo -e "${GREEN}✓ Root only accessible locally${NC}"
    echo "PASS: Root only accessible locally" >> "$REPORT_FILE"
fi

# Users without SSL requirement
NO_SSL_COUNT=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.user WHERE ssl_type='' AND Host!='localhost' AND User!=''")
if [ "$NO_SSL_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found ${NO_SSL_COUNT} remote users without SSL requirement${NC}"
    echo "WARNING: Found ${NO_SSL_COUNT} remote users without SSL requirement" >> "$REPORT_FILE"
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t -e "SELECT User, Host, ssl_type FROM mysql.user WHERE ssl_type='' AND Host!='localhost' AND User!=''" >> "$REPORT_FILE"
else
    echo -e "${GREEN}✓ All remote users require SSL${NC}"
    echo "PASS: All remote users require SSL" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

EOF

# 3. Global privileges
echo -e "${BLUE}[3/12]${NC} Checking global privileges..."
cat >> "$REPORT_FILE" <<EOF
3. USERS WITH GLOBAL PRIVILEGES
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    Super_priv,
    Grant_priv,
    Reload_priv,
    Shutdown_priv,
    Process_priv,
    File_priv,
    Repl_slave_priv,
    Repl_client_priv,
    Create_user_priv
FROM mysql.user
WHERE Super_priv='Y' OR Grant_priv='Y' OR Create_user_priv='Y'
ORDER BY User, Host;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 4. Database privileges
echo -e "${BLUE}[4/12]${NC} Checking database privileges..."
cat >> "$REPORT_FILE" <<EOF
4. DATABASE-LEVEL PRIVILEGES
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    Db,
    Select_priv,
    Insert_priv,
    Update_priv,
    Delete_priv,
    Create_priv,
    Drop_priv,
    Grant_priv,
    References_priv,
    Index_priv,
    Alter_priv,
    Create_tmp_table_priv,
    Lock_tables_priv,
    Create_view_priv,
    Show_view_priv,
    Create_routine_priv,
    Alter_routine_priv,
    Execute_priv,
    Event_priv,
    Trigger_priv
FROM mysql.db
ORDER BY Db, User, Host;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 5. Table privileges
echo -e "${BLUE}[5/12]${NC} Checking table privileges..."
cat >> "$REPORT_FILE" <<EOF
5. TABLE-LEVEL PRIVILEGES
================================================================================
EOF

TABLE_PRIV_COUNT=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.tables_priv")
if [ "$TABLE_PRIV_COUNT" -gt 0 ]; then
    mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    Db,
    Table_name,
    Table_priv,
    Column_priv
FROM mysql.tables_priv
ORDER BY Db, Table_name, User;
EOF
else
    echo "No table-level privileges defined" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

EOF

# 6. Password expiration status
echo -e "${BLUE}[6/12]${NC} Checking password expiration..."
cat >> "$REPORT_FILE" <<EOF
6. PASSWORD EXPIRATION STATUS
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    password_expired AS 'Expired',
    password_lifetime AS 'Lifetime (days)',
    password_last_changed AS 'Last Changed',
    CASE
        WHEN password_lifetime IS NULL THEN 'No expiration'
        WHEN password_expired = 'Y' THEN 'EXPIRED - IMMEDIATE ACTION REQUIRED'
        WHEN password_last_changed IS NULL THEN 'Never changed'
        WHEN DATEDIFF(NOW(), password_last_changed) > password_lifetime THEN 'WILL EXPIRE SOON'
        ELSE CONCAT('Expires in ', password_lifetime - DATEDIFF(NOW(), password_last_changed), ' days')
    END AS 'Status'
FROM mysql.user
WHERE User != ''
ORDER BY password_expired DESC, password_last_changed ASC;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 7. Connection limits
echo -e "${BLUE}[7/12]${NC} Checking connection limits..."
cat >> "$REPORT_FILE" <<EOF
7. CONNECTION AND QUERY LIMITS
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    max_connections AS 'Max Connections',
    max_questions AS 'Max Queries/Hour',
    max_updates AS 'Max Updates/Hour',
    max_user_connections AS 'Max User Connections'
FROM mysql.user
WHERE User != ''
ORDER BY User, Host;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 8. Plugin authentication
echo -e "${BLUE}[8/12]${NC} Checking authentication plugins..."
cat >> "$REPORT_FILE" <<EOF
8. AUTHENTICATION PLUGINS
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    User,
    Host,
    plugin AS 'Auth Plugin',
    CASE
        WHEN plugin = 'mysql_native_password' THEN 'Standard'
        WHEN plugin = 'unix_socket' THEN 'Unix socket auth'
        WHEN plugin = 'sha256_password' THEN 'SHA-256 (secure)'
        WHEN plugin = 'caching_sha2_password' THEN 'Cached SHA-2 (most secure)'
        ELSE plugin
    END AS 'Security Level'
FROM mysql.user
WHERE User != ''
ORDER BY plugin, User;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 9. Test database access
echo -e "${BLUE}[9/12]${NC} Checking test database access..."
cat >> "$REPORT_FILE" <<EOF
9. TEST DATABASE ACCESS
================================================================================
EOF

TEST_DB_EXISTS=$(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test'")
if [ "$TEST_DB_EXISTS" -gt 0 ]; then
    echo -e "${RED}✗ Test database still exists${NC}"
    echo "WARNING: Test database still exists" >> "$REPORT_FILE"
else
    echo -e "${GREEN}✓ Test database removed${NC}"
    echo "PASS: Test database does not exist" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF

EOF

# 10. SSL/TLS status
echo -e "${BLUE}[10/12]${NC} Checking SSL/TLS configuration..."
cat >> "$REPORT_FILE" <<EOF
10. SSL/TLS CONFIGURATION
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SHOW VARIABLES LIKE '%ssl%';
EOF

cat >> "$REPORT_FILE" <<EOF

TLS Versions:
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SHOW VARIABLES LIKE 'tls_version';
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 11. Current connections
echo -e "${BLUE}[11/12]${NC} Checking current connections..."
cat >> "$REPORT_FILE" <<EOF
11. CURRENT ACTIVE CONNECTIONS
================================================================================
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    USER,
    HOST,
    DB,
    COMMAND,
    TIME,
    STATE,
    LEFT(INFO, 50) AS 'Query Preview'
FROM information_schema.PROCESSLIST
ORDER BY TIME DESC;
EOF

cat >> "$REPORT_FILE" <<EOF

Connection Summary:
EOF

mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -t <<EOF >> "$REPORT_FILE"
SELECT
    USER,
    COUNT(*) AS 'Active Connections'
FROM information_schema.PROCESSLIST
GROUP BY USER
ORDER BY COUNT(*) DESC;
EOF

cat >> "$REPORT_FILE" <<EOF

EOF

# 12. Security recommendations
echo -e "${BLUE}[12/12]${NC} Generating security recommendations..."
cat >> "$REPORT_FILE" <<EOF
12. SECURITY RECOMMENDATIONS
================================================================================
EOF

# Count issues
ISSUES=0

if [ "$ANON_COUNT" -gt 0 ]; then
    echo "HIGH PRIORITY: Remove anonymous users" >> "$REPORT_FILE"
    echo "  Fix: DELETE FROM mysql.user WHERE User=''; FLUSH PRIVILEGES;" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    ((ISSUES++))
fi

if [ "$NO_PASS_COUNT" -gt 0 ]; then
    echo "CRITICAL: Set passwords for all users" >> "$REPORT_FILE"
    echo "  Fix: ALTER USER 'username'@'host' IDENTIFIED BY 'strong_password';" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    ((ISSUES++))
fi

if [ "$REMOTE_ROOT" -gt 0 ]; then
    echo "CRITICAL: Disable remote root access" >> "$REPORT_FILE"
    echo "  Fix: DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); FLUSH PRIVILEGES;" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    ((ISSUES++))
fi

if [ "$NO_SSL_COUNT" -gt 0 ]; then
    echo "HIGH PRIORITY: Require SSL for remote users" >> "$REPORT_FILE"
    echo "  Fix: ALTER USER 'username'@'%' REQUIRE SSL; FLUSH PRIVILEGES;" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    ((ISSUES++))
fi

if [ "$TEST_DB_EXISTS" -gt 0 ]; then
    echo "MEDIUM PRIORITY: Remove test database" >> "$REPORT_FILE"
    echo "  Fix: DROP DATABASE test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    ((ISSUES++))
fi

cat >> "$REPORT_FILE" <<EOF
RECOMMENDED SECURITY BEST PRACTICES:
- Enable password expiration (180 days recommended)
- Use SSL/TLS for all connections
- Implement least privilege principle
- Regular password rotation
- Monitor and audit user access
- Enable binary logging for point-in-time recovery
- Regular privilege audits (monthly recommended)
- Use strong password policies (12+ characters, complexity requirements)
- Limit connection attempts and queries per hour for application users
- Use separate users for backup, monitoring, and application access

EOF

# Summary
cat >> "$REPORT_FILE" <<EOF
================================================================================
AUDIT SUMMARY
================================================================================
Total Users: $(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.user WHERE User!=''")
Security Issues Found: ${ISSUES}
Report Location: ${REPORT_FILE}
Generated: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================
EOF

echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Audit Summary:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [ "$ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✓ No critical security issues found${NC}"
else
    echo -e "${RED}✗ Found ${ISSUES} security issues requiring attention${NC}"
fi

echo
echo "Total Users: $(mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} -N -s -e "SELECT COUNT(*) FROM mysql.user WHERE User!=''")"
echo
echo -e "${GREEN}Full audit report saved to: ${REPORT_FILE}${NC}"
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Display report
echo -e "${YELLOW}View report? (y/n)${NC}"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    less "$REPORT_FILE"
fi

exit 0
