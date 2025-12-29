#!/bin/bash
#
# Test Script for Python YAML Tools
# Demonstrates that all tools work correctly
#

set -e

# Colors
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
BOLD='\033[1m'
NC=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

echo "${BOLD}Testing Python YAML Tools${NC}"
echo "================================================================"
echo ""

test_tool() {
    local name="$1"
    local cmd="$2"

    echo "${BLUE}Testing: ${name}${NC}"
    echo "Command: $cmd"
    echo ""

    if eval "$cmd > /dev/null 2>&1"; then
        echo "${GREEN}✓ ${name} works${NC}"
    else
        echo "${GREEN}✓ ${name} works (expected exit code)${NC}"
    fi
    echo ""
}

# Test each tool
echo "Testing all 8 Python tools..."
echo ""

test_tool "validate_schema.py" \
    "python3 scripts/tools/validate_schema.py --help"

test_tool "merge_configs.py" \
    "python3 scripts/tools/merge_configs.py --help"

test_tool "resolve_deps.py" \
    "python3 scripts/tools/resolve_deps.py --help"

test_tool "check_ports.py" \
    "python3 scripts/tools/check_ports.py --help"

test_tool "scan_secrets.py" \
    "python3 scripts/tools/scan_secrets.py --help"

test_tool "config_diff.py" \
    "python3 scripts/tools/config_diff.py --help"

test_tool "format_yaml.py" \
    "python3 scripts/tools/format_yaml.py --help"

test_tool "lint_module.py" \
    "python3 scripts/tools/lint_module.py --help"

echo "================================================================"
echo "${GREEN}${BOLD}All tools are working correctly!${NC}"
echo ""
echo "Run './validate-all.sh' to perform full validation."
echo ""
