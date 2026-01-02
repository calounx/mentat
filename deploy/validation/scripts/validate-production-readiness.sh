#!/bin/bash

################################################################################
# CHOM Production Readiness Validation Script
################################################################################
#
# This script automates the validation of production readiness criteria.
# It performs comprehensive checks across code quality, security, performance,
# reliability, observability, operations, and compliance.
#
# Usage:
#   ./validate-production-readiness.sh [options]
#
# Options:
#   --category <name>    Run only specific category (e.g., security)
#   --report <file>      Output detailed report to file
#   --json               Output results in JSON format
#   --strict             Fail on any warning (not just errors)
#   --help               Show this help message
#
# Exit Codes:
#   0 - All validations passed (100%)
#   1 - Validations failed (< 100%)
#   2 - Script error or invalid usage
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REPORT_FILE=""
JSON_OUTPUT=false
STRICT_MODE=false
CATEGORY=""

# Validation results
declare -A CATEGORY_SCORES
declare -A CATEGORY_RESULTS
declare -A VALIDATION_ERRORS
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

################################################################################
# Utility Functions
################################################################################

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                          ║"
    echo "║           CHOM PRODUCTION READINESS VALIDATION SCRIPT                   ║"
    echo "║                                                                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}▶ $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_subsection() {
    echo -e "${BOLD}${MAGENTA}▸ $1${NC}"
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    echo -e "    ${RED}Reason: $2${NC}"
    VALIDATION_ERRORS["$1"]="$2"
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    echo -e "    ${YELLOW}Warning: $2${NC}"
    ((WARNING_CHECKS++))
    ((TOTAL_CHECKS++))

    if [ "$STRICT_MODE" = true ]; then
        VALIDATION_ERRORS["$1"]="$2"
        ((FAILED_CHECKS++))
    fi
}

check_skip() {
    echo -e "  ${CYAN}○${NC} $1 (skipped)"
}

calculate_score() {
    local category=$1
    local passed=$2
    local total=$3

    if [ "$total" -eq 0 ]; then
        CATEGORY_SCORES[$category]=100
    else
        CATEGORY_SCORES[$category]=$(( (passed * 100) / total ))
    fi
}

print_summary() {
    echo -e "\n${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                         VALIDATION SUMMARY                               ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local overall_score=0
    local category_count=0

    for category in "${!CATEGORY_SCORES[@]}"; do
        local score=${CATEGORY_SCORES[$category]}
        local status_color=$GREEN
        local status_text="PASS"

        if [ "$score" -lt 100 ]; then
            status_color=$RED
            status_text="FAIL"
        fi

        echo -e "${BOLD}$category:${NC} ${status_color}${score}%${NC} [$status_text]"
        overall_score=$((overall_score + score))
        ((category_count++))
    done

    if [ "$category_count" -gt 0 ]; then
        overall_score=$((overall_score / category_count))
    fi

    echo ""
    echo -e "${BOLD}Total Checks:${NC} $TOTAL_CHECKS"
    echo -e "${GREEN}Passed:${NC} $PASSED_CHECKS"
    echo -e "${RED}Failed:${NC} $FAILED_CHECKS"
    echo -e "${YELLOW}Warnings:${NC} $WARNING_CHECKS"
    echo ""

    local final_color=$GREEN
    local final_status="PRODUCTION READY ✓"

    if [ "$overall_score" -lt 100 ]; then
        final_color=$RED
        final_status="NOT PRODUCTION READY ✗"
    fi

    echo -e "${BOLD}${final_color}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                    OVERALL CONFIDENCE SCORE: ${overall_score}%                     ║"
    echo "║                                                                          ║"
    echo "║                        $final_status                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ "$overall_score" -lt 100 ]; then
        echo -e "${RED}${BOLD}DEPLOYMENT BLOCKED${NC}"
        echo -e "${RED}The following issues must be resolved before production deployment:${NC}\n"

        for error in "${!VALIDATION_ERRORS[@]}"; do
            echo -e "${RED}✗${NC} $error"
            echo -e "  ${VALIDATION_ERRORS[$error]}"
        done

        return 1
    fi

    return 0
}

################################################################################
# Category 1: Code Quality
################################################################################

validate_code_quality() {
    print_section "1. CODE QUALITY VALIDATION"

    local category_passed=0
    local category_total=0

    cd "$PROJECT_ROOT/chom" || exit 2

    # Test coverage
    print_subsection "Test Coverage"

    if command -v php &> /dev/null && [ -f "artisan" ]; then
        # Unit tests
        if php artisan test --testsuite=Unit --stop-on-failure &> /dev/null; then
            check_pass "Unit tests passing"
            ((category_passed++))
        else
            check_fail "Unit tests failing" "Run 'php artisan test --testsuite=Unit' to see failures"
        fi
        ((category_total++))

        # Feature tests
        if php artisan test --testsuite=Feature --stop-on-failure &> /dev/null; then
            check_pass "Feature tests passing"
            ((category_passed++))
        else
            check_fail "Feature tests failing" "Run 'php artisan test --testsuite=Feature' to see failures"
        fi
        ((category_total++))
    else
        check_skip "Tests (PHP/artisan not available)"
    fi

    # Code standards
    print_subsection "Code Standards"

    if [ -f "vendor/bin/pint" ]; then
        if ./vendor/bin/pint --test &> /dev/null; then
            check_pass "PSR-12 compliance (Pint)"
            ((category_passed++))
        else
            check_fail "PSR-12 violations found" "Run './vendor/bin/pint' to fix"
        fi
        ((category_total++))
    else
        check_skip "PSR-12 check (Pint not installed)"
    fi

    # Static analysis
    if [ -f "vendor/bin/phpstan" ]; then
        if ./vendor/bin/phpstan analyse --no-progress --error-format=raw &> /dev/null; then
            check_pass "Static analysis (PHPStan)"
            ((category_passed++))
        else
            check_fail "Static analysis errors" "Run './vendor/bin/phpstan analyse' to see errors"
        fi
        ((category_total++))
    else
        check_skip "Static analysis (PHPStan not installed)"
    fi

    # Code quality checks
    print_subsection "Code Quality"

    # Check for TODO comments
    local todo_count=$(grep -r "TODO" app/ 2>/dev/null | wc -l)
    if [ "$todo_count" -eq 0 ]; then
        check_pass "No TODO comments in production code"
        ((category_passed++))
    else
        check_warn "TODO comments found" "Found $todo_count TODO comments - should be converted to issues"
    fi
    ((category_total++))

    # Check for FIXME comments
    local fixme_count=$(grep -r "FIXME" app/ 2>/dev/null | wc -l)
    if [ "$fixme_count" -eq 0 ]; then
        check_pass "No FIXME comments in production code"
        ((category_passed++))
    else
        check_fail "FIXME comments found" "Found $fixme_count FIXME comments - must be resolved"
    fi
    ((category_total++))

    # Check for debug code
    local debug_count=$(grep -rE "(dd\(|dump\(|var_dump\()" app/ 2>/dev/null | wc -l)
    if [ "$debug_count" -eq 0 ]; then
        check_pass "No debug code in production"
        ((category_passed++))
    else
        check_fail "Debug code found" "Found $debug_count debug statements - must be removed"
    fi
    ((category_total++))

    calculate_score "Code Quality" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Code Quality"]="${category_passed}/${category_total}"
}

################################################################################
# Category 2: Security
################################################################################

validate_security() {
    print_section "2. SECURITY VALIDATION"

    local category_passed=0
    local category_total=0

    cd "$PROJECT_ROOT/chom" || exit 2

    # Dependency vulnerabilities
    print_subsection "Dependency Security"

    if command -v composer &> /dev/null; then
        local audit_output=$(composer audit --no-interaction 2>&1)
        if echo "$audit_output" | grep -q "No security vulnerability advisories found"; then
            check_pass "No known vulnerabilities (composer audit)"
            ((category_passed++))
        else
            local vuln_count=$(echo "$audit_output" | grep -c "Package:" || echo "0")
            check_fail "Security vulnerabilities found" "Found $vuln_count vulnerable packages - run 'composer audit' for details"
        fi
        ((category_total++))
    else
        check_skip "Composer audit (composer not available)"
    fi

    # Environment configuration
    print_subsection "Environment Security"

    if [ -f ".env" ]; then
        # Check APP_DEBUG
        if grep -q "APP_DEBUG=false" .env; then
            check_pass "APP_DEBUG set to false"
            ((category_passed++))
        else
            check_fail "APP_DEBUG not set to false" "Set APP_DEBUG=false in production .env"
        fi
        ((category_total++))

        # Check APP_ENV
        if grep -q "APP_ENV=production" .env; then
            check_pass "APP_ENV set to production"
            ((category_passed++))
        else
            check_warn "APP_ENV not set to production" "Should be set to 'production' for production deployment"
        fi
        ((category_total++))

        # Check APP_KEY is set
        if grep -q "APP_KEY=base64:" .env; then
            check_pass "APP_KEY is configured"
            ((category_passed++))
        else
            check_fail "APP_KEY not configured" "Run 'php artisan key:generate'"
        fi
        ((category_total++))
    else
        check_fail ".env file not found" "Create .env from .env.production.example"
        category_total=$((category_total + 3))
    fi

    # Check for secrets in git
    print_subsection "Secrets Management"

    if command -v git &> /dev/null; then
        if git log --all --full-history -- .env &> /dev/null && [ -z "$(git log --all --full-history -- .env)" ]; then
            check_pass ".env file not committed to git"
            ((category_passed++))
        else
            check_fail ".env file found in git history" "Secrets may have been exposed - rotate all secrets"
        fi
        ((category_total++))
    else
        check_skip "Git history check (git not available)"
    fi

    # Docker secrets
    print_subsection "Docker Secrets"

    if [ -f "docker/production/secrets/mysql_root_password" ]; then
        check_pass "MySQL root password secret configured"
        ((category_passed++))
    else
        check_fail "MySQL root password secret not configured" "Create docker/production/secrets/mysql_root_password"
    fi
    ((category_total++))

    if [ -f "docker/production/secrets/mysql_password" ]; then
        check_pass "MySQL app password secret configured"
        ((category_passed++))
    else
        check_fail "MySQL app password secret not configured" "Create docker/production/secrets/mysql_password"
    fi
    ((category_total++))

    calculate_score "Security" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Security"]="${category_passed}/${category_total}"
}

################################################################################
# Category 3: Performance
################################################################################

validate_performance() {
    print_section "3. PERFORMANCE VALIDATION"

    local category_passed=0
    local category_total=0

    cd "$PROJECT_ROOT/chom" || exit 2

    # Caching
    print_subsection "Caching Configuration"

    # Check if cache is configured
    if [ -f ".env" ] && grep -q "CACHE_DRIVER=redis" .env; then
        check_pass "Redis cache configured"
        ((category_passed++))
    else
        check_warn "Cache not using Redis" "Set CACHE_DRIVER=redis for optimal performance"
    fi
    ((category_total++))

    # Check if queue is configured
    if [ -f ".env" ] && grep -q "QUEUE_CONNECTION=redis" .env; then
        check_pass "Redis queue configured"
        ((category_passed++))
    else
        check_warn "Queue not using Redis" "Set QUEUE_CONNECTION=redis for optimal performance"
    fi
    ((category_total++))

    # Asset optimization
    print_subsection "Asset Optimization"

    # Check if assets are built
    if [ -d "public/build" ] && [ "$(ls -A public/build)" ]; then
        check_pass "Production assets built"
        ((category_passed++))
    else
        check_fail "Production assets not built" "Run 'npm run build' to build production assets"
    fi
    ((category_total++))

    # PHP configuration
    print_subsection "PHP Configuration"

    if command -v php &> /dev/null; then
        # Check OPcache
        if php -i 2>/dev/null | grep -q "opcache.enable => On"; then
            check_pass "OPcache enabled"
            ((category_passed++))
        else
            check_warn "OPcache not enabled" "Enable OPcache for better PHP performance"
        fi
        ((category_total++))
    else
        check_skip "PHP configuration (PHP not available)"
    fi

    calculate_score "Performance" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Performance"]="${category_passed}/${category_total}"
}

################################################################################
# Category 4: Reliability
################################################################################

validate_reliability() {
    print_section "4. RELIABILITY VALIDATION"

    local category_passed=0
    local category_total=0

    cd "$PROJECT_ROOT/chom" || exit 2

    # Docker configuration
    print_subsection "Docker Configuration"

    if [ -f "docker-compose.production.yml" ]; then
        check_pass "Production docker-compose file exists"
        ((category_passed++))

        # Check for health checks
        if grep -q "healthcheck:" docker-compose.production.yml; then
            check_pass "Health checks configured in docker-compose"
            ((category_passed++))
        else
            check_warn "No health checks in docker-compose" "Add healthcheck configurations for critical services"
        fi
        ((category_total++))

        # Check for restart policies
        if grep -q "restart:" docker-compose.production.yml; then
            check_pass "Restart policies configured"
            ((category_passed++))
        else
            check_fail "No restart policies configured" "Add 'restart: unless-stopped' to all services"
        fi
        ((category_total++))
    else
        check_fail "Production docker-compose file not found" "Create docker-compose.production.yml"
        category_total=$((category_total + 2))
    fi
    ((category_total++))

    # Backup scripts
    print_subsection "Backup Configuration"

    if [ -d "$PROJECT_ROOT/deploy/backup" ]; then
        check_pass "Backup scripts directory exists"
        ((category_passed++))
    else
        check_warn "Backup scripts not found" "Create backup automation scripts"
    fi
    ((category_total++))

    # Monitoring
    print_subsection "Monitoring Configuration"

    if [ -f "docker/prometheus/prometheus.yml" ]; then
        check_pass "Prometheus configuration exists"
        ((category_passed++))
    else
        check_fail "Prometheus configuration not found" "Create prometheus.yml configuration"
    fi
    ((category_total++))

    calculate_score "Reliability" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Reliability"]="${category_passed}/${category_total}"
}

################################################################################
# Category 5: Observability
################################################################################

validate_observability() {
    print_section "5. OBSERVABILITY VALIDATION"

    local category_passed=0
    local category_total=0

    cd "$PROJECT_ROOT/chom" || exit 2

    # Monitoring stack
    print_subsection "Monitoring Stack"

    if [ -f "docker-compose.yml" ] && grep -q "prometheus:" docker-compose.yml; then
        check_pass "Prometheus configured"
        ((category_passed++))
    else
        check_fail "Prometheus not configured" "Add Prometheus to docker-compose"
    fi
    ((category_total++))

    if [ -f "docker-compose.yml" ] && grep -q "grafana:" docker-compose.yml; then
        check_pass "Grafana configured"
        ((category_passed++))
    else
        check_fail "Grafana not configured" "Add Grafana to docker-compose"
    fi
    ((category_total++))

    if [ -f "docker-compose.yml" ] && grep -q "loki:" docker-compose.yml; then
        check_pass "Loki configured"
        ((category_passed++))
    else
        check_warn "Loki not configured" "Add Loki for log aggregation"
    fi
    ((category_total++))

    # Exporters
    print_subsection "Metrics Exporters"

    if [ -f "docker-compose.production.yml" ] && grep -q "node-exporter:" docker-compose.production.yml; then
        check_pass "Node exporter configured"
        ((category_passed++))
    else
        check_warn "Node exporter not configured" "Add node-exporter for system metrics"
    fi
    ((category_total++))

    if [ -f "docker-compose.production.yml" ] && grep -q "phpfpm-exporter:" docker-compose.production.yml; then
        check_pass "PHP-FPM exporter configured"
        ((category_passed++))
    else
        check_warn "PHP-FPM exporter not configured" "Add phpfpm-exporter for PHP metrics"
    fi
    ((category_total++))

    calculate_score "Observability" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Observability"]="${category_passed}/${category_total}"
}

################################################################################
# Category 6: Operations
################################################################################

validate_operations() {
    print_section "6. OPERATIONS VALIDATION"

    local category_passed=0
    local category_total=0

    # Documentation
    print_subsection "Documentation"

    if [ -f "$PROJECT_ROOT/deploy/DEPLOYMENT_RUNBOOK.md" ]; then
        check_pass "Deployment runbook exists"
        ((category_passed++))
    else
        check_fail "Deployment runbook not found" "Create deployment runbook at /deploy/DEPLOYMENT_RUNBOOK.md"
    fi
    ((category_total++))

    if [ -f "$PROJECT_ROOT/docs/ARCHITECTURE.md" ]; then
        check_pass "Architecture documentation exists"
        ((category_passed++))
    else
        check_warn "Architecture documentation not found" "Create architecture docs at /docs/ARCHITECTURE.md"
    fi
    ((category_total++))

    if [ -f "$PROJECT_ROOT/docs/TROUBLESHOOTING.md" ]; then
        check_pass "Troubleshooting guide exists"
        ((category_passed++))
    else
        check_warn "Troubleshooting guide not found" "Create troubleshooting guide at /docs/TROUBLESHOOTING.md"
    fi
    ((category_total++))

    # Deployment scripts
    print_subsection "Deployment Automation"

    if [ -f "$PROJECT_ROOT/deploy/production-deploy.sh" ]; then
        check_pass "Production deployment script exists"
        ((category_passed++))
    else
        check_warn "Production deployment script not found" "Create automated deployment script"
    fi
    ((category_total++))

    calculate_score "Operations" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Operations"]="${category_passed}/${category_total}"
}

################################################################################
# Category 7: Compliance
################################################################################

validate_compliance() {
    print_section "7. COMPLIANCE VALIDATION"

    local category_passed=0
    local category_total=0

    cd "$PROJECT_ROOT/chom" || exit 2

    # Legal documents
    print_subsection "Legal & Privacy"

    if [ -f "resources/views/privacy-policy.blade.php" ] || [ -f "public/privacy-policy.html" ]; then
        check_pass "Privacy policy exists"
        ((category_passed++))
    else
        check_fail "Privacy policy not found" "Create privacy policy document"
    fi
    ((category_total++))

    if [ -f "resources/views/terms-of-service.blade.php" ] || [ -f "public/terms-of-service.html" ]; then
        check_pass "Terms of service exists"
        ((category_passed++))
    else
        check_fail "Terms of service not found" "Create terms of service document"
    fi
    ((category_total++))

    # Email configuration
    print_subsection "Email Service"

    if [ -f ".env" ] && grep -q "MAIL_MAILER" .env; then
        check_pass "Email service configured"
        ((category_passed++))
    else
        check_warn "Email service not configured" "Configure production email service"
    fi
    ((category_total++))

    # Licensing
    print_subsection "Licensing"

    if [ -f "LICENSE" ]; then
        check_pass "LICENSE file exists"
        ((category_passed++))
    else
        check_warn "LICENSE file not found" "Add LICENSE file to repository"
    fi
    ((category_total++))

    calculate_score "Compliance" "$category_passed" "$category_total"
    CATEGORY_RESULTS["Compliance"]="${category_passed}/${category_total}"
}

################################################################################
# Main Execution
################################################################################

show_help() {
    echo "CHOM Production Readiness Validation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --category <name>    Run only specific category"
    echo "                       Options: code-quality, security, performance,"
    echo "                                reliability, observability, operations, compliance"
    echo "  --report <file>      Output detailed report to file"
    echo "  --json               Output results in JSON format"
    echo "  --strict             Fail on any warning (not just errors)"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                              # Run all validations"
    echo "  $0 --category security          # Run only security validations"
    echo "  $0 --report report.txt          # Save report to file"
    echo "  $0 --strict                     # Treat warnings as failures"
    echo ""
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            --report)
                REPORT_FILE="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --strict)
                STRICT_MODE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 2
                ;;
        esac
    done

    # Redirect output to report file if specified
    if [ -n "$REPORT_FILE" ]; then
        exec > >(tee "$REPORT_FILE")
    fi

    print_header

    echo "Starting production readiness validation..."
    echo "Project Root: $PROJECT_ROOT"
    echo "Strict Mode: $STRICT_MODE"
    echo ""

    # Run validations
    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "code-quality" ]; then
        validate_code_quality
    fi

    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "security" ]; then
        validate_security
    fi

    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "performance" ]; then
        validate_performance
    fi

    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "reliability" ]; then
        validate_reliability
    fi

    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "observability" ]; then
        validate_observability
    fi

    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "operations" ]; then
        validate_operations
    fi

    if [ -z "$CATEGORY" ] || [ "$CATEGORY" = "compliance" ]; then
        validate_compliance
    fi

    # Print summary and determine exit code
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
