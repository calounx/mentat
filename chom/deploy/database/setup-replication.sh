#!/bin/bash
################################################################################
# MariaDB Master-Slave Replication Setup Script
# Configures master-slave replication for high availability
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ROLE="${1:-}"  # master or slave
MASTER_HOST="${MASTER_HOST:-}"
MASTER_PORT="${MASTER_PORT:-3306}"
MASTER_USER="${MASTER_USER:-replication_user}"
MASTER_PASSWORD="${MASTER_PASSWORD:-}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
SERVER_ID="${SERVER_ID:-}"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       MariaDB Replication Setup                              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check usage
if [ -z "$ROLE" ]; then
    echo "Usage: $0 <master|slave>"
    echo
    echo "Master setup:"
    echo "  $0 master"
    echo
    echo "Slave setup:"
    echo "  MASTER_HOST=<ip> MASTER_USER=<user> MASTER_PASSWORD=<pass> $0 slave"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Prompt for root password if not set
if [ -z "$DB_ROOT_PASSWORD" ]; then
    echo -e "${YELLOW}Enter MariaDB root password:${NC}"
    read -s DB_ROOT_PASSWORD
    echo
fi

# Generate server ID if not set
if [ -z "$SERVER_ID" ]; then
    SERVER_ID=$((RANDOM % 1000 + 1))
    echo -e "${YELLOW}Generated server ID: ${SERVER_ID}${NC}"
fi

# ============================================================================
# MASTER CONFIGURATION
# ============================================================================
if [ "$ROLE" = "master" ]; then
    echo -e "${BLUE}[MASTER] Setting up replication master...${NC}"
    echo

    # Step 1: Configure server
    echo -e "${BLUE}[1/5]${NC} Configuring server..."

    cat > /etc/mysql/mariadb.conf.d/60-replication.cnf <<EOF
[mysqld]
# Replication Configuration - Master
server-id = ${SERVER_ID}
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
binlog_expire_logs_seconds = 604800
max_binlog_size = 100M
sync_binlog = 1

# GTID Mode (recommended)
gtid_strict_mode = ON

# Binlog optimization
binlog_row_image = MINIMAL
binlog_annotate_row_events = ON
EOF

    echo -e "${GREEN}✓ Configuration file created${NC}"
    echo

    # Step 2: Restart MySQL
    echo -e "${BLUE}[2/5]${NC} Restarting MariaDB..."
    systemctl restart mariadb
    sleep 3
    echo -e "${GREEN}✓ MariaDB restarted${NC}"
    echo

    # Step 3: Create replication user
    echo -e "${BLUE}[3/5]${NC} Creating replication user..."

    if [ -z "$MASTER_PASSWORD" ]; then
        MASTER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    fi

    mysql -u root -p${DB_ROOT_PASSWORD} <<EOF
-- Create replication user
DROP USER IF EXISTS '${MASTER_USER}'@'%';
CREATE USER '${MASTER_USER}'@'%' IDENTIFIED BY '${MASTER_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO '${MASTER_USER}'@'%';
FLUSH PRIVILEGES;
EOF

    echo -e "${GREEN}✓ Replication user created${NC}"
    echo -e "${YELLOW}  Username: ${MASTER_USER}${NC}"
    echo -e "${YELLOW}  Password: ${MASTER_PASSWORD}${NC}"
    echo

    # Step 4: Get master status
    echo -e "${BLUE}[4/5]${NC} Getting master status..."

    MASTER_STATUS=$(mysql -u root -p${DB_ROOT_PASSWORD} -e "SHOW MASTER STATUS\G")
    MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
    MASTER_LOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

    echo "$MASTER_STATUS"
    echo

    # Step 5: Save configuration
    echo -e "${BLUE}[5/5]${NC} Saving configuration..."

    cat > /root/.replication-master-config <<EOF
# Master Replication Configuration
# Generated: $(date)

MASTER_HOST=$(hostname -I | awk '{print $1}')
MASTER_PORT=${MASTER_PORT}
MASTER_USER=${MASTER_USER}
MASTER_PASSWORD=${MASTER_PASSWORD}
SERVER_ID=${SERVER_ID}
MASTER_LOG_FILE=${MASTER_LOG_FILE}
MASTER_LOG_POS=${MASTER_LOG_POS}

# Slave setup command:
MASTER_HOST=\$(hostname -I | awk '{print \$1}') \\
MASTER_USER=${MASTER_USER} \\
MASTER_PASSWORD=${MASTER_PASSWORD} \\
./setup-replication.sh slave
EOF

    chmod 600 /root/.replication-master-config

    echo -e "${GREEN}✓ Configuration saved to: /root/.replication-master-config${NC}"
    echo

    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Master configuration complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo "Master Status:"
    echo "  Server ID: ${SERVER_ID}"
    echo "  Log File: ${MASTER_LOG_FILE}"
    echo "  Position: ${MASTER_LOG_POS}"
    echo
    echo "Replication Credentials:"
    echo "  User: ${MASTER_USER}"
    echo "  Password: ${MASTER_PASSWORD}"
    echo
    echo -e "${YELLOW}Configure slave with:${NC}"
    echo "  MASTER_HOST=$(hostname -I | awk '{print $1}') \\"
    echo "  MASTER_USER=${MASTER_USER} \\"
    echo "  MASTER_PASSWORD=${MASTER_PASSWORD} \\"
    echo "  ./setup-replication.sh slave"
    echo

# ============================================================================
# SLAVE CONFIGURATION
# ============================================================================
elif [ "$ROLE" = "slave" ]; then
    echo -e "${BLUE}[SLAVE] Setting up replication slave...${NC}"
    echo

    # Validate required variables
    if [ -z "$MASTER_HOST" ] || [ -z "$MASTER_USER" ] || [ -z "$MASTER_PASSWORD" ]; then
        echo -e "${RED}✗ Missing required variables${NC}"
        echo "Required: MASTER_HOST, MASTER_USER, MASTER_PASSWORD"
        exit 1
    fi

    # Step 1: Configure server
    echo -e "${BLUE}[1/7]${NC} Configuring server..."

    cat > /etc/mysql/mariadb.conf.d/60-replication.cnf <<EOF
[mysqld]
# Replication Configuration - Slave
server-id = ${SERVER_ID}
relay_log = /var/log/mysql/relay-bin
relay_log_index = /var/log/mysql/relay-bin.index
relay_log_recovery = ON

# Read-only mode (recommended for slaves)
read_only = 1
super_read_only = 1

# Replication settings
slave_net_timeout = 60
slave_parallel_threads = 4
slave_parallel_mode = conservative

# GTID Mode
gtid_strict_mode = ON
EOF

    echo -e "${GREEN}✓ Configuration file created${NC}"
    echo

    # Step 2: Restart MySQL
    echo -e "${BLUE}[2/7]${NC} Restarting MariaDB..."
    systemctl restart mariadb
    sleep 3
    echo -e "${GREEN}✓ MariaDB restarted${NC}"
    echo

    # Step 3: Stop slave (if running)
    echo -e "${BLUE}[3/7]${NC} Stopping slave..."
    mysql -u root -p${DB_ROOT_PASSWORD} -e "STOP SLAVE;" 2>/dev/null || true
    echo -e "${GREEN}✓ Slave stopped${NC}"
    echo

    # Step 4: Configure replication
    echo -e "${BLUE}[4/7]${NC} Configuring replication..."

    mysql -u root -p${DB_ROOT_PASSWORD} <<EOF
CHANGE MASTER TO
    MASTER_HOST='${MASTER_HOST}',
    MASTER_PORT=${MASTER_PORT},
    MASTER_USER='${MASTER_USER}',
    MASTER_PASSWORD='${MASTER_PASSWORD}',
    MASTER_USE_GTID=slave_pos;
EOF

    echo -e "${GREEN}✓ Replication configured${NC}"
    echo

    # Step 5: Start slave
    echo -e "${BLUE}[5/7]${NC} Starting slave..."
    mysql -u root -p${DB_ROOT_PASSWORD} -e "START SLAVE;"
    sleep 2
    echo -e "${GREEN}✓ Slave started${NC}"
    echo

    # Step 6: Check slave status
    echo -e "${BLUE}[6/7]${NC} Checking slave status..."

    SLAVE_STATUS=$(mysql -u root -p${DB_ROOT_PASSWORD} -e "SHOW SLAVE STATUS\G")

    IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
    SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')
    SECONDS_BEHIND=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')

    echo "$SLAVE_STATUS"
    echo

    if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
        echo -e "${GREEN}✓ Replication is working${NC}"
    else
        echo -e "${RED}✗ Replication failed to start${NC}"
        echo "IO Running: $IO_RUNNING"
        echo "SQL Running: $SQL_RUNNING"
        exit 1
    fi
    echo

    # Step 7: Save configuration
    echo -e "${BLUE}[7/7]${NC} Saving configuration..."

    cat > /root/.replication-slave-config <<EOF
# Slave Replication Configuration
# Generated: $(date)

MASTER_HOST=${MASTER_HOST}
MASTER_PORT=${MASTER_PORT}
MASTER_USER=${MASTER_USER}
SERVER_ID=${SERVER_ID}

Slave_IO_Running=${IO_RUNNING}
Slave_SQL_Running=${SQL_RUNNING}
Seconds_Behind_Master=${SECONDS_BEHIND}
EOF

    chmod 600 /root/.replication-slave-config

    echo -e "${GREEN}✓ Configuration saved to: /root/.replication-slave-config${NC}"
    echo

    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Slave configuration complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo "Replication Status:"
    echo "  Master: ${MASTER_HOST}:${MASTER_PORT}"
    echo "  IO Running: ${IO_RUNNING}"
    echo "  SQL Running: ${SQL_RUNNING}"
    echo "  Lag: ${SECONDS_BEHIND} seconds"
    echo
    echo -e "${YELLOW}Monitor replication with:${NC}"
    echo "  mysql -e 'SHOW SLAVE STATUS\\G'"
    echo

else
    echo -e "${RED}✗ Invalid role: ${ROLE}${NC}"
    echo "Usage: $0 <master|slave>"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo "1. Monitor replication status regularly"
echo "2. Set up monitoring alerts for replication lag"
echo "3. Test failover procedures"
echo "4. Document recovery procedures"
echo "5. Schedule regular replication health checks"
echo
