#!/bin/bash

################################################################################
# CHOM Test User Setup Script
#
# This script creates test users, organizations, and tenants for development
# and testing purposes.
#
# Usage:
#   ./scripts/create-test-users.sh
#
# Environment:
#   - Development or testing environment only
#   - Database must be migrated
#   - Laravel must be configured
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

################################################################################
# Helper Functions
################################################################################

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

################################################################################
# Pre-flight Checks
################################################################################

log_info "Starting CHOM test user setup..."

# Check if we're in the project root
if [ ! -f "$PROJECT_ROOT/artisan" ]; then
    log_error "artisan file not found. Please run this script from the project root."
    exit 1
fi

cd "$PROJECT_ROOT"

# Check environment
APP_ENV=$(php artisan tinker --execute="echo config('app.env');" 2>/dev/null | tail -n 1)
if [[ "$APP_ENV" == "production" ]]; then
    log_error "This script cannot be run in production!"
    exit 1
fi

log_success "Environment check passed (Environment: $APP_ENV)"

################################################################################
# Create Test Users
################################################################################

log_info "Creating test users via PHP artisan tinker..."

php artisan tinker <<'EOF'
use App\Models\User;
use App\Models\Organization;
use App\Models\Tenant;
use Illuminate\Support\Facades\Hash;

echo "\n=== Creating Super Admin ===\n";

// Create Super Admin
$superAdmin = User::firstOrCreate(
    ['email' => 'admin@chom.test'],
    [
        'name' => 'Super Admin',
        'password' => Hash::make('password'),
        'is_super_admin' => true,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

echo "✓ Super Admin created: admin@chom.test / password\n";

// ============================================================================
// Starter Organization
// ============================================================================

echo "\n=== Creating Starter Organization ===\n";

$starterOrg = Organization::firstOrCreate(
    ['name' => 'Starter Organization'],
    [
        'is_approved' => true,
        'settings' => json_encode([]),
    ]
);

$starterOwner = User::firstOrCreate(
    ['email' => 'starter@chom.test'],
    [
        'name' => 'Starter Owner',
        'password' => Hash::make('password'),
        'is_super_admin' => false,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

// Attach user to organization
if (!$starterOrg->users()->where('user_id', $starterOwner->id)->exists()) {
    $starterOrg->users()->attach($starterOwner->id, ['role' => 'owner']);
}

// Create tenant for starter org
$starterTenant = Tenant::firstOrCreate(
    [
        'organization_id' => $starterOrg->id,
        'name' => 'Starter Tenant'
    ],
    [
        'is_approved' => true,
        'settings' => json_encode([]),
    ]
);

echo "✓ Starter Organization created\n";
echo "  - Organization: Starter Organization\n";
echo "  - Owner: starter@chom.test / password\n";
echo "  - Tenant: Starter Tenant\n";

// ============================================================================
// Pro Organization
// ============================================================================

echo "\n=== Creating Pro Organization ===\n";

$proOrg = Organization::firstOrCreate(
    ['name' => 'Pro Organization'],
    [
        'is_approved' => true,
        'settings' => json_encode([]),
    ]
);

$proOwner = User::firstOrCreate(
    ['email' => 'pro@chom.test'],
    [
        'name' => 'Pro Owner',
        'password' => Hash::make('password'),
        'is_super_admin' => false,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

if (!$proOrg->users()->where('user_id', $proOwner->id)->exists()) {
    $proOrg->users()->attach($proOwner->id, ['role' => 'owner']);
}

$proTenant = Tenant::firstOrCreate(
    [
        'organization_id' => $proOrg->id,
        'name' => 'Pro Tenant'
    ],
    [
        'is_approved' => true,
        'settings' => json_encode([]),
    ]
);

echo "✓ Pro Organization created\n";
echo "  - Organization: Pro Organization\n";
echo "  - Owner: pro@chom.test / password\n";
echo "  - Tenant: Pro Tenant\n";

// ============================================================================
// Enterprise Organization
// ============================================================================

echo "\n=== Creating Enterprise Organization ===\n";

$enterpriseOrg = Organization::firstOrCreate(
    ['name' => 'Enterprise Organization'],
    [
        'is_approved' => true,
        'settings' => json_encode([]),
    ]
);

$enterpriseOwner = User::firstOrCreate(
    ['email' => 'enterprise@chom.test'],
    [
        'name' => 'Enterprise Owner',
        'password' => Hash::make('password'),
        'is_super_admin' => false,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

if (!$enterpriseOrg->users()->where('user_id', $enterpriseOwner->id)->exists()) {
    $enterpriseOrg->users()->attach($enterpriseOwner->id, ['role' => 'owner']);
}

$enterpriseTenant = Tenant::firstOrCreate(
    [
        'organization_id' => $enterpriseOrg->id,
        'name' => 'Enterprise Tenant'
    ],
    [
        'is_approved' => true,
        'settings' => json_encode([]),
    ]
);

echo "✓ Enterprise Organization created\n";
echo "  - Organization: Enterprise Organization\n";
echo "  - Owner: enterprise@chom.test / password\n";
echo "  - Tenant: Enterprise Tenant\n";

// ============================================================================
// Team Members
// ============================================================================

echo "\n=== Creating Team Members ===\n";

// Admin member
$adminMember = User::firstOrCreate(
    ['email' => 'admin-member@chom.test'],
    [
        'name' => 'Admin Member',
        'password' => Hash::make('password'),
        'is_super_admin' => false,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

if (!$starterOrg->users()->where('user_id', $adminMember->id)->exists()) {
    $starterOrg->users()->attach($adminMember->id, ['role' => 'admin']);
}

echo "✓ Admin Member: admin-member@chom.test / password (Role: Admin)\n";

// Regular member
$member = User::firstOrCreate(
    ['email' => 'member@chom.test'],
    [
        'name' => 'Regular Member',
        'password' => Hash::make('password'),
        'is_super_admin' => false,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

if (!$starterOrg->users()->where('user_id', $member->id)->exists()) {
    $starterOrg->users()->attach($member->id, ['role' => 'member']);
}

echo "✓ Regular Member: member@chom.test / password (Role: Member)\n";

// Viewer
$viewer = User::firstOrCreate(
    ['email' => 'viewer@chom.test'],
    [
        'name' => 'Viewer User',
        'password' => Hash::make('password'),
        'is_super_admin' => false,
        'email_verified_at' => now(),
        'must_reset_password' => false,
        'settings' => json_encode([]),
    ]
);

if (!$starterOrg->users()->where('user_id', $viewer->id)->exists()) {
    $starterOrg->users()->attach($viewer->id, ['role' => 'viewer']);
}

echo "✓ Viewer: viewer@chom.test / password (Role: Viewer)\n";

// ============================================================================
// Summary
// ============================================================================

echo "\n=== Test User Setup Complete ===\n";
echo "\nCreated Users:\n";
echo "  1. Super Admin:     admin@chom.test / password\n";
echo "  2. Starter Owner:   starter@chom.test / password\n";
echo "  3. Pro Owner:       pro@chom.test / password\n";
echo "  4. Enterprise Owner: enterprise@chom.test / password\n";
echo "  5. Admin Member:    admin-member@chom.test / password\n";
echo "  6. Regular Member:  member@chom.test / password\n";
echo "  7. Viewer:          viewer@chom.test / password\n";

echo "\nCreated Organizations:\n";
echo "  1. Starter Organization (starter@chom.test)\n";
echo "  2. Pro Organization (pro@chom.test)\n";
echo "  3. Enterprise Organization (enterprise@chom.test)\n";

echo "\nAll users have password: 'password'\n";
echo "\n";

EOF

################################################################################
# Completion
################################################################################

log_success "Test user setup complete!"
log_info "You can now log in with any of the test accounts."
log_warning "Remember: These are TEST accounts. Never use in production!"

echo ""
echo "Quick Start:"
echo "  1. Start development server: php artisan serve"
echo "  2. Visit: http://localhost:8000"
echo "  3. Login with: admin@chom.test / password"
echo ""
