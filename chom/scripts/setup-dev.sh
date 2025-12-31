#!/bin/bash
# CHOM Development Environment Setup Script
# This script sets up a complete local development environment in one command
set -e

PROJECT_ROOT="/home/calounx/repositories/mentat/chom"
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CHOM Development Environment Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print status messages
print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

command -v php >/dev/null 2>&1 || { print_error "PHP is required but not installed. Aborting."; exit 1; }
command -v composer >/dev/null 2>&1 || { print_error "Composer is required but not installed. Aborting."; exit 1; }
command -v node >/dev/null 2>&1 || { print_error "Node.js is required but not installed. Aborting."; exit 1; }
command -v docker >/dev/null 2>&1 || { print_warning "Docker not found. Will use local Redis/MySQL if available."; }

PHP_VERSION=$(php -r "echo PHP_VERSION;" | cut -d. -f1,2)
if (( $(echo "$PHP_VERSION < 8.2" | bc -l) )); then
    print_error "PHP 8.2 or higher is required (found $PHP_VERSION)"
    exit 1
fi

print_success "Prerequisites check passed"
echo ""

# Install PHP dependencies
print_status "Installing PHP dependencies via Composer..."
composer install --no-interaction --prefer-dist
print_success "Composer dependencies installed"
echo ""

# Install Node dependencies
print_status "Installing Node.js dependencies..."
npm install
print_success "Node.js dependencies installed"
echo ""

# Setup environment file
print_status "Setting up environment configuration..."
if [ ! -f .env ]; then
    cp .env.example .env
    print_success "Created .env file from .env.example"
else
    print_warning ".env file already exists, skipping..."
fi
echo ""

# Generate application key
print_status "Generating application key..."
php artisan key:generate --force
print_success "Application key generated"
echo ""

# Start Docker services if available
if command -v docker >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then
    print_status "Starting Docker services (Redis, MySQL)..."
    docker-compose up -d 2>/dev/null || print_warning "Could not start Docker services. Using local services."

    if docker ps | grep -q chom-redis; then
        print_success "Docker services started"
        print_status "Waiting for services to be ready..."
        sleep 5
    fi
else
    print_warning "Docker not available. Ensure Redis and MySQL are running locally."
fi
echo ""

# Setup database
print_status "Setting up database..."
if [ ! -f database/database.sqlite ]; then
    touch database/database.sqlite
    print_success "Created SQLite database"
fi

# Run migrations
print_status "Running database migrations..."
php artisan migrate:fresh --force
print_success "Database migrations completed"
echo ""

# Run seeders
print_status "Seeding database with test data..."
php artisan db:seed --class=DatabaseSeeder --force
if php artisan db:seed --class=TestUserSeeder --force 2>/dev/null; then
    print_success "Test users created"
else
    print_warning "TestUserSeeder not found (will be created later)"
fi
if php artisan db:seed --class=TestDataSeeder --force 2>/dev/null; then
    print_success "Test data seeded"
else
    print_warning "TestDataSeeder not found (will be created later)"
fi
echo ""

# Clear caches
print_status "Clearing application caches..."
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
print_success "Caches cleared"
echo ""

# Build frontend assets
print_status "Building frontend assets..."
npm run build
print_success "Frontend assets built"
echo ""

# Run tests to verify setup
print_status "Running tests to verify setup..."
if php artisan test --stop-on-failure; then
    print_success "All tests passed"
else
    print_warning "Some tests failed. Check output above."
fi
echo ""

# Generate IDE helper files if available
if composer show --installed | grep -q barryvdh/laravel-ide-helper; then
    print_status "Generating IDE helper files..."
    php artisan ide-helper:generate 2>/dev/null || true
    php artisan ide-helper:models -N 2>/dev/null || true
    php artisan ide-helper:meta 2>/dev/null || true
    print_success "IDE helper files generated"
    echo ""
fi

# Display summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo -e "1. Start the development server:"
echo -e "   ${YELLOW}composer run dev${NC}"
echo -e "   OR run services individually:"
echo -e "   ${YELLOW}php artisan serve${NC}"
echo -e "   ${YELLOW}npm run dev${NC}"
echo -e "   ${YELLOW}php artisan queue:listen${NC}"
echo ""
echo -e "2. Access the application:"
echo -e "   ${GREEN}http://localhost:8000${NC}"
echo ""
echo -e "3. Test user credentials (if TestUserSeeder exists):"
echo -e "   Admin:  ${YELLOW}admin@chom.test / password${NC}"
echo -e "   Owner:  ${YELLOW}owner@chom.test / password${NC}"
echo -e "   Member: ${YELLOW}member@chom.test / password${NC}"
echo -e "   Viewer: ${YELLOW}viewer@chom.test / password${NC}"
echo ""
echo -e "4. Useful commands:"
echo -e "   Run tests:           ${YELLOW}composer test${NC}"
echo -e "   Clear caches:        ${YELLOW}php artisan optimize:clear${NC}"
echo -e "   Run migrations:      ${YELLOW}php artisan migrate${NC}"
echo -e "   Tinker (REPL):       ${YELLOW}php artisan tinker${NC}"
echo -e "   Queue dashboard:     ${YELLOW}php artisan queue:monitor${NC}"
echo ""
echo -e "5. Documentation:"
echo -e "   Onboarding:          ${YELLOW}cat ONBOARDING.md${NC}"
echo -e "   Development:         ${YELLOW}cat DEVELOPMENT.md${NC}"
echo -e "   Contributing:        ${YELLOW}cat CONTRIBUTING.md${NC}"
echo -e "   Testing:             ${YELLOW}cat TESTING.md${NC}"
echo ""
echo -e "${BLUE}Happy coding!${NC}"
