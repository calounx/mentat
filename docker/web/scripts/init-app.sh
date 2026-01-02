#!/bin/bash
# ============================================================================
# CHOM Application Initialization Script
# ============================================================================
# This script initializes the Laravel application on container startup
# ============================================================================

set -e

APP_PATH="/var/www/chom"
LOG_PREFIX="[CHOM-INIT]"

echo "$LOG_PREFIX Starting CHOM container..."

# ============================================================================
# Create necessary directories and set permissions
# ============================================================================
echo "$LOG_PREFIX Creating system directories..."
mkdir -p /var/log/php-fpm /var/log/php /var/log/mysql /var/log/supervisor /var/lib/alloy /run/php /var/run/mysqld
chown -R www-data:www-data /var/log/php-fpm /var/log/php
chown -R mysql:mysql /var/log/mysql /var/run/mysqld /var/lib/mysql
touch /var/log/supervisor/supervisord.log

# ============================================================================
# Initialize MySQL data directory if needed
# ============================================================================
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "$LOG_PREFIX Initializing MySQL data directory..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

# ============================================================================
# Start supervisor (which manages all services including MySQL/Redis)
# ============================================================================
echo "$LOG_PREFIX Starting supervisor..."
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &
SUPERVISOR_PID=$!

# Give supervisor time to start services
sleep 5

# ============================================================================
# Wait for MySQL to be ready
# ============================================================================
echo "$LOG_PREFIX Waiting for MySQL to start..."
max_attempts=60
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "$LOG_PREFIX MySQL is ready!"
        break
    fi
    attempt=$((attempt + 1))
    echo "$LOG_PREFIX Waiting for MySQL... (attempt $attempt/$max_attempts)"
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "$LOG_PREFIX ERROR: MySQL failed to start within timeout period"
    # Continue anyway for debugging
fi

# ============================================================================
# Wait for Redis to be ready
# ============================================================================
echo "$LOG_PREFIX Waiting for Redis to start..."
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if redis-cli ping > /dev/null 2>&1; then
        echo "$LOG_PREFIX Redis is ready!"
        break
    fi
    attempt=$((attempt + 1))
    echo "$LOG_PREFIX Waiting for Redis... (attempt $attempt/$max_attempts)"
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "$LOG_PREFIX WARNING: Redis failed to start within timeout period"
fi

# ============================================================================
# Create MySQL database and users
# ============================================================================
echo "$LOG_PREFIX Setting up MySQL database..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_DATABASE:-chom};" || echo "$LOG_PREFIX Database may already exist"
mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USERNAME:-chom}'@'localhost' IDENTIFIED BY '${DB_PASSWORD:-secret}';" || echo "$LOG_PREFIX User may already exist"
mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USERNAME:-chom}'@'%' IDENTIFIED BY '${DB_PASSWORD:-secret}';" || echo "$LOG_PREFIX User may already exist"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_DATABASE:-chom}.* TO '${DB_USERNAME:-chom}'@'localhost';" || true
mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_DATABASE:-chom}.* TO '${DB_USERNAME:-chom}'@'%';" || true
mysql -u root -e "FLUSH PRIVILEGES;" || true

# Create MySQL exporter user
echo "$LOG_PREFIX Creating MySQL exporter user..."
mysql -u root -e "CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'exporter_password' WITH MAX_USER_CONNECTIONS 3;" || true
mysql -u root -e "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';" || true
mysql -u root -e "FLUSH PRIVILEGES;" || true

# Create exporter config
cat > /etc/mysql/exporter.cnf <<EOF
[client]
user=exporter
password=exporter_password
EOF
chmod 600 /etc/mysql/exporter.cnf

# ============================================================================
# Check if Laravel application exists
# ============================================================================
if [ ! -f "$APP_PATH/artisan" ]; then
    echo "$LOG_PREFIX WARNING: Laravel application not found at $APP_PATH"
    echo "$LOG_PREFIX Please mount your application at $APP_PATH"
    echo "$LOG_PREFIX Skipping Laravel initialization..."
else
    echo "$LOG_PREFIX Laravel application found, initializing..."

    cd $APP_PATH

    # ========================================================================
    # Install Composer dependencies
    # ========================================================================
    if [ ! -d "$APP_PATH/vendor" ]; then
        echo "$LOG_PREFIX Installing Composer dependencies..."
        su -s /bin/bash www-data -c "composer install --no-interaction --no-dev --optimize-autoloader" || echo "$LOG_PREFIX Composer install failed"
    else
        echo "$LOG_PREFIX Composer dependencies already installed"
    fi

    # ========================================================================
    # Create .env file if it doesn't exist
    # ========================================================================
    if [ ! -f "$APP_PATH/.env" ]; then
        echo "$LOG_PREFIX Creating .env file from .env.example..."
        if [ -f "$APP_PATH/.env.example" ]; then
            cp "$APP_PATH/.env.example" "$APP_PATH/.env"
            chown www-data:www-data "$APP_PATH/.env"
        fi
    fi

    # ========================================================================
    # Generate application key if missing
    # ========================================================================
    if [ -f "$APP_PATH/.env" ] && ! grep -q "APP_KEY=base64:" "$APP_PATH/.env"; then
        echo "$LOG_PREFIX Generating application key..."
        su -s /bin/bash www-data -c "php artisan key:generate --force" || echo "$LOG_PREFIX Key generation skipped"
    else
        echo "$LOG_PREFIX Application key already set"
    fi

    # ========================================================================
    # Create storage directories and set permissions
    # ========================================================================
    echo "$LOG_PREFIX Setting up storage directories..."
    mkdir -p "$APP_PATH/storage/framework/"{sessions,views,cache}
    mkdir -p "$APP_PATH/storage/logs"
    mkdir -p "$APP_PATH/bootstrap/cache"
    chown -R www-data:www-data "$APP_PATH/storage" "$APP_PATH/bootstrap/cache"
    chmod -R 775 "$APP_PATH/storage" "$APP_PATH/bootstrap/cache"

    # ========================================================================
    # Run database migrations
    # ========================================================================
    echo "$LOG_PREFIX Running database migrations..."
    max_migration_attempts=5
    migration_attempt=0

    while [ $migration_attempt -lt $max_migration_attempts ]; do
        if su -s /bin/bash www-data -c "php artisan migrate --force" 2>/dev/null; then
            echo "$LOG_PREFIX Database migrations completed successfully"
            break
        fi
        migration_attempt=$((migration_attempt + 1))
        echo "$LOG_PREFIX Migration attempt $migration_attempt failed, retrying..."
        sleep 5
    done

    # ========================================================================
    # Seed database (only in development)
    # ========================================================================
    if [ "${APP_ENV:-production}" = "local" ] || [ "${APP_ENV:-production}" = "development" ]; then
        echo "$LOG_PREFIX Seeding database with test data..."
        su -s /bin/bash www-data -c "php artisan db:seed --force" 2>/dev/null || echo "$LOG_PREFIX Database seeding skipped or failed"
    fi

    # ========================================================================
    # Cache optimization
    # ========================================================================
    echo "$LOG_PREFIX Optimizing application cache..."
    su -s /bin/bash www-data -c "php artisan config:cache" 2>/dev/null || echo "$LOG_PREFIX Config cache skipped"
    su -s /bin/bash www-data -c "php artisan route:cache" 2>/dev/null || echo "$LOG_PREFIX Route cache skipped"
    su -s /bin/bash www-data -c "php artisan view:cache" 2>/dev/null || echo "$LOG_PREFIX View cache skipped"

    # ========================================================================
    # Set up Laravel scheduler cron
    # ========================================================================
    echo "$LOG_PREFIX Setting up Laravel scheduler..."
    (crontab -u www-data -l 2>/dev/null || true; echo "* * * * * cd $APP_PATH && php artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data - 2>/dev/null || true

    echo "$LOG_PREFIX Laravel application initialization complete!"
fi

# ============================================================================
# Keep container running by waiting for supervisor
# ============================================================================
echo "$LOG_PREFIX Initialization complete, monitoring services..."
wait $SUPERVISOR_PID
