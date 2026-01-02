#!/bin/bash

# CHOM API Test Suite Runner
#
# This script runs the comprehensive API test suite with various options.
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh auth         # Run only auth tests
#   ./run_tests.sh --verbose    # Run with verbose output
#   ./run_tests.sh --coverage   # Run with coverage report
#   ./run_tests.sh --parallel   # Run tests in parallel

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERBOSE=""
COVERAGE=""
PARALLEL=""
MARKER=""
TEST_PATH="tests/api"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        -c|--coverage)
            COVERAGE="--cov=tests --cov-report=html --cov-report=term"
            shift
            ;;
        -p|--parallel)
            PARALLEL="-n auto"
            shift
            ;;
        -m|--marker)
            MARKER="-m $2"
            shift 2
            ;;
        auth|sites|backups|team|health)
            MARKER="-m $1"
            shift
            ;;
        --performance)
            MARKER="-m performance"
            shift
            ;;
        --security)
            MARKER="-m security"
            shift
            ;;
        --critical)
            MARKER="-m critical"
            shift
            ;;
        -h|--help)
            echo "CHOM API Test Suite Runner"
            echo ""
            echo "Usage: $0 [OPTIONS] [MARKER]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose      Verbose output"
            echo "  -c, --coverage     Generate coverage report"
            echo "  -p, --parallel     Run tests in parallel"
            echo "  -m, --marker NAME  Run tests with specific marker"
            echo "  -h, --help         Show this help"
            echo ""
            echo "Markers:"
            echo "  auth               Run authentication tests"
            echo "  sites              Run site management tests"
            echo "  backups            Run backup tests"
            echo "  team               Run team management tests"
            echo "  health             Run health check tests"
            echo "  performance        Run performance tests"
            echo "  security           Run security tests"
            echo "  critical           Run critical path tests"
            echo ""
            echo "Examples:"
            echo "  $0                 # Run all tests"
            echo "  $0 auth            # Run only auth tests"
            echo "  $0 -v -c           # Run all tests with coverage"
            echo "  $0 -p --security   # Run security tests in parallel"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Print banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                     CHOM API Test Suite                               ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Virtual environment not found. Creating...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements-test.txt
else
    source venv/bin/activate
fi

# Check if dependencies are installed
if ! python -c "import pytest" 2>/dev/null; then
    echo -e "${YELLOW}Installing test dependencies...${NC}"
    pip install -r requirements-test.txt
fi

# Create reports directory
mkdir -p reports
mkdir -p htmlcov

# Print test configuration
echo -e "${GREEN}Test Configuration:${NC}"
echo "  Test Path: $TEST_PATH"
echo "  Verbose: $([ -n "$VERBOSE" ] && echo "Yes" || echo "No")"
echo "  Coverage: $([ -n "$COVERAGE" ] && echo "Yes" || echo "No")"
echo "  Parallel: $([ -n "$PARALLEL" ] && echo "Yes" || echo "No")"
echo "  Marker: $([ -n "$MARKER" ] && echo "${MARKER#-m }" || echo "All")"
echo ""

# Check if API is accessible
API_URL="${API_BASE_URL:-http://localhost:8000/api/v1}"
echo -e "${BLUE}Checking API connectivity at $API_URL/health...${NC}"

if curl -s -f "$API_URL/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Warning: API may not be accessible${NC}"
    echo -e "${YELLOW}  Make sure the API server is running${NC}"
    echo ""
fi

# Run tests
echo -e "${BLUE}Running tests...${NC}"
echo ""

# Build pytest command
PYTEST_CMD="pytest $TEST_PATH $VERBOSE $COVERAGE $PARALLEL $MARKER --html=reports/test_report.html --self-contained-html"

# Run pytest
if eval $PYTEST_CMD; then
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                     Tests Passed Successfully!                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"

    # Show report locations
    echo ""
    echo -e "${BLUE}Reports generated:${NC}"
    echo "  HTML Report: reports/test_report.html"

    if [ -n "$COVERAGE" ]; then
        echo "  Coverage Report: htmlcov/index.html"
    fi

    exit 0
else
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                        Tests Failed!                                  ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Check the HTML report for details: reports/test_report.html${NC}"

    exit 1
fi
