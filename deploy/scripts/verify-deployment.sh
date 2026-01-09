#!/usr/bin/env bash
# Verify deployment health - comprehensive post-deployment checks
# Prevents P0, P1, and P2 issues identified in regression testing
# Usage: ./verify-deployment.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source utilities
source "${DEPLOY_ROOT}/utils/logging.sh"
source "${DEPLOY_ROOT}/utils/colors.sh"

# Configuration
APP_DOMAIN="${APP_DOMAIN:-chom.arewel.com}"
APP_DIR="${APP_DIR:-/var/www/chom}"

# Exit codes
EXIT_SUCCESS=0
EXIT_FAILURE=1
EXIT_WARNINGS=2

# Track verification results
FAILED_CHECKS=0
WARNING_CHECKS=0
PASSED_CHECKS=0

# Verify VPSManager functionality (P0/P1 fix)
verify_vpsmanager() {
    log_step "Verifying VPSManager"

    # Check if VPSManager is installed
    if ! command -v vpsmanager &>/dev/null; then
        log_error "VPSManager command not found"
        ((FAILED_CHECKS++))
        return 1
    fi

    # Check if VPSManager binary is executable
    if [[ ! -x /usr/local/bin/vpsmanager ]] && [[ ! -x /opt/vpsmanager/bin/vpsmanager ]]; then
        log_error "VPSManager binary not executable"
        ((FAILED_CHECKS++))
        return 1
    fi

    # Test site:create command
    log_info "Testing site:create command"
    local test_domain="verify-$(date +%s).local"
    if sudo /usr/local/bin/vpsmanager site:create "$test_domain" --type=html >/dev/null 2>&1; then
        log_success "site:create works"
    else
        log_error "site:create failed"
        ((FAILED_CHECKS++))
        return 1
    fi

    # Test site:info command
    log_info "Testing site:info command"
    if sudo /usr/local/bin/vpsmanager site:info "$test_domain" >/dev/null 2>&1; then
        log_success "site:info works"
    else
        log_error "site:info failed"
        ((FAILED_CHECKS++))
        sudo /usr/local/bin/vpsmanager site:delete "$test_domain" 2>/dev/null || true
        return 1
    fi

    # Test site:delete command
    log_info "Testing site:delete command"
    if sudo /usr/local/bin/vpsmanager site:delete "$test_domain" >/dev/null 2>&1; then
        log_success "site:delete works"
    else
        log_error "site:delete failed"
        ((FAILED_CHECKS++))
        return 1
    fi

    log_success "VPSManager verification passed"
    ((PASSED_CHECKS++))
    return 0
}

# Verify health endpoint (P2 fix)
verify_health_endpoint() {
    log_step "Verifying health endpoint"

    # Test HTTP endpoint
    local health_url="https://${APP_DOMAIN}/health"
    if curl -sf "$health_url" >/dev/null 2>&1; then
        log_success "Health endpoint responding at $health_url"
        ((PASSED_CHECKS++))
        return 0
    fi

    # Try alternate health endpoint
    health_url="https://${APP_DOMAIN}/api/health"
    if curl -sf "$health_url" >/dev/null 2>&1; then
        log_success "Health endpoint responding at $health_url"
        ((PASSED_CHECKS++))
        return 0
    fi

    log_error "Health endpoint not responding at https://${APP_DOMAIN}/health or /api/health"
    ((FAILED_CHECKS++))
    return 1
}

# Verify password reset functionality (P1 fix)
verify_password_reset() {
    log_step "Verifying password reset functionality"

    # Check if forgot-password page is accessible
    local reset_url="https://${APP_DOMAIN}/forgot-password"
    if curl -sf "$reset_url" >/dev/null 2>&1; then
        log_success "Password reset page accessible at $reset_url"
    else
        log_warning "Password reset page not accessible at $reset_url (may be route name issue)"
        ((WARNING_CHECKS++))
    fi

    # Verify routes exist via artisan (more reliable than HTTP)
    if [[ -d "${APP_DIR}/current" ]]; then
        cd "${APP_DIR}/current"
        if php artisan route:list --path=password 2>/dev/null | grep -q "password.request"; then
            log_success "Password reset routes registered"
            ((PASSED_CHECKS++))
            return 0
        else
            log_error "Password reset routes not found in route list"
            ((FAILED_CHECKS++))
            return 1
        fi
    else
        log_error "Application directory not found: ${APP_DIR}/current"
        ((FAILED_CHECKS++))
        return 1
    fi
}

# Verify PostgreSQL exporter (P2 fix)
verify_postgres_exporter() {
    log_step "Verifying PostgreSQL exporter"

    # Check if postgres_exporter service is running
    if ! systemctl is-active --quiet postgres_exporter 2>/dev/null; then
        log_warning "postgres_exporter service not running"
        ((WARNING_CHECKS++))
        return 0
    fi

    # Check if exporter is responding
    if ! curl -s http://localhost:9187/metrics >/dev/null 2>&1; then
        log_error "postgres_exporter not responding on port 9187"
        ((FAILED_CHECKS++))
        return 1
    fi

    # Check if exporter has valid metrics (pg_up should be 1)
    if curl -s http://localhost:9187/metrics | grep -q "pg_up 1"; then
        log_success "PostgreSQL exporter working (pg_up=1)"
        ((PASSED_CHECKS++))
        return 0
    else
        log_error "PostgreSQL exporter authentication failed (pg_up!=1)"
        log_info "Check /etc/exporters/postgres_exporter.env for credentials"
        ((FAILED_CHECKS++))
        return 1
    fi
}

# Verify application is accessible
verify_application() {
    log_step "Verifying application accessibility"

    # Test main application URL
    if curl -sf "https://${APP_DOMAIN}" >/dev/null 2>&1; then
        log_success "Application accessible at https://${APP_DOMAIN}"
        ((PASSED_CHECKS++))
        return 0
    else
        log_error "Application not accessible at https://${APP_DOMAIN}"
        ((FAILED_CHECKS++))
        return 1
    fi
}

# Verify database connectivity
verify_database() {
    log_step "Verifying database connectivity"

    if [[ -d "${APP_DIR}/current" ]]; then
        cd "${APP_DIR}/current"

        # Test database connection via Laravel
        if php artisan tinker --execute="DB::connection()->getPdo(); echo 'OK';" 2>/dev/null | grep -q "OK"; then
            log_success "Database connectivity verified"
            ((PASSED_CHECKS++))
            return 0
        else
            log_error "Database connection failed"
            ((FAILED_CHECKS++))
            return 1
        fi
    else
        log_warning "Cannot verify database - application directory not found"
        ((WARNING_CHECKS++))
        return 0
    fi
}

# Verify queue workers
verify_queue_workers() {
    log_step "Verifying queue workers"

    if systemctl is-active --quiet supervisor 2>/dev/null; then
        if sudo supervisorctl status chom-worker:* 2>/dev/null | grep -q "RUNNING"; then
            log_success "Queue workers running"
            ((PASSED_CHECKS++))
            return 0
        else
            log_warning "Queue workers not running"
            ((WARNING_CHECKS++))
            return 0
        fi
    else
        log_warning "Supervisor not active, cannot verify queue workers"
        ((WARNING_CHECKS++))
        return 0
    fi
}

# Verify critical services
verify_services() {
    log_step "Verifying critical services"

    local critical_services=(nginx postgresql redis-server)
    local failed_services=()

    for service in "${critical_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_success "$service is running"
        else
            log_error "$service is not running"
            failed_services+=("$service")
            ((FAILED_CHECKS++))
        fi
    done

    if [[ ${#failed_services[@]} -eq 0 ]]; then
        ((PASSED_CHECKS++))
        return 0
    else
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    log_section "Verification Summary"

    local total_checks=$((PASSED_CHECKS + FAILED_CHECKS + WARNING_CHECKS))

    log_info "Total checks: $total_checks"
    log_success "Passed: $PASSED_CHECKS"

    if [[ $WARNING_CHECKS -gt 0 ]]; then
        log_warning "Warnings: $WARNING_CHECKS"
    fi

    if [[ $FAILED_CHECKS -gt 0 ]]; then
        log_error "Failed: $FAILED_CHECKS"
    fi

    echo ""

    if [[ $FAILED_CHECKS -eq 0 ]]; then
        if [[ $WARNING_CHECKS -eq 0 ]]; then
            log_success "All deployment verifications passed"
            return $EXIT_SUCCESS
        else
            log_warning "Deployment verification completed with warnings"
            return $EXIT_WARNINGS
        fi
    else
        log_error "Deployment verification failed"
        log_info "Review failed checks above and fix issues before proceeding"
        return $EXIT_FAILURE
    fi
}

# Main execution
main() {
    print_header "Deployment Verification"
    log_info "Verifying deployment on $(hostname)"
    echo ""

    # Run all verification checks
    verify_services
    verify_application
    verify_database
    verify_health_endpoint
    verify_password_reset
    verify_vpsmanager
    verify_postgres_exporter
    verify_queue_workers

    # Print summary and exit with appropriate code
    print_summary
    local exit_code=$?

    exit $exit_code
}

main "$@"
