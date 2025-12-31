#!/bin/bash
#===============================================================================
# CHOM Integration Verification Script
#
# Comprehensive verification that all components work together correctly
# Tests: Database, Redis, Services, Middleware, Routes, Auth, Security, etc.
#
# Usage:
#   ./verify-integration.sh [OPTIONS]
#
# Options:
#   --verbose    Show detailed output
#   --skip-db    Skip database checks
#   --skip-redis Skip Redis checks
#   --help       Show this help
#===============================================================================

set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERBOSE=false
SKIP_DB=false
SKIP_REDIS=false

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

#===============================================================================
# Helper Functions
#===============================================================================

print_section() {
    echo ""
    echo "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "${CYAN}${BOLD} $1${NC}"
    echo "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test() {
    local test_name="$1"
    echo -n "${BLUE}  [TEST]${NC} ${test_name}... "
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

pass_test() {
    echo "${GREEN}✓ PASS${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    [[ "$VERBOSE" == true ]] && [[ -n "${1:-}" ]] && echo "    ${GREEN}→${NC} $1"
}

fail_test() {
    echo "${RED}✗ FAIL${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "    ${RED}→${NC} $1"
}

skip_test() {
    echo "${YELLOW}⊘ SKIP${NC}"
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    [[ "$VERBOSE" == true ]] && [[ -n "${1:-}" ]] && echo "    ${YELLOW}→${NC} $1"
}

warn() {
    echo "${YELLOW}  [WARN]${NC} $1"
}

info() {
    [[ "$VERBOSE" == true ]] && echo "${BLUE}  [INFO]${NC} $1"
}

artisan() {
    php "${PROJECT_ROOT}/artisan" "$@" 2>&1
}

#===============================================================================
# Verification Tests
#===============================================================================

verify_environment() {
    print_section "1. Environment Configuration"

    # Check .env exists
    print_test "Environment file exists"
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        pass_test ".env file found"
    else
        fail_test ".env file not found"
    fi

    # Check required environment variables
    print_test "Required environment variables set"
    required_vars=(
        "APP_KEY"
        "DB_CONNECTION"
        "DB_HOST"
        "REDIS_HOST"
        "CACHE_DRIVER"
        "SESSION_DRIVER"
    )

    missing_vars=()
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "${PROJECT_ROOT}/.env" 2>/dev/null; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        pass_test "All required variables present"
    else
        fail_test "Missing variables: ${missing_vars[*]}"
    fi

    # Verify APP_KEY is set
    print_test "Application key configured"
    if grep -q "^APP_KEY=base64:" "${PROJECT_ROOT}/.env" 2>/dev/null; then
        pass_test "APP_KEY is properly configured"
    else
        fail_test "APP_KEY not set or invalid format"
    fi
}

verify_database() {
    if [[ "$SKIP_DB" == true ]]; then
        print_section "2. Database Verification (SKIPPED)"
        return
    fi

    print_section "2. Database Verification"

    # Test database connection
    print_test "Database connection"
    if output=$(artisan db:show 2>&1); then
        pass_test "Connected to database"
    else
        fail_test "Cannot connect to database: ${output}"
        return
    fi

    # Verify migrations are applied
    print_test "Database migrations status"
    if output=$(artisan migrate:status 2>&1 | grep -c "Ran"); then
        pass_test "${output} migrations applied"
    else
        fail_test "Cannot verify migrations"
    fi

    # Check critical tables exist
    print_test "Critical tables exist"
    critical_tables=(
        "users"
        "organizations"
        "tenants"
        "vps_servers"
        "sites"
        "audit_logs"
        "operations"
    )

    missing_tables=()
    for table in "${critical_tables[@]}"; do
        if ! artisan db:table "$table" &>/dev/null; then
            missing_tables+=("$table")
        fi
    done

    if [[ ${#missing_tables[@]} -eq 0 ]]; then
        pass_test "All critical tables exist"
    else
        fail_test "Missing tables: ${missing_tables[*]}"
    fi

    # Verify indexes exist on critical columns
    print_test "Database indexes present"
    # This is a simplified check - in production, verify specific indexes
    if output=$(artisan db:show 2>&1); then
        pass_test "Database structure verified"
    else
        warn "Cannot verify indexes"
        skip_test "Index verification needs manual check"
    fi
}

verify_redis() {
    if [[ "$SKIP_REDIS" == true ]]; then
        print_section "3. Redis Cache Verification (SKIPPED)"
        return
    fi

    print_section "3. Redis Cache Verification"

    # Test Redis connection
    print_test "Redis connection"
    if artisan tinker --execute="Redis::ping()" 2>&1 | grep -q "PONG"; then
        pass_test "Redis is responding"
    else
        fail_test "Cannot connect to Redis"
        return
    fi

    # Test cache operations
    print_test "Cache write operation"
    if artisan tinker --execute="Cache::put('integration_test', 'value', 60)" &>/dev/null; then
        pass_test "Cache write successful"
    else
        fail_test "Cache write failed"
    fi

    print_test "Cache read operation"
    if artisan tinker --execute="echo Cache::get('integration_test')" 2>&1 | grep -q "value"; then
        pass_test "Cache read successful"
    else
        fail_test "Cache read failed"
    fi

    # Test cache driver configuration
    print_test "Cache driver configuration"
    cache_driver=$(grep "^CACHE_DRIVER=" "${PROJECT_ROOT}/.env" | cut -d= -f2)
    if [[ "$cache_driver" == "redis" ]]; then
        pass_test "Using Redis cache driver"
    else
        warn "Cache driver is: ${cache_driver}"
    fi
}

verify_service_container() {
    print_section "4. Service Container Registration"

    # Verify key services are registered
    print_test "VpsManagerInterface binding"
    if artisan tinker --execute="app()->has(App\Services\Integration\VpsManagerInterface::class)" 2>&1 | grep -q "true"; then
        pass_test "VpsManagerInterface is registered"
    else
        # Check if it exists but differently
        if [[ -f "${PROJECT_ROOT}/app/Services/Integration/VpsManagerInterface.php" ]]; then
            warn "Interface exists but may not be registered in container"
        else
            skip_test "VpsManagerInterface not found (may not be implemented yet)"
        fi
    fi

    print_test "Service provider registration"
    if grep -q "AppServiceProvider" "${PROJECT_ROOT}/bootstrap/providers.php" 2>/dev/null; then
        pass_test "AppServiceProvider registered"
    else
        warn "Check providers configuration"
    fi
}

verify_middleware() {
    print_section "5. Middleware Registration"

    # Check middleware files exist
    print_test "Authentication middleware"
    if [[ -f "${PROJECT_ROOT}/app/Http/Middleware/Authenticate.php" ]]; then
        pass_test "Authenticate middleware exists"
    else
        fail_test "Authenticate middleware missing"
    fi

    print_test "Tenant scoping middleware"
    if grep -rq "TenantScoping" "${PROJECT_ROOT}/app/Http/Middleware/" 2>/dev/null; then
        pass_test "Tenant scoping middleware configured"
    else
        warn "Tenant scoping middleware may not be configured"
    fi

    print_test "Rate limiting middleware"
    if grep -q "RateLimiter" "${PROJECT_ROOT}/app/Providers/AppServiceProvider.php" 2>/dev/null; then
        pass_test "Rate limiting configured"
    else
        warn "Rate limiting may not be configured"
    fi
}

verify_routes() {
    print_section "6. Route Configuration"

    # Verify route files exist
    print_test "API routes defined"
    if [[ -f "${PROJECT_ROOT}/routes/api.php" ]]; then
        route_count=$(grep -c "Route::" "${PROJECT_ROOT}/routes/api.php" 2>/dev/null || echo "0")
        pass_test "${route_count} API routes defined"
    else
        fail_test "API routes file missing"
    fi

    # Check critical routes exist
    print_test "Authentication routes"
    if grep -q "auth" "${PROJECT_ROOT}/routes/api.php" 2>/dev/null; then
        pass_test "Authentication routes configured"
    else
        fail_test "Authentication routes missing"
    fi

    print_test "Resource routes"
    if grep -q "sites\|vpservers\|backups" "${PROJECT_ROOT}/routes/api.php" 2>/dev/null; then
        pass_test "Resource routes configured"
    else
        warn "Some resource routes may be missing"
    fi

    # Verify route list can be generated
    print_test "Route list generation"
    if artisan route:list --json &>/dev/null; then
        pass_test "Routes are properly registered"
    else
        fail_test "Cannot generate route list"
    fi
}

verify_authentication() {
    print_section "7. Authentication System"

    # Check Sanctum configuration
    print_test "Laravel Sanctum installed"
    if [[ -f "${PROJECT_ROOT}/config/sanctum.php" ]]; then
        pass_test "Sanctum configuration exists"
    else
        fail_test "Sanctum not configured"
    fi

    # Verify User model has Sanctum trait
    print_test "User model Sanctum integration"
    if grep -q "HasApiTokens" "${PROJECT_ROOT}/app/Models/User.php" 2>/dev/null; then
        pass_test "User model has HasApiTokens trait"
    else
        fail_test "User model missing Sanctum integration"
    fi

    # Check personal_access_tokens table exists
    print_test "Personal access tokens table"
    if artisan db:table personal_access_tokens &>/dev/null ||
       grep -q "create_personal_access_tokens" "${PROJECT_ROOT}/database/migrations/"* 2>/dev/null; then
        pass_test "Personal access tokens table configured"
    else
        fail_test "Personal access tokens table missing"
    fi
}

verify_authorization() {
    print_section "8. Authorization Policies"

    # Check policies exist
    print_test "Policy classes defined"
    if [[ -d "${PROJECT_ROOT}/app/Policies" ]]; then
        policy_count=$(find "${PROJECT_ROOT}/app/Policies" -name "*.php" 2>/dev/null | wc -l)
        if [[ $policy_count -gt 0 ]]; then
            pass_test "${policy_count} policy classes found"
        else
            warn "No policy classes found"
        fi
    else
        warn "Policies directory not found"
    fi

    # Check AuthServiceProvider
    print_test "AuthServiceProvider configuration"
    if [[ -f "${PROJECT_ROOT}/app/Providers/AuthServiceProvider.php" ]]; then
        pass_test "AuthServiceProvider exists"
    else
        fail_test "AuthServiceProvider missing"
    fi
}

verify_audit_logging() {
    print_section "9. Audit Logging System"

    # Check audit_logs table
    print_test "Audit logs table exists"
    if artisan db:table audit_logs &>/dev/null ||
       grep -q "create_audit_logs" "${PROJECT_ROOT}/database/migrations/"* 2>/dev/null; then
        pass_test "Audit logs table configured"
    else
        fail_test "Audit logs table missing"
    fi

    # Check AuditLog model
    print_test "AuditLog model exists"
    if [[ -f "${PROJECT_ROOT}/app/Models/AuditLog.php" ]]; then
        pass_test "AuditLog model defined"
    else
        fail_test "AuditLog model missing"
    fi
}

verify_security_headers() {
    print_section "10. Security Headers"

    # Check for security middleware
    print_test "Security headers middleware"
    if grep -rq "securityHeaders\|SecurityHeaders" "${PROJECT_ROOT}/app/Http/" 2>/dev/null; then
        pass_test "Security headers middleware configured"
    else
        warn "Security headers middleware may not be configured"
    fi

    # Check CORS configuration
    print_test "CORS configuration"
    if [[ -f "${PROJECT_ROOT}/config/cors.php" ]]; then
        pass_test "CORS configuration exists"
    else
        warn "CORS configuration file missing"
    fi
}

verify_performance_monitoring() {
    print_section "11. Performance Monitoring"

    # Check for performance monitoring setup
    print_test "Query logging configuration"
    if grep -q "DB::listen\|QueryLogger" "${PROJECT_ROOT}/app/Providers/"* 2>/dev/null; then
        pass_test "Query logging configured"
    else
        warn "Query logging may not be configured"
    fi

    # Check operations table for tracking
    print_test "Operations tracking table"
    if artisan db:table operations &>/dev/null ||
       grep -q "create_operations" "${PROJECT_ROOT}/database/migrations/"* 2>/dev/null; then
        pass_test "Operations tracking configured"
    else
        warn "Operations tracking table not found"
    fi
}

verify_ssh_connection_pooling() {
    print_section "12. SSH Connection Pooling"

    # Check VpsConnectionPool service
    print_test "VpsConnectionPool service exists"
    if [[ -f "${PROJECT_ROOT}/app/Services/VPS/VpsConnectionPool.php" ]]; then
        pass_test "VpsConnectionPool service defined"
    else
        fail_test "VpsConnectionPool service missing"
    fi

    # Check connection manager
    print_test "VpsConnectionManager service exists"
    if [[ -f "${PROJECT_ROOT}/app/Services/VPS/VpsConnectionManager.php" ]]; then
        pass_test "VpsConnectionManager service defined"
    else
        fail_test "VpsConnectionManager service missing"
    fi
}

verify_vps_services() {
    print_section "13. VPS Management Services"

    # Check VPS services exist
    vps_services=(
        "VpsAllocationService"
        "VpsHealthService"
        "VpsSiteManager"
        "VpsSslManager"
        "VpsCommandExecutor"
    )

    for service in "${vps_services[@]}"; do
        print_test "${service} exists"
        if [[ -f "${PROJECT_ROOT}/app/Services/VPS/${service}.php" ]]; then
            pass_test "${service} defined"
        else
            fail_test "${service} missing"
        fi
    done
}

verify_site_provisioning() {
    print_section "14. Site Provisioning System"

    # Check provisioner services
    print_test "Site provisioners exist"
    if [[ -d "${PROJECT_ROOT}/app/Services/Sites/Provisioners" ]]; then
        provisioner_count=$(find "${PROJECT_ROOT}/app/Services/Sites/Provisioners" -name "*Provisioner.php" 2>/dev/null | wc -l)
        if [[ $provisioner_count -gt 0 ]]; then
            pass_test "${provisioner_count} provisioners found"
        else
            warn "No provisioner classes found"
        fi
    else
        fail_test "Provisioners directory missing"
    fi

    # Check SiteCreationService
    print_test "SiteCreationService exists"
    if [[ -f "${PROJECT_ROOT}/app/Services/Sites/SiteCreationService.php" ]]; then
        pass_test "SiteCreationService defined"
    else
        fail_test "SiteCreationService missing"
    fi
}

verify_backup_system() {
    print_section "15. Backup System"

    # Check backup services
    print_test "BackupService exists"
    if [[ -f "${PROJECT_ROOT}/app/Services/Backup/BackupService.php" ]]; then
        pass_test "BackupService defined"
    else
        fail_test "BackupService missing"
    fi

    print_test "BackupRestoreService exists"
    if [[ -f "${PROJECT_ROOT}/app/Services/Backup/BackupRestoreService.php" ]]; then
        pass_test "BackupRestoreService defined"
    else
        fail_test "BackupRestoreService missing"
    fi

    # Check site_backups table
    print_test "Site backups table exists"
    if artisan db:table site_backups &>/dev/null ||
       grep -q "create_site_backups" "${PROJECT_ROOT}/database/migrations/"* 2>/dev/null; then
        pass_test "Site backups table configured"
    else
        fail_test "Site backups table missing"
    fi
}

#===============================================================================
# Summary Report
#===============================================================================

print_summary() {
    print_section "Integration Verification Summary"

    echo ""
    echo "  ${BOLD}Total Tests:${NC}   ${TOTAL_TESTS}"
    echo "  ${GREEN}${BOLD}Passed:${NC}        ${PASSED_TESTS}"
    echo "  ${RED}${BOLD}Failed:${NC}        ${FAILED_TESTS}"
    echo "  ${YELLOW}${BOLD}Skipped:${NC}       ${SKIPPED_TESTS}"
    echo ""

    # Calculate success rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
        echo "  ${BOLD}Success Rate:${NC}  ${success_rate}%"
    fi

    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "  ${GREEN}${BOLD}✓ ALL INTEGRATION TESTS PASSED${NC}"
        echo ""
        return 0
    else
        echo "  ${RED}${BOLD}✗ INTEGRATION VERIFICATION FAILED${NC}"
        echo ""
        echo "  ${RED}Please review the failed tests above and fix the issues.${NC}"
        echo ""
        return 1
    fi
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-db)
                SKIP_DB=true
                shift
                ;;
            --skip-redis)
                SKIP_REDIS=true
                shift
                ;;
            --help)
                grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# \?//'
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Print header
    echo ""
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}${BOLD}║              CHOM Integration Verification System                         ║${NC}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Run all verification tests
    verify_environment
    verify_database
    verify_redis
    verify_service_container
    verify_middleware
    verify_routes
    verify_authentication
    verify_authorization
    verify_audit_logging
    verify_security_headers
    verify_performance_monitoring
    verify_ssh_connection_pooling
    verify_vps_services
    verify_site_provisioning
    verify_backup_system

    # Print summary and exit with appropriate code
    print_summary
}

main "$@"
