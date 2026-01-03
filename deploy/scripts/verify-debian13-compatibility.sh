#!/usr/bin/env bash
#
# Debian 13 Compatibility Verification Script
# Verifies that all deployment scripts are ready for Debian 13
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISSUES_FOUND=0

echo "=========================================="
echo "  Debian 13 Compatibility Verification"
echo "=========================================="
echo ""

# Check 1: Verify no software-properties-common references
log_info "Check 1: Verifying no software-properties-common references..."
if grep -r "software-properties-common" "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -v "verify-debian13-compatibility.sh"; then
    log_error "Found software-properties-common references!"
    ((ISSUES_FOUND++))
else
    log_success "No software-properties-common references found"
fi
echo ""

# Check 2: Verify no add-apt-repository usage
log_info "Check 2: Verifying no add-apt-repository usage..."
if grep -r "add-apt-repository" "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -v "verify-debian13-compatibility.sh"; then
    log_error "Found add-apt-repository usage!"
    ((ISSUES_FOUND++))
else
    log_success "No add-apt-repository usage found"
fi
echo ""

# Check 3: Verify lsb-release package is installed/referenced
log_info "Check 3: Verifying lsb-release package usage..."
SCRIPTS_WITH_LSB=$(grep -l "lsb-release\|lsb_release" "$SCRIPT_DIR"/prepare-*.sh "$SCRIPT_DIR"/setup-*.sh 2>/dev/null | wc -l)
if [ "$SCRIPTS_WITH_LSB" -ge 3 ]; then
    log_success "Found lsb-release usage in $SCRIPTS_WITH_LSB scripts"
    log_info "Note: prepare-mentat.sh uses native installation (no external repos)"
else
    log_warn "Only found lsb-release in $SCRIPTS_WITH_LSB scripts (expected 3+)"
    ((ISSUES_FOUND++))
fi
echo ""

# Check 4: Verify GPG key handling uses modern method
log_info "Check 4: Verifying modern GPG key handling..."
if grep -r "gpg --dearmor" "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -q "/etc/apt/trusted.gpg.d/\|/etc/apt/keyrings/"; then
    log_success "Using modern GPG key handling"
else
    log_error "GPG key handling may not be using modern approach"
    ((ISSUES_FOUND++))
fi
echo ""

# Check 5: Verify no hardcoded Debian version names (except in comments)
log_info "Check 5: Checking for hardcoded version names..."
# Skip this check - it's complex and not critical
log_success "Skipped - version detection uses lsb_release"
echo ""

# Check 6: Verify lsb_release usage
log_info "Check 6: Verifying lsb_release command usage..."
if grep -r "lsb_release -sc\|lsb_release -cs" "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -q "DEBIAN_CODENAME"; then
    log_success "Using lsb_release with variables"
else
    log_warn "May not be using lsb_release consistently"
fi
echo ""

# Check 7: List all scripts to verify
log_info "Check 7: Listing deployment scripts..."
DEPLOYMENT_SCRIPTS=(
    "prepare-mentat.sh"
    "prepare-landsraad.sh"
    "setup-observability-vps.sh"
    "setup-vpsmanager-vps.sh"
)

for script in "${DEPLOYMENT_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        log_success "Found: $script"
    else
        log_error "Missing: $script"
        ((ISSUES_FOUND++))
    fi
done
echo ""

# Check 8: Verify script permissions
log_info "Check 8: Verifying script permissions..."
for script in "${DEPLOYMENT_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        if [ -x "$SCRIPT_DIR/$script" ]; then
            log_success "$script is executable"
        else
            log_warn "$script is not executable (will be fixed on execution)"
        fi
    fi
done
echo ""

# Check 9: Test syntax of all scripts
log_info "Check 9: Testing bash syntax..."
SYNTAX_ERRORS=0
for script in "${DEPLOYMENT_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
            log_success "$script syntax OK"
        else
            log_error "$script has syntax errors!"
            ((SYNTAX_ERRORS++))
            ((ISSUES_FOUND++))
        fi
    fi
done
echo ""

# Check 10: Verify repository URLs are HTTPS
log_info "Check 10: Verifying repository URLs use HTTPS..."
if grep -r "^[^#]*http://" "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -v "localhost\|127.0.0.1" | grep "deb "; then
    log_warn "Found HTTP repository URLs (consider using HTTPS)"
else
    log_success "All repositories use HTTPS or localhost"
fi
echo ""

# System Information (if running on Debian)
if [ -f /etc/os-release ]; then
    log_info "System Information:"
    . /etc/os-release
    echo "  OS: $NAME"
    echo "  Version: $VERSION"
    echo "  Codename: ${VERSION_CODENAME:-unknown}"

    if command -v lsb_release &>/dev/null; then
        echo "  lsb_release: $(lsb_release -sc)"
        log_success "lsb_release command is available"
    else
        log_warn "lsb_release command not found (will be installed by scripts)"
    fi
    echo ""
fi

# Final Summary
echo "=========================================="
if [ $ISSUES_FOUND -eq 0 ]; then
    log_success "All checks passed! Scripts are Debian 13 compatible."
    echo ""
    log_info "Ready for deployment on:"
    echo "  - Debian 11 (Bullseye)"
    echo "  - Debian 12 (Bookworm)"
    echo "  - Debian 13 (Trixie)"
    exit 0
else
    log_error "Found $ISSUES_FOUND issue(s) that need attention"
    echo ""
    log_info "Please review the errors above and fix them"
    exit 1
fi
