#!/bin/bash
#===============================================================================
# Version Management System - Comprehensive Test Suite
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Source version management library
if [[ ! -f "$LIB_DIR/versions.sh" ]]; then
    echo -e "${RED}ERROR: Version management library not found${NC}"
    exit 1
fi

source "$LIB_DIR/versions.sh"

#===============================================================================
# TEST FRAMEWORK
#===============================================================================

test_start() {
    local test_name="$1"
    echo -n "Testing: $test_name ... "
    ((TESTS_RUN++))
}

test_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    local message="${1:-}"
    echo -e "${RED}FAIL${NC}"
    [[ -n "$message" ]] && echo "  Error: $message"
    ((TESTS_FAILED++))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        [[ -z "$message" ]] && message="Expected '$expected', got '$actual'"
        echo "  $message"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value is empty}"

    if [[ -n "$value" ]]; then
        return 0
    else
        echo "  $message"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" -eq "$actual" ]]; then
        return 0
    else
        [[ -z "$message" ]] && message="Expected exit code $expected, got $actual"
        echo "  $message"
        return 1
    fi
}

#===============================================================================
# VERSION VALIDATION TESTS
#===============================================================================

test_version_validation() {
    test_start "Version validation - valid versions"

    local valid_versions=(
        "1.0.0"
        "1.2.3"
        "10.20.30"
        "1.0.0-alpha"
        "1.0.0-beta.1"
        "1.0.0+build123"
        "1.0.0-rc.1+build456"
    )

    local all_valid=true
    for version in "${valid_versions[@]}"; do
        if ! validate_version "$version" 2>/dev/null; then
            assert_equals "valid" "invalid" "Version $version should be valid"
            all_valid=false
        fi
    done

    if $all_valid; then
        test_pass
    else
        test_fail
    fi
}

test_version_validation_invalid() {
    test_start "Version validation - invalid versions"

    local invalid_versions=(
        "1.0"
        "1"
        "abc"
        "1.2.x"
        ""
    )

    local all_invalid=true
    for version in "${invalid_versions[@]}"; do
        if validate_version "$version" 2>/dev/null; then
            assert_equals "invalid" "valid" "Version '$version' should be invalid"
            all_invalid=false
        fi
    done

    if $all_invalid; then
        test_pass
    else
        test_fail
    fi
}

#===============================================================================
# VERSION COMPARISON TESTS
#===============================================================================

test_version_comparison_greater() {
    test_start "Version comparison - greater than"

    local result
    result=$(compare_versions "2.0.0" "1.0.0" 2>/dev/null)

    if assert_equals "1" "$result"; then
        test_pass
    else
        test_fail
    fi
}

test_version_comparison_less() {
    test_start "Version comparison - less than"

    local result
    result=$(compare_versions "1.0.0" "2.0.0" 2>/dev/null)

    if assert_equals "-1" "$result"; then
        test_pass
    else
        test_fail
    fi
}

test_version_comparison_equal() {
    test_start "Version comparison - equal"

    local result
    result=$(compare_versions "1.5.0" "1.5.0" 2>/dev/null)

    if assert_equals "0" "$result"; then
        test_pass
    else
        test_fail
    fi
}

test_version_comparison_complex() {
    test_start "Version comparison - complex cases"

    local tests_passed=0
    local tests_total=5

    # 1.8.0 > 1.7.9
    if [[ $(compare_versions "1.8.0" "1.7.9" 2>/dev/null) -eq 1 ]]; then
        ((tests_passed++))
    fi

    # 2.0.0 > 1.99.99
    if [[ $(compare_versions "2.0.0" "1.99.99" 2>/dev/null) -eq 1 ]]; then
        ((tests_passed++))
    fi

    # 1.0.1 > 1.0.0
    if [[ $(compare_versions "1.0.1" "1.0.0" 2>/dev/null) -eq 1 ]]; then
        ((tests_passed++))
    fi

    # 1.0.0 > 1.0.0-beta
    if [[ $(compare_versions "1.0.0" "1.0.0-beta" 2>/dev/null) -eq 1 ]]; then
        ((tests_passed++))
    fi

    # 1.0.0-beta.2 > 1.0.0-beta.1
    if [[ $(compare_versions "1.0.0-beta.2" "1.0.0-beta.1" 2>/dev/null) -eq 1 ]]; then
        ((tests_passed++))
    fi

    if [[ $tests_passed -eq $tests_total ]]; then
        test_pass
    else
        test_fail "Only $tests_passed/$tests_total comparison tests passed"
    fi
}

#===============================================================================
# VERSION CONSTRAINTS TESTS
#===============================================================================

test_version_satisfies() {
    test_start "Version constraints - satisfies"

    local tests_passed=0
    local tests_total=6

    # Test various constraints
    version_satisfies "1.8.0" ">=1.7.0" 2>/dev/null && ((tests_passed++))
    version_satisfies "1.7.0" "<=1.8.0" 2>/dev/null && ((tests_passed++))
    version_satisfies "2.0.0" ">1.9.0" 2>/dev/null && ((tests_passed++))
    version_satisfies "1.5.0" "<2.0.0" 2>/dev/null && ((tests_passed++))
    version_satisfies "1.7.0" "=1.7.0" 2>/dev/null && ((tests_passed++))
    version_satisfies "1.7.0" "1.7.0" 2>/dev/null && ((tests_passed++))

    if [[ $tests_passed -eq $tests_total ]]; then
        test_pass
    else
        test_fail "Only $tests_passed/$tests_total constraint tests passed"
    fi
}

test_version_range() {
    test_start "Version range - in range"

    if version_in_range "1.8.0" ">=1.7.0 <2.0.0" 2>/dev/null; then
        test_pass
    else
        test_fail
    fi
}

test_version_range_out() {
    test_start "Version range - out of range"

    if ! version_in_range "2.0.0" ">=1.7.0 <2.0.0" 2>/dev/null; then
        test_pass
    else
        test_fail
    fi
}

#===============================================================================
# CACHE TESTS
#===============================================================================

test_cache_set_get() {
    test_start "Cache - set and get"

    local test_component="test_component_$$"
    local test_key="test_key"
    local test_value="test_value_123"

    cache_set "$test_component" "$test_key" "$test_value"

    local retrieved
    retrieved=$(cache_get "$test_component" "$test_key" 2>/dev/null)

    # Cleanup
    cache_invalidate "$test_component" 2>/dev/null

    if assert_equals "$test_value" "$retrieved"; then
        test_pass
    else
        test_fail
    fi
}

test_cache_invalidate() {
    test_start "Cache - invalidate"

    local test_component="test_component_invalidate_$$"
    local test_key="test_key"
    local test_value="test_value"

    cache_set "$test_component" "$test_key" "$test_value"
    cache_invalidate "$test_component" 2>/dev/null

    local retrieved
    if retrieved=$(cache_get "$test_component" "$test_key" 2>/dev/null); then
        test_fail "Cache should be empty after invalidation"
    else
        test_pass
    fi
}

#===============================================================================
# VERSION RESOLUTION TESTS
#===============================================================================

test_resolve_version_env_override() {
    test_start "Version resolution - environment override"

    export VERSION_OVERRIDE_NODE_EXPORTER="9.9.9"

    local version
    version=$(resolve_version "node_exporter" 2>/dev/null)

    unset VERSION_OVERRIDE_NODE_EXPORTER

    if assert_equals "9.9.9" "$version"; then
        test_pass
    else
        test_fail
    fi
}

test_resolve_version_fallback() {
    test_start "Version resolution - fallback to manifest"

    # Use offline mode to skip GitHub API
    local old_offline="${VERSION_OFFLINE_MODE:-}"
    export VERSION_OFFLINE_MODE=true

    local version
    version=$(resolve_version "node_exporter" 2>/dev/null)

    export VERSION_OFFLINE_MODE="$old_offline"

    if assert_not_empty "$version" "Should resolve to a version"; then
        test_pass
    else
        test_fail
    fi
}

test_get_manifest_version() {
    test_start "Get manifest version"

    cd "$PROJECT_ROOT"

    local version
    version=$(get_manifest_version "node_exporter" 2>/dev/null)

    if assert_not_empty "$version" "Should get version from manifest"; then
        test_pass
    else
        test_fail
    fi
}

#===============================================================================
# GITHUB API TESTS (optional - requires internet)
#===============================================================================

test_github_latest_release() {
    test_start "GitHub API - fetch latest release"

    # Skip if offline mode
    if [[ "${VERSION_OFFLINE_MODE:-false}" == "true" ]]; then
        echo -e "${YELLOW}SKIP (offline mode)${NC}"
        return
    fi

    local release_json
    if release_json=$(github_latest_release "prometheus/node_exporter" 2>/dev/null); then
        if assert_not_empty "$release_json" "Should get release JSON"; then
            test_pass
        else
            test_fail
        fi
    else
        echo -e "${YELLOW}SKIP (GitHub API unavailable)${NC}"
    fi
}

test_github_extract_version() {
    test_start "GitHub API - extract version from JSON"

    local mock_json='{"tag_name": "v1.7.0", "name": "Release 1.7.0"}'

    local version
    version=$(github_extract_version "$mock_json" 2>/dev/null)

    if assert_equals "1.7.0" "$version"; then
        test_pass
    else
        test_fail
    fi
}

test_get_latest_version() {
    test_start "Get latest version from GitHub"

    # Skip if offline mode
    if [[ "${VERSION_OFFLINE_MODE:-false}" == "true" ]]; then
        echo -e "${YELLOW}SKIP (offline mode)${NC}"
        return
    fi

    local version
    if version=$(get_latest_version "node_exporter" 2>/dev/null); then
        if validate_version "$version" 2>/dev/null; then
            test_pass
        else
            test_fail "Got invalid version: $version"
        fi
    else
        echo -e "${YELLOW}SKIP (GitHub API unavailable)${NC}"
    fi
}

#===============================================================================
# INTEGRATION TESTS
#===============================================================================

test_full_version_workflow() {
    test_start "Full version workflow"

    cd "$PROJECT_ROOT"

    local component="node_exporter"
    local success=true

    # 1. Resolve version
    local version
    if ! version=$(resolve_version "$component" 2>/dev/null); then
        success=false
        echo "  Failed to resolve version"
    fi

    # 2. Validate version
    if ! validate_version "$version" 2>/dev/null; then
        success=false
        echo "  Invalid version format: $version"
    fi

    # 3. Check compatibility
    if ! is_version_compatible "$component" "$version" 2>/dev/null; then
        success=false
        echo "  Version not compatible"
    fi

    if $success; then
        test_pass
    else
        test_fail
    fi
}

#===============================================================================
# MAIN TEST RUNNER
#===============================================================================

run_all_tests() {
    echo "==============================================================================="
    echo "Version Management System - Test Suite"
    echo "==============================================================================="
    echo ""

    # Version validation tests
    test_version_validation
    test_version_validation_invalid

    # Version comparison tests
    test_version_comparison_greater
    test_version_comparison_less
    test_version_comparison_equal
    test_version_comparison_complex

    # Version constraints tests
    test_version_satisfies
    test_version_range
    test_version_range_out

    # Cache tests
    test_cache_set_get
    test_cache_invalidate

    # Version resolution tests
    test_resolve_version_env_override
    test_resolve_version_fallback
    test_get_manifest_version

    # GitHub API tests (optional)
    test_github_latest_release
    test_github_extract_version
    test_get_latest_version

    # Integration tests
    test_full_version_workflow

    # Print summary
    echo ""
    echo "==============================================================================="
    echo "Test Summary"
    echo "==============================================================================="
    echo "Total tests run:    $TESTS_RUN"
    echo -e "Tests passed:       ${GREEN}$TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Tests failed:       ${RED}$TESTS_FAILED${NC}"
    else
        echo -e "Tests failed:       $TESTS_FAILED"
    fi
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
run_all_tests
