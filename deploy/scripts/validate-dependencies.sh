#!/usr/bin/env bash
# Comprehensive Dependency Validation Script
# Validates that ALL required files exist before deployment
#
# Usage:
#   ./scripts/validate-dependencies.sh
#
# Exit codes:
#   0 - All dependencies OK
#   1 - Missing dependencies found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Print functions
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         CHOM Deployment - Dependency Validation                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "${BLUE}▶ $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_file() {
    local file_path="$1"
    local description="$2"
    ((TOTAL_CHECKS++))

    if [[ -f "${file_path}" ]]; then
        echo -e "  ${GREEN}✓${NC} ${description}"
        ((PASSED_CHECKS++))
        return 0
    else
        echo -e "  ${RED}✗${NC} ${description}"
        echo -e "    ${RED}Missing: ${file_path}${NC}"
        ((FAILED_CHECKS++))
        return 1
    fi
}

check_executable() {
    local file_path="$1"
    local description="$2"
    ((TOTAL_CHECKS++))

    if [[ -f "${file_path}" ]]; then
        if [[ -x "${file_path}" ]]; then
            echo -e "  ${GREEN}✓${NC} ${description}"
            ((PASSED_CHECKS++))
            return 0
        else
            echo -e "  ${YELLOW}⚠${NC} ${description} (not executable)"
            echo -e "    ${YELLOW}Run: chmod +x ${file_path}${NC}"
            ((PASSED_CHECKS++))
            return 0
        fi
    else
        echo -e "  ${RED}✗${NC} ${description}"
        echo -e "    ${RED}Missing: ${file_path}${NC}"
        ((FAILED_CHECKS++))
        return 1
    fi
}

check_directory() {
    local dir_path="$1"
    local description="$2"
    ((TOTAL_CHECKS++))

    if [[ -d "${dir_path}" ]]; then
        echo -e "  ${GREEN}✓${NC} ${description}"
        ((PASSED_CHECKS++))
        return 0
    else
        echo -e "  ${RED}✗${NC} ${description}"
        echo -e "    ${RED}Missing directory: ${dir_path}${NC}"
        ((FAILED_CHECKS++))
        return 1
    fi
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}SUMMARY${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Total checks:  ${TOTAL_CHECKS}"
    echo -e "  ${GREEN}Passed:        ${PASSED_CHECKS}${NC}"
    if [[ ${FAILED_CHECKS} -gt 0 ]]; then
        echo -e "  ${RED}Failed:        ${FAILED_CHECKS}${NC}"
    else
        echo -e "  ${GREEN}Failed:        ${FAILED_CHECKS}${NC}"
    fi
    echo ""

    if [[ ${FAILED_CHECKS} -eq 0 ]]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ ALL DEPENDENCIES VERIFIED - DEPLOYMENT SYSTEM READY          ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
        return 0
    else
        echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ✗ MISSING DEPENDENCIES - CANNOT PROCEED WITH DEPLOYMENT        ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Please ensure all required files are in place before deploying.${NC}"
        return 1
    fi
}

# Main validation
main() {
    print_header

    # 1. Core directories
    print_section "1. Core Directories"
    check_directory "${DEPLOY_ROOT}" "Deploy root directory"
    check_directory "${DEPLOY_ROOT}/scripts" "Scripts directory"
    check_directory "${DEPLOY_ROOT}/utils" "Utils directory"
    check_directory "${DEPLOY_ROOT}/config" "Config directory"
    check_directory "${DEPLOY_ROOT}/config/landsraad" "Landsraad config directory"
    check_directory "${DEPLOY_ROOT}/config/mentat" "Mentat config directory"
    check_directory "${DEPLOY_ROOT}/security" "Security directory"
    check_directory "${DEPLOY_ROOT}/tests" "Tests directory"
    echo ""

    # 2. Utility libraries
    print_section "2. Utility Libraries"
    check_file "${DEPLOY_ROOT}/utils/colors.sh" "Colors library"
    check_file "${DEPLOY_ROOT}/utils/logging.sh" "Logging library"
    check_file "${DEPLOY_ROOT}/utils/notifications.sh" "Notifications library"
    check_file "${DEPLOY_ROOT}/utils/idempotence.sh" "Idempotence helpers library"
    echo ""

    # 3. Main deployment scripts
    print_section "3. Main Deployment Scripts"
    check_executable "${DEPLOY_ROOT}/deploy-chom.sh" "Main deployment orchestrator"
    check_executable "${DEPLOY_ROOT}/deploy-chom-automated.sh" "Automated deployment orchestrator"
    echo ""

    # 4. Server preparation scripts
    print_section "4. Server Preparation Scripts"
    check_executable "${DEPLOY_ROOT}/scripts/prepare-mentat.sh" "Mentat server preparation"
    check_executable "${DEPLOY_ROOT}/scripts/prepare-landsraad.sh" "Landsraad server preparation"
    check_executable "${DEPLOY_ROOT}/scripts/preflight-check.sh" "Pre-flight checks"
    echo ""

    # 5. Deployment scripts
    print_section "5. Deployment Scripts"
    check_executable "${DEPLOY_ROOT}/scripts/deploy-application.sh" "Application deployment"
    check_executable "${DEPLOY_ROOT}/scripts/deploy-observability.sh" "Observability deployment"
    check_executable "${DEPLOY_ROOT}/scripts/backup-before-deploy.sh" "Pre-deployment backup"
    check_executable "${DEPLOY_ROOT}/scripts/rollback.sh" "Rollback script"
    check_executable "${DEPLOY_ROOT}/scripts/health-check.sh" "Health check script"
    echo ""

    # 6. User and SSH setup
    print_section "6. User and SSH Setup Scripts"
    check_executable "${DEPLOY_ROOT}/scripts/setup-stilgar-user.sh" "Stilgar user setup"
    check_executable "${DEPLOY_ROOT}/scripts/setup-ssh-automation.sh" "SSH automation setup"
    check_executable "${DEPLOY_ROOT}/scripts/setup-ssh-keys.sh" "SSH keys setup"
    echo ""

    # 7. Security scripts
    print_section "7. Security Scripts"
    check_executable "${DEPLOY_ROOT}/scripts/setup-firewall.sh" "Firewall setup"
    check_executable "${DEPLOY_ROOT}/scripts/setup-ssl.sh" "SSL setup"
    check_executable "${DEPLOY_ROOT}/scripts/generate-deployment-secrets.sh" "Deployment secrets generator"
    check_executable "${DEPLOY_ROOT}/security/create-deployment-user.sh" "Secure deployment user creation"
    check_executable "${DEPLOY_ROOT}/security/generate-ssh-keys-secure.sh" "Secure SSH key generation"
    check_executable "${DEPLOY_ROOT}/security/generate-secure-secrets.sh" "Secure secrets generation"
    check_executable "${DEPLOY_ROOT}/security/rotate-secrets.sh" "Secret rotation"
    echo ""

    # 8. Configuration files
    print_section "8. Configuration Files"
    check_file "${DEPLOY_ROOT}/config/landsraad/nginx.conf" "Nginx configuration"
    check_file "${DEPLOY_ROOT}/config/landsraad/php-fpm.conf" "PHP-FPM configuration"
    check_file "${DEPLOY_ROOT}/config/landsraad/postgresql.conf" "PostgreSQL configuration"
    check_file "${DEPLOY_ROOT}/config/landsraad/redis.conf" "Redis configuration"
    check_file "${DEPLOY_ROOT}/config/landsraad/supervisor.conf" "Supervisor configuration"
    check_file "${DEPLOY_ROOT}/config/landsraad/.env.production.template" "Environment template"
    echo ""

    # 9. Observability configurations
    print_section "9. Observability Configurations"
    check_file "${DEPLOY_ROOT}/config/mentat/prometheus.yml" "Prometheus configuration"
    check_file "${DEPLOY_ROOT}/config/mentat/alertmanager.yml" "AlertManager configuration"
    check_file "${DEPLOY_ROOT}/config/mentat/grafana-datasources.yml" "Grafana datasources"
    check_file "${DEPLOY_ROOT}/config/mentat/loki-config.yml" "Loki configuration"
    check_file "${DEPLOY_ROOT}/config/mentat/promtail-config.yml" "Promtail configuration"
    check_file "${DEPLOY_ROOT}/config/mentat/blackbox.yml" "Blackbox exporter configuration"
    echo ""

    # 10. Templates
    print_section "10. Templates"
    check_file "${DEPLOY_ROOT}/.deployment-secrets.template" "Deployment secrets template"
    echo ""

    # 11. Testing framework
    print_section "11. Testing Framework"
    check_executable "${DEPLOY_ROOT}/tests/test-idempotence.sh" "Idempotence testing framework"
    echo ""

    # 12. Verification scripts
    print_section "12. Verification Scripts"
    check_executable "${DEPLOY_ROOT}/scripts/verify-native-deployment.sh" "Native deployment verification"
    check_executable "${DEPLOY_ROOT}/scripts/verify-debian13-compatibility.sh" "Debian 13 compatibility verification"
    echo ""

    # 13. Documentation
    print_section "13. Documentation"
    check_file "${DEPLOY_ROOT}/README.md" "Main README"
    check_file "${DEPLOY_ROOT}/QUICK_START.md" "Quick start guide"
    check_file "${DEPLOY_ROOT}/QUICK-START-AUTOMATED.md" "Automated deployment quick start"
    check_file "${DEPLOY_ROOT}/AUTOMATED-DEPLOYMENT.md" "Automated deployment guide"
    echo ""

    # Print summary
    print_summary
}

# Run main validation
main
exit_code=$?

# Exit with appropriate code
exit ${exit_code}
