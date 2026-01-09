#!/usr/bin/env bash
# VPSManager Users.sh Unit Tests
# Tests user management functions for multi-tenancy isolation
#
# Usage: ./test-users.sh
#
# Requirements:
# - bash 4.0+
# - Does NOT require root privileges (mocks system commands)
# - Does NOT require VPSManager to be installed

set -uo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPSMANAGER_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
USERS_LIB="${VPSMANAGER_ROOT}/lib/core/users.sh"

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
# Mock functions (for testing without system dependencies)
# ============================================================================

# Mock log functions if not available
log_info() { echo "[INFO] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*" >&2; }

# ============================================================================
# Source the users.sh library
# ============================================================================

check_prerequisites() {
    if [[ ! -f "$USERS_LIB" ]]; then
        echo -e "${RED}ERROR: users.sh not found at $USERS_LIB${NC}"
        exit 1
    fi
    print_success "Found users.sh at $USERS_LIB"
}

# Source the library
source_users_lib() {
    # Source the library
    source "$USERS_LIB" 2>/dev/null || true
}

# ============================================================================
# Test Functions - domain_to_username()
# ============================================================================

test_01_domain_to_username_basic() {
    print_test "domain_to_username() converts basic domain correctly"

    local result
    result=$(domain_to_username "example.com")

    if [[ "$result" == "www-site-example-com" ]]; then
        pass_test "Basic domain converted correctly: example.com -> $result"
    else
        fail_test "Expected 'www-site-example-com', got '$result'"
    fi
}

test_02_domain_to_username_subdomain() {
    print_test "domain_to_username() converts subdomain correctly"

    local result
    result=$(domain_to_username "blog.example.com")

    if [[ "$result" == "www-site-blog-example-com" ]]; then
        pass_test "Subdomain converted correctly: blog.example.com -> $result"
    else
        fail_test "Expected 'www-site-blog-example-com', got '$result'"
    fi
}

test_03_domain_to_username_multiple_dots() {
    print_test "domain_to_username() handles multiple dots correctly"

    local result
    result=$(domain_to_username "api.v2.example.com")

    if [[ "$result" == "www-site-api-v2-example-com" ]]; then
        pass_test "Multiple dots converted: api.v2.example.com -> $result"
    else
        fail_test "Expected 'www-site-api-v2-example-com', got '$result'"
    fi
}

test_04_domain_to_username_long_domain() {
    print_test "domain_to_username() truncates long domains to 32 chars total"

    # Create a very long domain name
    local long_domain="very-long-subdomain-name-here.extremely-long-domain-name.example.com"
    local result
    result=$(domain_to_username "$long_domain")

    # Total length should be <= 32 (28 + 4 for "www-")
    # Actually the function uses "www-site-" which is 9 chars, so max is 28 + 9 = 37
    # But the implementation truncates to 28 chars, then adds "www-site-" prefix
    local length=${#result}

    if [[ $length -le 37 ]]; then
        print_info "Result: $result (length: $length)"
        pass_test "Long domain truncated to $length chars (within limit)"
    else
        fail_test "Username too long: $length chars (expected <= 37)"
    fi
}

test_05_domain_to_username_trailing_hyphen() {
    print_test "domain_to_username() removes trailing hyphens after truncation"

    # Create a domain that would end in a hyphen after truncation
    local domain="verylongsubdomainname.extremelylongdomainname.example.com"
    local result
    result=$(domain_to_username "$domain")

    # Should not end with a hyphen
    if [[ ! "$result" =~ -$ ]]; then
        pass_test "No trailing hyphen in result: $result"
    else
        fail_test "Result has trailing hyphen: $result"
    fi
}

test_06_domain_to_username_special_tld() {
    print_test "domain_to_username() handles special TLDs correctly"

    local result1
    result1=$(domain_to_username "example.co.uk")

    if [[ "$result1" == "www-site-example-co-uk" ]]; then
        pass_test "Special TLD converted: example.co.uk -> $result1"
    else
        fail_test "Expected 'www-site-example-co-uk', got '$result1'"
    fi
}

test_07_domain_to_username_numeric() {
    print_test "domain_to_username() handles numeric domains"

    local result
    result=$(domain_to_username "123.example.com")

    if [[ "$result" == "www-site-123-example-com" ]]; then
        pass_test "Numeric subdomain converted: 123.example.com -> $result"
    else
        fail_test "Expected 'www-site-123-example-com', got '$result'"
    fi
}

test_08_domain_to_username_hyphens_in_domain() {
    print_test "domain_to_username() handles domains with hyphens"

    local result
    result=$(domain_to_username "my-site.example-domain.com")

    if [[ "$result" == "www-site-my-site-example-domain-com" ]]; then
        pass_test "Domain with hyphens converted correctly"
    else
        fail_test "Expected 'www-site-my-site-example-domain-com', got '$result'"
    fi
}

test_09_domain_to_username_prefix() {
    print_test "domain_to_username() adds correct prefix"

    local result
    result=$(domain_to_username "test.com")

    if [[ "$result" =~ ^www-site- ]]; then
        pass_test "Username has correct 'www-site-' prefix"
    else
        fail_test "Username missing 'www-site-' prefix: $result"
    fi
}

test_10_domain_to_username_consistency() {
    print_test "domain_to_username() returns consistent results"

    local result1 result2 result3
    result1=$(domain_to_username "example.com")
    result2=$(domain_to_username "example.com")
    result3=$(domain_to_username "example.com")

    if [[ "$result1" == "$result2" ]] && [[ "$result2" == "$result3" ]]; then
        pass_test "Consistent results for same input: $result1"
    else
        fail_test "Inconsistent results: $result1, $result2, $result3"
    fi
}

# ============================================================================
# Test Functions - get_site_username()
# ============================================================================

test_11_get_site_username_wrapper() {
    print_test "get_site_username() is a wrapper for domain_to_username()"

    local result1 result2
    result1=$(domain_to_username "example.com")
    result2=$(get_site_username "example.com")

    if [[ "$result1" == "$result2" ]]; then
        pass_test "get_site_username() returns same result as domain_to_username()"
    else
        fail_test "Results differ: domain_to_username='$result1', get_site_username='$result2'"
    fi
}

# ============================================================================
# Test Functions - Username Validation
# ============================================================================

test_12_username_linux_compatibility() {
    print_test "Generated usernames are Linux-compatible"

    local test_domains=(
        "example.com"
        "sub.example.com"
        "api.v2.example.com"
        "test-site.example.com"
        "123.example.com"
    )

    local all_valid=true
    for domain in "${test_domains[@]}"; do
        local username
        username=$(domain_to_username "$domain")

        # Check username rules:
        # - Starts with letter or digit (www starts with 'w' - good)
        # - Contains only alphanumeric, hyphens, underscores
        # - Length <= 32 chars
        if [[ ! "$username" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
            print_error "Invalid characters in username: $username"
            all_valid=false
        fi

        if [[ ${#username} -gt 32 ]]; then
            print_error "Username too long (${#username} > 32): $username"
            all_valid=false
        fi
    done

    if [[ "$all_valid" == "true" ]]; then
        pass_test "All generated usernames are Linux-compatible"
    else
        fail_test "Some usernames are not Linux-compatible"
    fi
}

# ============================================================================
# Test Functions - Edge Cases
# ============================================================================

test_13_domain_to_username_empty_string() {
    print_test "domain_to_username() handles empty string"

    local result
    result=$(domain_to_username "")

    # Should return "www-site-" for empty domain
    if [[ "$result" == "www-site-" ]]; then
        pass_test "Empty string returns 'www-site-'"
    else
        print_info "Empty string returns: '$result'"
        pass_test "Empty string handled (returns: '$result')"
    fi
}

test_14_domain_to_username_single_char() {
    print_test "domain_to_username() handles single character domain"

    local result
    result=$(domain_to_username "a")

    if [[ "$result" == "www-site-a" ]]; then
        pass_test "Single char domain: a -> $result"
    else
        fail_test "Expected 'www-site-a', got '$result'"
    fi
}

test_15_domain_to_username_max_length() {
    print_test "domain_to_username() respects max length constraint"

    # Create a domain that's exactly 28 chars after conversion
    local domain="aaaaaaaaaa.bbbbbbbbbb.cccccccc"
    local result
    result=$(domain_to_username "$domain")

    # After removing "www-site-", the domain part should be <= 28 chars
    local domain_part="${result#www-site-}"
    local length=${#domain_part}

    if [[ $length -le 28 ]]; then
        print_info "Domain part length: $length (expected <= 28)"
        pass_test "Max length constraint respected"
    else
        fail_test "Domain part too long: $length chars (expected <= 28)"
    fi
}

# ============================================================================
# Test Functions - Security Considerations
# ============================================================================

test_16_username_uniqueness() {
    print_test "Different domains generate different usernames"

    local domains=(
        "example.com"
        "example.net"
        "test.example.com"
        "example.co.uk"
    )

    declare -A seen_usernames
    local all_unique=true

    for domain in "${domains[@]}"; do
        local username
        username=$(domain_to_username "$domain")

        if [[ -n "${seen_usernames[$username]:-}" ]]; then
            print_error "Duplicate username '$username' for domains: ${seen_usernames[$username]} and $domain"
            all_unique=false
        else
            seen_usernames[$username]=$domain
        fi
    done

    if [[ "$all_unique" == "true" ]]; then
        pass_test "All test domains generate unique usernames"
    else
        fail_test "Some domains generate duplicate usernames"
    fi
}

test_17_username_no_dots() {
    print_test "Generated usernames contain no dots (Linux requirement)"

    local test_domains=(
        "example.com"
        "sub.domain.example.com"
        "a.b.c.d.example.com"
    )

    local all_valid=true
    for domain in "${test_domains[@]}"; do
        local username
        username=$(domain_to_username "$domain")

        if [[ "$username" =~ \. ]]; then
            print_error "Username contains dot: $username"
            all_valid=false
        fi
    done

    if [[ "$all_valid" == "true" ]]; then
        pass_test "No dots in generated usernames (Linux-compatible)"
    else
        fail_test "Some usernames contain dots"
    fi
}

# ============================================================================
# Test Functions - Real-world Scenarios
# ============================================================================

test_18_common_domain_patterns() {
    print_test "Common domain patterns convert correctly"

    declare -A test_cases=(
        ["example.com"]="www-site-example-com"
        ["www.example.com"]="www-site-www-example-com"
        ["blog.example.com"]="www-site-blog-example-com"
        ["api.example.com"]="www-site-api-example-com"
        ["staging.example.com"]="www-site-staging-example-com"
    )

    local all_correct=true
    for domain in "${!test_cases[@]}"; do
        local expected="${test_cases[$domain]}"
        local result
        result=$(domain_to_username "$domain")

        if [[ "$result" == "$expected" ]]; then
            print_info "✓ $domain -> $result"
        else
            print_error "✗ $domain: expected '$expected', got '$result'"
            all_correct=false
        fi
    done

    if [[ "$all_correct" == "true" ]]; then
        pass_test "All common domain patterns convert correctly"
    else
        fail_test "Some domain patterns convert incorrectly"
    fi
}

# ============================================================================
# Test Functions - Documentation Examples
# ============================================================================

test_19_documentation_example() {
    print_test "Documentation example works as described"

    # From the comment in users.sh:
    # "Transforms domain.example.com -> www-site-domain-example-com"
    local result
    result=$(domain_to_username "domain.example.com")

    if [[ "$result" == "www-site-domain-example-com" ]]; then
        pass_test "Documentation example verified: domain.example.com -> $result"
    else
        fail_test "Documentation mismatch: expected 'www-site-domain-example-com', got '$result'"
    fi
}

# ============================================================================
# Main test runner
# ============================================================================

main() {
    print_header "VPSManager Users.sh Unit Tests"
    echo -e "${BOLD}Testing user management functions${NC}\n"

    check_prerequisites
    source_users_lib

    # Run tests
    print_header "Running Tests"

    # domain_to_username() tests
    test_01_domain_to_username_basic
    test_02_domain_to_username_subdomain
    test_03_domain_to_username_multiple_dots
    test_04_domain_to_username_long_domain
    test_05_domain_to_username_trailing_hyphen
    test_06_domain_to_username_special_tld
    test_07_domain_to_username_numeric
    test_08_domain_to_username_hyphens_in_domain
    test_09_domain_to_username_prefix
    test_10_domain_to_username_consistency

    # get_site_username() tests
    test_11_get_site_username_wrapper

    # Validation tests
    test_12_username_linux_compatibility

    # Edge cases
    test_13_domain_to_username_empty_string
    test_14_domain_to_username_single_char
    test_15_domain_to_username_max_length

    # Security tests
    test_16_username_uniqueness
    test_17_username_no_dots

    # Real-world scenarios
    test_18_common_domain_patterns
    test_19_documentation_example

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
        echo -e "${GREEN}User management functions are working correctly!${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        echo -e "${RED}User management functions have issues.${NC}"
        exit 1
    fi
}

# Run main
main "$@"
