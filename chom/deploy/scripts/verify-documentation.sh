#!/bin/bash
#===============================================================================
# Documentation Completeness Verification Script
#
# Verifies all components are properly documented
#
# Usage:
#   ./verify-documentation.sh [OPTIONS]
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

TOTAL=0
PASSED=0
FAILED=0

print_check() {
    echo -n "  [CHECK] $1... "
    TOTAL=$((TOTAL + 1))
}

pass() {
    echo "${GREEN}✓${NC}"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

echo "${CYAN}${BOLD}Documentation Completeness Check${NC}"
echo ""

# Check README
print_check "README.md exists"
[[ -f "${PROJECT_ROOT}/README.md" ]] && pass || fail "Missing"

# Check API documentation
print_check "API documentation exists"
[[ -f "${PROJECT_ROOT}/docs/API.md" ]] || [[ -d "${PROJECT_ROOT}/docs/api" ]] && pass || fail "Missing"

# Check deployment guide
print_check "Deployment guide exists"
[[ -f "${PROJECT_ROOT}/deploy/DEPLOYMENT-GUIDE.md" ]] && pass || fail "Missing"

# Check security documentation
print_check "Security documentation exists"
[[ -f "${PROJECT_ROOT}/docs/SECURITY-AUDIT-CHECKLIST.md" ]] && pass || fail "Missing"

# Check architecture documentation
print_check "Architecture documentation exists"
[[ -f "${PROJECT_ROOT}/docs/ARCHITECTURE.md" ]] || [[ -f "${PROJECT_ROOT}/ARCHITECTURE.md" ]] && pass || fail "Missing"

# Check performance baselines
print_check "Performance baselines documented"
[[ -f "${PROJECT_ROOT}/docs/PERFORMANCE-BASELINES.md" ]] && pass || fail "Missing"

# Check all services have docblocks
print_check "Services have documentation"
undocumented=$(find "${PROJECT_ROOT}/app/Services" -name "*.php" -exec grep -L "@" {} \; 2>/dev/null | wc -l)
[[ $undocumented -eq 0 ]] && pass || fail "${undocumented} files undocumented"

# Check all controllers have docblocks
print_check "Controllers have documentation"
undocumented=$(find "${PROJECT_ROOT}/app/Http/Controllers" -name "*.php" -exec grep -L "@" {} \; 2>/dev/null | wc -l)
[[ $undocumented -eq 0 ]] && pass || fail "${undocumented} files undocumented"

# Summary
echo ""
echo "${BOLD}Summary:${NC} ${PASSED}/${TOTAL} checks passed"
[[ $FAILED -eq 0 ]] && echo "${GREEN}✓ Documentation complete${NC}" || echo "${RED}✗ ${FAILED} issues found${NC}"
echo ""

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
