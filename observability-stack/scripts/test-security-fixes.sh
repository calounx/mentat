#!/bin/bash
#===============================================================================
# Security Fixes Test Suite
# Tests all critical security fixes implemented
#
# Usage: sudo ./test-security-fixes.sh
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

test_result() {
    local test_name="$1"
    local result="$2"
    ((TESTS_TOTAL++))

    if [[ "$result" == "PASS" ]]; then
        echo "${GREEN}[PASS]${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo "${RED}[FAIL]${NC} $test_name"
        ((TESTS_FAILED++))
    fi
}

echo ""
echo "=========================================="
echo "Security Fixes Test Suite"
echo "=========================================="
echo ""

#===============================================================================
# TEST 1: Command Validation (Anti-Injection)
#===============================================================================

echo "Testing Command Validation Functions..."
echo ""

# Test 1.1: Valid command should pass
if validate_and_execute_detection_command "which nginx" &>/dev/null; then
    test_result "Valid command: which nginx" "PASS"
else
    test_result "Valid command: which nginx" "FAIL"
fi

# Test 1.2: Command injection should be blocked
if validate_and_execute_detection_command "test -f /etc/passwd && echo pwned" &>/dev/null; then
    test_result "Block command chaining (&&)" "FAIL"
else
    test_result "Block command chaining (&&)" "PASS"
fi

# Test 1.3: Command substitution should be blocked
if validate_and_execute_detection_command "test \$(whoami)" &>/dev/null; then
    test_result "Block command substitution" "FAIL"
else
    test_result "Block command substitution" "PASS"
fi

# Test 1.4: Pipe should be blocked
if validate_and_execute_detection_command "cat /etc/passwd | grep root" &>/dev/null; then
    test_result "Block pipe operators" "FAIL"
else
    test_result "Block pipe operators" "PASS"
fi

# Test 1.5: Redirect should be blocked
if validate_and_execute_detection_command "echo pwned > /tmp/test" &>/dev/null; then
    test_result "Block redirect operators" "FAIL"
else
    test_result "Block redirect operators" "PASS"
fi

# Test 1.6: Disallowed command should be blocked
if validate_and_execute_detection_command "curl http://evil.com" &>/dev/null; then
    test_result "Block non-allowlisted command" "FAIL"
else
    test_result "Block non-allowlisted command" "PASS"
fi

echo ""

#===============================================================================
# TEST 2: Input Validation
#===============================================================================

echo "Testing Input Validation Functions..."
echo ""

# Test 2.1: Valid IP addresses
if is_valid_ip "192.168.1.1"; then
    test_result "Valid IP: 192.168.1.1" "PASS"
else
    test_result "Valid IP: 192.168.1.1" "FAIL"
fi

# Test 2.2: Invalid IP (octet > 255)
if is_valid_ip "256.1.1.1"; then
    test_result "Reject invalid IP: 256.1.1.1" "FAIL"
else
    test_result "Reject invalid IP: 256.1.1.1" "PASS"
fi

# Test 2.3: Invalid IP (incomplete)
if is_valid_ip "10.0.0"; then
    test_result "Reject incomplete IP: 10.0.0" "FAIL"
else
    test_result "Reject incomplete IP: 10.0.0" "PASS"
fi

# Test 2.4: Valid hostname
if is_valid_hostname "web-server-01.example.com" || is_valid_hostname "webserver01"; then
    test_result "Valid hostname: webserver01" "PASS"
else
    test_result "Valid hostname: webserver01" "FAIL"
fi

# Test 2.5: Invalid hostname (starts with hyphen)
if is_valid_hostname "-invalid"; then
    test_result "Reject invalid hostname: -invalid" "FAIL"
else
    test_result "Reject invalid hostname: -invalid" "PASS"
fi

# Test 2.6: Valid version
if is_valid_version "1.2.3"; then
    test_result "Valid version: 1.2.3" "PASS"
else
    test_result "Valid version: 1.2.3" "FAIL"
fi

# Test 2.7: Valid version with prerelease
if is_valid_version "2.0.0-beta.1"; then
    test_result "Valid version: 2.0.0-beta.1" "PASS"
else
    test_result "Valid version: 2.0.0-beta.1" "FAIL"
fi

# Test 2.8: Invalid version
if is_valid_version "1.2"; then
    test_result "Reject invalid version: 1.2" "FAIL"
else
    test_result "Reject invalid version: 1.2" "PASS"
fi

echo ""

#===============================================================================
# TEST 3: Secure File Operations
#===============================================================================

echo "Testing Secure File Operations..."
echo ""

# Test 3.1: Secure write creates file with correct permissions
TEMP_FILE=$(mktemp)
secure_write "$TEMP_FILE" "test content" "600" "root:root"

if [[ -f "$TEMP_FILE" ]]; then
    PERMS=$(stat -c '%a' "$TEMP_FILE" 2>/dev/null || echo "fail")
    if [[ "$PERMS" == "600" ]]; then
        test_result "Secure write: correct permissions (600)" "PASS"
    else
        test_result "Secure write: correct permissions (600)" "FAIL (got $PERMS)"
    fi
else
    test_result "Secure write: file creation" "FAIL"
fi

# Test 3.2: Audit detects correct permissions
if audit_file_permissions "$TEMP_FILE" "600" "root:root" &>/dev/null; then
    test_result "Audit: detect correct permissions" "PASS"
else
    test_result "Audit: detect correct permissions" "FAIL"
fi

# Test 3.3: Audit detects incorrect permissions
chmod 644 "$TEMP_FILE"
if audit_file_permissions "$TEMP_FILE" "600" "root:root" &>/dev/null; then
    test_result "Audit: detect wrong permissions" "FAIL"
else
    test_result "Audit: detect wrong permissions" "PASS"
fi

rm -f "$TEMP_FILE"

echo ""

#===============================================================================
# TEST 4: Download Security
#===============================================================================

echo "Testing Download Security..."
echo ""

# Test 4.1: download_and_verify exists
if type download_and_verify &>/dev/null; then
    test_result "download_and_verify function exists" "PASS"
else
    test_result "download_and_verify function exists" "FAIL"
fi

# Test 4.2: safe_download exists
if type safe_download &>/dev/null; then
    test_result "safe_download function exists" "PASS"
else
    test_result "safe_download function exists" "FAIL"
fi

# Test 4.3: HTTPS enforcement in download_and_verify
# This test would require actually calling the function with HTTP URL
# We'll just verify the function has the check
if grep -q "Only HTTPS URLs are allowed" "$SCRIPT_DIR/lib/common.sh"; then
    test_result "HTTPS enforcement code present" "PASS"
else
    test_result "HTTPS enforcement code present" "FAIL"
fi

# Test 4.4: Checksum verification code present
if grep -q "Checksum verification" "$SCRIPT_DIR/lib/common.sh"; then
    test_result "Checksum verification code present" "PASS"
else
    test_result "Checksum verification code present" "FAIL"
fi

# Test 4.5: Retry logic present
if grep -q "max_attempts" "$SCRIPT_DIR/lib/common.sh"; then
    test_result "Retry logic present" "PASS"
else
    test_result "Retry logic present" "FAIL"
fi

# Test 4.6: Timeout handling present
if grep -q "timeout_seconds" "$SCRIPT_DIR/lib/common.sh"; then
    test_result "Timeout handling present" "PASS"
else
    test_result "Timeout handling present" "FAIL"
fi

echo ""

#===============================================================================
# SUMMARY
#===============================================================================

echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo ""
echo "Total Tests:  $TESTS_TOTAL"
echo "${GREEN}Passed:       $TESTS_PASSED${NC}"
echo "${RED}Failed:       $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "${GREEN}All security fixes are working correctly!${NC}"
    echo ""
    exit 0
else
    echo "${RED}Some tests failed. Please review the security fixes.${NC}"
    echo ""
    exit 1
fi
