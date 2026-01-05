#!/usr/bin/env bash
# MariaDB database operations for vpsmanager

# Load config for database credentials
load_db_config() {
    local config_file="${VPSMANAGER_ROOT}/config/vpsmanager.conf"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
    fi

    # Defaults
    MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
    MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
    MYSQL_HOST="${MYSQL_HOST:-localhost}"
}

# Execute MySQL command as root
# Uses MYSQL_PWD to avoid password in process list
mysql_exec() {
    local sql="$1"
    load_db_config

    local mysql_cmd=(mysql -h "$MYSQL_HOST" -u "$MYSQL_ROOT_USER" -N)

    # Execute with password in environment (not visible in ps)
    local output
    local exit_code
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        output=$(MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "${mysql_cmd[@]}" -e "$sql" 2>&1)
    else
        output=$("${mysql_cmd[@]}" -e "$sql" 2>&1)
    fi
    exit_code=$?

    echo "$output"
    return $exit_code
}

# Escape string for use in SQL single-quoted string
sql_escape() {
    local str="$1"
    # Escape backslashes first, then single quotes
    str="${str//\\/\\\\}"
    str="${str//\'/\'\'}"
    echo "$str"
}

# Create database for a site
# Usage: create_site_database "domain" "db_name" "db_user" "db_password"
create_site_database() {
    local domain="$1"
    local db_name="$2"
    local db_user="$3"
    local db_password="$4"

    # Sanitize inputs for SQL (db_name and db_user should already be clean from domain_to_dbname)
    db_name=$(echo "$db_name" | tr -cd 'a-zA-Z0-9_')
    db_user=$(echo "$db_user" | tr -cd 'a-zA-Z0-9_')
    local escaped_password
    escaped_password=$(sql_escape "$db_password")

    log_info "Creating database ${db_name} for ${domain}"

    # Create database
    local sql="CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    if ! mysql_exec "$sql"; then
        log_error "Failed to create database ${db_name}"
        return 1
    fi

    # Create user with escaped password
    sql="CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${escaped_password}';"
    if ! mysql_exec "$sql"; then
        log_error "Failed to create user ${db_user}"
        return 1
    fi

    # Grant privileges
    sql="GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';"
    if ! mysql_exec "$sql"; then
        log_error "Failed to grant privileges to ${db_user}"
        return 1
    fi

    # Flush privileges
    mysql_exec "FLUSH PRIVILEGES;"

    log_info "Database ${db_name} created successfully"
    return 0
}

# Drop database and user for a site
# Usage: drop_site_database "db_name" "db_user"
drop_site_database() {
    local db_name="$1"
    local db_user="$2"

    # Sanitize inputs
    db_name=$(echo "$db_name" | tr -cd 'a-zA-Z0-9_')
    db_user=$(echo "$db_user" | tr -cd 'a-zA-Z0-9_')

    log_info "Dropping database ${db_name} and user ${db_user}"

    # Drop database
    local sql="DROP DATABASE IF EXISTS \`${db_name}\`;"
    mysql_exec "$sql"

    # Drop user
    sql="DROP USER IF EXISTS '${db_user}'@'localhost';"
    mysql_exec "$sql"

    mysql_exec "FLUSH PRIVILEGES;"

    log_info "Database ${db_name} dropped"
    return 0
}

# Check if database exists
database_exists() {
    local db_name="$1"
    db_name=$(echo "$db_name" | tr -cd 'a-zA-Z0-9_')

    local result
    result=$(mysql_exec "SHOW DATABASES LIKE '${db_name}';")

    if [[ -n "$result" ]]; then
        return 0
    fi
    return 1
}

# Generate secure random password
# Uses only alphanumeric characters to avoid SQL/shell escaping issues
generate_db_password() {
    local length="${1:-32}"
    # Use alphanumeric only to avoid any SQL injection or shell escaping issues
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# Dump database to file
# Usage: dump_database "db_name" "output_file"
dump_database() {
    local db_name="$1"
    local output_file="$2"
    load_db_config

    db_name=$(echo "$db_name" | tr -cd 'a-zA-Z0-9_')

    local mysqldump_cmd=(mysqldump -h "$MYSQL_HOST" -u "$MYSQL_ROOT_USER" --single-transaction --quick)

    log_info "Dumping database ${db_name} to ${output_file}"

    local result
    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        result=$(MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "${mysqldump_cmd[@]}" "$db_name" 2>&1)
    else
        result=$("${mysqldump_cmd[@]}" "$db_name" 2>&1)
    fi

    if [[ $? -eq 0 ]]; then
        echo "$result" > "$output_file"
        log_info "Database dump completed: $(du -h "$output_file" | cut -f1)"
        return 0
    else
        log_error "Database dump failed for ${db_name}: $result"
        return 1
    fi
}

# Restore database from file
# Usage: restore_database "db_name" "input_file"
restore_database() {
    local db_name="$1"
    local input_file="$2"
    load_db_config

    db_name=$(echo "$db_name" | tr -cd 'a-zA-Z0-9_')

    local mysql_cmd=(mysql -h "$MYSQL_HOST" -u "$MYSQL_ROOT_USER")

    log_info "Restoring database ${db_name} from ${input_file}"

    if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
        if MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "${mysql_cmd[@]}" "$db_name" < "$input_file" 2>&1; then
            log_info "Database restore completed for ${db_name}"
            return 0
        fi
    else
        if "${mysql_cmd[@]}" "$db_name" < "$input_file" 2>&1; then
            log_info "Database restore completed for ${db_name}"
            return 0
        fi
    fi

    log_error "Database restore failed for ${db_name}"
    return 1
}
