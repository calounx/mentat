#!/bin/bash
# ============================================================================
# CHOM Health Check Script
# ============================================================================
# Checks the health of all critical services
# Returns 0 if healthy, 1 if unhealthy
# ============================================================================

HEALTHY=0

# ============================================================================
# Check Nginx
# ============================================================================
if ! curl -f http://localhost/health > /dev/null 2>&1; then
    echo "UNHEALTHY: Nginx is not responding"
    HEALTHY=1
fi

# ============================================================================
# Check PHP-FPM
# ============================================================================
if ! curl -f http://localhost/fpm-ping > /dev/null 2>&1; then
    echo "UNHEALTHY: PHP-FPM is not responding"
    HEALTHY=1
fi

# ============================================================================
# Check MySQL
# ============================================================================
if ! mysqladmin ping -h localhost --silent; then
    echo "UNHEALTHY: MySQL is not responding"
    HEALTHY=1
fi

# ============================================================================
# Check Redis
# ============================================================================
if ! redis-cli ping > /dev/null 2>&1; then
    echo "UNHEALTHY: Redis is not responding"
    HEALTHY=1
fi

# ============================================================================
# Check if Laravel application is accessible
# ============================================================================
if [ -f "/var/www/chom/artisan" ]; then
    if ! curl -f http://localhost > /dev/null 2>&1; then
        echo "UNHEALTHY: Laravel application is not responding"
        HEALTHY=1
    fi
fi

# ============================================================================
# Return status
# ============================================================================
if [ $HEALTHY -eq 0 ]; then
    echo "HEALTHY: All services are running"
    exit 0
else
    exit 1
fi
