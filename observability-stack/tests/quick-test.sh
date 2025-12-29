#!/bin/bash
#===============================================================================
# Quick Test Script
# Convenient wrapper for common test scenarios
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

show_help() {
    cat << EOF
Quick Test - Convenient test runner for common scenarios

Usage: $0 [COMMAND]

Commands:
  all               Run all tests (default)
  unit              Run unit tests only
  integration       Run integration tests only
  security          Run security tests only
  errors            Run error handling tests only

  common            Run common.sh tests
  loader            Run module-loader.sh tests
  generator         Run config-generator.sh tests

  fast              Run fast tests (unit + security)
  slow              Run slow tests (integration)

  check             Quick health check (subset of tests)
  watch             Run tests on file changes (requires entr)

  setup             Set up test environment
  clean             Clean test artifacts

  help              Show this help message

Examples:
  $0                # Run all tests
  $0 unit           # Run unit tests
  $0 common         # Run common.sh tests only
  $0 check          # Quick health check
  $0 fast           # Run fast tests

EOF
}

run_command() {
    local cmd="$1"

    case "$cmd" in
        all)
            echo "${BLUE}Running all tests...${NC}"
            ./run-all-tests.sh
            ;;

        unit)
            echo "${BLUE}Running unit tests...${NC}"
            ./run-all-tests.sh --unit-only
            ;;

        integration)
            echo "${BLUE}Running integration tests...${NC}"
            ./run-all-tests.sh --integration-only
            ;;

        security)
            echo "${BLUE}Running security tests...${NC}"
            ./run-all-tests.sh --security-only
            ;;

        errors)
            echo "${BLUE}Running error handling tests...${NC}"
            ./run-all-tests.sh --errors-only
            ;;

        common)
            echo "${BLUE}Running common.sh tests...${NC}"
            bats unit/test_common.bats
            ;;

        loader)
            echo "${BLUE}Running module-loader.sh tests...${NC}"
            bats unit/test_module_loader.bats
            ;;

        generator)
            echo "${BLUE}Running config-generator.sh tests...${NC}"
            bats unit/test_config_generator.bats
            ;;

        fast)
            echo "${BLUE}Running fast tests (unit + security)...${NC}"
            bats unit/ security/
            ;;

        slow)
            echo "${BLUE}Running slow tests (integration)...${NC}"
            bats integration/
            ;;

        check)
            echo "${BLUE}Quick health check...${NC}"
            echo "Running subset of critical tests..."

            # Run a few key tests from each category
            bats unit/test_common.bats::*yaml_get* 2>/dev/null || bats unit/test_common.bats

            echo "${GREEN}✓ Health check passed${NC}"
            ;;

        watch)
            if ! command -v entr &>/dev/null; then
                echo "${RED}ERROR: 'entr' not installed${NC}"
                echo "Install with: sudo apt-get install entr"
                exit 1
            fi

            echo "${BLUE}Watching for changes...${NC}"
            echo "Press Ctrl+C to stop"

            find ../scripts ../modules -name "*.sh" | entr -c ./run-all-tests.sh --unit-only
            ;;

        setup)
            echo "${BLUE}Setting up test environment...${NC}"
            ./setup.sh
            ;;

        clean)
            echo "${BLUE}Cleaning test artifacts...${NC}"
            rm -rf /tmp/observability-stack-tests
            echo "${GREEN}✓ Cleaned${NC}"
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            echo "${RED}Unknown command: $cmd${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Main
if [[ $# -eq 0 ]]; then
    run_command "all"
else
    run_command "$1"
fi
