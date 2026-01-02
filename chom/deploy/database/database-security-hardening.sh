#!/bin/bash
################################################################################
# Database Security Hardening Script
# Implements production security best practices for MariaDB
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
DB_APP_USER="${DB_APP_USER:-chom}"
DB_APP_PASSWORD="${DB_APP_PASSWORD:-}"
DB_APP_DATABASE="${DB_APP_DATABASE:-chom}"
DB_BACKUP_USER="${DB_BACKUP_USER:-backup_user}"
DB_BACKUP_PASSWORD="${DB_BACKUP_PASSWORD:-}"
DB_MONITOR_USER="${DB_MONITOR_USER:-monitor_user}"
DB_MONITOR_PASSWORD="${DB_MONITOR_PASSWORD:-}"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       MariaDB Security Hardening                             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Generate strong random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Prompt for passwords if not set
if [ -z "$DB_ROOT_PASSWORD" ]; then
    echo -e "${YELLOW}Enter MariaDB root password:${NC}"
    read -s DB_ROOT_PASSWORD
    echo
fi

if [ -z "$DB_APP_PASSWORD" ]; then
    echo -e "${YELLOW}Generating strong password for application user...${NC}"
    DB_APP_PASSWORD=$(generate_password)
    echo -e "${GREEN}Generated password: ${DB_APP_PASSWORD}${NC}"
    echo -e "${YELLOW}Save this password to .env file!${NC}"
    echo
fi

if [ -z "$DB_BACKUP_PASSWORD" ]; then
    DB_BACKUP_PASSWORD=$(generate_password)
fi

if [ -z "$DB_MONITOR_PASSWORD" ]; then
    DB_MONITOR_PASSWORD=$(generate_password)
fi

# MySQL command alias
MYSQL_CMD="mysql -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD}"

echo -e "${BLUE}[1/10]${NC} Testing database connection..."
if ! $MYSQL_CMD -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cannot connect to database. Check credentials.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Database connection successful${NC}"
echo

echo -e "${BLUE}[2/10]${NC} Removing anonymous users..."
$MYSQL_CMD <<EOF
DELETE FROM mysql.user WHERE User='';
FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}✓ Anonymous users removed${NC}"
echo

echo -e "${BLUE}[3/10]${NC} Removing test database..."
$MYSQL_CMD <<EOF
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}✓ Test database removed${NC}"
echo

echo -e "${BLUE}[4/10]${NC} Disabling remote root login..."
$MYSQL_CMD <<EOF
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}✓ Remote root login disabled${NC}"
echo

echo -e "${BLUE}[5/10]${NC} Creating application database and user..."
$MYSQL_CMD <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_APP_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Drop user if exists (for re-runs)
DROP USER IF EXISTS '${DB_APP_USER}'@'localhost';
DROP USER IF EXISTS '${DB_APP_USER}'@'%';

-- Create application user with SSL requirement
CREATE USER '${DB_APP_USER}'@'localhost' IDENTIFIED BY '${DB_APP_PASSWORD}' REQUIRE SSL;
CREATE USER '${DB_APP_USER}'@'%' IDENTIFIED BY '${DB_APP_PASSWORD}' REQUIRE SSL;

-- Grant privileges with least privilege principle
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER,
      CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW,
      CREATE ROUTINE, ALTER ROUTINE, TRIGGER
ON \`${DB_APP_DATABASE}\`.*
TO '${DB_APP_USER}'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER,
      CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW,
      CREATE ROUTINE, ALTER ROUTINE, TRIGGER
ON \`${DB_APP_DATABASE}\`.*
TO '${DB_APP_USER}'@'%';

-- Enable password expiration policy (180 days)
ALTER USER '${DB_APP_USER}'@'localhost' PASSWORD EXPIRE INTERVAL 180 DAY;
ALTER USER '${DB_APP_USER}'@'%' PASSWORD EXPIRE INTERVAL 180 DAY;

-- Set max queries per hour (optional rate limiting)
-- ALTER USER '${DB_APP_USER}'@'%' WITH MAX_QUERIES_PER_HOUR 10000;

FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}✓ Application database and user created${NC}"
echo -e "${YELLOW}  Database: ${DB_APP_DATABASE}${NC}"
echo -e "${YELLOW}  User: ${DB_APP_USER}${NC}"
echo -e "${YELLOW}  Password: ${DB_APP_PASSWORD}${NC}"
echo

echo -e "${BLUE}[6/10]${NC} Creating backup user..."
$MYSQL_CMD <<EOF
DROP USER IF EXISTS '${DB_BACKUP_USER}'@'localhost';

CREATE USER '${DB_BACKUP_USER}'@'localhost'
IDENTIFIED BY '${DB_BACKUP_PASSWORD}';

-- Backup user needs these privileges
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER, RELOAD
ON *.*
TO '${DB_BACKUP_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}✓ Backup user created${NC}"
echo -e "${YELLOW}  User: ${DB_BACKUP_USER}${NC}"
echo -e "${YELLOW}  Password: ${DB_BACKUP_PASSWORD}${NC}"
echo

echo -e "${BLUE}[7/10]${NC} Creating monitoring user..."
$MYSQL_CMD <<EOF
DROP USER IF EXISTS '${DB_MONITOR_USER}'@'localhost';
DROP USER IF EXISTS '${DB_MONITOR_USER}'@'%';

CREATE USER '${DB_MONITOR_USER}'@'localhost'
IDENTIFIED BY '${DB_MONITOR_PASSWORD}';

CREATE USER '${DB_MONITOR_USER}'@'%'
IDENTIFIED BY '${DB_MONITOR_PASSWORD}';

-- Monitoring user needs only read access to performance schema
GRANT PROCESS, REPLICATION CLIENT, SELECT
ON *.*
TO '${DB_MONITOR_USER}'@'localhost';

GRANT PROCESS, REPLICATION CLIENT, SELECT
ON *.*
TO '${DB_MONITOR_USER}'@'%';

FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}✓ Monitoring user created${NC}"
echo -e "${YELLOW}  User: ${DB_MONITOR_USER}${NC}"
echo -e "${YELLOW}  Password: ${DB_MONITOR_PASSWORD}${NC}"
echo

echo -e "${BLUE}[8/10]${NC} Setting password policies..."
$MYSQL_CMD <<EOF
-- Set password validation policies
SET PERSIST simple_password_check_other_characters = 1;
SET PERSIST simple_password_check_minimal_length = 12;

-- Set default password expiration
SET PERSIST default_password_lifetime = 180;
EOF
echo -e "${GREEN}✓ Password policies configured${NC}"
echo

echo -e "${BLUE}[9/10]${NC} Enabling audit logging..."
# Check if audit plugin is available
if $MYSQL_CMD -e "SHOW PLUGINS" | grep -q "SERVER_AUDIT"; then
    $MYSQL_CMD <<EOF
SET PERSIST server_audit_logging = ON;
SET PERSIST server_audit_events = 'CONNECT,QUERY_DDL,QUERY_DML_INSERT,QUERY_DML_UPDATE,QUERY_DML_DELETE';
SET PERSIST server_audit_file_path = '/var/log/mysql/audit.log';
SET PERSIST server_audit_file_rotate_size = 1000000;
SET PERSIST server_audit_file_rotations = 9;
EOF
    echo -e "${GREEN}✓ Audit logging enabled${NC}"
else
    echo -e "${YELLOW}⚠ Server audit plugin not available. Install with:${NC}"
    echo -e "${YELLOW}  apt install mariadb-plugin-server-audit${NC}"
fi
echo

echo -e "${BLUE}[10/10]${NC} Generating credentials file..."
CREDS_FILE="/root/.database-credentials"
cat > "$CREDS_FILE" <<EOF
# ============================================================================
# CHOM Database Credentials
# Generated: $(date)
# ============================================================================

# Root credentials
DB_ROOT_USER=${DB_ROOT_USER}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}

# Application credentials
DB_APP_USER=${DB_APP_USER}
DB_APP_PASSWORD=${DB_APP_PASSWORD}
DB_APP_DATABASE=${DB_APP_DATABASE}

# Backup user credentials
DB_BACKUP_USER=${DB_BACKUP_USER}
DB_BACKUP_PASSWORD=${DB_BACKUP_PASSWORD}

# Monitoring user credentials
DB_MONITOR_USER=${DB_MONITOR_USER}
DB_MONITOR_PASSWORD=${DB_MONITOR_PASSWORD}

# Connection string for Laravel .env
DB_CONNECTION=mysql
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_APP_DATABASE}
DB_USERNAME=${DB_APP_USER}
DB_PASSWORD=${DB_APP_PASSWORD}

# SSL Configuration (if enabled)
MYSQL_ATTR_SSL_CA=/etc/mysql/ssl/ca-cert.pem
MYSQL_ATTR_SSL_VERIFY_SERVER_CERT=false
EOF

chmod 600 "$CREDS_FILE"
echo -e "${GREEN}✓ Credentials saved to: ${CREDS_FILE}${NC}"
echo

# Display user summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}User Summary:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
$MYSQL_CMD <<EOF
SELECT
    User,
    Host,
    ssl_type as 'SSL',
    password_expired as 'Expired',
    password_lifetime as 'Lifetime (days)'
FROM mysql.user
WHERE User != ''
ORDER BY User, Host;
EOF
echo

# Display database summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Database Summary:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
$MYSQL_CMD <<EOF
SHOW DATABASES;
EOF
echo

# Security checklist
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Security Checklist:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓${NC} Anonymous users removed"
echo -e "${GREEN}✓${NC} Test database removed"
echo -e "${GREEN}✓${NC} Remote root login disabled"
echo -e "${GREEN}✓${NC} Application user with SSL required"
echo -e "${GREEN}✓${NC} Backup user created"
echo -e "${GREEN}✓${NC} Monitoring user created"
echo -e "${GREEN}✓${NC} Password policies enforced"
echo -e "${GREEN}✓${NC} Password expiration: 180 days"
echo

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo "1. Update Laravel .env with credentials from: ${CREDS_FILE}"
echo
echo "2. Enable SSL/TLS:"
echo "   ./deploy/database/setup-mariadb-ssl.sh"
echo
echo "3. Configure firewall:"
echo "   ufw allow from <app-server-ip> to any port 3306"
echo "   ufw enable"
echo
echo "4. Test connection:"
echo "   mysql -h ${DB_HOST} -u ${DB_APP_USER} -p${DB_APP_PASSWORD} ${DB_APP_DATABASE} --ssl"
echo
echo "5. Run privilege audit:"
echo "   ./deploy/database/audit-database-users.sh"
echo
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Security hardening completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
