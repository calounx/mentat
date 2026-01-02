#!/bin/bash
#
# Verification script for Exporter Validator installation
#

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Verifying Exporter Validator Installation"
echo "=========================================="
echo

checks_passed=0
checks_failed=0

# Check 1: Python version
echo -n "Checking Python version... "
if python3 --version | grep -qE "Python 3\.(8|9|10|11|12)"; then
    echo -e "${GREEN}✓${NC}"
    ((checks_passed++))
else
    echo -e "${RED}✗${NC} (Python 3.8+ required)"
    ((checks_failed++))
fi

# Check 2: Main script exists
echo -n "Checking validate-exporters.py... "
if [ -f "validate-exporters.py" ] && [ -x "validate-exporters.py" ]; then
    echo -e "${GREEN}✓${NC}"
    ((checks_passed++))
else
    echo -e "${RED}✗${NC} (Script not found or not executable)"
    ((checks_failed++))
fi

# Check 3: Dependencies
echo -n "Checking requests library... "
if python3 -c "import requests" 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    ((checks_passed++))
else
    echo -e "${RED}✗${NC} (Run: pip install requests)"
    ((checks_failed++))
fi

# Check 4: Documentation
echo -n "Checking documentation... "
docs_count=$(ls -1 EXPORTER_*.md QUICK_START_*.md VALIDATOR_*.md 2>/dev/null | wc -l)
if [ "$docs_count" -ge 3 ]; then
    echo -e "${GREEN}✓${NC} ($docs_count files)"
    ((checks_passed++))
else
    echo -e "${YELLOW}⚠${NC} (Some documentation missing)"
fi

# Check 5: Examples directory
echo -n "Checking examples directory... "
if [ -d "examples" ] && [ -f "examples/validate-all-exporters.sh" ]; then
    examples_count=$(ls -1 examples/*.sh examples/*.py 2>/dev/null | wc -l)
    echo -e "${GREEN}✓${NC} ($examples_count files)"
    ((checks_passed++))
else
    echo -e "${YELLOW}⚠${NC} (Examples not found)"
fi

# Check 6: Script syntax
echo -n "Checking Python syntax... "
if python3 -m py_compile validate-exporters.py 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    ((checks_passed++))
else
    echo -e "${RED}✗${NC} (Syntax errors found)"
    ((checks_failed++))
fi

# Check 7: Help output
echo -n "Checking help output... "
if ./validate-exporters.py --help >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
    ((checks_passed++))
else
    echo -e "${RED}✗${NC} (Help command failed)"
    ((checks_failed++))
fi

echo
echo "=========================================="
echo "Results: ${GREEN}$checks_passed passed${NC}, ${RED}$checks_failed failed${NC}"
echo

if [ $checks_failed -eq 0 ]; then
    echo -e "${GREEN}Installation verified successfully!${NC}"
    echo
    echo "Next steps:"
    echo "1. Read quick start: cat QUICK_START_VALIDATION.md"
    echo "2. Try validation: ./validate-exporters.py --endpoint http://localhost:9100/metrics"
    echo "3. Explore examples: ls examples/"
    exit 0
else
    echo -e "${RED}Installation incomplete. Please fix the issues above.${NC}"
    exit 1
fi
