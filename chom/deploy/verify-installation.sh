#!/bin/bash

###############################################################################
# Verification Script for CHOM Deployment Tools
# Verifies all deployment validation and monitoring tools are installed
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     CHOM Deployment Tools Installation Verification          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISSING=0
TOTAL=0

check_script() {
    local script_path="$1"
    local description="$2"

    ((TOTAL++))

    if [[ -f "$script_path" ]]; then
        if [[ -x "$script_path" ]]; then
            echo -e "${GREEN}[✓]${NC} $description"
        else
            echo -e "${YELLOW}[⚠]${NC} $description (not executable)"
            ((MISSING++))
        fi
    else
        echo -e "${RED}[✗]${NC} $description (missing)"
        ((MISSING++))
    fi
}

echo -e "${BOLD}Validation Scripts:${NC}"
check_script "$SCRIPT_DIR/validation/pre-deployment-check.sh" "Pre-deployment check"
check_script "$SCRIPT_DIR/validation/post-deployment-check.sh" "Post-deployment check"
check_script "$SCRIPT_DIR/validation/smoke-tests.sh" "Smoke tests"
check_script "$SCRIPT_DIR/validation/performance-check.sh" "Performance check"
check_script "$SCRIPT_DIR/validation/security-check.sh" "Security check"
check_script "$SCRIPT_DIR/validation/observability-check.sh" "Observability check"
check_script "$SCRIPT_DIR/validation/migration-check.sh" "Migration check"
check_script "$SCRIPT_DIR/validation/rollback-test.sh" "Rollback test"

echo ""
echo -e "${BOLD}Monitoring Tools:${NC}"
check_script "$SCRIPT_DIR/monitoring/deployment-status.sh" "Deployment status dashboard"
check_script "$SCRIPT_DIR/monitoring/service-status.sh" "Service status dashboard"
check_script "$SCRIPT_DIR/monitoring/resource-monitor.sh" "Resource monitor"
check_script "$SCRIPT_DIR/monitoring/deployment-history.sh" "Deployment history"

echo ""
echo -e "${BOLD}Troubleshooting Tools:${NC}"
check_script "$SCRIPT_DIR/troubleshooting/analyze-logs.sh" "Log analysis"
check_script "$SCRIPT_DIR/troubleshooting/test-connections.sh" "Connection tests"
check_script "$SCRIPT_DIR/troubleshooting/emergency-diagnostics.sh" "Emergency diagnostics"

echo ""
echo -e "${BOLD}Documentation:${NC}"

check_doc() {
    local doc_path="$1"
    local description="$2"

    ((TOTAL++))

    if [[ -f "$doc_path" ]]; then
        echo -e "${GREEN}[✓]${NC} $description"
    else
        echo -e "${RED}[✗]${NC} $description (missing)"
        ((MISSING++))
    fi
}

check_doc "$SCRIPT_DIR/DEPLOYMENT-TOOLS-README.md" "Comprehensive README"
check_doc "$SCRIPT_DIR/QUICK-START.md" "Quick Start Guide"
check_doc "$SCRIPT_DIR/DEPLOYMENT-VALIDATION-SUMMARY.md" "Implementation Summary"

echo ""
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Summary${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

INSTALLED=$((TOTAL - MISSING))

echo -e "Total components: ${BOLD}$TOTAL${NC}"
echo -e "Installed:        ${GREEN}${BOLD}$INSTALLED${NC}"
echo -e "Missing:          ${RED}${BOLD}$MISSING${NC}"

echo ""

if [[ "$MISSING" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ All deployment tools installed successfully!${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. Review: ${BOLD}cat $SCRIPT_DIR/QUICK-START.md${NC}"
    echo -e "  2. Test: ${BOLD}$SCRIPT_DIR/validation/pre-deployment-check.sh --help${NC}"
    echo -e "  3. Configure: Edit server settings in scripts (DEPLOY_USER, APP_SERVER)"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ Installation incomplete!${NC}"
    echo -e "${YELLOW}Please check missing components above${NC}"
    echo ""
    exit 1
fi
