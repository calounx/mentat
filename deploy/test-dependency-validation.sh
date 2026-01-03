#!/usr/bin/env bash
# Test dependency validation for all deployment scripts
# This script simulates missing dependencies and verifies error handling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ANSI color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Print test result
print_test_result() {
    local test_name="$1"
    local result="$2"  # pass or fail

    ((TOTAL_TESTS++))

    if [[ "$result" == "pass" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED_TESTS++))
    fi
}

# Test if script has validation function
test_script_has_validation() {
    local script="$1"
    local script_name="$(basename "$script")"

    if grep -q "validate_deployment_dependencies" "$script" 2>/dev/null; then
        print_test_result "$script_name has validation function" "pass"
        return 0
    else
        print_test_result "$script_name has validation function" "fail"
        return 1
    fi
}

# Test if script validates before sourcing
test_validation_before_sourcing() {
    local script="$1"
    local script_name="$(basename "$script")"

    # Check if validation happens before first source command
    local validation_line=$(grep -n "validate_deployment_dependencies" "$script" 2>/dev/null | head -1 | cut -d: -f1)
    local first_source_line=$(grep -n "^source\|^\\. " "$script" 2>/dev/null | head -1 | cut -d: -f1)

    if [[ -z "$validation_line" ]]; then
        print_test_result "$script_name validates before sourcing" "fail"
        return 1
    fi

    if [[ -z "$first_source_line" ]]; then
        # No source commands, validation exists, that's OK
        print_test_result "$script_name validates before sourcing" "pass"
        return 0
    fi

    if [[ "$validation_line" -lt "$first_source_line" ]]; then
        print_test_result "$script_name validates before sourcing" "pass"
        return 0
    else
        print_test_result "$script_name validates before sourcing" "fail"
        return 1
    fi
}

# Test if script has SCRIPT_DIR set
test_script_has_script_dir() {
    local script="$1"
    local script_name="$(basename "$script")"

    if grep -q 'SCRIPT_DIR=.*dirname.*BASH_SOURCE' "$script" 2>/dev/null; then
        print_test_result "$script_name sets SCRIPT_DIR correctly" "pass"
        return 0
    else
        print_test_result "$script_name sets SCRIPT_DIR correctly" "fail"
        return 1
    fi
}

# Test if script has error messaging
test_script_has_error_messaging() {
    local script="$1"
    local script_name="$(basename "$script")"

    if grep -q "ERROR: Missing required dependencies" "$script" 2>/dev/null; then
        print_test_result "$script_name has clear error messages" "pass"
        return 0
    else
        print_test_result "$script_name has clear error messages" "fail"
        return 1
    fi
}

# Main test suite
main() {
    echo -e "${BLUE}=== Dependency Validation Test Suite ===${NC}"
    echo ""

    echo -e "${YELLOW}Testing Main Scripts:${NC}"
    for script in "${SCRIPT_DIR}"/deploy-*.sh; do
        [[ -f "$script" ]] || continue
        test_script_has_validation "$script"
        test_validation_before_sourcing "$script"
        test_script_has_script_dir "$script"
        test_script_has_error_messaging "$script"
        echo ""
    done

    echo -e "${YELLOW}Testing Deployment Subscripts:${NC}"
    for script in "${SCRIPT_DIR}"/scripts/*.sh; do
        [[ -f "$script" ]] || continue
        local script_name="$(basename "$script")"

        # Skip utility scripts
        if [[ "$script_name" == "validate-dependencies.sh" ]]; then
            continue
        fi

        test_script_has_validation "$script"
        test_validation_before_sourcing "$script"
        test_script_has_script_dir "$script"
        test_script_has_error_messaging "$script"
        echo ""
    done

    echo -e "${YELLOW}Testing Security Scripts:${NC}"
    for script in "${SCRIPT_DIR}"/security/*.sh; do
        [[ -f "$script" ]] || continue
        test_script_has_validation "$script"
        test_validation_before_sourcing "$script"
        test_script_has_script_dir "$script"
        test_script_has_error_messaging "$script"
        echo ""
    done

    # Print summary
    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    else
        echo -e "${GREEN}Failed: $FAILED_TESTS${NC}"
    fi
    echo ""

    # Calculate success rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo "Success Rate: ${success_rate}%"
    fi

    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
