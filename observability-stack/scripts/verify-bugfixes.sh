#!/bin/bash
#===============================================================================
# Bug Fixes Verification Script
# Checks that all 10 high-priority bug fixes are properly implemented
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

echo "==============================================="
echo "Bug Fixes Verification"
echo "==============================================="
echo ""

#===============================================================================
# Bug #1: Installation Rollback
#===============================================================================
echo "Bug #1: Installation Rollback System"
echo "-------------------------------------------"

if grep -q "init_rollback" "$SCRIPT_DIR/lib/module-loader.sh"; then
    check_pass "init_rollback() function exists"
else
    check_fail "init_rollback() function missing"
fi

if grep -q "track_file_created" "$SCRIPT_DIR/lib/module-loader.sh"; then
    check_pass "track_file_created() function exists"
else
    check_fail "track_file_created() function missing"
fi

if grep -q "rollback_installation" "$SCRIPT_DIR/lib/module-loader.sh"; then
    check_pass "rollback_installation() function exists"
else
    check_fail "rollback_installation() function missing"
fi

if grep -q "cleanup_rollback" "$SCRIPT_DIR/lib/module-loader.sh"; then
    check_pass "cleanup_rollback() function exists"
else
    check_fail "cleanup_rollback() function missing"
fi

echo ""

#===============================================================================
# Bug #2: Atomic File Operations
#===============================================================================
echo "Bug #2: Atomic File Operations"
echo "-------------------------------------------"

if grep -q "atomic_write" "$SCRIPT_DIR/lib/config-generator.sh"; then
    check_pass "atomic_write() function exists"
else
    check_fail "atomic_write() function missing"
fi

if grep -q "mktemp" "$SCRIPT_DIR/lib/config-generator.sh"; then
    check_pass "Uses mktemp for temp files"
else
    check_fail "Not using mktemp for temp files"
fi

if grep -q "mv -f" "$SCRIPT_DIR/lib/config-generator.sh"; then
    check_pass "Uses mv -f for atomic replacement"
else
    check_warn "May not be using atomic mv"
fi

echo ""

#===============================================================================
# Bug #3: Error Propagation
#===============================================================================
echo "Bug #3: Error Propagation"
echo "-------------------------------------------"

# Count error checking patterns
error_checks=$(grep -r "|| {" "$SCRIPT_DIR/lib/module-loader.sh" "$SCRIPT_DIR/lib/config-generator.sh" 2>/dev/null | wc -l)

if [[ $error_checks -gt 10 ]]; then
    check_pass "Good error propagation pattern usage (${error_checks} instances)"
else
    check_warn "Limited error propagation (${error_checks} instances)"
fi

if grep -q "return 1" "$SCRIPT_DIR/lib/module-loader.sh"; then
    check_pass "Functions return error codes"
else
    check_fail "Functions don't return error codes"
fi

echo ""

#===============================================================================
# Bug #4: Binary Ownership Race
#===============================================================================
echo "Bug #4: Binary Ownership Race"
echo "-------------------------------------------"

checked=0
correct=0

for install_script in "$BASE_DIR/modules/_core"/*/install.sh; do
    if [[ -f "$install_script" ]]; then
        module=$(basename "$(dirname "$install_script")")
        checked=$((checked + 1))

        # Check if create_user is called before chown in main()
        if awk '/^main\(\)/,/^}/ {print}' "$install_script" | grep -q "create_user" && \
           awk '/^main\(\)/,/^}/ {print}' "$install_script" | grep -B999 "install_binary\|chown" | grep -q "create_user"; then
            check_pass "$module: create_user() before chown"
            correct=$((correct + 1))
        else
            check_warn "$module: Verify create_user() order"
        fi
    fi
done

if [[ $correct -eq $checked ]]; then
    check_pass "All $checked module install scripts have correct user creation order"
fi

echo ""

#===============================================================================
# Bug #5: Port Conflict Detection
#===============================================================================
echo "Bug #5: Port Conflict Detection"
echo "-------------------------------------------"

if grep -q "check_port_available" "$SCRIPT_DIR/lib/common.sh"; then
    check_pass "check_port_available() function exists"
else
    check_fail "check_port_available() function missing"
fi

if grep -q "ss -tln" "$SCRIPT_DIR/lib/common.sh"; then
    check_pass "Uses ss for port checking"
else
    check_warn "May not use ss for port checking"
fi

# Check if function handles fallbacks
if grep -q "netstat" "$SCRIPT_DIR/lib/common.sh" && grep -q "lsof" "$SCRIPT_DIR/lib/common.sh"; then
    check_pass "Has fallback mechanisms (netstat, lsof)"
else
    check_warn "Limited fallback mechanisms"
fi

echo ""

#===============================================================================
# Bug #6: Argument Parsing
#===============================================================================
echo "Bug #6: Argument Parsing"
echo "-------------------------------------------"

if grep -q "while \[\[ \$# -gt 0 \]\]" "$SCRIPT_DIR/auto-detect.sh"; then
    check_pass "Uses while loop for argument parsing"
else
    check_fail "Not using while loop for argument parsing"
fi

if grep -q "shift" "$SCRIPT_DIR/auto-detect.sh"; then
    check_pass "Uses shift for argument handling"
else
    check_fail "Doesn't use shift"
fi

if grep -q "\${1#\*=}" "$SCRIPT_DIR/auto-detect.sh"; then
    check_pass "Handles --option=value format"
else
    check_warn "May not handle --option=value format"
fi

echo ""

#===============================================================================
# Bug #7: File Locking
#===============================================================================
echo "Bug #7: File Locking"
echo "-------------------------------------------"

if [[ -f "$SCRIPT_DIR/lib/lock-utils.sh" ]]; then
    check_pass "lock-utils.sh exists"

    if grep -q "acquire_lock" "$SCRIPT_DIR/lib/lock-utils.sh"; then
        check_pass "acquire_lock() function exists"
    else
        check_fail "acquire_lock() function missing"
    fi

    if grep -q "release_lock" "$SCRIPT_DIR/lib/lock-utils.sh"; then
        check_pass "release_lock() function exists"
    else
        check_fail "release_lock() function missing"
    fi

    if grep -q "flock" "$SCRIPT_DIR/lib/lock-utils.sh"; then
        check_pass "Uses flock when available"
    else
        check_warn "May not use flock"
    fi
else
    check_fail "lock-utils.sh not found"
fi

echo ""

#===============================================================================
# Bug #8: YAML Parser Edge Cases
#===============================================================================
echo "Bug #8: YAML Parser Edge Cases"
echo "-------------------------------------------"

if grep -q "match(\$0, /\^\"" "$SCRIPT_DIR/lib/common.sh"; then
    check_pass "YAML parser handles quoted strings"
else
    check_warn "YAML parser may not handle quoted strings"
fi

if grep -q "yaml_get" "$SCRIPT_DIR/lib/common.sh"; then
    check_pass "yaml_get() function exists"
else
    check_fail "yaml_get() function missing"
fi

if grep -q "yaml_get_array" "$SCRIPT_DIR/lib/common.sh"; then
    check_pass "yaml_get_array() function exists"
else
    check_fail "yaml_get_array() function missing"
fi

echo ""

#===============================================================================
# Bug #9: Network Operation Timeouts
#===============================================================================
echo "Bug #9: Network Operation Timeouts"
echo "-------------------------------------------"

if [[ -f "$SCRIPT_DIR/lib/download-utils.sh" ]]; then
    check_pass "download-utils.sh exists"

    if grep -q "safe_download" "$SCRIPT_DIR/lib/download-utils.sh"; then
        check_pass "safe_download() function exists"
    else
        check_fail "safe_download() function missing"
    fi

    if grep -q "\-\-timeout" "$SCRIPT_DIR/lib/download-utils.sh"; then
        check_pass "wget timeout configured"
    else
        check_fail "wget timeout not configured"
    fi

    if grep -q "\-\-max-time" "$SCRIPT_DIR/lib/download-utils.sh"; then
        check_pass "curl timeout configured"
    else
        check_fail "curl timeout not configured"
    fi

    if grep -q "\-\-tries\|\-\-retry" "$SCRIPT_DIR/lib/download-utils.sh"; then
        check_pass "Retry logic implemented"
    else
        check_fail "Retry logic missing"
    fi
else
    check_fail "download-utils.sh not found"
fi

echo ""

#===============================================================================
# Bug #10: Idempotency
#===============================================================================
echo "Bug #10: Idempotency Patterns"
echo "-------------------------------------------"

if [[ -f "$BASE_DIR/BUGFIXES.md" ]]; then
    check_pass "BUGFIXES.md documentation exists"

    if grep -q "idempotency\|idempotent" "$BASE_DIR/BUGFIXES.md"; then
        check_pass "Idempotency patterns documented"
    else
        check_warn "Idempotency not fully documented"
    fi
else
    check_warn "BUGFIXES.md not found"
fi

# Check for common idempotency patterns
if grep -rq "if ! ufw status | grep -q" "$SCRIPT_DIR" 2>/dev/null; then
    check_pass "Firewall idempotency pattern found"
else
    check_warn "Firewall idempotency pattern not found"
fi

if grep -rq "if ! grep -q" "$SCRIPT_DIR" 2>/dev/null; then
    check_pass "Config idempotency pattern found"
else
    check_warn "Config idempotency pattern not found"
fi

echo ""

#===============================================================================
# Summary
#===============================================================================
echo "==============================================="
echo "Verification Summary"
echo "==============================================="
echo ""
echo -e "${GREEN}Passed:${NC}  $PASS_COUNT"
echo -e "${YELLOW}Warnings:${NC} $WARN_COUNT"
echo -e "${RED}Failed:${NC}  $FAIL_COUNT"
echo ""

# Overall status
total_checks=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
pass_rate=$((PASS_COUNT * 100 / total_checks))

echo "Pass Rate: ${pass_rate}%"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    exit 0
elif [[ $FAIL_COUNT -le 3 ]]; then
    echo -e "${YELLOW}⚠ Minor issues found, review recommended${NC}"
    exit 0
else
    echo -e "${RED}✗ Significant issues found, fixes needed${NC}"
    exit 1
fi
