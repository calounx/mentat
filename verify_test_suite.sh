#!/bin/bash

# CHOM API Test Suite Verification Script
# Checks that all test suite components are properly installed

set -e

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║           CHOM API Test Suite - Installation Verification            ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

ERRORS=0
WARNINGS=0

echo "Checking test suite files..."
echo ""

# Check core files
if [ -f "requirements-test.txt" ]; then
    check_pass "requirements-test.txt found"
else
    check_fail "requirements-test.txt missing"
    ((ERRORS++))
fi

if [ -f "pytest.ini" ]; then
    check_pass "pytest.ini found"
else
    check_fail "pytest.ini missing"
    ((ERRORS++))
fi

if [ -f ".env.testing" ]; then
    check_pass ".env.testing template found"
else
    check_fail ".env.testing missing"
    ((ERRORS++))
fi

if [ -f "run_tests.sh" ] && [ -x "run_tests.sh" ]; then
    check_pass "run_tests.sh found and executable"
else
    check_fail "run_tests.sh missing or not executable"
    ((ERRORS++))
fi

if [ -f "run_load_test.sh" ] && [ -x "run_load_test.sh" ]; then
    check_pass "run_load_test.sh found and executable"
else
    check_fail "run_load_test.sh missing or not executable"
    ((ERRORS++))
fi

echo ""
echo "Checking test files..."
echo ""

# Check test directory structure
if [ -d "tests/api" ]; then
    check_pass "tests/api directory exists"
    
    # Count test files
    TEST_COUNT=$(find tests/api -name "test_*.py" | wc -l)
    check_info "Found $TEST_COUNT test files"
    
    # Check individual test files
    for file in "test_auth.py" "test_sites.py" "test_backups.py" "test_team.py" "test_health.py" "test_schema_validation.py"; do
        if [ -f "tests/api/$file" ]; then
            FUNC_COUNT=$(grep -c "def test_" "tests/api/$file" || echo "0")
            check_pass "$file ($FUNC_COUNT test functions)"
        else
            check_fail "$file missing"
            ((ERRORS++))
        fi
    done
else
    check_fail "tests/api directory missing"
    ((ERRORS++))
fi

echo ""
echo "Checking configuration files..."
echo ""

if [ -f "tests/api/conftest.py" ]; then
    check_pass "conftest.py (fixtures) found"
else
    check_fail "conftest.py missing"
    ((ERRORS++))
fi

if [ -f "tests/api/utils.py" ]; then
    check_pass "utils.py (utilities) found"
else
    check_fail "utils.py missing"
    ((ERRORS++))
fi

if [ -f "tests/api/load/locustfile.py" ]; then
    check_pass "locustfile.py (load testing) found"
else
    check_fail "locustfile.py missing"
    ((ERRORS++))
fi

echo ""
echo "Checking documentation..."
echo ""

if [ -f "tests/api/README.md" ]; then
    check_pass "tests/api/README.md found"
else
    check_warn "tests/api/README.md missing"
    ((WARNINGS++))
fi

if [ -f "TESTING_GUIDE.md" ]; then
    check_pass "TESTING_GUIDE.md found"
else
    check_warn "TESTING_GUIDE.md missing"
    ((WARNINGS++))
fi

if [ -f "TEST_SUITE_SUMMARY.md" ]; then
    check_pass "TEST_SUITE_SUMMARY.md found"
else
    check_warn "TEST_SUITE_SUMMARY.md missing"
    ((WARNINGS++))
fi

if [ -f "QUICK_REFERENCE.md" ]; then
    check_pass "QUICK_REFERENCE.md found"
else
    check_warn "QUICK_REFERENCE.md missing"
    ((WARNINGS++))
fi

echo ""
echo "Checking Python environment..."
echo ""

# Check Python
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    check_pass "Python 3 installed ($PYTHON_VERSION)"
else
    check_fail "Python 3 not found"
    ((ERRORS++))
fi

# Check virtual environment
if [ -d "venv" ]; then
    check_pass "Virtual environment exists"
else
    check_warn "Virtual environment not created (run: python3 -m venv venv)"
    ((WARNINGS++))
fi

# Check if pytest is installed (if venv activated)
if [ -n "$VIRTUAL_ENV" ]; then
    if command -v pytest &> /dev/null; then
        PYTEST_VERSION=$(pytest --version | head -n1)
        check_pass "pytest installed ($PYTEST_VERSION)"
    else
        check_fail "pytest not installed"
        ((ERRORS++))
    fi
else
    check_info "Virtual environment not activated (cannot check pytest)"
fi

echo ""
echo "Checking optional components..."
echo ""

if [ -f "docker-compose.test.yml" ]; then
    check_pass "docker-compose.test.yml found"
else
    check_warn "docker-compose.test.yml missing"
    ((WARNINGS++))
fi

# Check if Docker is available
if command -v docker &> /dev/null; then
    check_pass "Docker installed"
else
    check_warn "Docker not installed (optional)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

# Summary
TOTAL_FILES=0
TOTAL_TESTS=0

if [ -d "tests/api" ]; then
    TOTAL_FILES=$(find tests/api -name "test_*.py" | wc -l)
    TOTAL_TESTS=$(grep -r "def test_" tests/api/test_*.py 2>/dev/null | wc -l || echo "0")
fi

echo "Summary:"
echo "  Test Files: $TOTAL_FILES"
echo "  Test Functions: $TOTAL_TESTS"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Test suite installation verified successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Create virtual environment: python3 -m venv venv"
    echo "  2. Activate it: source venv/bin/activate"
    echo "  3. Install dependencies: pip install -r requirements-test.txt"
    echo "  4. Configure environment: cp .env.testing .env.test"
    echo "  5. Run tests: ./run_tests.sh"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Test suite installation has errors!${NC}"
    echo ""
    echo "Please fix the errors above and run this script again."
    echo ""
    exit 1
fi
