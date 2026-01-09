#!/usr/bin/env bash
# VPSManager Validation Function Unit Tests
# Tests validation functions without requiring full environment
#
# Usage: ./test-validation.sh

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

VPSMANAGER_ROOT="${VPSMANAGER_ROOT:-/opt/vpsmanager}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ============================================================================
# Color output helpers
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
}

print_test() {
    echo -e "\n${BOLD}${BLUE}[TEST $((TESTS_TOTAL + 1))]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

print_error() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ INFO:${NC} $1"
}

# ============================================================================
# Test tracking
# ============================================================================

pass_test() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    print_success "$1"
}

fail_test() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    print_error "$1"
}

# ============================================================================
# Load validation functions
# ============================================================================

load_validation_lib() {
    if [[ ! -f "${VPSMANAGER_ROOT}/lib/core/validation.sh" ]]; then
        echo -e "${RED}ERROR: validation.sh not found at ${VPSMANAGER_ROOT}/lib/core/validation.sh${NC}"
        exit 1
    fi

    # Load validation library
    # shellcheck source=/dev/null
    source "${VPSMANAGER_ROOT}/lib/core/validation.sh"

    print_success "Loaded validation library"
}

# ============================================================================
# Test Functions
# ============================================================================

test_01_validate_valid_domains() {
    print_test "Validate valid domain names"

    local valid_domains=(
        "example.com"
        "test.example.com"
        "sub.domain.example.com"
        "site-with-dash.com"
        "123numeric.com"
        "a.co"
    )

    local success=true

    for domain in "${valid_domains[@]}"; do
        if validate_domain "$domain" &>/dev/null; then
            print_info "✓ '$domain' is valid"
        else
            print_error "✗ '$domain' should be valid but was rejected"
            success=false
        fi
    done

    if [[ "$success" == "true" ]]; then
        pass_test "All valid domains accepted"
    else
        fail_test "Some valid domains were rejected"
    fi
}

test_02_validate_invalid_domains() {
    print_test "Reject invalid domain names"

    local invalid_domains=(
        ""                          # empty
        "no-tld"                    # no TLD
        "invalid_underscore.com"    # underscore
        "space domain.com"          # space
        "semicolon;.com"            # semicolon
        "pipe|.com"                 # pipe
        "backtick\`.com"            # backtick
        "-startswithdash.com"       # starts with dash
        ".startswithperiod.com"     # starts with period
    )

    local success=true

    for domain in "${invalid_domains[@]}"; do
        if validate_domain "$domain" &>/dev/null; then
            print_error "✗ '$domain' should be invalid but was accepted"
            success=false
        else
            print_info "✓ '$domain' correctly rejected"
        fi
    done

    if [[ "$success" == "true" ]]; then
        pass_test "All invalid domains rejected"
    else
        fail_test "Some invalid domains were accepted"
    fi
}

test_03_validate_site_types() {
    print_test "Validate site types"

    local valid_types=("wordpress" "laravel" "html" "php")
    local invalid_types=("drupal" "joomla" "" "WordPress" "PHP")

    local success=true

    # Test valid types
    for type in "${valid_types[@]}"; do
        if validate_site_type "$type" &>/dev/null; then
            print_info "✓ '$type' is valid"
        else
            print_error "✗ '$type' should be valid but was rejected"
            success=false
        fi
    done

    # Test invalid types
    for type in "${invalid_types[@]}"; do
        if validate_site_type "$type" &>/dev/null; then
            print_error "✗ '$type' should be invalid but was accepted"
            success=false
        else
            print_info "✓ '$type' correctly rejected"
        fi
    done

    if [[ "$success" == "true" ]]; then
        pass_test "Site type validation working correctly"
    else
        fail_test "Site type validation issues"
    fi
}

test_04_validate_php_versions() {
    print_test "Validate PHP versions"

    local valid_versions=("8.2" "8.3" "8.4")
    local invalid_versions=("7.4" "8.1" "9.0" "8" "8.2.0" "")

    local success=true

    # Test valid versions
    for version in "${valid_versions[@]}"; do
        if validate_php_version "$version" &>/dev/null; then
            print_info "✓ '$version' is valid"
        else
            print_error "✗ '$version' should be valid but was rejected"
            success=false
        fi
    done

    # Test invalid versions
    for version in "${invalid_versions[@]}"; do
        if validate_php_version "$version" &>/dev/null; then
            print_error "✗ '$version' should be invalid but was accepted"
            success=false
        else
            print_info "✓ '$version' correctly rejected"
        fi
    done

    if [[ "$success" == "true" ]]; then
        pass_test "PHP version validation working correctly"
    else
        fail_test "PHP version validation issues"
    fi
}

test_05_domain_to_dirname() {
    print_test "Convert domains to safe directory names"

    local tests=(
        "example.com:example_com"
        "sub.domain.com:sub_domain_com"
        "test-site.com:test-site_com"
    )

    local success=true

    for test in "${tests[@]}"; do
        local input="${test%%:*}"
        local expected="${test##*:}"
        local result
        result=$(domain_to_dirname "$input")

        if [[ "$result" == "$expected" ]]; then
            print_info "✓ '$input' -> '$result'"
        else
            print_error "✗ '$input' -> '$result' (expected '$expected')"
            success=false
        fi
    done

    if [[ "$success" == "true" ]]; then
        pass_test "Domain to dirname conversion working correctly"
    else
        fail_test "Domain to dirname conversion issues"
    fi
}

test_06_domain_to_dbname() {
    print_test "Convert domains to safe database names"

    local tests=(
        "example.com:example_com"
        "sub.domain.com:sub_domain_com"
        "test-site.com:test_site_com"
    )

    local success=true

    for test in "${tests[@]}"; do
        local input="${test%%:*}"
        local expected="${test##*:}"
        local result
        result=$(domain_to_dbname "$input")

        if [[ "$result" == "$expected" ]]; then
            print_info "✓ '$input' -> '$result'"
        else
            print_error "✗ '$input' -> '$result' (expected '$expected')"
            success=false
        fi
    done

    # Test truncation (max 60 chars)
    local long_domain="very-long-subdomain-name-that-exceeds-the-maximum-length-allowed.example.com"
    local result
    result=$(domain_to_dbname "$long_domain")
    local length=${#result}

    if [[ $length -le 60 ]]; then
        print_info "✓ Long domain truncated to $length chars (max 60)"
    else
        print_error "✗ Long domain not truncated: $length chars (expected ≤60)"
        success=false
    fi

    if [[ "$success" == "true" ]]; then
        pass_test "Domain to database name conversion working correctly"
    else
        fail_test "Domain to database name conversion issues"
    fi
}

test_07_sanitize_string() {
    print_test "Sanitize strings for safe use"

    local tests=(
        "normal:normal"
        "with spaces:withspaces"
        "special!@#chars:specialchars"
        "dots.and-dashes:dots.and-dashes"
        "under_scores:under_scores"
    )

    local success=true

    for test in "${tests[@]}"; do
        local input="${test%%:*}"
        local expected="${test##*:}"
        local result
        result=$(sanitize_string "$input")

        if [[ "$result" == "$expected" ]]; then
            print_info "✓ '$input' -> '$result'"
        else
            print_error "✗ '$input' -> '$result' (expected '$expected')"
            success=false
        fi
    done

    if [[ "$success" == "true" ]]; then
        pass_test "String sanitization working correctly"
    else
        fail_test "String sanitization issues"
    fi
}

# ============================================================================
# Main test runner
# ============================================================================

main() {
    print_header "VPSManager Validation Function Unit Tests"
    echo -e "${BOLD}Testing validation functions in isolation${NC}\n"

    load_validation_lib
    echo ""

    print_header "Running Tests"

    test_01_validate_valid_domains
    test_02_validate_invalid_domains
    test_03_validate_site_types
    test_04_validate_php_versions
    test_05_domain_to_dirname
    test_06_domain_to_dbname
    test_07_sanitize_string

    # Print summary
    print_header "Test Summary"
    echo -e "${BOLD}Total Tests:${NC} $TESTS_TOTAL"
    echo -e "${GREEN}${BOLD}Passed:${NC} $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}${BOLD}Failed:${NC} $TESTS_FAILED"
    else
        echo -e "${GREEN}${BOLD}Failed:${NC} 0"
    fi

    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        exit 1
    fi
}

# Run main
main "$@"
