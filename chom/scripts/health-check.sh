#!/bin/bash

# Post-deployment health check script
# Validates application health after deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
APP_URL="${APP_URL:-http://localhost}"
TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
MAX_RETRIES="${HEALTH_CHECK_RETRIES:-5}"
RETRY_DELAY="${HEALTH_CHECK_RETRY_DELAY:-5}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "  POST-DEPLOYMENT HEALTH CHECKS"
echo "========================================="
echo ""

ERRORS=0

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to check HTTP endpoint
check_endpoint() {
    local url=$1
    local expected_status=${2:-200}
    local description=$3

    echo "Checking: $description"

    for i in $(seq 1 $MAX_RETRIES); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "$url" || echo "000")

        if [ "$HTTP_CODE" = "$expected_status" ]; then
            success "$description (HTTP $HTTP_CODE)"
            return 0
        else
            if [ $i -lt $MAX_RETRIES ]; then
                warning "Attempt $i/$MAX_RETRIES failed (HTTP $HTTP_CODE), retrying in ${RETRY_DELAY}s..."
                sleep $RETRY_DELAY
            fi
        fi
    done

    error "$description failed after $MAX_RETRIES attempts (HTTP $HTTP_CODE)"
    return 1
}

# Function to check response time
check_response_time() {
    local url=$1
    local max_time=$2
    local description=$3

    echo "Checking response time: $description"

    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time $TIMEOUT "$url" 2>/dev/null || echo "999")
    RESPONSE_MS=$(echo "$RESPONSE_TIME * 1000" | bc)
    MAX_MS=$(echo "$max_time * 1000" | bc)

    if (( $(echo "$RESPONSE_TIME < $max_time" | bc -l) )); then
        success "$description responded in ${RESPONSE_MS}ms"
    else
        warning "$description slow response: ${RESPONSE_MS}ms (expected < ${MAX_MS}ms)"
    fi
}

# Check 1: Basic health endpoint
check_endpoint "$APP_URL/health" 200 "Basic health endpoint"

# Check 2: Readiness check
check_endpoint "$APP_URL/health/ready" 200 "Readiness check (DB, Redis, Queue)"

# Check 3: Liveness check
check_endpoint "$APP_URL/health/live" 200 "Liveness check"

# Check 4: Response time
check_response_time "$APP_URL" 2.0 "Homepage response time"

# Check 5: Database connectivity via artisan
echo "Checking database via artisan..."
cd "$PROJECT_ROOT"
if php artisan db:show > /dev/null 2>&1; then
    success "Database accessible via artisan"
else
    error "Database not accessible via artisan"
fi

# Check 6: Redis connectivity via artisan
echo "Checking Redis via artisan..."
if php artisan tinker --execute="Redis::ping();" 2>/dev/null | grep -q "PONG"; then
    success "Redis accessible via artisan"
else
    error "Redis not accessible via artisan"
fi

# Check 7: Cache is working
echo "Checking cache functionality..."
TEST_KEY="health_check_$(date +%s)"
TEST_VALUE="test_value_$(date +%s)"

php artisan tinker --execute="Cache::put('$TEST_KEY', '$TEST_VALUE', 60);" > /dev/null 2>&1
CACHED_VALUE=$(php artisan tinker --execute="echo Cache::get('$TEST_KEY');" 2>/dev/null | grep -v "^>" | tail -1)

if [ "$CACHED_VALUE" = "$TEST_VALUE" ]; then
    success "Cache read/write working"
    php artisan tinker --execute="Cache::forget('$TEST_KEY');" > /dev/null 2>&1
else
    error "Cache not working properly"
fi

# Check 8: Queue is processing
echo "Checking queue functionality..."
QUEUE_SIZE=$(php artisan queue:monitor --once 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
success "Queue size: $QUEUE_SIZE jobs"

# Check 9: Storage is writable
echo "Checking storage write permissions..."
TEST_FILE="$PROJECT_ROOT/storage/app/health_check_$(date +%s).tmp"
if touch "$TEST_FILE" 2>/dev/null; then
    success "Storage is writable"
    rm -f "$TEST_FILE"
else
    error "Storage is not writable"
fi

# Check 10: Log files are being written
echo "Checking log files..."
LOG_FILE="$PROJECT_ROOT/storage/logs/laravel.log"
if [ -f "$LOG_FILE" ]; then
    LOG_AGE=$(stat -c %Y "$LOG_FILE")
    CURRENT_TIME=$(date +%s)
    AGE_MINUTES=$(( ($CURRENT_TIME - $LOG_AGE) / 60 ))

    if [ $AGE_MINUTES -lt 60 ]; then
        success "Log file recently updated ($AGE_MINUTES minutes ago)"
    else
        warning "Log file not recently updated ($AGE_MINUTES minutes ago)"
    fi
else
    warning "Log file not found"
fi

# Check 11: Configuration is cached
echo "Checking configuration cache..."
if [ -f "$PROJECT_ROOT/bootstrap/cache/config.php" ]; then
    success "Configuration is cached"
else
    warning "Configuration not cached (performance impact)"
fi

# Check 12: Routes are cached
echo "Checking route cache..."
if [ -f "$PROJECT_ROOT/bootstrap/cache/routes-v7.php" ]; then
    success "Routes are cached"
else
    warning "Routes not cached (performance impact)"
fi

# Check 13: Memory usage
echo "Checking PHP memory configuration..."
MEMORY_LIMIT=$(php -r "echo ini_get('memory_limit');")
success "PHP memory limit: $MEMORY_LIMIT"

# Check 14: Error log check
echo "Checking for recent errors..."
if [ -f "$LOG_FILE" ]; then
    RECENT_ERRORS=$(tail -100 "$LOG_FILE" | grep -c "ERROR" || echo "0")
    if [ "$RECENT_ERRORS" -eq 0 ]; then
        success "No recent errors in log"
    else
        warning "Found $RECENT_ERRORS recent error(s) in log"
    fi
fi

# Check 15: API endpoints (if applicable)
if [ -n "${API_HEALTH_ENDPOINTS:-}" ]; then
    IFS=',' read -ra ENDPOINTS <<< "$API_HEALTH_ENDPOINTS"
    for endpoint in "${ENDPOINTS[@]}"; do
        check_endpoint "$APP_URL$endpoint" 200 "API endpoint: $endpoint"
    done
fi

# Summary
echo ""
echo "========================================="
echo "  HEALTH CHECK SUMMARY"
echo "========================================="

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All health checks passed!${NC}"
    echo "Application is healthy and ready for traffic."
    exit 0
else
    echo -e "${RED}Health checks failed with $ERRORS error(s)${NC}"
    echo "Application may not be ready for production traffic."
    exit 1
fi
