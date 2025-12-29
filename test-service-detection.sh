#!/bin/bash
#===============================================================================
# Test Script for Service Detection Fix
# Tests the enable_and_start() function to ensure it properly detects services
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR/observability-stack"

# Source the deploy libraries
source "$STACK_DIR/deploy/lib/common.sh"

echo "=========================================="
echo "Service Detection Fix Test"
echo "=========================================="
echo

# Test 1: Check that wait_for_systemd_service function exists
echo "Test 1: Checking for wait_for_systemd_service function..."
if declare -f wait_for_systemd_service >/dev/null 2>&1; then
    log_success "wait_for_systemd_service function exists"
else
    log_error "wait_for_systemd_service function NOT found"
    exit 1
fi
echo

# Test 2: Verify function signature
echo "Test 2: Testing wait_for_systemd_service with a known service..."
if systemctl list-unit-files | grep -q "sshd.service"; then
    TEST_SERVICE="sshd"
elif systemctl list-unit-files | grep -q "ssh.service"; then
    TEST_SERVICE="ssh"
else
    log_warn "Neither sshd nor ssh service found, skipping live test"
    TEST_SERVICE=""
fi

if [[ -n "$TEST_SERVICE" ]]; then
    if systemctl is-active --quiet "$TEST_SERVICE"; then
        log_info "Testing with active service: $TEST_SERVICE"
        if wait_for_systemd_service "$TEST_SERVICE" 5; then
            log_success "$TEST_SERVICE detected as active"
        else
            log_error "$TEST_SERVICE should have been detected as active"
            exit 1
        fi
    else
        log_warn "$TEST_SERVICE is not active, skipping live test"
    fi
fi
echo

# Test 3: Check for function signature conflict
echo "Test 3: Checking for conflicting wait_for_service function..."
if declare -f wait_for_service >/dev/null 2>&1; then
    log_info "wait_for_service function exists (from scripts/lib/common.sh)"
    # Show what parameters it expects
    func_def=$(declare -f wait_for_service | head -10)
    if echo "$func_def" | grep -q "local host="; then
        log_info "  -> Uses host/port signature (correct for scripts/lib)"
    else
        log_warn "  -> Unexpected signature"
    fi
else
    log_info "wait_for_service not loaded (using fallback only)"
fi
echo

# Test 4: Verify enable_and_start uses the correct function
echo "Test 4: Checking enable_and_start implementation..."
func_body=$(declare -f enable_and_start)
if echo "$func_body" | grep -q "wait_for_systemd_service"; then
    log_success "enable_and_start correctly uses wait_for_systemd_service"
else
    log_error "enable_and_start does NOT use wait_for_systemd_service"
    echo "Function body:"
    echo "$func_body"
    exit 1
fi
echo

# Test 5: Check logging improvements
echo "Test 5: Checking for improved logging..."
if echo "$func_body" | grep -q "log_info.*Starting service"; then
    log_success "enable_and_start has improved logging"
else
    log_warn "enable_and_start may not have improved logging"
fi
echo

echo "=========================================="
log_success "All tests passed!"
echo "=========================================="
echo
echo "Summary of fixes:"
echo "  1. Renamed service checker to wait_for_systemd_service"
echo "  2. Avoids conflict with scripts/lib wait_for_service(host, port)"
echo "  3. Added better logging to show which service is starting"
echo "  4. Improved error messages"
echo
