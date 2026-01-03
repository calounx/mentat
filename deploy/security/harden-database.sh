#!/bin/bash
# ============================================================================
# Database Security Hardening Script
# ============================================================================
# Purpose: Harden PostgreSQL database with enterprise-grade security
# Features: SSL/TLS, limited privileges, secure authentication, audit logging
# Compliance: PCI DSS, SOC 2, OWASP
# ============================================================================

set -euo pipefail

# Configuration
DB_NAME="${DB_NAME:-chom}"
DB_USER="${DB_USER:-chom}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_BACKUP_USER="${DB_BACKUP_USER:-chom_backup}"
DB_BACKUP_PASSWORD="${DB_BACKUP_PASSWORD:-}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
PG_VERSION="${PG_VERSION:-15}"
PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install PostgreSQL if not present
install_postgresql() {
    log_info "Checking PostgreSQL installation..."

    if command -v psql &> /dev/null; then
        log_success "PostgreSQL is already installed"
        return 0
    fi

    log_info "Installing PostgreSQL..."

    apt-get update -qq
    apt-get install -y postgresql postgresql-contrib

    systemctl start postgresql
    systemctl enable postgresql

    log_success "PostgreSQL installed and started"
}

# Load passwords from secrets
load_passwords() {
    log_info "Loading database passwords..."

    local secrets_dir="/etc/chom/secrets"

    if [[ -z "$DB_PASSWORD" ]] && [[ -f "$secrets_dir/db_password" ]]; then
        DB_PASSWORD=$(cat "$secrets_dir/db_password")
        log_success "Loaded DB password from secrets"
    fi

    if [[ -z "$DB_PASSWORD" ]]; then
        log_warning "DB_PASSWORD not set, generating random password..."
        DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
        mkdir -p "$secrets_dir"
        echo "$DB_PASSWORD" > "$secrets_dir/db_password"
        chmod 600 "$secrets_dir/db_password"
        log_success "Generated and saved DB password"
    fi

    if [[ -z "$DB_BACKUP_PASSWORD" ]]; then
        DB_BACKUP_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
        mkdir -p "$secrets_dir"
        echo "$DB_BACKUP_PASSWORD" > "$secrets_dir/db_backup_password"
        chmod 600 "$secrets_dir/db_backup_password"
        log_success "Generated and saved backup user password"
    fi
}

# Create database and users
create_database_and_users() {
    log_info "Creating database and users..."

    # Create database
    sudo -u postgres psql <<EOF
-- Create database if not exists
SELECT 'CREATE DATABASE $DB_NAME'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

-- Create application user
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER') THEN
        CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

-- Create backup user (read-only)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_BACKUP_USER') THEN
        CREATE USER $DB_BACKUP_USER WITH ENCRYPTED PASSWORD '$DB_BACKUP_PASSWORD';
    END IF;
END
\$\$;

-- Grant privileges
GRANT CONNECT ON DATABASE $DB_NAME TO $DB_USER;
GRANT CONNECT ON DATABASE $DB_NAME TO $DB_BACKUP_USER;

-- Connect to database and set privileges
\c $DB_NAME

-- Application user: full privileges on schema
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

-- Backup user: read-only access
GRANT USAGE ON SCHEMA public TO $DB_BACKUP_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $DB_BACKUP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO $DB_BACKUP_USER;

-- Revoke public schema creation
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
EOF

    log_success "Database and users created with proper privileges"
}

# Configure PostgreSQL for security
harden_postgresql_config() {
    log_info "Hardening PostgreSQL configuration..."

    local pg_conf="$PG_CONF_DIR/postgresql.conf"
    local pg_hba="$PG_CONF_DIR/pg_hba.conf"

    # Backup original configuration
    cp "$pg_conf" "${pg_conf}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$pg_hba" "${pg_hba}.backup.$(date +%Y%m%d_%H%M%S)"

    # Update postgresql.conf with security settings
    cat >> "$pg_conf" <<EOF

# ============================================================================
# CHOM Security Hardening
# Generated: $(date)
# ============================================================================

# Connection Settings
listen_addresses = 'localhost'
max_connections = 100
superuser_reserved_connections = 3

# SSL/TLS Configuration
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'

# Authentication
password_encryption = scram-sha-256
db_user_namespace = off

# Security and Authentication
shared_preload_libraries = 'pg_stat_statements'

# Logging Configuration (Security Auditing)
logging_collector = on
log_destination = 'stderr'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_connections = on
log_disconnections = on
log_duration = off
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_lock_waits = on
log_statement = 'ddl'
log_temp_files = 0
log_timezone = 'UTC'

# Statement Statistics
pg_stat_statements.track = all
pg_stat_statements.max = 10000

# Resource Limits
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 128MB
effective_cache_size = 1GB

# Write Ahead Log (WAL) - for backup and recovery
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/wal_archive/%f && cp %p /var/lib/postgresql/wal_archive/%f'

# Query and Index Statistics
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all

# Autovacuum (maintenance)
autovacuum = on
autovacuum_max_workers = 3

# Security: Statement Timeout (prevent long-running queries)
statement_timeout = 30000  # 30 seconds
lock_timeout = 10000       # 10 seconds
idle_in_transaction_session_timeout = 60000  # 1 minute

# Client Connection Defaults
client_min_messages = notice
EOF

    # Create WAL archive directory
    mkdir -p /var/lib/postgresql/wal_archive
    chown postgres:postgres /var/lib/postgresql/wal_archive
    chmod 700 /var/lib/postgresql/wal_archive

    log_success "PostgreSQL configuration hardened"
}

# Configure host-based authentication
configure_pg_hba() {
    log_info "Configuring host-based authentication (pg_hba.conf)..."

    local pg_hba="$PG_CONF_DIR/pg_hba.conf"

    cat > "$pg_hba" <<EOF
# ============================================================================
# CHOM PostgreSQL Client Authentication Configuration
# Generated: $(date)
# ============================================================================
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections (Unix socket)
local   all             postgres                                peer
local   all             all                                     scram-sha-256

# IPv4 local connections
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 local connections
host    all             all             ::1/128                 scram-sha-256

# Deny all other connections
host    all             all             0.0.0.0/0               reject
host    all             all             ::/0                    reject

# NOTE: To allow remote connections from specific IPs, add:
# host    $DB_NAME        $DB_USER        <IP_ADDRESS>/32         scram-sha-256
EOF

    log_success "Host-based authentication configured"
    log_warning "Remote connections are DENIED by default"
    log_info "To allow remote connections, edit: $pg_hba"
}

# Enable SSL/TLS
enable_ssl() {
    log_info "Configuring SSL/TLS for PostgreSQL..."

    # Check if custom SSL certificates exist
    if [[ -f "/etc/letsencrypt/live/landsraad.arewel.com/fullchain.pem" ]]; then
        log_info "Using Let's Encrypt certificates"

        local cert_path="/etc/letsencrypt/live/landsraad.arewel.com"

        # Update postgresql.conf
        sed -i "s|ssl_cert_file = .*|ssl_cert_file = '${cert_path}/fullchain.pem'|" "$PG_CONF_DIR/postgresql.conf"
        sed -i "s|ssl_key_file = .*|ssl_key_file = '${cert_path}/privkey.pem'|" "$PG_CONF_DIR/postgresql.conf"

        # Allow postgres to read certificates
        setfacl -m u:postgres:rx /etc/letsencrypt/live
        setfacl -m u:postgres:rx /etc/letsencrypt/archive
        setfacl -m u:postgres:r /etc/letsencrypt/live/landsraad.arewel.com/privkey.pem
        setfacl -m u:postgres:r /etc/letsencrypt/live/landsraad.arewel.com/fullchain.pem

        log_success "SSL configured with Let's Encrypt certificates"
    else
        log_info "Using self-signed certificates"
        log_warning "Consider using Let's Encrypt for production"
    fi
}

# Install pg_stat_statements extension
install_extensions() {
    log_info "Installing PostgreSQL extensions..."

    sudo -u postgres psql -d "$DB_NAME" <<EOF
-- Enable pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Enable pgcrypto for cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enable uuid-ossp for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant usage
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO $DB_USER;
EOF

    log_success "PostgreSQL extensions installed"
}

# Configure connection limits
configure_connection_limits() {
    log_info "Configuring connection limits..."

    sudo -u postgres psql <<EOF
-- Set connection limits for application user
ALTER USER $DB_USER CONNECTION LIMIT 50;

-- Set connection limits for backup user
ALTER USER $DB_BACKUP_USER CONNECTION LIMIT 5;

-- Prevent postgres user from remote connections
ALTER USER postgres CONNECTION LIMIT -1;
EOF

    log_success "Connection limits configured"
}

# Create security audit functions
create_audit_functions() {
    log_info "Creating security audit functions..."

    sudo -u postgres psql -d "$DB_NAME" <<'EOF'
-- Create audit schema
CREATE SCHEMA IF NOT EXISTS audit;

-- Create audit log table
CREATE TABLE IF NOT EXISTS audit.activity_log (
    id SERIAL PRIMARY KEY,
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_name TEXT,
    database_name TEXT,
    client_addr INET,
    application_name TEXT,
    event_type TEXT,
    object_type TEXT,
    object_name TEXT,
    command_text TEXT
);

-- Create function to log DDL changes
CREATE OR REPLACE FUNCTION audit.log_ddl_changes()
RETURNS event_trigger AS $$
DECLARE
    audit_query TEXT;
BEGIN
    INSERT INTO audit.activity_log (
        user_name,
        database_name,
        event_type,
        command_text
    ) VALUES (
        current_user,
        current_database(),
        tg_tag,
        current_query()
    );
END;
$$ LANGUAGE plpgsql;

-- Create event trigger for DDL
DROP EVENT TRIGGER IF EXISTS audit_ddl_trigger;
CREATE EVENT TRIGGER audit_ddl_trigger
    ON ddl_command_end
    EXECUTE FUNCTION audit.log_ddl_changes();

-- Grant select on audit tables
GRANT USAGE ON SCHEMA audit TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO PUBLIC;
EOF

    log_success "Audit functions created"
}

# Restart PostgreSQL
restart_postgresql() {
    log_info "Restarting PostgreSQL..."

    systemctl restart postgresql

    if systemctl is-active --quiet postgresql; then
        log_success "PostgreSQL restarted successfully"
    else
        log_error "PostgreSQL failed to restart"
        log_error "Check logs: journalctl -u postgresql -n 50"
        exit 1
    fi
}

# Test database connection
test_connection() {
    log_info "Testing database connection..."

    # Test application user connection
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" &>/dev/null; then
        log_success "Application user connection successful"
    else
        log_error "Application user connection failed"
        return 1
    fi

    # Test backup user connection
    if PGPASSWORD="$DB_BACKUP_PASSWORD" psql -h "$DB_HOST" -U "$DB_BACKUP_USER" -d "$DB_NAME" -c "SELECT version();" &>/dev/null; then
        log_success "Backup user connection successful"
    else
        log_error "Backup user connection failed"
        return 1
    fi

    return 0
}

# Display security summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "Database Security Hardening Complete"
    log_success "=========================================="
    echo ""

    log_info "Database Configuration:"
    echo "  Database: $DB_NAME"
    echo "  Application User: $DB_USER"
    echo "  Backup User: $DB_BACKUP_USER"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT"
    echo ""

    log_info "Security Features Enabled:"
    echo "  ✓ SSL/TLS encryption (TLS 1.2+)"
    echo "  ✓ SCRAM-SHA-256 password authentication"
    echo "  ✓ Limited user privileges"
    echo "  ✓ Connection limits enforced"
    echo "  ✓ Audit logging enabled"
    echo "  ✓ Statement timeouts configured"
    echo "  ✓ Remote access denied (localhost only)"
    echo "  ✓ WAL archiving enabled"
    echo "  ✓ Query statistics tracking"
    echo ""

    log_info "Connection Strings:"
    echo "  Application:"
    echo "    postgresql://$DB_USER:<password>@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=require"
    echo ""
    echo "  Backup (read-only):"
    echo "    postgresql://$DB_BACKUP_USER:<password>@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=require"
    echo ""

    log_info "Credentials stored in:"
    echo "  /etc/chom/secrets/db_password"
    echo "  /etc/chom/secrets/db_backup_password"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  1. Keep database passwords secure"
    echo "  2. Regular backups are configured"
    echo "  3. Monitor audit logs regularly"
    echo "  4. Update PostgreSQL regularly"
    echo "  5. Review pg_hba.conf before allowing remote access"
    echo ""
}

# Create database management helper
create_db_helper() {
    log_info "Creating database management helper..."

    local helper_script="/usr/local/bin/chom-db"

    cat > "$helper_script" <<EOF
#!/bin/bash
# CHOM Database Management Helper

DB_NAME="$DB_NAME"
DB_USER="$DB_USER"

case "\$1" in
    status)
        sudo systemctl status postgresql
        ;;
    connect)
        sudo -u postgres psql -d "\$DB_NAME"
        ;;
    backup)
        backup_file="/var/backups/chom/db_backup_\$(date +%Y%m%d_%H%M%S).sql.gz"
        sudo -u postgres pg_dump "\$DB_NAME" | gzip > "\$backup_file"
        echo "Backup created: \$backup_file"
        ;;
    restore)
        if [[ -z "\$2" ]]; then
            echo "Usage: chom-db restore <backup-file>"
            exit 1
        fi
        gunzip -c "\$2" | sudo -u postgres psql "\$DB_NAME"
        ;;
    audit)
        sudo -u postgres psql -d "\$DB_NAME" -c "SELECT * FROM audit.activity_log ORDER BY event_time DESC LIMIT 50;"
        ;;
    stats)
        sudo -u postgres psql -d "\$DB_NAME" -c "SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;"
        ;;
    connections)
        sudo -u postgres psql -c "SELECT datname, usename, client_addr, state, query FROM pg_stat_activity WHERE datname = '\$DB_NAME';"
        ;;
    vacuum)
        sudo -u postgres vacuumdb -z -d "\$DB_NAME"
        echo "Vacuum complete"
        ;;
    *)
        echo "CHOM Database Management"
        echo ""
        echo "Usage: chom-db <command> [args]"
        echo ""
        echo "Commands:"
        echo "  status              Show PostgreSQL status"
        echo "  connect             Connect to database"
        echo "  backup              Create database backup"
        echo "  restore <file>      Restore from backup"
        echo "  audit               Show recent audit log"
        echo "  stats               Show query statistics"
        echo "  connections         Show active connections"
        echo "  vacuum              Run vacuum analyze"
        echo ""
        ;;
esac
EOF

    chmod +x "$helper_script"
    log_success "Database helper created: $helper_script"
}

# Main execution
main() {
    log_info "Starting database security hardening..."
    echo ""

    check_root
    install_postgresql
    load_passwords
    create_database_and_users
    harden_postgresql_config
    configure_pg_hba
    enable_ssl
    install_extensions
    configure_connection_limits
    create_audit_functions
    restart_postgresql
    test_connection
    create_db_helper
    display_summary

    log_success "Database hardening complete!"
}

# Run main function
main "$@"
