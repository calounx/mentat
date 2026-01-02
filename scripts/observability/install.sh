#!/bin/bash
#===============================================================================
# Exporter Troubleshooting System - Installation Script
#===============================================================================
# Sets up the troubleshooting system with all dependencies
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "================================================================================"
echo "  Exporter Troubleshooting System - Installation"
echo "================================================================================"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo -e "${YELLOW}Warning: Running as root. This is okay for installation.${NC}"
fi

# Function to check command availability
check_command() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $cmd installed"
        return 0
    else
        echo -e "  ${RED}✗${NC} $cmd not found"
        return 1
    fi
}

# Check prerequisites
echo "Checking prerequisites..."

MISSING_DEPS=()

if ! check_command curl; then MISSING_DEPS+=(curl); fi
if ! check_command systemctl; then MISSING_DEPS+=(systemd); fi

# Optional but recommended
if ! check_command bc; then
    echo -e "  ${YELLOW}⚠${NC} bc not found (optional, for resource checks)"
fi

if ! command -v netstat &>/dev/null && ! command -v ss &>/dev/null; then
    echo -e "  ${RED}✗${NC} Neither netstat nor ss found (at least one required)"
    MISSING_DEPS+=(net-tools)
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Missing required dependencies: ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo "Install with:"
    echo "  apt-get install -y ${MISSING_DEPS[*]}"
    echo "  yum install -y ${MISSING_DEPS[*]}"
    echo ""
    exit 1
fi

echo ""

# Create prometheus user if it doesn't exist
echo "Checking prometheus user..."
if id prometheus &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} prometheus user exists"
else
    echo -e "  ${YELLOW}→${NC} Creating prometheus user..."
    useradd --system --no-create-home --shell /bin/false prometheus
    echo -e "  ${GREEN}✓${NC} prometheus user created"
fi

echo ""

# Make scripts executable
echo "Setting up scripts..."
chmod +x "${SCRIPT_DIR}/troubleshoot-exporters.sh"
chmod +x "${SCRIPT_DIR}/quick-check.sh"
chmod +x "${SCRIPT_DIR}/lib/diagnostic-helpers.sh"
echo -e "  ${GREEN}✓${NC} Scripts made executable"

echo ""

# Create log directory
echo "Creating log directory..."
LOG_DIR="/var/log/exporter-diagnostics"
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    echo -e "  ${GREEN}✓${NC} Created ${LOG_DIR}"
else
    echo -e "  ${GREEN}✓${NC} Log directory exists: ${LOG_DIR}"
fi

echo ""

# Test basic functionality
echo "Testing basic functionality..."
if "${SCRIPT_DIR}/lib/diagnostic-helpers.sh" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Diagnostic helpers library loads correctly"
else
    # Library is meant to be sourced, so this might fail - that's ok
    echo -e "  ${BLUE}→${NC} Diagnostic helpers library present"
fi

echo ""

# Display installation summary
echo "================================================================================"
echo "  Installation Summary"
echo "================================================================================"
echo ""
echo "Scripts installed at: ${SCRIPT_DIR}"
echo "Log directory: ${LOG_DIR}"
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Run quick check:"
echo "   ${SCRIPT_DIR}/quick-check.sh"
echo ""
echo "2. Run full diagnostics:"
echo "   ${SCRIPT_DIR}/troubleshoot-exporters.sh --deep"
echo ""
echo "3. View help:"
echo "   ${SCRIPT_DIR}/troubleshoot-exporters.sh --help"
echo ""
echo "4. Setup scheduled monitoring (optional):"
echo "   Add to crontab:"
echo "   */5 * * * * ${SCRIPT_DIR}/quick-check.sh --log ${LOG_DIR}/check.log"
echo ""
echo "5. Read documentation:"
echo "   cat ${SCRIPT_DIR}/README.md"
echo ""
echo "================================================================================"
echo ""
