#!/bin/bash

# Pre-deployment checks script
# Validates system state before deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "  PRE-DEPLOYMENT CHECKS"
echo "========================================="
echo ""

ERRORS=0
WARNINGS=0

# Function to print success
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print error
error() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

# Function to print warning
warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

# Check 1: PHP Version
echo "Checking PHP version..."
PHP_VERSION=$(php -r "echo PHP_VERSION;")
PHP_MAJOR=$(php -r "echo PHP_MAJOR_VERSION;")
PHP_MINOR=$(php -r "echo PHP_MINOR_VERSION;")

if [ "$PHP_MAJOR" -ge 8 ] && [ "$PHP_MINOR" -ge 2 ]; then
    success "PHP version $PHP_VERSION (>= 8.2)"
else
    error "PHP version $PHP_VERSION is too old (requires >= 8.2)"
fi

# Check 2: Required PHP extensions
echo "Checking PHP extensions..."
REQUIRED_EXTENSIONS=("mbstring" "xml" "bcmath" "curl" "gd" "zip" "pdo" "redis")

for ext in "${REQUIRED_EXTENSIONS[@]}"; do
    if php -m | grep -q "^$ext$"; then
        success "PHP extension: $ext"
    else
        error "Missing PHP extension: $ext"
    fi
done

# Check 3: Composer installed
echo "Checking Composer..."
if command -v composer &> /dev/null; then
    COMPOSER_VERSION=$(composer --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    success "Composer $COMPOSER_VERSION installed"
else
    error "Composer not found"
fi

# Check 4: Node.js and NPM
echo "Checking Node.js and NPM..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    success "Node.js $NODE_VERSION installed"
else
    error "Node.js not found"
fi

if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm --version)
    success "NPM $NPM_VERSION installed"
else
    error "NPM not found"
fi

# Check 5: .env file exists
echo "Checking .env file..."
if [ -f "$PROJECT_ROOT/.env" ]; then
    success ".env file exists"

    # Check required environment variables
    REQUIRED_VARS=("APP_KEY" "DB_CONNECTION" "DB_DATABASE" "REDIS_HOST" "REDIS_PASSWORD")
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^${var}=" "$PROJECT_ROOT/.env"; then
            success "Environment variable: $var"
        else
            error "Missing environment variable: $var"
        fi
    done
else
    error ".env file not found"
fi

# Check 6: Database connectivity
echo "Checking database connectivity..."
cd "$PROJECT_ROOT"
if php artisan db:show > /dev/null 2>&1; then
    success "Database connection successful"
else
    error "Cannot connect to database"
fi

# Check 7: Redis connectivity
echo "Checking Redis connectivity..."
if php artisan tinker --execute="Redis::ping();" 2>/dev/null | grep -q "PONG"; then
    success "Redis connection successful"
else
    error "Cannot connect to Redis"
fi

# Check 8: Disk space
echo "Checking disk space..."
DISK_USAGE=$(df "$PROJECT_ROOT" | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    success "Disk usage: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -lt 90 ]; then
    warning "Disk usage: ${DISK_USAGE}% (getting high)"
else
    error "Disk usage: ${DISK_USAGE}% (critical)"
fi

# Check 9: Storage directory permissions
echo "Checking storage permissions..."
STORAGE_DIRS=("$PROJECT_ROOT/storage/app" "$PROJECT_ROOT/storage/framework" "$PROJECT_ROOT/storage/logs" "$PROJECT_ROOT/bootstrap/cache")

for dir in "${STORAGE_DIRS[@]}"; do
    if [ -d "$dir" ] && [ -w "$dir" ]; then
        success "Writable: $dir"
    else
        error "Not writable: $dir"
    fi
done

# Check 10: Git repository status
echo "Checking Git status..."
cd "$PROJECT_ROOT"
if [ -d .git ]; then
    if [ -z "$(git status --porcelain)" ]; then
        success "Working directory clean"
    else
        warning "Working directory has uncommitted changes"
    fi

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    success "Current branch: $CURRENT_BRANCH"
else
    warning "Not a Git repository"
fi

# Check 11: Backup directory exists
echo "Checking backup configuration..."
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/storage/app/backups}"
if [ -d "$BACKUP_DIR" ] && [ -w "$BACKUP_DIR" ]; then
    success "Backup directory exists and writable"
else
    warning "Backup directory not configured or not writable"
fi

# Check 12: Queue workers
echo "Checking queue workers..."
if pgrep -f "artisan queue:work" > /dev/null; then
    success "Queue workers running"
else
    warning "No queue workers found"
fi

# Check 13: SSL Certificates (if applicable)
echo "Checking SSL certificates..."
if [ -n "${SSL_CERT_PATH:-}" ] && [ -f "$SSL_CERT_PATH" ]; then
    CERT_EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_CERT_PATH" | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

    if [ "$DAYS_UNTIL_EXPIRY" -gt 30 ]; then
        success "SSL certificate valid for $DAYS_UNTIL_EXPIRY days"
    elif [ "$DAYS_UNTIL_EXPIRY" -gt 0 ]; then
        warning "SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
    else
        error "SSL certificate expired"
    fi
else
    warning "SSL certificate path not configured"
fi

# Summary
echo ""
echo "========================================="
echo "  CHECK SUMMARY"
echo "========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo -e "${RED}Failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    exit 1
fi
